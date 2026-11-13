extends Node3D
## The biology classroom's two impossible things (docs/ART_BIBLE.md, location studies).
##
## **The curtained window.** The front window stays ordinary - the yard, the low wall,
## the washing on the line. The back window has a curtain drawn over it. Drawing it aside
## (once the class has been let go) shows no outside at all: the wall's own thickness, and
## after it nothing. The protagonist leans out, falls, and lands in the yard.
##
## **The rear door.** A second door in the outside wall, at the back of the room. Opened,
## it shows only plaster behind it - and at the front of the room a staircase is suddenly
## there, coming down out of the ceiling and stopping in mid-air in front of the teacher's
## desk. What it is for is left open; it is not walkable.
##
## Both are staged moments (`StagedInteractable`): the director runs the handlers below
## inside a beat. The room's state lives in story flags, so a room loaded later - a
## return through the corridor, a save - is built in the state it was left in, and every
## animation here also has an instant form used for exactly that.
##
## Nothing here collides. The curtain, the door and the staircase are decoration as far as
## physics and navigation are concerned (`classroom_visual_slice_test.gd` keeps the room's
## solids a closed list), so neither one can change where the player can walk.

## Where the fall lands. The playground's `FromSchool` marker was authored for "the school
## side of the yard" and nothing used it until now (docs/MAP_PLAN.md).
const FALL_SCENE := "res://scenes/locations/playground/playground.tscn"
const FALL_SPAWN := &"FromSchool"
const FALL_DESTINATION := &"playground"
const CURTAIN_ROUTE := &"classroom_curtain"
const VOID_CONVERSATION := &"classroom_curtain_void"
const LANDING_CONVERSATION := &"classroom_fall_landing"
const STAIR_CONVERSATION := &"classroom_rear_door"
const REAR_DOOR_OPEN_INSPECTION := &"classroom_rear_door_open"
const CURTAIN_DRAWN_PROMPT := "prompt.curtain_drawn"
const CURTAIN_RETRY_PROMPT := "prompt.curtain_retry"
const REAR_DOOR_OPEN_PROMPT := "prompt.rear_door_open"
## A floor point that frames the player at the rear door and the whole staircase at once
## from the game camera's fixed angle (measured with its offset and field of view).
const STAIR_FRAME_POINT := Vector3(0.0, 0.0, 0.0)
const STAIR_FRAME_SECONDS := 1.4
const STAIR_RELEASE_SECONDS := 1.1
## The fall: a lean over the sill, then the drop, which keeps going while the screen goes
## black. The drop must end before the fade does (the flow stands the body back up once
## the next room is loaded).
const LEAN_SECONDS := 0.75
const LEAN_DEGREES := 38.0
const DROP_SECONDS := 0.45
const DROP_DEGREES := 85.0
const DROP_DEPTH := 2.4
const LEAN_RISE := 0.3
const LEAN_REACH := 0.3
const LEAN_REACH_MAX := 1.1
const LEAN_SILL_GAP := 0.45
const DROP_CLEARANCE := 0.6
const FALL_FADE_SECONDS := 0.7
const FALL_ROLL_DEGREES := -9.0

@export var curtain_path: NodePath = ^"BackCurtain"
@export var void_path: NodePath = ^"VoidOpening"
@export var door_path: NodePath = ^"../WallSouthLeft/RearDoor"
@export var stair_path: NodePath = ^"Staircase"
@export var curtain_interactable_path: NodePath = ^"../Interactables/CurtainDraw"
@export var door_interactable_path: NodePath = ^"../Interactables/RearDoorTry"
## The real window behind the curtain - its glass, the painted view and the mullion - which
## the void replaces. The frame stays: the hole is still a window-shaped hole.
@export var window_paths: PackedStringArray = [
	"../WindowGlass1", "../WindowGlow1", "../WindowMullion1"
]

var _curtain: WindowCurtain = null
var _void: MeshInstance3D = null
var _door: SwingDoor = null
var _stair: SuspendedStair = null
var _curtain_interactable: StagedInteractable = null
var _door_interactable: StagedInteractable = null


func _ready() -> void:
	_curtain = get_node_or_null(curtain_path) as WindowCurtain
	_void = get_node_or_null(void_path) as MeshInstance3D
	_door = get_node_or_null(door_path) as SwingDoor
	_stair = get_node_or_null(stair_path) as SuspendedStair
	_curtain_interactable = get_node_or_null(curtain_interactable_path) as StagedInteractable
	_door_interactable = get_node_or_null(door_interactable_path) as StagedInteractable
	for pair: Array in [
		[_curtain, curtain_path], [_void, void_path], [_door, door_path],
		[_stair, stair_path], [_curtain_interactable, curtain_interactable_path],
		[_door_interactable, door_interactable_path],
	]:
		if pair[0] == null:
			push_error("ClassroomAnomalies: '%s' is missing or of the wrong type." % pair[1])
	if _curtain_interactable != null:
		_curtain_interactable.stage_handler = _stage_curtain
	if _door_interactable != null:
		_door_interactable.stage_handler = _stage_rear_door
	_apply_story_state()


## Builds the room as the story left it, with no animation.
func _apply_story_state() -> void:
	if _flag(StoryFlags.CURTAIN_DRAWN):
		_show_void(true)
		if _curtain != null:
			_curtain.open(false)
		_set_prompt(_curtain_interactable, CURTAIN_DRAWN_PROMPT)
	else:
		_show_void(false)
		_set_prompt(
			_curtain_interactable,
			CURTAIN_RETRY_PROMPT if _flag(StoryFlags.CURTAIN_FALL_PENDING) else "prompt.curtain"
		)
	if _flag(StoryFlags.REAR_DOOR_OPENED):
		if _door != null:
			_door.open(false)
		if _stair != null:
			_stair.reveal(false)
		_set_prompt(_door_interactable, REAR_DOOR_OPEN_PROMPT)


## True once the back window shows the void instead of glass and a view.
func is_void_open() -> bool:
	return _void != null and _void.visible


# --- The curtain --------------------------------------------------------------------


func _stage_curtain(director: Node) -> Dictionary:
	var conversation := ConversationRouter.select(CURTAIN_ROUTE, _snapshot())
	if String(conversation).is_empty():
		push_error("ClassroomAnomalies: no conversation matched '%s'." % CURTAIN_ROUTE)
		return {}
	await director.play_conversation(conversation)
	if not _flag(StoryFlags.CURTAIN_FALL_PENDING) or _flag(StoryFlags.CURTAIN_DRAWN):
		return {}
	await draw_curtain()
	await get_tree().create_timer(0.9, false).timeout  # story time: stops under the pause menu
	await director.play_conversation(VOID_CONVERSATION)
	var player: PlayerController = director.get_player() if director.has_method("get_player") \
		else null
	var departure := Callable()
	if player != null:
		departure = _fall.bind(player)
	return {
		"transition": {
			"scene": FALL_SCENE,
			"spawn": FALL_SPAWN,
			"id": FALL_DESTINATION,
			"label": "the back-window curtain",
			"departure": departure,
			"fade_out": FALL_FADE_SECONDS,
			"arrival_conversation": LANDING_CONVERSATION,
			# Commit the drawn state only after the yard has actually loaded. A refused
			# transition leaves the pending flag intact and the room retryable.
			"arrival_flags": {
				StoryFlags.CURTAIN_FALL_PENDING: false,
				StoryFlags.CURTAIN_DRAWN: true,
			},
			"on_failure": Callable(self, "reset_curtain_after_failed_transition"),
		}
	}


## Draws the back curtain aside on the void. Public for the anomaly test; idempotent.
func draw_curtain(animated: bool = true) -> void:
	if _curtain == null:
		return
	# The void goes in while the cloth still covers the whole window, so it is the
	# curtain moving that uncovers it.
	_show_void(true)
	_set_prompt(_curtain_interactable, CURTAIN_RETRY_PROMPT)
	await _curtain.open(animated)


## A refused fall returns to the same room. Put the cloth and window back as they were;
## curtain_fall_pending remains true so the player can try the same choice again.
func reset_curtain_after_failed_transition() -> void:
	if _curtain != null:
		_curtain.set_open_amount(0.0)
	_show_void(false)
	_set_prompt(_curtain_interactable, CURTAIN_RETRY_PROMPT)


func _show_void(open: bool) -> void:
	if _void != null:
		_void.visible = open
	for path in window_paths:
		var node := get_node_or_null(NodePath(path)) as Node3D
		if node != null:
			node.visible = not open


## The lean over the sill and the start of the drop. Plays while the classroom still
## exists; returns once the body has tipped over, and the drop runs on into the fade.
## The tween belongs to the player, so freeing the room does not cut it short.
func _fall(player: PlayerController) -> void:
	if player == null or player.visual == null:
		return
	var window := _void.global_position if _void != null else player.global_position
	var toward := window - player.global_position
	toward.y = 0.0
	if toward.length() > 0.05:
		# Face the sill, and keep facing it: the controller's facing lerp aims there too.
		player.face_toward(toward)
	var visual := player.visual
	var rest := visual.position
	# The player may be standing anywhere the prompt reached from; the body reaches the
	# sill however far that is, and the drop always clears the far face of the wall.
	var distance := toward.length()
	var lean_reach := clampf(distance - LEAN_SILL_GAP, LEAN_REACH, LEAN_REACH_MAX)
	var drop_reach := distance + DROP_CLEARANCE
	var lean := player.create_tween()
	lean.set_parallel(true)
	lean.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	lean.tween_property(visual, "rotation_degrees:x", LEAN_DEGREES, LEAN_SECONDS)
	# Forward (the pivot's +Z, which faces the window now) and up onto the sill.
	lean.tween_property(visual, "position", rest + Vector3(0.0, LEAN_RISE, lean_reach), LEAN_SECONDS)
	await lean.finished
	# Over the sill and down behind the wall: the wall hides the body before the black does.
	var drop := player.create_tween()
	drop.set_parallel(true)
	drop.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drop.tween_property(visual, "rotation_degrees:x", DROP_DEGREES, DROP_SECONDS)
	drop.tween_property(
		visual, "position", rest + Vector3(0.0, -DROP_DEPTH, drop_reach), DROP_SECONDS
	)
	drop.tween_method(player.set_camera_roll, 0.0, FALL_ROLL_DEGREES, DROP_SECONDS)


# --- The rear door ------------------------------------------------------------------


func _stage_rear_door(director: Node) -> Dictionary:
	if _flag(StoryFlags.REAR_DOOR_OPENED):
		return {"inspection": REAR_DOOR_OPEN_INSPECTION}
	if not _flag(StoryFlags.CLASS_DISMISSED):
		return {"inspection": _door_interactable.inspection_id if _door_interactable else &""}
	var player: PlayerController = director.get_player() if director.has_method("get_player") \
		else null
	var rig: CameraRig = player.camera_rig if player != null else null
	await open_rear_door()
	if rig != null:
		await rig.frame_point(STAIR_FRAME_POINT, STAIR_FRAME_SECONDS)
	if _stair != null:
		await _stair.reveal()
	await get_tree().create_timer(0.8, false).timeout  # story time
	await director.play_conversation(STAIR_CONVERSATION)
	if rig != null:
		await rig.release_frame(STAIR_RELEASE_SECONDS)
	return {}


## Opens the rear door. The staircase is revealed by the beat (so the camera can be on it
## first) or by `_apply_story_state` on a later load. Public for the anomaly test.
func open_rear_door(animated: bool = true) -> void:
	_set_state_flag(StoryFlags.REAR_DOOR_OPENED)
	_set_prompt(_door_interactable, REAR_DOOR_OPEN_PROMPT)
	if _door != null:
		await _door.open(animated)


# --- Plumbing -----------------------------------------------------------------------


func _set_prompt(interactable: Interactable, key: String) -> void:
	if interactable != null:
		interactable.set_prompt(key)


func _game_state() -> Node:
	return get_node_or_null(^"/root/GameState")


func _snapshot() -> Dictionary:
	var state := _game_state()
	return state.get_snapshot() if state != null else {}


func _flag(flag: StringName) -> bool:
	var state := _game_state()
	return state != null and bool(state.get_flag(flag, false))


func _set_state_flag(flag: StringName) -> void:
	var state := _game_state()
	if state != null:
		state.set_flag(flag, true)

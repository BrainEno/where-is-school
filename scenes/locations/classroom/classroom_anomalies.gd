class_name ClassroomAnomalies
extends Node3D
## The biology classroom's impossible thing (docs/ART_BIBLE.md, location studies).
##
## **The curtained window.** The front window stays ordinary - the yard, the low wall,
## the washing on the line. The back window is a large opening hidden behind a
## floor-to-ceiling blackout curtain (issue #159). Drawing it aside (once the class has
## been let go) shows no outside at all: the wall is cut away from the floor to its top -
## no sill, no header, no glass, no view - and in the cut there is only the blank sheet of
## the biology-classroom experiment (`VoidOpening/BlankSheet`, unlit paper: nothing in it
## can be lit). Round the cut the room itself turns into a pencil drawing on an answer
## sheet (`PaperZone`), a few metres and no more: the rest of the room keeps its
## materials. The protagonist leans out, falls, and lands in the yard.
##
## The curtain is a staged moment (`StagedInteractable`): the director runs the handler
## below inside a beat. The room's state lives in story flags, so a room loaded later - a
## return through the corridor, a save - is built in the state it was left in, and every
## animation here also has an instant form used for exactly that.
##
## **The rear door** (the white door at the back of the east wall) is not staged any more.
## It never opens: its interactable is an ordinary inspection ("this door never opens,
## unless special means are used"). The staircase that used to appear when it opened is
## kept out of this room for now (issue #159; `suspended_stair.tscn` stays in the project
## for a later scene), and `StoryFlags.REAR_DOOR_OPENED` is neither read nor written -
## an older save that carries it loads with the door shut.
##
## Nothing here collides. The curtain is decoration as far as physics and navigation are
## concerned (`classroom_visual_slice_test.gd` keeps the room's solids a closed list), so
## it cannot change where the player can walk.

## Where the fall lands. The playground's `FromSchool` marker was authored for "the school
## side of the yard" and nothing used it until now (docs/MAP_PLAN.md).
const FALL_SCENE := "res://scenes/locations/playground/playground.tscn"
const FALL_SPAWN := &"FromSchool"
const FALL_DESTINATION := &"playground"
const CURTAIN_ROUTE := &"classroom_curtain"
const VOID_CONVERSATION := &"classroom_curtain_void"
const LANDING_CONVERSATION := &"classroom_fall_landing"
const CURTAIN_DRAWN_PROMPT := "prompt.curtain_drawn"
const CURTAIN_RETRY_PROMPT := "prompt.curtain_retry"
## The fall: a lean over the sill, then the drop, which keeps going while the screen goes
## black. The drop must end before the fade does (the flow stands the body back up once
## the next room is loaded).
const LEAN_SECONDS := 0.75
const LEAN_DEGREES := 32.0
const DROP_SECONDS := 0.55
const DROP_DEGREES := 85.0
const DROP_DEPTH := 3.6
const DROP_ROLL_DEGREES := -20.0
## The cut has no sill since the art migration (the wall is open to the floor): the lean
## no longer climbs onto one.
const LEAN_RISE := 0.0
const LEAN_REACH := 0.3
const LEAN_REACH_MAX := 1.1
const LEAN_SILL_GAP := 0.45
const DROP_CLEARANCE := 0.6
const FALL_FADE_SECONDS := 0.8
const FALL_ROLL_DEGREES := -16.0

@export var curtain_path: NodePath = ^"BackCurtain"
## The middle of the hole through the wall: where the fall leans toward.
@export var void_path: NodePath = ^"VoidOpening"
@export var curtain_interactable_path: NodePath = ^"../Interactables/CurtainDraw"
## The local paper anomaly round the cut (optional: a room without one still works).
@export var paper_path: NodePath = ^"PaperZone"

var _curtain: WindowCurtain = null
var _void: Node3D = null
var _curtain_interactable: StagedInteractable = null
var _paper: PaperZone = null


func _ready() -> void:
	_curtain = get_node_or_null(curtain_path) as WindowCurtain
	_void = get_node_or_null(void_path) as Node3D
	_curtain_interactable = get_node_or_null(curtain_interactable_path) as StagedInteractable
	_paper = get_node_or_null(paper_path) as PaperZone
	for pair: Array in [
		[_curtain, curtain_path], [_void, void_path],
		[_curtain_interactable, curtain_interactable_path],
	]:
		if pair[0] == null:
			push_error("ClassroomAnomalies: '%s' is missing or of the wrong type." % pair[1])
	if _curtain_interactable != null:
		_curtain_interactable.stage_handler = _stage_curtain
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


## True once the void behind the back window is uncovered (the curtain is being drawn
## or is drawn). `VoidOpening` is shown with it; the hole itself is always there.
func is_void_open() -> bool:
	return _void != null and _void.visible


# --- The curtain --------------------------------------------------------------------


func _stage_curtain(director: Node) -> Dictionary:
	var conversation := ConversationRouter.select(CURTAIN_ROUTE, _snapshot())
	if String(conversation).is_empty():
		push_error("ClassroomAnomalies: no conversation matched '%s'." % CURTAIN_ROUTE)
		return {}
	# After a refused fall `curtain_fall_pending` is still true, and the conversation asks
	# again. Only this conversation's answer may start the fall: the flag is set aside for
	# its length (inside the beat, where nothing can save), "Draw it aside" writes it
	# again, and "Leave it drawn" gets the failed attempt's state back exactly.
	var retrying := _flag(StoryFlags.CURTAIN_FALL_PENDING) and not _flag(StoryFlags.CURTAIN_DRAWN)
	if retrying:
		_set_flag_value(StoryFlags.CURTAIN_FALL_PENDING, false)
	await director.play_conversation(conversation)
	if retrying and not _flag(StoryFlags.CURTAIN_FALL_PENDING):
		_set_flag_value(StoryFlags.CURTAIN_FALL_PENDING, true)
		return {}
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
			# transition leaves the pending flag intact and the room retryable, and
			# LocationFlow calls `on_failure` once, behind the black, before the room is
			# shown again.
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
	# Marked open while the cloth still covers the whole opening, so it is the curtain
	# moving that uncovers it.
	_show_void(true, animated)
	_set_prompt(_curtain_interactable, CURTAIN_RETRY_PROMPT)
	await _curtain.open(animated)


## A refused fall returns to the same room. Put the cloth back as it was;
## curtain_fall_pending remains true so the player can try the same choice again.
## `LocationFlow.transition_to()` calls this as the fall's `on_failure`, once, while the
## screen is still black and the beat is held; the body and camera are already upright.
## Idempotent, and it writes no flags.
func reset_curtain_after_failed_transition() -> void:
	if _curtain != null:
		_curtain.set_open_amount(0.0)
	_show_void(false)
	_set_prompt(_curtain_interactable, CURTAIN_RETRY_PROMPT)
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		cam.fov = 60.0


func _show_void(open: bool, animated: bool = false) -> void:
	if _void != null:
		_void.visible = open
	if _paper != null:
		_paper.set_drawn(open, animated)


## The local paper anomaly round the cut, or null.
func get_paper_zone() -> PaperZone:
	return _paper


## The lean over the edge of the cut and the dreamlike drop into the void.
## Features dynamic camera close-up framing, vertigo dolly-zoom, aesthetic speed lines
## and vignette matching the curtain's expressionist art style.
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

	# 1. Close-up Camera Framing: frame closer to the window sill, capturing the cloth and void
	if player.camera_rig != null:
		player.camera_rig.frame_point(window + Vector3(0.0, 0.35, 0.0), LEAN_SECONDS)

	# 2. Camera Vertigo Dolly Zoom: widen FOV to simulate sudden depth/vertigo
	var cam: Camera3D = player.get_viewport().get_camera_3d() if player.get_viewport() != null else null
	var original_fov := cam.fov if cam != null else 60.0
	if cam != null:
		var fov_tween := player.create_tween()
		fov_tween.tween_property(cam, "fov", 76.0, LEAN_SECONDS).set_trans(Tween.TRANS_SINE)

	# 3. Protagonist steps and leans forward onto the sill, looking down into the sheer drop
	var lean := player.create_tween()
	lean.set_parallel(true)
	lean.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	lean.tween_property(visual, "rotation_degrees:x", LEAN_DEGREES, LEAN_SECONDS)
	# Forward (the pivot's +Z, which faces the window now), over the edge of the floor.
	lean.tween_property(visual, "position", rest + Vector3(0.0, LEAN_RISE, lean_reach), LEAN_SECONDS)
	await lean.finished

	# Hesitation moment: 0.15s pause as protagonist looks down into the 2nd-floor abyss
	await get_tree().create_timer(0.15, false).timeout

	# 4. Dreamlike curtain-style fall effect overlay
	var overlay := DreamFallOverlay.new()
	get_tree().root.add_child(overlay)

	# 5. Over the sill and down behind the wall: tumbling plunge with dynamic pitch and bank
	var drop := player.create_tween()
	drop.set_parallel(true)
	drop.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drop.tween_property(visual, "rotation_degrees:x", DROP_DEGREES, DROP_SECONDS)
	drop.tween_property(visual, "rotation_degrees:z", DROP_ROLL_DEGREES, DROP_SECONDS)
	drop.tween_property(
		visual, "position", rest + Vector3(0.0, -DROP_DEPTH, drop_reach), DROP_SECONDS
	)
	drop.tween_method(player.set_camera_roll, 0.0, FALL_ROLL_DEGREES, DROP_SECONDS)
	if cam != null:
		drop.tween_property(cam, "fov", 82.0, DROP_SECONDS)
	drop.tween_property(overlay, "progress", 1.0, DROP_SECONDS)

	await drop.finished

	if cam != null:
		cam.fov = original_fov
	if is_instance_valid(overlay):
		overlay.queue_free()


## Dreamlike falling overlay that matches the curtain's expressionist art style.
## Renders a radial ultramarine-ochre wash, vertical ink/sketch speed lines,
## and drifting paper fragments tumbling upward during the void drop.
class DreamFallOverlay extends CanvasLayer:
	var progress: float = 0.0:
		set(value):
			progress = clampf(value, 0.0, 1.0)
			if _drawer != null:
				_drawer.queue_redraw()

	var _drawer: Control = null
	var _streaks: Array[Dictionary] = []
	var _scraps: Array[Dictionary] = []

	func _init() -> void:
		layer = 20
		_generate_elements()

	func _ready() -> void:
		_drawer = Control.new()
		_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drawer.draw.connect(_on_draw)
		add_child(_drawer)

	func _generate_elements() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 42819
		for _i in range(26):
			_streaks.append({
				"x_ratio": rng.randf_range(0.02, 0.98),
				"width": rng.randf_range(1.5, 3.2),
				"length_ratio": rng.randf_range(0.18, 0.48),
				"speed": rng.randf_range(1.2, 2.6),
				"alpha": rng.randf_range(0.35, 0.8),
				"is_blue": rng.randf() > 0.35,
			})
		for _i in range(8):
			_scraps.append({
				"x_ratio": rng.randf_range(0.1, 0.9),
				"y_start": rng.randf_range(0.5, 1.2),
				"size": Vector2(rng.randf_range(10.0, 22.0), rng.randf_range(14.0, 28.0)),
				"speed": rng.randf_range(0.8, 1.5),
				"rot_speed": rng.randf_range(-3.0, 3.0),
				"angle": rng.randf_range(0.0, TAU),
			})

	func _on_draw() -> void:
		if _drawer == null or progress <= 0.001:
			return
		var size := _drawer.get_size()
		if size.x <= 1.0 or size.y <= 1.0:
			return

		# 1. Curtain palette vignette: deep ultramarine and ochre edge wash
		var blue_col := Color(0.11, 0.15, 0.36, 0.55 * progress)
		var corner_h := size.y * 0.35
		_drawer.draw_rect(Rect2(0, 0, size.x, corner_h), blue_col)
		_drawer.draw_rect(Rect2(0, size.y - corner_h, size.x, corner_h), blue_col)

		# 2. Vertical ink/sketch speed streaks rushing upward (matching PaperZone aesthetic)
		var streak_color_blue := Color(0.18, 0.24, 0.52, 0.65 * progress)
		var streak_color_ink := Color(0.06, 0.07, 0.12, 0.75 * progress)

		for s: Dictionary in _streaks:
			var x: float = float(s["x_ratio"]) * size.x
			var spd: float = float(s["speed"])
			var y_phase: float = fmod(progress * spd * 2.2, 1.0)
			var y_top: float = (1.0 - y_phase) * size.y
			var len_px: float = float(s["length_ratio"]) * size.y * (1.0 + progress * 0.4)
			var col: Color = streak_color_blue if bool(s["is_blue"]) else streak_color_ink
			col.a *= float(s["alpha"])
			_drawer.draw_line(
				Vector2(x, y_top),
				Vector2(x, y_top + len_px),
				col,
				float(s["width"])
			)

		# 3. Floating paper fragments drifting upward from the void
		var paper_col := Color(0.92, 0.90, 0.85, 0.8 * progress)
		var paper_line := Color(0.2, 0.22, 0.32, 0.55 * progress)
		for sc: Dictionary in _scraps:
			var sx: float = float(sc["x_ratio"]) * size.x + sin(progress * 4.0 + float(sc["angle"])) * 25.0
			var sy: float = (float(sc["y_start"]) - progress * float(sc["speed"])) * size.y
			var rot: float = float(sc["angle"]) + progress * float(sc["rot_speed"])
			var sc_size: Vector2 = sc["size"]
			var xform := Transform2D(rot, Vector2(sx, sy))
			var rect := Rect2(-sc_size * 0.5, sc_size)
			_drawer.draw_set_transform_matrix(xform)
			_drawer.draw_rect(rect, paper_col, true)
			_drawer.draw_rect(rect, paper_line, false, 1.0)
			_drawer.draw_set_transform_matrix(Transform2D.IDENTITY)


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
	_set_flag_value(flag, true)


func _set_flag_value(flag: StringName, value: bool) -> void:
	var state := _game_state()
	if state != null:
		state.set_flag(flag, value)

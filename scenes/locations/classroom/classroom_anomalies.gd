class_name ClassroomAnomalies
extends Node3D
## Owns the back curtain and the route through the cut in the west wall. The darkness
## is the room's world background, not a surface, and the temporary stop that keeps a
## closed curtain from being walked through is taken out of physics when it opens.
##
## Also owns the rear door. It is locked and says so (`classroom_rear_door`), except for
## a player who told Q they would borrow a book next door (`borrow_from_next_class`):
## until the lesson is over, that player gets one visible orientation check at it. A
## success leaves through the door into the corridor before the lesson - skipping class,
## so the bell and the substitute never happen (`skipped_class`, `PrologueSteps`) - and
## the door stays passable for them afterwards. A failure, or any later try, is the
## locked door's own line. The check's line is that same authored line; nothing is added.

const Motion = preload("res://scripts/actors/staged_actor_motion.gd")
const Landing = preload("res://scenes/locations/playground/container_landing.gd")
const FALL_SCENE := "res://scenes/locations/playground/playground.tscn"
const FALL_SPAWN := Landing.SPAWN
const FALL_DESTINATION := &"playground"
const CURTAIN_ROUTE := &"classroom_curtain"
const VOID_CONVERSATION := &"classroom_curtain_void"
const LANDING_CONVERSATION := &"classroom_fall_landing"
const BALANCE_CHECK := &"cv_balance_check"
const CURTAIN_DRAWN_PROMPT := "prompt.curtain_drawn"
const CURTAIN_RETRY_PROMPT := "prompt.curtain_retry"
const CURTAIN_STEP_PROMPT := "prompt.curtain_step"
const REAR_DOOR_CONVERSATION := &"classroom_rear_door_borrow"
const REAR_DOOR_CHECK := &"rdb_check"
const REAR_DOOR_INSPECTION := &"classroom_rear_door"
const CORRIDOR_SCENE := "res://scenes/locations/corridor/corridor.tscn"
const CORRIDOR_SPAWN := &"FromClassroomRear"
const CORRIDOR_DESTINATION := &"corridor"

@export var curtain_path: NodePath = ^"BackCurtain"
@export var void_path: NodePath = ^"VoidOpening"
@export var curtain_interactable_path: NodePath = ^"../Interactables/CurtainDraw"
@export var rear_door_interactable_path: NodePath = ^"../Interactables/RearDoorTry"

@onready var _curtain := get_node(curtain_path) as WindowCurtain
@onready var _void := get_node(void_path) as Node3D
@onready var _approach: Marker3D = $VoidApproach
@onready var _curtain_interactable := get_node(curtain_interactable_path) as StagedInteractable
@onready var _rear_door_interactable := get_node(rear_door_interactable_path) as StagedInteractable
@onready var _closed_stop: CollisionShape3D = $"../WallWest/ClosedCurtainStop"
@onready var _step_trigger: Area3D = $"../VoidStep"


func _ready() -> void:
	_curtain_interactable.stage_handler = _stage_curtain
	_rear_door_interactable.stage_handler = _stage_rear_door
	_step_trigger.body_entered.connect(_on_step)
	_apply_story_state()


func _apply_story_state() -> void:
	var opened := _flag(StoryFlags.CURTAIN_DRAWN)
	_set_cut_open(opened)
	_curtain.set_open_amount(1.0 if opened else 0.0)
	_update_prompt()


func is_void_open() -> bool:
	return _void.visible


func _update_prompt() -> void:
	var prompt := "prompt.curtain"
	if _flag(StoryFlags.CURTAIN_DRAWN):
		prompt = CURTAIN_STEP_PROMPT if _flag(StoryFlags.CURTAIN_EDGE_HELD) else CURTAIN_DRAWN_PROMPT
	elif _flag(StoryFlags.CURTAIN_FALL_PENDING):
		prompt = CURTAIN_RETRY_PROMPT
	_curtain_interactable.set_prompt(prompt)


## Walking physically over the far side of the lip is also a deliberate exit. This
## trigger starts the same staged transition as the interaction; it isn't a solid.
func _on_step(body: Node3D) -> void:
	var player := body as PlayerController
	if player != null:
		_step_off.call_deferred(player)


func _step_off(player: PlayerController) -> void:
	if not is_instance_valid(player) or not player.is_control_enabled() \
		or not _flag(StoryFlags.CURTAIN_DRAWN):
		return
	var interaction := player.get_node_or_null(^"InteractionController") as InteractionController
	if interaction != null:
		interaction.request_activation(_curtain_interactable)


func _stage_curtain(director: Node) -> Dictionary:
	var player: PlayerController = director.get_player()
	var started_at := player.global_position
	var facing := player.get_facing_direction()
	var physics := player.is_physics_processing()
	if _flag(StoryFlags.CURTAIN_DRAWN) and started_at.x < _void.global_position.x - 0.10:
		return _fall_request(player, false, _approach.global_position, Vector3.LEFT, true)

	var state := _state()
	var conversation := ConversationRouter.select(CURTAIN_ROUTE, state.get_snapshot())
	var already_open := _flag(StoryFlags.CURTAIN_DRAWN)
	# These two conversations use this flag for a choice. Set it aside during the
	# conversation so "leave it" never falls, even on a refused forced fall's retry.
	var pending := _flag(StoryFlags.CURTAIN_FALL_PENDING)
	if pending:
		state.set_flag(StoryFlags.CURTAIN_FALL_PENDING, false)
	await director.play_conversation(conversation)
	if not _flag(StoryFlags.CURTAIN_FALL_PENDING):
		if pending:
			state.set_flag(StoryFlags.CURTAIN_FALL_PENDING, true)
		return {}

	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	var mark := _approach.global_position
	var reach := mark if already_open else mark + Vector3.RIGHT * 0.38
	if not await Motion.walk_to(player, reach):
		player.set_physics_process(physics)
		state.set_flag(StoryFlags.CURTAIN_FALL_PENDING, pending)
		return {}
	await Motion.turn_to(player, Vector3.LEFT)
	if already_open:
		# The recorded success is not rolled again. A refused optional drop goes back
		# to the open edge, not to a closed curtain or a new roll.
		state.set_flag(StoryFlags.CURTAIN_FALL_PENDING, false)
		player.set_physics_process(physics)
		return _fall_request(player, false, started_at, facing, true)

	var rig := player.camera_rig
	if rig != null:
		rig.frame_point(mark + Vector3(0.1, 0, 0.05), 0.48)
	# Reach the cloth before it moves. The last beat is the step into the cleared cut.
	await Motion.act(player, "curtain_reach", 0.38, Callable())
	draw_curtain()
	await Motion.act(player, "curtain_draw", _curtain.open_seconds, Callable())
	Motion.reset_pose(player)
	var rear_boot: Motion.Limb = Motion.contacts(player).get("foot.R")
	var rear_sole := mark + Vector3(0.18, 0.0, 0.12)
	await Motion.act(player, "void_lean", 0.84, func(t: float) -> void:
		player.global_position = reach.lerp(mark, smoothstep(0.05, 0.72, t))
		_set_hip(player, -0.064 * sin(t * PI / 2.0), 0.13 * t)
		if rear_boot != null:
			rear_boot.plant(rear_sole, Vector3.LEFT, smoothstep(0.0, 0.48, t))
	)
	await director.play_conversation(VOID_CONVERSATION)
	var check: Variant = state.get_flag(StoryFlags.check_record_flag(VOID_CONVERSATION, BALANCE_CHECK), null)
	if check is Dictionary and check.get("success", false) == true:
		# Catch the weight on the rear foot, then take a step back, clear of the lip.
		await Motion.act(player, "void_recover", 0.70, func(t: float) -> void:
			player.global_position = mark + Vector3.RIGHT * 0.36 * smoothstep(0.16, 0.9, t)
			_set_hip(player, -0.064 * (1.0 - t), 0.13 * (1.0 - smoothstep(0.0, 0.54, t)))
			if rear_boot != null:
				rear_boot.plant(rear_sole, Vector3.LEFT, 1.0 - smoothstep(0.2, 0.74, t))
		)
		Motion.reset_pose(player)
		if rig != null:
			await rig.release_frame(0.32)
		state.set_flag(StoryFlags.CURTAIN_FALL_PENDING, false)
		state.set_flag(StoryFlags.CURTAIN_EDGE_HELD, true)
		state.set_flag(StoryFlags.CURTAIN_DRAWN, true)
		_update_prompt()
		player.set_physics_process(physics)
		return {"checkpoint": "curtain:held_edge"}

	player.set_physics_process(physics)
	return _fall_request(player, true, started_at, facing, false)


## True while the rear door offers its one attempt: the player said they would borrow a
## book next door, the lesson is not over, and the attempt has not been made.
func can_try_rear_door() -> bool:
	return _flag(StoryFlags.BORROW_FROM_NEXT_CLASS) and not _flag(StoryFlags.CLASS_DISMISSED) \
		and _rear_door_record().is_empty()


func _stage_rear_door(director: Node) -> Dictionary:
	if _rear_door_record().get("success", false) == true:
		return _rear_door_exit()
	if not can_try_rear_door():
		return {"inspection": REAR_DOOR_INSPECTION}
	await director.play_conversation(REAR_DOOR_CONVERSATION)
	if _rear_door_record().get("success", false) == true:
		return _rear_door_exit()
	return {}


## The recorded result of the rear-door check, or an empty Dictionary before it.
func _rear_door_record() -> Dictionary:
	var state := _state()
	if state == null:
		return {}
	var record: Variant = state.get_flag(
		StoryFlags.check_record_flag(REAR_DOOR_CONVERSATION, REAR_DOOR_CHECK), null
	)
	if record is Dictionary:
		return record as Dictionary
	return {}


func _rear_door_exit() -> Dictionary:
	return {
		"transition": {
			"scene": CORRIDOR_SCENE,
			"spawn": CORRIDOR_SPAWN,
			"id": CORRIDOR_DESTINATION,
			"label": "the classroom's rear door",
			"arrival_flags": {StoryFlags.SKIPPED_CLASS: true},
		}
	}


func _fall_request(
	player: PlayerController, hurt: bool, recover_at: Vector3, facing: Vector3, was_open: bool
) -> Dictionary:
	var host := get_parent().get_parent() as LocationHost
	return {
		"transition": {
			"scene": FALL_SCENE,
			"spawn": FALL_SPAWN,
			"id": FALL_DESTINATION,
			"label": "the back-window curtain",
			"departure": _drop.bind(player, hurt),
			"fade_out": 0.32,
			"arrival": Landing.present.bind(hurt, host),
			"arrival_conversation": LANDING_CONVERSATION,
			"arrival_flags": {
				StoryFlags.CURTAIN_FALL_PENDING: false,
				StoryFlags.CURTAIN_DRAWN: true,
				StoryFlags.CURTAIN_EDGE_HELD: false,
				StoryFlags.CURTAIN_LANDING_INJURED: hurt,
			},
			"on_failure": reset_curtain_after_failed_transition.bind(player, recover_at, facing, was_open),
		}
	}


func draw_curtain(animated: bool = true) -> void:
	_set_cut_open(true)
	await _curtain.open(animated)
	_curtain_interactable.rebuild_pick_shapes()


## Runs once behind black, after a refused transition. The check record is kept but
## injury/arrival were never committed. Restore the body's start and the prior opening.
func reset_curtain_after_failed_transition(
	player: PlayerController = null, recover_at: Vector3 = Vector3.ZERO,
	facing: Vector3 = Vector3.LEFT, was_open: bool = false
) -> void:
	if player != null:
		player.teleport(Transform3D(Basis.IDENTITY, recover_at))
		player.face_toward(facing)
		Motion.reset_pose(player)
	_set_cut_open(was_open)
	_curtain.set_open_amount(1.0 if was_open else 0.0)
	_curtain_interactable.rebuild_pick_shapes()
	_update_prompt()


func _set_cut_open(opened: bool) -> void:
	_void.visible = opened
	_closed_stop.set_deferred(&"disabled", opened)
	_step_trigger.set_deferred(&"monitoring", opened)


## Feet cross the real floor edge before descending. A prepared step compresses and
## pushes; the slip tries to plant the back foot, then pitches out with arms searching.
## The only cut is between the empty drop and the continuation above the roof.
func _drop(player: PlayerController, hurt: bool) -> void:
	var physics := player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	await Motion.turn_to(player, Vector3.LEFT)
	if player.camera_rig != null:
		player.camera_rig.frame_point(_approach.global_position + Vector3.LEFT * 0.24, 0.20)
	var start := player.global_position
	var end_x := -8.26
	var brace := 0.13 if hurt else 0.23
	var clip := "void_slip" if hurt else "void_step"
	await Motion.act(player, clip, 0.73 if hurt else 0.77, func(t: float) -> void:
		var travel := smoothstep(brace * 0.5, 0.76, t)
		var drop := clampf((t - 0.34) / 0.66, 0.0, 1.0)
		var hip := 0.13 * (1.0 - t) if hurt else -0.12 * sin(smoothstep(0.0, 0.54, t) * PI)
		_set_hip(player, -0.064 * (1.0 - t) if hurt else hip, 0.08 * travel + maxf(0.0, hip))
		player.global_position = Vector3(lerpf(start.x, end_x, travel), start.y - 2.8 * drop * drop, start.z)
		player.set_camera_roll(-4.0 * drop if hurt else 0.0)
	)
	player.set_physics_process(physics)


func _set_hip(player: PlayerController, lift: float, forward: float) -> void:
	if player.visual != null:
		player.visual.position = Vector3(0.0, PlayerController.STANDING_HIP_HEIGHT + lift, forward)


func _state() -> Node:
	return get_node_or_null(^"/root/GameState")


func _flag(flag: StringName) -> bool:
	var state := _state()
	return state != null and state.get_flag(flag, false) == true

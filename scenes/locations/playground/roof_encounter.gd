extends Node3D
## The container encounter belongs to this yard instance. The landing choreography
## cues it at roof contact; neither walking past the container nor loading a save
## replays the noise or starts a beat. No new saved state or dialogue text.

const Figure = preload("res://scenes/environment/characters/roof_collector_pose.gd")
const DOOR_SHOT := preload("res://assets/camera/shots/container_resident.tres")
const ROOF_SPAWN := &"FromSchool"

enum Phase { ASLEEP, WAKING, WALKING_OUT, OUTSIDE }
var phase: Phase = Phase.ASLEEP
var _print_tween: Tween

@onready var _collector: NpcActor = $Collector
@onready var _figure := _collector.get_visual() as Figure
@onready var _bed: Marker3D = $Bed
@onready var _route: Node3D = $ExitRoute
@onready var _doorstep: Marker3D = $ExitRoute/Doorstep
@onready var _frame: Marker3D = $WakeFrame
@onready var _print: ColorRect = $WorldPrint/Sheet
@onready var _ink := _print.material as ShaderMaterial


func _ready() -> void:
	prepare_drop()
	var yard := get_parent() as LocationRoot
	var host := yard.get_parent() as LocationHost if yard != null else null
	if host != null:
		host.location_entered.connect(_on_entered)


func _on_entered(location: LocationRoot, spawn_id: StringName) -> void:
	if location != get_parent():
		return
	var state := get_node_or_null(^"/root/GameState")
	var outcome: Variant = state.get_flag(StoryFlags.CURTAIN_LANDING_INJURED, null) if state != null else null
	# The existing flag is *absent* before either landing; false is a braced drop,
	# not a player who simply came through the gate. Save restores flags before the
	# location. The entrance marker still describes the visit after moving off the roof.
	if outcome is bool:
		_stand_in_doorway()
		_set_print(1.0 if outcome and spawn_id == ROOF_SPAWN else 0.0)


## A live arrival is different from reconstructing a visit. Called still behind black.
func prepare_drop() -> void:
	if _print_tween != null and _print_tween.is_running():
		_print_tween.kill()
	_set_print(0.0)
	phase = Phase.ASLEEP
	_collector.place_at(_bed.global_position, _bed.global_position + global_basis.x)
	_figure.sleep_on_bedding()


func roof_contact(hurt: bool) -> void:
	if phase != Phase.ASLEEP:
		return
	phase = Phase.WAKING
	_figure.stir()
	if hurt:
		_print_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_print_tween.tween_method(_set_print, 0.0, 1.0, 0.31)


## The roof contact has its own shot. Then frame the open end long enough to
## see the resident sit up, find his footing and walk down the threshold.
func come_out(rig: CameraRig) -> void:
	if phase != Phase.WAKING:
		return
	if rig != null:
		rig.focus_on(_frame, DOOR_SHOT)
		await rig.frame_point(_frame.global_position, 0.32)
	var shift := await _figure.rise()
	_collector.position += _collector.basis * shift
	_figure.start_walking()
	phase = Phase.WALKING_OUT
	var points: Array[Vector3] = []
	for mark: Marker3D in _route.get_children():
		points.append(mark.global_position)
	await _collector.walk_along(points)
	_figure.stand()
	var entry_yaw := _collector.rotation.y
	_collector.face_towards(global_position)
	var turn_yaw := entry_yaw + angle_difference(entry_yaw, _collector.rotation.y)
	_collector.rotation.y = entry_yaw
	var turn := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	turn.tween_property(_collector, "rotation:y", turn_yaw, 0.34)
	turn.tween_method(_figure.raise_gaze, 0.0, 1.0, 0.34)
	await turn.finished
	phase = Phase.OUTSIDE
	await get_tree().create_timer(0.42, false).timeout


func _stand_in_doorway() -> void:
	_collector.place_at(_doorstep.global_position, global_position)
	_figure.stand(true)
	phase = Phase.OUTSIDE


func _set_print(impression: float) -> void:
	_ink.set_shader_parameter(&"impression", impression)
	_print.visible = impression > 0.0

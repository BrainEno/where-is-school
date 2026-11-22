extends Node3D
## The container encounter belongs to this yard instance. The landing choreography
## cues it at roof contact; neither walking past the container nor loading a save
## replays the noise or starts a beat.
##
## Woken, he comes out, turns back to the container's front - where the noise came from - and
## looks round for it, at eye level: he never looks up at the roof, and never finds the
## protagonist lying on it. He keeps looking round while he stands in his doorway.
##
## Getting off the roof (`RoofWayDown`) is the rest of it: a protagonist seen on the ladder,
## or heard landing, is told to stop (`confront()`); one who dropped unheard off the closed
## rear is looked for (`search()`) - round the open end, along the south side and under the
## ladder, to a look along the rear half of that side - and then the resident goes back into
## his cabin. The protagonist hides by moving, crouched; one he holds in plain sight for
## `FOUND_SECONDS` while he searches is found, and the search ends there.

const Figure = preload("res://scenes/environment/characters/roof_collector_pose.gd")
const DOOR_SHOT := preload("res://assets/camera/shots/container_resident.tres")
const ROOF_SPAWN := &"FromSchool"
## Where he looks when he has come out: the container's open end, at eye level (local).
const FRONT_LOOK := Vector3(3.0, 1.3, -0.2)
## How far his head turns each way while he looks round, the first time and then idly.
const LOOK_REACH := 55.0
const IDLE_REACH := 35.0
## Searching, he finds a protagonist he holds in a clear line from his eyes, in front of him
## (the cosine of the half-angle he sees), within range, for this many story seconds.
const SIGHT_RANGE := 9.0
const SIGHT_COS := 0.35
const FOUND_SECONDS := 1.5
const EYE_HEIGHT := 1.55
## The part of a crouched protagonist he has to see.
const QUARRY_HEIGHT := 0.6

enum Phase { ASLEEP, WAKING, WALKING_OUT, OUTSIDE, SEARCHING, INSIDE }
var phase: Phase = Phase.ASLEEP
var _print_tween: Tween
var _idle_look: Tween
## Searching: whom he is looking for, how long he has held them in sight, whether he has.
var _quarry: Node3D = null
var _seen_for := 0.0
var _spotted := false

@onready var _collector: NpcActor = $Collector
@onready var _figure := _collector.get_visual() as Figure
@onready var _bed: Marker3D = $Bed
@onready var _route: Node3D = $ExitRoute
@onready var _doorstep: Marker3D = $ExitRoute/Doorstep
@onready var _search: Node3D = $SearchRoute
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
	_stop_looking()
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
	# Back towards the front of the container, level: the noise came from there.
	await _turn_towards(to_global(FRONT_LOOK), 0.6)
	await get_tree().create_timer(0.3, false).timeout
	await _look_around()
	phase = Phase.OUTSIDE
	_keep_looking()
	await get_tree().create_timer(0.42, false).timeout


## Seen or heard: he stands where he is and keeps the protagonist in view for the
## lines that follow (and after them, while the protagonist is in the yard).
func confront(player: Node3D) -> void:
	if phase == Phase.ASLEEP or phase == Phase.WAKING:
		return
	_stop_looking()
	_figure.stand()
	_collector.watch(player)


## The drop went unheard. He comes out round the open end, along the south side, waits
## under the ladder looking up at the roof, goes on to look along the rear half of that side
## and comes back the same way, stops on the doorstep facing the north leaf and goes back
## into the cabin. Each mark of `SearchRoute` carries its pause (`pause`, `pause_back`,
## story seconds) and where he looks (`look`, local). Waits are story time, so a paused game
## stops him. Meanwhile `quarry` - the hiding protagonist, free to move - is found if they
## stay in his sight (`sees()`) for `FOUND_SECONDS`: he stops where he is and the search
## ends. Returns whether he found them; then he is outside again, for `confront()`.
func search(director: Node, quarry: Node3D = null) -> bool:
	if phase != Phase.OUTSIDE:
		return false
	_stop_looking()
	phase = Phase.SEARCHING
	_quarry = quarry
	_seen_for = 0.0
	_spotted = false
	_collector.stop_watching()
	var marks: Array[Marker3D] = []
	for mark: Marker3D in _search.get_children():
		marks.append(mark)
	var legs: Array = []
	for mark in marks:
		legs.append([mark, float(mark.get_meta(&"pause", 0.0))])
	for index in range(marks.size() - 2, -1, -1):
		legs.append([marks[index], float(marks[index].get_meta(&"pause_back", 0.0))])
	legs.append([_doorstep, float(_doorstep.get_meta(&"pause_back", 0.0))])
	for leg: Array in legs:
		await _search_leg(director, leg[0] as Marker3D, float(leg[1]))
		if _spotted:
			_quarry = null
			_figure.stand()
			phase = Phase.OUTSIDE
			return true
	_quarry = null
	var inside: Array[Vector3] = []
	var route := _route.get_children()
	for index in range(route.size() - 2, -1, -1):
		inside.append((route[index] as Marker3D).global_position)
	_figure.start_walking()
	await _collector.walk_along(inside)
	_figure.stand()
	await _turn_towards(_bed.global_position, 0.4)
	phase = Phase.INSIDE
	return false


## A clear line from his eyes to `target`'s crouched body, in front of him and in range.
func sees(target: Node3D) -> bool:
	var eye := _collector.global_position + Vector3.UP * EYE_HEIGHT
	var body := target.global_position + Vector3.UP * QUARRY_HEIGHT
	var toward := body - eye
	toward.y = 0.0
	if toward.length() > SIGHT_RANGE or toward.length() < 0.01:
		return false
	if _collector.get_facing_direction().dot(toward.normalized()) < SIGHT_COS:
		return false
	var exclude: Array[RID] = []
	var solid := target as CollisionObject3D
	if solid != null:
		exclude.append(solid.get_rid())
	var query := PhysicsRayQueryParameters3D.create(eye, body, 0xFFFFFFFF, exclude)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _physics_process(delta: float) -> void:
	if phase != Phase.SEARCHING or _spotted or _quarry == null or not is_instance_valid(_quarry):
		return
	_seen_for = _seen_for + delta if sees(_quarry) else 0.0
	_spotted = _seen_for >= FOUND_SECONDS


func _search_leg(director: Node, mark: Marker3D, pause: float) -> void:
	_figure.start_walking()
	await _walk_to(mark.global_position)
	_figure.stand()
	if pause <= 0.0 or _spotted:
		return
	var look: Variant = mark.get_meta(&"look", null)
	if look is Vector3:
		var point := to_global(look as Vector3)
		await _turn_towards(point, 0.45)
		_figure.raise_gaze(clampf((point.y - 1.2) / 1.4, 0.0, 1.0))
	var left := pause
	while left > 0.0 and not _spotted:
		var slice := minf(left, 0.25)
		await director.wait_seconds(slice)
		left -= slice
	_figure.raise_gaze(0.0)


## `NpcActor.walk_along()` for one leg, but stopping where he is the moment he finds the
## protagonist. Pausable like the tween it replaces.
func _walk_to(point: Vector3) -> void:
	_collector.face_towards(point)
	while not _spotted:
		if can_process():
			var to := point - _collector.global_position
			var step := _collector.walk_speed * get_process_delta_time()
			if to.length() <= step:
				_collector.global_position = point
				return
			_collector.global_position += to.normalized() * step
		await get_tree().process_frame


## Head one way, the other way, back to the front: what woke him is not there.
func _look_around() -> void:
	var look := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	look.tween_method(_figure.turn_head, 0.0, LOOK_REACH, 0.5)
	look.tween_interval(0.45)
	look.tween_method(_figure.turn_head, LOOK_REACH, -LOOK_REACH, 0.85)
	look.tween_interval(0.45)
	look.tween_method(_figure.turn_head, -LOOK_REACH, 0.0, 0.45)
	await look.finished


## Standing in his doorway he goes on looking round, slowly, until something else moves him.
func _keep_looking() -> void:
	_stop_looking()
	_idle_look = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_look.tween_interval(1.6)
	_idle_look.tween_method(_figure.turn_head, 0.0, IDLE_REACH, 1.2)
	_idle_look.tween_interval(1.2)
	_idle_look.tween_method(_figure.turn_head, IDLE_REACH, -IDLE_REACH, 1.8)
	_idle_look.tween_interval(1.2)
	_idle_look.tween_method(_figure.turn_head, -IDLE_REACH, 0.0, 1.0)


func _stop_looking() -> void:
	if _idle_look != null and _idle_look.is_valid():
		_idle_look.kill()
	_idle_look = null
	_figure.turn_head(0.0)


func _turn_towards(point: Vector3, seconds: float) -> void:
	var start_yaw := _collector.rotation.y
	_collector.face_towards(point)
	var end_yaw := start_yaw + angle_difference(start_yaw, _collector.rotation.y)
	_collector.rotation.y = start_yaw
	var turn := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	turn.tween_property(_collector, "rotation:y", end_yaw, seconds)
	await turn.finished


func _stand_in_doorway() -> void:
	_collector.stop_watching()
	_collector.place_at(_doorstep.global_position, to_global(FRONT_LOOK))
	_figure.stand()
	phase = Phase.OUTSIDE
	_keep_looking()


func _set_print(impression: float) -> void:
	_ink.set_shader_parameter(&"impression", impression)
	_print.visible = impression > 0.0

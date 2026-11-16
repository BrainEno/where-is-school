extends Node3D
## Q in the experiment: a person in the room, not a camera-side companion.
##
## What this does, and pointedly does not do:
##
## * Q is somewhere. He stands in the aisle by his desk, turns to keep the protagonist in
##   view, and when he goes anywhere he **walks**, along the aisles, at a walking pace.
##   He never appears anywhere: no teleport, not to the fall's landing, not to the door.
## * Q does not follow. When the protagonist goes out of the front door, Q gets up and
##   comes as far as the doorway, and stops on the classroom's side of it
##   (`THRESHOLD_LIMIT_X`): he can be seen from the corridor, standing there. When the
##   protagonist comes back in, Q goes back to his place.
## * When the curtain is drawn, Q walks over to the window side and looks; when the
##   protagonist falls, Q stays at the window. He is still there when you climb back up.
## * When the bell has gone, Q sits down at his own desk.
##
## The places are a closed list, every route goes through Q's home in the aisle, and a
## new request waits until the walk in progress ends (`_queued`): Q never turns round in
## the middle of the floor because the player changed their mind.
##
## Room left for later (none of it implemented here, all of it possible without undoing
## anything): `Policy.INVITED` (Q comes along when asked), `Policy.REFUSES` (asked to go
## back, he does not), a chase. The policy is a property; only `STAYS_INSIDE` exists now.

enum Place { HOME, WINDOW, THRESHOLD, SEAT }
enum Policy { STAYS_INSIDE, INVITED, REFUSES }

const Room := preload("res://scenes/dev/visual_experiments/biology_classroom/room.gd")
const Q_SCENE := preload("res://scenes/environment/characters/q.tscn")

const WALK_SPEED: float = 1.45
const TURN_RATE: float = 6.0
## Q never stands further east than this: the classroom side of the front door.
const THRESHOLD_LIMIT_X: float = 6.45
const HOME := Vector3(-3.2, 0.0, 2.7)
const WINDOW := Vector3(-5.9, 0.0, 0.85)
## Beside the doorway, not in it: the way back in stays clear.
const THRESHOLD := Vector3(5.9, 0.0, -2.7)
## Legs from HOME to each place (HOME itself excluded); the way back is the reverse.
const LEGS := {
	Place.WINDOW: [Vector3(-3.2, 0.0, 0.85), WINDOW],
	Place.THRESHOLD: [Vector3(-3.2, 0.0, -1.25), Vector3(5.9, 0.0, -1.25), THRESHOLD],
	Place.SEAT: [Vector3(-3.2, 0.0, 2.25), Vector3(-4.8, 0.0, 2.25)],
}

var policy: Policy = Policy.STAYS_INSIDE
## Where Q is, or is walking to.
var place: Place = Place.HOME
## What Q looks at when he is standing still (usually the protagonist).
var look_target: Vector3 = Vector3.ZERO
var has_look_target: bool = false
## Metres walked (the test checks that every change of place is walked, not jumped).
var distance_walked: float = 0.0
## The largest distance covered in one frame.
var largest_step: float = 0.0

var _actor: Node3D = null
var _body: AnimatableBody3D = null
var _route: Array[Vector3] = []
var _queued: int = -1
var _seated: bool = false


func _ready() -> void:
	_actor = Q_SCENE.instantiate() as Node3D
	_actor.name = "Q"
	add_child(_actor)
	_body = AnimatableBody3D.new()
	_body.name = "Body"
	_body.sync_to_physics = false
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.6
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.8, 0.0)
	_body.add_child(shape)
	add_child(_body)
	position = HOME


func actor() -> Node3D:
	return _actor


func is_walking() -> bool:
	return not _route.is_empty()


func is_seated() -> bool:
	return _seated


## Sends Q to a place, on foot. Ignored if he is already there or on his way; queued if
## he is walking somewhere else.
func go(target: Place) -> void:
	if is_walking():
		if target != place:
			_queued = target
		else:
			_queued = -1
		return
	if target == place:
		return
	_start_route(target)


func _start_route(target: Place) -> void:
	_route.clear()
	if place != Place.HOME:
		var back: Array = LEGS[place]
		for index in range(back.size() - 2, -1, -1):
			_route.append(back[index] as Vector3)
		_route.append(HOME)
	if target != Place.HOME:
		for point: Vector3 in LEGS[target]:
			_route.append(point)
	if _seated:
		_set_seated(false)
	place = target


## Puts Q at a place without walking. Only for setting up a capture or a reset at load,
## never during play.
func set_place_instant(target: Place) -> void:
	_route.clear()
	_queued = -1
	place = target
	var points: Array = LEGS.get(target, [HOME])
	position = points[points.size() - 1] as Vector3
	_set_seated(target == Place.SEAT)
	if target == Place.SEAT:
		rotation.y = PI
	_report(Vector3.ZERO)


func _physics_process(delta: float) -> void:
	if not _route.is_empty():
		var goal: Vector3 = _route[0]
		var to_goal := goal - position
		to_goal.y = 0.0
		var step := WALK_SPEED * delta
		var moved: Vector3
		if to_goal.length() <= step:
			moved = to_goal
			_route.remove_at(0)
		else:
			moved = to_goal.normalized() * step
		var before := position
		position += moved
		position.x = minf(position.x, THRESHOLD_LIMIT_X)
		var covered := before.distance_to(position)
		distance_walked += covered
		largest_step = maxf(largest_step, covered)
		if moved.length() > 0.0001:
			_turn_toward(moved, delta)
		_report(moved / maxf(delta, 0.0001))
		if _route.is_empty():
			_arrive()
	else:
		_report(Vector3.ZERO)
		if not _seated:
			_face_place(delta)
	_body.global_transform = Transform3D(Basis.IDENTITY, global_position)


func _arrive() -> void:
	_report(Vector3.ZERO)
	if place == Place.SEAT:
		rotation.y = PI
		_set_seated(true)
	if _queued >= 0:
		var next: int = _queued
		_queued = -1
		go(next as Place)


func _face_place(delta: float) -> void:
	var toward := Vector3.ZERO
	if has_look_target:
		toward = look_target - global_position
	if place == Place.WINDOW:
		toward = Room.opening_centre() - global_position
	elif place == Place.THRESHOLD and has_look_target and look_target.x > Room.ROOM_MAX.x:
		toward = look_target - global_position
	toward.y = 0.0
	if toward.length() > 0.05:
		_turn_toward(toward, delta)


func _turn_toward(direction: Vector3, delta: float) -> void:
	var angle := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, angle, clampf(TURN_RATE * delta, 0.0, 1.0))


func _set_seated(seated: bool) -> void:
	_seated = seated
	if _actor != null and _actor.has_method("set_seated"):
		_actor.call("set_seated", seated)


func _report(velocity: Vector3) -> void:
	if _actor != null and _actor.has_method("report_velocity"):
		_actor.call("report_velocity", velocity)

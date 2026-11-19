extends Node3D
## A chair that is pushed back out of the way, once, and stays there until someone sits.
##
## The protagonist wakes up sitting in this chair, which is the problem: the body starts
## inside the seat, and there is nowhere to stand. The gap between the desk's front and the
## chair's seat is 9.7 cm - nobody stands up in 9.7 cm - so the chair has to move before the
## body can rise, which is also what a person does. They push the chair back with a hand and
## stand up in the room that makes.
##
## Pushing it back is the whole of the interaction: the chair slides along its own
## forward/back axis and stops. `push_back` is idempotent - a second call does nothing -
## because the position it ends at is a fact about the room afterwards, not a state of the
## animation. Sitting down slides it home again, so the two cannot disagree about where the
## chair is.
##
## ## The collision body, and the one rule it has
##
## The chair is a real obstacle: once the protagonist has stood up and let go of it, walking
## into it stops him. But while he is *sitting* in it, the body is inside the seat - that is
## what sitting is - and a solid chair would either trap him forever or shove him out of the
## room. So the collision only turns on when the chair is pushed back and nobody is in it:
## the state where a chair is something you walk around rather than something you sit in.
##
## The interaction area is not this node's: it lives with the room's other interactables
## (`Interactables/ChairSit`), on its own collision layer so the player body never notices it.
## Because it is anchored in the room rather than under the chair, whatever owns it has to call
## `rebuild_pick_shapes()` once this chair has moved - the pointer boxes are measured from the
## meshes, and the meshes are now somewhere else.

## How far the chair slides back from where the classroom places it.
##
## The capsule is 0.35 m in radius and the seat's front edge sits at z 1.670, so a body at
## the spawn needs the *chair* to move rather than the body: 0.63 m is where the capsule
## stops touching the seat, and 0.65 m leaves 2 cm. That is deliberately tight - the chair
## is a thing in a room, and watching it retreat across the floor was the wrong picture.
## `tools/check_seat_clearance.py` measures it rather than trusting this comment.
const PUSH_BACK_DISTANCE := 0.65

## Where the chair slides to, in its parent's space.
var _pushed_position := Vector3.ZERO
var _home_position := Vector3.ZERO
var _pushed := false
var _slide: Tween = null

## The solid body, and the layer it uses so it blocks the player's movement but is not
## itself an interactable (the pointer's area is the separate node below).
@onready var _body: StaticBody3D = get_node_or_null(^"Solid")


func _ready() -> void:
	_home_position = position
	_pushed_position = position + Vector3(0.0, 0.0, PUSH_BACK_DISTANCE)
	# The opening has the protagonist asleep in this chair, so it starts open: see the note
	# on the class about sitting being an overlap.
	_set_solid(false)


## True once the chair has been pushed back out of the seat's way.
func is_pushed_back() -> bool:
	return _pushed


## Where the chair is when it is under the body, and where it is when it is out of the way.
func get_home_position() -> Vector3:
	return _home_position


func get_pushed_position() -> Vector3:
	return _pushed_position


## Where a hand goes to push or draw this chair: the top of its back, in world space.
##
## Read from the back mesh rather than computed from the chair's origin, because the meshes
## are the chair and the origin is an authoring convenience. Falls back to a plausible point on
## the back if the prop has no back mesh under it.
func get_back_point() -> Vector3:
	var back := get_node_or_null(^"Back") as Node3D
	if back == null:
		return global_position + global_basis.z * 0.2 + Vector3.UP * 0.66
	# A little above the back's own centre, on the face nearest the body: that is where a hand
	# lands on a chair you are about to sit in or have just got out of.
	return back.global_position + Vector3.UP * 0.12 + global_basis.z * -0.03


## How far the back of the seat still is from where it started, for a hand that is pushing it.
func push_progress() -> float:
	var full := _pushed_position.distance_to(_home_position)
	if full <= 0.0001:
		return 1.0
	var travelled := position.distance_to(_home_position)
	return clampf(travelled / full, 0.0, 1.0)


## Slides the chair back over `duration`. Returns the tween so a caller can wait for it, or
## null when the chair is already there.
func push_back(duration: float) -> Tween:
	if _pushed:
		return null
	_pushed = true
	# The body being out of it and it becoming solid are the same moment: a chair that turns
	# solid while the protagonist is still in the seat is a chair that traps him.
	_set_solid(true)
	return _slide_to(_pushed_position, duration)


## Slides the chair back to where the room put it, for a body about to sit down again.
func pull_home(duration: float) -> Tween:
	if not _pushed:
		return null
	_pushed = false
	# Open *before* it moves: the body is about to arrive inside it.
	_set_solid(false)
	return _slide_to(_home_position, duration)


## Jumps straight to the pushed position, for a scene that opens after the protagonist has
## already stood up (a resumed save opens on its feet, with the chair already out).
func snap_back() -> void:
	_pushed = true
	_kill_slide()
	position = _pushed_position
	_set_solid(true)


func snap_home() -> void:
	_pushed = false
	_kill_slide()
	position = _home_position
	_set_solid(false)


## How far the chair still has to travel, 0 when it is where it was asked to be.
func remaining() -> float:
	return position.distance_to(_pushed_position if _pushed else _home_position)


func _set_solid(solid: bool) -> void:
	if _body == null:
		return
	# A disabled body is skipped by the physics step entirely, which is what we want while
	# the protagonist is sitting in it: not "the player is allowed through", but "there is
	# nothing there to collide with".
	_body.process_mode = Node.PROCESS_MODE_INHERIT
	for shape in _body.get_children():
		var collider := shape as CollisionShape3D
		if collider != null:
			collider.set_deferred("disabled", not solid)
	_body.set_deferred("collision_layer", 1 if solid else 0)


func _slide_to(target: Vector3, duration: float) -> Tween:
	_kill_slide()
	if duration <= 0.0:
		position = target
		return null
	_slide = create_tween()
	# Ease out: a chair pushed by someone standing up leaves fast - the hand is unloading -
	# and stops without a bounce. A linear slide reads as a machine, not a chair.
	_slide.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_slide.tween_property(self, "position", target, duration)
	return _slide


func _kill_slide() -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_slide = null

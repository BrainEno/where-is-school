extends Node3D
## A chair that is pushed back out of the way, once, and stays there.
##
## The protagonist wakes up sitting in this chair, which is the problem: the body starts
## inside the seat, and there is nowhere to stand. The gap between the desk's front and the
## chair's seat is 9.7 cm - nobody stands up in 9.7 cm - so the chair has to move before the
## body can rise, which is also what a person does. They push the chair back with their legs
## and stand up in the room that makes.
##
## Pushing it back is the whole of the interaction: the chair slides along its own
## forward/back axis and stops. `push_back` is idempotent - a second call does nothing -
## because the position it ends at is a fact about the room afterwards, not a state of the
## animation. Re-sitting uses the same slide in reverse, so the two cannot disagree about
## where the chair is.
##
## The mesh has no collision shape (the classroom chair is authored as decoration, only the
## desk is a static body), so this node is free to move without a physics body to drag along.

## How far the chair slides back from where the classroom places it.
##
## The capsule is 0.35 m in radius and the seat's front edge sits at z 1.670, so a body at
## the spawn needs the *chair* to move rather than the body: 0.63 m clears the seat, and
## 0.70 m leaves 0.07 m of slack for the twenty-four samples the clearance check takes.
## Measured from the chair's authored placement, not from the seat, so moving the desk in
## the room moves the whole arrangement.
const PUSH_BACK_DISTANCE := 0.70

## Where the chair slides to, in its parent's space.
var _pushed_position := Vector3.ZERO
var _home_position := Vector3.ZERO
var _pushed := false
var _slide: Tween = null


func _ready() -> void:
	_home_position = position
	_pushed_position = position + Vector3(0.0, 0.0, PUSH_BACK_DISTANCE)


## True once the chair has been pushed back out of the seat's way.
func is_pushed_back() -> bool:
	return _pushed


## Slides the chair back over `duration`. Returns the tween so a caller can wait for it, or
## null when the chair is already there.
func push_back(duration: float) -> Tween:
	if _pushed:
		return null
	_pushed = true
	return _slide_to(_pushed_position, duration)


## Slides the chair back to where the room put it, for a body about to sit down again.
func pull_home(duration: float) -> Tween:
	if not _pushed:
		return null
	_pushed = false
	return _slide_to(_home_position, duration)


## Jumps straight to the pushed position, for a scene that opens after the protagonist has
## already stood up (a resumed save opens on its feet, with the chair already out).
func snap_back() -> void:
	_pushed = true
	_kill_slide()
	position = _pushed_position


func snap_home() -> void:
	_pushed = false
	_kill_slide()
	position = _home_position


## How far the chair still has to travel, 0 when it is where it was asked to be.
func remaining() -> float:
	return position.distance_to(_pushed_position if _pushed else _home_position)


func _slide_to(target: Vector3, duration: float) -> Tween:
	_kill_slide()
	if duration <= 0.0:
		position = target
		return null
	_slide = create_tween()
	# Ease out: a chair pushed by someone standing up leaves fast - the legs are unloading -
	# and stops without a bounce. A linear slide reads as a machine, not a chair.
	_slide.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_slide.tween_property(self, "position", target, duration)
	return _slide


func _kill_slide() -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_slide = null

extends Camera3D
## The biology classroom's camera: a fixed set-up, like a camera on a stand. It does not
## follow the character, turn by itself, shake or zoom; its field of view never changes.
##
## It moves only when it is told to frame a new shot. Within one space that is a glide
## (smootherstep, so it starts and stops without a jolt); the experiment cuts, behind a
## short dip to dark, when the shot is in another space (through a door, down the
## stairs), so the camera never passes through a wall.
##
## Development only (scenes/dev/ is excluded from every export preset).

## Every shot uses this one lens.
const LENS_FOV: float = 60.0
const GLIDE_SECONDS: float = 1.6

## The shot being shown (or glided to); empty before the first.
var shot: StringName = &""
## Moves made: glides and cuts. The test reads it to show the camera only moves on a
## change of shot.
var moves: int = 0

var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _progress: float = 1.0
var _seconds: float = GLIDE_SECONDS


func _ready() -> void:
	fov = LENS_FOV
	current = true


## Frames `eye` looking at `look`. `instant` cuts; otherwise the camera glides there over
## `seconds`.
func frame(
	shot_name: StringName, eye: Vector3, look: Vector3, instant: bool,
	seconds: float = GLIDE_SECONDS
) -> void:
	var target := Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	shot = shot_name
	moves += 1
	if instant or seconds <= 0.0:
		_progress = 1.0
		_to = target
		global_transform = target
		return
	_from = global_transform
	_to = target
	_progress = 0.0
	_seconds = seconds


func is_gliding() -> bool:
	return _progress < 1.0


## Where the camera is going (or is): the shot's own transform.
func target_transform() -> Transform3D:
	return _to


## The yaw of the view, for reading the keys against it (0 = looking toward -Z).
func view_yaw() -> float:
	var back := _to.basis.z
	return atan2(back.x, back.z)


func _process(delta: float) -> void:
	fov = LENS_FOV
	if _progress >= 1.0:
		return
	_progress = minf(1.0, _progress + delta / _seconds)
	var t := _progress
	var eased := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	var turn := _from.basis.get_rotation_quaternion().slerp(
		_to.basis.get_rotation_quaternion(), eased
	)
	global_transform = Transform3D(Basis(turn), _from.origin.lerp(_to.origin, eased))

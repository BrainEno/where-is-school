class_name CameraShot
extends Resource
## How the game camera frames one important interaction (the prologue's camera focus).
##
## An `Interactable` that carries a shot (`Interactable.camera_shot`) pulls the camera to
## it during the interaction. An authored `camera_focus` effect can instead borrow a
## short close-up (`Interactable.dialogue_shot`) for the next line. The director decides
## when; `CameraRig` glides there and back. A regular shot describes where the camera ends up
## relative to the default framing, so it works from whichever side the player walked up:
##
## * **position**: the view centre moves `subject_mix` of the way from the player to the
##   look point (the interactable's position plus `look_offset`, on the player's floor);
##   the camera comes `distance_scale` of its usual distance (and `height_scale` of its
##   height) toward that centre;
## * **orientation**: the camera swings `yaw_degrees` round the view centre (it always
##   looks at the centre);
## * **lens**: `fov` degrees.
##
## Movement keys are read against the default framing, not the shot, so a swing never
## turns the controls under the player's hands.

## Added to the interactable's position (world axes, metres) to get what the view centres
## on. The height is ignored: the look point is on the player's floor, and the rig adds its
## usual eye height.
@export var look_offset: Vector3 = Vector3.ZERO
## 0 = the view stays on the player, 1 = it centres on the look point.
@export_range(0.0, 1.0, 0.01) var subject_mix: float = 0.55
## The camera's distance from the view centre, as a fraction of the default.
@export_range(0.4, 1.2, 0.01) var distance_scale: float = 0.8
## The camera's height above the view centre, as a fraction of the (scaled) default.
@export_range(0.5, 1.3, 0.01) var height_scale: float = 1.0
## Swing round the view centre, degrees (positive = counter-clockwise seen from above).
@export_range(-40.0, 40.0, 0.5) var yaw_degrees: float = 0.0
## The field of view while the shot holds.
@export_range(30.0, 90.0, 0.5) var fov: float = 52.0
## Seconds to reach the shot (about 95% of the way; critically damped, so no overshoot).
@export_range(0.2, 3.0, 0.05) var glide_seconds: float = 0.9
## Seconds to give the framing back.
@export_range(0.2, 3.0, 0.05) var release_seconds: float = 0.8

@export_group("Insert")
## Nonempty only for a subject-space close-up. Relative to the interactable, not the room.
## The wide framing fields above are not used by such an insert; the lens and glide are.
@export var insert_anchor_path: NodePath
## Aim in the anchor's rest space, in metres. Unlike look_offset this includes height.
@export var insert_aim: Vector3 = Vector3.ZERO
## Eye relative to the aim, in the anchor's axes. Keeps the angle even if a bone nods.
@export var insert_eye_offset: Vector3 = Vector3.ZERO
## Optional bone of an animated anchor; the aim then follows the live pose of that bone.
@export var insert_bone: StringName = &""
## Optional development nameplate to hide only while this dialogue insert is held.
@export var insert_nameplate_path: NodePath

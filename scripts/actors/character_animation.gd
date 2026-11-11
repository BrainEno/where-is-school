class_name CharacterAnimation
extends RefCounted
## Clips for the game's characters, built in code against *semantic* bone names.
##
## The two rigged characters in `scenes/dev/animation_retarget_test/` do not name their bones
## the same way, and neither does the production protagonist:
##
##   production protagonist   Root, Spine, Neck, Head, UpperArm.L, LowerArm.L, Thigh.L, …
##   rigged Q                 Root, Spine, Neck, Head, UpperArm.L, LowerArm.L, Thigh.L, …
##   retargeted protagonist   Root, Hips, Spine, Chest, UpperChest, LeftUpperArm, …
##
## and the animation library that was attempted first used a third convention
## (`root, pelvis, spine_01, upperarm_l, calf_l, …`). A clip authored against one set of names
## plays on exactly one of them. So the clips here are authored against canonical names —
## `hips`, `spine`, `upper_arm.L`, `shin.R` — and every rig resolves those against its own
## bone names at bind time. A bone a rig does not have is reported and its track is left out;
## nothing is silently dropped and nothing is played on a bone that is not there.
##
## The set is seven clips: four that loop a state (`idle`, `walk`, `jog`, `sit_idle`), two
## that are beats (`wave`, `talk`), and one transition (`get_up`) that is played once and
## hands back. What selects them is the character's own driver, not this file.
##
## Nothing here needs a third-party animation library, an external `.glb`, or a retarget pass
## in the editor: an `Animation` is a resource, its track paths are
## `"<skeleton path>:<bone name>"`, and its keys are quaternions relative to the rest pose.

## Bones the clips talk about, in the order the resolver prefers them. The first name that
## exists on a rig wins, so a rig that has both `Hips` and `Root` binds the hips to `Hips`.
const BONE_ALIASES := {
	"hips": ["Hips", "Pelvis", "Root", "root", "pelvis"],
	"spine": ["Spine", "Spine1", "spine_01", "spine"],
	"chest": ["UpperChest", "Chest", "Spine2", "spine_03", "spine_02"],
	"neck": ["Neck", "neck_01", "neck"],
	"head": ["Head", "head"],
	"shoulder.L": ["LeftShoulder", "Shoulder.L", "clavicle_l", "Shoulder_L"],
	"shoulder.R": ["RightShoulder", "Shoulder.R", "clavicle_r", "Shoulder_R"],
	"upper_arm.L": ["UpperArm.L", "LeftUpperArm", "LeftArm", "upperarm_l"],
	"upper_arm.R": ["UpperArm.R", "RightUpperArm", "RightArm", "upperarm_r"],
	"fore_arm.L": ["LowerArm.L", "LeftLowerArm", "LeftForeArm", "lowerarm_l", "forearm_l"],
	"fore_arm.R": ["LowerArm.R", "RightLowerArm", "RightForeArm", "lowerarm_r", "forearm_r"],
	"hand.L": ["Hand.L", "LeftHand", "hand_l"],
	"hand.R": ["Hand.R", "RightHand", "hand_r"],
	"thigh.L": ["Thigh.L", "LeftUpperLeg", "LeftUpLeg", "thigh_l", "upleg_l"],
	"thigh.R": ["Thigh.R", "RightUpperLeg", "RightUpLeg", "thigh_r", "upleg_r"],
	"shin.L": ["Shin.L", "LeftLowerLeg", "LeftLeg", "calf_l", "lowerleg_l"],
	"shin.R": ["Shin.R", "RightLowerLeg", "RightLeg", "calf_r", "lowerleg_r"],
	"foot.L": ["Foot.L", "LeftFoot", "foot_l"],
	"foot.R": ["Foot.R", "RightFoot", "foot_r"],
}

## What a positive X angle means, per canonical bone. `x_signs()` turns each of these into the
## ±1 that makes the rig's own local X axis do it; the clips never mention the sign.
const X_MEANING := {
	"hips": "forward",
	"spine": "forward",
	"chest": "forward",
	"neck": "forward",
	"head": "forward",
	"shoulder.L": "forward",
	"shoulder.R": "forward",
	"upper_arm.L": "forward",
	"upper_arm.R": "forward",
	"fore_arm.L": "close",
	"fore_arm.R": "close",
	"hand.L": "forward",
	"hand.R": "forward",
	"thigh.L": "forward",
	"thigh.R": "forward",
	"shin.L": "close",
	"shin.R": "close",
	"foot.L": "toes_down",
	"foot.R": "toes_down",
}

## The clips, authored in canonical names. Each key is `[time in seconds, degrees about the
## bone's own axes]`; the last key repeats the first so a looping clip closes the cycle.
##
## The X angle is authored in *meaning*, not in the rig's raw axis, because on every rig here
## the rig's local X points backwards: the limb bones point down their own local +Y and their
## local +X points to the character's right, so a positive rotation about it swings the limb
## towards the model's back (`X × (−Y) = −forward`, measured on all four rigs). An earlier
## version of this file believed the opposite and shipped a walk whose knee folded while the
## thigh was still forward — a character walking in a seated pose, hanging its shins under
## itself — and a `sit_idle` whose ankles ended up *above* its hips. A rotation turned the
## wrong way is the same number of degrees, so nothing that measured angles could see it.
##
## So `X_MEANING` says what a positive angle is supposed to do, and `x_signs()` measures the
## skeleton's rest pose at bind time to find the sign that makes it do that:
##
##   "forward"    the limb swings towards the front of the body — hips, spine, shoulders
##   "close"      the joint folds and its far end goes behind — knees and elbows
##   "toes_down"  the ankle points the toes down
##
## Everything else stays literal: Y twists about the bone, Z swings a limb out to the side,
## and the ±Z signs in the clips are mirrored between left and right. With that reading `walk`
## is a walk — the front leg is `thigh +18` with a nearly straight `shin +5`, the leg behind
## it carries the bent knee (`shin +44` as it swings through) — and a seated pose is
## `thigh +82, shin +84`: thighs forward, shins down, ankles under the knees.
##
## A clip may set `"loop": false`. Such a clip is a *transition*: it is played once and hands
## back to whatever was there before (see `CharacterView` / the wrapper's `play_action()`),
## and its last key is the rest pose rather than its first, because arriving is the point.
## `get_up` is the only one, and the test checks that its first key is the seated pose that
## `sit_idle` holds, so the two cannot drift apart.
const CLIPS := {
	"idle": {
		"length": 2.0,
		"tracks": {
			"spine": [[0.0, Vector3(-1.5, 0.0, 0.0)], [1.0, Vector3(1.5, 0.0, 0.0)], [2.0, Vector3(-1.5, 0.0, 0.0)]],
			"chest": [[0.0, Vector3(1.0, 0.0, 0.0)], [1.0, Vector3(-1.0, 0.0, 0.0)], [2.0, Vector3(1.0, 0.0, 0.0)]],
			"head": [[0.0, Vector3(0.0, 0.0, 1.0)], [1.0, Vector3(-1.5, 0.0, -1.0)], [2.0, Vector3(0.0, 0.0, 1.0)]],
			"upper_arm.L": [[0.0, Vector3(3.0, 0.0, 3.0)], [1.0, Vector3(5.0, 0.0, 4.0)], [2.0, Vector3(3.0, 0.0, 3.0)]],
			"upper_arm.R": [[0.0, Vector3(3.0, 0.0, -3.0)], [1.0, Vector3(5.0, 0.0, -4.0)], [2.0, Vector3(3.0, 0.0, -3.0)]],
			"fore_arm.L": [[0.0, Vector3(6.0, 0.0, 0.0)], [1.0, Vector3(8.0, 0.0, 0.0)], [2.0, Vector3(6.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(6.0, 0.0, 0.0)], [1.0, Vector3(8.0, 0.0, 0.0)], [2.0, Vector3(6.0, 0.0, 0.0)]],
		},
	},
	"walk": {
		"length": 1.0,
		"tracks": {
			"thigh.L": [[0.0, Vector3(18.0, 0.0, 0.0)], [0.25, Vector3(2.0, 0.0, 0.0)], [0.5, Vector3(-17.0, 0.0, 0.0)], [0.75, Vector3(2.0, 0.0, 0.0)], [1.0, Vector3(18.0, 0.0, 0.0)]],
			"shin.L": [[0.0, Vector3(5.0, 0.0, 0.0)], [0.25, Vector3(6.0, 0.0, 0.0)], [0.5, Vector3(14.0, 0.0, 0.0)], [0.75, Vector3(44.0, 0.0, 0.0)], [1.0, Vector3(5.0, 0.0, 0.0)]],
			"foot.L": [[0.0, Vector3(-7.0, 0.0, 0.0)], [0.25, Vector3(2.0, 0.0, 0.0)], [0.5, Vector3(12.0, 0.0, 0.0)], [0.75, Vector3(-10.0, 0.0, 0.0)], [1.0, Vector3(-7.0, 0.0, 0.0)]],
			"thigh.R": [[0.0, Vector3(-17.0, 0.0, 0.0)], [0.25, Vector3(2.0, 0.0, 0.0)], [0.5, Vector3(18.0, 0.0, 0.0)], [0.75, Vector3(2.0, 0.0, 0.0)], [1.0, Vector3(-17.0, 0.0, 0.0)]],
			"shin.R": [[0.0, Vector3(14.0, 0.0, 0.0)], [0.25, Vector3(44.0, 0.0, 0.0)], [0.5, Vector3(5.0, 0.0, 0.0)], [0.75, Vector3(6.0, 0.0, 0.0)], [1.0, Vector3(14.0, 0.0, 0.0)]],
			"foot.R": [[0.0, Vector3(12.0, 0.0, 0.0)], [0.25, Vector3(-10.0, 0.0, 0.0)], [0.5, Vector3(-7.0, 0.0, 0.0)], [0.75, Vector3(2.0, 0.0, 0.0)], [1.0, Vector3(12.0, 0.0, 0.0)]],
			"upper_arm.L": [[0.0, Vector3(-14.0, 0.0, 3.0)], [0.25, Vector3(-1.0, 0.0, 3.0)], [0.5, Vector3(14.0, 0.0, 3.0)], [0.75, Vector3(1.0, 0.0, 3.0)], [1.0, Vector3(-14.0, 0.0, 3.0)]],
			"upper_arm.R": [[0.0, Vector3(14.0, 0.0, -3.0)], [0.25, Vector3(1.0, 0.0, -3.0)], [0.5, Vector3(-14.0, 0.0, -3.0)], [0.75, Vector3(-1.0, 0.0, -3.0)], [1.0, Vector3(14.0, 0.0, -3.0)]],
			"fore_arm.L": [[0.0, Vector3(16.0, 0.0, 0.0)], [0.25, Vector3(12.0, 0.0, 0.0)], [0.5, Vector3(10.0, 0.0, 0.0)], [1.0, Vector3(16.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(10.0, 0.0, 0.0)], [0.25, Vector3(12.0, 0.0, 0.0)], [0.5, Vector3(16.0, 0.0, 0.0)], [1.0, Vector3(10.0, 0.0, 0.0)]],
			"spine": [[0.0, Vector3(2.0, 0.0, 1.2)], [0.5, Vector3(2.0, 0.0, -1.2)], [1.0, Vector3(2.0, 0.0, 1.2)]],
			"head": [[0.0, Vector3(-1.0, 0.0, -0.8)], [0.5, Vector3(-1.0, 0.0, 0.8)], [1.0, Vector3(-1.0, 0.0, -0.8)]],
		},
	},
	"jog": {
		"length": 0.72,
		"tracks": {
			"thigh.L": [[0.0, Vector3(30.0, 0.0, 0.0)], [0.18, Vector3(6.0, 0.0, 0.0)], [0.36, Vector3(-22.0, 0.0, 0.0)], [0.54, Vector3(6.0, 0.0, 0.0)], [0.72, Vector3(30.0, 0.0, 0.0)]],
			"shin.L": [[0.0, Vector3(12.0, 0.0, 0.0)], [0.18, Vector3(20.0, 0.0, 0.0)], [0.36, Vector3(34.0, 0.0, 0.0)], [0.54, Vector3(74.0, 0.0, 0.0)], [0.72, Vector3(12.0, 0.0, 0.0)]],
			"foot.L": [[0.0, Vector3(-10.0, 0.0, 0.0)], [0.18, Vector3(6.0, 0.0, 0.0)], [0.36, Vector3(16.0, 0.0, 0.0)], [0.54, Vector3(-14.0, 0.0, 0.0)], [0.72, Vector3(-10.0, 0.0, 0.0)]],
			"thigh.R": [[0.0, Vector3(-22.0, 0.0, 0.0)], [0.18, Vector3(6.0, 0.0, 0.0)], [0.36, Vector3(30.0, 0.0, 0.0)], [0.54, Vector3(6.0, 0.0, 0.0)], [0.72, Vector3(-22.0, 0.0, 0.0)]],
			"shin.R": [[0.0, Vector3(34.0, 0.0, 0.0)], [0.18, Vector3(74.0, 0.0, 0.0)], [0.36, Vector3(12.0, 0.0, 0.0)], [0.54, Vector3(20.0, 0.0, 0.0)], [0.72, Vector3(34.0, 0.0, 0.0)]],
			"foot.R": [[0.0, Vector3(16.0, 0.0, 0.0)], [0.18, Vector3(-14.0, 0.0, 0.0)], [0.36, Vector3(-10.0, 0.0, 0.0)], [0.54, Vector3(6.0, 0.0, 0.0)], [0.72, Vector3(16.0, 0.0, 0.0)]],
			"upper_arm.L": [[0.0, Vector3(-24.0, 0.0, 5.0)], [0.36, Vector3(24.0, 0.0, 5.0)], [0.72, Vector3(-24.0, 0.0, 5.0)]],
			"upper_arm.R": [[0.0, Vector3(24.0, 0.0, -5.0)], [0.36, Vector3(-24.0, 0.0, -5.0)], [0.72, Vector3(24.0, 0.0, -5.0)]],
			"fore_arm.L": [[0.0, Vector3(34.0, 0.0, 0.0)], [0.36, Vector3(26.0, 0.0, 0.0)], [0.72, Vector3(34.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(26.0, 0.0, 0.0)], [0.36, Vector3(34.0, 0.0, 0.0)], [0.72, Vector3(26.0, 0.0, 0.0)]],
			"spine": [[0.0, Vector3(5.0, 0.0, 2.0)], [0.36, Vector3(5.0, 0.0, -2.0)], [0.72, Vector3(5.0, 0.0, 2.0)]],
			"head": [[0.0, Vector3(-2.0, 0.0, -1.2)], [0.36, Vector3(-2.0, 0.0, 1.2)], [0.72, Vector3(-2.0, 0.0, -1.2)]],
		},
	},
	"sit_idle": {
		"length": 2.4,
		"tracks": {
			"thigh.L": [[0.0, Vector3(82.0, 0.0, 2.0)], [1.2, Vector3(82.0, 0.0, 3.0)], [2.4, Vector3(82.0, 0.0, 2.0)]],
			"thigh.R": [[0.0, Vector3(82.0, 0.0, -2.0)], [1.2, Vector3(82.0, 0.0, -3.0)], [2.4, Vector3(82.0, 0.0, -2.0)]],
			"shin.L": [[0.0, Vector3(84.0, 0.0, 0.0)], [1.2, Vector3(84.0, 0.0, 0.0)], [2.4, Vector3(84.0, 0.0, 0.0)]],
			"shin.R": [[0.0, Vector3(84.0, 0.0, 0.0)], [1.2, Vector3(84.0, 0.0, 0.0)], [2.4, Vector3(84.0, 0.0, 0.0)]],
			"foot.L": [[0.0, Vector3(-6.0, 0.0, 0.0)], [1.2, Vector3(-6.0, 0.0, 0.0)], [2.4, Vector3(-6.0, 0.0, 0.0)]],
			"foot.R": [[0.0, Vector3(-6.0, 0.0, 0.0)], [1.2, Vector3(-6.0, 0.0, 0.0)], [2.4, Vector3(-6.0, 0.0, 0.0)]],
			"spine": [[0.0, Vector3(10.0, 0.0, 0.0)], [1.2, Vector3(12.0, 0.0, 0.0)], [2.4, Vector3(10.0, 0.0, 0.0)]],
			"neck": [[0.0, Vector3(4.0, 0.0, 0.0)], [1.2, Vector3(5.0, 0.0, 0.0)], [2.4, Vector3(4.0, 0.0, 0.0)]],
			"head": [[0.0, Vector3(8.0, 0.0, 0.0)], [1.2, Vector3(10.0, 0.0, 0.0)], [2.4, Vector3(8.0, 0.0, 0.0)]],
			"upper_arm.L": [[0.0, Vector3(26.0, 0.0, 8.0)], [1.2, Vector3(28.0, 0.0, 8.0)], [2.4, Vector3(26.0, 0.0, 8.0)]],
			"upper_arm.R": [[0.0, Vector3(26.0, 0.0, -8.0)], [1.2, Vector3(28.0, 0.0, -8.0)], [2.4, Vector3(26.0, 0.0, -8.0)]],
			"fore_arm.L": [[0.0, Vector3(48.0, 0.0, 0.0)], [1.2, Vector3(50.0, 0.0, 0.0)], [2.4, Vector3(48.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(48.0, 0.0, 0.0)], [1.2, Vector3(50.0, 0.0, 0.0)], [2.4, Vector3(48.0, 0.0, 0.0)]],
		},
	},
	"get_up": {
		"length": 1.5,
		"loop": false,
		"tracks": {
			"thigh.L": [[0.0, Vector3(82.0, 0.0, 2.0)], [0.7, Vector3(40.0, 0.0, 1.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"thigh.R": [[0.0, Vector3(82.0, 0.0, -2.0)], [0.7, Vector3(40.0, 0.0, -1.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"shin.L": [[0.0, Vector3(84.0, 0.0, 0.0)], [0.7, Vector3(44.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"shin.R": [[0.0, Vector3(84.0, 0.0, 0.0)], [0.7, Vector3(44.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"foot.L": [[0.0, Vector3(-6.0, 0.0, 0.0)], [0.7, Vector3(-4.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"foot.R": [[0.0, Vector3(-6.0, 0.0, 0.0)], [0.7, Vector3(-4.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"spine": [[0.0, Vector3(10.0, 0.0, 0.0)], [0.7, Vector3(6.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"neck": [[0.0, Vector3(4.0, 0.0, 0.0)], [0.7, Vector3(2.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"head": [[0.0, Vector3(8.0, 0.0, 0.0)], [0.7, Vector3(4.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"upper_arm.L": [[0.0, Vector3(26.0, 0.0, 8.0)], [0.7, Vector3(14.0, 0.0, 4.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"upper_arm.R": [[0.0, Vector3(26.0, 0.0, -8.0)], [0.7, Vector3(14.0, 0.0, -4.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"fore_arm.L": [[0.0, Vector3(48.0, 0.0, 0.0)], [0.7, Vector3(22.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(48.0, 0.0, 0.0)], [0.7, Vector3(22.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
		},
	},
	"wave": {
		"length": 1.6,
		"tracks": {
			"upper_arm.R": [[0.0, Vector3(-10.0, 0.0, -70.0)], [0.8, Vector3(-10.0, 0.0, -80.0)], [1.6, Vector3(-10.0, 0.0, -70.0)]],
			"fore_arm.R": [[0.0, Vector3(0.0, 0.0, -20.0)], [0.4, Vector3(0.0, 0.0, 25.0)], [0.8, Vector3(0.0, 0.0, -25.0)], [1.2, Vector3(0.0, 0.0, 25.0)], [1.6, Vector3(0.0, 0.0, -20.0)]],
			"hand.R": [[0.0, Vector3(0.0, 0.0, 10.0)], [0.8, Vector3(0.0, 0.0, -10.0)], [1.6, Vector3(0.0, 0.0, 10.0)]],
			"head": [[0.0, Vector3(0.0, 0.0, -3.0)], [0.8, Vector3(-2.0, 0.0, -5.0)], [1.6, Vector3(0.0, 0.0, -3.0)]],
			"upper_arm.L": [[0.0, Vector3(3.0, 0.0, 3.0)], [0.8, Vector3(5.0, 0.0, 4.0)], [1.6, Vector3(3.0, 0.0, 3.0)]],
		},
	},
	"talk": {
		"length": 1.2,
		"tracks": {
			"head": [[0.0, Vector3(3.0, 0.0, 0.0)], [0.4, Vector3(-3.0, 0.0, 2.0)], [0.8, Vector3(2.0, 0.0, -2.0)], [1.2, Vector3(3.0, 0.0, 0.0)]],
			"neck": [[0.0, Vector3(0.0, 0.0, 0.0)], [0.6, Vector3(1.5, 0.0, 0.0)], [1.2, Vector3(0.0, 0.0, 0.0)]],
			"chest": [[0.0, Vector3(0.0, 0.0, 0.0)], [0.6, Vector3(-2.0, 0.0, 1.5)], [1.2, Vector3(0.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(20.0, 0.0, 0.0)], [0.4, Vector3(40.0, 0.0, -10.0)], [0.8, Vector3(25.0, 0.0, 0.0)], [1.2, Vector3(20.0, 0.0, 0.0)]],
			"upper_arm.R": [[0.0, Vector3(6.0, 0.0, -4.0)], [0.6, Vector3(14.0, 0.0, -8.0)], [1.2, Vector3(6.0, 0.0, -4.0)]],
		},
	},
}

## Name the built library is registered under, so clips play as `char/idle`.
const LIBRARY_NAME := &"char"


## Every skeleton under `model_root`, in tree order.
static func skeletons_in(model_root: Node) -> Array[Skeleton3D]:
	var found: Array[Skeleton3D] = []
	for node in model_root.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		if skeleton != null:
			found.append(skeleton)
	return found


## Which of a rig's bones each canonical name resolved to, and which canonical names the rig
## cannot express. `resolved` maps canonical → the rig's own bone name.
static func resolve_rig(skeleton: Skeleton3D) -> Dictionary:
	var by_lower := {}
	var bones: Array[String] = []
	for index in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(index)
		bones.append(name)
		by_lower[name.to_lower()] = name
	var resolved := {}
	var missing: Array[String] = []
	for canonical in BONE_ALIASES:
		var bone := _match(by_lower, canonical)
		if bone.is_empty():
			missing.append(canonical)
		else:
			resolved[canonical] = bone
	return {"skeleton": skeleton, "bones": bones, "resolved": resolved, "missing": missing}


## The bone name on this rig for a canonical name, or "" when the rig does not have it.
## Exact names win. Failing that, Godot's `_2` suffix is tried: a glTF node whose name is
## already taken becomes `Name_2`, which is why the production protagonist's neck answers to
## `Neck_2` here and `Neck` in Blender, while rigged Q answers to `Neck` — Q was exported from
## a scene with nothing else called Neck in it.
static func _match(by_lower: Dictionary, canonical: String) -> String:
	var aliases: Array = BONE_ALIASES[canonical]
	for alias: String in aliases:
		var hit: Variant = by_lower.get(alias.to_lower())
		if hit != null:
			return String(hit)
	for alias: String in aliases:
		for suffix in range(2, 5):
			var hit: Variant = by_lower.get("%s_%d" % [alias.to_lower(), suffix])
			if hit != null:
				return String(hit)
	return ""


## The rig's own frame, measured from its rest pose rather than assumed.
##
## `side` points from the left thigh to the right one, `up` from the hips to the head, and
## `forward` is `side × up` — which lands on +Z for both production rigs, the same side the
## protagonist's eyes and the toes of both shoes are on. A rig that faces the other way would
## report the other sign instead of silently animating backwards.
static func pose_frame(skeleton: Skeleton3D, rig: Dictionary) -> Dictionary:
	var resolved: Dictionary = rig["resolved"]
	var side := Vector3.RIGHT
	if has_bone(skeleton, resolved, "thigh.L") and has_bone(skeleton, resolved, "thigh.R"):
		var across := (
			bone_rest_origin(skeleton, resolved, "thigh.R")
			- bone_rest_origin(skeleton, resolved, "thigh.L")
		)
		if across.length() > 0.001:
			side = across.normalized()
	var up := Vector3.UP
	if has_bone(skeleton, resolved, "hips") and has_bone(skeleton, resolved, "head"):
		var spine := (
			bone_rest_origin(skeleton, resolved, "head")
			- bone_rest_origin(skeleton, resolved, "hips")
		)
		if spine.length() > 0.001:
			up = spine.normalized()
	# `up` has to be perpendicular to `side`, or `forward` is not perpendicular to either.
	var flat := up - side * up.dot(side)
	if flat.length() > 0.001:
		up = flat.normalized()
	return {"side": side, "up": up, "forward": side.cross(up).normalized()}


## Whether this rig resolved a canonical bone to a bone it actually has.
static func has_bone(skeleton: Skeleton3D, resolved: Dictionary, canonical: String) -> bool:
	if not resolved.has(canonical):
		return false
	return skeleton.find_bone(String(resolved[canonical])) >= 0


## Where a canonical bone sits in the rest pose. Only call it after `has_bone()`.
static func bone_rest_origin(skeleton: Skeleton3D, resolved: Dictionary, canonical: String) -> Vector3:
	var index := skeleton.find_bone(String(resolved[canonical]))
	if index < 0:
		return Vector3.ZERO
	return skeleton.get_bone_global_rest(index).origin


## The ±1 per canonical bone that turns "degrees of meaning" into the rig's own local X axis.
##
## The axis comes from the skeleton and the *meaning* from `X_MEANING`: a bone whose local X
## rotation swings its far end towards the model's back needs -1 for +18 to mean "forward", and
## a knee needs the opposite of whatever the thigh needed, because closing a joint sends its
## far end backwards. Nothing here is a table of rigs — a new rig measures itself.
static func x_signs(skeleton: Skeleton3D, rig: Dictionary) -> Dictionary:
	var frame := pose_frame(skeleton, rig)
	var forward: Vector3 = frame["forward"]
	var up: Vector3 = frame["up"]
	var resolved: Dictionary = rig["resolved"]
	var signs := {}
	for canonical: String in X_MEANING:
		if not has_bone(skeleton, resolved, canonical):
			continue
		var name := String(resolved[canonical])
		var index := skeleton.find_bone(name)
		var basis := skeleton.get_bone_global_rest(index).basis
		var axis := basis.x.normalized()
		var along := basis.y.normalized()
		# Where the far end of the bone goes for a small positive rotation about its own X.
		var swing := axis.cross(along).normalized()
		var towards_forward := swing.dot(forward)
		var meaning: String = X_MEANING[canonical]
		var sign := 1.0
		match meaning:
			"forward":
				sign = 1.0 if towards_forward > 0.0 else -1.0
			"close":
				sign = 1.0 if towards_forward < 0.0 else -1.0
			"toes_down":
				sign = 1.0 if swing.dot(up) < 0.0 else -1.0
		# A bone whose X axis is nearly parallel to `forward` has no swing in it at all: the
		# clip's angle would twist the limb instead, which no angle check can see.
		if absf(towards_forward) < 0.5:
			push_warning(
				"%s: the local X axis of '%s' is %.2f aligned with the body's forward axis, so the"
				% [String(name), canonical, towards_forward]
				+ " clips would twist it instead of swinging it."
			)
		signs[canonical] = sign
	return signs


## One entry per joint family, so a log can show what was measured without printing 19 numbers.
## A family whose left and right disagree is printed as `mixed`, which is a rig to look at.
static func signs_summary(report: Dictionary) -> String:
	var signs: Dictionary = report.get("x_signs", {})
	if signs.is_empty():
		return "no signs"
	var families := {}
	for canonical: String in signs:
		var family := canonical
		if family.ends_with(".L") or family.ends_with(".R"):
			family = family.substr(0, family.length() - 2)
		var value := float(signs[canonical])
		if not families.has(family):
			families[family] = value
		elif not is_equal_approx(float(families[family]), value):
			families[family] = 0.0
	var parts: PackedStringArray = []
	for family: String in families:
		var value := float(families[family])
		parts.append("%s %s" % [family, "+" if value > 0.0 else ("-" if value < 0.0 else "mixed")])
	return ", ".join(parts)


## Builds the four clips for one rig and registers them on `player` as `char/…`.
##
## `player.root_node` must be the model root, so that a track path of `"Skeleton3D:Spine"`
## means "this model's skeleton, this bone". Returns the report the caller can print:
## the resolved and missing bones, and the track count of each clip.
static func bind(model_root: Node3D, player: AnimationPlayer) -> Dictionary:
	var skeletons := skeletons_in(model_root)
	if skeletons.is_empty():
		return {
		"ok": false,
		"reason": "the model has no Skeleton3D",
		"resolved": {},
		"missing": [],
		"bones": [],
		"clips": {},
		"frame": {},
		"x_signs": {},
	}
	var skeleton := skeletons[0]
	if skeletons.size() > 1:
		push_warning(
			"%s has %d skeletons; binding the first (%s)."
			% [model_root.name, skeletons.size(), skeleton.name]
		)
	if player.get_parent() != model_root:
		# Track paths are resolved against the player's root node, so the player has to sit
		# inside the model for `..` to be the model and the skeleton path to be relative to it.
		push_warning("AnimationPlayer should be a child of the model root; binding anyway.")
	var rig := resolve_rig(skeleton)
	var signs := x_signs(skeleton, rig)
	var frame := pose_frame(skeleton, rig)
	var skeleton_path := model_root.get_path_to(skeleton)
	var library := AnimationLibrary.new()
	var clip_report := {}
	for clip_name in CLIPS:
		var spec: Dictionary = CLIPS[clip_name]
		var animation := Animation.new()
		animation.length = float(spec["length"])
		# A transition is played once and stops on its last key; everything else closes
		# its cycle, so the last key repeats the first.
		var loops := bool(spec.get("loop", true))
		animation.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
		var tracks: Dictionary = spec["tracks"]
		var used := 0
		for canonical in tracks:
			var bone: Variant = rig["resolved"].get(canonical)
			if bone == null:
				continue
			var path := NodePath("%s:%s" % [String(skeleton_path), String(bone)])
			var track := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track, path)
			# The X angle is authored in meaning; the sign is what the rig measured.
			var x_sign := float(signs.get(canonical, 1.0))
			for key: Array in tracks[canonical]:
				var degrees: Vector3 = key[1]
				animation.rotation_track_insert_key(
					track,
					float(key[0]),
					Quaternion.from_euler(
						Vector3(
							deg_to_rad(degrees.x * x_sign),
							deg_to_rad(degrees.y),
							deg_to_rad(degrees.z)
						)
					)
				)
			used += 1
		library.add_animation(clip_name, animation)
		clip_report[clip_name] = {
			"tracks": used,
			"requested": tracks.size(),
			"length": animation.length,
			"loops": loops,
		}
	if player.has_animation_library(LIBRARY_NAME):
		player.remove_animation_library(LIBRARY_NAME)
	player.add_animation_library(LIBRARY_NAME, library)
	return {
		"ok": true,
		"skeleton": skeleton.name,
		"bones": rig["bones"],
		"resolved": rig["resolved"],
		"missing": rig["missing"],
		"clips": clip_report,
		"library": library,
		"frame": frame,
		"x_signs": signs,
	}


## Plays `clip_name` on a bound player. Returns false (and says why) rather than leaving a
## character in whatever pose the last clip stopped at.
static func play(player: AnimationPlayer, clip_name: String) -> bool:
	var full := "%s/%s" % [String(LIBRARY_NAME), clip_name]
	if not player.has_animation(full):
		push_error("CharacterAnimation: '%s' is not bound on this player." % full)
		return false
	player.play(full)
	return true


## A one-line description of what a rig can and cannot do, for a log or a notice.
static func describe(report: Dictionary) -> String:
	if not bool(report.get("ok", false)):
		return "not bound: %s" % String(report.get("reason", "unknown"))
	var resolved: Dictionary = report["resolved"]
	var missing: Array = report["missing"]
	var clips: Dictionary = report["clips"]
	var parts: PackedStringArray = []
	for clip_name in clips:
		var info: Dictionary = clips[clip_name]
		parts.append(
			"%s %d/%d tracks %.1fs%s"
			% [
				clip_name,
				int(info["tracks"]),
				int(info["requested"]),
				float(info["length"]),
				"" if bool(info.get("loops", true)) else " once",
			]
		)
	return "%d bone(s) resolved, %d not on this rig (%s) | %s | x signs: %s" % [
		resolved.size(),
		missing.size(),
		", ".join(PackedStringArray(missing)) if not missing.is_empty() else "none",
		" | ".join(parts),
		signs_summary(report),
	]

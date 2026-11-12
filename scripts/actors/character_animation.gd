class_name CharacterAnimation
extends RefCounted
## Clips for the game's characters, built in code against *semantic* bone names.
##
## The rigged characters do not name their bones the same way:
##
##   protagonist (Protagonist_Character.glb)  Root, Pelvis, Spine, Chest, UpperArm_L, Shin_L, …
##   former protagonist (protagonist.glb)     Root, Spine, Neck, Head, UpperArm.L, LowerArm.L, …
##   rigged Q                                 Root, Spine, Neck, Head, UpperArm.L, LowerArm.L, …
##   retargeted protagonist (dev test)        Root, Hips, Spine, Chest, UpperChest, …
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
## in the editor: an `Animation` is a resource and its track paths are
## `"<skeleton path>:<bone name>"`.
##
## **The keys in `CLIPS` are offsets from the rest pose, and `bind()` composes them onto it.**
## A Godot 4 rotation track does not add to the rest: it *replaces* the bone's local rotation.
## Both rigs hang their arms and legs from the body with a local rest rotation of 170–180°, so
## a key of "3° about X" written as-is turned every arm and leg to point straight up — which is
## what the first runtime wiring shipped (both characters stood with their arms raised). Each
## key is therefore written as `rest * offset`, with the offset expressed in the bone's
## *semantic* frame (see `semantic_frame()`): X is the character's side axis, so X swings a
## limb forward and back and Z moves it out to the side, on every rig. A rig's own local axes
## are not trusted for that: the new protagonist's arms are twisted ~35–39° about their length
## and its feet ~19°, so the same local offset would swing an arm diagonally across the body.
##
## Sides are positional, not nominal: the clips' `.L` is the limb on the skeleton's −X side
## (the convention the clips were authored and measured in), whatever the rig calls it. The
## former protagonist and Q name that side `.L`; the new protagonist names its limbs
## anatomically and puts `UpperArm_L` at +X, so on that rig `upper_arm.L` binds to
## `UpperArm_R`. `resolve_rig()` decides this from the rest positions and reports it.
##
## Every clip also carries a track for every bone *any* clip animates. A bone that one clip
## moves and the next one does not would otherwise keep the last pose the first clip gave it —
## a character that stops walking would stand with one leg still mid-stride. Bones a clip does
## not author are held at rest.

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
	"upper_arm.L": ["UpperArm.L", "UpperArm_L", "LeftUpperArm", "LeftArm", "upperarm_l"],
	"upper_arm.R": ["UpperArm.R", "UpperArm_R", "RightUpperArm", "RightArm", "upperarm_r"],
	"fore_arm.L": ["LowerArm.L", "LeftLowerArm", "LeftForeArm", "lowerarm_l", "forearm_l"],
	"fore_arm.R": ["LowerArm.R", "RightLowerArm", "RightForeArm", "lowerarm_r", "forearm_r"],
	"hand.L": ["Hand.L", "LeftHand", "hand_l"],
	"hand.R": ["Hand.R", "RightHand", "hand_r"],
	"thigh.L": ["Thigh.L", "LeftUpperLeg", "LeftUpLeg", "thigh_l", "upleg_l"],
	"thigh.R": ["Thigh.R", "RightUpperLeg", "RightUpLeg", "thigh_r", "upleg_r"],
	"shin.L": ["Shin.L", "Shin_L", "LeftLowerLeg", "LeftLeg", "calf_l", "lowerleg_l"],
	"shin.R": ["Shin.R", "Shin_R", "RightLowerLeg", "RightLeg", "calf_r", "lowerleg_r"],
	"foot.L": ["Foot.L", "LeftFoot", "foot_l"],
	"foot.R": ["Foot.R", "RightFoot", "foot_r"],
}

## The clips, authored in canonical names. Each key is `[time in seconds, degrees about the
## bone's own axes]`; the last key repeats the first so a looping clip closes the cycle.
## Rotations are offsets from the rest pose, about the bone's semantic axes
## (`semantic_frame()`): Y runs along the bone, X is the character's side axis (skeleton +X)
## made perpendicular to it, and Z = X × Y. X swings a limb and Z reaches out to the side.
## On a hanging limb Z points backwards, so +Z moves the far end towards −X: outwards for a
## `.L` limb, which is why the `.R` keys carry the opposite Z sign.
##
## The sign that matters, because it is the one a new clip gets wrong, was measured from the
## GLB joints and is checked by `tests/runtime_character_animation_test.gd`: **+X moves the
## far end of a hanging limb backward.** So flexion is
##
##   hip (thigh)        −X   (the leg comes forward)
##   knee (shin)        +X   (the shin folds back)
##   shoulder           −X   (the arm comes forward)
##   elbow (fore_arm)   −X   (the hand comes forward)
##   foot               +X points the toe, −X lifts it
##   spine, neck, head  +X leans and nods forward (their rest is close to identity)
##
## A seated pose is therefore `thigh −82, shin +84`. An earlier note read "+X is flexion"
## for every joint; that came from keys written as absolute rotations (the arms-up bug, see
## `bind()`), and it bent hips, shoulders and elbows the wrong way once keys were composed
## with the rest pose.
##
## A clip may set `"loop": false`. Such a clip is a *transition*: it is played once and hands
## back to whatever was there before (the wrapper's `play_action()`), and its last key is the
## rest pose (zero offset) rather than its first, because arriving is the point. `get_up` is
## the only one, and the test checks that its first key is the seated pose that `sit_idle`
## holds, so the two cannot drift apart.
const CLIPS := {
	"idle": {
		"length": 2.0,
		"tracks": {
			"spine": [[0.0, Vector3(-1.5, 0.0, 0.0)], [1.0, Vector3(1.5, 0.0, 0.0)], [2.0, Vector3(-1.5, 0.0, 0.0)]],
			"chest": [[0.0, Vector3(1.0, 0.0, 0.0)], [1.0, Vector3(-1.0, 0.0, 0.0)], [2.0, Vector3(1.0, 0.0, 0.0)]],
			"head": [[0.0, Vector3(0.0, 0.0, 1.0)], [1.0, Vector3(-1.5, 0.0, -1.0)], [2.0, Vector3(0.0, 0.0, 1.0)]],
			"upper_arm.L": [[0.0, Vector3(3.0, 0.0, 3.0)], [1.0, Vector3(5.0, 0.0, 4.0)], [2.0, Vector3(3.0, 0.0, 3.0)]],
			"upper_arm.R": [[0.0, Vector3(3.0, 0.0, -3.0)], [1.0, Vector3(5.0, 0.0, -4.0)], [2.0, Vector3(3.0, 0.0, -3.0)]],
			"fore_arm.L": [[0.0, Vector3(-6.0, 0.0, 0.0)], [1.0, Vector3(-8.0, 0.0, 0.0)], [2.0, Vector3(-6.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(-6.0, 0.0, 0.0)], [1.0, Vector3(-8.0, 0.0, 0.0)], [2.0, Vector3(-6.0, 0.0, 0.0)]],
		},
	},
	"walk": {
		"length": 1.0,
		# Four phases per leg: toe-off (thigh back, foot pointed), swing (knee bent most),
		# heel strike (thigh forward, knee nearly straight, toe up), stance. The right leg is
		# the left leg half a cycle later, and each arm swings against the leg on its side.
		"tracks": {
			"thigh.L": [[0.0, Vector3(20.0, 0.0, 0.0)], [0.25, Vector3(0.0, 0.0, 0.0)], [0.5, Vector3(-22.0, 0.0, 0.0)], [0.75, Vector3(0.0, 0.0, 0.0)], [1.0, Vector3(20.0, 0.0, 0.0)]],
			"thigh.R": [[0.0, Vector3(-22.0, 0.0, 0.0)], [0.25, Vector3(0.0, 0.0, 0.0)], [0.5, Vector3(20.0, 0.0, 0.0)], [0.75, Vector3(0.0, 0.0, 0.0)], [1.0, Vector3(-22.0, 0.0, 0.0)]],
			"shin.L": [[0.0, Vector3(10.0, 0.0, 0.0)], [0.25, Vector3(38.0, 0.0, 0.0)], [0.5, Vector3(4.0, 0.0, 0.0)], [0.75, Vector3(8.0, 0.0, 0.0)], [1.0, Vector3(10.0, 0.0, 0.0)]],
			"shin.R": [[0.0, Vector3(4.0, 0.0, 0.0)], [0.25, Vector3(8.0, 0.0, 0.0)], [0.5, Vector3(10.0, 0.0, 0.0)], [0.75, Vector3(38.0, 0.0, 0.0)], [1.0, Vector3(4.0, 0.0, 0.0)]],
			"foot.L": [[0.0, Vector3(12.0, 0.0, 0.0)], [0.25, Vector3(4.0, 0.0, 0.0)], [0.5, Vector3(-8.0, 0.0, 0.0)], [0.75, Vector3(0.0, 0.0, 0.0)], [1.0, Vector3(12.0, 0.0, 0.0)]],
			"foot.R": [[0.0, Vector3(-8.0, 0.0, 0.0)], [0.25, Vector3(0.0, 0.0, 0.0)], [0.5, Vector3(12.0, 0.0, 0.0)], [0.75, Vector3(4.0, 0.0, 0.0)], [1.0, Vector3(-8.0, 0.0, 0.0)]],
			"upper_arm.L": [[0.0, Vector3(-16.0, 0.0, 3.0)], [0.5, Vector3(16.0, 0.0, 3.0)], [1.0, Vector3(-16.0, 0.0, 3.0)]],
			"upper_arm.R": [[0.0, Vector3(16.0, 0.0, -3.0)], [0.5, Vector3(-16.0, 0.0, -3.0)], [1.0, Vector3(16.0, 0.0, -3.0)]],
			"fore_arm.L": [[0.0, Vector3(-22.0, 0.0, 0.0)], [0.5, Vector3(-12.0, 0.0, 0.0)], [1.0, Vector3(-22.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(-12.0, 0.0, 0.0)], [0.5, Vector3(-22.0, 0.0, 0.0)], [1.0, Vector3(-12.0, 0.0, 0.0)]],
			"spine": [[0.0, Vector3(2.0, 0.0, 1.5)], [0.5, Vector3(2.0, 0.0, -1.5)], [1.0, Vector3(2.0, 0.0, 1.5)]],
			"head": [[0.0, Vector3(-2.0, 0.0, -1.0)], [0.5, Vector3(-2.0, 0.0, 1.0)], [1.0, Vector3(-2.0, 0.0, -1.0)]],
		},
	},
	"jog": {
		"length": 0.72,
		"tracks": {
			"thigh.L": [[0.0, Vector3(-34.0, 0.0, 0.0)], [0.36, Vector3(34.0, 0.0, 0.0)], [0.72, Vector3(-34.0, 0.0, 0.0)]],
			"thigh.R": [[0.0, Vector3(34.0, 0.0, 0.0)], [0.36, Vector3(-34.0, 0.0, 0.0)], [0.72, Vector3(34.0, 0.0, 0.0)]],
			"shin.L": [[0.0, Vector3(6.0, 0.0, 0.0)], [0.36, Vector3(46.0, 0.0, 0.0)], [0.72, Vector3(6.0, 0.0, 0.0)]],
			"shin.R": [[0.0, Vector3(46.0, 0.0, 0.0)], [0.36, Vector3(6.0, 0.0, 0.0)], [0.72, Vector3(46.0, 0.0, 0.0)]],
			"foot.L": [[0.0, Vector3(-10.0, 0.0, 0.0)], [0.36, Vector3(8.0, 0.0, 0.0)], [0.72, Vector3(-10.0, 0.0, 0.0)]],
			"foot.R": [[0.0, Vector3(8.0, 0.0, 0.0)], [0.36, Vector3(-10.0, 0.0, 0.0)], [0.72, Vector3(8.0, 0.0, 0.0)]],
			"upper_arm.L": [[0.0, Vector3(26.0, 0.0, 5.0)], [0.36, Vector3(-26.0, 0.0, 5.0)], [0.72, Vector3(26.0, 0.0, 5.0)]],
			"upper_arm.R": [[0.0, Vector3(-26.0, 0.0, -5.0)], [0.36, Vector3(26.0, 0.0, -5.0)], [0.72, Vector3(-26.0, 0.0, -5.0)]],
			"fore_arm.L": [[0.0, Vector3(-30.0, 0.0, 0.0)], [0.36, Vector3(-44.0, 0.0, 0.0)], [0.72, Vector3(-30.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(-44.0, 0.0, 0.0)], [0.36, Vector3(-30.0, 0.0, 0.0)], [0.72, Vector3(-44.0, 0.0, 0.0)]],
			"spine": [[0.0, Vector3(4.0, 0.0, 2.0)], [0.36, Vector3(4.0, 0.0, -2.0)], [0.72, Vector3(4.0, 0.0, 2.0)]],
			"head": [[0.0, Vector3(-3.0, 0.0, -1.5)], [0.36, Vector3(-3.0, 0.0, 1.5)], [0.72, Vector3(-3.0, 0.0, -1.5)]],
		},
	},
	"sit_idle": {
		"length": 2.4,
		"tracks": {
			"thigh.L": [[0.0, Vector3(-82.0, 0.0, 2.0)], [1.2, Vector3(-82.0, 0.0, 3.0)], [2.4, Vector3(-82.0, 0.0, 2.0)]],
			"thigh.R": [[0.0, Vector3(-82.0, 0.0, -2.0)], [1.2, Vector3(-82.0, 0.0, -3.0)], [2.4, Vector3(-82.0, 0.0, -2.0)]],
			"shin.L": [[0.0, Vector3(84.0, 0.0, 0.0)], [1.2, Vector3(84.0, 0.0, 0.0)], [2.4, Vector3(84.0, 0.0, 0.0)]],
			"shin.R": [[0.0, Vector3(84.0, 0.0, 0.0)], [1.2, Vector3(84.0, 0.0, 0.0)], [2.4, Vector3(84.0, 0.0, 0.0)]],
			"foot.L": [[0.0, Vector3(-6.0, 0.0, 0.0)], [1.2, Vector3(-6.0, 0.0, 0.0)], [2.4, Vector3(-6.0, 0.0, 0.0)]],
			"foot.R": [[0.0, Vector3(-6.0, 0.0, 0.0)], [1.2, Vector3(-6.0, 0.0, 0.0)], [2.4, Vector3(-6.0, 0.0, 0.0)]],
			"spine": [[0.0, Vector3(10.0, 0.0, 0.0)], [1.2, Vector3(12.0, 0.0, 0.0)], [2.4, Vector3(10.0, 0.0, 0.0)]],
			"neck": [[0.0, Vector3(4.0, 0.0, 0.0)], [1.2, Vector3(5.0, 0.0, 0.0)], [2.4, Vector3(4.0, 0.0, 0.0)]],
			"head": [[0.0, Vector3(8.0, 0.0, 0.0)], [1.2, Vector3(10.0, 0.0, 0.0)], [2.4, Vector3(8.0, 0.0, 0.0)]],
			"upper_arm.L": [[0.0, Vector3(-26.0, 0.0, 8.0)], [1.2, Vector3(-28.0, 0.0, 8.0)], [2.4, Vector3(-26.0, 0.0, 8.0)]],
			"upper_arm.R": [[0.0, Vector3(-26.0, 0.0, -8.0)], [1.2, Vector3(-28.0, 0.0, -8.0)], [2.4, Vector3(-26.0, 0.0, -8.0)]],
			"fore_arm.L": [[0.0, Vector3(-48.0, 0.0, 0.0)], [1.2, Vector3(-50.0, 0.0, 0.0)], [2.4, Vector3(-48.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(-48.0, 0.0, 0.0)], [1.2, Vector3(-50.0, 0.0, 0.0)], [2.4, Vector3(-48.0, 0.0, 0.0)]],
		},
	},
	"get_up": {
		"length": 1.5,
		"loop": false,
		"tracks": {
			"thigh.L": [[0.0, Vector3(-82.0, 0.0, 2.0)], [0.7, Vector3(-40.0, 0.0, 1.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"thigh.R": [[0.0, Vector3(-82.0, 0.0, -2.0)], [0.7, Vector3(-40.0, 0.0, -1.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"shin.L": [[0.0, Vector3(84.0, 0.0, 0.0)], [0.7, Vector3(44.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"shin.R": [[0.0, Vector3(84.0, 0.0, 0.0)], [0.7, Vector3(44.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"foot.L": [[0.0, Vector3(-6.0, 0.0, 0.0)], [0.7, Vector3(-4.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"foot.R": [[0.0, Vector3(-6.0, 0.0, 0.0)], [0.7, Vector3(-4.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"spine": [[0.0, Vector3(10.0, 0.0, 0.0)], [0.7, Vector3(6.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"neck": [[0.0, Vector3(4.0, 0.0, 0.0)], [0.7, Vector3(2.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"head": [[0.0, Vector3(8.0, 0.0, 0.0)], [0.7, Vector3(4.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"upper_arm.L": [[0.0, Vector3(-26.0, 0.0, 8.0)], [0.7, Vector3(-14.0, 0.0, 4.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"upper_arm.R": [[0.0, Vector3(-26.0, 0.0, -8.0)], [0.7, Vector3(-14.0, 0.0, -4.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"fore_arm.L": [[0.0, Vector3(-48.0, 0.0, 0.0)], [0.7, Vector3(-22.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
			"fore_arm.R": [[0.0, Vector3(-48.0, 0.0, 0.0)], [0.7, Vector3(-22.0, 0.0, 0.0)], [1.5, Vector3(0.0, 0.0, 0.0)]],
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
			"fore_arm.R": [[0.0, Vector3(-20.0, 0.0, 0.0)], [0.4, Vector3(-40.0, 0.0, -10.0)], [0.8, Vector3(-25.0, 0.0, 0.0)], [1.2, Vector3(-20.0, 0.0, 0.0)]],
			"upper_arm.R": [[0.0, Vector3(6.0, 0.0, -4.0)], [0.6, Vector3(14.0, 0.0, -8.0)], [1.2, Vector3(6.0, 0.0, -4.0)]],
		},
	},
}

## The bones the `CLIPS` swing about their own X, on the assumption that they hang down their
## own Y. `bind()` checks that assumption on each rig rather than trusting it: a limb modelled
## in another pose (rigged Q carries its right forearm held out in front, so `LowerArm.R` and
## `Hand.R` point forward) has a different axis under the same name, and a swing about it
## would lift the hand towards the shoulder. Such a bone is held at its modelled pose in every
## clip and listed under `posed` in the report.
const HANGING_LIMBS: Array[String] = [
	"upper_arm.L", "upper_arm.R", "fore_arm.L", "fore_arm.R", "hand.L", "hand.R",
	"thigh.L", "thigh.R", "shin.L", "shin.R",
]
## How closely a hanging limb's rest direction has to follow skeleton −Y (cosine).
const HANGING_MIN_COS := 0.7

## The canonical bones that come in a left/right pair, by their stem (`upper_arm` is
## `upper_arm.L` and `upper_arm.R`). Their sides are decided by position (see `resolve_rig()`).
const SIDE_PAIRS: Array[String] = [
	"shoulder", "upper_arm", "fore_arm", "hand", "thigh", "shin", "foot",
]
## Below this length, a bone's side axis made perpendicular to the bone is too short to define
## a frame (the bone runs along the side axis, like a T-pose clavicle); such a bone keeps its
## own axes. No clip animates one.
const SEMANTIC_MIN_SIDE := 0.2

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
##
## A canonical pair is then put on the right sides by where the two bones *are*: `.L` is the
## bone on the skeleton's −X side. A rig whose names say the opposite (the new protagonist,
## named anatomically, has `UpperArm_L` at +X) gets the pair swapped, and the stem is listed in
## `mirrored`, so a reader of the report sees `upper_arm.L → UpperArm_R` and why.
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
	var mirrored: Array[String] = []
	for stem: String in SIDE_PAIRS:
		var left := "%s.L" % stem
		var right := "%s.R" % stem
		if not resolved.has(left) or not resolved.has(right):
			continue
		var left_x := skeleton.get_bone_global_rest(skeleton.find_bone(String(resolved[left]))).origin.x
		var right_x := skeleton.get_bone_global_rest(skeleton.find_bone(String(resolved[right]))).origin.x
		if left_x > right_x:
			var swap: String = resolved[left]
			resolved[left] = resolved[right]
			resolved[right] = swap
			mirrored.append(stem)
	return {
		"skeleton": skeleton, "bones": bones, "resolved": resolved, "missing": missing,
		"mirrored": mirrored,
	}


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
	var skeleton_path := model_root.get_path_to(skeleton)
	var resolved: Dictionary = rig["resolved"]
	# Every canonical bone any clip animates, resolved on this rig: each clip writes all of
	# them, so switching clips never leaves a bone where the previous clip put it.
	var animated := _animated_bones(resolved)
	var posed := posed_limbs(skeleton, resolved)
	# Each animated bone's semantic frame, as a turn about its own length (see
	# `semantic_frame()`), and how far that turn is: the twist the rig's local axes carry.
	var frames := {}
	var twists := {}
	for canonical: String in animated:
		var frame := semantic_frame(skeleton, skeleton.find_bone(String(resolved[canonical])))
		frames[canonical] = frame
		twists[canonical] = snappedf(rad_to_deg(frame.get_angle()), 0.1)
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
		var held := 0
		for canonical: String in animated:
			var bone := String(resolved[canonical])
			var rest := skeleton.get_bone_rest(skeleton.find_bone(bone)).basis.get_rotation_quaternion()
			var path := NodePath("%s:%s" % [String(skeleton_path), bone])
			var track := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track, path)
			if not tracks.has(canonical) or posed.has(canonical):
				animation.rotation_track_insert_key(track, 0.0, rest)
				animation.rotation_track_insert_key(track, animation.length, rest)
				held += 1
				continue
			var frame: Quaternion = frames[canonical]
			for key: Array in tracks[canonical]:
				var offset := frame * offset_rotation(key[1]) * frame.inverse()
				animation.rotation_track_insert_key(track, float(key[0]), (rest * offset).normalized())
			used += 1
		library.add_animation(clip_name, animation)
		clip_report[clip_name] = {
			# Tracks that move a bone; `held` tracks pin the rest of the animated set at rest.
			"tracks": used,
			"requested": tracks.size(),
			"held": held,
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
		"mirrored": rig["mirrored"],
		"posed": posed,
		"twist_degrees": twists,
		"clips": clip_report,
		"library": library,
	}


## The rotation a `CLIPS` key describes, as an offset from the bone's rest: degrees about
## the bone's semantic X, Y and Z. `bind()` writes `rest * F * offset_rotation(key) * F⁻¹`,
## with F the bone's `semantic_frame()`.
static func offset_rotation(degrees: Vector3) -> Quaternion:
	return Quaternion.from_euler(
		Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
	)


## The turn, in the bone's own local space, from its local axes to its semantic ones:
## Y along the bone (unchanged), X the skeleton's +X made perpendicular to it, Z = X × Y.
##
## Both frames share Y, so this is always a pure twist about the bone's length: it re-aims
## which way X swings and Z reaches, and never changes where the bone points. For a bone whose
## local X already is the side axis it is the identity — the legs and spines of all three rigs
## are within 1° — so those keys are exactly the `rest * offset` they always were. It is what
## makes the same key mean the same movement on a rig whose arms are twisted 35° about their
## length (the new protagonist) and one whose arms are twisted 16° (the former protagonist).
static func semantic_frame(skeleton: Skeleton3D, index: int) -> Quaternion:
	var global := skeleton.get_bone_global_rest(index).basis.orthonormalized()
	var along := global.y.normalized()
	var side := Vector3.RIGHT - along * along.dot(Vector3.RIGHT)
	if side.length() < SEMANTIC_MIN_SIDE:
		return Quaternion.IDENTITY
	side = side.normalized()
	var semantic := Basis(side, along, side.cross(along))
	return (global.inverse() * semantic).get_rotation_quaternion().normalized()


## The `HANGING_LIMBS` this rig resolves but does not model hanging down: their rest Y, in
## skeleton space, is more than ~45° away from straight down. Both shipped models stand on an
## unrotated glTF root, so skeleton space is the character's own space (+Y up, +Z forward).
static func posed_limbs(skeleton: Skeleton3D, resolved: Dictionary) -> Array[String]:
	var posed: Array[String] = []
	for canonical: String in HANGING_LIMBS:
		if not resolved.has(canonical):
			continue
		var index := skeleton.find_bone(String(resolved[canonical]))
		var along := skeleton.get_bone_global_rest(index).basis.y.normalized()
		if along.dot(Vector3.DOWN) < HANGING_MIN_COS:
			posed.append(canonical)
	return posed


## Canonical bones that at least one clip animates and that this rig resolves, in a stable
## order (the order of `BONE_ALIASES`).
static func _animated_bones(resolved: Dictionary) -> Array[String]:
	var wanted := {}
	for clip_name in CLIPS:
		var tracks: Dictionary = CLIPS[clip_name]["tracks"]
		for canonical in tracks:
			wanted[canonical] = true
	var ordered: Array[String] = []
	for canonical: String in BONE_ALIASES:
		if wanted.has(canonical) and resolved.has(canonical):
			ordered.append(canonical)
	return ordered


## Plays `clip_name` on a bound player. Returns false (and says why) rather than leaving a
## character in whatever pose the last clip stopped at.
##
## `blend` is the cross-fade from the clip that was playing, in seconds; -1 uses the player's
## default (no cross-fade unless one was configured).
static func play(player: AnimationPlayer, clip_name: String, blend: float = -1.0) -> bool:
	var full := "%s/%s" % [String(LIBRARY_NAME), clip_name]
	if not player.has_animation(full):
		push_error("CharacterAnimation: '%s' is not bound on this player." % full)
		return false
	player.play(full, blend)
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
	var posed: Array = report.get("posed", [])
	var mirrored: Array = report.get("mirrored", [])
	var twists: Dictionary = report.get("twist_degrees", {})
	var widest := 0.0
	for canonical in twists:
		widest = maxf(widest, absf(float(twists[canonical])))
	return (
		"%d bone(s) resolved, %d not on this rig (%s), held at their modelled pose: %s, "
		% [
			resolved.size(),
			missing.size(),
			", ".join(PackedStringArray(missing)) if not missing.is_empty() else "none",
			", ".join(PackedStringArray(posed)) if not posed.is_empty() else "none",
		]
		+ "sides mirrored: %s, local axes twisted up to %.1f° | %s" % [
			", ".join(PackedStringArray(mirrored)) if not mirrored.is_empty() else "none",
			widest,
			" | ".join(parts),
		]
	)

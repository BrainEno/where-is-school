class_name CharacterMotionProfile
extends Resource
## How one character carries the shared clips: its tempo, how big its movements are, the
## posture it stands in, and a few small layers of its own.
##
## The seven clips in `CharacterAnimation.CLIPS` are one body rhythm. Played as they are,
## every character breathes, walks and talks with exactly the same timing and the same
## swing, which is what made the protagonist and Q read as the same mannequin in two
## outfits. A profile is handed to `CharacterAnimation.bind()` (through the wrapper's
## `CharacterVisualAnimation.motion_profile`) and changes the keys as they are written. It
## never changes which clips exist, what they are called, which bones they key, or the
## state machine that picks them:
##
##   offset(t) = amplitude × clip key(t) + layer(t) + posture × posture_weight(clip, t)
##
## all in the same semantic degrees as `CLIPS` (X swings a limb forward and back, Z out to
## the side; +X leans the spine, neck and head forward), at `t × tempo` seconds.
##
## Rules a profile keeps, so the state machine's promises still hold:
## - only bones the clips already animate are touched (`CharacterAnimation._animated_bones`);
##   a posture or layer naming any other bone is ignored and reported, so the set of joints
##   that move never changes (`tests/protagonist_model_test.gd` holds it to a list);
## - limbs a rig holds at its modelled pose (`posed` in the bind report) stay held;
## - every looping clip still closes: a layer's last key repeats its first;
## - `get_up` still starts on the pose `sit_idle` holds and ends on the standing posture,
##   because its posture weight runs from the seated weight to the standing one.
## No profile (N, the classroom student, every test that binds a bare GLB) is the identity.

## Clip name → length multiplier. 2.0 plays the clip at half speed (a 2 s idle lasts 4 s).
@export var tempo: Dictionary = {}
## Clip name → { canonical bone, stem (`upper_arm`) or `"*"` → multiplier on its keys }.
## The most specific entry wins: `upper_arm.R` before `upper_arm` before `*`.
@export var amplitude: Dictionary = {}
## Canonical bone → Vector3 of degrees added to every key of every clip (and to the bones a
## clip holds still). This is the character's stance: a slump, a lean back, a cocked head.
@export var posture: Dictionary = {}
## Clip name → how much of `posture` it carries (default 1.0). `get_up` blends from the
## `sit_idle` weight at its first key to the `idle` weight at its last.
@export var posture_weight: Dictionary = {}
## Clip name → { canonical bone → [[time, Vector3 degrees], ...] } added on top of the clip.
## Times are in the clip's own seconds, before `tempo`. A looping clip's layer has to end
## where it starts.
@export var layers: Dictionary = {}
## A short name for logs and the bind report.
@export var label: String = ""


func tempo_for(clip_name: String) -> float:
	return maxf(float(tempo.get(clip_name, 1.0)), 0.05)


func amplitude_for(clip_name: String, canonical: String) -> float:
	var table: Dictionary = amplitude.get(clip_name, {})
	if table.has(canonical):
		return float(table[canonical])
	var stem := canonical.get_slice(".", 0)
	if table.has(stem):
		return float(table[stem])
	return float(table.get("*", 1.0))


func posture_for(canonical: String) -> Vector3:
	var value: Variant = posture.get(canonical, Vector3.ZERO)
	return value if value is Vector3 else Vector3.ZERO


## The posture weight at `fraction` (0..1) of `clip_name`.
func posture_weight_at(clip_name: String, fraction: float) -> float:
	if clip_name == "get_up":
		var seated := float(posture_weight.get("sit_idle", 1.0))
		var standing := float(posture_weight.get("idle", 1.0))
		return lerpf(seated, standing, clampf(fraction, 0.0, 1.0))
	return float(posture_weight.get(clip_name, 1.0))


func layer_keys(clip_name: String, canonical: String) -> Array:
	var table: Dictionary = layers.get(clip_name, {})
	return table.get(canonical, [])


## Every canonical bone this profile names, for the bind report's "ignored" list.
func named_bones() -> Array[String]:
	var names: Array[String] = []
	for canonical: String in posture:
		if not names.has(canonical):
			names.append(canonical)
	for clip_name: String in layers:
		var table: Dictionary = layers[clip_name]
		for canonical: String in table:
			if not names.has(canonical):
				names.append(canonical)
	return names


## A key track (`[[time, Vector3], ...]`, sorted by time) sampled at `time`, linearly, held
## flat before the first key and after the last. An empty track is zero.
static func sample(keys: Array, time: float) -> Vector3:
	if keys.is_empty():
		return Vector3.ZERO
	var first: Array = keys[0]
	if time <= float(first[0]):
		return first[1]
	for index in range(1, keys.size()):
		var key: Array = keys[index]
		if time <= float(key[0]):
			var previous: Array = keys[index - 1]
			var span := float(key[0]) - float(previous[0])
			var weight := 0.0 if span <= 0.0 else (time - float(previous[0])) / span
			return (previous[1] as Vector3).lerp(key[1], weight)
	var last: Array = keys[keys.size() - 1]
	return last[1]

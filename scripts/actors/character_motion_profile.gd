class_name CharacterMotionProfile
extends Resource
## One character's keys, rhythm and posture on the shared animation states. A profile
## can replace selected semantic tracks, then apply the usual tempo, amplitude, posture
## and additive layers. It never changes the state machine, rig or movement controller.
##
## offset(t) = amplitude × (authored or fallback key)(t) + layer(t) + posture × weight
## at t × tempo seconds. Only the shared animated bone set is used, and posed-limb
## guards still hold. A null profile preserves the exact fallback clips.

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
## Clip name → { canonical bone → [[time, Vector3 degrees], ...] }. These keys replace
## that bone's base track; unlisted tracks inherit the shared clip. Use the base clip's
## seconds, including both endpoints, before tempo. Looping tracks must close.
@export var clip_tracks: Dictionary = {}
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


func base_keys(clip_name: String, canonical: String, fallback: Array) -> Array:
	var tracks: Dictionary = clip_tracks.get(clip_name, {})
	return tracks.get(canonical, fallback)


## Catch a misspelled state or a discontinuous authored loop before writing tracks.
func track_error(specs: Dictionary) -> String:
	for clip_name: Variant in clip_tracks:
		if not specs.has(clip_name):
			return "unknown clip '%s'" % str(clip_name)
		var table: Variant = clip_tracks[clip_name]
		if not table is Dictionary or table.is_empty():
			return "'%s' needs a dictionary of bone tracks" % clip_name
		var spec: Dictionary = specs[clip_name]
		for canonical: Variant in table:
			var label := "%s / %s" % [clip_name, canonical]
			var keys: Variant = table[canonical]
			if not canonical is String or not keys is Array or keys.size() < 2:
				return "%s needs a bone name and at least two keys" % label
			var previous := -1.0
			for key: Variant in keys:
				if not key is Array or key.size() != 2 \
						or not (key[0] is float or key[0] is int) or not key[1] is Vector3:
					return "%s needs [time, Vector3 angles] keys" % label
				var time := float(key[0])
				if not is_finite(time) or not (key[1] as Vector3).is_finite() \
						or time <= previous:
					return "%s keys must be finite and strictly ordered" % label
				previous = time
			if not is_zero_approx(float(keys[0][0])) or not is_equal_approx(previous, float(spec["length"])):
				return "%s must key both endpoints of its base clip" % label
			if bool(spec.get("loop", true)) and not (keys[0][1] as Vector3).is_equal_approx(keys[-1][1]):
				return "%s does not close its loop" % label
	return ""


## Every canonical bone this profile names, for the bind report's "ignored" list.
func named_bones() -> Array[String]:
	var names: Array[String] = []
	for canonical: String in posture:
		if not names.has(canonical):
			names.append(canonical)
	for source: Dictionary in [layers, clip_tracks]:
		for table: Dictionary in source.values():
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

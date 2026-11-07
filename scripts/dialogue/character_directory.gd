class_name CharacterDirectory
extends RefCounted
## Loads speaker presentation data from data/characters/*.tres.
##
## The file list is explicit instead of scanned so the resources are guaranteed
## to be included in exported builds and a missing file fails loudly.

const CHARACTER_PATHS: Array[String] = [
	"res://data/characters/protagonist.tres",
	"res://data/characters/q.tres",
	"res://data/characters/n.tres",
	"res://data/characters/b.tres",
	# Inner voices are not people, but their lines are presented by the same panel,
	# so they need the same profile for colour and for a fallback name. The translated
	# name comes from data/abilities/<locale>.json; these files hold presentation only.
	# One inner voice is in play for this milestone. Two files would be an
	# accident, not a plan: the ability list is the single source of truth for
	# which voices exist, and a second profile here would be dead weight.
	"res://data/characters/voice_orientation.tres",
]

var errors: Array[String] = []
var _profiles: Dictionary = {}


static func load_all() -> CharacterDirectory:
	var directory := CharacterDirectory.new()
	for path in CHARACTER_PATHS:
		if not ResourceLoader.exists(path):
			directory.errors.append("Character profile missing: %s" % path)
			continue
		var resource: Resource = ResourceLoader.load(path)
		if not (resource is CharacterProfile):
			directory.errors.append("Character profile is not a CharacterProfile: %s" % path)
			continue
		var profile: CharacterProfile = resource
		if String(profile.character_id).is_empty():
			directory.errors.append("Character profile has an empty character_id: %s" % path)
			continue
		if directory._profiles.has(profile.character_id):
			directory.errors.append(
				"Duplicate character_id '%s' in %s" % [profile.character_id, path]
			)
			continue
		directory._profiles[profile.character_id] = profile
	return directory


func has_character(character_id: StringName) -> bool:
	return _profiles.has(character_id)


func get_profile(character_id: StringName) -> CharacterProfile:
	return _profiles.get(character_id, null)


## Falls back to the raw id so a missing profile is visible in game rather than
## silently rendering an empty name.
func get_display_name(character_id: StringName) -> String:
	var profile: CharacterProfile = get_profile(character_id)
	if profile == null or profile.display_name.is_empty():
		return String(character_id)
	return profile.display_name


func get_short_role(character_id: StringName) -> String:
	var profile: CharacterProfile = get_profile(character_id)
	if profile == null:
		return ""
	return profile.short_role


func get_accent_color(character_id: StringName) -> Color:
	var profile: CharacterProfile = get_profile(character_id)
	if profile == null:
		return Color(0.776, 0.733, 0.643, 1.0)
	return profile.accent_color


func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _profiles.keys():
		ids.append(key)
	return ids

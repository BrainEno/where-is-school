class_name CharacterDirectory
extends RefCounted
## Loads speaker presentation data from data/characters/*.tres.
##
## Two kinds of speaker, found two different ways, because they have two different
## sources of truth:
##
## - **Ordinary characters** (the protagonist, classmates) are listed explicitly, so
##   the resources are guaranteed to be included in exported builds and a missing
##   file fails at start-up.
## - **Inner voices** are resolved from the ability registry. A voice declares a
##   `speaker` id in `data/abilities/abilities.json`, and its profile is
##   `data/characters/<speaker_id>.tres`. The voice roster therefore lives in exactly
##   one place, and adding a voice is a data change rather than an edit to a
##   hard-coded array here.
##
## Both are strict, and the voice half is strict on purpose: a voice whose profile is
## missing, whose file declares a different `character_id`, or whose speaker id
## collides with an ordinary character is an error naming the file and both ids.
## There is no fallback to another profile — a voice that speaks with someone else's
## name and colour is worse than one that does not appear at all.
##
## Scanning the directory is deliberately not an option: a scan would only work in an
## editor checkout, because an exported build contains the resources someone packed,
## not a browsable folder.

const CHARACTER_DIR := "res://data/characters"
## Ordinary speakers only. Inner voices are not listed here: see the class comment.
const ORDINARY_CHARACTER_PATHS: Array[String] = [
	"res://data/characters/protagonist.tres",
	"res://data/characters/q.tres",
	"res://data/characters/n.tres",
	"res://data/characters/b.tres",
	"res://data/characters/student.tres",
]

var errors: Array[String] = []
var _profiles: Dictionary = {}
## speaker_id -> ability_id, for the voices this directory resolved. Kept apart from
## `_profiles` so "is this a voice" cannot be answered by guessing from a name.
var _voices: Dictionary = {}
static var _cached: CharacterDirectory = null


## Where a voice's profile must live. One convention, one function, so the loader and
## the error message can never disagree about the expected path.
static func voice_profile_path(
	speaker_id: StringName, voice_dir: String = CHARACTER_DIR
) -> String:
	return "%s/%s.tres" % [voice_dir, String(speaker_id)]


## `abilities` supplies the inner-voice roster; without it only ordinary characters
## are loaded. `voice_dir` exists so a test can point the same lookup at a fixture
## directory in `user://`; the game always calls this with the defaults.
static func load_all(
	abilities: InnerAbilities = null, voice_dir: String = CHARACTER_DIR
) -> CharacterDirectory:
	var directory := CharacterDirectory.new()
	for path in ORDINARY_CHARACTER_PATHS:
		var profile := directory._read_profile(path)
		if profile != null:
			directory._register(profile, path)
	if abilities != null:
		for speaker_id: StringName in abilities.get_speaker_ids():
			directory._load_voice(speaker_id, abilities, voice_dir)
	return directory


func _load_voice(speaker_id: StringName, abilities: InnerAbilities, voice_dir: String) -> void:
	var ability := abilities.get_ability_for_speaker(speaker_id)
	var ability_id: StringName = &""
	if ability != null:
		ability_id = ability.ability_id
	var path := voice_profile_path(speaker_id, voice_dir)
	if _profiles.has(speaker_id):
		errors.append(
			"Inner voice '%s' uses speaker id '%s', which is already the profile of an ordinary character (%s); voices and people need different ids."
			% [ability_id, speaker_id, path]
		)
		return
	var profile := _read_profile(path)
	if profile == null:
		errors.append(
			"Inner voice '%s' has no usable character profile: expected %s for speaker '%s'."
			% [ability_id, path, speaker_id]
		)
		return
	if profile.character_id != speaker_id:
		errors.append(
			"%s declares character_id '%s' but is loaded as speaker '%s' (inner voice '%s'); a profile must belong to exactly one speaker."
			% [path, profile.character_id, speaker_id, ability_id]
		)
		return
	_profiles[speaker_id] = profile
	_voices[speaker_id] = ability_id


## Loads one profile without registering it, so a caller can check the id it declares
## before it becomes reachable by name.
func _read_profile(path: String) -> CharacterProfile:
	if not ResourceLoader.exists(path):
		errors.append("Character profile missing: %s" % path)
		return null
	var resource: Resource = ResourceLoader.load(path)
	if not (resource is CharacterProfile):
		errors.append("Character profile is not a CharacterProfile: %s" % path)
		return null
	var profile: CharacterProfile = resource
	if String(profile.character_id).is_empty():
		errors.append("Character profile has an empty character_id: %s" % path)
		return null
	return profile


func _register(profile: CharacterProfile, path: String) -> void:
	if _profiles.has(profile.character_id):
		errors.append(
			"Duplicate character_id '%s' in %s" % [profile.character_id, path]
		)
		return
	_profiles[profile.character_id] = profile


func has_character(character_id: StringName) -> bool:
	return _profiles.has(character_id)


## True when this speaker is one of the protagonist's inner voices rather than a
## person. The profile itself does not say so: the ability registry does.
func is_inner_voice(character_id: StringName) -> bool:
	return _voices.has(character_id)


func get_profile(character_id: StringName) -> CharacterProfile:
	return _profiles.get(character_id, null)


## The name to put in front of a line of dialogue or above a character in the world.
## The profile holds the name the content was written around; the locale table holds
## how that name reads in each language. Falling back to the profile means a character
## with no localized name still has a name, and falling back to the id keeps a missing
## profile visible instead of silent.
##
## Inner voices are the exception: their name is the translated ability name, which
## `DialogueRuntime.compose_line()` applies, so this stays a profile-level answer for
## every speaker and one override lives in one place.
func get_localized_name(character_id: StringName) -> String:
	var key := "name.%s" % String(character_id)
	if L10n.has_key(key):
		return L10n.t(key)
	return get_display_name(character_id)


## Cached directory for nodes that need a name but are not part of the dialogue
## session (the character nameplates in the world). It covers ordinary characters
## only: nameplates label people standing in a room, and an inner voice never does.
static func load_cached() -> CharacterDirectory:
	if _cached == null:
		_cached = load_all()
	return _cached


static func reset_cache_for_tests() -> void:
	_cached = null


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

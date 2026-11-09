extends SceneTree
## Proves the inner-voice system supports more than one voice, on fixtures only.
##
## The shipped content has one voice and this test does not change that: the two voices
## below (`probe_a`, `probe_b`) exist in `user://` for the length of the run and are
## written through the same loaders the game uses. Nothing here is added to
## `data/abilities/` or `data/characters/`, and no prose written here is canon.
##
## What is covered, in the order the features were built:
##
## - **Identity.** Two abilities with two different values and two different speaker
##   ids; each speaker resolves to its own profile and its own translated name.
## - **Strictness.** A duplicate speaker, a non-numeric or out-of-range value, a
##   missing translation, a translation copied from English, text for an unknown
##   ability, a missing profile, a profile that declares someone else's id, and a
##   speaker id that collides with an ordinary character are all rejected with an error
##   that names the file and the ids.
## - **Active checks.** Two check nodes, each naming a different ability, roll their own
##   value through the one shared `CheckResolver`, branch on their own result, record
##   under their own flag, and replay instead of re-rolling.
## - **Passive lines.** Two voices reacting to the same event: file order decides who
##   speaks, the loser keeps its allowance, `once` is per rule, the session cap is per
##   voice, nothing chains, nothing interrupts, and nothing speaks after the end card.
## - **Presentation.** The name and colour of each voice come from that voice's own
##   profile and that voice's own translated name, in both languages.

const Harness = preload("res://tests/test_harness.gd")
const BASE_DIR := "user://multi_voice"
const ABILITY_DIR := BASE_DIR + "/abilities"
const VOICE_DIR := BASE_DIR + "/characters"
## Colours are only compared, never shipped: they prove that two voices cannot share
## one profile's accent by accident.
const COLOUR_A := Color(0.4, 0.5, 0.6, 1.0)
const COLOUR_B := Color(0.7, 0.3, 0.2, 1.0)

var _failures: Array[String] = []
var _game_state: Node = null
var _narrative: Node = null


## The director asks its dialogue controller four questions and no more, so a subclass
## with those four answers is a complete stand-in. Overriding `_ready()` keeps the real
## controller's scene lookups out of a test that has no scene.
class FakeDialogue extends DialogueController:
	var busy := false
	var played: Array[StringName] = []
	var registry: InnerAbilities = null
	var library: DialogueLibrary = null

	func _ready() -> void:
		pass

	func is_busy() -> bool:
		return busy

	func get_abilities() -> InnerAbilities:
		return registry

	func get_dialogue_library() -> DialogueLibrary:
		return library

	func play_conversation(conversation_id: StringName) -> bool:
		played.append(conversation_id)
		# A real controller keeps the line on screen and emits when it ends. Here it ends
		# at once, which also exercises the director's "our own line is not an event to
		# react to" guard: it has to leave `_firing` false without counting an event.
		conversation_finished.emit(conversation_id)
		return true


class FakeSequence extends Node:
	var finished := false
	var beat_active := false

	func is_beat_active() -> bool:
		return beat_active

	func is_slice_finished() -> bool:
		return finished


func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "multi_voice_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	if _game_state == null or _narrative == null:
		Harness.finish(self, ["GameState/NarrativeState are unavailable."], "")
		return
	L10n.set_locale("en")
	Harness.clear_session_state(self)

	Harness.stage = "fixtures"
	if not _write_registry(ABILITY_DIR, _structure(), _texts()):
		Harness.finish(self, _failures, "")
		return
	if not _write_voice("voice_probe_a", "Probe A", COLOUR_A):
		Harness.finish(self, _failures, "")
		return
	if not _write_voice("voice_probe_b", "Probe B", COLOUR_B):
		Harness.finish(self, _failures, "")
		return

	var registry := InnerAbilities.load_all(ABILITY_DIR)
	for message in registry.errors:
		_failures.append("fixture registry: %s" % message)
	if not registry.is_valid():
		Harness.finish(self, _failures, "")
		return
	var directory := CharacterDirectory.load_all(registry, VOICE_DIR)
	for message in directory.errors:
		_failures.append("fixture directory: %s" % message)
	if not directory.errors.is_empty():
		Harness.finish(self, _failures, "")
		return

	Harness.stage = "identity"
	_check_registry(registry, directory)
	Harness.stage = "rejections"
	_check_identity_rejections(registry)
	Harness.stage = "active checks"
	_check_active_checks(registry, directory)
	Harness.stage = "passive lines"
	_check_passive(registry)
	Harness.stage = "presentation"
	_check_presentation(registry, directory)
	Harness.stage = "language switch"
	_check_language_switch(registry, directory)

	Harness.finish(
		self, _failures, "two fixture voices keep their own identity, checks and limits."
	)


# --- fixture data -----------------------------------------------------------


## Two voices, four rules. The rule order here is the priority order: `probe_a` is
## listed before `probe_b` for both events, and the passive cases below depend on it.
func _structure() -> Dictionary:
	return {
		"format_version": 1,
		"max_passive_per_session": 2,
		"abilities": {
			"probe_a": {"value": 2, "speaker": "voice_probe_a", "max_passive": 1},
			"probe_b": {"value": 5, "speaker": "voice_probe_b", "max_passive": 2},
		},
		"passives": [
			{
				"id": "mv_a_notice",
				"ability": "probe_a",
				"trigger": {"kind": "inspection", "id": "mv_thing"},
				"conversation": "voice_notice",
				"once": true,
			},
			{
				"id": "mv_b_notice",
				"ability": "probe_b",
				"trigger": {"kind": "inspection", "id": "mv_thing"},
				"conversation": "voice_hoop",
				"once": true,
			},
			{
				"id": "mv_a_again",
				"ability": "probe_a",
				"trigger": {"kind": "inspection", "id": "mv_other"},
				"conversation": "voice_hoop",
				"once": false,
			},
			{
				"id": "mv_b_again",
				"ability": "probe_b",
				"trigger": {"kind": "inspection", "id": "mv_other"},
				"conversation": "voice_arrival",
				"once": false,
			},
		],
	}


func _texts() -> Dictionary:
	return {
		"en": {
			"format_version": 1,
			"locale": "en",
			"abilities": {
				"probe_a": {
					"name": "Probe A",
					"description": "A test voice that only counts straight edges.",
				},
				"probe_b": {
					"name": "Probe B",
					"description": "A test voice that remembers who stood where.",
				},
			},
		},
		"zh-CN": {
			"format_version": 1,
			"locale": "zh-CN",
			"abilities": {
				"probe_a": {
					"name": "探针甲",
					"description": "一个只数直边的测试声音。",
				},
				"probe_b": {
					"name": "探针乙",
					"description": "一个记得谁站在哪里的测试声音。",
				},
			},
		},
	}


func _write_registry(dir: String, structure: Dictionary, texts: Dictionary) -> bool:
	if not _make_dir(dir):
		return false
	if not _write_json("%s/abilities.json" % dir, structure):
		return false
	for locale: String in L10n.LOCALES:
		var payload: Variant = texts.get(locale, {})
		if not (payload is Dictionary):
			_failures.append("Fixture text for '%s' is not an object." % locale)
			return false
		if not _write_json("%s/%s.json" % [dir, locale], payload):
			return false
	return true


func _write_voice(character_id: String, display_name: String, colour: Color) -> bool:
	if not _make_dir(VOICE_DIR):
		return false
	var profile := CharacterProfile.new()
	profile.character_id = StringName(character_id)
	profile.display_name = display_name
	profile.accent_color = colour
	var path := CharacterDirectory.voice_profile_path(StringName(character_id), VOICE_DIR)
	var result := ResourceSaver.save(profile, path)
	if result != OK:
		_failures.append("Could not write the fixture profile %s (error %d)." % [path, result])
		return false
	return true


func _make_dir(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK and error != ERR_ALREADY_EXISTS:
		_failures.append("Could not create %s (error %d)." % [path, error])
		return false
	return true


func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write %s (error %d)." % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true


# --- identity ---------------------------------------------------------------


func _check_registry(registry: InnerAbilities, directory: CharacterDirectory) -> void:
	if not registry.is_valid():
		_failures.append("The two-voice fixture registry is not valid: %s" % registry.describe_errors())
		return
	var ids := registry.get_ability_ids()
	if ids.size() != 2:
		_failures.append("Expected two fixture voices, found %d." % ids.size())
		return
	# Each voice reads its own number and its own speaker. Reading 2 where 5 belongs is
	# exactly the bug a shared stat would produce.
	if registry.get_value(&"probe_a") != 2:
		_failures.append("probe_a reads %d instead of 2." % registry.get_value(&"probe_a"))
	if registry.get_value(&"probe_b") != 5:
		_failures.append("probe_b reads %d instead of 5." % registry.get_value(&"probe_b"))
	var speakers := registry.get_speaker_ids()
	if speakers.size() != 2:
		_failures.append("Expected two speaker ids, found %d." % speakers.size())
	if registry.get_ability_for_speaker(&"voice_probe_a") != registry.get_ability(&"probe_a"):
		_failures.append("Speaker 'voice_probe_a' does not resolve to probe_a.")
	if registry.get_ability_for_speaker(&"voice_probe_b") != registry.get_ability(&"probe_b"):
		_failures.append("Speaker 'voice_probe_b' does not resolve to probe_b.")
	if registry.get_ability_for_speaker(&"orientation") != null:
		# A shipped speaker must not be reachable from a fixture registry: the resolution
		# is by declared speaker id, never by "the only voice there is".
		_failures.append("A fixture registry resolved a speaker it does not declare.")
	# Profiles: each speaker to its own file, no sharing.
	if not directory.is_inner_voice(&"voice_probe_a"):
		_failures.append("voice_probe_a is not treated as an inner voice.")
	if not directory.is_inner_voice(&"voice_probe_b"):
		_failures.append("voice_probe_b is not treated as an inner voice.")
	if directory.get_accent_color(&"voice_probe_a").is_equal_approx(
		directory.get_accent_color(&"voice_probe_b")
	):
		_failures.append("Two voices resolved to the same profile colour.")
	if not directory.get_accent_color(&"voice_probe_a").is_equal_approx(COLOUR_A):
		_failures.append("voice_probe_a did not load its own profile.")
	if directory.is_inner_voice(&"q"):
		_failures.append("An ordinary character was classified as an inner voice.")
	if registry.get_name_for_speaker(&"voice_probe_a") == registry.get_name_for_speaker(&"voice_probe_b"):
		_failures.append("Two voices show the same name.")


## Each rejection names what a content author has to open: the file, the ability id and
## the speaker id where they exist.
func _check_identity_rejections(registry: InnerAbilities) -> void:
	var duplicate_speaker := _structure()
	var abilities: Dictionary = duplicate_speaker["abilities"]
	(abilities["probe_b"] as Dictionary)["speaker"] = "voice_probe_a"
	_expect_registry_rejection(
		"duplicate speaker",
		duplicate_speaker,
		_texts(),
		["voice_probe_a", "probe_a", "probe_b"],
	)

	var non_numeric := _structure()
	var non_numeric_abilities: Dictionary = non_numeric["abilities"]
	(non_numeric_abilities["probe_a"] as Dictionary)["value"] = "strong"
	_expect_registry_rejection("a non-numeric value", non_numeric, _texts(), ["probe_a", "value"])

	var out_of_range := _structure()
	var out_of_range_abilities: Dictionary = out_of_range["abilities"]
	(out_of_range_abilities["probe_a"] as Dictionary)["value"] = 42
	_expect_registry_rejection("an out-of-range value", out_of_range, _texts(), ["probe_a", "42"])

	var negative_cap := _structure()
	var negative_cap_abilities: Dictionary = negative_cap["abilities"]
	(negative_cap_abilities["probe_b"] as Dictionary)["max_passive"] = -1
	_expect_registry_rejection(
		"a negative passive cap", negative_cap, _texts(), ["probe_b", "max_passive"]
	)

	var missing_translation := _texts()
	((missing_translation["zh-CN"] as Dictionary)["abilities"] as Dictionary).erase("probe_b")
	_expect_registry_rejection(
		"a missing translation", _structure(), missing_translation, ["probe_b", "zh-CN"]
	)

	var copied_translation := _texts()
	var zh_table: Dictionary = copied_translation["zh-CN"]
	var en_table: Dictionary = copied_translation["en"]
	var zh_abilities: Dictionary = zh_table["abilities"]
	var en_abilities: Dictionary = en_table["abilities"]
	(zh_abilities["probe_b"] as Dictionary)["description"] = String(
		(en_abilities["probe_b"] as Dictionary)["description"]
	)
	_expect_registry_rejection(
		"a translation copied from English",
		_structure(),
		copied_translation,
		["probe_b", "not translated"],
	)

	var ghost_text := _texts()
	for locale: String in L10n.LOCALES:
		var table: Dictionary = (ghost_text[locale] as Dictionary)["abilities"]
		table["probe_ghost"] = {"name": "Ghost", "description": "No such voice."}
	var ghost_errors := _load_registry_errors("ghost_text", _structure(), ghost_text)
	if ghost_errors.is_empty():
		_failures.append("Text for an ability that does not exist was accepted.")
	elif not _mentions(ghost_errors, "probe_ghost"):
		_failures.append(
			"Text for an unknown ability was rejected without naming it: %s" % ghost_errors
		)

	# Profiles: missing, borrowed, and colliding with a person.
	var missing_dir := BASE_DIR + "/no_profiles"
	_make_dir(missing_dir)
	var missing := CharacterDirectory.load_all(registry, missing_dir)
	if missing.errors.is_empty():
		_failures.append("A voice with no character profile was accepted.")
	else:
		for needle: String in ["voice_probe_a", "probe_a", missing_dir]:
			if not _mentions(missing.errors, needle):
				_failures.append(
					"A missing voice profile was reported without '%s': %s"
					% [needle, "\n".join(missing.errors)]
				)

	var borrowed_dir := BASE_DIR + "/borrowed_profiles"
	if _make_dir(borrowed_dir):
		var borrowed := CharacterProfile.new()
		borrowed.character_id = &"voice_probe_a"
		borrowed.display_name = "Probe B"
		ResourceSaver.save(
			borrowed, CharacterDirectory.voice_profile_path(&"voice_probe_b", borrowed_dir)
		)
		var borrowed_directory := CharacterDirectory.load_all(registry, borrowed_dir)
		if borrowed_directory.errors.is_empty():
			_failures.append("A profile that declares another speaker's id was accepted.")
		else:
			for needle: String in ["voice_probe_a", "voice_probe_b"]:
				if not _mentions(borrowed_directory.errors, needle):
					_failures.append(
						"A borrowed profile was reported without '%s': %s"
						% [needle, "\n".join(borrowed_directory.errors)]
					)

	var colliding := _structure()
	((colliding["abilities"] as Dictionary)["probe_a"] as Dictionary)["speaker"] = "q"
	var colliding_dir := BASE_DIR + "/colliding_speaker"
	if _write_registry(colliding_dir, colliding, _texts()):
		var colliding_registry := InnerAbilities.load_all(colliding_dir)
		if not colliding_registry.is_valid():
			_failures.append(
				"The collision fixture did not load: %s" % colliding_registry.describe_errors()
			)
		else:
			var colliding_directory := CharacterDirectory.load_all(colliding_registry, VOICE_DIR)
			if colliding_directory.errors.is_empty():
				_failures.append("A voice claiming a person's speaker id was accepted.")
			elif not _mentions(colliding_directory.errors, "ordinary character"):
				_failures.append(
					"A speaker collision was reported without saying so: %s"
					% "\n".join(colliding_directory.errors)
				)


func _expect_registry_rejection(
	label: String, structure: Dictionary, texts: Dictionary, needles: Array
) -> void:
	var errors := _load_registry_errors(label, structure, texts)
	if errors.is_empty():
		_failures.append("The registry accepted %s." % label)
		return
	var joined: String = "\n".join(errors)
	for needle: String in needles:
		if not (needle in joined):
			_failures.append(
				"Rejecting %s produced no error mentioning '%s':\n%s" % [label, needle, joined]
			)


func _load_registry_errors(
	label: String, structure: Dictionary, texts: Dictionary
) -> Array[String]:
	var dir := "%s/case_%s" % [BASE_DIR, label.replace(" ", "_").replace("'", "")]
	var errors: Array[String] = []
	if not _write_registry(dir, structure, texts):
		return errors
	var registry := InnerAbilities.load_all(dir)
	if registry.is_valid():
		return errors
	errors.append_array(registry.errors)
	return errors


func _mentions(messages: Array, needle: String) -> bool:
	for message: Variant in messages:
		if needle in String(message):
			return true
	return false


# --- active checks ----------------------------------------------------------


## Two voices in one conversation. The values differ (2 and 5), one check is visible and
## the other hidden, and both go through the single resolver the game uses.
func _check_active_checks(registry: InnerAbilities, directory: CharacterDirectory) -> void:
	var graph := _write_check_graph()
	if graph == null:
		return
	if not graph.is_valid():
		_failures.append("The two-voice check fixture is invalid: %s" % graph.describe_errors())
		return
	Harness.clear_session_state(self)
	var resolver := CheckResolver.new(4242)
	var runtime := DialogueRuntime.new(_game_state, _narrative, directory, registry, resolver)
	if not runtime.start(graph, &"mv_trial"):
		_failures.append("The two-voice check conversation did not start.")
		return

	var first := runtime.get_last_check()
	if String(first.get("ability", "")) != "probe_a":
		_failures.append("The first check rolled '%s' instead of probe_a." % first.get("ability"))
	if int(first.get("ability_value", -1)) != 2:
		_failures.append("The first check used value %s instead of probe_a's 2." % first.get("ability_value"))
	if String(first.get("kind", "")) != "visible":
		_failures.append("The first check lost its visible kind.")
	if int(first.get("die", -1)) != resolver.dice_total_for("mv_trial/a_roll"):
		_failures.append("The first check did not come from the shared resolver's dice.")
	if not _same_faces(first.get("dice", []), resolver.faces_for("mv_trial/a_roll")):
		_failures.append("The first check reported faces the resolver did not roll.")

	runtime.advance()
	var branch_a := String(runtime.get_current_node_id())
	if branch_a != (&"a_ok" if bool(first.get("success", false)) else &"a_bad"):
		_failures.append("The first check continued to '%s' instead of its own branch." % branch_a)
	runtime.advance()

	var second := runtime.get_last_check()
	if String(second.get("ability", "")) != "probe_b":
		_failures.append("The second check rolled '%s' instead of probe_b." % second.get("ability"))
	if int(second.get("ability_value", -1)) != 5:
		_failures.append("The second check used value %s instead of probe_b's 5." % second.get("ability_value"))
	if String(second.get("kind", "")) != "hidden":
		_failures.append("The second check lost its hidden kind.")
	if int(second.get("die", -1)) != resolver.dice_total_for("mv_trial/b_roll"):
		_failures.append("The hidden check did not come from the shared resolver's dice.")
	if String(first.get("key", "")) == String(second.get("key", "")):
		_failures.append("Two checks shared one resolver key, so one could overwrite the other.")

	runtime.advance()
	var branch_b := String(runtime.get_current_node_id())
	if branch_b != (&"b_ok" if bool(second.get("success", false)) else &"b_bad"):
		_failures.append("The hidden check continued to '%s' instead of its own branch." % branch_b)

	# Records: one flag per check, and neither voice's result is stored under the other.
	var record_a: Variant = _game_state.get_flag(
		StoryFlags.check_record_flag(&"mv_trial", &"a_roll"), null
	)
	var record_b: Variant = _game_state.get_flag(
		StoryFlags.check_record_flag(&"mv_trial", &"b_roll"), null
	)
	if not (record_a is Dictionary) or not (record_b is Dictionary):
		_failures.append("A two-voice conversation did not record both checks.")
		return
	if String((record_a as Dictionary).get("ability", "")) != "probe_a":
		_failures.append("probe_a's record holds another voice's result.")
	if String((record_b as Dictionary).get("ability", "")) != "probe_b":
		_failures.append("probe_b's record holds another voice's result.")
	if int((record_a as Dictionary).get("die", -1)) != int(first.get("die", -2)):
		_failures.append("probe_a's record does not match what was rolled.")

	# Replay with a different seed: the same run cannot reroll either voice.
	var replay := DialogueRuntime.new(_game_state, _narrative, directory, registry, CheckResolver.new(98765))
	replay.start(graph, &"mv_trial")
	var replay_a := replay.get_last_check()
	if not bool(replay_a.get("reused", false)):
		_failures.append("Re-entering the two-voice conversation rolled probe_a again.")
	if int(replay_a.get("die", -1)) != int(first.get("die", -2)):
		_failures.append("probe_a's recorded check changed its dice on replay.")
	replay.advance()
	replay.advance()
	var replay_b := replay.get_last_check()
	if not bool(replay_b.get("reused", false)):
		_failures.append("Re-entering the two-voice conversation rolled probe_b again.")
	if int(replay_b.get("die", -1)) != int(second.get("die", -2)):
		_failures.append("probe_b's recorded check changed its dice on replay.")

	# A language switch is a re-render, not a new roll. The controller rebinds the open
	# conversation to its other-language copy; with two voices in one conversation that
	# must still emit no check and must translate the speaker without touching the dice.
	var zh_graph := _write_check_graph("zh-CN")
	if zh_graph == null:
		return
	if not zh_graph.is_valid():
		_failures.append(
			"The Chinese copy of the two-voice graph is invalid: %s" % zh_graph.describe_errors()
		)
		return
	var events: Array[int] = [0]
	var switched := DialogueRuntime.new(_game_state, _narrative, directory, registry, resolver)
	switched.check_resolved.connect(
		func(_result: Dictionary) -> void: events[0] += 1
	)
	switched.start(graph, &"mv_trial")
	var emitted_before := events[0]
	registry.set_locale("zh-CN")
	if not switched.rebind_graph(zh_graph):
		_failures.append("The two-voice conversation did not rebind to Chinese.")
	if events[0] != emitted_before:
		_failures.append(
			"Switching language resolved %d more check(s)." % (events[0] - emitted_before)
		)
	var zh_line := switched.get_current_line()
	if String(zh_line.get("speaker_name", "")) != "探针甲":
		_failures.append(
			"The rebind did not translate the speaking voice's name: '%s'."
			% zh_line.get("speaker_name")
		)
	registry.set_locale("en")


func _same_faces(actual: Variant, expected: Array[int]) -> bool:
	if not (actual is Array):
		return false
	var faces: Array = actual
	if faces.size() != expected.size():
		return false
	for index in faces.size():
		if int(faces[index]) != expected[index]:
			return false
	return true


## The fixture lines, in both languages, so the same graph can be rebound the way the
## dialogue controller rebinds real content. Nothing here is canon: these are two test
## voices that only exist inside this file.
const FIXTURE_LINES := {
	"en": {
		"a_roll": "A looks at the frame.",
		"a_ok": "A is sure of the frame.",
		"a_bad": "A cannot place the frame.",
		"b_roll": "B counts the steps.",
		"b_ok": "B counts them the same way twice.",
		"b_bad": "B loses count.",
		"q_line": "Q waits by the door.",
	},
	"zh-CN": {
		"a_roll": "甲看了看门框。",
		"a_ok": "甲对门框很有把握。",
		"a_bad": "甲说不准门框在哪。",
		"b_roll": "乙数着台阶。",
		"b_ok": "乙数了两遍，结果一样。",
		"b_bad": "乙数乱了。",
		"q_line": "Q 在门边等着。",
	},
}


## A conversation with one check per voice, both reachable, both branching into a plain
## line that ends.
func _write_check_graph(locale: String = "en") -> DialogueGraph:
	var lines: Dictionary = FIXTURE_LINES.get(locale, {})
	var data := {
		"format_version": 2,
		"locale": locale,
		"chapter": "mv",
		"conversations": {
			"mv_trial": {
				"default_source": "observed",
				"start": "a_roll",
				"nodes": [
					{
						"id": "a_roll",
						"speaker": "voice_probe_a",
						"text": String(lines.get("a_roll", "A looks at the frame.")),
						"check": {
							"ability": "probe_a",
							"difficulty": 7,
							"kind": "visible",
							"success": "a_ok",
							"failure": "a_bad",
						},
					},
					{
						"id": "a_ok",
						"speaker": "voice_probe_a",
						"text": String(lines.get("a_ok", "A is sure of the frame.")),
						"next": "b_roll",
					},
					{
						"id": "a_bad",
						"speaker": "voice_probe_a",
						"text": String(lines.get("a_bad", "A cannot place the frame.")),
						"next": "b_roll",
					},
					{
						"id": "b_roll",
						"speaker": "voice_probe_b",
						"text": String(lines.get("b_roll", "B counts the steps.")),
						"check": {
							"ability": "probe_b",
							"difficulty": 9,
							"kind": "hidden",
							"success": "b_ok",
							"failure": "b_bad",
						},
					},
					{
						"id": "b_ok",
						"speaker": "voice_probe_b",
						"text": String(lines.get("b_ok", "B counts them the same way twice.")),
						"next": "q_line",
					},
					{
						"id": "b_bad",
						"speaker": "voice_probe_b",
						"text": String(lines.get("b_bad", "B loses count.")),
						"next": "q_line",
					},
					{
						"id": "q_line",
						"speaker": "q",
						"text": String(lines.get("q_line", "Q waits by the door.")),
						"next": null,
					},
				],
			}
		},
	}
	var path := _check_graph_path(locale)
	if not _make_dir(BASE_DIR):
		return null
	if not _write_json(path, data):
		return null
	return DialogueGraph.load_from_file(path)


# --- passive lines ----------------------------------------------------------


func _check_graph_path(locale: String) -> String:
	return "%s/mv_checks_%s.json" % [BASE_DIR, locale]


## The passive half, driven without a scene: the director is a plain node in the tree
## (it needs the flags), its dialogue controller is a four-answer stand-in, and the
## frames are taken by calling `pump()` instead of waiting for `_process`.
func _check_passive(registry: InnerAbilities) -> void:
	Harness.clear_session_state(self)
	var fake := FakeDialogue.new()
	fake.name = "DialogueController"
	fake.registry = registry
	fake.library = DialogueLibrary.load_all()
	if not fake.library.is_valid():
		_failures.append(
			"The dialogue library the rules point at did not load: %s"
			% fake.library.describe_errors()
		)
		return
	var holder := Node.new()
	get_root().add_child(holder)
	holder.add_child(fake)
	var director := InnerVoiceDirector.new()
	holder.add_child(director)
	# The director pumps on its own otherwise, which would make the order of these
	# assertions depend on when the engine happens to tick.
	director.set_process(false)
	if director.get_abilities() != registry:
		_failures.append("The director did not take the fixture registry from its controller.")

	# 1. A conversation is running: the event waits, it is not dropped and not shown.
	fake.busy = true
	director._on_inspection_presented(&"mv_other")
	if director.pending_count() != 1:
		_failures.append("An event during a conversation was not queued.")
	var queued := director.get_pending_event()
	if String(queued.get("kind", "")) != "inspection" or String(queued.get("id", "")) != "mv_other":
		_failures.append("The queued event is '%s', not the one that happened." % str(queued))
	if _selected_rule(director, "inspection", &"mv_other") != &"mv_a_again":
		_failures.append("The first rule in file order did not win the event.")
	director.pump()
	if not fake.played.is_empty():
		_failures.append("A voice spoke while a conversation was on screen.")
	fake.busy = false
	director.pump()
	# probe_a is listed first and its cap is 1, so it speaks and is then spent.
	_expect_counts("first event", {"probe_a": 1, "probe_b": 0})
	if fake.played.size() != 1 or fake.played[0] != &"voice_hoop":
		_failures.append("The wrong conversation played for the first event: %s" % [fake.played])
	if director.pending_count() != 0:
		_failures.append("A consumed event is still queued.")

	# 2. Nothing has happened since that line, so a second one cannot chain onto it.
	director.request("inspection", &"mv_other")
	director.pump()
	if director.pending_count() != 0 or fake.played.size() != 1:
		_failures.append("Two unprompted lines played back to back.")

	# 3. The next event reaches the voice that still has allowance: probe_a is at its
	#    cap of 1, probe_b is not, and the cap of one voice did not spend the other's.
	director._on_inspection_presented(&"mv_other")
	if _selected_rule(director, "inspection", &"mv_other") != &"mv_b_again":
		_failures.append("A capped voice still won the event.")
	director.pump()
	_expect_counts("second event", {"probe_a": 1, "probe_b": 1})
	if fake.played.size() != 2 or fake.played[1] != &"voice_arrival":
		_failures.append("The second voice played the wrong line: %s" % [fake.played])

	# 4. probe_b's own cap is 2, so it may speak once more; after that both voices are
	#    done and an event with nobody left is not queued at all.
	director._on_inspection_presented(&"mv_other")
	director.pump()
	_expect_counts("third event", {"probe_a": 1, "probe_b": 2})
	director._on_inspection_presented(&"mv_other")
	if director.pending_count() != 0:
		_failures.append("An event with no voice left was queued.")
	director.pump()
	if fake.played.size() != 3:
		_failures.append("A voice spoke past its session cap: %s" % [fake.played])

	# 5. Priority, stated from a clean state: both voices are eligible for the same
	#    event and the one listed first in abilities.json speaks.
	Harness.clear_session_state(self)
	fake.played.clear()
	director._on_inspection_presented(&"mv_thing")
	if _selected_rule(director, "inspection", &"mv_thing") != &"mv_a_notice":
		_failures.append("Two eligible voices did not resolve by file order.")
	director.pump()
	if fake.played.size() != 1 or fake.played[0] != &"voice_notice":
		_failures.append("The earlier rule did not play its own conversation: %s" % [fake.played])
	_expect_counts("deterministic winner", {"probe_a": 1, "probe_b": 0})
	if bool(_flag(StoryFlags.passive_fired_flag(&"mv_a_notice"), false)) != true:
		_failures.append("A fired `once` rule was not marked as spent.")
	if bool(_flag(StoryFlags.passive_fired_flag(&"mv_b_notice"), false)) == true:
		_failures.append("The rule that did not fire was marked as spent.")
	if director.pending_count() != 0:
		_failures.append("One event queued the same line twice.")

	# 6. The same event again: the winner's rule is spent, so the other voice answers.
	director._on_inspection_presented(&"mv_thing")
	if _selected_rule(director, "inspection", &"mv_thing") != &"mv_b_notice":
		_failures.append("A spent `once` rule was picked again.")
	director.pump()
	_expect_counts("second identical event", {"probe_a": 1, "probe_b": 1})
	if fake.played.size() != 2 or fake.played[1] != &"voice_hoop":
		_failures.append("The second voice did not answer the repeat event: %s" % [fake.played])

	# 7. An authored beat owns the frame, then the end card does. Neither is interrupted,
	#    and neither is permanent: once the beat ends the queued event still plays.
	var sequence := FakeSequence.new()
	holder.add_child(sequence)
	director._sequence = sequence
	Harness.clear_session_state(self)
	fake.played.clear()
	sequence.beat_active = true
	director._on_inspection_presented(&"mv_thing")
	director.pump()
	if not fake.played.is_empty():
		_failures.append("A voice interrupted an authored beat.")
	sequence.beat_active = false
	director.pump()
	if fake.played.size() != 1:
		_failures.append("An event queued during a beat was lost.")

	Harness.clear_session_state(self)
	fake.played.clear()
	sequence.finished = true
	director._on_inspection_presented(&"mv_thing")
	if director.pending_count() != 0:
		_failures.append("An event was queued after the end card.")
	director.pump()
	if not fake.played.is_empty():
		_failures.append("A voice spoke after the end of the slice.")

	holder.queue_free()


## `select_rule()` returns null when nothing may speak, and a null rule in an assertion
## would crash the test instead of reporting it.
func _selected_rule(
	director: InnerVoiceDirector, trigger_kind: String, trigger_id: StringName
) -> StringName:
	var rule := director.select_rule(trigger_kind, trigger_id)
	return rule.rule_id if rule != null else &""


func _expect_counts(label: String, expected: Dictionary) -> void:
	for ability_id: Variant in expected.keys():
		var flag := StoryFlags.passive_count_flag(StringName(String(ability_id)))
		var actual := int(_flag(flag, 0))
		if actual != int(expected[ability_id]):
			_failures.append(
				"%s: voice '%s' has spoken %d time(s), expected %d."
				% [label, ability_id, actual, expected[ability_id]]
			)


# --- presentation -----------------------------------------------------------


## The panel builds every line through `DialogueRuntime.compose_line()`, so that is
## where a shared name or a shared colour would show up.
func _check_presentation(registry: InnerAbilities, directory: CharacterDirectory) -> void:
	var graph := DialogueGraph.load_from_file(_check_graph_path("en"))
	if graph == null:
		_failures.append("The check fixture could not be re-read for the presentation cases.")
		return
	var conversation: DialogueGraph.Conversation = graph.get_conversation(&"mv_trial")
	if conversation == null:
		_failures.append("The check fixture lost its conversation.")
		return
	registry.set_locale("en")
	var line_a := DialogueRuntime.compose_line(
		conversation, conversation.nodes[&"a_ok"], directory, registry
	)
	var line_b := DialogueRuntime.compose_line(
		conversation, conversation.nodes[&"b_ok"], directory, registry
	)
	if String(line_a.get("speaker_name", "")) != "Probe A":
		_failures.append("The first voice showed '%s'." % line_a.get("speaker_name"))
	if String(line_b.get("speaker_name", "")) != "Probe B":
		_failures.append("The second voice showed '%s'." % line_b.get("speaker_name"))
	if not Color(line_a.get("accent_color", Color.BLACK)).is_equal_approx(COLOUR_A):
		_failures.append("The first voice drew in the wrong colour.")
	if not Color(line_b.get("accent_color", Color.BLACK)).is_equal_approx(COLOUR_B):
		_failures.append("The second voice drew in the wrong colour.")
	if StringName(String(line_b.get("speaker_id", ""))) != &"voice_probe_b":
		_failures.append("A voice line lost its speaker id.")

	# An ordinary character in the same conversation is still an ordinary character.
	var line_q := DialogueRuntime.compose_line(
		conversation, conversation.nodes[&"q_line"], directory, registry
	)
	if String(line_q.get("speaker_name", "")) == "q":
		_failures.append("An ordinary character was presented by its raw id.")
	if String(line_q.get("speaker_role", "")) != "classmate":
		_failures.append(
			"An ordinary character lost its role ('%s')." % line_q.get("speaker_role")
		)

	# The translated name is the ability's translated name, in the active language.
	registry.set_locale("zh-CN")
	var zh_a := DialogueRuntime.compose_line(
		conversation, conversation.nodes[&"a_ok"], directory, registry
	)
	if String(zh_a.get("speaker_name", "")) != "探针甲":
		_failures.append("The Chinese name of the first voice is '%s'." % zh_a.get("speaker_name"))
	if not Color(zh_a.get("accent_color", Color.BLACK)).is_equal_approx(COLOUR_A):
		_failures.append("Switching language changed a voice's colour.")
	registry.set_locale("en")


# --- language switch --------------------------------------------------------


## Switching language re-translates prose and nothing else: not the ids, not the
## numbers, not the passive bookkeeping.
func _check_language_switch(registry: InnerAbilities, directory: CharacterDirectory) -> void:
	Harness.clear_session_state(self)
	_game_state.set_flag(StoryFlags.passive_count_flag(&"probe_a"), 1)
	_game_state.set_flag(StoryFlags.passive_fired_flag(&"mv_a_notice"), true)
	var ids_before := registry.get_ability_ids()
	var speakers_before := registry.get_speaker_ids()
	registry.set_locale("zh-CN")
	registry.set_locale("en")
	registry.set_locale("zh-CN")
	if registry.get_ability_ids() != ids_before:
		_failures.append("Switching language changed the set of inner voices.")
	if registry.get_speaker_ids() != speakers_before:
		_failures.append("Switching language changed the speaker ids.")
	if registry.get_value(&"probe_a") != 2 or registry.get_value(&"probe_b") != 5:
		_failures.append("Switching language changed an ability value.")
	if int(_flag(StoryFlags.passive_count_flag(&"probe_a"), 0)) != 1:
		_failures.append("Switching language reset a voice's passive count.")
	if bool(_flag(StoryFlags.passive_fired_flag(&"mv_a_notice"), false)) != true:
		_failures.append("Switching language forgot that a rule had fired.")
	if not directory.get_accent_color(&"voice_probe_a").is_equal_approx(COLOUR_A):
		_failures.append("Switching language changed a profile.")
	registry.set_locale("en")
	Harness.clear_session_state(self)


func _flag(flag: StringName, default_value: Variant) -> Variant:
	return _game_state.get_flag(flag, default_value)

extends SceneTree
## Proves the inner-voice registry is complete, bilingual, and connected to content.
##
## An ability is not "implemented" because a value exists. It is implemented when:
##
## - it has a stable id, a value, and a speaker of its own, whose profile exists;
## - its name and description exist in every language and actually differ between
##   them (a copied English string in the Chinese table is a translation bug that no
##   structural check would catch);
## - its passive rules have real triggers and start with the correct voice's hidden
##   check in every language;
## - each authored check keeps its semantic owner; the one reserved voice stays
##   registered without inventing an unrelated check to make a coverage number;
## - the runtime presentation uses the translated name, not the raw id.

const Harness = preload("res://tests/test_harness.gd")
const VoiceMigration = preload("res://scripts/rpg/inner_voice_migration.gd")
const EXPECTED_NAMES := {
	&"insight": ["Insight", "洞察"],
	&"scrutiny": ["Scrutiny", "细察"],
	&"echo": ["Echo", "回声"],
	&"imagination": ["Imagination", "臆想"],
	&"inference": ["Inference", "推演"],
	&"resonance": ["Resonance", "共鸣"],
}
## Independent content contract, not read from the production migration table.
const CHECK_OWNERS := {
	"voice_notice/vn_1": &"insight",
	"voice_arrival/va_1": &"inference",
	"voice_hoop/vh_1": &"scrutiny",
	"pg_shed/ps_boundary_check": &"scrutiny",
	"pg_shed/ps_ledger_check": &"scrutiny",
	"pg_ball/pb_boundary_check": &"scrutiny",
	"pg_ball/pb_ledger_check": &"inference",
	"pg_roof_jump/prj_check": &"inference",
	"q_after_dismissal/ad_square_check": &"echo",
	"expected_b/e3_whimsy": &"imagination",
	"classroom_curtain/cc_edges_check": &"scrutiny",
	"classroom_curtain_void/cv_balance_check": &"scrutiny",
	"classroom_rear_door_borrow/rdb_check": &"inference",
	"align_archive/bearing": &"inference",
	"align_plan_room/bearing": &"inference",
	"align_projection_room/bearing": &"scrutiny",
	"align_computer_room/bearing": &"inference",
	"align_vacant_office/bearing": &"scrutiny",
	"align_principal_office/bearing": &"inference",
}
const PREPARATIONS := {
	"q_after_dismissal/ad_square_check": "saw_set_square",
	"classroom_curtain/cc_edges_check": "seen:classroom_window",
	"classroom_curtain_void/cv_balance_check": "curtain_edges_examined",
	"pg_shed/ps_ledger_check": "seen:staff_office_rota",
	"pg_ball/pb_boundary_check": "playground_shadow_measured",
}

var _failures: Array[String] = []
var _abilities: InnerAbilities = null
var _library: DialogueLibrary = null
var _characters: CharacterDirectory = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "inner_abilities_test.gd")
	call_deferred("_run")


func _run() -> void:
	# The registry loads in the active language, and the active language can be whatever
	# the last session left in user://settings.cfg. Pin it, so "English first, then
	# Chinese" is a fact of this test rather than of the machine it runs on.
	L10n.set_locale("en")
	_abilities = InnerAbilities.load_all()
	if not _abilities.is_valid():
		Harness.finish(self, ["abilities: " + _abilities.describe_errors()], "")
		return
	_library = DialogueLibrary.load_all(_abilities)
	if not _library.is_valid():
		_failures.append("shipped dialogue is invalid: %s" % _library.describe_errors())
	# The directory resolves inner voices from this registry, so a voice with no profile
	# (or with someone else's) shows up here instead of in a scene.
	_characters = CharacterDirectory.load_all(_abilities)
	for message in _characters.errors:
		_failures.append("character directory: %s" % message)

	_check_shape()
	_check_bilingual()
	_check_rules()
	_check_coverage()
	_check_presentation_names()
	_check_shipped_allocations()

	Harness.finish(self, _failures, "six voices are registered and translated; all 19 checks keep their reviewed owner.")


# --- cases ------------------------------------------------------------------


func _check_shape() -> void:
	var ids := _abilities.get_ability_ids()
	# Pin the owner's content roster here, not in the generic loader: the isolated
	# two-voice fixtures still prove that the plumbing is not hard-coded to six.
	var expected: Array = EXPECTED_NAMES.keys()
	expected.sort()
	if ids != expected:
		_failures.append("The shipped roster is not exactly the owner's six voices: %s." % str(ids))
	for retired: StringName in [&"orientation", &"whimsy"]:
		if _abilities.has_ability(retired) or _abilities.get_ability_for_speaker(
			StringName("voice_%s" % retired)
		) != null:
			_failures.append("A retired voice is still registered or aliased: %s." % retired)
		if FileAccess.file_exists("res://data/characters/voice_%s.tres" % retired):
			_failures.append("A retired character profile still ships: %s." % retired)
	var speakers: Dictionary = {}
	for ability_id: StringName in ids:
		var ability := _abilities.get_ability(ability_id)
		if String(ability_id).is_empty():
			_failures.append("An inner voice has an empty id.")
		if ability.value < InnerAbilities.MIN_VALUE or ability.value > InnerAbilities.MAX_VALUE:
			_failures.append(
				"Ability '%s' has a value (%d) outside %d..%d."
				% [ability_id, ability.value, InnerAbilities.MIN_VALUE, InnerAbilities.MAX_VALUE]
			)
		if _abilities.get_value(ability_id) != ability.value:
			_failures.append("Ability '%s' does not read back its own value." % ability_id)
		if ability.value != 3:
			_failures.append("Registry migration changed the provisional base value for %s." % ability_id)
		if not VoiceDirector.SPEAKER_PROFILES.has(ability.speaker_id):
			_failures.append("No acoustic preset is registered for %s." % ability.speaker_id)
		# The speaker is the only link between a voice and its presentation, so it has
		# to be unique and to point back at this exact ability.
		if String(ability.speaker_id).is_empty():
			_failures.append("Ability '%s' has an empty speaker id." % ability_id)
		elif speakers.has(ability.speaker_id):
			_failures.append(
				"Abilities '%s' and '%s' claim the same speaker '%s'."
				% [speakers[ability.speaker_id], ability_id, ability.speaker_id]
			)
		else:
			speakers[ability.speaker_id] = ability_id
		if _abilities.get_ability_for_speaker(ability.speaker_id) != ability:
			_failures.append(
				"Speaker '%s' does not resolve back to ability '%s'."
				% [ability.speaker_id, ability_id]
			)
		if _characters != null:
			var profile := _characters.get_profile(ability.speaker_id)
			if profile == null:
				_failures.append(
					"Ability '%s' has no character profile for '%s'."
					% [ability_id, ability.speaker_id]
				)
			elif profile.character_id != ability.speaker_id:
				_failures.append(
					"Ability '%s' resolved to a profile for '%s'."
					% [ability_id, profile.character_id]
				)
			if not _characters.is_inner_voice(ability.speaker_id):
				_failures.append(
					"Speaker '%s' is a voice but the directory does not treat it as one."
					% ability.speaker_id
				)
		if ability.max_passive < 1:
			_failures.append("Ability '%s' can never speak passively." % ability_id)
		# The display name is what the panel shows; an id or an empty string would leak
		# the data model into the interface.
		if ability.display_name.strip_edges().is_empty():
			_failures.append("Ability '%s' displays no name." % ability_id)
		elif ability.display_name == String(ability_id):
			_failures.append("Ability '%s' displays its raw id instead of a name." % ability_id)
	if _characters != null and _characters.is_inner_voice(&"q"):
		_failures.append("An ordinary classmate was loaded as an inner voice.")


## Every language must carry the same voices, with text that is not just the English
## string copied across. The second half matters: structure checks pass happily on a
## translation nobody did.
func _check_bilingual() -> void:
	var ids := _abilities.get_ability_ids()
	var english: Dictionary = {}
	var english_descriptions: Dictionary = {}
	var identity: Dictionary = {}
	for ability_id: StringName in ids:
		english[ability_id] = _abilities.get_ability(ability_id).display_name
		if EXPECTED_NAMES.has(ability_id) and english[ability_id] != EXPECTED_NAMES[ability_id][0]:
			_failures.append("The English name changed for %s." % ability_id)
		english_descriptions[ability_id] = _abilities.get_ability(ability_id).description
		if _abilities.get_ability(ability_id).description.strip_edges().is_empty():
			_failures.append("Ability '%s' has no description in the active language." % ability_id)
		# Numbers and speaker ids are not translated; only the prose is.
		identity[ability_id] = _abilities.get_value(ability_id)
	if not _abilities.set_locale("zh-CN"):
		_failures.append("Switching the ability registry to zh-CN failed.")
		return
	for ability_id: StringName in ids:
		var ability := _abilities.get_ability(ability_id)
		var zh_name := ability.display_name
		if EXPECTED_NAMES.has(ability_id) and zh_name != EXPECTED_NAMES[ability_id][1]:
			_failures.append("The Chinese name changed for %s." % ability_id)
		if zh_name.strip_edges().is_empty():
			_failures.append("Ability '%s' has no Chinese name." % ability_id)
		if zh_name == String(english[ability_id]):
			_failures.append(
				"Ability '%s' is called '%s' in both languages; the Chinese table was not translated."
				% [ability_id, zh_name]
			)
		if ability.description.strip_edges().is_empty():
			_failures.append("Ability '%s' has no Chinese description." % ability_id)
		elif ability.description == String(english_descriptions.get(ability_id, "")):
			_failures.append(
				"Ability '%s' has the English description in the Chinese table." % ability_id
			)
		if _abilities.get_value(ability_id) != int(identity[ability_id]):
			_failures.append("Switching language changed the value of '%s'." % ability_id)
	if _abilities.get_name_for_speaker(&"q") != "":
		_failures.append("An ordinary classmate was resolved as an inner voice in Chinese.")
	_abilities.set_locale("en")
	for ability_id: StringName in ids:
		if _abilities.get_ability(ability_id).display_name != String(english[ability_id]):
			_failures.append(
				"Switching back to English did not restore the name of '%s'." % ability_id
			)


func _check_rules() -> void:
	if _library == null:
		_failures.append("Passive rules cannot be checked without a loaded dialogue library.")
		return
	var rules := _abilities.get_rules()
	# Keep the three authored rules and their save identities. Registration alone
	# does not author more interruptions for the other voices.
	if rules.size() != VoiceMigration.PASSIVE_OWNERS.size():
		_failures.append("The three authored passive rules changed identity or count.")
	var seen: Dictionary = {}
	for rule: InnerAbilities.PassiveRule in rules:
		if seen.has(rule.rule_id):
			_failures.append("Passive rule '%s' is defined twice." % rule.rule_id)
		seen[rule.rule_id] = true
		if VoiceMigration.PASSIVE_OWNERS.get(rule.rule_id) != rule.ability_id:
			_failures.append("Passive '%s' lost its reviewed owner." % rule.rule_id)
		if not _abilities.has_ability(rule.ability_id):
			_failures.append("Rule '%s' names unknown voice '%s'." % [rule.rule_id, rule.ability_id])
		if not InnerAbilities.TRIGGER_KINDS.has(rule.trigger_kind):
			_failures.append("Rule '%s' has trigger kind '%s'." % [rule.rule_id, rule.trigger_kind])

	var inspections := InspectionLibrary.load_all()
	var locations := LocationCatalog.load_all()
	var previous_locale := _library.get_locale()
	for locale: String in L10n.LOCALES:
		if not _library.set_locale(locale) or not inspections.set_locale(locale):
			_failures.append("Could not check passive rules in %s." % locale)
			continue
		for rule: InnerAbilities.PassiveRule in rules:
			_check_rule_link(rule, inspections, locations, locale)
	_library.set_locale(previous_locale)


func _check_rule_link(
	rule: InnerAbilities.PassiveRule, inspections: InspectionLibrary,
	locations: LocationCatalog, locale: String
) -> void:
	var trigger_exists := false
	match rule.trigger_kind:
		"inspection":
			trigger_exists = inspections.has_inspection(rule.trigger_id)
		"location":
			trigger_exists = locations.get_entry(rule.trigger_id) != null
		"conversation_end":
			trigger_exists = _library.has_conversation(rule.trigger_id)
	var label := "%s: passive '%s'" % [locale, rule.rule_id]
	if not trigger_exists:
		_failures.append("%s has no %s trigger '%s'." % [label, rule.trigger_kind, rule.trigger_id])
	var conversation := _library.get_conversation(rule.conversation_id)
	if conversation == null:
		_failures.append("%s points at missing conversation '%s'." % [label, rule.conversation_id])
		return
	var node: DialogueGraph.DialogueNode = conversation.nodes.get(conversation.start_id, null)
	if node == null or String(node.check.get("kind", "")) != "hidden":
		_failures.append("%s: '%s' must open with a hidden check." % [label, rule.conversation_id])
		return
	var ability := _abilities.get_ability(rule.ability_id)
	if ability != null and (node.check.get("ability") != rule.ability_id or node.speaker_id != ability.speaker_id):
		_failures.append("%s: '%s' must open with its own voice's check." % [label, rule.conversation_id])


## Authored checks must use their own voice; resonance is registered but deliberately
## awaits interpersonal content. Giving a spatial check its name would mislead a player
## unless the test compares the identities.
func _check_coverage() -> void:
	if _library == null:
		return
	var used: Dictionary = {}
	for rule: InnerAbilities.PassiveRule in _abilities.get_rules():
		used[rule.ability_id] = true
	var graphs := _library.get_graphs_for(_library.get_locale())
	if graphs.is_empty():
		_failures.append("No dialogue chapters loaded for the active language.")
	for graph: DialogueGraph in graphs:
		for conversation_id: StringName in graph.get_conversation_ids():
			var conversation: DialogueGraph.Conversation = graph.get_conversation(conversation_id)
			for node_id: StringName in conversation.order:
				var node: DialogueGraph.DialogueNode = conversation.nodes[node_id]
				if node.check.is_empty():
					continue
				var ability_id: StringName = node.check.get("ability", &"")
				used[ability_id] = true
				if not _abilities.has_ability(ability_id):
					_failures.append(
						"%s/%s rolls on unknown voice '%s'." % [conversation_id, node_id, ability_id]
					)
				for target: StringName in node.check_targets:
					if not conversation.nodes.has(target):
						_failures.append(
							"%s/%s continues to missing node '%s'."
							% [conversation_id, node_id, target]
						)
	for ability_id: StringName in _abilities.get_ability_ids():
		if ability_id == &"resonance":
			if used.has(ability_id):
				_failures.append("An unauthorised interpersonal check was added to fill resonance coverage.")
		elif not used.has(ability_id):
			_failures.append("Authored voice '%s' lost its reachable content." % ability_id)


func _check_presentation_names() -> void:
	for ability_id: StringName in _abilities.get_ability_ids():
		var ability := _abilities.get_ability(ability_id)
		var resolved := _abilities.get_name_for_speaker(ability.speaker_id)
		if resolved != ability.display_name:
			_failures.append(
				"Speaker '%s' does not resolve to its translated name ('%s')."
				% [ability.speaker_id, ability.display_name]
			)
		var profile := _characters.get_profile(ability.speaker_id) if _characters != null else null
		if profile != null and _characters.get_localized_name(ability.speaker_id).is_empty():
			_failures.append(
				"Speaker '%s' has a profile but no name to show." % ability.speaker_id
			)
	if not _abilities.get_name_for_speaker(&"q").is_empty():
		_failures.append("An ordinary classmate was resolved as an inner voice.")


## Every existing attempt is reviewed independently. Replacing a whole chapter with
## insight, adding a sixth kind of check, or moving an old save key must fail here.
func _check_shipped_allocations() -> void:
	if VoiceMigration.CHECK_ABILITIES.size() != CHECK_OWNERS.size():
		_failures.append("The compatibility map does not cover exactly the 19 shipped attempts.")
	for locale: String in L10n.LOCALES:
		_abilities.set_locale(locale)
		var found: Dictionary = {}
		for graph: DialogueGraph in _library.get_graphs_for(locale):
			for conversation_id: StringName in graph.get_conversation_ids():
				var conversation := graph.get_conversation(conversation_id)
				for node_id: StringName in conversation.order:
					var node: DialogueGraph.DialogueNode = conversation.nodes[node_id]
					if node.speaker_id in [&"voice_orientation", &"voice_whimsy"]:
						_failures.append("%s: retired speaker in %s/%s." % [locale, conversation_id, node_id])
					if node.check.is_empty():
						continue
					var key := "%s/%s" % [conversation_id, node_id]
					found[key] = true
					if not CHECK_OWNERS.has(key):
						_failures.append("Unreviewed check added: %s/%s." % [locale, key])
						continue
					var expected: StringName = CHECK_OWNERS[key]
					if node.check["ability"] != expected:
						_failures.append("%s/%s should use %s, not %s." % [locale, key, expected, node.check["ability"]])
					var flag := StoryFlags.check_record_flag(conversation_id, node_id)
					if VoiceMigration.CHECK_ABILITIES.get(flag) != expected:
						_failures.append("The saved result for %s migrates to another voice." % key)
					if _characters.is_inner_voice(node.speaker_id) and node.speaker_id != StringName("voice_%s" % expected):
						_failures.append("The speaker and check disagree in %s/%s." % [locale, key])
					if _characters.is_inner_voice(node.speaker_id):
						var line := DialogueRuntime.compose_line(conversation, node, _characters, _abilities)
						if line.get("speaker_name") != _abilities.get_ability(expected).display_name:
							_failures.append("%s/%s does not display its translated voice name." % [locale, key])
					var modifiers: Array = node.check.get("modifiers", [])
					if PREPARATIONS.has(key):
						if modifiers.size() != 1 or String(modifiers[0].get("flag", "")) != PREPARATIONS[key] \
								or int(modifiers[0].get("value", 0)) != 1:
							_failures.append("%s/%s lost its one specific +1 preparation." % [locale, key])
					elif not modifiers.is_empty():
						_failures.append("An unreviewed preparation was added in %s/%s." % [locale, key])
		if found.size() != CHECK_OWNERS.size():
			_failures.append("%s has %d checks, expected %d stable identities." % [locale, found.size(), CHECK_OWNERS.size()])
	_abilities.set_locale("en")

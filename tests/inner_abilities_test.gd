extends SceneTree
## Proves the inner-voice registry is complete, bilingual, and connected to content.
##
## An ability is not "implemented" because a value exists. It is implemented when:
##
## - it has a stable id, a value, and a speaker of its own, whose profile exists;
## - its name and description exist in every language and actually differ between
##   them (a copied English string in the Chinese table is a translation bug that no
##   structural check would catch);
## - its passive rules point at conversations that exist;
## - it is reachable in shipped content, either through a passive rule or through a
##   check the player can choose;
## - the runtime presentation uses the translated name, not the raw id.

const Harness = preload("res://tests/test_harness.gd")

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

	Harness.finish(self, _failures, "every inner voice is valued, translated, and used.")


# --- cases ------------------------------------------------------------------


func _check_shape() -> void:
	var ids := _abilities.get_ability_ids()
	# How many voices ship is a content decision, so this test does not pin the count:
	# it pins that each registered voice is complete on its own. The multi-voice
	# plumbing itself is exercised with fixture voices in tests/multi_voice_test.gd.
	if ids.is_empty():
		_failures.append("No inner voice is registered at all.")
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
	# Three rules are enough to prove the mechanism with the voice that ships: an
	# inspection trigger, a second inspection trigger, and a location trigger. Fewer
	# would mean a voice that never speaks unprompted.
	if rules.size() < 3:
		_failures.append("Expected at least three passive rules, found %d." % rules.size())
	var seen: Dictionary = {}
	for rule: InnerAbilities.PassiveRule in rules:
		if seen.has(rule.rule_id):
			_failures.append("Passive rule '%s' is defined twice." % rule.rule_id)
		seen[rule.rule_id] = true
		if not _abilities.has_ability(rule.ability_id):
			_failures.append("Rule '%s' names unknown voice '%s'." % [rule.rule_id, rule.ability_id])
		if not InnerAbilities.TRIGGER_KINDS.has(rule.trigger_kind):
			_failures.append("Rule '%s' has trigger kind '%s'." % [rule.rule_id, rule.trigger_kind])
		var graph := _library.get_graph(rule.conversation_id)
		if graph == null:
			_failures.append(
				"Rule '%s' points at missing conversation '%s'." % [rule.rule_id, rule.conversation_id]
			)
		else:
			var start := graph.get_conversation(rule.conversation_id).start_id
			var node: DialogueGraph.DialogueNode = (
				graph.get_conversation(rule.conversation_id).nodes.get(start, null)
			)
			if node == null or node.check.is_empty():
				_failures.append(
					"Passive conversation '%s' must open with a hidden check." % rule.conversation_id
				)
			elif String(node.check.get("kind", "")) != "hidden":
				_failures.append(
					"Passive conversation '%s' opens with a visible check; passive rolls are hidden."
					% rule.conversation_id
				)


## Each voice must be reachable in shipped content, and only through itself: a check
## labelled 'orientation' that actually rolls something else would be invisible to a player
## and to this test unless the ids are compared.
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
		if not used.has(ability_id):
			_failures.append(
				"Voice '%s' exists but nothing in the content ever uses it." % ability_id
			)


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

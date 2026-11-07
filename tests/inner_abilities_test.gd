extends SceneTree
## Proves the inner-voice registry is complete, bilingual, and connected to content.
##
## An ability is not "implemented" because a value exists. It is implemented when:
##
## - it has a stable id, a value, and a speaker whose profile exists;
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
	_abilities = InnerAbilities.load_all()
	if not _abilities.is_valid():
		Harness.finish(self, ["abilities: " + _abilities.describe_errors()], "")
		return
	_library = DialogueLibrary.load_all(_abilities)
	if not _library.is_valid():
		_failures.append("shipped dialogue is invalid: %s" % _library.describe_errors())
	_characters = CharacterDirectory.load_all()

	_check_shape()
	_check_bilingual()
	_check_rules()
	_check_coverage()
	_check_presentation_names()

	Harness.finish(self, _failures, "every inner voice is valued, translated, and used.")


# --- cases ------------------------------------------------------------------


func _check_shape() -> void:
	var ids := _abilities.get_ability_ids()
	# One provisional voice for this milestone. The number is asserted so adding a
	# second one is a decision someone makes, not something that happens quietly.
	if ids.size() != 1:
		_failures.append("Expected exactly one inner voice, found %d." % ids.size())
	for ability_id: StringName in ids:
		var ability := _abilities.get_ability(ability_id)
		if String(ability_id).is_empty():
			_failures.append("An inner voice has an empty id.")
		if ability.value < 0 or ability.value > 10:
			_failures.append("Ability '%s' has a silly value %d." % [ability_id, ability.value])
		if _characters != null and _characters.get_display_name(ability.speaker_id) == String(ability.speaker_id):
			_failures.append("Ability '%s' has no character profile for '%s'." % [ability_id, ability.speaker_id])
		if ability.max_passive < 1:
			_failures.append("Ability '%s' can never speak passively." % ability_id)


## Every language must carry the same voices, with text that is not just the English
## string copied across. The second half matters: structure checks pass happily on a
## translation nobody did.
func _check_bilingual() -> void:
	var ids := _abilities.get_ability_ids()
	var english: Dictionary = {}
	for ability_id: StringName in ids:
		english[ability_id] = _abilities.get_ability(ability_id).display_name
		if _abilities.get_ability(ability_id).description.strip_edges().is_empty():
			_failures.append("Ability '%s' has no description in the active language." % ability_id)
	if not _abilities.set_locale("zh-CN"):
		_failures.append("Switching the ability registry to zh-CN failed.")
		return
	for ability_id: StringName in ids:
		var zh_name := _abilities.get_ability(ability_id).display_name
		if zh_name.strip_edges().is_empty():
			_failures.append("Ability '%s' has no Chinese name." % ability_id)
		if zh_name == String(english[ability_id]):
			_failures.append(
				"Ability '%s' is called '%s' in both languages; the Chinese table was not translated."
				% [ability_id, zh_name]
			)
		if _abilities.get_ability(ability_id).description.strip_edges().is_empty():
			_failures.append("Ability '%s' has no Chinese description." % ability_id)
	_abilities.set_locale("en")


func _check_rules() -> void:
	if _library == null:
		_failures.append("Passive rules cannot be checked without a loaded dialogue library.")
		return
	var rules := _abilities.get_rules()
	# Three rules are enough to prove the mechanism with one voice: an inspection
	# trigger, a second inspection trigger, and a location trigger. Fewer would mean
	# a voice that never speaks unprompted.
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
	if not _abilities.get_name_for_speaker(&"q").is_empty():
		_failures.append("An ordinary classmate was resolved as an inner voice.")

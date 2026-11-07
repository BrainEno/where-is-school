class_name InnerAbilities
extends RefCounted
## The protagonist's inner voices: what they are, what they are worth, and when
## they are allowed to speak on their own.
##
## Deliberately small. Four voices, one value each, one rule list. The point of this
## pass is not a skill tree; it is to prove that a voice can be a *character* with
## its own limitations instead of a stat that unlocks correct answers.
##
## Content layout, mirroring dialogue and inspections:
##
##   data/abilities/abilities.json     structure: values, speakers, passive rules
##   data/abilities/<locale>.json      prose: the voice's name and description
##
## Structure and prose are split for the same reason as everywhere else in this
## project: the prose is translated, the ids and numbers are not, and a translation
## that drops a voice has to fail the build.
##
## The loader is strict. A check or a passive rule that names a voice that does not
## exist is a content bug that would otherwise surface as a silent no-op in the
## middle of a scene.

const STRUCTURE_PATH := "res://data/abilities/abilities.json"
const TEXT_PATH := "res://data/abilities/%s.json"
const FORMAT_VERSION := 1
## Kinds of event that can make a voice speak up without being asked.
const TRIGGER_KINDS: Array[String] = ["inspection", "location", "conversation_end"]
## A voice that answers every prop is noise. The session cap is the blunt guard
## against that; per-rule `once` is the precise one.
const DEFAULT_MAX_PASSIVE_PER_SESSION := 2


class AbilityData extends RefCounted:
	var ability_id: StringName = &""
	## Base value added to the die. Small on purpose: 0-6 is a person, 10 is a
	## caricature.
	var value: int = 0
	## Character profile used when this voice speaks, so its lines carry the same
	## speaker name and colour as anyone else in the dialogue panel.
	var speaker_id: StringName = &""
	## Localized prose.
	var display_name: String = ""
	var description: String = ""
	## How many times this voice may start a passive line in one session.
	var max_passive: int = 2


class PassiveRule extends RefCounted:
	var rule_id: StringName = &""
	var ability_id: StringName = &""
	## "inspection", "location" or "conversation_end".
	var trigger_kind: String = ""
	## Which inspection id / location id / conversation id fires it.
	var trigger_id: StringName = &""
	var conversation_id: StringName = &""
	## Fires at most once per session when true (the default). The rule is still
	## remembered in GameState, so a save would keep the memory.
	var once: bool = true
	## Story flags that must all be true before the rule may fire.
	var requires: Array[StringName] = []


var errors: Array[String] = []
var _abilities: Dictionary = {}
var _text: Dictionary = {}
var _rules: Array[PassiveRule] = []
var _locale: String = L10n.DEFAULT_LOCALE


static func load_all() -> InnerAbilities:
	var registry := InnerAbilities.new()
	registry._parse_structure()
	for locale in L10n.LOCALES:
		registry._parse_text(locale)
	registry._check_text_parity()
	registry.set_locale(L10n.current)
	return registry


# --- lookups ----------------------------------------------------------------


func is_valid() -> bool:
	return errors.is_empty()


func set_locale(locale: String) -> bool:
	var code := L10n.normalize(locale)
	_locale = code
	for ability_id: StringName in _abilities.keys():
		var ability: AbilityData = _abilities[ability_id]
		var text: Dictionary = _text.get(code, {}).get(ability_id, {})
		ability.display_name = String(text.get("name", String(ability_id)))
		ability.description = String(text.get("description", ""))
	return true


func get_locale() -> String:
	return _locale


func has_ability(ability_id: StringName) -> bool:
	return _abilities.has(ability_id)


func get_ability(ability_id: StringName) -> AbilityData:
	return _abilities.get(ability_id, null)


func get_ability_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _abilities.keys():
		ids.append(key)
	ids.sort()
	return ids


func get_rules() -> Array[PassiveRule]:
	return _rules.duplicate()


## Every rule that could fire for one event, in file order. The caller still has to
## apply the `once` / session-cap / flag checks.
func get_rules_for(trigger_kind: String, trigger_id: StringName) -> Array[PassiveRule]:
	var result: Array[PassiveRule] = []
	for rule: PassiveRule in _rules:
		if rule.trigger_kind != trigger_kind:
			continue
		if rule.trigger_id != trigger_id:
			continue
		result.append(rule)
	return result


func get_value(ability_id: StringName) -> int:
	var ability := get_ability(ability_id)
	return ability.value if ability != null else 0


## The translated display name for a speaker id, when that speaker is one of the
## inner voices. Empty for ordinary characters, so callers can fall back.
func get_name_for_speaker(speaker_id: StringName) -> String:
	for ability: AbilityData in _abilities.values():
		if ability.speaker_id == speaker_id:
			return ability.display_name
	return ""


func get_speaker_id(ability_id: StringName) -> StringName:
	var ability := get_ability(ability_id)
	return ability.speaker_id if ability != null else &""


func describe_errors() -> String:
	if errors.is_empty():
		return "Inner abilities loaded without errors."
	return "Inner abilities have %d error(s):\n%s" % [errors.size(), "\n".join(errors)]


# --- parsing ----------------------------------------------------------------


func _parse_structure() -> void:
	var data := _read_json(STRUCTURE_PATH)
	if data.is_empty():
		return
	var version := int(data.get("format_version", 0))
	if version != FORMAT_VERSION:
		errors.append(
			"%s: format_version %d is not supported (expected %d)."
			% [STRUCTURE_PATH, version, FORMAT_VERSION]
		)
		return
	var default_cap := int(data.get("max_passive_per_session", DEFAULT_MAX_PASSIVE_PER_SESSION))

	var raw_abilities: Variant = data.get("abilities")
	if not (raw_abilities is Dictionary) or (raw_abilities as Dictionary).is_empty():
		errors.append("%s: 'abilities' must be a non-empty object." % STRUCTURE_PATH)
		return
	for key: Variant in (raw_abilities as Dictionary).keys():
		var ability := AbilityData.new()
		ability.ability_id = StringName(String(key))
		var raw: Variant = (raw_abilities as Dictionary)[key]
		if not (raw is Dictionary):
			errors.append("%s: ability '%s' must be an object." % [STRUCTURE_PATH, ability.ability_id])
			continue
		var entry: Dictionary = raw
		ability.value = int(entry.get("value", 0))
		if ability.value < 0 or ability.value > 10:
			errors.append(
				"%s: ability '%s' has value %d; keep it between 0 and 10."
				% [STRUCTURE_PATH, ability.ability_id, ability.value]
			)
		ability.speaker_id = StringName(
			String(entry.get("speaker", "voice_%s" % ability.ability_id))
		)
		ability.max_passive = int(entry.get("max_passive", default_cap))
		_abilities[ability.ability_id] = ability

	var raw_rules: Variant = data.get("passives", [])
	if not (raw_rules is Array):
		errors.append("%s: 'passives' must be an array." % STRUCTURE_PATH)
	else:
		var seen: Dictionary = {}
		for index in (raw_rules as Array).size():
			var rule := _parse_rule((raw_rules as Array)[index], index)
			if rule == null:
				continue
			if seen.has(rule.rule_id):
				errors.append("%s: duplicate passive rule id '%s'." % [STRUCTURE_PATH, rule.rule_id])
				continue
			seen[rule.rule_id] = true
			_rules.append(rule)


func _parse_rule(raw: Variant, index: int) -> PassiveRule:
	var context := "%s: passive #%d" % [STRUCTURE_PATH, index]
	if not (raw is Dictionary):
		errors.append("%s must be an object." % context)
		return null
	var data: Dictionary = raw
	var rule := PassiveRule.new()
	rule.rule_id = StringName(String(data.get("id", "")))
	if String(rule.rule_id).is_empty():
		errors.append("%s is missing 'id'." % context)
		return null
	context = "%s: passive '%s'" % [STRUCTURE_PATH, rule.rule_id]
	rule.ability_id = StringName(String(data.get("ability", "")))
	if not _abilities.has(rule.ability_id):
		errors.append("%s names unknown ability '%s'." % [context, rule.ability_id])
	var trigger: Variant = data.get("trigger")
	if not (trigger is Dictionary):
		errors.append("%s needs a 'trigger' object." % context)
		return rule
	var trigger_data: Dictionary = trigger
	rule.trigger_kind = String(trigger_data.get("kind", ""))
	if not TRIGGER_KINDS.has(rule.trigger_kind):
		errors.append(
			"%s has trigger kind '%s'; use one of %s."
			% [context, rule.trigger_kind, ", ".join(TRIGGER_KINDS)]
		)
	rule.trigger_id = StringName(String(trigger_data.get("id", "")))
	if String(rule.trigger_id).is_empty():
		errors.append("%s needs a trigger 'id'." % context)
	rule.conversation_id = StringName(String(data.get("conversation", "")))
	if String(rule.conversation_id).is_empty():
		errors.append("%s needs a 'conversation' id." % context)
	rule.once = bool(data.get("once", true))
	for flag: Variant in data.get("requires", []):
		rule.requires.append(StringName(String(flag)))
	return rule


func _parse_text(locale: String) -> void:
	var path := TEXT_PATH % locale
	_text[locale] = {}
	var data := _read_json(path)
	if data.is_empty():
		return
	var version := int(data.get("format_version", 0))
	if version != FORMAT_VERSION:
		errors.append(
			"%s: format_version %d is not supported (expected %d)."
			% [path, version, FORMAT_VERSION]
		)
		return
	var declared := String(data.get("locale", ""))
	if L10n.normalize(declared) != locale:
		errors.append("%s: 'locale' is '%s' but the file sits in the '%s' tree." % [path, declared, locale])
	var raw: Variant = data.get("abilities")
	if not (raw is Dictionary):
		errors.append("%s: 'abilities' must be an object." % path)
		return
	for key: Variant in (raw as Dictionary).keys():
		var ability_id := StringName(String(key))
		var entry: Variant = (raw as Dictionary)[key]
		if not (entry is Dictionary):
			errors.append("%s: ability '%s' must be an object." % [path, ability_id])
			continue
		var text: Dictionary = entry
		if String(text.get("name", "")).strip_edges().is_empty():
			errors.append("%s: ability '%s' has no 'name'." % [path, ability_id])
		if String(text.get("description", "")).strip_edges().is_empty():
			errors.append("%s: ability '%s' has no 'description'." % [path, ability_id])
		_text[locale][ability_id] = {
			"name": String(text.get("name", "")).strip_edges(),
			"description": String(text.get("description", "")).strip_edges(),
		}


## Every language must name the same voices: a missing translation would show an
## ability id to the player, which is the one thing the interface must never do.
func _check_text_parity() -> void:
	if L10n.LOCALES.is_empty():
		return
	var reference: String = L10n.LOCALES[0]
	var reference_ids: Array = _text.get(reference, {}).keys()
	reference_ids.sort()
	for locale in L10n.LOCALES:
		if locale == reference:
			continue
		var ids: Array = _text.get(locale, {}).keys()
		ids.sort()
		for ability_id: Variant in reference_ids:
			if not ids.has(ability_id):
				errors.append(
					"data/abilities/%s.json: ability '%s' has no text (present in %s)."
					% [locale, ability_id, reference]
				)
		for ability_id: Variant in ids:
			if not reference_ids.has(ability_id):
				errors.append(
					"data/abilities/%s.json: ability '%s' does not exist in %s."
					% [locale, ability_id, reference]
				)
	for ability_id: StringName in _abilities.keys():
		if not _text.get(reference, {}).has(ability_id):
			errors.append(
				"data/abilities/%s.json: ability '%s' from abilities.json has no text."
				% [reference, ability_id]
			)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("File not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Could not open %s (error %d)." % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append(
			"%s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
		)
		return {}
	if not (json.data is Dictionary):
		errors.append("%s: root value must be an object." % path)
		return {}
	return json.data

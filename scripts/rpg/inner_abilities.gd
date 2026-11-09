class_name InnerAbilities
extends RefCounted
## The protagonist's inner voices: what they are, what they are worth, and when
## they are allowed to speak on their own.
##
## The registry is a *list* of voices, and this round exists to keep it one: the
## number of voices is data, not code. Content ships exactly one voice
## (`orientation`); the tests load additional fictional voices from a fixture
## directory that never enters `data/`. Nothing here decides how many voices the
## game will have, what they are called, or what they are worth — those are the
## owner's decisions, and the voice's name, value and prose stay provisional
## (ADR 0003).
##
## Three identities are kept apart on purpose, because mixing them up is the failure
## mode a multi-voice system invites:
##
##   ability_id   what the content rolls against ("orientation"). Unique; it is the
##                key of the `abilities` object and the id a check names.
##   speaker_id   who the dialogue panel is speaking as ("voice_orientation"). Also
##                unique, and the only link between a voice and its CharacterProfile,
##                which is `data/characters/<speaker_id>.tres`.
##   value / max_passive
##                per voice, never shared: one voice's number can never be read for
##                another, and one voice's passive count can never spend another's.
##
## Content layout, mirroring dialogue and inspections:
##
##   data/abilities/abilities.json     structure: values, speakers, passive rules
##   data/abilities/<locale>.json      prose: each voice's name and description
##
## Structure and prose are split for the same reason as everywhere else in this
## project: the prose is translated, the ids and numbers are not, and a translation
## that drops a voice has to fail the build.
##
## The loader is strict. A check or a passive rule that names a voice that does not
## exist, two voices claiming one speaker, a non-numeric value, or a translation that
## is only the English string copied over are all content bugs that would otherwise
## surface as a silent no-op or as raw ids in the interface. Each one is reported with
## the file, the ability id and the speaker id.
##
## "Strict" includes types: a field the schema says is a string has to be a JSON string,
## `once` has to be a JSON boolean, `requires` has to be an array of flag names, and a
## localised `name` may not be rescued by `String()` on its way into the registry. A
## wrong type is a content bug with a file and a line behind it, not a value to coerce.

const DATA_DIR := "res://data/abilities"
const STRUCTURE_FILE := "abilities.json"
const FORMAT_VERSION := 1
## Kinds of event that can make a voice speak up without being asked.
const TRIGGER_KINDS: Array[String] = ["inspection", "location", "conversation_end"]
## The prose fields a voice has, and therefore the only fields a translation exception
## may name.
const TEXT_FIELDS: Array[String] = ["name", "description"]
## Per-voice, per-field opt-out from the "identical text means an unfinished
## translation" rule. It is declared in the *translated* file, next to the prose it
## applies to: `"untranslated_fields": ["name"]`. There is deliberately no global switch:
## one voice keeping one word in its original spelling must not silence the check for
## every other voice or every other field.
const EXCEPTION_KEY := "untranslated_fields"
## A voice that answers every prop is noise. The session cap is the blunt guard
## against that; per-rule `once` is the precise one.
const DEFAULT_MAX_PASSIVE_PER_SESSION := 2
## Ranges the loader enforces instead of clamping. A voice worth 40 would silently
## break every difficulty in the content, and a negative cap would silently mute a
## voice forever; both are cheaper to catch here than in a playtest.
const MIN_VALUE := 0
const MAX_VALUE := 10
const MIN_MAX_PASSIVE := 0
const MAX_MAX_PASSIVE := 20


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
## speaker_id -> ability_id, built while parsing so a duplicate speaker is caught
## once, at load, instead of being resolved silently by whoever asks first.
var _speakers: Dictionary = {}
var _text: Dictionary = {}
var _rules: Array[PassiveRule] = []
var _locale: String = L10n.DEFAULT_LOCALE
var _data_dir: String = DATA_DIR


## `data_dir` exists so a test can load a fixture registry from `user://` through
## the same parser and the same rules as the shipped one. The game always calls this
## with no argument.
static func load_all(data_dir: String = DATA_DIR) -> InnerAbilities:
	var registry := InnerAbilities.new()
	registry._data_dir = data_dir
	registry._parse_structure()
	for locale in L10n.LOCALES:
		registry._parse_text(locale)
	registry._check_text_parity()
	registry.set_locale(L10n.current)
	return registry


func structure_path() -> String:
	return "%s/%s" % [_data_dir, STRUCTURE_FILE]


func text_path(locale: String) -> String:
	return "%s/%s.json" % [_data_dir, locale]


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


## Every speaker id an inner voice owns, sorted. This is the list the character
## directory loads profiles from; it is derived from the data, never hard-coded.
func get_speaker_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _speakers.keys():
		ids.append(StringName(String(key)))
	ids.sort()
	return ids


## The voice that speaks as `speaker_id`, or null for an ordinary character. Null is
## the only answer for "not a voice": there is no fallback to another voice, because a
## line that silently borrows someone else's identity is worse than one that does not
## appear at all.
func get_ability_for_speaker(speaker_id: StringName) -> AbilityData:
	var ability_id: StringName = StringName(String(_speakers.get(speaker_id, "")))
	if String(ability_id).is_empty():
		return null
	return _abilities.get(ability_id, null)


## The translated display name for a speaker id, when that speaker is one of the
## inner voices. Empty for ordinary characters, so callers can fall back.
func get_name_for_speaker(speaker_id: StringName) -> String:
	var ability := get_ability_for_speaker(speaker_id)
	return ability.display_name if ability != null else ""


func describe_errors() -> String:
	if errors.is_empty():
		return "Inner abilities loaded without errors."
	return "Inner abilities have %d error(s):\n%s" % [errors.size(), "\n".join(errors)]


# --- parsing ----------------------------------------------------------------


func _parse_structure() -> void:
	var path := structure_path()
	var data := _read_json(path)
	if data.is_empty():
		return
	var version := _read_int(data, "format_version", 0, path)
	if version != FORMAT_VERSION:
		errors.append(
			"%s: format_version %d is not supported (expected %d)."
			% [path, version, FORMAT_VERSION]
		)
		return
	var default_cap := _read_int(
		data, "max_passive_per_session", DEFAULT_MAX_PASSIVE_PER_SESSION, path
	)
	if default_cap < MIN_MAX_PASSIVE or default_cap > MAX_MAX_PASSIVE:
		errors.append(
			"%s: max_passive_per_session %d is outside %d..%d."
			% [path, default_cap, MIN_MAX_PASSIVE, MAX_MAX_PASSIVE]
		)

	var raw_abilities: Variant = data.get("abilities")
	if not (raw_abilities is Dictionary) or (raw_abilities as Dictionary).is_empty():
		errors.append("%s: 'abilities' must be a non-empty object." % path)
		return
	for key: Variant in (raw_abilities as Dictionary).keys():
		var ability := AbilityData.new()
		ability.ability_id = StringName(String(key))
		var context := "%s: ability '%s'" % [path, ability.ability_id]
		if String(ability.ability_id).is_empty():
			errors.append("%s: an ability has an empty id." % path)
			continue
		var raw: Variant = (raw_abilities as Dictionary)[key]
		if not (raw is Dictionary):
			errors.append("%s must be an object." % context)
			continue
		var entry: Dictionary = raw
		ability.value = _read_int(entry, "value", 0, context)
		if ability.value < MIN_VALUE or ability.value > MAX_VALUE:
			errors.append(
				"%s has value %d; keep it between %d and %d."
				% [context, ability.value, MIN_VALUE, MAX_VALUE]
			)
		var raw_speaker: Variant = entry.get("speaker", "voice_%s" % ability.ability_id)
		if not (raw_speaker is String) or String(raw_speaker).strip_edges().is_empty():
			errors.append("%s needs a non-empty 'speaker' string." % context)
			continue
		ability.speaker_id = StringName(String(raw_speaker).strip_edges())
		ability.max_passive = _read_int(entry, "max_passive", default_cap, context)
		if ability.max_passive < MIN_MAX_PASSIVE or ability.max_passive > MAX_MAX_PASSIVE:
			errors.append(
				"%s has max_passive %d; keep it between %d and %d."
				% [context, ability.max_passive, MIN_MAX_PASSIVE, MAX_MAX_PASSIVE]
			)
		# One speaker, one voice. Without this check a second voice could claim
		# `voice_orientation` and every speaker lookup would silently return whichever
		# ability happened to be parsed first.
		if _speakers.has(ability.speaker_id):
			errors.append(
				"%s: speaker '%s' is already used by ability '%s'; one speaker belongs to one voice."
				% [context, ability.speaker_id, _speakers[ability.speaker_id]]
			)
		else:
			_speakers[ability.speaker_id] = ability.ability_id
		_abilities[ability.ability_id] = ability

	var raw_rules: Variant = data.get("passives", [])
	if not (raw_rules is Array):
		errors.append("%s: 'passives' must be an array." % path)
	else:
		var seen: Dictionary = {}
		for index in (raw_rules as Array).size():
			var rule := _parse_rule((raw_rules as Array)[index], index)
			if rule == null:
				continue
			if seen.has(rule.rule_id):
				errors.append("%s: duplicate passive rule id '%s'." % [path, rule.rule_id])
				continue
			seen[rule.rule_id] = true
			_rules.append(rule)


## Reads one passive rule, refusing anything whose type would otherwise be guessed.
##
## `String(value)` is not a type check: it turns a number into "7", an array into a
## meaningless string and a boolean into "true", and every one of those mistakes would
## then be reported — if at all — as "unknown ability" or "unknown flag" somewhere else.
## `once` is the sharpest case: `"once": "false"` is a non-empty string, which is truthy,
## so a rule the author meant to be repeatable would fire exactly once and nothing would
## say why. Each field is therefore checked against the JSON type it is supposed to be,
## and the message names the file, the rule id and the field.
func _parse_rule(raw: Variant, index: int) -> PassiveRule:
	var path := structure_path()
	var context := "%s: passive #%d" % [path, index]
	if not (raw is Dictionary):
		errors.append("%s must be an object." % context)
		return null
	var data: Dictionary = raw
	var rule := PassiveRule.new()
	var raw_id: Variant = data.get("id", null)
	if not (raw_id is String) or String(raw_id).strip_edges().is_empty():
		errors.append(
			"%s: 'id' must be a non-empty string (got %s)." % [context, JSON.stringify(raw_id)]
		)
		return null
	rule.rule_id = StringName(String(raw_id).strip_edges())
	context = "%s: passive '%s'" % [path, rule.rule_id]

	var raw_ability: Variant = data.get("ability", null)
	if not (raw_ability is String) or String(raw_ability).strip_edges().is_empty():
		errors.append(
			"%s: 'ability' must be a non-empty string (got %s)."
			% [context, JSON.stringify(raw_ability)]
		)
	else:
		rule.ability_id = StringName(String(raw_ability).strip_edges())
		if not _abilities.has(rule.ability_id):
			errors.append("%s names unknown ability '%s'." % [context, rule.ability_id])

	var raw_conversation: Variant = data.get("conversation", null)
	if not (raw_conversation is String) or String(raw_conversation).strip_edges().is_empty():
		errors.append(
			"%s: 'conversation' must be a non-empty string (got %s)."
			% [context, JSON.stringify(raw_conversation)]
		)
	else:
		rule.conversation_id = StringName(String(raw_conversation).strip_edges())

	var trigger: Variant = data.get("trigger", null)
	if not (trigger is Dictionary):
		errors.append("%s needs a 'trigger' object (got %s)." % [context, JSON.stringify(trigger)])
		return rule
	var trigger_data: Dictionary = trigger
	var raw_kind: Variant = trigger_data.get("kind", null)
	if not (raw_kind is String) or String(raw_kind).strip_edges().is_empty():
		errors.append(
			"%s: trigger.kind must be one of %s (got %s)."
			% [context, ", ".join(TRIGGER_KINDS), JSON.stringify(raw_kind)]
		)
	else:
		rule.trigger_kind = String(raw_kind).strip_edges()
		if not TRIGGER_KINDS.has(rule.trigger_kind):
			errors.append(
				"%s has trigger kind '%s'; use one of %s."
				% [context, rule.trigger_kind, ", ".join(TRIGGER_KINDS)]
			)
	var raw_trigger_id: Variant = trigger_data.get("id", null)
	if not (raw_trigger_id is String) or String(raw_trigger_id).strip_edges().is_empty():
		errors.append(
			"%s: trigger.id must be a non-empty string (got %s)."
			% [context, JSON.stringify(raw_trigger_id)]
		)
	else:
		rule.trigger_id = StringName(String(raw_trigger_id).strip_edges())

	if data.has("once"):
		var raw_once: Variant = data["once"]
		if raw_once is bool:
			rule.once = bool(raw_once)
		else:
			errors.append(
				"%s: 'once' must be true or false, not %s. A quoted \"false\" would count as true."
				% [context, JSON.stringify(raw_once)]
			)
			rule.once = true

	if data.has("requires"):
		var raw_requires: Variant = data["requires"]
		if not (raw_requires is Array):
			errors.append(
				"%s: 'requires' must be an array of story flag names (got %s)."
				% [context, JSON.stringify(raw_requires)]
			)
		else:
			var requires_list: Array = raw_requires
			for position in requires_list.size():
				var flag: Variant = requires_list[position]
				if not (flag is String) or String(flag).strip_edges().is_empty():
					errors.append(
						"%s: requires[%d] must be a non-empty flag name (got %s)."
						% [context, position, JSON.stringify(flag)]
					)
					continue
				rule.requires.append(StringName(String(flag).strip_edges()))
	return rule


## Reads one language's prose. `name` and `description` must be JSON strings: the
## previous version ran every value through `String()`, so `"name": 7` became "7" and
## `"name": {"zh": "路感"}` became a string nobody could predict — a translation bug that
## would reach the dialogue panel instead of CI.
func _parse_text(locale: String) -> void:
	var path := text_path(locale)
	_text[locale] = {}
	var data := _read_json(path)
	if data.is_empty():
		return
	var version := _read_int(data, "format_version", 0, path)
	if version != FORMAT_VERSION:
		errors.append(
			"%s: format_version %d is not supported (expected %d)."
			% [path, version, FORMAT_VERSION]
		)
		return
	var declared_raw: Variant = data.get("locale", "")
	if not (declared_raw is String):
		errors.append("%s: 'locale' must be a string (got %s)." % [path, JSON.stringify(declared_raw)])
	else:
		var declared := String(declared_raw)
		if L10n.normalize(declared) != locale:
			errors.append(
				"%s: 'locale' is '%s' but the file sits in the '%s' tree." % [path, declared, locale]
			)
	var raw: Variant = data.get("abilities")
	if not (raw is Dictionary):
		errors.append("%s: 'abilities' must be an object." % path)
		return
	var is_reference := not L10n.LOCALES.is_empty() and locale == L10n.LOCALES[0]
	for key: Variant in (raw as Dictionary).keys():
		var ability_id := StringName(String(key))
		var entry: Variant = (raw as Dictionary)[key]
		if not (entry is Dictionary):
			errors.append("%s: ability '%s' must be an object." % [path, ability_id])
			continue
		var text: Dictionary = entry
		var values: Dictionary = {}
		for field: String in TEXT_FIELDS:
			var raw_value: Variant = text.get(field, null)
			if not (raw_value is String):
				errors.append(
					"%s: ability '%s' has no '%s' string (got %s)."
					% [path, ability_id, field, JSON.stringify(raw_value)]
				)
				values[field] = ""
				continue
			var value_text := String(raw_value).strip_edges()
			if value_text.is_empty():
				errors.append("%s: ability '%s' has no '%s'." % [path, ability_id, field])
			values[field] = value_text
		var exceptions := _parse_exceptions(text, path, ability_id, locale, is_reference)
		values[EXCEPTION_KEY] = exceptions
		_text[locale][ability_id] = values


## Which fields of this voice may keep the source wording. Deliberately field by field:
## an exception is a decision about one string, and a per-voice or per-file switch would
## quietly excuse the next copied line too.
func _parse_exceptions(
	text: Dictionary, path: String, ability_id: StringName, locale: String, is_reference: bool
) -> Array[String]:
	var declared: Array[String] = []
	if not text.has(EXCEPTION_KEY):
		return declared
	var raw: Variant = text[EXCEPTION_KEY]
	if not (raw is Array):
		errors.append(
			"%s: ability '%s': '%s' must be an array of field names (got %s)."
			% [path, ability_id, EXCEPTION_KEY, JSON.stringify(raw)]
		)
		return declared
	if is_reference:
		errors.append(
			"%s: ability '%s': '%s' only makes sense in a translated language, not in the "
			% [path, ability_id, EXCEPTION_KEY]
			+ "reference one — its text is the source."
		)
		return declared
	var entries: Array = raw
	for position in entries.size():
		var entry: Variant = entries[position]
		if not (entry is String) or String(entry).strip_edges().is_empty():
			errors.append(
				"%s: ability '%s': %s[%d] must be a field name (got %s)."
				% [path, ability_id, EXCEPTION_KEY, position, JSON.stringify(entry)]
			)
			continue
		var field := String(entry).strip_edges()
		if not TEXT_FIELDS.has(field):
			errors.append(
				"%s: ability '%s': %s names '%s', which is not translated text; use one of %s."
				% [
					path,
					ability_id,
					EXCEPTION_KEY,
					field,
					", ".join(TEXT_FIELDS),
				]
			)
			continue
		if declared.has(field):
			errors.append(
				"%s: ability '%s': '%s' is listed twice in %s."
				% [path, ability_id, field, EXCEPTION_KEY]
			)
			continue
		declared.append(field)
	return declared


## Every language must name the same voices, and must actually name them: a missing
## translation would show an ability id to the player, which is the one thing the
## interface must never do, and a copied string would show English words under a
## Chinese label.
##
## The copy check is deliberately blunt — identical text in two languages is treated as
## an unfinished translation. Every voice in this game is named in prose, not by a
## proper noun that happens to be spelled the same way twice.
##
## It can be relaxed, but only on purpose and only by naming the field: a voice may list
## `"untranslated_fields": ["name"]` in its *translated* entry, and that one field of that
## one voice is then allowed — expected, even — to stay identical. There is no global
## switch, an undeclared identical string is still an error, and a declaration that no
## longer describes the file (the text was translated after all) is an error too, so the
## exception cannot quietly outlive the reason it was added. `tests/ability_validation_test.gd`
## covers all three cases.
func _check_text_parity() -> void:
	if L10n.LOCALES.is_empty():
		return
	var reference: String = L10n.LOCALES[0]
	var reference_ids: Array = _text.get(reference, {}).keys()
	reference_ids.sort()
	for locale in L10n.LOCALES:
		var path := text_path(locale)
		var ids: Array = _text.get(locale, {}).keys()
		ids.sort()
		# Text for a voice that the structure file does not define would be invisible
		# content: nobody can roll on it and nothing can speak it.
		for ability_id: Variant in ids:
			if not _abilities.has(StringName(String(ability_id))):
				errors.append(
					"%s: ability '%s' has text but no entry in %s."
					% [path, ability_id, structure_path()]
				)
		if locale == reference:
			continue
		for ability_id: Variant in reference_ids:
			if not ids.has(ability_id):
				errors.append(
					"%s: ability '%s' has no text (present in %s)."
					% [path, ability_id, reference]
				)
		for ability_id: Variant in ids:
			if not reference_ids.has(ability_id):
				errors.append(
					"%s: ability '%s' does not exist in %s."
					% [path, ability_id, reference]
				)
		for ability_id: Variant in ids:
			if not reference_ids.has(ability_id):
				continue
			var translated: Dictionary = _text[locale][ability_id]
			var original: Dictionary = _text[reference][ability_id]
			for field: String in TEXT_FIELDS:
				var source_text := String(original.get(field, "")).strip_edges()
				var target_text := String(translated.get(field, "")).strip_edges()
				if source_text.is_empty() or target_text.is_empty():
					# An empty or missing translation is already an error of its own.
					continue
				var kept: bool = (translated.get(EXCEPTION_KEY, []) as Array).has(field)
				if target_text == source_text:
					if kept:
						# Declared on purpose, field by field: a word that is spelled the same
						# way in both languages is not a bug when the author says so.
						continue
					errors.append(
						"%s: ability '%s' %s is identical to the %s text; it was not translated. "
						% [path, ability_id, field, reference]
						+ "If this field is meant to keep the source wording, add "
						+ '\"%s\": [\"%s\"] to its %s entry.' % [EXCEPTION_KEY, field, locale]
					)
				elif kept:
					errors.append(
						"%s: ability '%s' declares %s in %s, but its %s text differs from %s. "
						% [path, ability_id, field, EXCEPTION_KEY, locale, reference]
						+ "Either translate the field or remove the declaration."
					)
	for ability_id: StringName in _abilities.keys():
		if not _text.get(reference, {}).has(ability_id):
			errors.append(
				"%s: ability '%s' from %s has no text."
				% [text_path(reference), ability_id, structure_path()]
			)


## Reads an integer field without ever guessing. JSON has one number type, so a
## fractional or non-numeric value would otherwise become 0 through `int()` and a
## mistyped difficulty would quietly turn into an easy check.
func _read_int(source: Dictionary, key: String, fallback: int, context: String) -> int:
	if not source.has(key):
		return fallback
	var raw: Variant = source[key]
	if not (raw is int or raw is float):
		errors.append(
			"%s: '%s' must be a number (got %s)." % [context, key, JSON.stringify(raw)]
		)
		return fallback
	if raw is float and not is_equal_approx(float(raw), roundf(float(raw))):
		errors.append(
			"%s: '%s' must be a whole number (got %s)." % [context, key, str(raw)]
		)
	return int(raw)


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

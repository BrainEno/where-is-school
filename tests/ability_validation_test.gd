extends SceneTree
## Proves the inner-voice registry refuses the mistakes it can see, and only those.
##
## The registry is the one place in the project where a small JSON mistake becomes a silent
## gameplay bug: a `"once": "false"` that counts as true, a `requires` that iterates a
## string character by character, a localised `name` that arrives as the number 7 and is
## shown to the player, or a Chinese line that is the English one copied over. Every case
## below is one of those, written into a `user://` registry and loaded through the real
## loader — the shipped `data/abilities/` is only ever read.
##
## The translation exception is tested in all three states it has: an undeclared copy is an
## error, a declared copy is accepted, and a declaration whose field was translated after
## all is an error again, so an exception cannot outlive the reason it was written.
##
## Run it with:
##
##   godot --headless --path . --script res://tests/ability_validation_test.gd

const Harness = preload("res://tests/test_harness.gd")

const ROOT := "user://ability_validation"
const STRUCTURE := "res://data/abilities/abilities.json"

var _failures: Array[String] = []
var _checks: int = 0
var _base_structure: Dictionary = {}
var _base_text: Dictionary = {}


func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "ability_validation_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "base"
	if not _load_base():
		Harness.finish(self, _failures, "")
		return
	Harness.stage = "shipped data"
	_case_shipped_data_is_valid()
	Harness.stage = "once"
	_case_once_must_be_a_boolean()
	Harness.stage = "requires"
	_case_requires_must_be_flag_names()
	Harness.stage = "rule fields"
	_case_rule_fields_must_be_strings()
	Harness.stage = "localised strings"
	_case_localised_text_must_be_strings()
	Harness.stage = "translation exceptions"
	_case_translation_exceptions()
	Harness.stage = "existing checks"
	_case_existing_checks_still_fire()
	Harness.finish(self, _failures, "ability validation: %d assertions passed." % _checks)


# --- cases ------------------------------------------------------------------


func _case_shipped_data_is_valid() -> void:
	var registry := InnerAbilities.load_all()
	_expect_valid("随项目发布的 data/abilities", registry)


func _case_once_must_be_a_boolean() -> void:
	var structure := _base_structure_copy()
	var rule := _first_rule(structure)
	var rule_id := String(rule.get("id", ""))
	rule["once"] = "true"
	var registry := _load("once_string", structure, _base_text_copy())
	_expect_error(
		"once 写成字符串 \"true\"",
		registry,
		["'once'", rule_id, "must be true or false"]
	)

	structure = _base_structure_copy()
	_first_rule(structure)["once"] = 1
	registry = _load("once_number", structure, _base_text_copy())
	_expect_error("once 写成数字 1", registry, ["'once'", rule_id])

	structure = _base_structure_copy()
	_first_rule(structure)["once"] = false
	registry = _load("once_false", structure, _base_text_copy())
	_expect_valid("once 写成 JSON false", registry)
	if registry.is_valid():
		var rules := registry.get_rules()
		_expect(
			not rules.is_empty() and not bool(rules[0].once),
			"once: false 没有读成 false。"
		)

	structure = _base_structure_copy()
	_first_rule(structure).erase("once")
	registry = _load("once_absent", structure, _base_text_copy())
	_expect_valid("不写 once", registry)
	if registry.is_valid():
		var rules := registry.get_rules()
		_expect(not rules.is_empty() and bool(rules[0].once), "不写 once 时默认应该是 true。")


func _case_requires_must_be_flag_names() -> void:
	var structure := _base_structure_copy()
	_first_rule(structure)["requires"] = "saw_set_square"
	var registry := _load("requires_string", structure, _base_text_copy())
	_expect_error("requires 写成字符串", registry, ["'requires'", "array"])

	structure = _base_structure_copy()
	_first_rule(structure)["requires"] = ["saw_set_square", 3]
	registry = _load("requires_number", structure, _base_text_copy())
	_expect_error("requires 里混进数字", registry, ["requires[1]"])

	structure = _base_structure_copy()
	_first_rule(structure)["requires"] = [""]
	registry = _load("requires_empty", structure, _base_text_copy())
	_expect_error("requires 里是空字符串", registry, ["requires[0]"])

	structure = _base_structure_copy()
	_first_rule(structure)["requires"] = ["saw_set_square", "met_q"]
	registry = _load("requires_ok", structure, _base_text_copy())
	_expect_valid("requires 是两个旗标名", registry)
	if registry.is_valid():
		var rules := registry.get_rules()
		_expect(
			not rules.is_empty() and (rules[0].requires as Array).size() == 2,
			"requires 没有读成两个旗标。"
		)


func _case_rule_fields_must_be_strings() -> void:
	var structure := _base_structure_copy()
	var rule := _first_rule(structure)
	rule["id"] = 7
	var registry := _load("rule_id_number", structure, _base_text_copy())
	_expect_error("规则 id 写成数字", registry, ["passive #0", "'id'"])

	structure = _base_structure_copy()
	rule = _first_rule(structure)
	var rule_id := String(rule.get("id", ""))
	rule["ability"] = 3
	registry = _load("rule_ability_number", structure, _base_text_copy())
	_expect_error("规则 ability 写成数字", registry, [rule_id, "'ability'"])

	structure = _base_structure_copy()
	rule = _first_rule(structure)
	rule["conversation"] = ["voice_notice"]
	registry = _load("rule_conversation_array", structure, _base_text_copy())
	_expect_error("规则 conversation 写成数组", registry, [rule_id, "'conversation'"])

	structure = _base_structure_copy()
	rule = _first_rule(structure)
	(rule["trigger"] as Dictionary)["kind"] = 1
	registry = _load("trigger_kind_number", structure, _base_text_copy())
	_expect_error("trigger.kind 写成数字", registry, [rule_id, "trigger.kind"])

	structure = _base_structure_copy()
	rule = _first_rule(structure)
	(rule["trigger"] as Dictionary)["id"] = 5
	registry = _load("trigger_id_number", structure, _base_text_copy())
	_expect_error("trigger.id 写成数字", registry, [rule_id, "trigger.id"])

	structure = _base_structure_copy()
	rule = _first_rule(structure)
	rule["trigger"] = "inspection"
	registry = _load("trigger_not_object", structure, _base_text_copy())
	_expect_error("trigger 写成字符串", registry, [rule_id, "'trigger'"])


func _case_localised_text_must_be_strings() -> void:
	var text := _base_text_copy()
	var translated: Dictionary = text["zh-CN"]
	var ability_id := _first_ability_id()
	var ability_text: Dictionary = (translated["abilities"] as Dictionary)[ability_id]
	ability_text["name"] = 7
	var registry := _load("text_name_number", _base_structure_copy(), text)
	_expect_error(
		"中文名称写成数字",
		registry,
		["zh-CN.json", ability_id, "'name'"]
	)

	text = _base_text_copy()
	translated = text["zh-CN"]
	ability_text = (translated["abilities"] as Dictionary)[ability_id]
	ability_text["description"] = {"text": "一种感觉"}
	registry = _load("text_description_object", _base_structure_copy(), text)
	_expect_error(
		"中文说明写成对象",
		registry,
		["zh-CN.json", ability_id, "'description'"]
	)

	text = _base_text_copy()
	var original: Dictionary = text["en"]
	ability_text = (original["abilities"] as Dictionary)[ability_id]
	ability_text["name"] = true
	registry = _load("text_name_bool", _base_structure_copy(), text)
	_expect_error("英文名称写成布尔", registry, ["en.json", ability_id, "'name'"])


func _case_translation_exceptions() -> void:
	var ability_id := _first_ability_id()
	var english_name := _ability_name(_base_text["en"], ability_id)
	_expect(not english_name.is_empty(), "基准数据里没有英文名称，这一组断言无从谈起。")

	# 1. Nobody declared anything: a copy is a bug.
	var text := _base_text_copy()
	_localised(text, "zh-CN", ability_id)["name"] = english_name
	var registry := _load("copy_undeclared", _base_structure_copy(), text)
	_expect_error(
		"中英名称完全相同且没有声明",
		registry,
		["not translated", ability_id, "untranslated_fields"]
	)

	# 2. Declared, field by field: the same copy is accepted.
	text = _base_text_copy()
	var entry := _localised(text, "zh-CN", ability_id)
	entry["name"] = english_name
	entry["untranslated_fields"] = ["name"]
	registry = _load("copy_declared", _base_structure_copy(), text)
	_expect_valid("名称声明为保留原文", registry)

	# 3. The declaration outlived the reason: the field was translated after all.
	text = _base_text_copy()
	entry = _localised(text, "zh-CN", ability_id)
	entry["name"] = "路感（已经翻译了）"
	entry["untranslated_fields"] = ["name"]
	registry = _load("copy_declared_but_translated", _base_structure_copy(), text)
	_expect_error(
		"声明保留原文，但字段已经翻译",
		registry,
		["declares", "untranslated_fields"]
	)

	# 4. The exception is per field: naming `name` must not excuse an identical
	#    description.
	text = _base_text_copy()
	entry = _localised(text, "zh-CN", ability_id)
	entry["name"] = english_name
	entry["untranslated_fields"] = ["name"]
	entry["description"] = _ability_description(_base_text["en"], ability_id)
	registry = _load("copy_declared_other_field", _base_structure_copy(), text)
	_expect_error(
		"只声明了名称，说明仍然照抄",
		registry,
		["not translated", "description"]
	)

	# 5. The reference language has nothing to except itself from.
	text = _base_text_copy()
	_localised(text, "en", ability_id)["untranslated_fields"] = ["name"]
	registry = _load("copy_declared_reference", _base_structure_copy(), text)
	_expect_error(
		"在英文里声明保留原文",
		registry,
		["untranslated_fields", "translated language"]
	)

	# 6. The declaration may only name prose fields.
	text = _base_text_copy()
	_localised(text, "zh-CN", ability_id)["untranslated_fields"] = ["speaker"]
	registry = _load("copy_declared_wrong_field", _base_structure_copy(), text)
	_expect_error(
		"声明了一个不是文本的字段",
		registry,
		["untranslated_fields", "speaker"]
	)

	# 7. It has to be an array of names, not a string and not a duplicated list.
	text = _base_text_copy()
	_localised(text, "zh-CN", ability_id)["untranslated_fields"] = "name"
	registry = _load("copy_declared_not_array", _base_structure_copy(), text)
	_expect_error("untranslated_fields 写成字符串", registry, ["untranslated_fields", "array"])

	text = _base_text_copy()
	_localised(text, "zh-CN", ability_id)["untranslated_fields"] = ["name", "name"]
	registry = _load("copy_declared_twice", _base_structure_copy(), text)
	_expect_error("untranslated_fields 重复列出同一个字段", registry, ["twice"])


func _case_existing_checks_still_fire() -> void:
	var ability_id := _first_ability_id()

	# Text for a voice the structure does not define.
	var text := _base_text_copy()
	(text["zh-CN"]["abilities"] as Dictionary)["ghost_voice"] = {
		"name": "多出来的声音", "description": "结构里没有这个声音。"
	}
	var registry := _load("orphan_text", _base_structure_copy(), text)
	_expect_error("中文里多了一个结构中没有的声音", registry, ["ghost_voice", "no entry in"])

	# A voice the structure defines that the language forgot.
	text = _base_text_copy()
	(text["zh-CN"]["abilities"] as Dictionary).erase(ability_id)
	registry = _load("missing_text", _base_structure_copy(), text)
	_expect_error("中文里漏掉了一个声音", registry, [ability_id, "no text"])

	# Two voices claiming one speaker.
	var structure := _base_structure_copy()
	var speaker := String((structure["abilities"] as Dictionary)[ability_id].get("speaker", ""))
	(structure["abilities"] as Dictionary)["probe_voice"] = {
		"value": 1, "speaker": speaker, "max_passive": 1
	}
	text = _base_text_copy()
	for locale: String in L10n.LOCALES:
		(text[locale]["abilities"] as Dictionary)["probe_voice"] = {
			"name": "探针" if locale == "zh-CN" else "Probe",
			"description": "第二个声音，只在这个测试里存在。" if locale == "zh-CN" else "A second voice, only in this test.",
		}
	registry = _load("duplicate_speaker", structure, text)
	_expect_error("两个声音共用同一个说话者", registry, ["already used by ability", speaker])


# --- assertions -------------------------------------------------------------


func _expect_valid(label: String, registry: InnerAbilities) -> void:
	_checks += 1
	if registry.is_valid():
		return
	_failures.append("%s：应该通过，却报了错：%s" % [label, registry.describe_errors()])


func _expect_error(label: String, registry: InnerAbilities, needles: Array) -> void:
	_checks += 1
	if registry.is_valid():
		_failures.append("%s：应该被拒绝，却通过了。" % label)
		return
	var reported := registry.describe_errors()
	for needle: Variant in needles:
		if not reported.contains(String(needle)):
			_failures.append(
				"%s：错误里没有「%s」。实际报的是：%s" % [label, String(needle), reported.left(700)]
			)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


# --- fixture ----------------------------------------------------------------


func _load_base() -> bool:
	var structure: Variant = JSON.parse_string(_read(STRUCTURE))
	if not (structure is Dictionary):
		_failures.append("读不出 %s。" % STRUCTURE)
		return false
	_base_structure = structure
	for locale: String in L10n.LOCALES:
		var path := "res://data/abilities/%s.json" % locale
		var text: Variant = JSON.parse_string(_read(path))
		if not (text is Dictionary):
			_failures.append("读不出 %s。" % path)
			return false
		_base_text[locale] = text
	return true


func _base_structure_copy() -> Dictionary:
	return _base_structure.duplicate(true)


func _base_text_copy() -> Dictionary:
	var copy: Dictionary = {}
	for locale: String in L10n.LOCALES:
		copy[locale] = (_base_text[locale] as Dictionary).duplicate(true)
	return copy


func _localised(text: Dictionary, locale: String, ability_id: String) -> Dictionary:
	return (text[locale]["abilities"] as Dictionary)[ability_id]


func _ability_name(text: Variant, ability_id: String) -> String:
	if not (text is Dictionary):
		return ""
	var abilities: Variant = (text as Dictionary).get("abilities", {})
	if not (abilities is Dictionary):
		return ""
	var entry: Variant = (abilities as Dictionary).get(ability_id, {})
	if not (entry is Dictionary):
		return ""
	return String((entry as Dictionary).get("name", ""))


func _ability_description(text: Variant, ability_id: String) -> String:
	if not (text is Dictionary):
		return ""
	var abilities: Variant = (text as Dictionary).get("abilities", {})
	if not (abilities is Dictionary):
		return ""
	var entry: Variant = (abilities as Dictionary).get(ability_id, {})
	if not (entry is Dictionary):
		return ""
	return String((entry as Dictionary).get("description", ""))


func _first_rule(structure: Dictionary) -> Dictionary:
	var rules: Variant = structure.get("passives", [])
	if not (rules is Array) or (rules as Array).is_empty():
		return {}
	var first: Variant = (rules as Array)[0]
	return first if first is Dictionary else {}


func _first_ability_id() -> String:
	var abilities: Variant = _base_structure.get("abilities", {})
	if not (abilities is Dictionary) or (abilities as Dictionary).is_empty():
		return ""
	return String((abilities as Dictionary).keys()[0])


## Writes one registry into its own folder and loads it through the real loader. A fresh
## folder per case keeps one case's mistakes out of the next one's verdict.
func _load(case_name: String, structure: Dictionary, text: Dictionary) -> InnerAbilities:
	var dir := "%s/%s" % [ROOT, case_name]
	_clear_dir(dir)
	_write("%s/abilities.json" % dir, JSON.stringify(structure, "  "))
	for locale: String in L10n.LOCALES:
		_write("%s/%s.json" % [dir, locale], JSON.stringify(text[locale], "  "))
	return InnerAbilities.load_all(dir)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("写不了 %s（错误码 %d）。" % [path, FileAccess.get_open_error()])
		return
	file.store_string(text)
	file.close()


func _clear_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [path, name]))
	for name: String in DirAccess.get_directories_at(path):
		_clear_dir("%s/%s" % [path, name])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

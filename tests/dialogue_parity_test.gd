extends SceneTree
## Exercises the production JSON parser and parity checker with translated prose.
const Harness = preload("res://tests/test_harness.gd")
const DIR := "user://parity_test"
var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 60.0, "dialogue_parity_test.gd")
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var en := _fixture("en")
	var zh := _fixture("zh-CN")
	_expect_match("identical structure, translated text", en, zh)
	# Both the legacy choice-level requires and the conditions spelling are
	# normalized by the parser and must be compared, separately from node rules.
	for field in ["requires", "all_flags", "not_flags"]:
		var broken: Dictionary = zh.duplicate(true)
		var choice: Dictionary = broken["conversations"]["fixture"]["nodes"][0]["choices"][0]
		match field:
			"requires":
				choice["requires"]["legacy_flag"] = false
			"all_flags":
				choice["conditions"]["all_flags"] = ["other_flag"]
			"not_flags":
				choice["conditions"]["not_flags"] = ["other_flag"]
		_expect_mismatch("choice %s" % field, en, broken, "choice 'try'", field)
	var condition_broken: Dictionary = zh.duplicate(true)
	condition_broken["conversations"]["fixture"]["nodes"][0]["choices"][0]["conditions"]["requires"]["condition_flag"] = "changed"
	_expect_mismatch("nested choice requires", en, condition_broken, "choice 'try'", "requires")
	var effect_broken: Dictionary = zh.duplicate(true)
	effect_broken["conversations"]["fixture"]["nodes"][0]["choices"][0]["effects"][0]["value"] = "true"
	_expect_mismatch("effect value type", en, effect_broken, "choice 'try'", "value")
	var en_check: Dictionary = en.duplicate(true)
	var zh_check: Dictionary = zh.duplicate(true)
	for fixture: Dictionary in [en_check, zh_check]:
		var option: Dictionary = fixture["conversations"]["fixture"]["nodes"][0]["choices"][0]
		option.erase("next")
		option["check"] = {"id": "parity_check", "ability": "pattern", "difficulty": 6,
			"success": "result", "failure": "failure"}
		fixture["conversations"]["fixture"]["nodes"].append(
			{"id": "failure", "speaker": "q", "text": "Failure", "next": null})
	_expect_match("matching check", en_check, zh_check)
	zh_check["conversations"]["fixture"]["nodes"][0]["choices"][0]["check"]["difficulty"] = 7
	_expect_mismatch("check difficulty", en_check, zh_check, "choice 'try'", "check")
	var node_broken: Dictionary = zh.duplicate(true)
	node_broken["conversations"]["fixture"]["nodes"][1]["tags"] = ["changed"]
	_expect_mismatch("node tags", en, node_broken, "result", "tags")
	Harness.finish(self, _failures, "dialogue parity checks choice conditions and structural fields.")


func _fixture(locale: String) -> Dictionary:
	return {
		"format_version": 2,
		"locale": locale,
		"chapter": "fixture",
		"conversations": {
			"fixture": {
				"start": "hub",
				"default_source": "observed",
				"nodes": [
					{
						"id": "hub", "speaker": "q", "text": "A" if locale == "en" else "甲",
						"choices": [{
							"id": "try", "text": "Try" if locale == "en" else "试试",
							"next": "result", "requires": {"legacy_flag": true},
							"conditions": {"requires": {"condition_flag": "yes"},
								"all_flags": ["ready"], "not_flags": ["done"]},
							"effects": [{"type": "set_flag", "flag": "chosen", "value": true}],
						}],
					},
					{"id": "result", "speaker": "q", "text": "B" if locale == "en" else "乙",
					 "tags": ["fixture"], "next": null},
				],
			},
		},
	}


func _load(name: String, data: Dictionary) -> DialogueGraph:
	var path := "%s/%s.json" % [DIR, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Cannot write parity fixture %s." % path)
		return null
	file.store_string(JSON.stringify(data))
	file.close()
	var graph := DialogueGraph.load_from_file(path)
	if not graph.is_valid():
		_failures.append("Invalid parity fixture %s: %s" % [name, " | ".join(graph.errors)])
	return graph


func _expect_match(label: String, en: Dictionary, zh: Dictionary) -> void:
	var problems := DialogueParity.compare(_load("reference", en), _load("translation", zh))
	if not problems.is_empty():
		_failures.append("%s should pass: %s" % [label, " | ".join(problems)])


func _expect_mismatch(label: String, en: Dictionary, zh: Dictionary, context: String, field: String) -> void:
	var problems := DialogueParity.compare(_load("reference", en), _load("translation", zh))
	var joined := " | ".join(problems)
	if problems.is_empty() or not joined.contains(context) or not joined.contains(field):
		_failures.append("%s did not report %s/%s: %s" % [label, context, field, joined])

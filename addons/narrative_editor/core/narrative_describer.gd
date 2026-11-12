extends RefCounted
## Editor-only: builds the read-only listing, editable text-field models, and structure descriptions.
##
## The store owns the editing session and file writes. This helper reads its live document and
## structure dictionaries to present the data without owning or changing the underlying files.

const JsonText := preload("res://addons/narrative_editor/core/narrative_json_text.gd")

const KIND_DIALOGUE := "dialogue"
const KIND_INSPECTIONS := "inspections"
const KIND_ABILITIES := "abilities"

var kind: String = KIND_DIALOGUE
var locales: Array[String] = []
var reference_locale: String = "en"
var errors: Array[String] = []

var _docs: Dictionary = {}
var _structure: Dictionary = {}
var _ability_structure_path: String = ""
var _ability_text_leaves: Array[String] = []
var _inspection_fields_spec: Array[Dictionary] = []


## Binds the helper to the Store's current documents; dictionaries and errors stay owned by Store.
func configure(
	unit_kind: String,
	unit_locales: Array[String],
	unit_reference_locale: String,
	documents: Dictionary,
	structures: Dictionary,
	store_errors: Array[String],
	ability_structure_path: String,
	ability_text_leaves: Array[String],
	inspection_fields: Array[Dictionary]
) -> void:
	kind = unit_kind
	locales = unit_locales
	reference_locale = unit_reference_locale
	_docs = documents
	_structure = structures
	errors = store_errors
	_ability_structure_path = ability_structure_path
	_ability_text_leaves = ability_text_leaves
	_inspection_fields_spec = inspection_fields


# --- listing ----------------------------------------------------------------


func list_ids() -> Array[String]:
	var ids: Array[String] = []
	var root: Variant = _structure.get(reference_locale, null)
	if not (root is Dictionary):
		return ids
	var data: Dictionary = root
	match kind:
		KIND_DIALOGUE:
			var conversations: Variant = data.get("conversations", null)
			if conversations is Dictionary:
				for key: Variant in (conversations as Dictionary).keys():
					ids.append(String(key))
		KIND_INSPECTIONS:
			for key: Variant in data.keys():
				if _is_inspection_entry(key, data):
					ids.append(String(key))
		KIND_ABILITIES:
			var abilities: Variant = data.get("abilities", null)
			if abilities is Dictionary:
				for key: Variant in (abilities as Dictionary).keys():
					ids.append(String(key))
	return ids


## Every node of a conversation, in file order, with enough text to recognise it in a list.
func node_entries(conversation_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var nodes: Variant = _conversation_value(conversation_id, "nodes")
	if not (nodes is Array):
		return entries
	var node_list: Array = nodes
	for index in node_list.size():
		var node: Variant = node_list[index]
		if not (node is Dictionary):
			continue
		var data: Dictionary = node
		var node_id := String(data.get("id", ""))
		var speaker := String(data.get("speaker", ""))
		var text := _effective([
			"conversations",
			conversation_id,
			"nodes",
			index,
			"text",
		], reference_locale, "")
		var choices: Variant = data.get("choices", [])
		var has_choices := choices is Array and (choices as Array).size() > 0
		var has_check := data.get("check") is Dictionary
		entries.append(
			{
				"index": index,
				"id": node_id,
				"speaker": speaker,
				"label": _list_label(index, node_id, speaker, text, has_choices, has_check),
				"text": text,
				"has_choices": has_choices,
				"has_check": has_check,
			}
		)
	return entries


func conversation_defaults(conversation_id: String) -> Dictionary:
	return {
		"default_source": String(_conversation_value(conversation_id, "default_source", "observed")),
		"subjective": bool(_conversation_value(conversation_id, "subjective", false)),
		"start": String(_conversation_value(conversation_id, "start", "")),
	}


# --- models -----------------------------------------------------------------


## Read-only summary plus the editable text fields of one dialogue node.
func node_model(conversation_id: String, node_index: int) -> Dictionary:
	var model := _empty_model("对话节点")
	var node := _node_value(conversation_id, node_index)
	if node.is_empty():
		errors.append("找不到节点：%s 里的第 %d 个节点。" % [conversation_id, node_index])
		return model
	var defaults := conversation_defaults(conversation_id)
	var node_id := String(node.get("id", ""))
	var speaker := String(node.get("speaker", ""))
	var source := String(node.get("source", ""))
	if source.is_empty():
		source = "（跟随对话的默认值：%s）" % String(defaults["default_source"])
	model["title"] = "%s / %s" % [conversation_id, node_id]
	model["header"] = [
		{"label": "节点 ID", "value": node_id},
		{"label": "说话者", "value": speaker},
		{"label": "叙述来源", "value": source},
	]
	model["fields"] = _node_fields(conversation_id, node_index)
	model["structure_text"] = _describe_node(conversation_id, node_index, node, defaults)
	model["context"] = {"conversation": conversation_id, "node_index": node_index, "node_id": node_id}
	return model


func inspection_model(inspection_id: String) -> Dictionary:
	var model := _empty_model("检视内容")
	var entry := _inspection_value(inspection_id)
	if entry.is_empty():
		errors.append("找不到检视内容：%s。" % inspection_id)
		return model
	model["title"] = inspection_id
	model["header"] = [
		{"label": "检视 ID", "value": inspection_id},
		{"label": "说话者（只读）", "value": String(entry.get("speaker", "protagonist"))},
		{"label": "叙述来源（只读）", "value": String(entry.get("source", ""))},
	]
	model["fields"] = _inspection_fields(inspection_id)
	model["structure_text"] = _describe_inspection(entry)
	model["context"] = {"inspection_id": inspection_id}
	return model


func ability_model(ability_id: String) -> Dictionary:
	var model := _empty_model("内心声音文案")
	var entry := _ability_value(ability_id)
	if entry.is_empty():
		errors.append("找不到内心声音：%s。" % ability_id)
		return model
	model["title"] = ability_id
	model["header"] = [
		{"label": "声音 ID（只读）", "value": ability_id},
		{"label": "数值（只读）", "value": str(entry.get("value", 0))},
		{"label": "说话者（只读）", "value": String(entry.get("speaker", ""))},
		{"label": "被动上限（只读）", "value": str(entry.get("max_passive", ""))},
	]
	model["fields"] = _ability_fields(ability_id)
	model["structure_text"] = _describe_ability(ability_id, entry)
	model["context"] = {"ability_id": ability_id}
	return model


func _empty_model(title: String) -> Dictionary:
	return {"title": title, "header": [], "fields": [], "structure_text": "", "context": {}}


# --- field construction -----------------------------------------------------


func all_fields() -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	match kind:
		KIND_DIALOGUE:
			for conversation_id: String in list_ids():
				for field: Dictionary in _conversation_fields(conversation_id):
					fields.append(field)
		KIND_INSPECTIONS:
			for inspection_id: String in list_ids():
				for field: Dictionary in _inspection_fields(inspection_id):
					fields.append(field)
		KIND_ABILITIES:
			for ability_id: String in list_ids():
				for field: Dictionary in _ability_fields(ability_id):
					fields.append(field)
	return fields


func _conversation_fields(conversation_id: String) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	var nodes: Variant = _conversation_value(conversation_id, "nodes")
	if not (nodes is Array):
		return fields
	var node_list: Array = nodes
	for index in node_list.size():
		for field: Dictionary in _node_fields(conversation_id, index):
			fields.append(field)
	return fields


func _node_fields(conversation_id: String, node_index: int) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	var node := _node_value(conversation_id, node_index)
	if node.is_empty():
		return fields
	var node_id := String(node.get("id", ""))
	var speaker := String(node.get("speaker", ""))
	var base := ["conversations", conversation_id, "nodes", node_index]
	# A hub node may have no `text` at all: a field the file does not carry is not offered,
	# because the editor never adds a key to a node.
	if _has_address(base + ["text"]):
		fields.append(
			_make_field(
				"text",
				"正文（%s · %s）" % [node_id, speaker],
				base + ["text"],
				"node",
				{
					"conversation": conversation_id,
					"node_index": node_index,
					"node_id": node_id,
					"choice_index": -1,
					"search_context": "%s %s" % [node_id, speaker],
				}
			)
		)
	var choices: Variant = node.get("choices", [])
	if choices is Array:
		var choice_list: Array = choices
		for choice_index in choice_list.size():
			var choice: Variant = choice_list[choice_index]
			if not (choice is Dictionary):
				continue
			var choice_id := "选项 %d" % choice_index
			var choice_data: Dictionary = choice
			fields.append(
				_make_field(
					"choice.%d.text" % choice_index,
					"选项「%s」的文字" % String(choice_data.get("id", choice_id)),
					base + ["choices", choice_index, "text"],
					"choice",
					{
						"conversation": conversation_id,
						"node_index": node_index,
						"node_id": node_id,
						"choice_index": choice_index,
						"choice_id": String(choice_data.get("id", "")),
						"search_context": String(choice_data.get("id", "")),
					}
				)
			)
	return fields


func _inspection_fields(inspection_id: String) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	if _inspection_value(inspection_id).is_empty():
		return fields
	for spec: Dictionary in _inspection_fields_spec:
		var address: Array = [inspection_id, String(spec["key"])]
		if spec.has("sub"):
			address.append(String(spec["sub"]))
		if not _has_address(address):
			continue
		fields.append(
			_make_field(
				String(spec["field_id"]),
				String(spec["label"]),
				address,
				"inspection",
				{"inspection_id": inspection_id, "search_context": inspection_id}
			)
		)
	return fields


func _ability_fields(ability_id: String) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	if _ability_value(ability_id).is_empty():
		return fields
	for leaf: String in _ability_text_leaves:
		var address: Array = ["abilities", ability_id, leaf]
		if not _has_address(address):
			continue
		var label := "名称" if leaf == "name" else "说明"
		fields.append(
			_make_field(
				leaf,
				"%s（%s）" % [label, ability_id],
				address,
				"ability",
				{"ability_id": ability_id, "search_context": ability_id}
			)
		)
	return fields


func _make_field(
	field_id: String,
	label: String,
	address: Array,
	field_kind: String,
	context: Dictionary
) -> Dictionary:
	var values: Dictionary = {}
	for locale: String in locales:
		values[locale] = _effective(address, locale, "")
	var field := {
		"field_id": field_id,
		"label": label,
		"address": address,
		"kind": field_kind,
		"values": values,
		"multiline": true,
	}
	field.merge(context, true)
	return field


## The text as the author currently sees it in one language, which is the pending edit
## while there is one and the file on disk otherwise. Lists and search read through this,
## so an unsaved line is searchable and the node list does not lag behind the text box.
##
## The language is a parameter and not `reference_locale`, because the dock shows both
## languages side by side: reading the reference document for every language put the
## English line in the Chinese box, and the author would have been editing English text
## that was labelled Chinese.
func _effective(address: Array, locale: String, fallback: String) -> String:
	var doc: Variant = _docs.get(locale, null)
	if doc == null:
		return fallback
	return (doc as JsonText).effective_string(address, fallback)


# --- structure text ---------------------------------------------------------


func _describe_node(
	conversation_id: String, node_index: int, node: Dictionary, defaults: Dictionary
) -> String:
	var lines: Array[String] = []
	lines.append("对话：%s" % conversation_id)
	lines.append("默认叙述来源：%s" % String(defaults["default_source"]))
	lines.append("主观想象对话：%s" % ("是" if bool(defaults["subjective"]) else "否"))
	lines.append("对话起点：%s" % String(defaults["start"]))
	lines.append("")
	lines.append("节点：%s（文件里的第 %d 个）" % [String(node.get("id", "")), node_index + 1])
	lines.append("说话者：%s" % String(node.get("speaker", "")))
	lines.append("叙述来源：%s" % String(node.get("source", "（跟随默认值）")))
	lines.append("下一节点：%s" % _describe_next(node))
	lines.append("条件：%s" % _describe_conditions(node.get("conditions", null)))
	lines.append("效果：%s" % _describe_effects(node.get("effects", [])))
	lines.append("检定：%s" % _describe_check(node.get("check", null)))
	var tags: Variant = node.get("tags", null)
	if tags is Array and (tags as Array).size() > 0:
		lines.append("标签：%s" % ", ".join(PackedStringArray(tags)))
	lines.append("")
	var choices: Variant = node.get("choices", [])
	if choices is Array and (choices as Array).size() > 0:
		lines.append("选项（只读）：")
		var index := 0
		for choice: Variant in (choices as Array):
			if choice is Dictionary:
				var data: Dictionary = choice
				lines.append(
					"  %d. id=%s → %s%s%s"
					% [
						index,
						String(data.get("id", "")),
						String(data.get("next", "")),
						"  [once]" if bool(data.get("once", false)) else "",
						"" if not data.has("conditions") else "  [有条件]",
					]
				)
				if data.has("effects"):
					lines.append("     效果：%s" % _describe_effects(data.get("effects", [])))
			index += 1
	else:
		lines.append("选项：无")
	return "\n".join(lines)


func _describe_inspection(entry: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("说话者：%s" % String(entry.get("speaker", "protagonist")))
	lines.append("叙述来源：%s" % String(entry.get("source", "")))
	lines.append("回忆条目 ID：%s" % _entry_id(entry, "recall"))
	lines.append("记录条目 ID：%s" % _entry_id(entry, "record"))
	lines.append("记录来源：%s" % _record_source(entry))
	lines.append("效果（只读）：%s" % _describe_effects(entry.get("effects", [])))
	return "\n".join(lines)


func _describe_ability(ability_id: String, entry: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("声音 ID：%s" % ability_id)
	lines.append("数值：%s（只读）" % str(entry.get("value", 0)))
	lines.append("说话者：%s（只读）" % String(entry.get("speaker", "")))
	lines.append("每局被动上限：%s（只读）" % str(entry.get("max_passive", "")))
	lines.append("")
	lines.append("被动规则（只读）：")
	var rules := _ability_rules(ability_id)
	if rules.is_empty():
		lines.append("  无")
	for rule: Dictionary in rules:
		lines.append(
			"  %s：%s:%s → %s（%s%s）"
			% [
				String(rule["id"]),
				String(rule["trigger_kind"]),
				String(rule["trigger_id"]),
				String(rule["conversation"]),
				"只触发一次" if bool(rule["once"]) else "可重复触发",
				"" if (rule["requires"] as Array).is_empty() else "，需要 " + ", ".join(PackedStringArray(rule["requires"])),
			]
		)
	return "\n".join(lines)


func _describe_next(node: Dictionary) -> String:
	if not node.has("next"):
		return "（不写：接着文件里的下一条）"
	var raw: Variant = node["next"]
	if raw == null:
		return "null（对话到这里结束）"
	return String(raw)


func _describe_conditions(raw: Variant) -> String:
	if not (raw is Dictionary):
		return "无"
	var data: Dictionary = raw
	var parts: Array[String] = []
	for key: Variant in data.keys():
		parts.append("%s=%s" % [String(key), JSON.stringify(data[key])])
	if parts.is_empty():
		return "无"
	return "；".join(PackedStringArray(parts))


func _describe_effects(raw: Variant) -> String:
	if not (raw is Array) or (raw as Array).is_empty():
		return "无"
	var parts: Array[String] = []
	for effect: Variant in (raw as Array):
		if not (effect is Dictionary):
			parts.append(str(effect))
			continue
		var data: Dictionary = effect
		var effect_type := String(data.get("type", ""))
		match effect_type:
			"set_flag":
				parts.append("设为 %s=%s" % [String(data.get("flag", "")), JSON.stringify(data.get("value", true))])
			"set_objective":
				parts.append("目标 → %s" % String(data.get("key", "")))
			"record":
				parts.append(
					"记录 %s（%s）" % [String(data.get("entry_id", "")), String(data.get("source", ""))]
				)
			_:
				parts.append(JSON.stringify(data))
	return "；".join(PackedStringArray(parts))


func _describe_check(raw: Variant) -> String:
	if not (raw is Dictionary):
		return "无"
	var data: Dictionary = raw
	var parts: Array[String] = [
		"能力=%s" % String(data.get("ability", "")),
		"难度=%s" % str(data.get("difficulty", "")),
		"类型=%s" % String(data.get("kind", "")),
		"成功→%s" % String(data.get("success", "")),
		"失败→%s" % String(data.get("failure", "")),
	]
	if data.has("modifiers"):
		parts.append("修正=%s" % JSON.stringify(data.get("modifiers")))
	if bool(data.get("repeatable", false)):
		parts.append("可重复")
	return "，".join(PackedStringArray(parts))


func _entry_id(entry: Dictionary, key: String) -> String:
	var block: Variant = entry.get(key, null)
	if not (block is Dictionary):
		return "（无）"
	return String((block as Dictionary).get("entry_id", "（无）"))


func _record_source(entry: Dictionary) -> String:
	var block: Variant = entry.get("record", null)
	if not (block is Dictionary):
		return "（无）"
	return String((block as Dictionary).get("source", ""))


func _list_label(
	index: int,
	node_id: String,
	speaker: String,
	text: String,
	has_choices: bool,
	has_check: bool
) -> String:
	var marks: Array[String] = []
	if has_choices:
		marks.append("选项")
	if has_check:
		marks.append("检定")
	var suffix := "" if marks.is_empty() else "  【%s】" % "、".join(PackedStringArray(marks))
	var flat := " ".join(text.split("\n", false))
	if flat.length() > 34:
		flat = flat.substr(0, 34) + "…"
	return "%d. %s · %s：%s%s" % [index + 1, node_id, speaker, flat, suffix]


func _is_inspection_entry(key: Variant, data: Dictionary) -> bool:
	if String(key) in ["format_version", "locale"]:
		return false
	var value: Variant = data[key]
	if not (value is Dictionary):
		return false
	return (value as Dictionary).has("text") or (value as Dictionary).has("title")


func _has_address(address: Array) -> bool:
	for locale: String in locales:
		var doc: Variant = _docs.get(locale, null)
		if doc != null and (doc as JsonText).has_path(address):
			return true
	return false


func _conversation_value(conversation_id: String, key: String, fallback: Variant = null) -> Variant:
	var root: Variant = _structure.get(reference_locale, null)
	if not (root is Dictionary):
		return fallback
	var conversations: Variant = (root as Dictionary).get("conversations", null)
	if not (conversations is Dictionary):
		return fallback
	var conversation: Variant = (conversations as Dictionary).get(conversation_id, null)
	if not (conversation is Dictionary):
		return fallback
	if not (conversation as Dictionary).has(key):
		return fallback
	return (conversation as Dictionary)[key]


func _node_value(conversation_id: String, node_index: int) -> Dictionary:
	var nodes: Variant = _conversation_value(conversation_id, "nodes")
	if not (nodes is Array):
		return {}
	var node_list: Array = nodes
	if node_index < 0 or node_index >= node_list.size():
		return {}
	var node: Variant = node_list[node_index]
	if not (node is Dictionary):
		return {}
	return node


func _inspection_value(inspection_id: String) -> Dictionary:
	var root: Variant = _structure.get(reference_locale, null)
	if not (root is Dictionary):
		return {}
	var data: Dictionary = root
	if not data.has(inspection_id):
		return {}
	var entry: Variant = data[inspection_id]
	if not (entry is Dictionary):
		return {}
	return entry


func _ability_value(ability_id: String) -> Dictionary:
	var root: Variant = _structure.get(reference_locale, null)
	if not (root is Dictionary):
		return {}
	var abilities: Variant = (root as Dictionary).get("abilities", null)
	if not (abilities is Dictionary):
		return {}
	var entry: Variant = (abilities as Dictionary).get(ability_id, null)
	if not (entry is Dictionary):
		return {}
	return entry


## The passive rules that point at this voice, read from `abilities.json`. Read-only.
func _ability_rules(ability_id: String) -> Array[Dictionary]:
	var rules: Array[Dictionary] = []
	var text := _read_file_text(_ability_structure_path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return rules
	var raw: Variant = (parsed as Dictionary).get("passives", [])
	if not (raw is Array):
		return rules
	for rule: Variant in (raw as Array):
		if not (rule is Dictionary):
			continue
		var data: Dictionary = rule
		if String(data.get("ability", "")) != ability_id:
			continue
		var trigger: Variant = data.get("trigger", {})
		var trigger_data: Dictionary = trigger if trigger is Dictionary else {}
		var requires: Array[String] = []
		var raw_requires: Variant = data.get("requires", [])
		if raw_requires is Array:
			for flag: Variant in (raw_requires as Array):
				requires.append(String(flag))
		rules.append(
			{
				"id": String(data.get("id", "")),
				"trigger_kind": String(trigger_data.get("kind", "")),
				"trigger_id": String(trigger_data.get("id", "")),
				"conversation": String(data.get("conversation", "")),
				"once": bool(data.get("once", true)),
				"requires": requires,
			}
		)
	return rules


func _read_file_text(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

extends RefCounted

## Editor-only: turns the parts of one dialogue node, inspection or passive rule into the
## read-only text the describer shows. Moved out of `narrative_describer.gd` to keep that file
## under the 600-line cap (issue #349). Preload-only, no `class_name`, no state: every function
## is a pure function of the entry it is given, so nothing here reads the store or the
## describer's documents.

static func describe_next(node: Dictionary) -> String:
	if not node.has("next"):
		return "（不写：接着文件里的下一条）"
	var raw: Variant = node["next"]
	if raw == null:
		return "null（对话到这里结束）"
	return String(raw)


static func describe_conditions(raw: Variant) -> String:
	if not (raw is Dictionary):
		return "无"
	var data: Dictionary = raw
	var parts: Array[String] = []
	for key: Variant in data.keys():
		parts.append("%s=%s" % [String(key), JSON.stringify(data[key])])
	if parts.is_empty():
		return "无"
	return "；".join(PackedStringArray(parts))


static func describe_effects(raw: Variant) -> String:
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
			"camera_focus":
				parts.append("聚焦 → %s" % String(data.get("target", "")))
			_:
				parts.append(JSON.stringify(data))
	return "；".join(PackedStringArray(parts))


static func describe_check(raw: Variant) -> String:
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


static func entry_id(entry: Dictionary, key: String) -> String:
	var block: Variant = entry.get(key, null)
	if not (block is Dictionary):
		return "（无）"
	return String((block as Dictionary).get("entry_id", "（无）"))


static func record_source(entry: Dictionary) -> String:
	var block: Variant = entry.get("record", null)
	if not (block is Dictionary):
		return "（无）"
	return String((block as Dictionary).get("source", ""))

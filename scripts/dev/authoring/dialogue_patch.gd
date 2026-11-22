extends RefCounted
## The narrow, portable authoring format. An operation names content, never a path.
## Work on a copy; only return it if the actual game parser accepts the whole chapter.

const FORMAT := "where-is-school/dialogue-draft"
const VERSION := 1
const LOCALE := "zh-CN"
const MAX_FIELD_CHARS := 8000
const MAX_BYTES := 2 * 1024 * 1024
const MAX_OPS := 1024
const ID_PREFIX := "author_"


static func new_id() -> String:
	return ID_PREFIX + Crypto.new().generate_random_bytes(12).hex_encode()


static func digest(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()


static func authored_text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= MAX_FIELD_CHARS


static func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	return json.data


static func valid_envelope(draft: Dictionary) -> bool:
	return draft.get("format") == FORMAT and draft.get("version") == VERSION \
		and draft.get("locale") == LOCALE and draft.get("chapters") is Dictionary


static func get_conversation(data: Dictionary, id: String) -> Dictionary:
	return data.get("conversations", {}).get(id, {})


static func find_record(rows: Array, id: String) -> Dictionary:
	for val: Variant in rows:
		if val is Dictionary and val.get("id") == id:
			return val
	return {}


static func can_insert(node: Dictionary) -> bool:
	return not node.is_empty() and node.get("choices", []).is_empty() \
		and not node.has("check") and not node.has("conditions") and not node.has("requires")


static func can_add_choice(node: Dictionary) -> bool:
	return not node.is_empty() and not node.get("choices", []).is_empty() \
		and not node.has("next") and not node.has("check") \
		and not node.has("conditions") and not node.has("requires")


static func continuation(nodes: Array, node: Dictionary) -> Variant:
	if node.has("next"):
		return node["next"]
	var index := nodes.find(node)
	return nodes[index + 1]["id"] if index >= 0 and index + 1 < nodes.size() else null


static func choice_signature(node: Dictionary) -> String:
	var choices: Array = node.get("choices", []).duplicate(true)
	for choice: Dictionary in choices:
		choice.erase("text")
	return digest(choices)


static func _valid_new_id(value: Variant) -> bool:
	if not value is String or not value.begins_with(ID_PREFIX) or value.length() != ID_PREFIX.length() + 24:
		return false
	for letter: String in value.substr(ID_PREFIX.length()):
		if not letter in "0123456789abcdef":
			return false
	return true


static func _speaker_known(nodes: Array, speaker: Variant) -> bool:
	if not speaker is String or speaker.is_empty():
		return false
	for node: Dictionary in nodes:
		if node.get("speaker") == speaker:
			return true
	return false


static func _new_reply(nodes: Array, reply: Dictionary) -> Dictionary:
	var id: Variant = reply.get("id")
	if not _valid_new_id(id) or not find_record(nodes, id).is_empty():
		return {}
	var speaker: Variant = reply.get("speaker")
	var text: Variant = reply.get("text")
	var target: Variant = reply.get("next")
	if not _speaker_known(nodes, speaker) or not authored_text(text) \
			or (target != null and (not target is String or find_record(nodes, target).is_empty())):
		return {}
	# Only these fields travel into game data, never a caller-supplied condition/effect.
	return {"id": id, "speaker": speaker, "text": text, "next": target}


static func apply_chapter(base: Dictionary, chapter: String, entry: Dictionary) -> Dictionary:
	var ops: Variant = entry.get("ops")
	if not ops is Array or ops.is_empty() or ops.size() > MAX_OPS:
		return {"error": "修改列表为空或超出上限。"}
	if entry.get("result") == digest(base):
		return {"data": base, "graph": DialogueGraph.load_from_data(base, chapter), "already_applied": true}
	var candidate := base.duplicate(true)
	var added_choices: Array[Dictionary] = []
	for v: Variant in ops:
		if not v is Dictionary:
			return {"error": "修改操作格式无效。"}
		var op: Dictionary = v
		var error := _apply_op(candidate, op)
		if not error.is_empty():
			return {"error": "%s / %s / %s：%s" % [chapter, op.get("conversation", "?"), op.get("node", "?"), error]}
		if op["kind"] == "choice":
			added_choices.append(op)
	var graph := DialogueGraph.load_from_data(candidate, "authoring:%s" % chapter)
	if not graph.is_valid():
		return {"error": "分支未应用：\n%s" % "\n".join(graph.errors)}
	for choice: Dictionary in added_choices:
		var conversation := graph.get_conversation(StringName(choice["conversation"]))
		if DialogueGraph.reachable_nodes(conversation, StringName(choice["next"])).has(StringName(choice["node"])):
			return {"error": "%s / %s：新选项不能绕回这个选择点。" % [choice["conversation"], choice["node"]]}
	return {"data": candidate, "graph": graph, "already_applied": false}


static func _apply_op(data: Dictionary, op: Dictionary) -> String:
	if not op.get("conversation") is String or not op.get("node") is String:
		return "缺少会话或节点 ID。"
	var conversation := get_conversation(data, op["conversation"])
	var nodes: Array = conversation.get("nodes", [])
	var node := find_record(nodes, op["node"])
	if node.is_empty():
		return "找不到原节点；它可能已被移动或删除。"
	match op.get("kind"):
		"text":
			if not op.get("choice") is String or not op.get("before") is String or not authored_text(op.get("text")):
				return "需要有效的文案（1–8000 字符）。"
			var slot := node
			if not String(op["choice"]).is_empty():
				slot = find_record(node.get("choices", []), op["choice"])
			if slot.is_empty():
				return "原选项已删除。"
			var current: String = slot.get("text", "")
			if current != op["before"] and current != op["text"]:
				return "同一字段已在另一版本修改；没有覆盖。"
			slot["text"] = op["text"]
		"insert":
			if not can_insert(node) or not op.get("reply") is Dictionary or not op.has("before"):
				return "这里只能在不带检定、选项或条件的普通节点后插句。"
			var previous: Variant = continuation(nodes, node)
			if previous != op["before"]:
				return "原来的后续已改变；没有覆盖。"
			var reply := _new_reply(nodes, op["reply"])
			if reply.is_empty() or reply["next"] != previous:
				return "新对白必须接回原后续，且 ID、说话人和正文有效。"
			nodes.insert(nodes.find(node) + 1, reply)
			node["next"] = reply["id"]
		"choice":
			if not can_add_choice(node) or choice_signature(node) != op.get("before"):
				return "该选择点不支持添加，或已有分支结构已变。"
			var id: Variant = op.get("id")
			var target: Variant = op.get("next")
			var text: Variant = op.get("text")
			if not _valid_new_id(id) or not authored_text(text) or not target is String:
				return "新选项需要有效的 ID、文案和去向。"
			var choices: Array = node["choices"]
			if not find_record(choices, id).is_empty():
				return "该选项 ID 已存在；没有重复添加。"
			var raw_reply: Variant = op.get("reply")
			if raw_reply != null:
				if not raw_reply is Dictionary:
					return "新回应格式不正确。"
				var reply := _new_reply(nodes, raw_reply)
				if reply.is_empty() or reply["id"] != target:
					return "新回应需要有效的说话人、正文和接回点。"
				# A choice hub has no fall-through; inserting here cannot steal an edge
				# from an unrelated node which uses implicit file order.
				nodes.insert(nodes.find(node) + 1, reply)
			elif find_record(nodes, target).is_empty():
				return "选项的去向不存在。"
			choices.append({"id": id, "text": text, "next": target})
		_:
			return "不支持的操作。"
	return ""

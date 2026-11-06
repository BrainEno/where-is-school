extends RefCounted
class_name DialogueContent
## Small, project-owned prototype format. JSON keeps lines independently editable
## and permits validation without coupling the content to a dialogue addon.

const KINDS: Array[String] = ["statement", "observation", "recollection", "imagination", "choice", "branch"]
const FLAG_PREFIXES: Array[String] = ["observed.", "statement.", "recollection.", "imagination.", "choice."]


static func validate(data: Variant, path: String) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not data is Dictionary or not data.has("conversations") or not data["conversations"] is Dictionary:
		errors.append("%s: expected an object with a conversations object." % path)
		return errors
	var conversations: Dictionary = data["conversations"]
	if conversations.is_empty():
		errors.append("%s: conversations must not be empty." % path)
	for conversation_id: Variant in conversations:
		var where: String = "%s: conversation '%s'" % [path, conversation_id]
		var conversation: Variant = conversations[conversation_id]
		if not String(conversation_id).is_valid_identifier() or not conversation is Dictionary:
			errors.append("%s must have a stable identifier and an object value." % where)
			continue
		if not conversation.has("nodes") or not conversation["nodes"] is Dictionary:
			errors.append("%s: nodes must be an object." % where)
			continue
		var nodes: Dictionary = conversation["nodes"]
		if not conversation.get("start") is String or not nodes.has(conversation.get("start")):
			errors.append("%s: start must reference an existing node." % where)
		for node_id: Variant in nodes:
			var node_where: String = "%s, node '%s'" % [where, node_id]
			var node: Variant = nodes[node_id]
			if not String(node_id).is_valid_identifier() or not node is Dictionary:
				errors.append("%s must have a stable identifier and an object value." % node_where)
				continue
			var kind: String = str(node.get("kind", ""))
			if not KINDS.has(kind):
				errors.append("%s: invalid kind '%s'." % [node_where, kind])
				continue
			if kind == "branch":
				if not node.get("cases") is Array or node["cases"].is_empty():
					errors.append("%s: branch requires a nonempty cases array." % node_where)
				else:
					for item: Variant in node["cases"]:
						if not item is Dictionary or not item.has("equals") or not _valid_flag(str(item.get("flag", ""))):
							errors.append("%s: branch case requires a categorized flag and equals value." % node_where)
						else:
							_check_target(item.get("next"), nodes, node_where + " case", errors)
				_check_target(node.get("default"), nodes, node_where + " default", errors)
				if node.has("effects"):
					errors.append("%s: branch nodes cannot have effects." % node_where)
				continue
			if not node.get("speaker") is String or str(node.get("speaker", "")).strip_edges().is_empty():
				errors.append("%s: speaker must be a nonempty string." % node_where)
			if not node.get("text") is String or str(node.get("text", "")).strip_edges().is_empty():
				errors.append("%s: text must be a nonempty string." % node_where)
			_check_effects(node.get("effects", []), kind, str(node.get("speaker", "")), node_where, errors)
			if kind == "choice":
				if not node.get("choices") is Array or node["choices"].size() < 2:
					errors.append("%s: choice requires at least two options." % node_where)
				else:
					for option: Variant in node["choices"]:
						if not option is Dictionary or not option.get("text") is String or str(option.get("text", "")).strip_edges().is_empty():
							errors.append("%s: each choice needs nonempty text." % node_where)
							continue
						_check_target(option.get("next"), nodes, node_where + " choice", errors)
						_check_effects(option.get("effects", []), "choice", "YOU", node_where + " choice", errors)
			elif node.has("next"):
				_check_target(node["next"], nodes, node_where, errors)
	return errors


static func _check_target(target: Variant, nodes: Dictionary, where: String, errors: PackedStringArray) -> void:
	if not target is String or not nodes.has(target):
		errors.append("%s: next/default must reference an existing node (got '%s')." % [where, target])


static func _valid_flag(flag: String) -> bool:
	for prefix: String in FLAG_PREFIXES:
		if flag.begins_with(prefix) and flag.length() > prefix.length():
			return true
	return false


static func _check_effects(effects: Variant, kind: String, speaker: String, where: String, errors: PackedStringArray) -> void:
	if not effects is Array:
		errors.append("%s: effects must be an array." % where)
		return
	for effect: Variant in effects:
		if not effect is Dictionary:
			errors.append("%s: each effect must be an object." % where)
			continue
		var category: String = str(effect.get("category", ""))
		var identifier: String = str(effect.get("id", ""))
		var allowed: bool = false
		match kind:
			"statement":
				allowed = category == "statement" and str(effect.get("source", "")) == speaker.to_lower() and ["q", "n"].has(speaker.to_lower())
			"choice":
				allowed = category in ["choice", "recollection"]
			"recollection":
				allowed = category == "recollection"
			"imagination":
				allowed = category == "imagination"
			_: # Observations are recorded by the scene that actually performs them.
				allowed = false
		if not allowed or not identifier.is_valid_identifier() or not effect.has("value"):
			errors.append("%s: invalid or out-of-bound effect '%s.%s' for %s." % [where, category, identifier, kind])
		elif not (effect["value"] is bool or effect["value"] is String or effect["value"] is int or effect["value"] is float):
			errors.append("%s: effect values must be simple scalar data." % where)

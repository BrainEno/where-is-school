extends RefCounted
class_name DialogueScript
## A validated, ordered conversation graph. Content authors build one of these
## in data/dialogue/*.gd; nothing in this class touches the scene tree.

var id: StringName = &""
var title: String = ""
var start_id: StringName = &""
var _nodes: Dictionary = {}


static func create(script_id: StringName, script_title: String = "") -> DialogueScript:
	var script := DialogueScript.new()
	script.id = script_id
	script.title = script_title if not script_title.is_empty() else String(script_id)
	return script


func add(node: DialogueNode) -> DialogueScript:
	if node == null:
		push_error("DialogueScript.add received a null node.")
		return self
	if _nodes.has(node.id):
		push_error("DialogueScript '%s' has a duplicate node id '%s'." % [String(id), String(node.id)])
		return self
	_nodes[node.id] = node
	return self


func get_node(node_id: StringName) -> DialogueNode:
	return _nodes.get(node_id)


func has_node(node_id: StringName) -> bool:
	return _nodes.has(node_id)


func node_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for key in _nodes.keys():
		result.append(key)
	return result


func node_count() -> int:
	return _nodes.size()


func start_node() -> DialogueNode:
	return get_node(start_id)


func first_node() -> DialogueNode:
	if has_node(start_id):
		return get_node(start_id)
	for key in _nodes.keys():
		return _nodes[key]
	return null


## Returns a list of human-readable problems. An empty array means the graph can
## be played: every jump target exists, every node can terminate, and every node
## has something to show.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if _nodes.is_empty():
		problems.append("Dialogue script '%s' has no nodes." % String(id))
		return problems
	if not String(start_id).is_empty() and not has_node(start_id):
		problems.append(
			"Dialogue script '%s' declares start node '%s' which does not exist."
			% [String(id), String(start_id)]
		)
	for node_id in _nodes.keys():
		var node: DialogueNode = _nodes[node_id]
		var where := "%s/%s" % [String(id), String(node_id)]
		# A node with choices but no lines of its own is legitimate: the prompt was
		# already shown by the previous node. A node with neither is not.
		if node.lines.is_empty() and not node.has_choices():
			problems.append("Node '%s' has neither lines nor choices." % where)
		for line in node.lines:
			if not line.is_valid():
				problems.append("Node '%s' contains an invalid line." % where)
		if node.has_choices():
			for choice in node.choices:
				if not choice.is_valid():
					problems.append("Node '%s' has an invalid choice." % where)
					continue
				if String(choice.goto).is_empty():
					continue
				if not has_node(choice.goto):
					problems.append(
						"Node '%s' choice '%s' jumps to missing node '%s'."
						% [where, String(choice.id), String(choice.goto)]
					)
		elif not String(node.next_id).is_empty() and not has_node(node.next_id):
			problems.append(
				"Node '%s' continues to missing node '%s'." % [where, String(node.next_id)]
			)
	return problems


## Total number of player-facing choices, used by tests and by the docs.
func choice_count() -> int:
	var total := 0
	for node_id in _nodes.keys():
		total += (_nodes[node_id] as DialogueNode).choices.size()
	return total

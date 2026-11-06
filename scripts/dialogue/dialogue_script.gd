class_name DialogueScript
extends RefCounted
## Container for one authored conversation graph (see data/dialogue/).
##
## A DialogueScript is plain data built in GDScript, deliberately not a Godot
## Resource: the content is short, reviewable in a diff, and needs no editor
## round-trip. It is validated by tests/dialogue_content_test.gd so a broken
## branch fails CI instead of surfacing as a silent dead end at runtime.

var id: StringName
var nodes: Dictionary = {}
var start_id: StringName = &""
## character id -> {name_zh, name_en, portrait_tint, note_zh, note_en}
var characters: Dictionary = {}


func _init(p_id: StringName) -> void:
	id = p_id


func define_character(
	character_id: StringName,
	name_zh: String,
	name_en: String,
	tint: Color,
	note_zh: String = "",
	note_en: String = ""
) -> DialogueScript:
	characters[character_id] = {
		"id": character_id,
		"name_zh": name_zh,
		"name_en": name_en,
		"tint": tint,
		"note_zh": note_zh,
		"note_en": note_en,
	}
	return self


func add(node: DialogueNode) -> DialogueScript:
	if node == null:
		push_error("DialogueScript '%s' tried to add a null node." % id)
		return self
	if nodes.has(node.id):
		push_error("DialogueScript '%s' has duplicate node id '%s'." % [id, node.id])
		return self
	nodes[node.id] = node
	if start_id == &"":
		start_id = node.id
	return self


func set_start(node_id: StringName) -> DialogueScript:
	start_id = node_id
	return self


func get_node_by_id(node_id: StringName) -> DialogueNode:
	return nodes.get(node_id)


func character(character_id: StringName) -> Dictionary:
	return characters.get(character_id, {})


## Returns a (possibly empty) list of human-readable problems: missing ids,
## dangling continuations, unknown speakers, invalid provenance, duplicate choice
## ids. Empty means the graph is safe to play.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var label: String = "dialogue:%s" % id
	if nodes.is_empty():
		problems.append("%s has no nodes." % label)
		return problems
	if not nodes.has(start_id):
		problems.append("%s start node '%s' does not exist." % [label, start_id])

	for node_id: StringName in nodes:
		var node: DialogueNode = nodes[node_id]
		problems.append_array(node.validate(label))
		for line: DialogueLine in node.lines:
			if line.speaker != &"" and not characters.has(line.speaker):
				problems.append("%s/%s: unknown speaker '%s'." % [label, node_id, line.speaker])
		if node.next_id != &"" and not nodes.has(node.next_id):
			problems.append("%s/%s: continuation '%s' does not exist." % [label, node_id, node.next_id])
		var seen_choices: Dictionary = {}
		for choice: DialogueChoice in node.choices:
			if seen_choices.has(choice.id):
				problems.append("%s/%s: duplicate choice id '%s'." % [label, node_id, choice.id])
			seen_choices[choice.id] = true
			if choice.next_id != &"" and not nodes.has(choice.next_id):
				problems.append("%s/%s: choice '%s' points at missing node '%s'." % [label, node_id, choice.id, choice.next_id])
	return problems


## Ids of nodes that are declared but unreachable from start_id. Reported by
## tests as information, not as a failure: a deliberate orphan is a writing bug
## worth seeing during review.
func unreachable_node_ids() -> Array[StringName]:
	var reachable: Dictionary = {}
	if not nodes.has(start_id):
		return []
	var queue: Array[StringName] = [start_id]
	while not queue.is_empty():
		var current: StringName = queue.pop_back()
		if reachable.has(current) or not nodes.has(current):
			continue
		reachable[current] = true
		var node: DialogueNode = nodes[current]
		if node.next_id != &"":
			queue.append(node.next_id)
		for choice: DialogueChoice in node.choices:
			if choice.next_id != &"":
				queue.append(choice.next_id)
	var unreachable: Array[StringName] = []
	for node_id: StringName in nodes:
		if not reachable.has(node_id):
			unreachable.append(node_id)
	return unreachable

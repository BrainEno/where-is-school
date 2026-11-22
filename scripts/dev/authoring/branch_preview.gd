extends RefCounted
## A second instance of the game's walker, never a second walker implementation.
## The state nodes are deliberately detached and never registered as autoloads.

const Flags := preload("res://scripts/autoload/game_state.gd")
const Knowledge := preload("res://scripts/autoload/narrative_state.gd")

signal ended

var _panel: DialoguePanel
var _flags: Node
var _knowledge: Node
var _runtime: DialogueRuntime
var _characters: CharacterDirectory
var _abilities: InnerAbilities
var _last_shape := []


func _init(panel: DialoguePanel) -> void:
	_panel = panel
	_abilities = InnerAbilities.load_all()
	_abilities.set_locale(L10n.current)
	_characters = CharacterDirectory.load_all(_abilities)


func show_node(graph: DialogueGraph, conversation: String, node_id: String) -> void:
	var entry := graph.get_conversation(StringName(conversation)) if graph != null else null
	if entry == null or not entry.nodes.has(StringName(node_id)):
		_last_shape = []
		_panel.close()
		return
	var node: DialogueGraph.DialogueNode = entry.nodes[StringName(node_id)]
	var shape := [graph.chapter, conversation, node_id, node.speaker_id]
	var presented := []
	var words := PackedStringArray()
	for choice: DialogueGraph.DialogueChoice in node.choices:
		shape.append(choice.choice_id)
		words.append(choice.text)
		presented.append({"text": choice.text, "choice_id": choice.choice_id})
	if _last_shape == shape:
		_panel.update_preview_text(node.text, words)
	else:
		_panel.show_line(DialogueRuntime.compose_line(entry, node, _characters, _abilities))
		_panel.set_choices(presented)
	_last_shape = shape


func has_line() -> bool:
	return not _last_shape.is_empty()

func start(graph: DialogueGraph, conversation: String, flags: Dictionary, knowledge: Dictionary, seed_value: int) -> bool:
	stop()
	_flags = Flags.new()
	_flags.replace_snapshot(flags)
	_knowledge = Knowledge.new()
	_knowledge.restore_snapshot(knowledge)
	_runtime = DialogueRuntime.new(_flags, _knowledge, _characters, _abilities, CheckResolver.new(seed_value))
	_runtime.line_changed.connect(_line)
	_runtime.choices_changed.connect(_choices)
	_runtime.conversation_finished.connect(_finished)
	return _runtime.start(graph, StringName(conversation))


func _line(line: Dictionary) -> void:
	_panel.show_line(line)


func _choices(choices: Array) -> void:
	var line := _runtime.get_current_line()
	if not choices.is_empty() and String(line.get("text", "")).is_empty():
		_panel.show_line(line)
	_panel.set_choices(choices)


func _finished(_id: StringName) -> void:
	_panel.close()
	ended.emit()


func advance() -> void:
	if _runtime != null and _runtime.is_active():
		_runtime.advance()


func choose(index: int) -> void:
	if _runtime != null and _runtime.is_active():
		_runtime.choose(index)


func stop() -> void:
	_last_shape = []
	if is_instance_valid(_panel):
		_panel.close()
	if _runtime != null:
		# Disconnect before releasing nodes that this instance can write to.
		_runtime.line_changed.disconnect(_line)
		_runtime.choices_changed.disconnect(_choices)
		_runtime.conversation_finished.disconnect(_finished)
		_runtime = null
	if is_instance_valid(_flags):
		_flags.free()
	if is_instance_valid(_knowledge):
		_knowledge.free()
	_flags = null
	_knowledge = null

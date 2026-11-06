class_name DialogueLibrary
extends RefCounted
## Loads every dialogue content file once and resolves conversations by id.
##
## Dialogue content stays in data/dialogue/*.json so it can be reviewed, diffed
## and later localised without touching gameplay scripts. Keeping the loader
## behind this class is also the seam a future Dialogic adapter would replace
## (see docs/ARCHITECTURE.md section 5).

const DIALOGUE_PATHS: Array[String] = [
	"res://data/dialogue/opening.json",
]

var errors: Array[String] = []
var _graphs: Array[DialogueGraph] = []
var _conversation_index: Dictionary = {}


static func load_all() -> DialogueLibrary:
	var library := DialogueLibrary.new()
	for path in DIALOGUE_PATHS:
		var graph := DialogueGraph.load_from_file(path)
		library._graphs.append(graph)
		for message in graph.errors:
			library.errors.append(message)
		for conversation_id: StringName in graph.get_conversation_ids():
			if library._conversation_index.has(conversation_id):
				library.errors.append(
					"Conversation '%s' is defined in more than one content file." % conversation_id
				)
				continue
			library._conversation_index[conversation_id] = graph
	return library


func is_valid() -> bool:
	return errors.is_empty()


func has_conversation(conversation_id: StringName) -> bool:
	return _conversation_index.has(conversation_id)


func get_graph(conversation_id: StringName) -> DialogueGraph:
	return _conversation_index.get(conversation_id, null)


func get_conversation(conversation_id: StringName) -> DialogueGraph.Conversation:
	var graph := get_graph(conversation_id)
	if graph == null:
		return null
	return graph.get_conversation(conversation_id)


func get_conversation_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _conversation_index.keys():
		ids.append(key)
	return ids


## Speaker ids referenced anywhere in the content, so tests can prove every
## speaker has a CharacterProfile instead of trusting the author.
func get_referenced_speaker_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for graph in _graphs:
		for speaker_id: Variant in graph.speaker_ids.keys():
			var typed := StringName(String(speaker_id))
			if not ids.has(typed):
				ids.append(typed)
	return ids


func describe_errors() -> String:
	if errors.is_empty():
		return "Dialogue content loaded without errors."
	return "Dialogue content has %d error(s):\n%s" % [errors.size(), "\n".join(errors)]

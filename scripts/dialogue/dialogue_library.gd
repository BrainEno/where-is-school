class_name DialogueLibrary
extends RefCounted
## Loads every dialogue chapter in every language once, then resolves
## conversations in the language currently on screen.
##
## Layout:
##   data/dialogue/<locale>/<chapter>.json    e.g. data/dialogue/zh-CN/street.json
##
## Two jobs beyond lookup:
## - parse errors from *any* language fail loudly at start-up, so a broken
##   translation cannot ship unnoticed;
## - DialogueParity is run between the reference language and every other one,
##   and objective keys are checked against the locale tables, so a translator
##   cannot drop a branch or point at a label that does not exist.

const CHAPTERS: Array[String] = ["prologue", "street", "residential", "playground"]
const DIALOGUE_DIR := "res://data/dialogue"

var errors: Array[String] = []
var _graphs: Dictionary = {}
var _index: Dictionary = {}
var _locale: String = L10n.DEFAULT_LOCALE


static func chapter_path(locale: String, chapter: String) -> String:
	return "%s/%s/%s.json" % [DIALOGUE_DIR, locale, chapter]


static func load_all() -> DialogueLibrary:
	var library := DialogueLibrary.new()
	for locale in L10n.LOCALES:
		library._graphs[locale] = {}
		library._index[locale] = {}
		var check_ids: Dictionary = {}
		for rule: Dictionary in PassiveVoices.RULES.values():
			check_ids[String(rule["check_id"])] = "passive voice rule"
		for chapter in CHAPTERS:
			var path := chapter_path(locale, chapter)
			var graph := DialogueGraph.load_from_file(path)
			for message in graph.errors:
				library.errors.append(message)
			library._graphs[locale][chapter] = graph
			for conversation_id: StringName in graph.get_conversation_ids():
				var index: Dictionary = library._index[locale]
				if index.has(conversation_id):
					library.errors.append(
						"%s: conversation '%s' is also defined in another chapter. "
						% [path, conversation_id]
						+ "Conversation ids must be unique across a language."
					)
					continue
				index[conversation_id] = graph
			library._check_objective_keys(graph)
			library._check_unique_checks(graph, check_ids)

	library._check_parity()
	library.set_locale(L10n.current)
	return library


func set_locale(locale: String) -> bool:
	var code := L10n.normalize(locale)
	if not _index.has(code):
		errors.append("DialogueLibrary: no content loaded for locale '%s'." % locale)
		return false
	_locale = code
	return true


func get_locale() -> String:
	return _locale


func is_valid() -> bool:
	return errors.is_empty()


func get_chapters() -> Array[String]:
	return CHAPTERS.duplicate()


func has_conversation(conversation_id: StringName) -> bool:
	return _index.get(_locale, {}).has(conversation_id)


func get_graph(conversation_id: StringName) -> DialogueGraph:
	var index: Dictionary = _index.get(_locale, {})
	return index.get(conversation_id, null)


func get_conversation(conversation_id: StringName) -> DialogueGraph.Conversation:
	var graph := get_graph(conversation_id)
	if graph == null:
		return null
	return graph.get_conversation(conversation_id)


func get_conversation_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _index.get(_locale, {}).keys():
		ids.append(key)
	return ids


func get_graphs_for(locale: String) -> Array[DialogueGraph]:
	var result: Array[DialogueGraph] = []
	var chapters: Dictionary = _graphs.get(L10n.normalize(locale), {})
	for chapter in CHAPTERS:
		if chapters.has(chapter):
			result.append(chapters[chapter])
	return result


## Speaker ids referenced anywhere in the content, so tests can prove every
## speaker has a CharacterProfile instead of trusting the author.
func get_referenced_speaker_ids(locale: String = "") -> Array[StringName]:
	var ids: Array[StringName] = []
	for graph in get_graphs_for(locale if not locale.is_empty() else _locale):
		for speaker_id: Variant in graph.speaker_ids.keys():
			var typed := StringName(String(speaker_id))
			if not ids.has(typed):
				ids.append(typed)
	return ids


## Check IDs are session-wide cache keys, not merely local choice labels.
func _check_unique_checks(graph: DialogueGraph, seen: Dictionary) -> void:
	for conversation_id: StringName in graph.get_conversation_ids():
		var conversation: DialogueGraph.Conversation = graph.get_conversation(conversation_id)
		for node_id: StringName in conversation.order:
			var node: DialogueGraph.DialogueNode = conversation.nodes[node_id]
			for choice: DialogueGraph.DialogueChoice in node.choices:
				if choice.check.is_empty():
					continue
				var check_id := String(choice.check["id"])
				var label := "%s:%s/%s/%s" % [graph.source_path, conversation_id, node_id, choice.choice_id]
				if seen.has(check_id):
					errors.append("%s: duplicate check id '%s' (also %s)." % [label, check_id, seen[check_id]])
				else:
					seen[check_id] = label


func _check_parity() -> void:
	var reference_locale: String = L10n.LOCALES[0]
	for chapter in CHAPTERS:
		var reference: DialogueGraph = _graphs[reference_locale][chapter]
		for locale in L10n.LOCALES:
			if locale == reference_locale:
				continue
			var other: DialogueGraph = _graphs[locale][chapter]
			errors.append_array(DialogueParity.compare(reference, other))


## `set_objective` stores a locale key, never literal text, so every key it names
## must exist in the language file it appears in.
func _check_objective_keys(graph: DialogueGraph) -> void:
	for conversation_id: StringName in graph.get_conversation_ids():
		var conversation: DialogueGraph.Conversation = graph.get_conversation(conversation_id)
		for node_id: StringName in conversation.order:
			var node: DialogueGraph.DialogueNode = conversation.nodes[node_id]
			var label := "%s: %s/%s" % [graph.source_path, conversation_id, node_id]
			for effect: Dictionary in node.effects:
				_check_objective_effect(effect, label, graph.locale)
			for choice: DialogueGraph.DialogueChoice in node.choices:
				for effect: Dictionary in choice.effects:
					_check_objective_effect(
						effect, "%s choice '%s'" % [label, choice.choice_id], graph.locale
					)


func _check_objective_effect(effect: Dictionary, label: String, locale: String) -> void:
	if String(effect.get("type", "")) != "set_objective":
		return
	var key := String(effect.get("key", ""))
	if key.is_empty():
		return
	if not L10n.has_key(key, locale):
		errors.append(
			"%s: objective key '%s' does not exist in data/locale/%s.json." % [label, key, locale]
		)


func describe_errors() -> String:
	if errors.is_empty():
		return "Dialogue content loaded without errors."
	return "Dialogue content has %d error(s):\n%s" % [errors.size(), "\n".join(errors)]

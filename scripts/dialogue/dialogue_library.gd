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

const CHAPTERS: Array[String] = [
	"prologue", "corridor", "street", "residential", "alley", "playground",
	# Inner-voice reactions live in their own chapter: they are not part of a
	# place, and keeping them separate makes it obvious how much of the game is
	# the protagonist talking to himself.
	"inner_voice",
]
const DIALOGUE_DIR := "res://data/dialogue"

var errors: Array[String] = []
var _graphs: Dictionary = {}
## Which inner voices exist, so a check cannot name a voice nobody implemented.
## Optional: a test may load dialogue without the ability registry.
var _abilities: InnerAbilities = null
var _index: Dictionary = {}
var _locale: String = L10n.DEFAULT_LOCALE

## What the last `load_all()` actually cost and actually loaded, so the size of the corpus
## is a number instead of an impression. Shape:
##
##     {
##       "total_usec": int,                       # the whole load, all languages
##       "locales": {
##         "zh-CN": {
##           "bytes": int, "conversations": int, "nodes": int, "usec": int,
##           "chapters": { "prologue": {"bytes": int, "conversations": int,
##                                      "nodes": int, "usec": int}, ... },
##         }, ...
##       },
##     }
##
## Filled once per load, never per frame. The loader is still "every chapter, every
## language, at start-up": this reports that cost, it does not change it.
var load_report: Dictionary = {}


static func chapter_path(locale: String, chapter: String) -> String:
	return "%s/%s/%s.json" % [DIALOGUE_DIR, locale, chapter]


static func load_all(abilities: InnerAbilities = null) -> DialogueLibrary:
	var library := DialogueLibrary.new()
	library._abilities = abilities
	var started := Time.get_ticks_usec()
	for locale in L10n.LOCALES:
		library._graphs[locale] = {}
		library._index[locale] = {}
		for chapter in CHAPTERS:
			var path := chapter_path(locale, chapter)
			var chapter_started := Time.get_ticks_usec()
			var graph := DialogueGraph.load_from_file(path)
			library._note_chapter(
				locale, chapter, path, graph, Time.get_ticks_usec() - chapter_started
			)
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
			library._check_check_abilities(graph)

	library._check_parity()
	library.load_report["total_usec"] = Time.get_ticks_usec() - started
	library._print_load_report()
	library.set_locale(L10n.current)
	return library


## Adds one chapter's size, counts and parse time to `load_report`.
func _note_chapter(
	locale: String, chapter: String, path: String, graph: DialogueGraph, usec: int
) -> void:
	var bytes := _file_bytes(path)
	var conversations := graph.get_conversation_ids().size()
	var nodes := 0
	for conversation_id: StringName in graph.get_conversation_ids():
		var conversation := graph.get_conversation(conversation_id)
		if conversation != null:
			nodes += conversation.nodes.size()
	var locales: Dictionary = load_report.get("locales", {})
	var entry: Dictionary = locales.get(
		locale, {"bytes": 0, "conversations": 0, "nodes": 0, "usec": 0, "chapters": {}}
	)
	entry["bytes"] = int(entry["bytes"]) + bytes
	entry["conversations"] = int(entry["conversations"]) + conversations
	entry["nodes"] = int(entry["nodes"]) + nodes
	entry["usec"] = int(entry["usec"]) + usec
	var chapters: Dictionary = entry["chapters"]
	chapters[chapter] = {
		"bytes": bytes, "conversations": conversations, "nodes": nodes, "usec": usec
	}
	entry["chapters"] = chapters
	locales[locale] = entry
	load_report["locales"] = locales


static func _file_bytes(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


## The report as text: the same numbers the console gets, for a test or a document.
func describe_load_report() -> String:
	if load_report.is_empty():
		return "DialogueLibrary: nothing loaded."
	var lines: Array[String] = []
	lines.append(
		"DialogueLibrary: %d language(s) in %.1f ms."
		% [int(load_report.get("locales", {}).size()), int(load_report.get("total_usec", 0)) / 1000.0]
	)
	var locales: Dictionary = load_report.get("locales", {})
	for locale: String in locales.keys():
		var entry: Dictionary = locales[locale]
		lines.append(
			"  %s: %.1f KB, %d conversations, %d nodes, parsed in %.1f ms"
			% [
				locale,
				int(entry["bytes"]) / 1024.0,
				int(entry["conversations"]),
				int(entry["nodes"]),
				int(entry["usec"]) / 1000.0,
			]
		)
		var chapters: Dictionary = entry["chapters"]
		for chapter: String in CHAPTERS:
			if not chapters.has(chapter):
				continue
			var chapter_entry: Dictionary = chapters[chapter]
			lines.append(
				"    %s: %.1f KB, %d conversations, %d nodes, %.1f ms"
				% [
					chapter,
					int(chapter_entry["bytes"]) / 1024.0,
					int(chapter_entry["conversations"]),
					int(chapter_entry["nodes"]),
					int(chapter_entry["usec"]) / 1000.0,
				]
			)
	return "\n".join(lines)


func get_load_report() -> Dictionary:
	return load_report


## Printed at start-up in debug builds only: the corpus size is a development number, not
## something a player should see in a console.
func _print_load_report() -> void:
	if not OS.is_debug_build():
		return
	print(describe_load_report())


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


## A check without a real voice would roll at value 0 forever, which reads as a
## broken scene rather than as a hard check.
func _check_check_abilities(graph: DialogueGraph) -> void:
	if _abilities == null:
		return
	for conversation_id: StringName in graph.get_conversation_ids():
		var conversation: DialogueGraph.Conversation = graph.get_conversation(conversation_id)
		for node_id: StringName in conversation.order:
			var node: DialogueGraph.DialogueNode = conversation.nodes[node_id]
			if node.check.is_empty():
				continue
			var ability_id: StringName = node.check.get("ability", &"")
			if not _abilities.has_ability(ability_id):
				errors.append(
					"%s: %s/%s rolls a check on unknown inner voice '%s'."
					% [graph.source_path, conversation_id, node_id, ability_id]
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

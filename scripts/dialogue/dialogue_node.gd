class_name DialogueNode
extends RefCounted
## A single beat in a conversation graph: some lines, then either choices or a
## single continuation.
##
## Nodes never touch the scene tree. PrologueFlow reads them, applies their flag
## and ledger effects, and tells DialoguePanel what to draw.

var id: StringName
var lines: Array[DialogueLine] = []
var choices: Array[DialogueChoice] = []
## Used when there are no choices. Empty next_id ends the conversation.
var next_id: StringName
## Flags written when the node is entered.
var on_enter_flags: Array[StringName] = []
## Ledger entries recorded when the node is entered: {id, kind, zh, en}.
var on_enter_records: Array[Dictionary] = []


func _init(p_id: StringName) -> void:
	id = p_id


## Convenience builder so content files read as a script rather than as
## nested constructor calls.
func say(
	speaker: StringName,
	text_zh: String,
	text_en: String,
	kind: int = NarrativeProvenance.Kind.HEARD,
	style: StringName = &""
) -> DialogueNode:
	lines.append(DialogueLine.new(speaker, text_zh, text_en, kind, style))
	return self


func note(text_zh: String, text_en: String, kind: int = NarrativeProvenance.Kind.OBSERVED, style: StringName = &"interior") -> DialogueNode:
	lines.append(DialogueLine.new(&"", text_zh, text_en, kind, style))
	return self


func choose(
	choice_id: StringName,
	text_zh: String,
	text_en: String,
	next: StringName,
	flags: Array[StringName] = [],
	records: Array[Dictionary] = [],
	aside_zh: String = "",
	aside_en: String = ""
) -> DialogueNode:
	choices.append(DialogueChoice.new(choice_id, text_zh, text_en, next, flags, records, aside_zh, aside_en))
	return self


func go_to(next: StringName) -> DialogueNode:
	next_id = next
	return self


func set_flags(flags: Array[StringName]) -> DialogueNode:
	on_enter_flags = flags
	return self


func record(entry_id: StringName, kind: int, text_zh: String, text_en: String) -> DialogueNode:
	on_enter_records.append({"id": entry_id, "kind": NarrativeProvenance.id_of(kind), "zh": text_zh, "en": text_en})
	return self


func validate(owner_label: String) -> Array[String]:
	var label: String = "%s/%s" % [owner_label, id]
	var problems: Array[String] = []
	if id == &"":
		problems.append("%s: node has an empty id." % owner_label)
	if lines.is_empty() and choices.is_empty() and next_id == &"":
		problems.append("%s: node is empty and dead-ends." % label)
	for line: DialogueLine in lines:
		problems.append_array(line.validate(label))
	for choice: DialogueChoice in choices:
		problems.append_array(choice.validate(label))
	if not choices.is_empty() and next_id != &"":
		problems.append("%s: node has both choices and a plain continuation." % label)
	for record: Dictionary in on_enter_records:
		if not NarrativeProvenance.has_id(str(record.get("kind", ""))):
			problems.append("%s: on-enter record uses unknown provenance." % label)
	return problems

class_name DialogueChoice
extends RefCounted
## One selectable reply in a dialogue node.
##
## Content is authored here as plain objects inside DialogueScript files rather
## than as hard-coded control flow, so writers can add branches without touching
## gameplay scripts.

var id: StringName
var text_zh: String
var text_en: String
var next_id: StringName
## Story flags written when this choice is taken. Applied by PrologueFlow.
var flags: Array[StringName]
## Narrative ledger entries recorded when this choice is taken. Each item is a
## dictionary: {id, kind, zh, en}. See NarrativeProvenance for kind ids.
var records: Array[Dictionary]
## Optional line the protagonist says to themself after choosing. Empty = none.
var aside_zh: String
var aside_en: String


func _init(
	p_id: StringName,
	p_text_zh: String,
	p_text_en: String,
	p_next_id: StringName,
	p_flags: Array[StringName] = [],
	p_records: Array[Dictionary] = [],
	p_aside_zh: String = "",
	p_aside_en: String = ""
) -> void:
	id = p_id
	text_zh = p_text_zh
	text_en = p_text_en
	next_id = p_next_id
	flags = p_flags
	records = p_records
	aside_zh = p_aside_zh
	aside_en = p_aside_en


func validate(owner_label: String) -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("%s: a choice has an empty id." % owner_label)
	if text_zh.strip_edges().is_empty():
		problems.append("%s: choice '%s' has no Chinese text." % [owner_label, id])
	if text_en.strip_edges().is_empty():
		problems.append("%s: choice '%s' has no English text." % [owner_label, id])
	if next_id == &"":
		problems.append("%s: choice '%s' does not point anywhere." % [owner_label, id])
	for record: Dictionary in records:
		if not record.has("id") or not record.has("kind") or not record.has("zh"):
			problems.append("%s: choice '%s' has an incomplete ledger record." % [owner_label, id])
		elif not NarrativeProvenance.has_id(str(record["kind"])):
			problems.append("%s: choice '%s' uses unknown provenance '%s'." % [owner_label, id, record["kind"]])
	return problems

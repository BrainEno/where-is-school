class_name DialogueLine
extends RefCounted
## One spoken/described exchange inside a dialogue node.
##
## `speaker` is a character id from DialogueScript "characters"; an empty speaker
## means the line is not spoken by anyone (stage direction, interior observation).

var speaker: StringName
var text_zh: String
var text_en: String
var kind: int
## Optional tag for presentation variation, e.g. "interior" for the protagonist's
## own half-formed thoughts. Presentation only; never read by gameplay logic.
var style: StringName


func _init(
	p_speaker: StringName,
	p_text_zh: String,
	p_text_en: String,
	p_kind: int = NarrativeProvenance.Kind.HEARD,
	p_style: StringName = &""
) -> void:
	speaker = p_speaker
	text_zh = p_text_zh
	text_en = p_text_en
	kind = p_kind
	style = p_style


func validate(owner_label: String) -> Array[String]:
	var problems: Array[String] = []
	if text_zh.strip_edges().is_empty():
		problems.append("%s: a line has no Chinese text." % owner_label)
	if text_en.strip_edges().is_empty():
		problems.append("%s: a line has no English text." % owner_label)
	if not NarrativeProvenance.is_valid(kind):
		problems.append("%s: line '%s' has invalid provenance." % [owner_label, text_zh])
	return problems

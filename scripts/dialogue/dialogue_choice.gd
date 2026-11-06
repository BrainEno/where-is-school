extends RefCounted
class_name DialogueChoice
## A player-selectable reply.
##
## A choice owns its own consequences so that authored content — not the UI and
## not the scene — decides what a reply does. [DialogueSession] collects the
## effects and emits them; [PrologueFlow] is the only code that writes them to
## GameState / NarrativeLedger.

var id: StringName = &""
var text: String = ""
## Node id to jump to. Empty means "end the conversation after the reply".
var goto: StringName = &""
## Flags to write when chosen. Values are String, bool, int or float.
var flags: Dictionary = {}
## Ledger record ids (see PrologueRecords) to append when chosen.
var records: Array[StringName] = []
## Lines spoken immediately after picking this option, before the jump. This is
## how non-convergent replies stay honest instead of silently collapsing.
var reply_lines: Array[DialogueLine] = []
## Shown only when GameState flag [member requires_flag] equals [member requires_value].
var requires_flag: StringName = &""
var requires_value: Variant = null
## Optional one-line hint under the option (used for "you don't remember this").
var hint: String = ""


static func make(choice_id: StringName, choice_text: String, target: StringName = &"") -> DialogueChoice:
	var choice := DialogueChoice.new()
	choice.id = choice_id
	choice.text = choice_text
	choice.goto = target
	return choice


func with_flag(flag: StringName, value: Variant) -> DialogueChoice:
	flags[flag] = value
	return self


func with_record(record_id: StringName) -> DialogueChoice:
	if not records.has(record_id):
		records.append(record_id)
	return self


func with_reply(line: DialogueLine) -> DialogueChoice:
	reply_lines.append(line)
	return self


func with_requirement(flag: StringName, value: Variant) -> DialogueChoice:
	requires_flag = flag
	requires_value = value
	return self


func with_hint(text_value: String) -> DialogueChoice:
	hint = text_value
	return self


func is_valid() -> bool:
	return not String(id).is_empty() and not text.strip_edges().is_empty()


func is_available(flag_reader: Callable) -> bool:
	if String(requires_flag).is_empty():
		return true
	return flag_reader.call(requires_flag) == requires_value

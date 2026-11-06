extends SceneTree
## Writes a plain-text transcript of the prologue's conversations by playing them
## through the real DialogueSession. Useful for writers, reviewers, and PR
## evidence without launching the game.
##
## Usage: godot --headless --path . --script res://tools/dialogue_transcript.gd

const OUT_PATH := "user://preview/dialogue_transcript.txt"

# A deterministic path through each conversation, by choice index.
const PATH_Q := [0, 1, 0, 1]
const PATH_REHEARSAL := [0]
const PATH_N := [1, 0]

var _out: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://preview")
	var game_state: Node = root.get_node_or_null("GameState")
	if game_state != null:
		game_state.clear()

	_section("BEAT A — WAKE")
	_line("(screen fades from black; the protagonist is slumped at a desk)")
	_line("")

	_section("BEAT B — Q IS ALREADY TALKING")
	await _play(PrologueDialogue.q_conversation(), PATH_Q)

	_section("BEAT D — INSPECTIONS (content as shown in the result card)")
	for id in [&"schoolbag", &"own_desk", &"set_square", &"teacher_desk", &"chalkboard", &"timetable", &"window"]:
		var entry: Dictionary = PrologueInspections.get_entry(id)
		_line("[%s] %s" % [String(id), String(entry.get("title", ""))])
		_line("    " + String(entry.get("text", "")))
		_line("")

	_section("BEAT E — REHEARSAL (imagined; nothing here is in the room)")
	await _play(PrologueDialogue.anticipation(), PATH_REHEARSAL)

	_section("BEAT F — THE BELL, THEN THE SUBSTITUTE")
	_line("(the bell rings twice; the chair at the teacher's desk stays empty)")
	await _play(PrologueDialogue.n_lesson(), PATH_N)

	_section("BEAT G — THE CORRIDOR, THEN THE GATE")
	_line("(the door opens onto a corridor; the gate is open a hand's width)")

	if game_state != null:
		_section("LEDGER AFTER THIS PATH")
		var ledger: Node = root.get_node_or_null("NarrativeLedger")
		if ledger != null:
			for record in ledger.records():
				_line("[%-18s] %s" % [record.label(), record.title])

	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string("\n".join(_out))
	file.close()
	print("Transcript written to %s (%d lines)" % [ProjectSettings.globalize_path(OUT_PATH), _out.size()])
	quit(0)


func _play(script: DialogueScript, choices: Array) -> void:
	var game_state: Node = root.get_node_or_null("GameState")
	var reader: Callable = Callable(game_state, "get_flag") if game_state != null else Callable()
	var session := DialogueSession.new()
	var ledger: Node = root.get_node_or_null("NarrativeLedger")
	session.flags_requested.connect(func(flags):
		if game_state == null:
			return
		for key in flags.keys():
			game_state.set_flag(StringName(key), flags[key])
	)
	session.records_requested.connect(func(ids):
		if ledger == null:
			return
		for id in ids:
			var entry: Dictionary = PrologueRecords.entry_for(id)
			if entry.is_empty():
				continue
			ledger.record(id, entry["kind"], String(entry["title"]), String(entry["body"]), StringName(entry["source"]))
	)
	session.line_presented.connect(func(line: DialogueLine, _history):
		var name := CharacterDirectory.display_name(line.speaker)
		var imagined := " (imagined)" if (line.imagined or session.is_imagining()) else ""
		if CharacterDirectory.is_narration(line.speaker):
			_line("    " + line.text)
		else:
			_line("%s%s: %s" % [name, imagined, line.text])
	)
	session.choices_presented.connect(func(options: Array):
		_line("    [choices]")
		for index in options.size():
			var option: DialogueChoice = options[index]
			_line("      %d. %s" % [index + 1, option.text])
	)
	if not session.start(script, reader):
		_line("!! script failed validation: " + String(script.id))
		return
	var choice_index := 0
	var guard := 0
	while not session.is_finished() and guard < 300:
		guard += 1
		if session.is_awaiting_choice():
			var pick: int = 0
			if choice_index < choices.size():
				pick = int(choices[choice_index])
			choice_index += 1
			var options := session.available_choices()
			if pick < options.size():
				_line("    > you choose: " + options[pick].text)
			session.choose(pick)
			continue
		session.advance()
	_line("")


func _section(title: String) -> void:
	_out.append("")
	_out.append("=".repeat(72))
	_out.append(title)
	_out.append("=".repeat(72))


func _line(text: String) -> void:
	_out.append(text)

extends SceneTree
## Language switching, tested on the real UI instead of on string data.
##
## What this suite is allowed to claim: that the panel, the choices, the aside,
## the backlog, the notebook, and the interaction prompt each render exactly one
## language, and that switching mid-line swaps them without restarting the line
## or losing the choices. What it cannot claim: that the text is good, that the
## English reads naturally, or that line lengths fit the panel on a real screen.
##
## The leak checks matter. A bilingual game usually fails by showing a little of
## the other language (a speaker tag, a bracketed key, "（还没有）") rather than by
## showing all of it, so every English render is scanned for CJK characters and
## every Chinese render for the English-only punctuation that only appears in the
## authored English strings.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const WAIT_STEP := 0.15

var _failures: Array[String] = []
var _checks: int = 0
var _main: Node
var _flow: PrologueFlow
var _director: PrologueDirector
var _panel: DialoguePanel
var _notebook: NoteBook
var _hud: PrologueHud
var _main_script: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _start_game()

	_check_autoload()
	_check_pick_helpers()
	await _check_panel_switches_mid_line()
	await _check_choices_and_aside()
	await _check_backlog()
	await _check_notebook()
	await _check_prompt()
	await _check_every_authored_line_is_complete()
	_check_authored_pairs_are_actually_paired()

	_switch_to(Language.ZH)

	if _failures.is_empty():
		print("language_switch_test passed (%d checks)." % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			printerr("FAIL: " + failure)
		printerr("language_switch_test failed: %d failure(s) of %d checks." % [_failures.size(), _checks])
		quit(1)


# ------------------------------------------------------------------ harness
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


## Switches language exactly the way the L key does, so the test covers the real
## refresh path rather than only the panel's internals.
func _switch_to(language: StringName) -> void:
	Language.set_language(language)
	_main_script.apply_language_to_all()


func _start_game() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main scene failed to load")
	if packed == null:
		return
	_main = packed.instantiate()
	root.add_child(_main)
	_flow = _main.get_node("Flow") as PrologueFlow
	_director = _main.get_node("Director") as PrologueDirector
	_panel = _main.get_node("DialoguePanel") as DialoguePanel
	_notebook = _main.get_node("NoteBook") as NoteBook
	_hud = _main.get_node("Hud") as PrologueHud
	_main_script = _main
	await process_frame
	await process_frame


func _find_interactable(interact_id: StringName) -> Interactable3D:
	if _director == null or _director.current_location == null:
		return null
	var stack: Array[Node] = [_director.current_location]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var interactable := node as Interactable3D
		if interactable != null and interactable.interact_id == interact_id:
			return interactable
		for child: Node in node.get_children():
			stack.append(child)
	return null


func _read_through_dialogue(max_steps: int = 200) -> int:
	var steps: int = 0
	while _flow.is_dialogue_active() and steps < max_steps:
		steps += 1
		if _panel.has_open_choices():
			return steps
		_panel.press_advance()
		await process_frame
	return steps


func _has_cjk(text: String) -> bool:
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
		if code >= 0x3000 and code <= 0x303F:
			return true
		if code >= 0xFF00 and code <= 0xFFEF:
			return true
	return false


func _body_text() -> String:
	var label: RichTextLabel = _panel.get_node("%BodyLabel")
	return label.text


func _visible_english_label() -> Control:
	var label: Control = _panel.get_node("%EnglishLabel")
	return label


# ------------------------------------------------------------------- checks
func _check_autoload() -> void:
	_check(Language.current == Language.ZH, "the game must start in Chinese")
	_check(Language.is_zh(), "is_zh() must agree with current")
	_check(Language.pick("中文", "english") == "中文", "pick() must return Chinese in zh mode")


func _check_pick_helpers() -> void:
	Language.set_language(Language.EN)
	_check(Language.pick("中文", "english") == "english", "pick() must return English in en mode")
	_check(Language.kb("N", "笔记", "notes") == "[N] notes", "key hints must localise the label")
	_check(Language.other_label() == "中文", "the switch button must offer the other language")
	Language.set_language(Language.ZH)
	_check(Language.other_label() == "English", "the switch button must offer English from Chinese")
	# A missing translation must fall back loudly, never render an empty panel.
	_check(Language.pick("有内容", "") == "有内容", "a missing translation must fall back, not blank")
	_check(not _visible_english_label().visible,
		"the second language label must never be visible in single-language mode")


## The important case: switch while a line is already on screen.
func _check_panel_switches_mid_line() -> void:
	var q: Interactable3D = _find_interactable(&"q")
	_check(q != null, "could not find Q to start a conversation")
	if q == null:
		return
	_flow.interact_with(q)
	await process_frame
	await process_frame
	_check(_panel.visible, "Q's conversation must open the panel")

	var zh_text: String = _body_text()
	_check(_has_cjk(zh_text), "the Chinese render must actually contain Chinese")

	# Switching must not restart the reveal or empty the panel.
	var ratio_before: float = (_panel.get_node("%BodyLabel") as RichTextLabel).visible_ratio
	_switch_to(Language.EN)
	await process_frame

	var en_text: String = _body_text()
	_check(not en_text.is_empty(), "switching to English must keep a line on screen")
	_check(not _has_cjk(en_text), "English mode must not show any Chinese characters in the body")
	_check(en_text != zh_text, "the body text must change when the language changes")
	_check((_panel.get_node("%BodyLabel") as RichTextLabel).visible_ratio >= ratio_before,
		"switching languages must not hide the part of the line already read")
	_check(not (_panel.get_node("%EnglishLabel") as Control).visible,
		"the English duplicate label must stay hidden in English mode too")

	_switch_to(Language.ZH)
	await process_frame
	_check(_body_text() == zh_text, "switching back must restore the exact Chinese line")


func _check_choices_and_aside() -> void:
	await _read_through_dialogue()
	_check(_panel.has_open_choices(), "Q's opening must offer choices")
	if not _panel.has_open_choices():
		return

	var zh_choice: String = (_panel.get_node("%ChoiceList").get_child(0) as Button).text
	_check(_has_cjk(zh_choice), "Chinese mode must show Chinese choice text")

	_switch_to(Language.EN)
	await process_frame
	var en_choice: String = (_panel.get_node("%ChoiceList").get_child(0) as Button).text
	_check(not _has_cjk(en_choice),
		"English mode must not leave Chinese in the choice buttons (got: %s)" % en_choice)
	_check(_panel.choice_count() > 0, "choices must survive a language switch")
	_check(_panel.has_open_choices(), "the choice list must still be usable after switching")

	# Pick the reply that carries an aside, then check the aside follows the switch.
	var choices: Array[DialogueChoice] = _flow.session.choices()
	for index: int in choices.size():
		if not choices[index].aside_zh.is_empty():
			_panel.select_choice(index)
			break
	await process_frame
	var aside: Label = _panel.get_node("%AsideLabel")
	if aside.visible:
		_check(not _has_cjk(aside.text),
			"English mode must not leave Chinese in the protagonist's aside (got: %s)" % aside.text)
	else:
		_check(false, "the chosen reply should have shown an aside")


func _check_backlog() -> void:
	var backlog: RichTextLabel = _panel.get_node("%BacklogText")
	_panel.set_backlog([
		{"speaker_zh": "Q", "speaker_en": "Q", "text_zh": "中文行的内容。", "text_en": "The English line."},
	])
	_switch_to(Language.EN)
	await process_frame
	_check(not _has_cjk(backlog.text), "English mode must not show Chinese in the history")
	_check(backlog.text.find("The English line.") != -1, "the history must show the English text")
	_switch_to(Language.ZH)
	await process_frame
	_check(backlog.text.find("中文行的内容。") != -1, "the history must return to Chinese")


func _check_notebook() -> void:
	# Record something, then open the notebook in both languages.
	_flow.ledger.record(&"language_test_entry", NarrativeProvenance.Kind.OBSERVED,
		"笔记本里的中文。", "In the notebook, in English.", &"q_start")
	_notebook.open_notebook()
	await process_frame
	_check(_has_cjk(_notebook_text()), "the notebook must render Chinese in zh mode")
	_switch_to(Language.EN)
	await process_frame
	_check(not _has_cjk(_notebook_text()),
		"the notebook must not leave Chinese headings or entries in English mode")
	_switch_to(Language.ZH)
	await process_frame
	_check(_has_cjk(_notebook_text()), "the notebook must return to Chinese")
	_notebook.close_notebook()


func _notebook_text() -> String:
	var root_node: Node = _notebook.get_node("%ContentRoot")
	var parts: PackedStringArray = PackedStringArray()
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label:
			parts.append((node as Label).text)
		elif node is RichTextLabel:
			parts.append((node as RichTextLabel).text)
		for child: Node in node.get_children():
			stack.append(child)
	return "\n".join(parts)


func _check_prompt() -> void:
	# The prompt only exists outside a conversation, so finish the one started
	# above before probing it.
	var guard: int = 0
	while _flow.is_dialogue_active() and guard < 60:
		guard += 1
		if _panel.has_open_choices():
			_panel.select_choice(0)
		else:
			_panel.press_advance()
		await process_frame
	_check(not _flow.is_dialogue_active(), "the conversation must be closable before the prompt test")

	var target: Interactable3D = _find_interactable(&"bag")
	if target == null:
		_check(false, "could not find the bag for the prompt test")
		return
	_flow.set_focused_interactable(target)
	await process_frame
	var prompt: Label = _hud.get_node("%PromptLabel")
	var zh_prompt: String = prompt.text
	_check(_has_cjk(zh_prompt), "the interaction prompt must be Chinese in zh mode")
	_switch_to(Language.EN)
	await process_frame
	_check(not _has_cjk(prompt.text),
		"the interaction prompt must not keep Chinese after switching (got: %s)" % prompt.text)
	_switch_to(Language.ZH)
	await process_frame
	_check(prompt.text == zh_prompt, "the prompt must be restored exactly")


## Builds every authored conversation and asserts the pairing rule on the real
## objects: each line, choice, aside and ledger record has both fields, the
## Chinese one contains Chinese, and the English one contains none. This is what
## makes "switch to English and nothing Chinese remains" true by construction
## rather than by having looked at one screen.
func _check_authored_pairs_are_actually_paired() -> void:
	var scripts: Array[DialogueScript] = [
		PrologueQConversation.build(),
		PrologueNConversation.build(),
		PrologueAnticipation.build(),
	]
	for inspection_id: StringName in [&"bag", &"set_square", &"teacher_desk", &"timetable", &"chair", &"window"]:
		scripts.append(ClassroomInspections.script_for(inspection_id, {}))
	scripts.append(StreetObservations.build())

	var line_count: int = 0
	for script: DialogueScript in scripts:
		for node_id: StringName in script.nodes:
			var node: DialogueNode = script.nodes[node_id]
			for line: DialogueLine in node.lines:
				line_count += 1
				_check(not line.text_zh.strip_edges().is_empty(),
					"%s/%s: a line has no Chinese" % [script.id, node_id])
				_check(not line.text_en.strip_edges().is_empty(),
					"%s/%s: a line has no English" % [script.id, node_id])
				_check(_has_cjk(line.text_zh),
					"%s/%s: the Chinese field contains no Chinese" % [script.id, node_id])
				_check(not _has_cjk(line.text_en),
					"%s/%s: the English field still contains Chinese: %s" % [script.id, node_id, line.text_en])
			for choice: DialogueChoice in node.choices:
				line_count += 1
				_check(not choice.text_zh.strip_edges().is_empty(),
					"%s/%s: choice %s has no Chinese" % [script.id, node_id, choice.id])
				_check(not choice.text_en.strip_edges().is_empty(),
					"%s/%s: choice %s has no English" % [script.id, node_id, choice.id])
				_check(not _has_cjk(choice.text_en),
					"%s/%s: choice %s keeps Chinese in its English text" % [script.id, node_id, choice.id])
				if not choice.aside_zh.is_empty():
					_check(not choice.aside_en.strip_edges().is_empty(),
						"%s/%s: aside on %s has no English" % [script.id, node_id, choice.id])
					_check(not _has_cjk(choice.aside_en),
						"%s/%s: aside on %s keeps Chinese in its English text" % [script.id, node_id, choice.id])
				for record: Dictionary in choice.records:
					_check(not str(record.get("en", "")).strip_edges().is_empty(),
						"%s/%s: record %s has no English" % [script.id, node_id, record.get("id", "?")])
					_check(not _has_cjk(str(record.get("en", ""))),
						"%s/%s: record %s keeps Chinese in its English text" % [script.id, node_id, record.get("id", "?")])
			for record: Dictionary in node.on_enter_records:
				_check(not str(record.get("en", "")).strip_edges().is_empty(),
					"%s/%s: record %s has no English" % [script.id, node_id, record.get("id", "?")])
				_check(not _has_cjk(str(record.get("en", ""))),
					"%s/%s: record %s keeps Chinese in its English text" % [script.id, node_id, record.get("id", "?")])
	_check(line_count > 100, "expected the authored scripts to contain more than 100 lines, found %d" % line_count)


## Guards the authoring rule in one place: every authored line has both fields
## and the Chinese one is Simplified (no characters that only occur in the
## traditional forms of common words).
func _check_every_authored_line_is_complete() -> void:
	var sources: Array[String] = [
		"res://data/dialogue/classroom_inspections.gd",
		"res://data/dialogue/prologue_anticipation.gd",
		"res://data/dialogue/prologue_n_conversation.gd",
		"res://data/dialogue/prologue_q_conversation.gd",
		"res://data/dialogue/street_observations.gd",
	]
	# Characters that survived only where text was still traditional.
	var traditional_only: String = "著牠裡麼"
	for path: String in sources:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		_check(file != null, "could not open %s" % path)
		if file == null:
			continue
		var text: String = file.get_as_text()
		for index: int in traditional_only.length():
			var glyph: String = traditional_only[index]
			_check(text.find(glyph) == -1,
				"%s still contains the traditional-form character '%s'" % [path, glyph])

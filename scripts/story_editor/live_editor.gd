extends CanvasLayer
## Paused editing of the actual presented line, not a second panel or a trial runner.
## Staged author apps only: the entire run started in a different user data directory.

const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const Store := preload("res://scripts/story_editor/draft_store.gd")
const Exchange := preload("res://scripts/story_editor/author_exchange.gd")
const RoundForm := preload("res://scripts/story_editor/live_round_form.gd")
const Form := preload("res://scripts/story_editor/author_form.gd")
const KeyboardArea := preload("res://scripts/story_editor/keyboard_area.gd")
const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

var store: Store
var controller: DialogueController
var ui: GameUI
var _panel: DialoguePanel
var _root: Control
var _toolbar: PanelContainer
var _status: Label
var _body: TextEdit
var _round: RoundForm
var _exchange: Exchange
var _timer: Timer
var _buttons: Dictionary[String, Button] = {}
var _form := {}
var _open := false
var _native_target: TextEdit
var _export_warning := ""


func _ready() -> void:
	name = "LiveStoryEditor"
	layer = 41
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = ui.dialogue_panel
	_root = Control.new()
	_root.name = "Controls"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var theme := Theme.new()
	theme.default_font = Form.make_font(_root.get_theme_default_font())
	theme.default_font_size = 18
	_root.theme = theme
	_build_toolbar()
	_build_body()
	_round = RoundForm.new()
	_root.add_child(_round)
	_round.apply_requested.connect(_apply)
	_round.keep_requested.connect(_keep)
	_round.discard_requested.connect(_discard)
	_round.native_requested.connect(_native_edit)
	_round.changed.connect(_changed)
	_round.hide()
	_exchange = Exchange.new()
	_exchange.name = "Exchange"
	_root.add_child(_exchange)
	_exchange.edited.connect(_native_result)
	_exchange.notice.connect(_notice)
	_exchange.exported.connect(_exported)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.32
	add_child(_timer)
	_timer.timeout.connect(_save_input)
	_root.hide()
	set_process(false)


func can_open() -> bool:
	return not _open and _panel.is_visible_in_tree() and not ui.fade.visible \
		and not ui.backlog.is_open() and not ui.end_card.visible and not ui.check_overlay.visible \
		and not _address().is_empty()


func is_editing() -> bool:
	return _open


func open_editor() -> bool:
	if not can_open() or get_tree().paused:
		return false
	_open = true
	get_tree().paused = true
	controller.set_author_editing(true)
	_panel.set_author_controls(_begin, _begin, "编辑")
	controller.refresh_author_dialogue()
	_root.show()
	_notice(store.blocked)
	set_process(true)
	_fit()
	return true


func close_editor() -> bool:
	if not _open:
		return true
	if _exchange.is_busy() or not _save_input():
		return false
	_finish_form()
	_open = false
	_root.hide()
	set_process(false)
	if is_instance_valid(_panel):
		_panel.set_author_controls()
	if is_instance_valid(controller):
		controller.set_author_editing(false)
	get_tree().paused = false
	return true


func _address(choice: String = "") -> Dictionary:
	var runtime := controller.get_runtime()
	var displayed := controller.get_current_line()
	if runtime == null or not runtime.is_active() or runtime.get_current_node_id() == &"" \
			or displayed.get("node_id") != runtime.get_current_node_id() \
			or displayed.get("conversation_id") != runtime.get_active_conversation_id():
		return {}
	var conversation := String(runtime.get_active_conversation_id())
	var chapter := store.chapter_for(conversation)
	if chapter.is_empty() or (not choice.is_empty() and StringName(choice) not in runtime.get_available_choice_ids()):
		return {}
	return {"chapter": chapter, "conversation": conversation, "node": String(runtime.get_current_node_id()), "choice": choice}


func _begin(choice: String = "") -> void:
	if not _open or not get_tree().paused or _exchange.is_busy():
		return
	if not store.blocked.is_empty() or L10n.current != Patch.LOCALE:
		_notice(store.blocked)
		return
	var address := _address(choice)
	if address.is_empty():
		_notice("现在没有这个可编辑的对白或选项。")
		return
	if not _form.is_empty():
		_notice("请先应用、保留或放弃当前输入。")
		return
	var saved := store.live_buffer
	if not saved.is_empty() and saved.get("address") != address:
		_notice("另一个位置有未应用输入。可回到该句继续，或先放弃那份输入。")
		return
	if choice.is_empty():
		_begin_body(address, saved)
	else:
		_begin_round(address, saved)
	_fit()


func _begin_body(address: Dictionary, saved: Dictionary) -> void:
	var before := store.live_body_anchor(address)
	var initial := store.editable_text(address["chapter"], address["conversation"], address["node"], "")
	_form = {"address": address, "kind": "body", "before": saved.get("before", before), "initial": initial}
	_body.text = String(saved.get("text", initial))
	_body.clear_undo_history()
	_body.show()
	_notice("原位改字 · 应用后只刷新这一句。")
	if OS.has_feature("ios"):
		_native_edit(_body, "修改当前对白")
	else:
		_body.grab_focus()


func _begin_round(address: Dictionary, saved: Dictionary) -> void:
	var anchor: Dictionary = saved.get("anchor", store.round_anchor(address))
	if anchor.is_empty():
		_notice("此选项已接入下一轮或没有可用去向。继续到新选项旁，可再接一轮。")
		return
	var chapter: String = address["chapter"]
	var conversation: String = address["conversation"]
	var speakers := PackedStringArray()
	for row: Dictionary in store.nodes_for(chapter, conversation):
		var id: String = row["speaker"]
		if id not in speakers:
			speakers.append(id)
	var targets := {}
	for row: Dictionary in store.choice_targets(chapter, conversation, address["node"]):
		targets[row["id"]] = "%s · %s" % [row["id"], _snippet(row["text"])]
	var option := store.editable_text(chapter, conversation, address["node"], address["choice"])
	_form = {"address": address, "kind": "round", "anchor": anchor}
	var speaker := String(controller.get_current_line().get("speaker_id", ""))
	_round.prepare(_snippet(option), speakers, speaker, targets, anchor["before"], saved.get("values", {}))
	_round.show()
	_notice("先填对白和选项，再一次接入；未应用的输入不影响游戏。")


func _apply() -> void:
	if not _open or not get_tree().paused or _form.is_empty() or _exchange.is_busy():
		return
	var address: Dictionary = _form["address"]
	if _address(address["choice"]) != address or L10n.current != Patch.LOCALE:
		_save_input()
		_notice("当前对白已改变，输入未应用。")
		return
	var ok: bool
	if _form["kind"] == "body":
		ok = store.apply_live_text(address, _form["before"], _body.text)
	else:
		ok = store.apply_live_round(address, _form["anchor"], _round.capture())
	if not ok:
		var problem := store.error
		if _save_input():
			_notice("未应用：" + problem)
		return
	var refreshed := controller.refresh_author_dialogue()
	_finish_form()
	_notice("已保存并应用。点「继续游戏」后沿现场对白走。" if refreshed
		else "已保存草稿，但无法刷新当前对白。请重新进入会话后再试。")


func _restore_input() -> void:
	var address: Variant = store.live_buffer.get("address")
	if not address is Dictionary or _address(String(address.get("choice", ""))) != address:
		_notice("未应用输入属于另一句。走到原位置再继续，或放弃这份输入。")
		return
	_begin(String(address.get("choice", "")))


func _capture() -> Dictionary:
	if _form.is_empty():
		return store.live_buffer
	var saved := _form.duplicate(true)
	if _form["kind"] == "body":
		if _body.text == _form["initial"] and store.live_buffer.is_empty():
			return {}
		saved["text"] = _body.text
	else:
		saved["values"] = _round.capture()
	return saved


func _save_input() -> bool:
	_timer.stop()
	var pending := _capture()
	if pending == store.live_buffer:
		return true
	if store.save_live_buffer(pending):
		return true
	_notice(store.save_problem() + " 输入仍在画面中；可重试或放弃。")
	return false


func _changed() -> void:
	if _open and not _form.is_empty():
		_timer.start()


func _keep() -> void:
	if not _exchange.is_busy() and _save_input():
		_finish_form()
		_notice("输入已保留，尚未接入游戏。")


func _discard() -> void:
	if _exchange.is_busy():
		return
	if not store.live_buffer.is_empty() and not store.save_live_buffer({}):
		_notice(store.save_problem())
		return
	_finish_form()
	_notice("已放弃未应用输入；已应用对白不变。")


func _finish_form() -> void:
	_timer.stop()
	_form = {}
	_body.release_focus()
	_body.hide()
	_round.hide()


func _native_edit(input: TextEdit, caption: String) -> void:
	if OS.has_feature("ios") and not _exchange.is_busy():
		_native_target = input
		_exchange.edit_field("live", input.text, caption)


func _native_result(field: String, text: String) -> void:
	if field == "live" and _open and not _form.is_empty() and is_instance_valid(_native_target):
		_native_target.text = text
		_changed()
	_native_target = null


func _export() -> void:
	if _exchange.is_busy() or not _save_input():
		return
	var chapter := String(_address().get("chapter", ""))
	var result := store.export_chapter(chapter)
	if result.has("error"):
		_notice(result["error"])
		return
	_export_warning = "英文 %d 项待译，候选可试玩，不是正式译文。" % result["pending"]
	if not store.live_buffer.is_empty():
		_export_warning += " 未应用输入不在包内。"
	_notice(_export_warning)
	_exchange.export_chapter(chapter, result["files"])


func _exported(digest: String, note: String) -> void:
	_notice(note + (" " + _export_warning if not digest.is_empty() else ""))


func _chinese() -> void:
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null and _form.is_empty() and not _exchange.is_busy():
		loc.call("set_locale", Patch.LOCALE)
		_notice("")


func _notice(note: String) -> void:
	var chinese := L10n.current == Patch.LOCALE
	var writing := not _form.is_empty()
	var body: bool = _form.get("kind") == "body"
	var buffered := not store.live_buffer.is_empty()
	_buttons["SimplifiedChinese"].visible = not chinese and not writing
	_buttons["EditLine"].visible = chinese and not writing and store.blocked.is_empty()
	_buttons["ApplyLine"].visible = body
	_buttons["KeepLine"].visible = body
	_buttons["NativeInput"].visible = body and OS.has_feature("ios")
	_buttons["ResumeInput"].visible = buffered and not writing
	_buttons["DiscardInput"].visible = body or (buffered and not writing)
	_buttons["ExportChapter"].disabled = not store.blocked.is_empty()
	if note.is_empty():
		note = "双击原对白框改字，或点原选项旁「编辑」接下一轮。" if chinese \
			else "现场只编辑简中主稿。英文保留现有译文，先切到简中再改。"
	_status.text = note
	_status.tooltip_text = note


func _build_toolbar() -> void:
	_toolbar = PanelContainer.new()
	_toolbar.name = "AuthorBar"
	var style := MenuStyle.panel_style()
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 8.0)
	_toolbar.add_theme_stylebox_override(&"panel", style)
	_root.add_child(_toolbar)
	var column := VBoxContainer.new()
	_toolbar.add_child(column)
	var row := HFlowContainer.new()
	column.add_child(row)
	var mark := Label.new()
	mark.text = "现场编辑 · 作者进度"
	mark.add_theme_color_override(&"font_color", MenuStyle.ACCENT)
	row.add_child(mark)
	_button(row, "EditLine", "改当前句", _begin)
	_button(row, "SimplifiedChinese", "切到简中", _chinese)
	_button(row, "NativeInput", "系统输入法", func() -> void: _native_edit(_body, "修改当前对白"))
	_button(row, "ApplyLine", "应用改字", _apply)
	_button(row, "KeepLine", "保留输入", _keep)
	_button(row, "ResumeInput", "继续未应用输入", _restore_input)
	_button(row, "DiscardInput", "放弃输入", _discard)
	_button(row, "ExportChapter", "导出整章", _export)
	_button(row, "ContinueGame", "继续游戏", func() -> void: close_editor())
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.max_lines_visible = 3
	_status.add_theme_color_override(&"font_color", MenuStyle.PAGE_TEXT)
	column.add_child(_status)


func _build_body() -> void:
	_body = TextEdit.new()
	_body.name = "InlineBody"
	_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_body.editable = not OS.has_feature("ios")
	_body.placeholder_text = "在原对白框内输入正文"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff8e8")
	style.border_color = MenuStyle.EMBER
	style.set_border_width_all(1)
	style.set_content_margin_all(5.0)
	for state in [&"normal", &"focus", &"read_only"]:
		_body.add_theme_stylebox_override(state, style)
	for state in [&"font_color", &"font_readonly_color", &"caret_color"]:
		_body.add_theme_color_override(state, Color("211c2c"))
	_body.text_changed.connect(_changed)
	_root.add_child(_body)
	_body.hide()


func _button(row: Container, id: String, text: String, action: Callable) -> void:
	var button := Button.new()
	button.name = id
	button.text = text
	button.custom_minimum_size.y = 34.0
	button.pressed.connect(action)
	row.add_child(button)
	_buttons[id] = button
	if MobileLayout.enabled:
		MobileLayout.enlarge(button)


func _fit() -> void:
	var area := KeyboardArea.usable_rect(_root, true)
	_toolbar.position = area.position
	_toolbar.size = Vector2(area.size.x, 0.0)
	if _body.visible:
		var body := _panel.get_body_label()
		var bounds := body.get_global_rect().intersection(area)
		_body.position = bounds.position
		_body.size = bounds.size
		_body.add_theme_font_size_override(&"font_size", body.get_theme_font_size(&"normal_font_size"))
	if _round.visible:
		var top := _toolbar.position.y + _toolbar.size.y + 8.0
		var width := minf(area.size.x, maxf(400.0, area.size.x * (0.61 if MobileLayout.enabled else 0.39)))
		_round.position = Vector2(area.end.x - width, top)
		_round.size = Vector2(width, maxf(0.0, area.end.y - top))


func _process(_delta: float) -> void:
	if _open:
		_fit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		if _form.is_empty():
			close_editor()
		else:
			_keep()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST] and _open:
		_save_input()


func _exit_tree() -> void:
	if not _open:
		return
	_save_input()
	if is_instance_valid(_panel) and _panel.is_inside_tree():
		_panel.set_author_controls()
	if is_instance_valid(controller):
		controller.set_author_editing(false)
	get_tree().paused = false


func _snippet(text: String) -> String:
	var plain := text.replace("\n", " ")
	return plain.left(28) + ("…" if plain.length() > 28 else "")

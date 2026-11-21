extends OpeningSequence
## Preview-only interaction extension. The shipped director never loads this script.
## Everything committed to the slot is a completed response or piece of evidence.

const HOTSPOT := preload("res://scenes/interaction/interactable.tscn")
const RESPONSE := &"preview.name_quest.response"
const CLASS_INDEXED := &"preview.name_quest.class_indexed"
const REFERENCE := &"preview.name_quest.reference"
const Q_CLUE := &"preview_name_quest_q_clue"
const BOARD_CLUE := &"preview_name_quest_board_clue"
const VERIFIED := &"preview_name_quest_verified"
const Q_FOLLOWUP := &"preview_name_quest_q"
const ORIGINALS := &"preview_name_quest_originals"
const RESPONSES: Array[String] = ["a", "b", "c"]
const CLASS_TABS: Array[String] = ["J", "K", "M"]
const CLASS_MARK := "K"
const SEAT_MARK := "R"
# Non-canonical sample records, not class numbers. Pin offsets, column positions
# and the original's keys must agree; none of the index tabs contains a name.
const COLUMNS: Array[String] = ["A", "B", "C", "D", "E"]
const SEATS: Array[String] = ["P", "R", "S"]
const SEAT_COLUMNS: Array[int] = [1, 2, 3]
const ORIGINAL_PINS: Array[int] = [1, 3]
const COPY_PINS: Array[int] = [0, 2]
const COPY_REFERENCES: Array[String] = ["L2", "G4", "C7", "E3"]
const FILES: Array[Dictionary] = [
	{"reference": "G4", "class": "K", "seat": "R", "original": false},
	{"reference": "G4", "class": "M", "seat": "R", "original": true},
	{"reference": "L2", "class": "K", "seat": "P", "original": true},
	{"reference": "G4", "class": "K", "seat": "R", "original": true},
]

var cards: Dictionary
var progress: Label
var preview_font: Font
var _q_target: Interactable
var _save_problem := false


func _ready() -> void:
	# The base director also emits this on load/Continue; decorate only those
	# instances, including return visits, without touching a room resource.
	var host := get_node(location_host_path) as LocationHost
	host.location_entered.connect(_prepare_location)
	super()
	if host.get_current() == null:
		return
	var panel_font := _ui.dialogue_panel._dialogue_font() as FontVariation
	var fallbacks := panel_font.fallbacks
	fallbacks.append(preview_font)
	panel_font.fallbacks = fallbacks
	progress.add_theme_font_override("font", preview_font)
	_game_state().story_flag_changed.connect(_refresh_from_flag)
	_refresh_progress()
	_ui.fade.set_clear()
	allow_player_control()
	_finish_boot.call_deferred()


func _finish_boot() -> void:
	_add_q_target()
	if _room() != &"classroom" or _has_flag(StoryFlags.SKIPPED_CLASS):
		return
	if not _has_flag(StoryFlags.CLASS_DISMISSED):
		await _beat_substitute()
		autosave("preview:dismissal")


func _prepare_location(location: LocationRoot, _spawn: StringName) -> void:
	for item: Interactable in location.get_interactables():
		var exit := item as LocationExit
		if exit != null and (exit.is_milestone_end or exit.destination_id not in [
			&"classroom", &"corridor", &"archive",
		]):
			item.interaction_enabled = false
	match location.location_id:
		&"classroom":
			# The curtain fall goes outside the preview map. The rear door keeps
			# its own handler and timing; it is never routed to the name question.
			location.find_interactable(&"curtain").interaction_enabled = false
		&"corridor":
			# As in school_room_tour, leave the real doorway in place but don't
			# make this preview solve an unrelated threshold check first.
			var door := location.find_interactable(&"to_archive") as LocationExit
			door.required_flag = &""
			for item: Interactable in location.get_interactables():
				if String(item.interact_id).begins_with("align_"):
					item.interaction_enabled = false
		&"archive":
			var target := HOTSPOT.instantiate() as Interactable
			target.name = "VerifyOriginal"
			target.interact_id = ORIGINALS
			target.prompt_text = _text("original_prompt")
			target.radius = 1.3
			target.position = Vector3(0.0, 1.45, 0.94)
			target.support_paths = PackedStringArray([".."])
			target.outline_paths = PackedStringArray(["../Register"])
			target.interaction_enabled = _started()
			location.get_node(^"Registry/InspectionDesk").add_child(target)


func _add_q_target() -> void:
	# This hotspot is separate from q_ask_along, which still means resume following.
	var ask_along := _companion.get_node(^"AskAlong") as Interactable
	_q_target = HOTSPOT.instantiate() as Interactable
	_q_target.name = "AskAboutTheRegister"
	_q_target.interact_id = Q_FOLLOWUP
	_q_target.prompt_text = _text("q_followup")
	_q_target.position = ask_along.position
	_q_target.radius = ask_along.radius
	_q_target.outline_paths = ask_along.outline_paths
	_q_target.support_paths = ask_along.support_paths
	_q_target.interaction_enabled = false
	_companion.add_child(_q_target)
	_companion.visibility_changed.connect(_refresh_q_target)
	_companion.joined.connect(_refresh_q_target)
	_companion.waiting_changed.connect(func(_waiting: bool) -> void: _refresh_q_target())
	_refresh_q_target()


func _on_activation_requested(item: Interactable) -> void:
	if is_beat_active() or _dialogue.is_busy() or not item.can_interact():
		return
	var exit := item as LocationExit
	if exit != null and _can_ask_name(exit):
		await begin_beat()
		var n := _locations.get_current().find_actor(NPresence.ACTOR_ID)
		n.watch(_player)
		var pick := await _card("ask_title", "", cards["ask_choices"], "n")
		n.stop_watching()
		_game_state().set_flag(RESPONSE, RESPONSES[pick])
		end_beat()
		# Commit the answer while still inside. A refused or interrupted door
		# transition cannot make N ask again after the answer was chosen.
		autosave("preview:answer")
		await _handle_exit(exit)
		return
	if item == _q_target:
		if _q_available():
			await _ask_q()
		return
	if _started():
		if _room() == &"corridor" and item.interact_id == &"noticeboard":
			await _read_board(item)
			return
		if _room() == &"archive":
			if item.interact_id == &"archive_detail":
				await _read_index(item)
				return
			if item.interact_id == ORIGINALS:
				await _verify_original()
				return
	super(item)


func _can_ask_name(exit: LocationExit) -> bool:
	if _room() != &"classroom" or exit.interact_id != LocationFlow.COMPLETION_DOOR_ID \
			or not exit.is_open() or _started() or _has_flag(StoryFlags.SKIPPED_CLASS) \
			or not _has_flag(StoryFlags.CLASS_DISMISSED) or not _has_flag(StoryFlags.N_ARRIVED):
		return false
	var n := _locations.get_current().find_actor(NPresence.ACTOR_ID)
	return n != null and n.is_visible_in_tree()


func _ask_q() -> void:
	await begin_beat()
	var reply := await _card("q_title", "", [_text("q_followup"), _text("back")], "q")
	if reply == 0:
		var clue := _clue()
		_knowledge().record(Q_CLUE, NarrativeEntry.Source.REPORTED, &"q", clue)
		await _card("q_report", clue, [_text("back")])
	end_beat()
	if reply == 0:
		autosave("preview:q_clue")


func _read_board(item: Interactable) -> void:
	await begin_beat()
	await _inspect(item)
	var clue := _clue()
	_knowledge().record(BOARD_CLUE, NarrativeEntry.Source.OBSERVED, &"protagonist", clue)
	await _card("board_title", clue, [_text("back")])
	end_beat()
	autosave("preview:board_clue")


func _read_index(item: Interactable) -> void:
	_focus.engage(item)
	await begin_beat()
	if not _has_flag(StoryFlags.inspection_seen_flag(item.inspection_id)):
		await _inspect(item)
	if not _has_clue():
		await _card("class_title", _step("clue"), [_text("back")])
	elif _reference().is_empty():
		if _has_flag(CLASS_INDEXED) or await _choose_class():
			await _align_copy()
	else:
		await _card("class_title", _index_clue(), [_text("back")])
	end_beat()
	autosave("preview:index")


func _choose_class() -> bool:
	var options := CLASS_TABS.duplicate()
	options.append(_text("back"))
	var hint := _clue()
	while true:
		var pick := await _card("class_title", hint, options)
		if pick == CLASS_TABS.size():
			return false
		if CLASS_TABS[pick] == CLASS_MARK:
			_game_state().set_flag(CLASS_INDEXED, true)
			return true
		hint = _clue() + "\n" + _text("wrong_class")
	return false


func _align_copy() -> void:
	var offset := 0
	var hint := ""
	var options := [_text("shift_left"), _text("shift_right"), _text("align_confirm"), _text("back")]
	while true:
		var shifted_pins: Array[int] = [COPY_PINS[0] + offset, COPY_PINS[1] + offset]
		var seat_keys := PackedStringArray()
		var copy_keys := PackedStringArray()
		for i in SEATS.size():
			seat_keys.append("%s:%s" % [_column(SEAT_COLUMNS[i]), SEATS[i]])
		for i in COPY_REFERENCES.size():
			copy_keys.append("%s:%s" % [_column(i + offset), COPY_REFERENCES[i]])
		var rows := _text("align_rows") % [
			_pins(ORIGINAL_PINS), "    ".join(seat_keys),
			_pins(shifted_pins), "    ".join(copy_keys),
		]
		var pick := await _card("align_title", _clue() + "\n" + rows + hint, options)
		match pick:
			0, 1:
				offset = clampi(offset + (-1 if pick == 0 else 1), -1, 1)
				hint = ""
			2:
				if shifted_pins == ORIGINAL_PINS:
					var col := SEAT_COLUMNS[SEATS.find(SEAT_MARK)] - offset
					_game_state().set_flag(REFERENCE, COPY_REFERENCES[col])
					await _card("align_title", _index_clue(), [_text("back")])
					return
				hint = "\n" + _text("wrong_alignment")
			_:
				return


func _verify_original() -> void:
	await begin_beat()
	if _reference().is_empty():
		await _card("original_title", _text("missing_reference"), [_text("back")])
	elif _knowledge().has_entry(VERIFIED) or await _choose_original():
		await _card("reveal_title", _text("reveal_name"), [_text("back")])
	end_beat()
	autosave("preview:original")


func _choose_original() -> bool:
	var options: Array[String] = []
	for file: Dictionary in FILES:
		options.append("%s / %s / %s　·　%s" % [
			file["reference"], file["class"], file["seat"],
			_text("original" if file["original"] else "copy"),
		])
	options.append(_text("back"))
	var hint := _index_clue()
	while true:
		var pick := await _card("original_title", hint, options)
		if pick == FILES.size():
			return false
		var file := FILES[pick]
		if file["original"] and file["reference"] == _reference() \
				and file["class"] == CLASS_MARK and file["seat"] == SEAT_MARK:
			_knowledge().record(VERIFIED, NarrativeEntry.Source.OBSERVED, &"protagonist", _text("reveal_name"))
			return true
		hint = _index_clue() + "\n" + _text("wrong_original")
	return false


func _inspect(item: Interactable) -> void:
	if _dialogue.present_inspection(item.inspection_id):
		while _dialogue.is_busy():
			await _dialogue.presentation_active_changed


## Mechanical cards reuse the same paper surface and input as dialogue but never
## start a dialogue node, change the real speaker's name, or add a line to backlog.
## The caller holds the existing beat lock for the entire stack of cards.
func _card(title_key: String, body: String, options: Array, speaker: String = "") -> int:
	var panel := _ui.dialogue_panel
	panel.show_line({"title": _text(title_key), "text": body, "speaker_id": speaker})
	var choices: Array[Dictionary] = []
	for label: String in options:
		choices.append({"text": label})
	panel.set_choices(choices)
	var pick: int = await panel.choice_selected
	panel.close()
	return pick


func autosave(why: String = "") -> Dictionary:
	var result := super(why)
	_save_problem = not result.get("ok", false)
	_refresh_progress()
	return result


func _refresh_from_flag(flag: StringName, _previous: Variant, _value: Variant) -> void:
	if flag in [StoryFlags.CURRENT_LOCATION, StoryFlags.CLASS_DISMISSED, StoryFlags.SKIPPED_CLASS]:
		# A room can set its own objective later in this same arrival callback.
		_refresh_progress.call_deferred()
	elif flag == StoryFlags.Q_COMPANION:
		_refresh_q_target()


func _refresh_progress() -> void:
	_refresh_q_target()
	_hud.set_objective("")
	var step := "dismissal"
	if _has_flag(StoryFlags.SKIPPED_CLASS):
		step = "skipped"
	elif not _started():
		if _has_flag(StoryFlags.CLASS_DISMISSED):
			step = "door"
	elif _knowledge().has_entry(VERIFIED):
		step = "complete"
	elif not _reference().is_empty():
		step = "original"
	elif _has_flag(CLASS_INDEXED):
		step = "align"
	elif _has_clue():
		step = "ledger"
	else:
		step = "clue"
	var title := _text("banner")
	if _started():
		title += "  /  " + _text("title")
	progress.text = title + "\n" + _step(step)
	if _save_problem:
		progress.text += "\n" + _step("save_error")


func _refresh_q_target() -> void:
	if is_instance_valid(_q_target):
		_q_target.interaction_enabled = _q_available()


func _q_available() -> bool:
	return _started() and _room() == &"corridor" and _companion.is_joined() \
		and _companion.is_visible_in_tree() and not _companion.is_waiting() \
		and not _knowledge().has_entry(Q_CLUE)


func _room() -> StringName:
	var location := _locations.get_current()
	return location.location_id if location != null else &""


func _started() -> bool:
	return String(_game_state().get_flag(RESPONSE, "")) in RESPONSES


func _reference() -> String:
	return String(_game_state().get_flag(REFERENCE, ""))


func _knowledge() -> Node:
	return get_node(^"/root/NarrativeState")


func _has_clue() -> bool:
	return _knowledge().has_entry(Q_CLUE) or _knowledge().has_entry(BOARD_CLUE)


func _clue() -> String:
	return _text("clue_format") % [CLASS_MARK, SEAT_MARK]


func _index_clue() -> String:
	return _clue() + "\n" + _text("reference_format") % _reference()


func _text(key: String) -> String:
	return String(cards[key])


func _step(key: String) -> String:
	return String(cards["steps"][key])


static func _column(index: int) -> String:
	# A single column may hang over the left edge during a bad trial.
	return COLUMNS[index] if index >= 0 else "-A"


static func _pins(columns: Array[int]) -> String:
	return "%s / %s" % [_column(columns[0]), _column(columns[1])]

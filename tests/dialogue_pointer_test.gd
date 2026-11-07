extends SceneTree
## The conversation panel under the mouse.
##
## Click-to-move added a second consumer of the left button, so the rules that keep the
## two apart have to be visible in a test:
##
## 1. the options are ordinary `Button`s, so a left click selects exactly one of them,
##    once — never two, never none;
## 2. a click that a `Control` consumed must not reach the world. The world counts the
##    mouse presses that arrive as unhandled input, and that counter is checked against
##    a control case (a click on nothing but the world) so a zero means something;
## 3. the digit keys still pick an option by number;
## 4. the panel stays above the HUD, and the option buttons carry hover styling, so
##    pointing at an option is visible feedback and not just a click target;
## 5. switching language re-renders the options in the new language without losing
##    them: the same number of options, different text.
##
## The real conversation used here is the classroom's `n_class`, the same one the
## free-period test drives, because its stay/leave node is the one real choice in the
## slice.

const Harness = preload("res://tests/test_harness.gd")

const MAX_ADVANCE_STEPS := 80

var _failures: Array[String] = []
var _main: Node = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _panel: DialoguePanel = null
var _sequence: OpeningSequence = null
var _navigator: PointerNavigator = null
var _selected: Array[int] = []
var _last_click_note: String = ""


func _initialize() -> void:
	Harness.arm_watchdog(self, 200.0, "dialogue_pointer_test.gd")
	call_deferred("_run")


func _run() -> void:
	# A headless run opens a 64x64 window, so the bottom-anchored dialogue panel is laid
	# out mostly above the top edge and a click on one of its buttons lands outside the
	# viewport. The game is authored for 1600x900; give the run that surface first.
	root.size = Vector2i(1600, 900)
	await _frames(3)
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await _frames(3)

	_player = _main.get_node_or_null("Player") as PlayerController
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	var game_ui := _main.get_node_or_null("GameUI")
	if game_ui != null:
		_panel = game_ui.get_node_or_null("DialoguePanel") as DialoguePanel
	if _player != null:
		_navigator = _player.get_node_or_null("PointerNavigator") as PointerNavigator
	if _player == null or _dialogue == null or _panel == null or _navigator == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	if _sequence != null:
		_sequence.allow_player_control()

	# The passive inner voice can open its own conversation at any time, which would
	# lock the player mid-walk and make these timings a race. It is switched off here;
	# it has its own test.
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	_panel.choice_selected.connect(_on_choice_selected)
	Engine.time_scale = 4.0
	await _frames(3)

	await _check_world_clicks_are_counted()
	await _check_real_conversation_click()
	await _check_digit_keys()

	Harness.finish(
		self, _failures,
		"a left click chooses exactly one option, never reaches the world, and the digits and the language switch still work."
	)


# --- cases ------------------------------------------------------------------


## The control case. Without this, "no world click happened" could be true because the
## counter never moves at all.
func _check_world_clicks_are_counted() -> void:
	_panel.close()
	await _frames(2)
	var before := _navigator.get_world_click_event_count()
	await _click_at(_world_screen_position())
	if _navigator.get_world_click_event_count() != before + 1:
		_failures.append(
			"A left click on the empty world did not reach the world input path at all."
		)
	if _player.is_path_active():
		_player.cancel_path()
	await _frames(2)


## Real conversation, real buttons, real mouse events — including the language switch,
## which is done on the same choice screen so the run does not depend on the room
## offering its stay/leave node twice.
func _check_real_conversation_click() -> void:
	if not await _open_a_choice():
		return
	var buttons := _buttons()
	if buttons.size() < 2:
		_failures.append("The stay/leave node offered %d option(s)." % buttons.size())
		await _close_conversation()
		return
	for button in buttons:
		if button.mouse_filter != Control.MOUSE_FILTER_STOP:
			_failures.append("An option button does not stop the mouse: a click could fall through.")
		if button.focus_mode != Control.FOCUS_NONE:
			_failures.append("An option button takes keyboard focus, which the digits do not need.")
		if not button.has_theme_stylebox("hover"):
			_failures.append("An option button has no hover style, so pointing at it shows nothing.")
	# The panel sits in a CanvasLayer, so it cannot be re-ordered by moving the node;
	# what matters is that it is drawn above the HUD and that it is the layer that
	# receives the click.
	var parent := _panel.get_parent()
	if parent == null:
		_failures.append("The dialogue panel has no parent layer.")
	else:
		var hud := parent.get_node_or_null("HUD")
		if hud != null and _panel.get_index() < hud.get_index():
			_failures.append("The dialogue panel is drawn below the HUD.")
	if not _panel.is_visible_in_tree():
		_failures.append("The dialogue panel is not visible while a choice is open.")

	# --- same choice, in the other language -------------------------------
	var english: Array[String] = []
	for button in buttons:
		english.append(button.text)
	L10n.set_locale("zh-CN")
	var switched := _dialogue.apply_locale("zh-CN")
	await _frames(5)
	var translated := _buttons()
	if not switched:
		_failures.append("The language switch was refused while a choice was open.")
	elif translated.size() != buttons.size():
		_failures.append(
			"The option count changed from %d to %d on a language switch."
			% [buttons.size(), translated.size()]
		)
	else:
		var changed := 0
		for index in translated.size():
			if translated[index].text != english[index]:
				changed += 1
		if changed == 0:
			_failures.append("The options stayed in the old language after switching to zh-CN.")

	# --- clicking an option ---------------------------------------------------
	var world_before := _navigator.get_world_click_event_count()
	_selected.clear()
	var target: Button = translated[1] if translated.size() > 1 else buttons[1]
	await _click_control(target)
	await _frames(4)
	if _selected.size() != 1:
		_failures.append(
			"Clicking an option selected %d options (%s)." % [_selected.size(), _last_click_note]
		)
	elif _selected[0] != 1:
		_failures.append("Clicking the second option selected index %d." % _selected[0])
	if _navigator.get_world_click_event_count() != world_before:
		_failures.append("A click on a dialogue option also reached the world.")
	if _player.is_path_active():
		_failures.append("A click on a dialogue option started the character walking.")
	L10n.set_locale("en")
	_dialogue.apply_locale("en")
	await _close_conversation()


func _check_digit_keys() -> void:
	_panel.close()
	await _frames(2)
	_panel.show_line({
		"speaker_name": "Q",
		"text": "Probe line.",
		"badge": "source.observed",
		"source": NarrativeEntry.Source.OBSERVED,
	})
	_panel.set_choices([{"text": "One"}, {"text": "Two"}, {"text": "Three"}])
	await _frames(3)
	var buttons := _buttons()
	if buttons.size() != 3:
		_failures.append("The probe choice list built %d buttons." % buttons.size())
		_panel.close()
		return
	var world_before := _navigator.get_world_click_event_count()
	_selected.clear()
	await _press_key(KEY_2)
	if _selected.size() != 1:
		_failures.append("The digit key selected %d options." % _selected.size())
	elif _selected[0] != 1:
		_failures.append("Pressing 2 selected index %d." % _selected[0])
	if _navigator.get_world_click_event_count() != world_before:
		_failures.append("A digit key press also reached the world.")
	# A click on the panel background is not an option and is not the world either.
	_selected.clear()
	var frame := _panel.get_node_or_null("Frame") as Control
	if frame != null:
		await _click_control(frame, Vector2(12.0, 12.0))
		await _frames(3)
		if not _selected.is_empty():
			_failures.append("Clicking the panel background selected option %d." % _selected[0])
		if _navigator.get_world_click_event_count() != world_before:
			_failures.append("Clicking the panel background reached the world.")
		# And the buttons still work afterwards: the panel was not left half-open.
		_selected.clear()
		var third := _buttons()[2] if _buttons().size() > 2 else null
		await _click_control(third)
		await _frames(3)
		if _selected.size() != 1 or _selected[0] != 2:
			_failures.append(
				"After a background click the third option selected %s (%s)."
				% [str(_selected), _last_click_note]
			)
	_panel.close()
	await _frames(2)


# --- helpers ----------------------------------------------------------------


## Runs the real classroom conversation until the stay/leave node offers its options.
func _open_a_choice() -> bool:
	if _dialogue.is_busy():
		await _close_conversation()
	_panel.close()
	await _frames(2)
	if not _dialogue.play_conversation(&"n_class"):
		_failures.append("The n_class conversation could not be started.")
		return false
	var steps := 0
	while not _dialogue.has_pending_choices() and _dialogue.is_busy() and steps < MAX_ADVANCE_STEPS:
		steps += 1
		_dialogue.advance_presentation()
		await _frames(2)
	if not _dialogue.has_pending_choices():
		_failures.append("The classroom conversation never offered its choice (after %d advances)." % steps)
		await _close_conversation()
		return false
	await _frames(3)
	if not _panel.visible:
		_failures.append("The panel is hidden while a choice is pending.")
	return true


func _close_conversation() -> void:
	var steps := 0
	while _dialogue.is_busy() and steps < MAX_ADVANCE_STEPS:
		steps += 1
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		else:
			_dialogue.advance_presentation()
		await _frames(2)
	if _dialogue.is_busy():
		_failures.append("The conversation would not close.")
	_panel.close()
	await _frames(2)


func _buttons() -> Array[Button]:
	var found: Array[Button] = []
	var container := _panel.get_node_or_null("Frame/Content/ChoicesContainer")
	if container == null:
		return found
	for child in container.get_children():
		var button := child as Button
		if button != null:
			found.append(button)
	return found


## A point on screen that is world, not UI: low enough to be floor, well away from the
## HUD's hint texts.
func _world_screen_position() -> Vector2:
	var size := root.get_visible_rect().size
	return Vector2(size.x * 0.35, size.y * 0.45)


func _click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	motion.button_mask = 0
	root.push_input(motion, true)
	await _frames(1)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = position
	press.global_position = position
	root.push_input(press, true)
	await _frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.button_mask = 0
	release.position = position
	release.global_position = position
	root.push_input(release, true)
	await _frames(1)


## Clicks a control at a point in its own local space, converting with the canvas
## transform so a layer offset or a scale cannot move the click. Records what was on
## screen at that point, so a failure says *where* the click went instead of only that
## nothing happened.
func _click_control(control: Control, local_point: Variant = null) -> void:
	_last_click_note = "no control to click"
	if control == null or not is_instance_valid(control):
		return
	var point: Vector2 = control.size * 0.5 if local_point == null else local_point
	var position := control.get_global_transform_with_canvas() * point
	var rect := control.get_global_rect()
	var id_before := control.get_instance_id()
	await _click_at(position)
	var hovered := root.gui_get_hovered_control()
	var hovered_name := "nothing"
	if hovered != null and is_instance_valid(hovered):
		hovered_name = String(hovered.name)
	_last_click_note = (
		"clicked %s (id %d) at %s, its rect is %s, viewport %s, hovered %s, alive %s"
		% [
			String(control.name), id_before, str(position), str(rect),
			str(root.get_visible_rect().size), hovered_name, str(is_instance_valid(control))
		]
	)


func _press_key(code: Key, shift: bool = false) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = code
	press.keycode = code
	press.pressed = true
	press.shift_pressed = shift
	root.push_input(press, true)
	await _frames(1)
	var release := InputEventKey.new()
	release.physical_keycode = code
	release.keycode = code
	release.pressed = false
	release.shift_pressed = shift
	root.push_input(release, true)
	await _frames(1)


func _on_choice_selected(index: int) -> void:
	_selected.append(index)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame

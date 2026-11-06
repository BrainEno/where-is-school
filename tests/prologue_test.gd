extends Node
## Deterministic headless regression coverage of the authored prologue.
## Run with --fixed-fps 60 so the movement route uses a reproducible physics step.

var failures: PackedStringArray = []
var checks: int = 0
var state: Node
var choice_paths_completed: bool = false
var playable_flow_completed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)


func _run() -> void:
	state = get_node("/root/GameState")
	_test_content_validation()
	await _test_choice_paths()
	await _test_playable_flow()
	state.call("clear")
	_check(choice_paths_completed and playable_flow_completed, "All test stages ran to completion.")
	if failures.is_empty():
		print("Prologue tests passed: %d checks (content, branching, evidence, UI, movement, transitions, revisit)." % checks)
		get_tree().quit(0)
	else:
		printerr("Prologue tests FAILED: %d of %d checks." % [failures.size(), checks])
		get_tree().quit(1)


func _test_content_validation() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DialogueRunner.CONTENT_PATH))
	_check(DialogueContent.validate(data, "biology_class.json").is_empty(), "Authored dialogue validates.")
	var bad_target: Dictionary = data.duplicate(true)
	bad_target["conversations"]["opening"]["nodes"]["q_wake"]["next"] = "missing_node"
	_check(not DialogueContent.validate(bad_target, "bad_target").is_empty(), "Invalid graph links are rejected.")
	var bad_imagination: Dictionary = data.duplicate(true)
	bad_imagination["conversations"]["bag_first"]["nodes"]["imagining"]["effects"][0]["category"] = "statement"
	bad_imagination["conversations"]["bag_first"]["nodes"]["imagining"]["effects"][0]["source"] = "q"
	_check(not DialogueContent.validate(bad_imagination, "bad_imagination").is_empty(), "Imagination cannot write NPC statements.")
	bad_imagination["conversations"]["bag_first"]["nodes"]["imagining"]["effects"][0]["category"] = "observed"
	_check(not DialogueContent.validate(bad_imagination, "bad_observation").is_empty(), "Dialogue cannot write objective observations.")
	var bad_speaker: Dictionary = data.duplicate(true)
	bad_speaker["conversations"]["opening"]["nodes"]["q_term"]["effects"][0]["source"] = "n"
	_check(not DialogueContent.validate(bad_speaker, "bad_speaker").is_empty(), "An account cannot be attributed to another speaker.")


func _test_choice_paths() -> void:
	var greeting_nodes: Array[String] = ["greet_question", "greet_polite", "greet_firm"]
	var memory_nodes: Array[String] = ["memory_blank", "memory_pen", "memory_later"]
	var memory_values: Array[String] = ["unavailable", "uncertain_pen", "deferred"]
	var teacher_nodes: Array[String] = ["teacher_ask", "teacher_challenge", "teacher_change"]
	var teacher_values: Array[String] = ["ask", "challenge", "change"]
	var book_nodes: Array[String] = ["book_share", "book_explain", "book_avoid"]
	var book_values: Array[String] = ["share", "explain", "avoid"]
	for i: int in range(3):
		state.call("clear")
		var runner: DialogueRunner = DialogueRunner.new()
		get_tree().root.add_child(runner)
		_check(runner.start(&"opening"), "Opening conversation starts in branch %d." % i)
		_check(runner.current_node_id == "q_wake", "Q automatically speaks first.")
		runner.advance() # physical sensation
		runner.advance() # greeting choice
		_check(runner.current_node_id == "greeting", "Greeting choice is reached.")
		runner.choose(i)
		_check(runner.current_node_id == greeting_nodes[i], "Greeting %d gives its own immediate response." % i)
		_advance_runner_to(runner, "memory_choice")
		runner.choose(i)
		_check(runner.current_node_id == memory_nodes[i], "Recollection %d gives its own immediate response." % i)
		_check(state.call("get_flag", &"recollection.exam") == memory_values[i], "Recollection %d is stored as uncertain, not an observation." % i)
		_advance_runner_to(runner, "teacher_choice")
		runner.choose(i)
		_check(runner.current_node_id == teacher_nodes[i], "Response to B %d changes Q's next line." % i)
		_check(state.call("get_flag", &"choice.b_response") == teacher_values[i], "Response to B %d is recorded." % i)
		_finish_runner(runner)
		_check(state.call("get_flag", &"statement.q.final_term") == true, "Q's term account is attributed to Q.")
		_check(not state.call("has_flag", &"observed.final_term"), "Q's account is not promoted to fact.")
		_check(runner.start(&"bag_first"), "Book conversation starts.")
		runner.advance()
		runner.advance()
		_check(runner.current_node_id == "book_choice", "Missing-book choice is reached.")
		runner.choose(i)
		_check(runner.current_node_id == book_nodes[i], "Book response %d changes Q's next line." % i)
		var before: Dictionary = state.call("get_snapshot")
		runner.advance() # imagination
		var after: Dictionary = state.call("get_snapshot")
		_check(runner.current_node_id == "imagining" and runner.current_node["kind"] == "imagination", "Imagination is explicitly tagged.")
		_check(after.erase(&"imagination.teacher_question"), "Imagination is separately recorded.")
		_check(before == after, "Imagination changes no observation, account, recollection, or choice.")
		runner.advance()
		_check(runner.start(&"q_revisit") and runner.current_node_id == book_values[i], "Q's later response follows the selected book choice (%d)." % i)
		_check(runner.history.any(func(entry: Dictionary) -> bool: return entry["kind"] == "choice_answer"), "History retains the selected response.")
		runner.queue_free()
		await get_tree().process_frame
	choice_paths_completed = true


func _advance_runner_to(runner: DialogueRunner, node_id: String) -> void:
	var limit: int = 0
	while runner.active and runner.current_node_id != node_id and limit < 32:
		runner.advance()
		limit += 1
	_check(runner.active and runner.current_node_id == node_id, "Reached dialogue node '%s'." % node_id)


func _finish_runner(runner: DialogueRunner) -> void:
	var limit: int = 0
	while runner.active and limit < 32:
		if runner.current_node.get("kind") == "choice":
			runner.choose(0)
		else:
			runner.advance()
		limit += 1
	_check(not runner.active, "Conversation can complete.")


func _press(key: Key) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = key
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up: InputEventKey = InputEventKey.new()
	up.keycode = key
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _until_node(runner: DialogueRunner, node_id: String, limit: int = 100) -> void:
	var count: int = 0
	while runner.active and runner.current_node_id != node_id and count < limit:
		await _press(KEY_E)
		count += 1
	_check(runner.active and runner.current_node_id == node_id, "Keyboard reaches dialogue node '%s'." % node_id)


func _finish_with_keyboard(runner: DialogueRunner) -> void:
	var count: int = 0
	while runner.active and count < 100:
		await _press(KEY_E)
		count += 1
	_check(not runner.active, "Dialogue can be completed using E.")


func _release_movement() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(action)


func _drive(player: PlayerController, target: Vector2, frames: int = 500, tolerance: float = 0.23, stop_on_transition: Node = null) -> bool:
	for _i: int in range(frames):
		if stop_on_transition != null and stop_on_transition.get("transitioning"):
			_release_movement()
			await get_tree().physics_frame
			return true
		var difference: Vector2 = target - Vector2(player.global_position.x, player.global_position.z)
		if difference.length() <= tolerance:
			_release_movement()
			await get_tree().physics_frame
			return true
		var desired: Vector3 = Vector3(difference.x, 0.0, difference.y).normalized()
		var right: Vector3 = player.camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		var forward: Vector3 = -player.camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var horizontal: float = desired.dot(right)
		var vertical: float = desired.dot(forward)
		Input.action_press(&"move_right", maxf(horizontal, 0.0))
		Input.action_press(&"move_left", maxf(-horizontal, 0.0))
		Input.action_press(&"move_forward", maxf(vertical, 0.0))
		Input.action_press(&"move_back", maxf(-vertical, 0.0))
		await get_tree().physics_frame
	_release_movement()
	await get_tree().physics_frame
	return false


func _walk(player: PlayerController, target: Vector2, label: String) -> void:
	var reached: bool = await _drive(player, target)
	_check(reached, "Navigate %s to %s (at %s)." % [label, target, player.global_position])


func _interact_focused(interaction: InteractionController, id: StringName, runner: DialogueRunner, expects_dialogue: bool = true) -> void:
	interaction.refresh_focus()
	_check(is_instance_valid(interaction.focused) and interaction.focused.interaction_id == id, "Nearby prompt targets %s (got %s)." % [id, interaction.focused.interaction_id if is_instance_valid(interaction.focused) else &"none"])
	await _press(KEY_E)
	_check(runner.active == expects_dialogue, "E starts the expected %s interaction." % id)


func _test_playable_flow() -> void:
	state.call("clear")
	var packed: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	var game: Node3D = packed.instantiate()
	game.set("wake_duration", 0.1)
	var initial_classroom: ClassroomLocation = game.get_node("LocationRoot/Classroom") as ClassroomLocation
	initial_classroom.entrance_duration = 0.2
	get_tree().root.add_child(game)
	await get_tree().process_frame
	var runner: DialogueRunner = game.get_node("DialogueRunner") as DialogueRunner
	var hud: PrologueHUD = game.get_node("PrologueHUD") as PrologueHUD
	var player: PlayerController = game.get_node("Player") as PlayerController
	var interaction: InteractionController = game.get_node("InteractionController") as InteractionController
	await get_tree().create_timer(0.2).timeout
	_check(runner.active and runner.current_node_id == "q_wake", "Wake starts Q's dialogue without an interaction marker.")
	_check(player.seated.visible and not player.control_enabled, "Player is seated and input is locked during the opening.")
	_check(state.call("get_flag", &"observed.woke_in_classroom") == true, "Wake is an observed event.")
	# This generic fixture is not story text or material from a manuscript.
	var long_chinese: String = "这是用于测试长文本显示与滚动的通用句子。".repeat(100)
	hud._on_line_presented({"speaker": "YOU NOTICE", "kind": "observation", "text": long_chinese})
	for _frame: int in range(4):
		await get_tree().process_frame
	var body_scroll: VScrollBar = hud.body.get_v_scroll_bar()
	_check(hud.body.get_total_character_count() == long_chinese.length() and body_scroll.max_value > body_scroll.page, "Long Unicode dialogue remains scrollable instead of being truncated.")
	var original_line: Dictionary = runner.current_node.duplicate(true)
	original_line["id"] = runner.current_node_id
	hud._on_line_presented(original_line)
	await _press(KEY_E)
	await _press(KEY_E)
	_check(runner.current_node_id == "greeting" and hud.choices.get_child_count() == 3, "Greeting renders three choices with one keypress per line.")
	await _press(KEY_H)
	_check(hud.backlog.visible and not player.control_enabled, "History opens and disables movement.")
	var node_before_history: String = runner.current_node_id
	await _press(KEY_E)
	_check(runner.current_node_id == node_before_history, "History consumes dialogue advance input.")
	await _press(KEY_ENTER)
	_check(not hud.backlog.visible and runner.current_node_id == node_before_history, "Enter closes focused history without selecting an underlying choice.")
	await _press(KEY_H)
	var old_size: int = hud.text_size
	hud.get_node("%Larger").emit_signal("pressed")
	_check(hud.text_size == old_size + 2, "Text size setting changes the dialogue size.")
	_check(hud.backlog_entries.get_child_count() == runner.history.size(), "Rebuilding history does not leave duplicate entries.")
	hud.speed_button.emit_signal("pressed")
	_check(not hud.instant_text, "Slow text setting is selectable.")
	await _press(KEY_H)
	await _press(KEY_RIGHT)
	_check(hud.get("_selected_choice") == 1, "Keyboard focus and selected choice remain synchronized.")
	await _press(KEY_E)
	_check(runner.current_node_id == "greet_polite", "Focused choice, rather than a stale selection, is applied.")
	_check(hud.get("_typing") == true, "Slow text reveals progressively.")
	await _press(KEY_E)
	_check(runner.current_node_id == "greet_polite" and hud.get("_typing") == false, "First advance completes slow text without skipping the line.")
	await _press(KEY_E)
	_check(runner.current_node_id == "q_term", "Second advance proceeds to the next line.")
	await _press(KEY_H)
	hud.speed_button.emit_signal("pressed")
	await _press(KEY_H)
	await _finish_with_keyboard(runner)
	_check(player.standing.visible and player.control_enabled, "The player stands and can move after Q's opening.")
	_check(hud.controls.is_visible_in_tree() and hud.controls.get_global_rect().position.x < 1600.0, "Movement and wait instructions are visible inside the viewport.")
	_check(not state.call("has_flag", &"observed.biology_textbook_missing"), "The textbook is not discovered before searching the bag.")
	await _interact_focused(interaction, &"schoolbag", runner)
	_check(runner.current_node_id == "open", "One interaction press does not also skip the first line.")
	_check(state.call("get_flag", &"observed.biology_textbook_missing") == true, "The actual bag interaction discovers the missing book.")
	await _until_node(runner, "book_share")
	var physical_before: Array[Vector3] = [player.global_position, initial_classroom.substitute.global_position, initial_classroom.door_leaf.global_position]
	var snapshot: Dictionary = state.call("get_snapshot")
	await _press(KEY_E)
	_check(runner.current_node_id == "imagining" and hud.subjective_wash.visible, "The imagining is presented with a distinct visual treatment.")
	_check(hud.kind_label.text.contains("NOT AN EVENT"), "The UI explicitly marks imagination as not an event.")
	var imagined_snapshot: Dictionary = state.call("get_snapshot")
	imagined_snapshot.erase(&"imagination.teacher_question")
	_check(snapshot == imagined_snapshot, "Only imagination state changes during subjective presentation.")
	_check(physical_before == [player.global_position, initial_classroom.substitute.global_position, initial_classroom.door_leaf.global_position], "Imagination does not move the player, N, or the door.")
	await _finish_with_keyboard(runner)
	_check(hud.wait_available, "Waiting is offered explicitly after inspecting the bag.")
	await _interact_focused(interaction, &"schoolbag", runner)
	_check(runner.conversation_id == &"bag_again", "Revisiting the bag preserves the missing-book observation.")
	await _finish_with_keyboard(runner)

	# Walk the actual floor plan instead of teleporting to props.
	await _walk(player, Vector2(1.65, 3.1), "into the aisle")
	await _walk(player, Vector2(1.65, -2.4), "up the aisle past collidable desks")
	await _walk(player, Vector2(-0.2, -2.45), "to the teacher's desk")
	await _interact_focused(interaction, &"set_square", runner)
	_check(state.call("get_flag", &"observed.set_square_examined") == true, "The damaged wooden set square was inspected.")
	await _finish_with_keyboard(runner)
	await _walk(player, Vector2(-3.45, -2.45), "around the teacher's desk")
	await _walk(player, Vector2(-3.45, -3.5), "toward the blackboard")
	await _interact_focused(interaction, &"board", runner)
	_check(state.call("get_flag", &"observed.blackboard_examined") == true, "The blackboard was inspected.")
	await _finish_with_keyboard(runner)
	await _walk(player, Vector2(-4.9, -2.4), "toward the windows")
	await _walk(player, Vector2(-4.9, 0.2), "along the window wall")
	await _interact_focused(interaction, &"window", runner)
	_check(state.call("get_flag", &"observed.window_examined") == true, "The window was inspected.")
	await _finish_with_keyboard(runner)
	await _walk(player, Vector2(-4.9, -2.4), "back to the front")
	await _walk(player, Vector2(1.8, -2.4), "across the front of the room")
	await _walk(player, Vector2(1.9, -3.7), "toward the clock")
	await _interact_focused(interaction, &"clock", runner)
	_check(state.call("get_flag", &"observed.clock_examined") == true, "The clock was inspected.")
	await _finish_with_keyboard(runner)
	await _walk(player, Vector2(4.4, -3.8), "to the classroom door")
	await _interact_focused(interaction, &"classroom_exit", runner)
	_check(runner.conversation_id == &"door_before", "Door explains the lesson has not started.")
	await _finish_with_keyboard(runner)
	var crossed_closed: bool = await _drive(player, Vector2(4.4, -5.9), 120)
	_check(not crossed_closed and player.global_position.z > -4.95, "Closed door physically blocks the player.")
	await _press(KEY_SPACE)
	_check(not state.call("has_flag", &"observed.lesson_bell_heard") and hud.objective_label.text.contains("Step back"), "N's entrance waits for the player to clear the path.")
	await _walk(player, Vector2(3.65, -2.25), "away from the entrance path")
	await _press(KEY_SPACE)
	_check(not player.control_enabled and state.call("get_flag", &"observed.lesson_bell_heard") == true, "Waiting locks movement and triggers the lesson bell.")
	await get_tree().create_timer(1.2).timeout
	_check(initial_classroom.substitute.visible and state.call("get_flag", &"observed.n_entered_classroom") == true, "N physically enters before speaking.")
	_check(runner.active and runner.conversation_id == &"lesson" and runner.current_node_id == "n_seen", "N's lesson starts after the entrance with the observed young teacher.")
	await _finish_with_keyboard(runner)
	await get_tree().physics_frame
	_check(state.call("get_flag", &"statement.n.b_is_away") == true and state.call("get_flag", &"statement.n.is_covering") == true, "N's account of B's absence and substitution remains attributed.")
	_check(state.call("get_flag", &"observed.b_not_at_this_lesson") == true, "B is absent from the presented lesson.")
	_check(state.call("get_flag", &"observed.free_activity_granted") == true and initial_classroom.n_target.available, "Free activity enables N and unlocks the route.")
	_check(initial_classroom.barrier.disabled, "The physical door barrier is disabled after release.")
	_check(not initial_classroom.substitute_collision.disabled, "N has a physical collider after the entrance.")
	var walked_through_n: bool = await _drive(player, Vector2(1.25, -3.6), 120, 0.15)
	_check(not walked_through_n and player.global_position.distance_to(initial_classroom.substitute.global_position) > 0.5, "The player cannot walk through N.")
	await _walk(player, Vector2(3.65, -2.25), "around N toward the exit")
	await _walk(player, Vector2(4.4, -4.3), "back to the opened door")
	# Crossing the actual doorway triggers the corridor; no interaction press is needed.
	await _drive(player, Vector2(4.4, -5.6), 100, 0.23, game)
	await get_tree().create_timer(0.8).timeout
	_check(game.get("location_id") == &"corridor", "Walking through the doorway transitions to the corridor.")
	_check(state.call("get_flag", &"observed.entered_corridor") == true, "Corridor arrival is observed.")
	# Return, then re-enter and reach the exit to verify state reconstruction.
	await _interact_focused(interaction, &"return_classroom", runner, false)
	await get_tree().create_timer(0.8).timeout
	_check(game.get("location_id") == &"classroom", "The corridor can return to the classroom.")
	var revisited: ClassroomLocation = game.get("current_location") as ClassroomLocation
	_check(revisited.substitute.visible and revisited.n_target.available and revisited.barrier.disabled, "N, the open door, and free-activity state are reconstructed on return.")
	_check(state.call("get_flag", &"observed.biology_textbook_missing") == true, "The missing-book observation survives scene transitions.")
	await _interact_focused(interaction, &"classroom_exit", runner, false)
	await get_tree().create_timer(0.8).timeout
	_check(game.get("location_id") == &"corridor", "The reopened classroom exit can be used by interaction.")
	await _walk(player, Vector2(0, -4.2), "through the corridor to the school exit")
	await _interact_focused(interaction, &"school_threshold", runner)
	await _finish_with_keyboard(runner)
	_check(hud.ending.visible and state.call("get_flag", &"observed.school_exit_reached") == true, "The school exit presents an explicit milestone ending.")
	_check(not player.control_enabled, "The ending stops movement until dismissed.")
	hud.resume_button.emit_signal("pressed")
	_check(not hud.ending.visible and player.control_enabled, "Return to corridor works after the ending.")
	game.queue_free()
	await get_tree().process_frame
	playable_flow_completed = true

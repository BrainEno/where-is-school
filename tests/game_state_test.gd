extends SceneTree
## Unit tests for the GameState autoload (run headless via --script).

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var game_state_script: GDScript = load("res://scripts/autoload/game_state.gd") as GDScript

	# --- basic set/get/has
	var state: Node = game_state_script.new()
	if state.has_flag(&"observed.textbook_missing"):
		failures.append("fresh state should not have observed.textbook_missing")
	state.set_flag(&"observed.textbook_missing", true)
	if not state.has_flag(&"observed.textbook_missing"):
		failures.append("set_flag/has_flag round trip failed")
	if state.get_flag(&"observed.textbook_missing") != true:
		failures.append("get_flag returned wrong value")
	if state.get_flag(&"nope", 42) != 42:
		failures.append("get_flag default not returned for missing flag")

	# --- empty flag is rejected
	state.set_flag(&"", true)
	if state.has_flag(&""):
		failures.append("empty flag identifier should not be set")

	# --- duplicate set does not re-emit
	var emissions: Array = []
	state.story_flag_changed.connect(func(flag: StringName, _old: Variant, _new: Variant) -> void: emissions.append(flag))
	state.set_flag(&"claim.q.exam_blank", true)
	state.set_flag(&"claim.q.exam_blank", true)
	state.set_flag(&"claim.q.exam_blank", false)
	if emissions.size() != 2:
		failures.append("expected 2 story_flag_changed emissions, got %d" % emissions.size())

	# --- prefix counting
	state.set_flag(&"observed.inspect.blackboard", true)
	state.set_flag(&"observed.inspect.noticeboard", true)
	state.set_flag(&"observed.inspect.clock", true)
	if state.count_flags_with_prefix("observed.inspect.") != 3:
		failures.append("count_flags_with_prefix('observed.inspect.') != 3")
	if state.count_flags_with_prefix("observed.") != 4:
		failures.append("count_flags_with_prefix('observed.') != 4")

	# --- snapshot / replace / clear
	var snapshot: Dictionary = state.get_snapshot()
	state.clear()
	if state.has_flag(&"observed.textbook_missing"):
		failures.append("clear() did not clear flags")
	state.replace_snapshot(snapshot)
	if not state.has_flag(&"observed.textbook_missing"):
		failures.append("replace_snapshot did not restore flags")
	state.clear()
	if state.has_flag(&"claim.q.exam_blank"):
		failures.append("clear() after restore did not clear flags")
	state.free()

	if not failures.is_empty():
		for failure in failures:
			push_error("game_state_test failed: %s" % failure)
		quit(1)
		return
	print("game_state_test passed")
	quit(0)

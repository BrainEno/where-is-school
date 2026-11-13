extends SceneTree
## The free-period branch, at the level of story state.
##
## N announces that the class may study or go to the yard. The conversation then
## ends; Q's separate invitation is available only after class_dismissed is set.
## Accepting or declining the invitation records an intention, never a scene change:
## the classroom door remains the actual way out.

const Harness = preload("res://tests/test_harness.gd")
const MAX_STEPS := 400

var _failures: Array[String] = []
var _game_state: Node = null
var _narrative: Node = null
var _abilities: InnerAbilities = null
var _library: DialogueLibrary = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "free_period_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	if _game_state == null or _narrative == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	_abilities = InnerAbilities.load_all()
	if not _abilities.is_valid():
		Harness.finish(self, ["abilities: " + _abilities.describe_errors()], "")
		return
	_library = DialogueLibrary.load_all(_abilities)
	if not _library.is_valid():
		Harness.finish(self, ["dialogue: " + _library.describe_errors()], "")
		return

	_play_branch("en", &"no")
	_play_branch("en", &"yes")
	_play_branch("zh-CN", &"no")
	_play_branch("zh-CN", &"yes")

	Harness.finish(
		self, _failures,
		"N announces the free period; Q's later invitation records stay/leave intent without moving the player."
	)


func _play_branch(locale: String, choice_id: StringName) -> void:
	Harness.clear_session_state(self)
	_library.set_locale(locale)
	var line := "%s/%s" % [locale, choice_id]
	var runtime := DialogueRuntime.new(
		_game_state, _narrative, CharacterDirectory.load_all(_abilities), _abilities,
		CheckResolver.new(7)
	)

	var n_graph := _library.get_graph(&"n_class")
	if n_graph == null or not runtime.start(n_graph, &"n_class"):
		_failures.append("%s: n_class did not start." % line)
		return

	var steps := 0
	while runtime.is_active() and steps < MAX_STEPS:
		steps += 1
		var choices := runtime.get_available_choice_ids()
		if not choices.is_empty():
			runtime.choose(0)
		else:
			runtime.advance()
	if runtime.is_active():
		_failures.append("%s: n_class did not terminate." % line)
		return
	if not _flag(StoryFlags.CLASS_DISMISSED):
		_failures.append("%s: N did not dismiss the class before Q's invitation." % line)
		return

	var q_graph := _library.get_graph(&"q_after_dismissal")
	if q_graph == null or not runtime.start(q_graph, &"q_after_dismissal"):
		_failures.append("%s: Q's free-period invitation did not start." % line)
		return

	var took_branch := false
	steps = 0
	while runtime.is_active() and steps < MAX_STEPS:
		steps += 1
		var choices := runtime.get_available_choice_ids()
		if not choices.is_empty():
			var index := choices.find(choice_id)
			if index >= 0:
				took_branch = true
				runtime.choose(index)
			else:
				runtime.choose(0)
		else:
			runtime.advance()
	if runtime.is_active():
		_failures.append("%s: Q's invitation did not terminate." % line)
		return
	if not took_branch:
		_failures.append("%s: Q's invitation did not offer '%s'." % [line, choice_id])
		return

	_check_state(line, choice_id)


func _check_state(line: String, choice_id: StringName) -> void:
	var stayed := choice_id == &"no"
	if not _flag(StoryFlags.CLASS_DISMISSED):
		_failures.append("%s: the class was not dismissed, so there is no free period." % line)
	if _flag(StoryFlags.FREE_PERIOD_STAYED) != stayed:
		_failures.append("%s: FREE_PERIOD_STAYED has the wrong value." % line)
	if _flag(StoryFlags.FREE_PERIOD_LEAVING) == stayed:
		_failures.append("%s: the free-period flags are not exclusive." % line)

	var objective := String(_game_state.get_flag(StoryFlags.OBJECTIVE_KEY, ""))
	var expected := "objective.stay_classroom" if stayed else "objective.leave_classroom"
	if objective != expected:
		_failures.append("%s: the objective is '%s', expected '%s'." % [line, objective, expected])

	var entry := &"n_stayed" if stayed else &"n_leaving"
	if not _narrative.has_entry(entry):
		_failures.append("%s: the branch recorded no knowledge entry ('%s')." % [line, entry])
	elif int(_narrative.get_entry(entry).source) != NarrativeEntry.Source.OBSERVED:
		_failures.append("%s: what the player chose was not recorded as observed." % line)

	var location := String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, ""))
	if location == "corridor" or location == "playground":
		_failures.append("%s: the choice moved the player out of the room by itself." % line)
	if not _flag(StoryFlags.LEFT_CLASSROOM) and not location.is_empty() and location != "classroom":
		_failures.append("%s: the player left without activating the door." % line)


func _flag(flag: StringName) -> bool:
	var value: Variant = _game_state.get_flag(flag, false)
	return value == true

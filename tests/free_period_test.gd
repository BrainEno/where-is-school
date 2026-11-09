extends SceneTree
## The free-period branch, at the level of story state.
##
## N's announcement now hands control back instead of pushing the player out of
## the room. Two things have to be true, and only one of them is visible on screen:
##
## 1. **Staying is a real option.** Picking "stay" must keep the player in the
##    classroom (no scene change, no forced beat) and must be recorded as having
##    happened, so the rest of the game can tell the two free periods apart.
## 2. **Leaving is a real option, and it is not a cutscene.** Picking "leave" sets
##    the intent and the objective, and nothing else: walking through the door is
##    still the player's job.
##
## The assertions are made on GameState and NarrativeState snapshots rather than on
## text, because this branch is about what the game remembers.

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

	_play_branch("en", &"stay")
	_play_branch("en", &"leave")
	_play_branch("zh-CN", &"stay")
	_play_branch("zh-CN", &"leave")

	Harness.finish(
		self, _failures,
		"staying and leaving are both recorded, and neither one is forced."
	)


# --- cases ------------------------------------------------------------------


## Runs `n_class` to its last node, taking `choice_id` when the stay/leave node
## comes up, and asserts what the game now remembers.
func _play_branch(locale: String, choice_id: StringName) -> void:
	Harness.clear_session_state(self)
	_library.set_locale(locale)
	var line := "%s/%s" % [locale, choice_id]

	var runtime := DialogueRuntime.new(
		_game_state, _narrative, CharacterDirectory.load_all(_abilities), _abilities,
		CheckResolver.new(7)
	)
	var graph := _library.get_graph(&"n_class")
	if graph == null:
		_failures.append("%s: the n_class conversation is missing." % line)
		return
	if not runtime.start(graph, &"n_class"):
		_failures.append("%s: n_class did not start." % line)
		return

	var took_branch := false
	var steps := 0
	while runtime.is_active() and steps < MAX_STEPS:
		steps += 1
		var choice_ids := runtime.get_available_choice_ids()
		if not choice_ids.is_empty():
			var index := choice_ids.find(choice_id)
			if index >= 0:
				took_branch = true
			else:
				index = 0
			runtime.choose(index)
			continue
		runtime.advance()
	if steps >= MAX_STEPS:
		_failures.append("%s: n_class did not terminate." % line)
		return
	if not took_branch:
		_failures.append("%s: the free-period choice never appeared." % line)
		return

	_check_state(line, choice_id)


func _check_state(line: String, choice_id: StringName) -> void:
	var stayed := choice_id == &"stay"
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
		_failures.append("%s: what the player did was not recorded as observed." % line)

	# Choosing to leave is an intention, not a scene change: the location is set by
	# the exit, and this test never activated one.
	var location := String(_game_state.get_flag(StoryFlags.CURRENT_LOCATION, ""))
	if location == "corridor" or location == "playground":
		_failures.append("%s: the choice moved the player out of the room by itself." % line)
	if not _flag(StoryFlags.LEFT_CLASSROOM) and not location.is_empty() and location != "classroom":
		_failures.append("%s: the player left without activating the door." % line)


func _flag(flag: StringName) -> bool:
	var value: Variant = _game_state.get_flag(flag, false)
	return value == true

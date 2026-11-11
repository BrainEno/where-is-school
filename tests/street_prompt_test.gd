extends SceneTree
## The street's way back into the school says what it does.
##
## Two things are checked here, and they are different problems:
##
## 1. the street exit has its own prompt key (`prompt.back_to_classroom`), present in
##    both languages, with the destination untouched;
## 2. the story's "the class is dismissed" rewrite only touches the classroom door. It
##    used to match any exit whose destination was the corridor, which also matched
##    the street's return exit — so standing in the street showed "Leave the
##    classroom" at the school door. That regression is pinned below.
##
## The corridor's own `prompt.back_inside` is checked as well: it is a different door
## and it keeps its own text.

const Harness = preload("res://tests/test_harness.gd")

const STREET := "res://scenes/locations/street/street.tscn"
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"

const EXPECTED := {
	"en": "Return to classroom",
	"zh-CN": "回到教室",
}

var _failures: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _game_state = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 150.0, "street_prompt_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	_game_state = autoloads["game_state"]

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

	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_sequence = _main.get_node_or_null("OpeningSequence") as OpeningSequence
	if _host == null or _player == null or _dialogue == null or _sequence == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	_sequence.allow_player_control()

	_check_locale_keys()
	await _check_street_exit_text()
	await _check_corridor_still_says_back_inside()
	await _check_dismissal_does_not_rewrite_the_street()

	Harness.finish(
		self, _failures,
		"the street's way back says 'Return to classroom' in both languages and the story rewrite left it alone."
	)


# --- cases ------------------------------------------------------------------


## The keys exist, with the agreed text, in both languages.
func _check_locale_keys() -> void:
	for locale: String in EXPECTED.keys():
		if not L10n.has_key("prompt.back_to_classroom", locale):
			_failures.append("prompt.back_to_classroom is missing from %s." % locale)
			continue
		var text := L10n.t_for("prompt.back_to_classroom", locale)
		if text != String(EXPECTED[locale]):
			_failures.append(
				"In %s prompt.back_to_classroom reads '%s', expected '%s'."
				% [locale, text, String(EXPECTED[locale])]
			)
	# The corridor's own door keeps its own key, in both languages.
	for locale: String in EXPECTED.keys():
		if not L10n.has_key("prompt.back_inside", locale):
			_failures.append("prompt.back_inside is missing from %s." % locale)


func _check_street_exit_text() -> void:
	var location := await _enter(STREET, &"FromCorridor")
	if location == null:
		return
	var exit := location.get_node_or_null("Interactables/BackToSchool") as LocationExit
	if exit == null:
		_failures.append("The street lost its way back to school.")
		return
	if exit.prompt_key != "prompt.back_to_classroom":
		_failures.append("The street exit still uses the prompt key '%s'." % exit.prompt_key)
	if exit.destination_scene != CORRIDOR:
		_failures.append("The street exit now leads to '%s'." % exit.destination_scene)
	if exit.destination_spawn != &"FromStreet":
		_failures.append("The street exit now spawns at '%s'." % String(exit.destination_spawn))
	if exit.destination_id != &"corridor":
		_failures.append("The street exit no longer records the corridor as its destination.")
	if exit.is_milestone_end:
		_failures.append("The street exit turned into a milestone end.")
	for locale: String in EXPECTED.keys():
		# The game switches language through the `Loc` autoload, which sets both the
		# dialogue library and the static display locale. A plain script run has no
		# autoload, so both steps are done here, in the same order.
		L10n.set_locale(locale)
		_dialogue.apply_locale(locale)
		var prompt := _dialogue.get_interact_prompt(exit)
		if prompt != String(EXPECTED[locale]):
			_failures.append(
				"In %s the street exit shows '%s' instead of '%s'."
				% [locale, prompt, String(EXPECTED[locale])]
			)
	L10n.set_locale("en")
	_dialogue.apply_locale("en")
	await _frames(2)


## A different door, a different sentence.
func _check_corridor_still_says_back_inside() -> void:
	var location := await _enter(CORRIDOR, &"FromStreet")
	if location == null:
		return
	var exit := location.get_node_or_null("Interactables/BackToClassroom") as LocationExit
	if exit == null:
		_failures.append("The corridor lost the door back to the classroom.")
		return
	if exit.prompt_key != "prompt.back_inside":
		_failures.append("The corridor's door now uses '%s'." % exit.prompt_key)
	if not await _check_text(exit, "Go back inside"):
		_failures.append("The corridor's door no longer reads 'Go back inside'.")
	await _frames(2)


## The regression: with the class dismissed, the director rewrites the classroom door
## and nothing else.
func _check_dismissal_does_not_rewrite_the_street() -> void:
	var street := await _enter(STREET, &"FromCorridor")
	if street == null:
		return
	_game_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	_sequence.call("update_exit_prompt")
	await _frames(2)
	var street_exit := street.get_node_or_null("Interactables/BackToSchool") as LocationExit
	if street_exit == null:
		_failures.append("The street lost its way back to school during the dismissal check.")
		return
	if not street_exit.get_prompt_override().is_empty():
		_failures.append(
			"Dismissing the class rewrote the street exit's prompt to '%s'."
			% street_exit.get_prompt_override()
		)
	var shown := _dialogue.get_interact_prompt(street_exit)
	if shown != String(EXPECTED["en"]):
		_failures.append(
			"With the class dismissed, the street exit shows '%s' instead of '%s'."
			% [shown, String(EXPECTED["en"])]
		)

	# And the classroom door still does the thing the rewrite exists for.
	var classroom := await _enter(CLASSROOM, &"FromCorridor")
	if classroom == null:
		return
	_sequence.call("update_exit_prompt")
	await _frames(2)
	var door := classroom.find_interactable(&"classroom_door")
	if door == null:
		_failures.append("The classroom lost its door.")
		return
	if door.get_prompt_override() != "prompt.door_leave":
		_failures.append(
			"With the class dismissed the classroom door's prompt override is '%s'."
			% door.get_prompt_override()
		)
	if _dialogue.get_interact_prompt(door) != L10n.t("prompt.door_leave"):
		_failures.append("The classroom door does not show the dismissal prompt.")


# --- helpers ----------------------------------------------------------------


func _check_text(interactable: Interactable, expected: String) -> bool:
	L10n.set_locale("en")
	_dialogue.apply_locale("en")
	var shown := _dialogue.get_interact_prompt(interactable)
	return shown == expected


func _enter(scene: String, spawn: StringName) -> LocationRoot:
	if not _host.load_location(scene, spawn, _player):
		return null
	await _frames(3)
	await _physics_frames(2)
	return _host.get_current()


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame

extends SceneTree
## A conversation can be over before the call that started it returns.
##
## `DialogueRuntime.start()` walks the graph synchronously. Three of its exits end
## the conversation inside that walk: a node id that does not exist, a first node
## whose conditions are not met with nothing left after it, and the step limit. In
## all three `conversation_finished` is emitted *before* `play_conversation()`
## returns to its caller.
##
## The bug this test pins down: `OpeningSequence.play_conversation()` awaited that
## signal unconditionally. When the conversation had already ended, the await
## waited forever, the beat that called it never reached `end_beat()`, the player
## lock stayed on, and the game was stuck with nothing on screen and no way out.
## Before the fix this test hangs at "the director waiting for a conversation that
## is already over" until the watchdog fails it; after the fix it passes.
##
## The fixture conversation is built in code and installed into the real library's
## index, so the real controller, the real runtime and the real director are under
## test — a stub dialogue controller could happily agree with a wrong director.

const Harness = preload("res://tests/test_harness.gd")

const FIXTURE_ID := &"fixture_gated_silence"
## Never written by content, by the fixture, or by this test, so the fixture's
## only node is skipped every single run.
const FIXTURE_NEVER_SET := &"fixture_flag_nobody_sets"

var _failures: Array[String] = []
var _main: Node = null
var _dialogue: DialogueController = null
var _player: PlayerController = null
var _sequence: OpeningSequence = null


func _initialize() -> void:
	# The watchdog is the assertion for the "before the fix" half of this test: a
	# director that waits for a signal already sent never returns, and a hang has to
	# end as a failure rather than as a CI job that eats its whole time budget.
	Harness.arm_watchdog(self, 150.0, "dialogue_sync_finish_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	_check_validation()

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

	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	_player = _main.get_node_or_null("Player") as PlayerController
	_sequence = sequence_node as OpeningSequence
	if _dialogue == null or _player == null or _sequence == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return

	# The passive inner voice can open its own conversation at any time, which would
	# make the lock assertions below a race. It has its own test; switch it off.
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)

	var installed := _install_fixture()
	if not installed:
		Harness.finish(self, _failures, "")
		return

	_sequence.allow_player_control()
	await _frames(2)
	_expect(_player.is_control_enabled(), "The player never received control at the start.")

	# --- The regression -------------------------------------------------------
	# Exactly what the authored beats do: take the lock, play a conversation, give
	# the lock back. The only unusual thing is that this conversation has nothing
	# left to say — which is a state content can reach without meaning to.
	Harness.stage = "the director waiting for a conversation that is already over"
	await _sequence.begin_beat()
	_expect(_player.is_control_enabled() == false, "The beat did not take the player lock.")
	await _sequence.play_conversation(FIXTURE_ID)
	_expect(_dialogue.is_busy() == false, "The fixture conversation is still on screen.")
	_sequence.end_beat()
	await _frames(2)
	_expect(
		_player.is_control_enabled(),
		"Control did not come back after a conversation that ended inside its own start."
	)
	_expect(_sequence.is_beat_active() == false, "The beat stayed active after it ended.")

	# The director has to survive it a second time: a soft lock that only happens
	# once is still a soft lock, but a director left in a half-finished state would
	# show up here.
	Harness.stage = "the second attempt"
	await _sequence.begin_beat()
	await _sequence.play_conversation(FIXTURE_ID)
	_sequence.end_beat()
	await _frames(2)
	_expect(_player.is_control_enabled(), "Control did not come back on the second attempt.")

	_main.queue_free()
	await process_frame
	Harness.stage = ""
	Harness.finish(
		self, _failures,
		"a conversation that finishes inside start() no longer locks the player out."
	)


# --- Content rule ------------------------------------------------------------


## The trap is preventable at authoring time: a start node that cannot be skipped
## cannot produce a conversation that shows nothing. The validator refuses one.
func _check_validation() -> void:
	var gated := _build_conversation(true)
	_expect(
		_mentions(gated.errors, "conditional"),
		"The validator accepted a start node that can be skipped."
	)

	var plain := _build_conversation(false)
	_expect(
		not _mentions(plain.errors, "conditional"),
		"The validator flagged a start node that cannot be skipped."
	)


func _mentions(messages: Array[String], needle: String) -> bool:
	for message in messages:
		if message.contains(needle):
			return true
	return false


# --- Fixtures ----------------------------------------------------------------


## Installs the fixture graph into the library the controller already holds.
## Going through the real index (rather than a fake library) keeps
## `play_conversation()` — the method the director calls — on its normal path.
func _install_fixture() -> bool:
	var library: DialogueLibrary = _dialogue._library
	if library == null:
		_failures.append("The dialogue controller has no loaded library.")
		return false
	var locale := library.get_locale()
	var index: Dictionary = library._index.get(locale, {})
	if index.is_empty():
		_failures.append("The dialogue library has no index for '%s'." % locale)
		return false
	index[FIXTURE_ID] = _build_conversation(true)
	return true


## A one-node conversation whose only node is gated on a flag nobody sets, so the
## runtime skips it, finds nothing to continue into, and finishes.
func _build_conversation(gated: bool) -> DialogueGraph:
	var node := DialogueGraph.DialogueNode.new()
	node.node_id = &"only_line"
	node.speaker_id = &"q"
	node.text = "This line is only shown when the fixture flag is set."
	node.ends_here = true
	if gated:
		var flags: Array[StringName] = [FIXTURE_NEVER_SET]
		node.all_flags = flags

	var conversation := DialogueGraph.Conversation.new()
	conversation.conversation_id = FIXTURE_ID
	conversation.start_id = node.node_id
	conversation.nodes[node.node_id] = node
	conversation.order.append(node.node_id)

	var graph := DialogueGraph.new()
	graph.source_path = "res://tests/dialogue_sync_finish_test.gd (fixture)"
	graph.conversations[FIXTURE_ID] = conversation

	# Validation is run here rather than at load time because this conversation
	# deliberately never reaches the content files.
	graph._validate_conversation(conversation, graph.source_path)
	return graph


# --- Helpers ----------------------------------------------------------------


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

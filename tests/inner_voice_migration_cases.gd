extends RefCounted
## Called by save_validation_test.gd: real save files, all 19 shipped check nodes,
## both historical outcomes, and per-voice passive accounting. No authored prose
## is copied into fixtures, and no source JSON is written.

class SeedProbe extends Node:
	var value: int = 0

	func set_session_seed(seed_value: int) -> void:
		value = seed_value

	func get_session_seed() -> int:
		return value

var _failures: Array[String] = []
var _state: Node
var _narrative: Node
var _save: Node
var _abilities: InnerAbilities
var _library: DialogueLibrary
var _seed: SeedProbe


func run(tree: SceneTree, state: Node, narrative: Node, save: Node) -> Array[String]:
	_state = state
	_narrative = narrative
	_save = save
	_abilities = InnerAbilities.load_all()
	_library = DialogueLibrary.load_all(_abilities)
	if not _abilities.is_valid() or not _library.is_valid():
		return ["The shipped content is invalid; legacy checks cannot be tested."]
	_library.set_locale("en")
	var world := Node.new()
	_seed = SeedProbe.new()
	_seed.name = "DialogueController"
	world.add_child(_seed)
	tree.root.add_child(world)
	_save.bind_world(world)
	for success: bool in [false, true]:
		_check_file_round_trip(success)
	_check_partial_and_unattributed_counts()
	_save.unbind_world()
	world.free()
	print("inner_voice_migration_cases: checked 38 cached branches, save/load, seed and passive accounting.")
	return _failures


func _old_snapshot(success: bool) -> Dictionary:
	var flags: Dictionary = {
		&"voice_count:orientation": 2,
		&"voice_count:whimsy": 1,
		&"voice:alley_notice_orientation": true,
		&"voice:playground_arrival_orientation": true,
		&"check:unrelated:fixture": {"ability": "orientation", "success": success},
		&"unrelated_value": {"orientation": [1, 2, 3]},
	}
	var expected: Dictionary = {}
	for graph: DialogueGraph in _library.get_graphs_for("en"):
		for conversation_id: StringName in graph.get_conversation_ids():
			var conversation := graph.get_conversation(conversation_id)
			for node_id: StringName in conversation.order:
				var node: DialogueGraph.DialogueNode = conversation.nodes[node_id]
				if node.check.is_empty():
					continue
				var ability: StringName = node.check["ability"]
				var die := 12 if success else 2
				var total := die + 2 - 1
				var difficulty := int(node.check["difficulty"])
				var retired := &"whimsy" if ability == &"imagination" else &"orientation"
				var record := {
					"ability": String(retired) if success else retired,
					"ability_value": 2, # Not today's 3; loading must not recalculate.
					"dice": [6, 6] if success else [1, 1],
					"die": die, "dice_count": 2, "die_faces": 6,
					"modifier": -1, "total": total, "difficulty": difficulty,
					"margin": total - difficulty, "success": success,
					"key": "%s/%s" % [conversation_id, node_id],
					"kind": node.check["kind"],
					"fixture_extension": {"kept": [17, &"tag"]},
				}
				var flag := StoryFlags.check_record_flag(conversation_id, node_id)
				flags[flag] = record
				var migrated: Dictionary = record.duplicate(true)
				migrated["ability"] = String(ability) if success else ability
				expected[flag] = migrated
	_expect(expected.size() == 19, "Legacy replay no longer covers all 19 shipped checks.")
	return {"flags": flags, "expected": expected}


func _check_file_round_trip(success: bool) -> void:
	_state.clear()
	_narrative.clear()
	var fixture := _old_snapshot(success)
	var flags: Dictionary = fixture["flags"]
	var before: Dictionary = flags.duplicate(true)
	var entries: Array = []
	for source: String in ["observed", "reported", "recalled", "imagined"]:
		entries.append({"entry_id": "fixture_" + source, "source": source,
			"speaker_id": "q" if source == "reported" else "protagonist", "text": "Fixture."})
	var payload := {"flags": SaveCodec.encode_flags(flags), "entries": entries, "check_seed": 7919}
	var written: Dictionary = _save.write_payload(payload)
	if not written.get("ok", false):
		_failures.append("Could not write the legacy voice fixture.")
		return
	var disk_before := FileAccess.get_file_as_bytes("user://save.json")
	var writes_before: int = _save.saves_written
	_seed.value = -1
	var loaded: Dictionary = _save.load_game()
	if not loaded.get("ok", false):
		_failures.append("The legacy voice fixture would not load: %s." % str(loaded))
		return
	_expect(_seed.value == 7919, "Voice migration changed the session seed.")
	_expect(_narrative.to_snapshot() == {"entries": entries}, "Voice migration changed knowledge sources or speakers.")
	_expect(flags == before, "Voice migration mutated its input dictionary.")
	_expect(FileAccess.get_file_as_bytes("user://save.json") == disk_before and _save.saves_written == writes_before,
		"Loading a legacy save rewrote the file instead of waiting for a checkpoint.")
	_expect(not _state.has_flag(StoryFlags.CURTAIN_EDGES_EXAMINED),
		"Loading an old check invented a preparation the player never chose.")
	var canonical: Dictionary = _state.get_snapshot()
	_expect(not canonical.has(&"voice_count:orientation") and not canonical.has(&"voice_count:whimsy"),
		"Retired aggregate counters survived migration.")
	for ability: StringName in [&"insight", &"inference", &"imagination"]:
		_expect(_state.get_flag(StoryFlags.passive_count_flag(ability), 0) == 1,
			"The evidenced old passive use was not assigned to %s." % ability)
	for ability: StringName in [&"scrutiny", &"echo", &"resonance"]:
		_expect(_state.get_flag(StoryFlags.passive_count_flag(ability), 0) == 0,
			"An old aggregate spent the allowance of %s, which never spoke." % ability)
	_expect(canonical.get(&"check:unrelated:fixture") == before[&"check:unrelated:fixture"]
		and canonical.get(&"unrelated_value") == before[&"unrelated_value"], "Migration guessed at an unrelated record.")
	_state.replace_snapshot(canonical)
	_expect(_state.get_snapshot() == canonical, "Voice migration is not idempotent.")

	# Preparation learned *after* an attempt, plus a new seed, still cannot buy a
	# new result. Test every real node through the real runtime, not only reuse().
	_seed.value = 12345
	for graph: DialogueGraph in _library.get_graphs_for("en"):
		for conversation_id: StringName in graph.get_conversation_ids():
			var conversation := graph.get_conversation(conversation_id)
			for node_id: StringName in conversation.order:
				var node: DialogueGraph.DialogueNode = conversation.nodes[node_id]
				if node.check.is_empty():
					continue
				_replay_node(graph, conversation, node, fixture["expected"], success)
	_seed.value = 7919
	var checkpoint: Dictionary = _state.get_snapshot()
	var checkpoint_knowledge: Dictionary = _narrative.to_snapshot()
	var saved: Dictionary = _save.save_game()
	_expect(saved.get("ok", false), "The migrated session could not be saved again.")
	_state.clear()
	_narrative.clear()
	_seed.value = -1
	var again: Dictionary = _save.load_game()
	_expect(again.get("ok", false) and _state.get_snapshot() == checkpoint
		and _narrative.to_snapshot() == checkpoint_knowledge and _seed.value == 7919,
		"The canonical six-voice save changed on its second load.")


func _replay_node(
	graph: DialogueGraph, conversation: DialogueGraph.Conversation,
	node: DialogueGraph.DialogueNode, expected: Dictionary, success: bool
) -> void:
	for modifier: Dictionary in node.check.get("modifiers", []):
		_state.set_flag(StringName(modifier["flag"]), true)
	var flag := StoryFlags.check_record_flag(conversation.conversation_id, node.node_id)
	var recorded: Dictionary = expected[flag]
	_expect(_state.get_flag(flag, {}) == recorded, "Migration rewrote more than the ability in %s." % flag)
	var runtime := DialogueRuntime.new(_state, _narrative, null, _abilities, CheckResolver.new(_seed.value))
	# Start at this node in the in-memory fixture only; no authored JSON or earlier
	# effects are replayed. Gameplay still starts at the authored start node.
	var first := conversation.start_id
	conversation.start_id = node.node_id
	var started := runtime.start(graph, conversation.conversation_id)
	conversation.start_id = first
	_expect(started, "Could not replay %s." % flag)
	var replayed := recorded.duplicate(true)
	replayed["reused"] = true
	_expect(runtime.get_last_check() == replayed, "A migrated %s was rerolled or recalculated." % flag)
	runtime.advance()
	var target: StringName = node.check["success" if success else "failure"]
	_expect((not runtime.is_active() if target == &"" else runtime.get_current_node_id() == target),
		"A migrated %s followed a different historical branch." % flag)


func _check_partial_and_unattributed_counts() -> void:
	var partial := {
		&"voice_count:orientation": 2, &"voice_count:insight": 2,
		&"voice_count:whimsy": 1, &"voice_count:imagination": 2,
		&"voice:alley_notice_orientation": true, &"voice:playground_hoop_orientation": true,
	}
	_state.replace_snapshot(partial)
	_expect(_state.get_flag(&"voice_count:insight") == 2 and _state.get_flag(&"voice_count:scrutiny") == 1
		and _state.get_flag(&"voice_count:imagination") == 2 and not _state.has_flag(&"voice_count:inference"),
		"A mixed snapshot double-counted a voice or charged one that never spoke.")
	var once: Dictionary = _state.get_snapshot()
	_state.replace_snapshot(once)
	_expect(_state.get_snapshot() == once, "A mixed snapshot gains passive uses on repeated loads.")
	_state.replace_snapshot({&"voice_count:orientation": 2})
	_expect(_state.get_snapshot().is_empty(), "An unattributable legacy aggregate was guessed into another voice's cap.")
	# A known retired check can prove a legacy run even if the old aggregate is
	# missing. Already-current results must not be reinterpreted as old runs.
	var evidence := {&"check:voice_hoop:vh_1": {"ability": "orientation", "success": false},
		&"voice:playground_hoop_orientation": true}
	_state.replace_snapshot(evidence)
	_expect(_state.get_flag(&"voice_count:scrutiny", 0) == 1
		and _state.get_flag(&"check:voice_hoop:vh_1").get("ability") == "scrutiny",
		"A failed historical passive was not attributed when only its old check survived.")
	var current := {&"check:voice_hoop:vh_1": {"ability": "scrutiny", "success": false},
		&"voice:playground_hoop_orientation": true}
	_state.replace_snapshot(current)
	_expect(_state.get_snapshot() == current, "A current snapshot was guessed to be a legacy run.")
	var malformed := {&"check:pg_ball:pb_boundary_check": {"ability": {"unknown": true}, "success": false},
		&"voice_count:whimsy": {"not_a_counter": 1}}
	_state.replace_snapshot(malformed)
	_expect(_state.get_flag(&"check:pg_ball:pb_boundary_check") == malformed[&"check:pg_ball:pb_boundary_check"],
		"A non-string ability was coerced into a migration target.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

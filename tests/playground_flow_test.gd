extends SceneTree
## Integration test for playground open exploration and state preservation.

const Harness = preload("res://tests/test_harness.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "playground_flow_test.gd")
	call_deferred("_run")

func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	var gs: Node = autoloads["game_state"]
	var ns: Node = autoloads["narrative_state"]
	if gs == null or ns == null:
		Harness.finish(self, ["State autoloads unavailable"], "")
		return
	Harness.clear_session_state(self)
	var rpg := Harness.ensure_autoload(self, "Rpg", "res://scripts/rpg/rpg_manager.gd")
	if rpg != null:
		# ensure abilities loaded
		if rpg.has_method("abilities_load"):
			rpg.abilities_load()

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn not loadable"], "")
		return
	var main: Node = packed.instantiate()
	var seq: OpeningSequence = main.get_node_or_null("OpeningSequence")
	if seq != null:
		seq.autostart = false
	root.add_child(main)
	await process_frame
	await process_frame
	var host: LocationHost = main.get_node_or_null("LocationHost")
	var player: PlayerController = main.get_node_or_null("Player")
	var dialogue: DialogueController = main.get_node_or_null("DialogueController")
	var interaction: InteractionController = player.get_node_or_null("InteractionController") if player else null
	var ui: GameUI = main.get_node_or_null("GameUI")
	if host == null or player == null or dialogue == null or interaction == null:
		Harness.finish(self, ["Main missing core nodes"], "")
		return

	# Load residential directly, simulate having reached it
	var pg_path := "res://scenes/locations/residential/residential.tscn"
	if not host.load_location(pg_path, &"PlayerStart", player):
		_failures.append("Could not load residential for playground test")
	else:
		gs.set_flag(StoryFlags.RESIDENTIAL_ARRIVED, true)
		gs.set_flag(StoryFlags.ANIMAL_SEEN, true)
		gs.set_flag(StoryFlags.CURRENT_LOCATION, &"residential")
		ns.record(&"animal_seen", NarrativeEntry.Source.OBSERVED, &"protagonist", "animal")

		var res_loc := host.get_current()
		var alley_exit := res_loc.find_interactable(&"res_alley_end") if res_loc else null
		if alley_exit == null:
			_failures.append("Residential missing res_alley_end exit to alley.")
		else:
			if alley_exit.destination_scene != "res://scenes/locations/alley/alley.tscn":
				_failures.append("res_alley_end should go to alley, got %s" % alley_exit.destination_scene)
			if alley_exit.is_milestone_end:
				_failures.append("res_alley_end should no longer be milestone_end (playground moved).")

			# Go to alley
			host.load_location(alley_exit.destination_scene, alley_exit.destination_spawn, player)
			gs.set_flag(StoryFlags.ALLEY_ARRIVED, true)
			gs.set_flag(StoryFlags.CURRENT_LOCATION, &"alley")
			var alley := host.get_current()
			if alley == null or String(alley.location_id) != "alley":
				_failures.append("Did not arrive in alley.")
			else:
				if alley.get_interactables().size() < 2:
					_failures.append("Alley should have at least 2 interactables.")
				var to_gate := alley.find_interactable(&"alley_to_gate")
				if to_gate == null:
					_failures.append("Alley missing alley_to_gate.")
				else:
					host.load_location(to_gate.destination_scene, to_gate.destination_spawn, player)
					gs.set_flag(StoryFlags.ESTATE_GATE_PASSED, true)
					gs.set_flag(StoryFlags.CURRENT_LOCATION, &"estate_gate")
					var gate := host.get_current()
					if gate == null or String(gate.location_id) != "estate_gate":
						_failures.append("Did not arrive in estate_gate.")
					else:
						var to_pg := gate.find_interactable(&"estate_to_playground")
						if to_pg == null:
							_failures.append("Estate gate missing estate_to_playground.")
						else:
							host.load_location(to_pg.destination_scene, to_pg.destination_spawn, player)
							gs.set_flag(StoryFlags.CURRENT_LOCATION, &"playground")
							var playground := host.get_current()
							if playground == null or String(playground.location_id) != "playground":
								_failures.append("Did not arrive in playground.")
							else:
								# Check 3 anchors exist
								for anchor in [&"playground_shed", &"playground_wall", &"playground_equipment"]:
									if playground.find_interactable(anchor) == null:
										_failures.append("Playground missing anchor %s" % anchor)
								# Free order: can visit shed then wall
								if playground.get_interactables().size() < 6:
									_failures.append("Playground should be open with >=6 interactables, got %d" % playground.get_interactables().size())
								# State preservation
								if not gs.get_flag(StoryFlags.ANIMAL_SEEN, false):
									_failures.append("State not preserved: ANIMAL_SEEN lost after playground transition.")
								if not ns.has_entry(&"animal_seen"):
									_failures.append("Knowledge not preserved after playground transition.")

								# Try active check via dialogue (playground_shed)
								var lib := dialogue.get_dialogue_library()
								if lib != null and lib.has_conversation(&"playground_shed"):
									var rt := dialogue.get_runtime()
									# inject deterministic engine
									var rng := RandomNumberGenerator.new()
									rng.seed = 1
									var eng := CheckEngine.new(rng, gs)
									rt.set_check_engine(eng)
									if not rt.start(lib.get_graph(&"playground_shed"), &"playground_shed"):
										_failures.append("Could not start playground_shed conversation.")
									else:
										# Drive conversation: pick first choice (active check)
										if rt.is_awaiting_choice():
											rt.choose(0)
										# Check should have set flag
										var success_flag: Variant = gs.get_flag(StoryFlags.check_success_flag(&"playground_shed_search"), null)
										if success_flag == null:
											_failures.append("Active check should set check_success flag.")
										# Second attempt should be blocked (anti-spam)
										var prev_roll: int = 0
										if rt.get_last_check() != null:
											prev_roll = rt.get_last_check().roll
										# Try again with same id, without allow_reroll - should return already_attempted
										var eng2 := CheckEngine.new(rng, gs)
										var r2 := eng2.roll(&"playground_shed_search", &"keen_eye", 2, 12, 0, true, false)
										if prev_roll != 0 and r2.roll != prev_roll:
											_failures.append("Anti-spam: second roll should reuse previous result, got %d vs %d" % [prev_roll, r2.roll])
								else:
									_failures.append("Dialogue library missing playground_shed conversation.")

								# Verify playground exit is milestone
								var exit := playground.find_interactable(&"playground_exit")
								if exit == null:
									_failures.append("Playground missing playground_exit milestone.")
								elif not exit.is_milestone_end:
									_failures.append("playground_exit should be milestone_end.")

								# Return path: back to gate should work (free traversal)
								var back := playground.find_interactable(&"playground_to_gate")
								if back == null:
									_failures.append("Playground missing back-to-gate exit.")
								else:
									host.load_location(back.destination_scene, back.destination_spawn, player)
									if String(host.get_current().location_id) != "estate_gate":
										_failures.append("Could not return from playground to estate_gate (free traversal broken).")

	main.queue_free()
	await process_frame
	Harness.finish(self, _failures, "playground open exploration, state preservation, and active checks work.")

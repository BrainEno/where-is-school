extends SceneTree
## A real edge in the street - the container's roof - a save taken while falling,
## and a legacy below-world save.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := preload("res://scenes/main/main.tscn")
const HOTSPOT := preload("res://scenes/interaction/interactable.tscn")
const STREET := "res://scenes/locations/street/street.tscn"
const HALL := "res://scenes/locations/corridor/corridor.tscn"

var _check := Harness.Checker.new()
var _world: Node
var _host: LocationHost
var _player: PlayerController
var _director: OpeningSequence
var _save: Node
var _state: Node
var _recoveries := 0
var _entries := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 65.0, "fall_recovery_test.gd")
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var boot := Harness.ensure_state_autoloads(self)
	_save = boot["save"]
	_state = boot["game_state"]
	Harness.clear_session_state(self)
	_state.set_flag(StoryFlags.CLASS_DISMISSED, true)
	_state.set_flag(StoryFlags.LEFT_CLASSROOM, true)
	_boot()
	# Let the initial classroom settle before replacing it with the street fixture.
	await process_frame
	if _load(STREET, &"FromCorridor", &"street") and await _ready_to_walk():
		await _street_edge()
		await _recover_on_foot()
		await _new_location_and_continue()
	Harness.clear_session_state(self)
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.wait_for_mix()
	await process_frame
	Harness.finish(self, _check.failures,
		"the south barrier holds; a live fall cancels its walk, keeps the room and uses a safe checkpoint; Continue leaves a legacy void position at the entry.")


func _boot() -> void:
	_world = MAIN.instantiate()
	_director = _world.get_node(^"OpeningSequence") as OpeningSequence
	_director.autostart = false
	_director.autosave_enabled = false
	root.add_child(_world)
	_world.get_node(^"InnerVoiceDirector").set_process(false)
	_host = _world.get_node(^"LocationHost") as LocationHost
	_player = _world.get_node(^"Player") as PlayerController
	_host.player_recovered.connect(func() -> void: _recoveries += 1)
	_host.location_entered.connect(func(_room: LocationRoot, _spawn: StringName) -> void: _entries += 1)
	_director.allow_player_control()
	(_world.get_node(^"GameUI") as GameUI).fade.set_clear()


func _load(path: String, spawn: StringName, id: StringName) -> bool:
	if not _check.expect(_host.load_location(path, spawn, _player, id), "Could not place the player in %s." % id):
		return false
	_state.set_flag(StoryFlags.CURRENT_LOCATION, id)
	return true


func _ready_to_walk() -> bool:
	var navigation := _host.get_current().get_node(^"Navigation") as LocationNavigation
	return _check.expect(await Harness.wait_until(func() -> bool:
		return navigation.is_routable() and _player.is_on_floor() and _player.is_control_enabled(), 6.0),
		"Could not stand on the live map (%s)." % Harness.stage)


func _street_edge() -> void:
	Harness.stage = "walking into the works barrier"
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 18.0)))
	await _ready_to_walk()
	# The real default camera maps back+left to +Z. Keep pushing after reaching the rail.
	Input.action_press(&"move_back")
	Input.action_press(&"move_left")
	await create_timer(1.2, false, true).timeout
	Input.action_release(&"move_back")
	Input.action_release(&"move_left")
	_check.expect(_player.is_on_floor() and _player.global_position.z > 19.15
		and _player.global_position.z < 19.62 and _recoveries == 0,
		"The south end did not stop the walking capsule at the barrier: %s." % _player.global_position)


func _recover_on_foot() -> void:
	Harness.stage = "the container roof's east edge"
	var street := _host.get_current()
	var before := _state.get_snapshot() as Dictionary
	var before_entries := _entries
	# Only the click target is a fixture: the edge, the fall, and the route use the
	# game collision, pointer and navigation. Round 34 walled the street's own deck
	# in (the school wall west, the back-lot block north, the shops east), so the
	# honest cliff left on the map is the container's roof: 2.6 m of free fall off
	# its east face, standing on the same walkable top the container-yard arrival
	# has used since round 30. A small target above the roof gives the falling
	# camera something genuinely pickable to ask to walk towards.
	var hotspot := HOTSPOT.instantiate() as Interactable
	hotspot.position = Vector3(16.3, 3.4, -32.0)
	hotspot.radius = 0.64
	hotspot.interact_id = &"recover_click_fixture"
	hotspot.inspection_id = &"street_gutter"
	street.get_node(^"Interactables").add_child(hotspot)
	var pointer := _player.get_node(^"PointerNavigator") as PointerNavigator
	var hud := (_world.get_node(^"GameUI") as GameUI).hud
	var rig := _player.camera_rig
	_player.teleport(Transform3D(Basis.IDENTITY, Vector3(15.5, 2.8, -32.0)))
	if not _check.expect(await Harness.wait_until(func() -> bool:
		return _host.get_safe_checkpoint().origin.y > 2.7, 2.0), "The last safe stance was not sampled."):
		return
	var stance_y := _host.get_safe_checkpoint().origin.y
	# No test hook takes the floor away. Walk off the actual edge: back+right is
	# the input pair that maps to pure east (the camera hangs to the south-east,
	# so its pairs walk the cardinal axes), out past the roof's east face.
	Input.action_press(&"move_back")
	Input.action_press(&"move_right")
	var dropped := await Harness.wait_until(func() -> bool: return _player.global_position.y < stance_y - 0.45, 4.0)
	Input.action_release(&"move_back")
	Input.action_release(&"move_right")
	if not _check.expect(dropped and not _player.is_on_floor(), "The roof-edge reproduction never fell."):
		return
	var safe_pose := _host.get_safe_checkpoint()
	var safe := safe_pose.origin
	var saved := _save.save_game() as Dictionary
	var read := _save.read_save() as Dictionary
	var payload: Dictionary = read.get("payload", {})
	var checkpoint: Dictionary = payload.get("world", {})
	var feet := OpeningSave.vec3(checkpoint.get("position"))
	_check.expect(saved.get("ok", false) and read.get("ok", false) and feet.is_equal_approx(safe),
		"A save taken mid-fall put Continue below the asphalt instead of on the last safe support.")
	var pixel := rig.camera.unproject_position(hotspot.global_position)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = pixel
		click.global_position = pixel
		Input.parse_input_event(click)
	var walking := await Harness.wait_until(func() -> bool:
		return pointer.get_pending_target() == hotspot and _player.is_path_active(), .45)
	var cue := _world.get_node_or_null(^"DestinationCue") as DestinationCue
	if not _check.expect(walking and cue != null and cue.is_shown() and cue.get_role() == "target",
		"The fall never held a pending click: %s at %s, pixel %s." % [pointer.get_last_rejection(), _player.global_position, pixel]):
		return
	# Simulate an old shot/label still releasing when the body drops out. Recovery
	# must cut back in the same frame, not wait for either presentation to finish.
	rig.focus_on(hotspot, CameraShot.new())
	await rig.frame_point(hotspot.global_position, 0.0)
	hud.set_prompt_text("Old street prompt")
	if not _check.expect(await Harness.wait_until(func() -> bool: return _recoveries == 1, 3.0),
		"The body kept falling without recovering."):
		return
	_check.expect(_host.get_current() == street and _entries == before_entries
		and _state.get_snapshot() == before, "Recovering replayed an arrival or changed story state.")
	_check.expect(not _player.is_path_active() and _player.is_control_enabled()
		and pointer.get_pending_target() == null and not pointer.is_approaching() and not cue.is_shown()
		and rig.get_frame_weight() == 0.0 and rig.get_focus_weight() == 0.0
		and rig.global_position.distance_to(_player.global_position) < .13
		and hud.get_prompt_text().is_empty(), "The old click, cue, prompt or shot survived the fall.")
	_check.expect(_player.get_facing_direction().is_equal_approx(-safe_pose.basis.z)
		and _player.velocity.length() < 1.0, "The fall kept its velocity or heading on recovery.")
	_check.expect(await _ready_to_walk() and _player.global_position.distance_to(safe) < .18,
		"Recovery did not put the body on its recent support: %s (expected %s)." % [_player.global_position, safe])
	var restored_feet := _player.global_position
	# Back and left maps to pure south: away from the west rim this fixture falls
	# off, and the one direction the z-walked assertion reads honestly.
	Input.action_press(&"move_back")
	Input.action_press(&"move_left")
	var walked := await Harness.wait_until(func() -> bool: return _player.global_position.z > restored_feet.z + .75, 2.0)
	Input.action_release(&"move_back")
	Input.action_release(&"move_left")
	_check.expect(walked and _recoveries == 1, "The player could not walk back after recovering.")
	print("fall test: live container-roof drop recovered near %s without reloading %s" % [safe, street.location_id])


func _new_location_and_continue() -> void:
	Harness.stage = "location-scoped anchor and legacy Continue"
	if not _load(HALL, &"FromTeachingEntrance", &"corridor"):
		return
	var room := _host.get_current()
	var local_entry := room.get_spawn(&"FromTeachingEntrance").global_position
	# No sample has run in this room. The previous street stance must already be gone.
	_check.expect(_host.get_safe_checkpoint().origin.is_equal_approx(local_entry), "The last room's anchor leaked across the swap.")
	if not await _ready_to_walk():
		return
	_check.expect(absf(_player.global_position.y + 3.4) < .07 and _recoveries == 1,
		"The legitimate 01 floor was mistaken for a fall.")
	var legacy := _save.capture() as Dictionary
	legacy["world"]["position"] = [62.0, -46.0, 73.0]
	if not _check.expect(_save.write_payload(legacy).get("ok", false), "Could not write the legacy-save fixture."):
		return
	_world.queue_free()
	await process_frame
	_state.clear()
	_boot()
	if not _check.expect(_host.get_current().location_id == &"corridor" and _host.get_current_spawn() == &"FromTeachingEntrance"
		and _player.global_position.distance_to(local_entry) < .02, "Continue placed a below-floor save instead of its current location's entry."):
		return
	await _ready_to_walk()
	_check.expect(_state.get_flag(StoryFlags.LEFT_CLASSROOM, false) and _recoveries == 1,
		"Continue lost the saved progress or needed a second fall to get back.")

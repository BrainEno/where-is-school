extends SceneTree
## Read the shipped choices in Main and check the real CameraRig, including the
## live 3D landmarks, rather than calling focus_on() in isolation.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"
const READ_LOG := "user://dialogue_closeups_read_log.json"

var _checks := Harness.Checker.new()
var _state: Node
var _main: PackedScene
var _world: Node
var _sequence: OpeningSequence
var _dialogue: DialogueController
var _panel: DialoguePanel
var _room: LocationRoot
var _rig: CameraRig
var _focus: CameraFocusDirector


func _initialize() -> void:
	Harness.arm_watchdog(self, 135.0, "dialogue_closeups_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_state = autoloads["game_state"]
	_main = load(MAIN) as PackedScene
	if not _checks.expect(_state != null and _main != null, "Could not boot Main and story state."):
		Harness.finish(self, _checks.failures, "")
		return
	root.size = Vector2i(1600, 900)
	ProjectSettings.set_setting(CharacterNameplate.SETTING, true)
	Engine.time_scale = 4.0
	for locale: String in ["zh-CN", "en"]:
		await _opening(locale, &"look_square")
		await _opening(locale, &"watch_q", locale == "en")
	await _again()
	await _release_world()
	Engine.time_scale = 1.0
	Harness.clear_session_state(self)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(READ_LOG))
	Harness.finish(self, _checks.failures, "Dialogue close-ups: both locales, held and "
		+ "fast-advanced lines, ordinary talk and the later ruler branch.")


func _boot(locale: String, after_bag: bool = false) -> bool:
	await _release_world()
	Harness.clear_session_state(self)
	if after_bag:
		# A post-search checkpoint. Do not run the bell timer while testing the Q route.
		for flag: StringName in [StoryFlags.MET_Q, StoryFlags.Q_FIRST_TALK_DONE,
				StoryFlags.TEXTBOOK_MISSING, &"saw_set_square"]:
			_state.set_flag(flag, true)
	L10n.set_locale(locale)
	_world = _main.instantiate()
	_sequence = _world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	_sequence.autosave_enabled = false
	root.add_child(_world)
	_dialogue = _world.get_node(^"DialogueController") as DialogueController
	_dialogue.apply_locale(locale)
	_dialogue.set_read_log(ReadLog.new(READ_LOG))
	_rig = _world.get_node(^"CameraRig") as CameraRig
	_panel = (_world.get_node(^"GameUI") as GameUI).dialogue_panel
	_room = (_world.get_node(^"LocationHost") as LocationHost).get_current()
	_focus = _sequence.get_camera_focus()
	if not _checks.expect(_room != null and _room.location_id == &"classroom" and _focus != null,
			"The production classroom and focus director are required."):
		return false
	if after_bag:
		var player := _world.get_node(^"Player") as PlayerController
		var interaction := player.get_node(^"InteractionController") as InteractionController
		interaction.request_activation(_room.find_interactable(&"q_talk"))
	else:
		_sequence.start()
	return true


func _release_world() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		await _world.tree_exited
		await process_frame # Leave the tree-exit notification before booting the next Main.
	_world = null


func _opening(locale: String, choice: StringName, fast: bool = false) -> void:
	Harness.stage = "%s q_wake/%s" % [locale, choice]
	if not await _boot(locale) or not await _seek(&"q_who_look"):
		return
	var subject := _room.find_interactable(&"q_talk" if choice == &"watch_q" else &"set_square")
	if not _checks.expect(_dialogue.get_runtime().get_active_conversation_id() == &"q_wake"
			and _focus.get_glance() == null and _rig.get_focus_weight() == 0.0,
			"The wake conversation was already focused before the choice.") or not _pick(choice):
		return
	if not _started(subject, &"p_why"):
		return
	var plate := _room.get_node(^"Actors/Q/Nameplate") as CharacterNameplate
	if choice == &"watch_q":
		_checks.expect(not plate.visible, "Q's debug nameplate covers the insert.")
	if not fast:
		if not await _check_framing(subject, choice):
			return
		var other := "en" if locale == "zh-CN" else "zh-CN"
		_checks.expect(_dialogue.apply_locale(other) and _focus.get_glance() == subject,
			"Republishing the same line in another language ended the close-up.")
	# On the fast leg this happens before any physics tick. A skipped line must not
	# leave a delayed insert, and must not wait for the camera before it can advance.
	_dialogue.advance_presentation()
	_checks.expect(_node() == &"q_zero" and _dialogue.is_busy() and _focus.get_glance() == null,
		"Advancing did not give the view back while dialogue continued.")
	if choice == &"watch_q":
		_checks.expect(plate.visible, "Q's nameplate did not restore when the glance ended.")
	await _check_home()


func _again() -> void:
	Harness.stage = "q_after_bag/square_again"
	if not await _boot("zh-CN", true) or not await _seek(&"q_ab_1"):
		return
	var talk := _room.find_interactable(&"q_talk")
	var wide := await Harness.wait_until(func() -> bool:
		return _rig.get_focus_subject() == talk and is_equal_approx(_rig.get_effective_fov(), talk.camera_shot.fov), 12.0)
	_checks.expect(wide and _focus.get_glance() == null and _rig.camera.global_position.distance_to(talk.global_position) > 2.0,
		"Ordinary activation of Q did not use the wide talk shot.")
	if not _pick(&"square") or not await _seek(&"q_sq_2") or not _pick(&"square_again"):
		return
	var square := _room.find_interactable(&"set_square")
	if not _started(square, &"q_sq_3") or not await _check_framing(square, &"square_again"):
		return
	_dialogue.advance_presentation()
	_checks.expect(not _dialogue.is_busy() and _focus.get_glance() == null,
		"The last q_after_bag line did not release its close-up.")
	await _check_home()


func _seek(node: StringName) -> bool:
	var arrived := await Harness.wait_until(func() -> bool:
		if _node() == node:
			return true
		if _dialogue.has_pending_choices():
			_dialogue.select_choice(0)
		elif _dialogue.is_busy():
			_dialogue.advance_presentation()
		return false, 35.0)
	return _checks.expect(arrived, "%s: could not reach %s (at %s)." % [Harness.stage, node, _node()])


func _node() -> StringName:
	return _dialogue.get_runtime().get_current_node_id()


func _pick(choice: StringName) -> bool:
	var index := _dialogue.get_runtime().get_available_choice_ids().find(choice)
	if not _checks.expect(index >= 0, "%s: the option %s is missing." % [Harness.stage, choice]):
		return false
	_dialogue.select_choice(index)
	return true


func _started(subject: Interactable, line: StringName) -> bool:
	return _checks.expect(subject != null and _node() == line and _focus.get_glance() == subject
		and _rig.get_focus_subject() == subject, "%s: the real option did not start its glance." % Harness.stage)


func _check_framing(subject: Interactable, choice: StringName) -> bool:
	var shot := subject.dialogue_shot
	if not _checks.expect(shot != null and not shot.insert_anchor_path.is_empty(), "%s has no insert." % choice):
		return false
	var settled := await Harness.wait_until(func() -> bool:
		return is_equal_approx(_rig.get_effective_fov(), shot.fov) and not _panel.is_revealing(), 12.0)
	if not _checks.expect(settled and _rig.camera == root.get_camera_3d() and _focus.get_glance() == subject,
			"The close-up did not settle on the original camera and held dialogue line."):
		return false
	var a: Vector3
	var b: Vector3
	if choice == &"watch_q":
		var actor := _room.find_actor(&"q")
		var skeleton := actor.get_character_animator().get_skeleton()
		var head := skeleton.find_bone(&"Head")
		var pose := skeleton.get_bone_global_pose(head) * skeleton.get_bone_global_rest(head).affine_inverse()
		# These are face landmarks on the real model, not the QTalk interaction anchor.
		a = skeleton.to_global(pose * skeleton.to_local(actor.get_visual().to_global(Vector3(-.033, 1.661, .1))))
		b = skeleton.to_global(pose * skeleton.to_local(actor.get_visual().to_global(Vector3(.033, 1.661, .1))))
	else:
		var ruler := _room.get_node(^"Props/SetSquare") as Node3D
		a = ruler.to_global(Vector3(.121, .014, .208)) # The splintered long edge.
		b = ruler.to_global(Vector3(.067, .032, .155)) # The overlapping tape on top.
	var sa := _rig.camera.unproject_position(a)
	var sb := _rig.camera.unproject_position(b)
	var safe := root.get_visible_rect().grow(-32.0)
	var paper := _panel.get_global_rect()
	var readable := not _rig.camera.is_position_behind(a) and not _rig.camera.is_position_behind(b) \
		and safe.has_point(sa) and safe.has_point(sb) and not paper.has_point(sa) and not paper.has_point(sb) \
		and sa.distance_to(sb) >= root.get_visible_rect().size.y * 0.09 \
		and _rig.camera.global_position.distance_to(a) < 0.9
	print("CLOSEUP: %s eye=%s basis=%s lens=%.3f landmarks=%s %s paper=%s" % [choice,
		_rig.camera.global_position, _rig.camera.global_basis, _rig.get_effective_fov(), sa, sb, paper])
	return _checks.expect(readable, "%s: close-up landmarks are too small, off screen or under the panel." % choice)


func _check_home() -> void:
	var home := await Harness.wait_until(func() -> bool:
		return _rig.get_focus_weight() == 0.0 and _rig.get_focus_subject() == null, 12.0)
	_checks.expect(home and is_equal_approx(_rig.get_effective_fov(), _rig.fov)
		and _rig.camera.position.is_equal_approx(_rig.offset), "The rig did not return to gameplay framing.")

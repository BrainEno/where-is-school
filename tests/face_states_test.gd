extends SceneTree
## #387: the face channels - one writer composing rest, directed state and blink; the
## eyeballs leading the head inside `NpcGaze`; and `CharacterFaceDirector` putting it
## together on a real conversation in the production classroom.
##
## Three claims, in order:
##
## 1. **Composition.** On the real protagonist and Q wrappers, `set_face_state()`
##    blends the shapes it names from the resting expression toward the state's target
##    and leaves every other shape alone; a blink written over it comes out on top and
##    does not erase the state; clearing settles exactly back to rest; a treatment
##    switch settles too; a look with no states (N, the seated student) honestly
##    refuses instead of borrowing another character's; and Q's tables never name the
##    two shapes `q_textbook_pose` owns (`Smile`, `Mouth_Open`).
## 2. **Eyeballs.** On Q's real skeleton, a watch turns the head about the vertical,
##    the eyes lead it (their own turn runs ahead of the head's applied turn), the
##    lead stays inside `eye_lead_degrees`, at full weight the eyes are centred again,
##    and letting go returns the eyeballs to exactly the pose the animation plays. The
##    protagonist's rig gets the same lead - his idle clips key the eye bones, so the
##    claim there is that the lead appears and then stops writing.
## 3. **The conversation.** Booted from `main.tscn` with the prologue's own beats off,
##    the real QTalk activation: friendly while Q speaks, listening while the
##    protagonist does, `attention` plus the insert gaze while the camera holds Q's
##    face insert on the `watch_q` choice, friendly again on the next line with the
##    glance gone and the gaze released, and at the natural end of the conversation
##    every face is back at rest with the camera on its gameplay framing.
##
## Waits are wall-clock (`Harness.wait_until`, deadline loops), never fixed frame
## counts: a headless run's frame rate is not the engine's, and a count would race it.

const Harness = preload("res://tests/test_harness.gd")
const MAIN := "res://scenes/main/main.tscn"

var _checks := Harness.Checker.new()
var _dialogue: DialogueController = null
var _sequence: OpeningSequence = null
var _rig: CameraRig = null
var _focus: CameraFocusDirector = null
var _room: LocationRoot = null
var _q_actor: NpcActor = null
var _q_visual: CharacterVisualAnimation = null
var _q_look: CharacterLookApplier = null
var _player: PlayerController = null
var _player_look: CharacterLookApplier = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 420.0, "face_states_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	await _check_composition()
	await _check_eyeballs()
	await _check_conversation()
	Harness.finish(self, _checks.failures,
		"face states compose in one writer, the eyes lead the head, and a real "
		+ "conversation enters and settles every state.")


# ---------------------------------------------------------------- composition


func _check_composition() -> void:
	Harness.stage = "composition"
	var protagonist := _load_wrapper("res://scenes/environment/characters/protagonist.tscn")
	var q := _load_wrapper("res://scenes/environment/characters/q.tscn")
	var student := _load_wrapper("res://scenes/environment/characters/classroom_student.tscn")
	var teacher := _load_wrapper("res://scenes/environment/characters/teacher_n.tscn")
	if protagonist == null or q == null or student == null or teacher == null:
		_checks.fail("A character wrapper scene could not be loaded.")
		return
	await _frames(4)
	var hero_look := protagonist.get_node(^"Look") as CharacterLookApplier
	var q_applier := q.get_node(^"Look") as CharacterLookApplier
	# Blinking off so the composition can be read without a lid landing mid-assertion;
	# the blink's own claim is made by driving the channel directly below.
	hero_look.blinking = false
	q_applier.blinking = false

	# Rest is what the look says, on the real wrapper.
	var rest: Dictionary = hero_look.get_composed_face()
	for shape in hero_look.look.expression:
		_checks.expect(is_equal_approx(float(rest.get(shape, -1.0)),
				float(hero_look.look.expression[shape])),
			"The protagonist's rest composition drifted from look.expression on %s." % shape)

	# The listening state applies at once and composes exactly its tabled weights,
	# leaving every shape it does not name at rest.
	_checks.expect(hero_look.set_face_state(&"listening", 0.0)
			and hero_look.get_face_state() == &"listening"
			and is_equal_approx(hero_look.get_face_state_weight(), 1.0),
		"The protagonist's listening state did not apply at once.")
	var listening: Dictionary = hero_look.get_composed_face()
	var table: Dictionary = hero_look.look.face_states["listening"]
	for shape in hero_look.look.expression:
		var expected: float = float(hero_look.look.expression[shape])
		if table.has(shape):
			expected = float(table[shape])
		_checks.expect(is_equal_approx(float(listening.get(shape, -1.0)), expected),
			"listening did not compose %s to its tabled weight." % shape)
	_checks.expect(is_equal_approx(_mesh_value(hero_look, "BrowRaise"), float(table["BrowRaise"])),
		"The listening state did not land on the mesh (%.3f)."
			% _mesh_value(hero_look, "BrowRaise"))

	# A blink written over the held state comes out on top and changes nothing else.
	hero_look._set_blink(1.0)
	var shut: Dictionary = hero_look.get_composed_face()
	for shape in hero_look.look.blink_shapes:
		_checks.expect(is_equal_approx(float(shut.get(shape, -1.0)), 1.0),
			"Blink did not take %s to 1 while a state was held." % shape)
	_checks.expect(is_equal_approx(_mesh_value(hero_look, "Blink_L"), 1.0),
		"The blink did not land on the mesh.")
	for shape in hero_look.look.expression:
		if hero_look.look.blink_shapes.has(shape):
			continue
		_checks.expect(is_equal_approx(float(shut.get(shape, -1.0)),
				float(listening.get(shape, -1.0))),
			"Blink erased the held state on %s." % shape)
	hero_look._set_blink(0.0)

	# Clearing settles exactly back to rest - on the mesh, not only in the
	# composition (a settle that forgets to write strands the face mid-state), and
	# an unknown state is refused.
	hero_look.clear_face_state(0.0)
	var settled: Dictionary = hero_look.get_composed_face()
	for shape in hero_look.look.expression:
		_checks.expect(is_equal_approx(float(settled.get(shape, -1.0)),
				float(hero_look.look.expression[shape])),
			"Clearing did not return %s to rest." % shape)
	_checks.expect(is_equal_approx(_mesh_value(hero_look, "BrowRaise"), 0.0),
		"Clearing left BrowRaise at %.3f on the mesh." % _mesh_value(hero_look, "BrowRaise"))
	_checks.expect(not hero_look.set_face_state(&"no_such_state", 0.0),
		"An unknown face state was accepted.")

	# A slow blend is part-rest, part-target after one process step.
	hero_look.set_face_state(&"listening", 4.0)
	hero_look._process(1.0)
	var part: Dictionary = hero_look.get_composed_face()
	var brow_target := float(table["BrowRaise"])
	_checks.expect(float(part.get("BrowRaise", -1.0)) > 0.0
			and float(part.get("BrowRaise", -1.0)) < brow_target,
		"A slow blend is not between rest and target on BrowRaise.")

	# A treatment switch settles the directed layer: a rebind cannot inherit a face.
	hero_look.apply_treatment(CharacterLookApplier.Treatment.PAINTED)
	_checks.expect(is_equal_approx(hero_look.get_face_state_weight(), 0.0)
			and hero_look.get_face_state() == &"",
		"A treatment switch kept the directed face state.")

	# Q: the three states exist, and none of them names the two shapes the textbook
	# pose owns while a book is up (two writers on one shape is the bug to avoid).
	var states: Dictionary = q_applier.look.face_states
	for state: String in ["listening", "attention", "friendly"]:
		_checks.expect(states.has(state), "Q has no '%s' face state." % state)
	for state in states:
		var shapes: Dictionary = states[state]
		_checks.expect(not shapes.has("Smile") and not shapes.has("Mouth_Open"),
			"Q's '%s' state claims a shape the textbook pose owns." % state)
	_checks.expect(q_applier.set_face_state(&"friendly", 0.0),
		"Q's friendly state did not apply.")
	var q_face: Dictionary = q_applier.get_composed_face()
	_checks.expect(is_equal_approx(float(q_face.get("Smile", 0.0)), 0.0),
		"Q's friendly state moved Smile.")
	q_applier.clear_face_state(0.0)

	# Characters without face morphs refuse the state instead of borrowing one.
	_check_no_states(student, &"listening", "the seated student")
	_check_no_states(teacher, &"listening", "N")

	protagonist.queue_free()
	q.queue_free()
	student.queue_free()
	teacher.queue_free()
	await _frames(2)
	Harness.stage = ""


## The value the mesh actually holds for `shape` (the first surface that has it),
## or -1 when no mesh carries the shape.
func _mesh_value(applier: CharacterLookApplier, shape: String) -> float:
	var model := applier.get_model()
	if model == null:
		return -1.0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var index := mesh_instance.find_blend_shape_by_name(StringName(shape))
		if index >= 0:
			return mesh_instance.get_blend_shape_value(index)
	return -1.0


func _check_no_states(wrapper: Node, state: StringName, label: String) -> void:
	var applier := wrapper.get_node(^"Look") as CharacterLookApplier
	_checks.expect(applier.look != null and applier.look.face_states.is_empty(),
		"%s was given face states it does not have morphs for." % label)
	_checks.expect(not applier.set_face_state(state, 0.0),
		"%s accepted a face state it cannot show." % label)


func _load_wrapper(path: String) -> Node:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var instance := packed.instantiate()
	root.add_child(instance)
	return instance


# ------------------------------------------------------------------ eyeballs


func _check_eyeballs() -> void:
	Harness.stage = "eyeballs"
	await _check_one_gaze("res://scenes/environment/characters/q.tscn", true)
	await _check_one_gaze("res://scenes/environment/characters/protagonist.tscn", false)
	Harness.stage = ""


## One gaze rig on one real wrapper: a target 90 degrees to the left, sampled for the
## lead, the clamp, the centring at full weight, and the return.
func _check_one_gaze(path: String, exact_return: bool) -> void:
	var packed := load(path) as PackedScene
	if not _checks.expect(packed != null, "%s did not load." % path):
		return
	var actor := Node3D.new()
	actor.name = "GazeActor"
	root.add_child(actor)
	var visual := packed.instantiate()
	actor.add_child(visual)
	await _frames(4)
	var animator := visual as CharacterVisualAnimation
	var skeleton := animator.get_skeleton()
	if not _checks.expect(skeleton != null, "%s has no skeleton." % path):
		actor.queue_free()
		await _frames(2)
		return
	var eye := skeleton.find_bone(&"Eye_L")
	if not _checks.expect(eye >= 0, "%s has no Eye_L bone." % path):
		actor.queue_free()
		await _frames(2)
		return
	var local_before := skeleton.get_bone_pose_rotation(eye)
	var target := Marker3D.new()
	target.position = Vector3(-3.0, 1.5, 0.0)
	root.add_child(target)
	var gaze := NpcGaze.new()
	gaze.name = "Gaze"
	gaze.setup(actor)
	skeleton.add_child(gaze)
	gaze.look_at_node(target, 1.5)

	var deadline := Time.get_ticks_msec() + 8000
	var max_lead := 0.0
	var max_eye_written := 0.0
	var saw_head_turn := 0.0
	var centred := false
	while Time.get_ticks_msec() < deadline:
		max_lead = maxf(max_lead, gaze.get_eye_yaw_degrees() - gaze.get_applied_yaw_degrees())
		max_eye_written = maxf(max_eye_written, absf(gaze.get_applied_eye_degrees()))
		saw_head_turn = maxf(saw_head_turn, absf(gaze.get_measured_head_turn_degrees()))
		if gaze.get_weight() >= 0.99 and is_equal_approx(gaze.get_applied_eye_degrees(), 0.0):
			centred = true
			break
		await process_frame
	_checks.expect(max_eye_written > 0.5,
		"%s: the eyeballs never took a lead." % path)
	_checks.expect(max_eye_written <= gaze.eye_lead_degrees + 0.01,
		"%s: the eye lead broke its clamp (%.2f deg)." % [path, max_eye_written])
	_checks.expect(max_lead > 0.5,
		"%s: the eyes never ran ahead of the head's applied turn." % path)
	_checks.expect(saw_head_turn > 1.0,
		"%s: the head never turned." % path)
	_checks.expect(centred,
		"%s: the eyes were not centred at full weight." % path)

	gaze.let_go()
	var returned := false
	deadline = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if gaze.get_weight() <= 0.001 and is_equal_approx(gaze.get_applied_eye_degrees(), 0.0):
			returned = true
			break
		await process_frame
	_checks.expect(returned, "%s: the gaze did not let go." % path)
	if exact_return:
		# Q's clips do not key the eyeballs, so a released gaze must leave exactly the
		# pose the animation plays - proof nothing was stranded in the bone.
		var local_after := skeleton.get_bone_pose_rotation(eye)
		_checks.expect(rad_to_deg(local_before.angle_to(local_after)) < 0.1,
			"%s: a released gaze stranded the eyeball off its animated pose." % path)
	_checks.expect("Eye_L" in gaze.get_bone_names() and "Head" in gaze.get_bone_names(),
		"%s: the gaze does not report the bones it moves." % path)
	gaze.free()
	target.queue_free()
	actor.queue_free()
	await _frames(2)


# ------------------------------------------------------------- conversation


func _check_conversation() -> void:
	Harness.stage = "conversation"
	var packed := load(MAIN) as PackedScene
	if not _checks.expect(packed != null, "main.tscn did not load."):
		return
	var world := packed.instantiate()
	_sequence = world.get_node(^"OpeningSequence") as OpeningSequence
	_sequence.autostart = false
	_sequence.autosave_enabled = false
	root.add_child(world)
	await _frames(4)
	_dialogue = world.get_node(^"DialogueController") as DialogueController
	_rig = world.get_node(^"CameraRig") as CameraRig
	_focus = _sequence.get_camera_focus()
	_room = (world.get_node(^"LocationHost") as LocationHost).get_current()
	_player = world.get_node(^"Player") as PlayerController
	if not _checks.expect(_dialogue != null and _focus != null and _room != null
			and _room.location_id == &"classroom", "The production classroom is required."):
		return
	_q_actor = _room.find_actor(&"q")
	if not _checks.expect(_q_actor != null, "Q is not in the classroom."):
		return
	_q_visual = _q_actor.get_character_animator()
	_q_look = _q_visual.get_node(^"Look") as CharacterLookApplier
	_player_look = _player.get_character_animator().get_node(^"Look") as CharacterLookApplier

	# Activation through the same dispatcher a click uses: route "q" with no flags is
	# the wake conversation, framed by Q's wide talk shot.
	var interaction := _player.get_node(^"InteractionController") as InteractionController
	interaction.request_activation(_room.find_interactable(&"q_talk"))
	if not await _arrive(&"q_1", &"", 20.0):
		_checks.fail("The QTalk activation did not start q_wake at q_1.")
		return
	# Q speaks: his face goes friendly, the protagonist's listening.
	if not await _hold_state(_q_look, &"friendly", 10.0):
		_checks.fail("Q did not take the friendly state on his own line.")
	if not await _hold_state(_player_look, &"listening", 10.0):
		_checks.fail("The protagonist did not listen on Q's line.")
	if not await _arrive(&"p_who", &"", 20.0):
		_checks.fail("q_1 did not advance to p_who.")
	# The protagonist speaks: the states swap.
	if not await _hold_state(_q_look, &"listening", 10.0):
		_checks.fail("Q did not take the listening state on the protagonist's line.")
	if not await _hold_state(_player_look, &"friendly", 10.0):
		_checks.fail("The protagonist did not take the friendly state on his own line.")
	# Walk the trunk to the choice the insert hangs on (who -> the ruler beat).
	if not await _arrive(&"q_3", &"", 20.0) \
			or not await _arrive(&"q_who_1", &"who", 20.0) \
			or not await _arrive(&"q_who_2", &"", 20.0) \
			or not await _arrive(&"q_who_look", &"", 20.0):
		_checks.fail("The conversation did not reach q_who_look.")
		return
	# The watch_q choice: the camera takes Q's face insert and the director engages
	# the close-up state and gaze on him.
	if not await _arrive(&"p_why", &"watch_q", 25.0):
		_checks.fail("watch_q did not start the insert on p_why.")
		return
	if not await _hold_state(_q_look, &"attention", 10.0):
		_checks.fail("Q did not take the attention state inside his own insert.")
	_checks.expect(_focus.get_glance() == _room.find_interactable(&"q_talk"),
		"The insert glance is not held on QTalk.")
	var gaze := _q_actor.get_gaze()
	_checks.expect(gaze != null and _q_actor.is_watching() and gaze.get_weight() > 0.5,
		"Q's insert gaze did not engage.")
	if gaze != null:
		_checks.expect(absf(gaze.get_applied_eye_degrees()) <= gaze.eye_lead_degrees + 0.01,
			"The eye lead broke its clamp during the insert.")
	# The next line gives the glance back: the face returns to its line state, the
	# gaze lets go, the camera returns to the talk shot.
	if not await _arrive(&"q_zero", &"", 25.0):
		_checks.fail("The insert line did not advance to q_zero.")
		return
	_checks.expect(_focus.get_glance() == null, "The glance outlived its line.")
	if not await _hold_state(_q_look, &"friendly", 10.0):
		_checks.fail("Q did not return to his line state after the insert.")
	var released := await Harness.wait_until(func() -> bool:
		return not _q_actor.is_watching() and gaze != null and gaze.get_weight() <= 0.001, 8.0)
	_checks.expect(released, "Q's insert gaze did not let go after the insert.")

	# Walk the conversation to its natural end (silent -> the memorising beat) and
	# check that everything settles: faces at rest, gaze released, camera home.
	for step: Array in [[&"p_zero", &""], [&"p_none", &"none"], [&"q_none_1", &""],
			[&"q_exam_end", &""], [&"p_topic_what", &""], [&"q_topic_ask", &""],
			[&"p_topic_silent", &"silent"], [&"q_topic_silent", &""], [&"q_end_2", &""],
			[&"q_end_grin", &""]]:
		if not await _arrive(step[0], step[1], 25.0):
			_checks.fail("The conversation did not reach %s." % String(step[0]))
			return
	# On q_end_grin the textbook pose's own `Smile` plays through: the directed
	# states never took the shape it owns.
	_checks.expect(await Harness.wait_until(_grin_visible, 6.0),
		"The authored grin on q_end_grin did not play through the face channels.")
	if not await Harness.wait_until(func() -> bool:
			return not _dialogue.is_busy(), 15.0):
		_checks.fail("q_end_grin did not end the conversation.")
		return
	await _frames(30)
	_checks.expect(_q_look.get_face_state_weight() == 0.0
			and _player_look.get_face_state_weight() == 0.0,
		"A face state survived the end of the conversation.")
	var q_rest: Dictionary = _q_look.get_composed_face()
	for shape in _q_look.look.expression:
		_checks.expect(is_equal_approx(float(q_rest.get(shape, -1.0)),
				float(_q_look.look.expression[shape])),
			"Q's %s did not settle to rest." % shape)
	_checks.expect(_rig.get_focus_weight() == 0.0 and _rig.get_focus_subject() == null,
		"The camera did not return to its gameplay framing.")
	if gaze != null:
		_checks.expect(gaze.get_weight() <= 0.001 and not _q_actor.is_watching(),
			"Q's gaze survived the end of the conversation.")
	world.queue_free()
	await _frames(2)
	Harness.stage = ""


func _grin_visible() -> bool:
	if _q_visual == null:
		return false
	var head := _q_visual.get_node("Model").find_child("Q_Head", true, false) as MeshInstance3D
	if head == null:
		return false
	var smile := head.find_blend_shape_by_name(&"Smile")
	return smile >= 0 and head.get_blend_shape_value(smile) > 0.2


## Waits until the runtime sits on `node_id`, picking `choice` when the wait finds the
## conversation asking for one (the same advance loop `dialogue_closeups_test` uses).
func _arrive(node_id: StringName, choice: StringName, limit_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _dialogue.get_runtime().get_current_node_id() == node_id and _dialogue.is_busy():
			return true
		if _dialogue.has_pending_choices():
			if choice.is_empty():
				return false
			var index := _dialogue.get_runtime().get_available_choice_ids().find(choice)
			if index < 0:
				return false
			_dialogue.select_choice(index)
		elif _dialogue.is_busy():
			_dialogue.advance_presentation()
		await process_frame
	return _dialogue.get_runtime().get_current_node_id() == node_id and _dialogue.is_busy()


## Waits until `applier` holds `state` at full blend.
func _hold_state(applier: CharacterLookApplier, state: StringName, limit_seconds: float) -> bool:
	return await Harness.wait_until(func() -> bool:
		return applier.get_face_state() == state and applier.get_face_state_weight() >= 0.99,
		limit_seconds)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame

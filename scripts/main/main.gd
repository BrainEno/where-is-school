extends Node3D
## Composes the location, player, interaction, dialogue, UI, and short transitions.
## The scene controller records objective events; DialogueRunner records accounts,
## choices, recollections, and imagination, never objective world mutations.

const CLASSROOM: PackedScene = preload("res://scenes/locations/classroom.tscn")
const CORRIDOR: PackedScene = preload("res://scenes/locations/corridor.tscn")

enum Phase { WAKING, OPENING, SEARCH_BAG, LOOK_AROUND, ARRIVAL, RELEASED, ENDING }

@export_range(0.1, 8.0, 0.1) var wake_duration: float = 2.2
@onready var player: PlayerController = $Player
@onready var location_root: Node3D = $LocationRoot
@onready var dialogue_runner: DialogueRunner = $DialogueRunner
@onready var interaction: InteractionController = $InteractionController
@onready var hud: PrologueHUD = $PrologueHUD
@onready var room_tone: AudioStreamPlayer = $RoomTone
@onready var bell: AudioStreamPlayer = $Bell

var phase: Phase = Phase.WAKING
var current_location: Node3D
var location_id: StringName = &"classroom"
var transitioning: bool = false


func _ready() -> void:
	current_location = $LocationRoot/Classroom
	_connect_classroom(current_location as ClassroomLocation)
	hud.bind_dialogue(dialogue_runner)
	hud.advance_requested.connect(dialogue_runner.advance)
	hud.choice_requested.connect(dialogue_runner.choose)
	hud.history_visibility_changed.connect(_on_history_visibility_changed)
	hud.wait_requested.connect(_on_wait_requested)
	hud.resume_requested.connect(_on_resume_requested)
	hud.restart_requested.connect(_on_restart_requested)
	dialogue_runner.conversation_started.connect(_on_dialogue_started)
	dialogue_runner.conversation_finished.connect(_on_dialogue_finished)
	interaction.focus_changed.connect(hud.set_prompt)
	interaction.interaction_requested.connect(_on_interaction)
	# Dummy audio is unnecessary in headless tests and can outlive an immediate quit.
	if DisplayServer.get_name() != "headless":
		room_tone.finished.connect(room_tone.play)
		room_tone.play()
	player.set_seated(true)
	_set_objective("BIOLOGY CLASS", "A voice is close by.")
	hud.play_wake_fade(wake_duration)
	_refresh_control()
	_begin_wake()


func _begin_wake() -> void:
	await get_tree().create_timer(wake_duration).timeout
	if not is_inside_tree():
		return
	GameState.record_observation(&"woke_in_classroom")
	phase = Phase.OPENING
	_set_objective("BIOLOGY CLASS", "Listen to Q.")
	dialogue_runner.start(&"opening")


func _connect_classroom(classroom: ClassroomLocation) -> void:
	if classroom == null:
		push_error("Main expected a ClassroomLocation scene.")
		return
	classroom.exit_requested.connect(_on_classroom_exit_requested)


func _on_dialogue_started(_id: StringName) -> void:
	_refresh_control()


func _on_dialogue_finished(id: StringName) -> void:
	match id:
		&"opening":
			phase = Phase.SEARCH_BAG
			player.set_seated(false)
			_set_objective("BIOLOGY CLASS", "Check your schoolbag.")
		&"bag_first":
			phase = Phase.LOOK_AROUND
			_set_objective("BIOLOGY CLASS", "Look around, then press SPACE to wait for class.")
		&"lesson":
			GameState.record_observation(&"b_not_at_this_lesson")
			GameState.record_observation(&"free_activity_granted")
			phase = Phase.RELEASED
			var classroom: ClassroomLocation = current_location as ClassroomLocation
			if classroom:
				classroom.unlock_exit()
			player.reset_camera()
			_set_objective("BIOLOGY CLASS", "Leave through the classroom door.")
		&"threshold":
			phase = Phase.ENDING
			hud.show_ending()
	_refresh_control()


func _on_interaction(target: Interactable) -> void:
	if target == null or transitioning or dialogue_runner.active:
		return
	match target.interaction_id:
		&"schoolbag":
			if not GameState.get_flag(&"observed.biology_textbook_missing", false):
				GameState.record_observation(&"schoolbag_checked")
				GameState.record_observation(&"biology_textbook_missing")
				dialogue_runner.start(&"bag_first")
			else:
				dialogue_runner.start(&"bag_again")
		&"set_square":
			if not GameState.get_flag(&"observed.set_square_examined", false):
				GameState.record_observation(&"set_square_examined")
				dialogue_runner.start(&"square")
			else:
				dialogue_runner.start(&"square_again")
		&"board":
			GameState.record_observation(&"blackboard_examined")
			dialogue_runner.start(&"board")
		&"window":
			GameState.record_observation(&"window_examined")
			dialogue_runner.start(&"window")
		&"clock":
			GameState.record_observation(&"clock_examined")
			dialogue_runner.start(&"clock_after" if phase == Phase.RELEASED else &"clock")
		&"q":
			dialogue_runner.start(&"q_revisit" if GameState.get_flag(&"observed.biology_textbook_missing", false) else &"q_before_bag")
		&"n":
			dialogue_runner.start(&"n_after")
		&"classroom_exit":
			if GameState.get_flag(&"observed.free_activity_granted", false):
				_switch_location(&"corridor")
			else:
				dialogue_runner.start(&"door_before")
		&"return_classroom":
			_switch_location(&"classroom")
		&"school_threshold":
			GameState.record_observation(&"school_exit_reached")
			dialogue_runner.start(&"threshold")
		_:
			push_error("Unknown interaction '%s' at %s." % [target.interaction_id, target.get_path()])


func _on_wait_requested() -> void:
	if phase != Phase.LOOK_AROUND or transitioning or dialogue_runner.active or hud.backlog.visible:
		return
	var classroom: ClassroomLocation = current_location as ClassroomLocation
	if classroom == null:
		push_error("Cannot stage N's entrance outside the classroom.")
		return
	if not classroom.entrance_is_clear(player.global_position):
		_set_objective("BIOLOGY CLASS", "Step back from the doorway and front desk, then press SPACE.")
		return
	phase = Phase.ARRIVAL
	_refresh_control()
	_set_objective("BIOLOGY CLASS", "The lesson is starting.")
	GameState.record_observation(&"lesson_bell_heard")
	if DisplayServer.get_name() != "headless":
		bell.play()
	player.focus_camera_on(Vector3(1.6, 0.0, -3.5))
	await get_tree().create_timer(0.7).timeout
	await classroom.present_substitute()
	if not is_inside_tree():
		return
	GameState.record_observation(&"n_entered_classroom")
	dialogue_runner.start(&"lesson")


func _on_classroom_exit_requested() -> void:
	if phase == Phase.RELEASED and not transitioning and not dialogue_runner.active:
		_switch_location(&"corridor")


func _switch_location(destination: StringName) -> void:
	if transitioning:
		return
	transitioning = true
	_refresh_control()
	await hud.fade_to_black()
	location_root.remove_child(current_location)
	current_location.queue_free()
	if destination == &"corridor":
		current_location = CORRIDOR.instantiate()
		location_id = &"corridor"
		location_root.add_child(current_location)
		player.global_position = Vector3(0.0, 0.0, 3.9)
		GameState.record_observation(&"entered_corridor")
		_set_objective("SCHOOL CORRIDOR", "Follow the corridor to the school exit.")
	elif destination == &"classroom":
		current_location = CLASSROOM.instantiate()
		location_id = &"classroom"
		location_root.add_child(current_location)
		_connect_classroom(current_location as ClassroomLocation)
		player.global_position = Vector3(4.4, 0.0, -3.4)
		_set_objective("BIOLOGY CLASS", "Leave through the classroom door.")
	else:
		push_error("Unknown location '%s'." % destination)
		transitioning = false
		return
	player.velocity = Vector3.ZERO
	player.snap_camera_home()
	await hud.fade_from_black()
	transitioning = false
	_refresh_control()


func _on_history_visibility_changed(_opened: bool) -> void:
	_refresh_control()


func _on_resume_requested() -> void:
	phase = Phase.RELEASED
	_refresh_control()


func _on_restart_requested() -> void:
	GameState.clear()
	get_tree().reload_current_scene()


func _set_objective(location: String, objective: String) -> void:
	hud.set_objective(location, objective)


func _refresh_control() -> void:
	var roaming_phase: bool = phase in [Phase.SEARCH_BAG, Phase.LOOK_AROUND, Phase.RELEASED]
	var can_roam: bool = roaming_phase and not transitioning and not dialogue_runner.active and not hud.backlog.visible and not hud.ending.visible
	player.set_control_enabled(can_roam)
	interaction.enabled = can_roam
	hud.set_wait_available(can_roam and phase == Phase.LOOK_AROUND)


func _exit_tree() -> void:
	room_tone.stop()
	bell.stop()

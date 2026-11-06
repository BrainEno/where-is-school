class_name PrologueDirector
extends Node
## Scene-level conductor for the prologue slice.
##
## Ownership boundaries (see docs/PROLOGUE_ARCHITECTURE.md):
## - PrologueDirector decides *when* story beats run and *which* location is live.
## - PrologueFlow (a child of the main scene) owns dialogue + narrative state.
## - Locations own geometry, props, and their own spawn/exit markers.
## - Dialogue content and inspection content live in data/dialogue/.
##
## The director never writes story flags itself except for the spatial ones it
## owns (which room the player is in), and it never draws dialogue.

signal location_ready(location_id: StringName)
signal wake_beat_finished
signal exit_threshold_reached
## Emitted once, when the lesson bell sounds at the Beat F transition.
signal bell_rung

const CLASSROOM_SCENE := "res://scenes/locations/classroom/classroom.tscn"
const CORRIDOR_SCENE := "res://scenes/locations/corridor/corridor.tscn"
const STREET_SCENE := "res://scenes/locations/street/street_threshold.tscn"

## How long the black-to-room wake beat holds before control returns.
@export_range(0.2, 6.0, 0.1) var wake_duration: float = 2.2
## How long the player stands before Q starts talking on his own.
@export_range(0.0, 10.0, 0.1) var q_delay: float = 2.4

var current_location: Node3D = null
var current_location_id: StringName = &""

var _location_container: Node3D
var _player: PlayerController
var _flow: Node
var _loading: bool = false


func setup(location_container: Node3D, player: PlayerController, flow: Node) -> void:
	_location_container = location_container
	_player = player
	_flow = flow


## Loads the opening classroom and runs Beat A.
func start_prologue() -> void:
	await load_location(&"classroom")
	if current_location == null:
		push_error("PrologueDirector could not load the classroom.")
		return
	await _run_wake_beat()


func _run_wake_beat() -> void:
	_player.set_input_enabled(false)
	StoryFlags.set_flag(PrologueFlags.CORRIDOR_ENTERED, false)
	await get_tree().create_timer(wake_duration).timeout
	if not is_inside_tree():
		return
	StoryFlags.set_flag(PrologueFlags.AWAKENED, true)
	_player.set_input_enabled(true)
	StoryFlags.set_flag(PrologueFlags.CONTROL_RETURNED, true)
	wake_beat_finished.emit()
	await get_tree().create_timer(q_delay).timeout
	if not is_inside_tree() or _flow == null:
		return
	if not StoryFlags.has_flag(PrologueFlags.Q_INTRO_SEEN):
		_flow.call("begin_q_conversation")


func load_location(location_id: StringName) -> void:
	if _loading:
		push_warning("PrologueDirector ignored a location load while another load was in progress.")
		return
	_loading = true
	_player.set_input_enabled(false)
	var path: String = _scene_path_for(location_id)
	if path.is_empty():
		push_error("PrologueDirector has no scene for location '%s'." % location_id)
		_loading = false
		return
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("PrologueDirector failed to load '%s' for location '%s'." % [path, location_id])
		_loading = false
		return

	if current_location != null:
		current_location.queue_free()
		current_location = null

	var instanced: Node3D = packed.instantiate() as Node3D
	if instanced == null:
		push_error("PrologueDirector loaded a non-Node3D location scene: %s" % path)
		_loading = false
		return
	_location_container.add_child(instanced)
	current_location = instanced
	current_location_id = location_id

	_connect_location_signals(instanced)
	_place_player_at_spawn(instanced, location_id)
	_player.set_input_enabled(true)
	_loading = false
	location_ready.emit(location_id)


func _connect_location_signals(location: Node3D) -> void:
	if location.has_signal("transition_requested"):
		if not location.is_connected("transition_requested", Callable(self, "_on_transition_requested")):
			location.connect("transition_requested", Callable(self, "_on_transition_requested"))
	if location.has_signal("threshold_reached"):
		if not location.is_connected("threshold_reached", Callable(self, "_on_threshold_reached")):
			location.connect("threshold_reached", Callable(self, "_on_threshold_reached"))


func _on_transition_requested(target_location: StringName) -> void:
	await load_location(target_location)


## PrologueFlow calls this when the bell beat starts, so that staging and audio
## stay in one place instead of the flow reaching into audio nodes.
func ring_bell() -> void:
	bell_rung.emit()


func _on_threshold_reached(threshold_id: StringName) -> void:
	if threshold_id == &"school_exit":
		StoryFlags.set_flag(PrologueFlags.EXIT_REACHED, true)
		exit_threshold_reached.emit()


func _place_player_at_spawn(location: Node3D, location_id: StringName) -> void:
	var spawn: Node3D = null
	var preferred: StringName = _preferred_spawn(location_id)
	if preferred != &"":
		spawn = location.get_node_or_null(NodePath("SpawnPoints/" + String(preferred))) as Node3D
	if spawn == null:
		var spawn_points: Node = location.get_node_or_null("SpawnPoints")
		if spawn_points != null:
			for child: Node in spawn_points.get_children():
				if child is Node3D:
					spawn = child as Node3D
					break
	if spawn == null:
		push_warning("Location '%s' has no spawn point; keeping the player where they are." % location_id)
		return
	_player.teleport_to(spawn.global_transform)


func _preferred_spawn(location_id: StringName) -> StringName:
	match location_id:
		&"classroom":
			return &"Desk"
		&"corridor":
			return &"FromClassroom"
		&"street":
			return &"FromGate"
	return &""


func _scene_path_for(location_id: StringName) -> String:
	match location_id:
		&"classroom":
			return CLASSROOM_SCENE
		&"corridor":
			return CORRIDOR_SCENE
		&"street":
			return STREET_SCENE
	return ""


## Called by PrologueFlow when N releases the class: the door becomes usable.
func unlock_classroom_door() -> void:
	if current_location == null:
		return
	if current_location.has_method("unlock_exit"):
		current_location.call("unlock_exit")

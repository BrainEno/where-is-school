extends Node
class_name SceneDirector
## Loads authored locations and puts the player at a named spawn.
##
## Deliberately small: it swaps one location scene inside a container, positions
## the player, and emits a signal. It does not own story state, does not decide
## where the player should go, and does not run dialogue.

signal location_changed(location_id: StringName)
signal threshold_crossed(threshold_id: StringName)

const CLASSROOM := preload("res://scenes/locations/classroom/classroom.tscn")
const CORRIDOR := preload("res://scenes/locations/corridor/corridor.tscn")
const YARD := preload("res://scenes/locations/yard/yard.tscn")

@export var location_root: Node3D
@export var player: PlayerController
@export var fade_seconds: float = 0.42

var _current_id: StringName = &""
var _current: Node3D
var _busy: bool = false


func _ready() -> void:
	if location_root == null or player == null:
		# PrologueRoot assigns both during its own _ready(), which runs after this
		# node (children are readied before parents). Defer the check rather than
		# failing a scene that is about to be wired.
		_verify_configuration.call_deferred()


func _verify_configuration() -> void:
	if location_root == null or player == null:
		push_error("SceneDirector requires location_root and player exports; none were assigned.")


func current_location_id() -> StringName:
	return _current_id


func current_location() -> Node3D:
	return _current


func load_location(location_id: StringName, spawn: StringName = &"") -> bool:
	if _busy:
		push_warning("SceneDirector.load_location called while a swap is in progress.")
		return false
	var packed: PackedScene = _scene_for(location_id)
	if packed == null:
		push_error("SceneDirector: unknown location '%s'." % String(location_id))
		return false

	_busy = true
	_clear_current()
	_current = packed.instantiate() as Node3D
	if _current == null:
		push_error("SceneDirector: location '%s' root is not a Node3D." % String(location_id))
		_busy = false
		return false
	location_root.add_child(_current)
	_current_id = location_id
	_place_player(spawn)
	_connect_thresholds(location_id, _current)
	_busy = false
	location_changed.emit(location_id)
	return true


func _scene_for(location_id: StringName) -> PackedScene:
	match location_id:
		&"classroom":
			return CLASSROOM
		&"corridor":
			return CORRIDOR
		&"yard":
			return YARD
	return null


func _clear_current() -> void:
	if _current == null:
		return
	_current.queue_free()
	_current = null
	_current_id = &""


func _place_player(spawn: StringName) -> void:
	var transform := Transform3D.IDENTITY
	match _current_id:
		&"classroom":
			var room := _current as ClassroomLocation
			if room != null:
				transform = room.spawn_transform(&"seated" if spawn == &"seated" else &"standing")
		&"corridor":
			var corridor := _current as CorridorLocation
			if corridor != null:
				transform = corridor.spawn_transform()
		&"yard":
			var yard := _current as YardLocation
			if yard != null:
				transform = yard.spawn_transform()
	player.teleport_to(transform)


func _connect_thresholds(location_id: StringName, location: Node3D) -> void:
	match location_id:
		&"corridor":
			var corridor := location as CorridorLocation
			if corridor != null:
				corridor.yard_threshold_entered.connect(_on_threshold.bind(&"yard"))
		&"yard":
			var yard := location as YardLocation
			if yard != null:
				yard.gate_threshold_entered.connect(_on_threshold.bind(&"gate"))


func _on_threshold(threshold_id: StringName) -> void:
	if _busy:
		return
	threshold_crossed.emit(threshold_id)

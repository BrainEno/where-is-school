class_name InteractionController
extends Node
## Finds the best interaction target near the player and forwards the player's
## intent. Owns no UI and no narrative logic.
##
## Target choice prefers the object the player is facing, then distance, so two
## props in the same isle do not produce a flickering prompt.

signal target_changed(interactable: Interactable)
signal activation_requested(interactable: Interactable)

@export var player_path: NodePath = ^".."
@export var sensor_path: NodePath = ^"../InteractionSensor"
@export var max_distance: float = 2.4
## How strongly facing direction outweighs raw distance when ranking targets.
@export var facing_weight: float = 0.9

var _player: Node3D = null
var _sensor: Area3D = null
var _current: Interactable = null
var _enabled: bool = true


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	if _player == null:
		push_error("InteractionController: player_path '%s' did not resolve." % player_path)
	_sensor = get_node_or_null(sensor_path) as Area3D
	if _sensor == null:
		push_error("InteractionController: sensor_path '%s' did not resolve." % sensor_path)
	set_process_input(false)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if enabled:
		set_process_input(true)
	else:
		set_process_input(false)
		_set_current(null)


func is_enabled() -> bool:
	return _enabled


func get_current_target() -> Interactable:
	return _current


func _physics_process(_delta: float) -> void:
	if not _enabled or _player == null or _sensor == null:
		_set_current(null)
		return
	_set_current(_find_best_target())


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if not event.is_action_pressed("interact"):
		return
	if _current == null:
		return
	get_viewport().set_input_as_handled()
	activation_requested.emit(_current)


func _find_best_target() -> Interactable:
	var best: Interactable = null
	var best_score := INF
	var origin := _player.global_position
	var facing := -_player.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()

	for area: Area3D in _sensor.get_overlapping_areas():
		var candidate := area as Interactable
		if candidate == null or not candidate.can_interact():
			continue
		var offset := candidate.global_position - origin
		offset.y = 0.0
		var distance := offset.length()
		if distance > max_distance or distance <= 0.001:
			continue
		var alignment := facing.dot(offset.normalized())
		var score := distance + facing_weight * (1.0 - maxf(alignment, 0.0))
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _set_current(interactable: Interactable) -> void:
	if _current == interactable:
		return
	_current = interactable
	target_changed.emit(_current)

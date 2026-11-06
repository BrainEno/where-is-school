extends Node
class_name InteractionController
## Finds the nearest available target in the current location. No story/UI logic.

signal focus_changed(target: Interactable)
signal interaction_requested(target: Interactable)

@export var player: Node3D
var enabled: bool = false:
	set(value):
		enabled = value
		if not enabled:
			_set_focus(null)

var focused: Interactable


func _ready() -> void:
	if player == null:
		push_error("InteractionController requires a player reference.")


func _physics_process(_delta: float) -> void:
	if not enabled or player == null:
		return
	refresh_focus()


func refresh_focus() -> void:
	var best: Interactable = null
	var best_distance: float = INF
	for candidate: Node in get_tree().get_nodes_in_group("interactable"):
		var target: Interactable = candidate as Interactable
		if target == null or not target.available or not target.is_inside_tree():
			continue
		var offset: Vector3 = target.global_position - player.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance <= target.interaction_radius and distance < best_distance:
			best = target
			best_distance = distance
	_set_focus(best)


func _unhandled_input(event: InputEvent) -> void:
	if enabled and event.is_action_pressed("interact") and not event.is_echo():
		refresh_focus()
		if is_instance_valid(focused):
			interaction_requested.emit(focused)
			get_viewport().set_input_as_handled()


func _set_focus(target: Interactable) -> void:
	if focused == target:
		return
	focused = target
	focus_changed.emit(focused)

class_name InteractionSensor
extends Node3D
## Finds the best Interactable for the player each physics frame.
## Selection rule: nearest enabled interactable within range, preferring
## ones the player is roughly facing; falls back to proximity at close range.

@export var range: float = 1.9
@export var facing_range: float = 3.4
@export var facing_dot_min: float = 0.25

var focused: Interactable = null


func _ready() -> void:
	add_to_group("interaction_sensor")


func _physics_process(_delta: float) -> void:
	focused = _find_focused()


func _find_focused() -> Interactable:
	var player := get_parent() as Node3D
	if player == null:
		return null
	var origin := player.global_position
	var facing: Vector3 = Vector3.ZERO
	if player.has_method("facing_direction"):
		facing = player.call("facing_direction")
	if facing.length() < 0.001:
		facing = -player.global_basis.z
	facing.y = 0.0
	if facing.length() < 0.001:
		facing = Vector3(0, 0, -1)
	facing = facing.normalized()

	var best: Interactable = null
	var best_score: float = INF
	var tree := get_tree()
	for node in tree.get_nodes_in_group("interactables"):
		var interactable := node as Interactable
		if interactable == null or not interactable.enabled:
			continue
		if not is_instance_valid(interactable):
			continue
		var to_target: Vector3 = interactable.global_position - origin
		var distance: float = to_target.length()
		if distance > facing_range:
			continue
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		var flat_distance: float = flat.length()
		var dot: float = 1.0
		if flat_distance > 0.001:
			dot = flat.normalized().dot(facing)
		# Very close targets can be used even when not faced; distant ones must be faced.
		if flat_distance > range and dot < facing_dot_min:
			continue
		var score: float = flat_distance - dot * 0.6 - interactable.interact_priority * 0.75
		if score < best_score:
			best_score = score
			best = interactable
	return best

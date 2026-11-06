class_name InteractionSensor
extends Area3D
## Finds the nearest enabled Interactable3D in reach and reports it.
##
## Lives on the player scene. Owns no story knowledge: it reports what is nearby,
## and let PrologueFlow decide what happens when the player presses interact.

signal focus_changed(interactable: Interactable3D)
## Emitted whenever the sensor finishes an update pass and has chosen its focus.
## Tests wait on this instead of guessing a frame count.
signal focus_settled

@export_range(0.5, 6.0, 0.1) var reach: float = 2.6
## Interactables beyond this distance are ignored even if inside the area.
@export var enabled: bool = true

var current: Interactable3D = null
var _force_pending: bool = false
## Interactables that must never take focus. Used by tests to prove that each prop
## can be targeted on its own, and useful later for temporarily disabling a prop
## without deleting it.
var exclude: Array[Node] = []


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	# A generous sphere: Area3D overlap with static bodies is not needed; we only
	# look for child areas of props.
	_resize_shape()


func _resize_shape() -> void:
	var shape_node: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	var sphere := SphereShape3D.new()
	sphere.radius = reach
	shape_node.shape = sphere


## Ask for an update on the next physics tick even if the body has not moved.
func force_update() -> void:
	_force_pending = true


func _physics_process(_delta: float) -> void:
	_force_pending = false
	var best: Interactable3D = null
	var best_distance: float = INF
	var best_focus_priority: int = -1
	if enabled:
		for area: Area3D in get_overlapping_areas():
			var candidate := area as Interactable3D
			if candidate == null or not candidate.enabled:
				continue
			if exclude.has(candidate):
				continue
			var distance: float = global_position.distance_to(candidate.global_position)
			if distance > reach:
				continue
			# Priority first, then distance. This is what lets a small prop on a
			# large piece of furniture stay targetable.
			# A candidate that is not actually overlapping *this* frame is stale:
			# Area3D keeps reporting an area for a moment after either of them moved.
			# Trusting that is what made a second prop steal focus at a distance.
			if not overlaps_area(candidate):
				continue
			if candidate.focus_priority > best_focus_priority or (
				candidate.focus_priority == best_focus_priority and distance < best_distance
			):
				best = candidate
				best_distance = distance
				best_focus_priority = candidate.focus_priority
	if best != current:
		current = best
		focus_changed.emit(current)
	focus_settled.emit()


func interact_with_current() -> bool:
	if current == null:
		return false
	current.request_interaction()
	return true


func clear() -> void:
	if current != null:
		current = null
		focus_changed.emit(null)

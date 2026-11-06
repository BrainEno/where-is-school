extends Node3D
class_name ClassroomLocation
## Local scene presentation and the physical classroom doorway.

signal exit_requested

@export_range(0.1, 6.0, 0.1) var entrance_duration: float = 2.2
@onready var door_leaf: Node3D = $DoorLeaf
@onready var barrier: CollisionShape3D = $ExitBarrier/Collision
@onready var exit_trigger: Area3D = $ExitTrigger
@onready var exit_target: Interactable = $ExitTarget
@onready var n_target: Interactable = $NTarget
@onready var substitute: Node3D = $N
@onready var substitute_collision: CollisionShape3D = $N/BodyCollision/CollisionShape3D

var _exit_pending: bool = false


func _ready() -> void:
	exit_trigger.body_entered.connect(_on_exit_body_entered)
	if GameState.get_flag(&"observed.free_activity_granted", false):
		restore_after_lesson()


func entrance_is_clear(world_point: Vector3) -> bool:
	# N is staged along this short doorway-to-desk path. Ask the player to
	# step back instead of moving a cutscene actor through their body.
	var local_point: Vector3 = to_local(world_point)
	var point: Vector2 = Vector2(local_point.x, local_point.z)
	var path: Array[Vector2] = [Vector2(4.4, -5.8), Vector2(4.4, -4.05), Vector2(1.25, -3.6)]
	for i: int in range(path.size() - 1):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])
		if point.distance_to(closest) < 1.0:
			return false
	return true


func present_substitute() -> void:
	substitute.visible = true
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(door_leaf, "rotation_degrees:y", -83.0, entrance_duration * 0.3)
	tween.parallel().tween_property(substitute, "position", Vector3(4.4, 0.0, -4.05), entrance_duration * 0.45)
	tween.tween_property(substitute, "position", Vector3(1.25, 0.0, -3.6), entrance_duration * 0.55)
	await tween.finished
	substitute_collision.set_deferred("disabled", false)


func restore_after_lesson() -> void:
	door_leaf.rotation_degrees.y = -83.0
	substitute.visible = true
	substitute.position = Vector3(1.25, 0.0, -3.6)
	substitute_collision.set_deferred("disabled", false)
	unlock_exit()


func unlock_exit() -> void:
	barrier.set_deferred("disabled", true)
	exit_trigger.set_deferred("monitoring", true)
	exit_target.prompt = "ENTER THE CORRIDOR"
	n_target.available = true


func _on_exit_body_entered(body: Node3D) -> void:
	if not _exit_pending and body.is_in_group("player") and GameState.get_flag(&"observed.free_activity_granted", false):
		_exit_pending = true
		exit_requested.emit()

extends Node3D
class_name CorridorLocation
## The short corridor between the classroom and the yard.
##
## It exists so that leaving the classroom is a *walk* and not a cut. It has one
## authored event (the overheard noise near the lockers) and one exit.

signal yard_threshold_entered

@export var narrative_enabled: bool = true

@onready var spawn_from_classroom: Marker3D = $SpawnFromClassroom
@onready var yard_exit: Area3D = $YardExit


func _ready() -> void:
	yard_exit.body_entered.connect(_on_exit_body_entered)


func id() -> StringName:
	return &"corridor"


func spawn_transform() -> Transform3D:
	return spawn_from_classroom.global_transform


func _on_exit_body_entered(body: Node3D) -> void:
	if not (body is PlayerController):
		return
	yard_threshold_entered.emit()

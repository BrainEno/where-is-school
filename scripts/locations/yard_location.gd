extends Node3D
class_name YardLocation
## The school yard and the gate. This is the milestone's last authored space.
##
## The street beyond the gate is deliberately not implemented: the prologue's
## green-animal beat belongs to a second milestone, and guessing its species
## here would pre-empt a narrative decision that has not been made.

signal gate_threshold_entered

@onready var spawn_from_corridor: Marker3D = $SpawnFromCorridor
@onready var gate_threshold: Area3D = $YardGateThreshold
@onready var gate_focus: Marker3D = $GateFocus


func _ready() -> void:
	gate_threshold.body_entered.connect(_on_gate_body_entered)


func id() -> StringName:
	return &"yard"


func spawn_transform() -> Transform3D:
	return spawn_from_corridor.global_transform


func gate_focus_point() -> Vector3:
	return gate_focus.global_position


func _on_gate_body_entered(body: Node3D) -> void:
	if not (body is PlayerController):
		return
	gate_threshold_entered.emit()

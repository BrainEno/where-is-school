extends StagedInteractable
## Look through a high classroom slit using the ordinary interaction action. The beat
## holds horizontal movement; PlayerController still applies gravity and moves the body.
## Standing at the trigger (or being on another floor) is not an observation.

const STANDING_EYE: float = 1.62
const HOP_RISE: float = 0.64
const PEEK_REACH: float = 2.80

@export var pane_path: NodePath

@onready var _pane: MeshInstance3D = get_node_or_null(pane_path) as MeshInstance3D


func _ready() -> void:
	super._ready()
	if _pane == null or not (_pane.mesh is QuadMesh):
		push_error("High window '%s' needs a QuadMesh pane at '%s'." % [interact_id, pane_path])
		interaction_enabled = false
		return
	stage_handler = _hop_and_peek


## The eye must actually pass between the head and sill on the hall side of the pane.
func can_peek_at(feet: Vector3) -> bool:
	if _pane == null:
		return false
	var eye := _pane.to_local(feet + Vector3.UP * STANDING_EYE)
	return _near_pane(eye) and absf(eye.y) < (_pane.mesh as QuadMesh).size.y * 0.5


func _near_pane(eye: Vector3) -> bool:
	return (
		eye.z > 0.15 and Vector2(eye.x, eye.z).length() <= PEEK_REACH
		and absf(eye.x) < (_pane.mesh as QuadMesh).size.x * 0.5 + 0.8
	)


func _hop_and_peek(director: OpeningSequence) -> Dictionary:
	var player := director.get_player()
	if player == null or not player.is_on_floor():
		return {}
	var feet := player.global_position
	var eye := _pane.to_local(feet + Vector3.UP * STANDING_EYE)
	if not _near_pane(eye) or eye.y > -0.16 or eye.y < -HOP_RISE:
		return {}
	player.face_toward(_pane.global_position - feet)
	player.velocity = Vector3.UP * sqrt(2.0 * HOP_RISE * player.gravity)
	var airborne := false
	var glimpsed := false
	# Physics ticks, not rendered frames. Allow a little extra time if the body
	# hits a ceiling early; no pose or velocity is written on landing.
	var deadline := get_tree().create_timer(1.25, false, true)
	while deadline.time_left > 0.0:
		await get_tree().physics_frame
		if not is_instance_valid(player):
			return {}
		if player.is_on_floor():
			if airborne:
				break
			continue
		airborne = true
		glimpsed = glimpsed or can_peek_at(player.global_position)
	if airborne and glimpsed and player.is_on_floor():
		return {"inspection": inspection_id}
	return {}

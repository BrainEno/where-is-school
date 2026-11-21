extends StagedInteractable
## The seated model does not fill its standing collision capsule. Ignore only
## that occupant in the visibility probe, not walls, furniture or other actors.

var sitter: PlayerController


func is_occupied_by(body: Node3D) -> bool:
	return is_instance_valid(sitter) and sitter == body and sitter.is_seated()

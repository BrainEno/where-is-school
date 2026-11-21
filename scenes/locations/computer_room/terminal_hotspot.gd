extends StagedInteractable
## Keep both shapes in the interaction sensor. Turning monitorable off and back
## on while already overlapping can leave the new offer out of the sensor list.

@export var requires_sitter := false

var chair: PushableChair
var sitter: PlayerController


func can_interact() -> bool:
	return interaction_enabled and is_station_occupied() == requires_sitter


func is_station_occupied() -> bool:
	return is_instance_valid(sitter) and sitter.is_seated() and not sitter.is_seat_transition_active() \
		and sitter.global_position.distance_to(chair.home_mark()) < 0.09


## The seated model does not fill its standing collision capsule. Ignore only
## that occupant in the view probe, not walls, furniture or other actors.
func is_occupied_by(body: Node3D) -> bool:
	return sitter == body and is_station_occupied()

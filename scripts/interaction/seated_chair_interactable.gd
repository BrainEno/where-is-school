extends StagedInteractable
## The wake chair offers one action at a time. The room owns the approach and
## staging; this node owns the live offer through the normal interaction route.

enum Offer { NONE, SIT, STAND }

var player: PlayerController


func current_offer() -> Offer:
	if not is_instance_valid(player) or player.is_seat_transition_active():
		return Offer.NONE
	return Offer.STAND if player.is_seated() else Offer.SIT


func can_interact() -> bool:
	return interaction_enabled and current_offer() != Offer.NONE

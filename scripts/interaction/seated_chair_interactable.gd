extends StagedInteractable
## The protagonist's own chair, offering whichever of sit / stand the body is not already doing.
##
## The classroom already had an interactable over this chair, and it pointed at the schoolbag
## hanging on its back: point at the chair, search the bag. That is right while the
## protagonist is on his feet and the chair is empty, and it stops being right once he can sit
## in it, because the same outline then answers two different questions.
##
## So this node answers one question at a time, chosen by where the body is:
##
## - on his feet, chair out of the way → "Sit down": the chair is drawn home and he sits;
## - seated → "Stand up": the ordinary stand-up, which pushes the chair back out;
## - mid-transition → nothing at all, and the interactable is *disabled* rather than merely
##   unprompted, so the pointer falls through to the schoolbag behind it instead of offering a
##   button that would do nothing.
##
## What actually happens is the room's (`classroom_chair_control.gd`), assigned to
## `stage_handler`; this node only says what is on offer.

enum Offer { NONE, SIT, STAND }

const SIT_PROMPT_KEY := "prompt.sit"
const STAND_PROMPT_KEY := "prompt.stand"

## The body whose state decides the offer. Assigned by the room.
var player: Node = null
## The chair node this speaks for (`pushable_chair.gd`), so the prompt can wait for it to be
## out of the way before offering a seat.
var chair: Node3D = null


## What the body is doing with this chair.
func current_offer() -> Offer:
	if player == null or not is_instance_valid(player):
		return Offer.NONE
	if bool(player.call("is_getting_up")):
		return Offer.NONE
	if bool(player.call("is_seated")):
		return Offer.STAND
	return Offer.SIT


func can_interact() -> bool:
	return interaction_enabled and current_offer() != Offer.NONE


func get_prompt() -> String:
	var override := get_prompt_override()
	if not override.is_empty():
		return override
	return "Sit down" if current_offer() == Offer.SIT else "Stand up"


## The locale key for the current offer, for a build that translates prompts. The room sets
## this through `set_prompt` as well; this is what a content check reads.
func get_offer_prompt_key() -> String:
	match current_offer():
		Offer.SIT:
			return SIT_PROMPT_KEY
		Offer.STAND:
			return STAND_PROMPT_KEY
		_:
			return ""

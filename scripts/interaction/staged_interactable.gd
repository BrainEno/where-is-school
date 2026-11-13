class_name StagedInteractable
extends Interactable
## An interactable whose use is a staged moment of its own room, not just a text.
##
## Most interactables declare an inspection, a conversation route or an exit, and the
## sequence director routes the activation to one of them. Some objects change the room
## they stand in: the biology classroom's rear door opens and a staircase is suddenly in
## the room; its back-window curtain is drawn aside and there is nothing behind it. What
## happens there is choreography that only that room knows, so the room's script sets
## `stage_handler`, and the director (`OpeningSequence`) calls it through `perform()`
## *inside a beat*: the player is locked, nothing else can start, and the handler can play
## conversations and animate its own nodes.
##
## The handler never outlives its room. When the moment ends by leaving the room (the
## curtain's fall), the handler does not take the transition itself - the room is freed
## halfway through a transition, and a coroutine resumed on a freed node is an engine error
## - it *returns a request* and the director carries it out:
##
##   {}                                    nothing more; the beat ends.
##   {"inspection": &"some_inspection"}    show this text once the beat has ended.
##   {"transition": {"scene": "res://...", "spawn": &"Marker", "id": &"location_id",
##                   ...LocationFlow.transition_to() options}}
##                                         leave, still holding the same beat.
##
## `inspection_id`, `conversation_route` and `prompt_key` keep their ordinary meaning for
## the prompt and for content checks (`content_integrity_test.gd` reads them from the
## scene); the handler decides when to use them.
##
## Keep these rare. A prop that only needs a sentence is an inspection.

## func(director: Node) -> Dictionary (may await). Set by the room's script.
var stage_handler: Callable = Callable()


## Read by the director: true when the room has a handler for this object.
func is_staged() -> bool:
	return stage_handler.is_valid()


## Runs the room's handler and returns its request (see the class notes). The director
## calls this inside a beat; anything else should call `activate()`.
func perform(director: Node) -> Dictionary:
	if not stage_handler.is_valid():
		push_error("StagedInteractable '%s' has no stage handler." % interact_id)
		return {}
	var result: Variant = await stage_handler.call(director)
	if result is Dictionary:
		return result
	return {}

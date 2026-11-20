class_name OpeningInteractions
extends RefCounted
## What happens when the player uses something in the room.
##
## Split out of `OpeningSequence` (issue #223). The director still receives the
## `activation_requested` signal and owns the beat lock, the conversations and the exits;
## this object only decides which of those an interactable asks for, in a fixed order:
##
## 1. an exit is a visit (`LocationFlow.handle_exit()`, awaited to the end);
## 2. a room that stages its own moment (`StagedInteractable`) is asked first, inside a
##    beat, and its request - a text, a checkpoint, a transition - is carried out after;
## 3. a declared `conversation_route` picks a conversation from the story flags
##    (`ConversationRouter`) and plays it inside a beat;
## 4. a declared `inspection_id` shows its text;
## 5. anything else is an authoring mistake, and is logged as one.
##
## While a dialogue runs or the slice is over, nothing is routed; an important moment
## pulls the camera in for as long as it holds the player (`CameraFocusDirector`).

## The interaction after which the roaming Q starts following again.
const ASK_ALONG_ID: StringName = &"q_ask_along"

## The `OpeningSequence` (untyped, as `LocationFlow`'s host is): the beat lock, the
## conversations and the checkpoints are its.
var _director: Node = null
var _dialogue: DialogueController = null
var _flow: LocationFlow = null
var _focus: CameraFocusDirector = null
var _companion: CompanionController = null
var _game_state: Node = null


func _init(director: Node, dialogue: DialogueController, flow: LocationFlow,
		focus: CameraFocusDirector, companion: CompanionController, game_state: Node) -> void:
	_director = director
	_dialogue = dialogue
	_flow = flow
	_focus = focus
	_companion = companion
	_game_state = game_state


## Carries out what `interactable` asks for. Awaitable: an exit, a staged moment and a
## conversation each return when they are over.
func activate(interactable: Interactable) -> void:
	if _dialogue.is_busy() or _director.is_slice_finished():
		return

	var exit := interactable as LocationExit
	if exit != null:
		# The same call as `OpeningSequence._handle_exit()`: awaits the whole visit.
		if _flow != null:
			await _flow.handle_exit(exit)
		return

	var beat_active := bool(_director.is_beat_active())
	# An important moment pulls the camera in for as long as it holds the player.
	if _focus != null and not (beat_active and interactable is StagedInteractable):
		_focus.engage(interactable)

	# A room that stages its own moment (see StagedInteractable) is asked before the
	# object's declared route or text, which are then the room's to use.
	var staged := interactable as StagedInteractable
	if staged != null and staged.is_staged():
		# A staged moment owns the room while it runs (a door is still swinging, a
		# curtain still moving), even between its lines, when no dialogue is busy.
		if beat_active:
			return
		await run_staged(staged)
		return

	if not String(interactable.conversation_route).is_empty():
		await _play_route(interactable)
		return

	if not String(interactable.inspection_id).is_empty():
		_dialogue.present_inspection(interactable.inspection_id)
		return

	push_error(
		"OpeningSequence: interactable '%s' declares no inspection, conversation, or exit."
		% interactable.interact_id
	)


func _play_route(interactable: Interactable) -> void:
	var conversation := ConversationRouter.select(
		interactable.conversation_route, _game_state.get_snapshot()
	)
	if String(conversation).is_empty():
		push_error(
			"OpeningSequence: no conversation rule matched route '%s'."
			% interactable.conversation_route
		)
		return
	await _director.begin_beat()
	await _director.play_conversation(conversation)
	_director.end_beat()
	if interactable.interact_id == ASK_ALONG_ID and _companion != null:
		_companion.resume_following()


## One staged moment: the room's handler runs inside a beat, then whatever it asked for
## afterwards (see `StagedInteractable`) - a text once the beat is over, or a transition
## that keeps the same beat, so the player never gets a frame of control in between.
func run_staged(staged: StagedInteractable) -> void:
	await _director.begin_beat()
	var request: Dictionary = await staged.perform(_director)
	var transition: Dictionary = request.get("transition", {})
	if not transition.is_empty() and _flow != null:
		var options := transition.duplicate()
		options["beat_held"] = true
		if not options.has("label"):
			options["label"] = "staged '%s'" % staged.interact_id
		# A refused transition runs the request's `on_failure` inside `transition_to()`,
		# before the fade back and while this beat is still held; it is not called again.
		await _flow.transition_to(
			String(transition.get("scene", "")),
			StringName(String(transition.get("spawn", ""))),
			StringName(String(transition.get("id", ""))),
			options
		)
		return
	_director.end_beat()
	var checkpoint := String(request.get("checkpoint", ""))
	if not checkpoint.is_empty():
		_director.autosave(checkpoint)
	var inspection := StringName(String(request.get("inspection", "")))
	if not String(inspection).is_empty():
		_dialogue.present_inspection(inspection)

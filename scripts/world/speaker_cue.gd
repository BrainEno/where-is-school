extends AudioStreamPlayer3D
## Plays one short original noise cue when a particular conversation starts.
##
## The corridor's wall speaker is not music and not a stinger: it is the sound of a
## class carrying on behind a wall, heard once or twice and then not mentioned
## again. Keeping it on the speaker node (rather than in the dialogue runtime)
## means the cue stays a property of the prop.

## Conversation that triggers the cue.
@export var conversation_id: StringName = &""
## How many times this cue may play in one session. A noise that repeats loses the
## quality of something happening by accident.
@export var max_plays: int = 2

var _dialogue: Node = null
var _plays: int = 0


func _ready() -> void:
	_dialogue = _find_dialogue()
	if _dialogue == null:
		push_warning("SpeakerCue: no DialogueController found; the cue will stay silent.")
		return
	if _dialogue.has_signal("conversation_started"):
		_dialogue.connect("conversation_started", Callable(self, "_on_conversation_started"))


## The director is a sibling of the location host, not an ancestor: walk up until
## a level has a DialogueController child.
func _find_dialogue() -> Node:
	var node: Node = get_parent()
	while node != null:
		var found := node.get_node_or_null(^"DialogueController")
		if found != null:
			return found
		node = node.get_parent()
	return null


## How many times the cue has fired this session. Diagnostics, not gameplay: the
## capture run and the tests use it to prove the sound was actually asked for.
func get_play_count() -> int:
	return _plays


func _on_conversation_started(started_id: StringName) -> void:
	if String(conversation_id).is_empty() or started_id != conversation_id:
		return
	if _plays >= max_plays:
		return
	_plays += 1
	play()

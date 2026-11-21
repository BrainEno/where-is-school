extends StagedInteractable
## The yard tap by the landing. Clear-headed, it is only its inspection (`pg_tap`). While
## the dazed look of a hurt landing lasts (`ConcussionView`), using it offers a mouthful of
## water, a wash, or leaving it (`pg_tap_use`): a mouthful takes a third of what is left
## of the look and can be taken again; a wash clears it at once. The choice is applied the
## moment it is made, so the picture settles under the line that describes it.

const CONVERSATION := &"pg_tap_use"
const DRINK := "drink"
const WASH := "wash"
const LEAVE := "leave"


func _ready() -> void:
	super()
	stage_handler = _use


func _use(director: Node) -> Dictionary:
	var state := get_node_or_null(^"/root/GameState")
	if state == null or not _dazed(state):
		return {"inspection": inspection_id}
	state.set_flag(StoryFlags.TAP_USE, LEAVE)
	var apply := func(flag: StringName, _previous: Variant, value: Variant) -> void:
		if flag != StoryFlags.TAP_USE:
			return
		if String(value) == DRINK:
			ConcussionView.relieve(self)
		elif String(value) == WASH:
			ConcussionView.clear(self)
	state.story_flag_changed.connect(apply)
	await director.play_conversation(CONVERSATION)
	state.story_flag_changed.disconnect(apply)
	return {}


static func _dazed(state: Node) -> bool:
	var left: Variant = state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0)
	return (left is int or left is float) and int(left) > 0

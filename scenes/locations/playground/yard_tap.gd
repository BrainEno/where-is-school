extends StagedInteractable
## The yard tap by the landing. Clear-headed, it is only its inspection (`pg_tap`). While
## the dazed look of a hurt landing lasts (`ConcussionView`), using it offers a mouthful of
## water, a wash, or leaving it (`pg_tap_use`): water either way, drunk or on the face,
## clears the look (`ConcussionView.clear()`); leaving it keeps it. The choice is applied the
## moment it is made, so the picture settles under the line that describes it - and once
## more when the conversation is over, in case the choice was made some other way (a
## restored line, a skipped one): clearing twice is still clear.

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
		if flag == StoryFlags.TAP_USE:
			_take(value)
	state.story_flag_changed.connect(apply)
	await director.play_conversation(CONVERSATION)
	state.story_flag_changed.disconnect(apply)
	_take(state.get_flag(StoryFlags.TAP_USE, LEAVE))
	return {}


func _take(choice: Variant) -> void:
	var taken := String(choice) if choice is String or choice is StringName else LEAVE
	if (taken == DRINK or taken == WASH) and _dazed(get_node_or_null(^"/root/GameState")):
		ConcussionView.clear(self)


static func _dazed(state: Node) -> bool:
	if state == null:
		return false
	var left: Variant = state.get_flag(StoryFlags.CONCUSSION_SECONDS_LEFT, 0)
	return (left is int or left is float) and int(left) > 0

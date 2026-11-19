extends StagedInteractable
## The directory is read before it can be marked. Its small slide is local staging:
## the dialogue owns the choice, and the saved choice sets the initial pose on return.

const SIDE_OFFSET := 0.62
const PLAY := 0.055

@export var tab_path: NodePath

@onready var _tab: Node3D = get_node_or_null(tab_path) as Node3D
@onready var _state: Node = get_node_or_null(^"/root/GameState")
var _center_x: float


func _ready() -> void:
	super._ready()
	if _tab == null or _state == null:
		push_error("DirectoryTab needs its slide and GameState.")
		interaction_enabled = false
		return
	_center_x = _tab.position.x
	_restore_tab()
	_state.story_state_replaced.connect(_restore_tab)
	stage_handler = _use_directory


func get_prompt_override() -> String:
	if _has_read_directory():
		return "prompt.corridor_directory_tab"
	return super.get_prompt_override()


func _has_read_directory() -> bool:
	return _state != null and _state.get_flag(StoryFlags.inspection_seen_flag(inspection_id)) == true


func _slide_offset() -> float:
	match _state.get_flag(StoryFlags.CORRIDOR_DIRECTORY_TAB, ""):
		"glass":
			return -SIDE_OFFSET
		"stair":
			return SIDE_OFFSET
	return 0.0


func _restore_tab() -> void:
	_tab.position.x = _center_x + _slide_offset()


func _use_directory(director: OpeningSequence) -> Dictionary:
	if not _has_read_directory():
		return {"inspection": inspection_id}
	var before := _slide_offset()
	var conversation := ConversationRouter.select(conversation_route, _state.get_snapshot())
	await director.play_conversation(conversation)
	var after := _slide_offset()
	if is_equal_approx(before, after):
		return {}
	# A little play in the metal slot. The camera's ordinary interaction focus and
	# the director's existing beat stay held until the tab has come to rest.
	var stop := _center_x + after
	var slide := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slide.tween_property(_tab, ^"position:x", stop + signf(after - before) * PLAY, 0.44)
	slide.tween_property(_tab, ^"position:x", stop, 0.24)
	await slide.finished
	return {"checkpoint": "directory_tab"}

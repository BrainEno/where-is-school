extends CharacterVisualAnimation
## Q's textbook performance is cued by presented node IDs, not translated words.
## It belongs to the room's Q; the following Q uses this wrapper's ordinary clips.

const TextbookPose = preload("res://scripts/actors/npc/q_textbook_pose.gd")
const OPENING_BOOK_CUES := [&"q_none_1", &"q_exam_end", &"p_ecosystem_question"]
const STUDY_CONVERSATIONS := [&"q_studying", &"q_after_bag"]

@export var textbook_scene: PackedScene

var _study: TextbookPose
var _story: Node
var _book_open := false
var _subjective := false
var _conversation := &""
var _line_id := &""
var _speaking := false


func _ready() -> void:
	super._ready()
	if not is_bound() or not _is_classroom_q():
		return
	_study = TextbookPose.new()
	if not _study.install(self, textbook_scene):
		_study.free()
		_study = null
		return
	_story = get_node_or_null(^"/root/GameState")
	if _story != null:
		_story.story_state_replaced.connect(_restore_book)
		_story.story_flag_changed.connect(_on_story_flag_changed)
	_restore_book()


func _is_classroom_q() -> bool:
	var actor := get_parent() as NpcActor
	if actor == null or actor.npc_id != &"q":
		return false
	var ancestor := actor.get_parent()
	while ancestor != null:
		if ancestor is LocationRoot:
			return ancestor.location_id == &"classroom"
		ancestor = ancestor.get_parent()
	return false


func present_dialogue_line(line: Dictionary, speaking: bool) -> void:
	super.present_dialogue_line(line, speaking)
	if _study == null:
		return
	_subjective = bool(line.get("subjective", false))
	_conversation = StringName(line.get("conversation_id", &""))
	_line_id = StringName(line.get("node_id", &""))
	_speaking = speaking
	if not _subjective and not _flag(StoryFlags.CLASS_DISMISSED):
		# The clearest reading cue is a protagonist observation, not Q speaking.
		if (_conversation == &"q_wake" and _line_id in OPENING_BOOK_CUES
			or _conversation in STUDY_CONVERSATIONS
			or (_conversation == &"n_class" and _line_id == &"q_n_guarded")):
			_book_open = true
	_update_book_cue()


func _update_book_cue() -> void:
	if not _book_open or _subjective or _flag(StoryFlags.CLASS_DISMISSED):
		_study.cue = TextbookPose.Cue.STOWED
	elif _conversation == &"q_after_bag" and _line_id == &"q_accused_2":
		_study.cue = TextbookPose.Cue.SHOW_PAGE
	elif _conversation == &"q_wake" and _line_id == &"q_end_grin":
		_study.cue = TextbookPose.Cue.GRIN
	elif _speaking:
		_study.cue = TextbookPose.Cue.REPLY
	else:
		_study.cue = TextbookPose.Cue.RECITE


func _restore_book() -> void:
	# No new save flag: legal checkpoints after the first talk already record it.
	# In saves older than q_first_talk_done, met_q meant the first talk had finished.
	_book_open = _story != null and bool(_story.get_flag(
		StoryFlags.Q_FIRST_TALK_DONE, _flag(StoryFlags.MET_Q)))
	_update_book_cue()


func _on_story_flag_changed(flag: StringName, _previous: Variant, value: Variant) -> void:
	if flag == StoryFlags.Q_FIRST_TALK_DONE and bool(value):
		_book_open = true
		_update_book_cue()
	elif flag == StoryFlags.CLASS_DISMISSED:
		_update_book_cue()


func _flag(flag: StringName) -> bool:
	return _story != null and bool(_story.get_flag(flag, false))

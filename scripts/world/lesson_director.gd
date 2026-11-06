class_name LessonDirector
extends Node
## Orchestrates the Biology Class prologue sequence.
## Owns sequencing only: it never writes prose, never moves the player,
## and never mutates story flags that belong to dialogue content.
## Phase order: wake -> Q initiates -> bag discovery -> classroom inspect
## -> bell (B absent) -> N substitutes -> dismissal -> exit.

@export var wake_conversation: DialogueConversation
@export var q_intro_conversation: DialogueConversation
@export var q_bag_conversation: DialogueConversation
@export var bell_gap_conversation: DialogueConversation
@export var n_arrival_conversation: DialogueConversation
@export var imagination_conversation: DialogueConversation

@export var n_npc: Node3D
@export var n_entry_point: Marker3D
@export var n_desk_point: Marker3D

const BELL_FALLBACK_SECONDS: float = 60.0
const BELL_INSPECTS_REQUIRED: int = 2

var _wake_started: bool = false
var _bell_rung: bool = false
var _substitute_entered: bool = false
var _time_since_wake: float = 0.0
var _audio: AudioStreamPlayer


func _ready() -> void:
	add_to_group("lesson_director")
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	if n_npc != null:
		n_npc.visible = false
	var ui := _ui()
	if ui != null and ui.has_signal("conversation_finished"):
		ui.connect("conversation_finished", _on_conversation_finished)
	else:
		push_error("LessonDirector: no node in group 'game_ui' with conversation_finished signal")
	var state := _state()
	if state != null and state.has_signal("story_flag_changed"):
		state.connect("story_flag_changed", _on_story_flag_changed)
	_begin_sequence()


func _process(delta: float) -> void:
	if _bell_rung or not _wake_started:
		return
	var state := _state()
	if state == null:
		return
	if state.get_flag(&"flow.woke_up", false) == true:
		_time_since_wake += delta
		_evaluate_bell()
		if _time_since_wake >= BELL_FALLBACK_SECONDS and state.get_flag(&"observed.textbook_missing", false) == true:
			_ring_bell()


func _begin_sequence() -> void:
	if _wake_started:
		return
	_wake_started = true
	var state := _state()
	if state != null and state.get_flag(&"flow.class_dismissed", false) == true:
		# Defensive: restored session after dismissal. Offer the exit objective.
		_set_objective("Leave the classroom.")
		return
	var scene_flow := _scene_flow()
	if scene_flow != null:
		scene_flow.begin_fade_in()
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	var ui := _ui()
	if ui != null:
		ui.start_conversation(wake_conversation)


func _on_conversation_finished(conversation_id: StringName) -> void:
	var state := _state()
	match conversation_id:
		&"wake_intro":
			if state != null:
				state.set_flag(&"flow.woke_up", true)
			_set_objective("Check your schoolbag.")
			await get_tree().create_timer(0.6).timeout
			if not is_inside_tree():
				return
			if state != null and state.get_flag(&"flow.q_intro_done", false) != true:
				var ui := _ui()
				if ui != null:
					ui.start_conversation(q_intro_conversation)
		&"q_intro":
			if state != null:
				state.set_flag(&"flow.q_intro_done", true)
			_set_objective("Check your schoolbag. (E to interact)")
		&"bag_search":
			if state != null:
				state.set_flag(&"flow.bag_searched", true)
			if state != null and state.get_flag(&"flow.q_bag_barked", false) != true:
				state.set_flag(&"flow.q_bag_barked", true)
				await get_tree().create_timer(0.5).timeout
				_ui().start_conversation(q_bag_conversation)
		&"bell_gap":
			_start_substitute_entrance()
		&"n_arrival":
			_set_objective("Leave the classroom.")
		_:
			pass
	# Subjective imagination chains after the conversation that requested it.
	if state != null and state.get_flag(&"flow.want_imagination", false) == true:
		state.set_flag(&"flow.want_imagination", false)
		if conversation_id != &"imagination_b":
			var ui := _ui()
			if ui != null:
				ui.start_conversation(imagination_conversation)
			return
	if conversation_id != &"bag_search" and conversation_id != &"bell_gap":
		_evaluate_bell()


func _on_story_flag_changed(flag: StringName, _previous: Variant, new_value: Variant) -> void:
	if flag == &"observed.textbook_missing" or String(flag).begins_with("observed.inspect."):
		_evaluate_bell()
	if flag == &"flow.class_dismissed" and new_value == true:
		_set_objective("Leave the classroom.")


func _evaluate_bell() -> void:
	if _bell_rung:
		return
	var state := _state()
	if state == null:
		return
	if state.get_flag(&"flow.bell_rung", false) == true:
		_bell_rung = true
		return
	var bag_missing: bool = state.get_flag(&"observed.textbook_missing", false) == true
	var inspects: int = state.count_flags_with_prefix("observed.inspect.")
	if bag_missing and inspects >= BELL_INSPECTS_REQUIRED:
		_ring_bell()


func _ring_bell() -> void:
	if _bell_rung:
		return
	_bell_rung = true
	var state := _state()
	if state != null:
		state.set_flag(&"flow.bell_rung", true)
	_set_objective("The bell has rung. B hasn't come in.")
	_audio.stream = SfxBank.bell()
	_audio.play()
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
	var ui := _ui()
	if ui != null:
		ui.start_conversation(bell_gap_conversation)


func _start_substitute_entrance() -> void:
	if _substitute_entered:
		return
	_substitute_entered = true
	if n_npc == null or n_entry_point == null or n_desk_point == null:
		push_error("LessonDirector: substitute entrance markers are not wired; N teleports to the front.")
		var ui := _ui()
		if ui != null:
			ui.start_conversation(n_arrival_conversation)
		return
	n_npc.global_position = n_entry_point.global_position
	n_npc.visible = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(n_npc, "global_position", n_desk_point.global_position, 2.4)
	await tween.finished
	if not is_inside_tree():
		return
	_audio.stream = SfxBank.paper()
	_audio.play()
	var ui := _ui()
	if ui != null:
		ui.start_conversation(n_arrival_conversation)


func _ui() -> Node:
	return get_tree().get_first_node_in_group("game_ui")


func _state() -> Node:
	var root := get_tree().get_root()
	return root.get_node_or_null("GameState") if root else null


func _scene_flow() -> Node:
	var root := get_tree().get_root()
	return root.get_node_or_null("SceneFlow") if root else null


func _set_objective(text: String) -> void:
	var ui := _ui()
	if ui != null and ui.has_method("set_objective"):
		ui.set_objective(text)

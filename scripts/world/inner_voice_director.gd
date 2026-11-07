class_name InnerVoiceDirector
extends Node
## Decides when an inner voice speaks *without being asked*.
##
## The active half of the ability system lives in dialogue content: a check node
## names a voice, the player picked the option that leads to it, and the panel
## shows the numbers. This node owns the passive half, which is the part that can
## go wrong for the player's patience if it is unmanaged:
##
## - **Triggers are events, not clocks.** A voice reacts to reading something
##   (`inspection`), to arriving somewhere (`location`), or to the end of a
##   conversation. It never speaks on a timer, so it cannot chatter while the
##   player is walking or thinking.
## - **It waits for the frame to be free.** A passive line never interrupts an
##   authored beat or a conversation the player started; the request stays queued.
## - **It is rationed.** Each rule fires once unless content says otherwise, each
##   voice has a per-session cap, and one unprompted line cannot chain straight
##   into another: something else has to happen in between.
## - **It stays silent during the end card.** Once the slice is finished there is
##   nothing left to notice.
##
## The rules themselves are data (`data/abilities/abilities.json`), and every rule
## points at a conversation whose first node is a *hidden* check, so the same dice
## core decides what the voice notices. That is why this script contains no
## randomness at all.

## At most this many requests may wait; more than one would stack lines up and make
## the pacing feel scripted.
const MAX_PENDING := 1

@export var dialogue_path: NodePath = ^"../DialogueController"
@export var sequence_path: NodePath = ^"../OpeningSequence"
@export var location_host_path: NodePath = ^"../LocationHost"

var _dialogue: DialogueController = null
var _sequence: Node = null
var _location_host: Node = null
var _abilities: InnerAbilities = null

var _pending: Array[InnerAbilities.PassiveRule] = []
## How many presentations have happened since the last unprompted line.
var _since_voice: int = 0
## True while the conversation this node started is running, so it does not count
## itself as "something happened" and immediately queue another voice.
var _firing: bool = false


func _ready() -> void:
	_dialogue = get_node_or_null(dialogue_path) as DialogueController
	if _dialogue == null:
		push_error("InnerVoiceDirector: dialogue controller not found at '%s'." % dialogue_path)
		return
	_sequence = get_node_or_null(sequence_path)
	_location_host = get_node_or_null(location_host_path)
	_abilities = _dialogue.get_abilities()
	if _abilities == null or not _abilities.is_valid():
		push_error("InnerVoiceDirector: inner abilities failed to load; passive lines are off.")
		return
	_dialogue.inspection_presented.connect(_on_inspection_presented)
	_dialogue.conversation_finished.connect(_on_conversation_finished)
	if _location_host != null and _location_host.has_signal("location_entered"):
		_location_host.connect(
			"location_entered", Callable(self, "_on_location_entered")
		)


func _process(_delta: float) -> void:
	_pump()


# --- triggers ---------------------------------------------------------------


func _on_inspection_presented(inspection_id: StringName) -> void:
	_since_voice += 1
	request("inspection", inspection_id)


func _on_location_entered(location: Node, _spawn_id: StringName) -> void:
	if location == null:
		return
	_since_voice += 1
	var location_id: StringName = StringName(String(location.get("location_id")))
	request("location", location_id)


func _on_conversation_finished(conversation_id: StringName) -> void:
	if _firing:
		# Our own line ending is not a new event to react to.
		_firing = false
		return
	_since_voice += 1
	request("conversation_end", conversation_id)


## Queues whichever rules match this event and are still allowed to fire. Public
## so a test can ask the same question the triggers ask, without a running scene.
func request(trigger_kind: String, trigger_id: StringName) -> void:
	var fired := evaluate(trigger_kind, trigger_id)
	for rule: InnerAbilities.PassiveRule in fired:
		if _pending.size() >= MAX_PENDING:
			break
		_pending.append(rule)


## Every rule for this event that would be allowed to fire right now. No side
## effects: nothing is marked as spent and nothing is played.
func evaluate(trigger_kind: String, trigger_id: StringName) -> Array[InnerAbilities.PassiveRule]:
	var result: Array[InnerAbilities.PassiveRule] = []
	if _abilities == null:
		return result
	for rule: InnerAbilities.PassiveRule in _abilities.get_rules_for(trigger_kind, trigger_id):
		if _can_fire(rule):
			result.append(rule)
	return result


func _can_fire(rule: InnerAbilities.PassiveRule) -> bool:
	if _dialogue == null:
		return false
	if _firing:
		return false
	if _since_voice < 1:
		# Nothing has happened since the last unprompted line.
		return false
	if _is_slice_finished():
		return false
	var ability := _abilities.get_ability(rule.ability_id)
	if ability == null:
		return false
	if rule.once and _flag(StoryFlags.passive_fired_flag(rule.rule_id), false):
		return false
	var count := int(_flag(StoryFlags.passive_count_flag(rule.ability_id), 0))
	if count >= ability.max_passive:
		return false
	for flag: StringName in rule.requires:
		if _flag(flag, false) != true:
			return false
	var library := _dialogue.get_dialogue_library()
	if library == null or library.get_graph(rule.conversation_id) == null:
		push_error(
			"InnerVoiceDirector: rule '%s' points at missing conversation '%s'."
			% [rule.rule_id, rule.conversation_id]
		)
		return false
	return true


func _pump() -> void:
	if _pending.is_empty():
		return
	if _dialogue.is_busy():
		return
	if _sequence != null and _sequence.call("is_beat_active") == true:
		return
	var rule: InnerAbilities.PassiveRule = _pending.pop_front()
	if not _can_fire(rule):
		return
	_fire(rule)


func _fire(rule: InnerAbilities.PassiveRule) -> void:
	if rule.once:
		_set_flag(StoryFlags.passive_fired_flag(rule.rule_id), true)
	var count_flag := StoryFlags.passive_count_flag(rule.ability_id)
	_set_flag(count_flag, int(_flag(count_flag, 0)) + 1)
	_since_voice = 0
	_firing = true
	if not _dialogue.play_conversation(rule.conversation_id):
		_firing = false


func _is_slice_finished() -> bool:
	if _sequence == null:
		return false
	return _sequence.call("is_slice_finished") == true


# --- state ------------------------------------------------------------------


func _flag(flag: StringName, default_value: Variant) -> Variant:
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state == null:
		return default_value
	return game_state.get_flag(flag, default_value)


func _set_flag(flag: StringName, value: Variant) -> void:
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state != null:
		game_state.set_flag(flag, value)


func pending_count() -> int:
	return _pending.size()


func is_firing() -> bool:
	return _firing


func get_abilities() -> InnerAbilities:
	return _abilities

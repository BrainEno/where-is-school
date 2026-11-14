class_name BPresence
extends RefCounted
## When the biology teacher B may be presented, and whether a room's B is on screen (#171).
##
## B is heard about before she is seen. Q's first conversation (`q_wake`) is the player's
## introduction to the lesson and to "the teacher"; nothing that presents B - the imagined
## `expected_b` scene the director plays, or an actor of hers in a room - may come before
## that conversation has ended. Her actual entrance is a separate, explicit story trigger
## (`present()`); this slice has none, so she stays off stage.
##
## Two story flags are the only memory, so a resumed game, a repeated talk with Q and a
## re-entered room all read the same answer:
##
## - `q_first_talk_done`: `false` from Q's first line (when `met_q` is written) until the
##   conversation finishes, then `true`. Absent in saves from before #171 - see
##   `is_introduced()`.
## - `b_on_stage`: written by `present()` only.
##
## A room that holds an actor with npc_id `b` keeps it hidden, not processing (no
## animation, no sound, no collision) and not interactable until both are true. Preloading
## her scene is fine: an instance that is hidden draws nothing and casts no shadow.
##
## It owns no dialogue content and no routing: it listens to what the dialogue controller
## reports and to the flags, which is why Q's conversation and its route (#160) are not
## touched to make this work.

## The biology teacher's actor id, should a room ever hold her.
const ACTOR_ID: StringName = &"b"
## Q's first conversation: the one that has to be over before B is presented.
const Q_FIRST_TALK: StringName = &"q_wake"

var _game_state: Node = null
var _locations: LocationHost = null


func _init(game_state: Node, locations: LocationHost, dialogue: DialogueController) -> void:
	_game_state = game_state
	_locations = locations
	if _game_state != null:
		_game_state.story_flag_changed.connect(_on_story_flag_changed)
		_game_state.story_state_replaced.connect(_on_story_state_replaced)
	if _locations != null:
		_locations.location_entered.connect(_on_location_entered)
	if dialogue != null:
		dialogue.conversation_finished.connect(_on_conversation_finished)


## True once Q's first conversation has run to its end in this run (or in the run an
## older save came from). The gate for everything that presents B.
##
## Saves and snapshots written before #171 have `met_q` but no word on whether Q's first
## conversation ended. A checkpoint is never taken mid-conversation (Session refuses one,
## and autosaves happen between steps), so for them `met_q` means it did. A run that has
## the flag at all - even as `false`, which is what an unfinished talk leaves - is already
## in the new format and is believed as it stands. This is read, not written back: loading
## an older save changes none of its flags.
func is_introduced() -> bool:
	if _game_state == null:
		return false
	if _game_state.has_flag(StoryFlags.Q_FIRST_TALK_DONE):
		return _flag(StoryFlags.Q_FIRST_TALK_DONE)
	return _flag(StoryFlags.MET_Q)


## True when B is allowed to be visible in a room: introduced, then explicitly brought in.
func is_on_stage() -> bool:
	return is_introduced() and _flag(StoryFlags.B_ON_STAGE)


## The explicit story trigger for B's entrance: shows the current room's `b` actor at
## `position_point`, facing `facing_point`, and records it so a reload agrees. Refused
## (false, nothing changes) before Q's first conversation has ended, or when the room has
## no B. Calling it again only moves her: there is one actor, never a second B.
func present(position_point: Vector3, facing_point: Vector3 = Vector3.ZERO) -> bool:
	if not is_introduced():
		push_warning("BPresence: B cannot enter before Q's first conversation has ended.")
		return false
	var actor := find_actor()
	if actor == null:
		push_error("BPresence: the current room has no actor with npc_id 'b'.")
		return false
	_apply(actor, true)
	actor.place_at(position_point, facing_point)
	_game_state.set_flag(StoryFlags.B_ON_STAGE, true)
	return true


## The current room's B, or null - the usual case: no room of this slice has one.
func find_actor() -> NpcActor:
	var location: LocationRoot = _locations.get_current() if _locations != null else null
	return location.find_actor(ACTOR_ID) if location != null else null


## Makes the room's B (if it has one) match the flags.
func sync() -> void:
	var actor := find_actor()
	if actor != null:
		_apply(actor, is_on_stage())


func _apply(actor: NpcActor, present_now: bool) -> void:
	actor.set_visible_actor(present_now)
	actor.process_mode = Node.PROCESS_MODE_INHERIT if present_now else Node.PROCESS_MODE_DISABLED
	# `find_children()`'s type filter does not see script classes; test each node.
	for node in actor.find_children("*", "", true, false):
		var interactable := node as Interactable
		if interactable != null:
			interactable.interaction_enabled = present_now


func _on_conversation_finished(conversation_id: StringName) -> void:
	# `met_q` is written by the first line, so a conversation that failed before showing
	# it (or any other conversation) has not introduced anything.
	if conversation_id == Q_FIRST_TALK and _flag(StoryFlags.MET_Q):
		_game_state.set_flag(StoryFlags.Q_FIRST_TALK_DONE, true)


func _on_story_flag_changed(flag: StringName, _previous: Variant, value: Variant) -> void:
	if flag == StoryFlags.MET_Q:
		# Q has started talking: until the last line the talk is on record as begun but
		# not finished, which keeps B back if the run stops in between.
		if bool(value) and not _game_state.has_flag(StoryFlags.Q_FIRST_TALK_DONE):
			_game_state.set_flag(StoryFlags.Q_FIRST_TALK_DONE, false)
		sync()
	elif flag == StoryFlags.Q_FIRST_TALK_DONE or flag == StoryFlags.B_ON_STAGE:
		sync()


func _on_location_entered(_location: LocationRoot, _spawn_id: StringName) -> void:
	sync()


func _on_story_state_replaced() -> void:
	sync()


func _flag(flag: StringName) -> bool:
	return _game_state != null and bool(_game_state.get_flag(flag, false))

class_name ClassroomChairControl
extends Node
## Sitting back down in the chair the protagonist woke up in.
##
## The room already had an interactable over that chair; it pointed at the schoolbag on the
## back. That is still there, and still what the bag is for - but once the chair can be sat in,
## the same outline answers two questions, so the chair gets its own interactable and this
## script decides which question it is answering at the moment the pointer finds it:
##
##   standing, chair out of the way   → "Sit down": pull the chair home, sit in it
##   seated                          → "Stand up": the ordinary stand-up, which pushes the
##                                     chair back out again
##   mid-transition                  → nothing, so the pointer falls through to the bag
##
## The prompt is recomputed whenever the body's state could have changed, which in practice
## means the door is `_process`-cheap: it compares a small enum and only writes when it moves.
##
## Nothing here writes a story flag or a save field. A chair is furniture: a room loaded again
## starts with the protagonist wherever the save put him and the chair wherever its own script
## left it, which is the same rule the projector screen follows.
##
## The offer is only recomputed when the body is *not* mid-transition and only when it actually
## changed, so this costs a comparison per frame rather than a tree walk.

const PROMPT_SIT := "prompt.sit"
const PROMPT_STAND := "prompt.stand"

@export var chair_path: NodePath = ^"../Furniture/DeskB2/Chair"
@export var seat_interactable_path: NodePath = ^"../Interactables/ChairSit"
## The protagonist, by group: the host adds the player to the room after the room is ready,
## and where it lands is the host's business, not this script's.
@export var player_group: StringName = &"protagonist"

var _chair: Node3D = null
var _seat: Node = null
var _player: Node = null
## What was last written to the interactable, so `_process` does not rewrite it every frame.
var _shown: int = -1


func _ready() -> void:
	_chair = get_node_or_null(chair_path) as Node3D
	_seat = get_node_or_null(seat_interactable_path)
	_player = get_tree().get_first_node_in_group(player_group)
	if _chair == null:
		push_error("ClassroomChairControl: '%s' is missing." % chair_path)
	if _seat == null:
		push_error("ClassroomChairControl: '%s' is missing." % seat_interactable_path)
	if _player == null:
		# The host may add the player a frame after the room, so this is a warning and a
		# deferred retry rather than a hard failure: the room is still usable without it.
		push_warning("ClassroomChairControl: no node in group '%s' yet." % player_group)
	if _chair == null or _seat == null:
		set_process(false)
		return
	# `stage_handler` is a property on `StagedInteractable`, assigned the same way the
	# projector screen's pull cord does it. It does not need the body, so it is wired now.
	_seat.set("stage_handler", _stage_sit)
	_seat.set("chair", _chair)
	if _player == null:
		_bind_player.call_deferred()
		return
	_seat.set("player", _player)
	_update_offer()


## Wires the body up once it exists, for a room that was built before the player was added.
func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group(player_group)
	if _player == null:
		push_warning("ClassroomChairControl: still no '%s'; the chair offers nothing." % player_group)
		return
	_seat.set("player", _player)
	_update_offer()


func _process(_delta: float) -> void:
	# `current_offer` is an enum compare on three booleans; `_update_offer` writes only when the
	# answer changed, so this costs a handful of comparisons per frame and nothing else.
	_update_offer()


## The chair's own interactable was activated, inside the director's beat. Sits down or stands
## up, waits for the body to finish, and reports nothing further for the director to do.
func _stage_sit(_director: Node) -> Dictionary:
	if _player == null:
		return {}
	if bool(_player.call("is_seated")):
		_player.call("stand_up")
		# The stand-up is driven by the clip and by `_physics_process`; wait for the body to
		# report that it is on its feet rather than guessing a duration here.
		await _wait_until(func() -> bool: return not bool(_player.call("is_getting_up")))
	else:
		var tween: Tween = _player.call("sit_down")
		if tween != null:
			await tween.finished
	# The chair moved, and the interactable is anchored in the room rather than under it: its
	# pointer boxes were measured from meshes that are no longer there.
	refresh_pick_shapes()
	_update_offer()
	return {}


## Re-measures the interactable's pointer boxes against where the chair is now.
func refresh_pick_shapes() -> void:
	if _seat != null and _seat.has_method("rebuild_pick_shapes"):
		_seat.call("rebuild_pick_shapes")


func _wait_until(predicate: Callable, timeout: float = 4.0) -> void:
	var elapsed := 0.0
	while not predicate.call() and elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## Rewrites the prompt only when the offer changed. Called every frame, cheap by design.
func _update_offer() -> void:
	if _seat == null or _player == null:
		return
	var offer := int(_seat.call("current_offer"))
	if offer == _shown:
		return
	_shown = offer
	match offer:
		1:  # SIT
			_seat.call("set_prompt", PROMPT_SIT)
			_seat.set("interaction_enabled", true)
		2:  # STAND
			_seat.call("set_prompt", PROMPT_STAND)
			_seat.set("interaction_enabled", true)
		_:
			# Off, not just unprompted: a disabled interactable is skipped by the pointer, so
			# the click passes through to the schoolbag behind it.
			_seat.set("interaction_enabled", false)

class_name CompanionController
extends Node3D
## Q walks with the player between locations.
##
## The companion is deliberately **not** part of any location scene. A location
## swap frees everything under `LocationRoot`, so anything authored inside a
## location would disappear the moment the player walks through a door. This node
## lives on the main scene instead, next to the player, and only ever reports
## itself to the current location.
##
## What Q does, and what Q deliberately does not do:
##
## - follows at a natural distance, speeding up only to catch up;
## - stops when the player stops, and looks around rather than staring;
## - waits instead of teleporting when left far behind, and can be asked along
##   again through one ordinary interaction;
## - never points at anything, never opens a conversation on its own, never
##   comments on a check result. It is company, not a guide or a quest log.
##
## If the current location already has an authored Q (the classroom does), this
## companion hides itself, so two Qs are never visible at once.

signal joined()
signal waiting_changed(waiting: bool)

@export var player_path: NodePath = ^"../Player"
@export var host_path: NodePath = ^"../LocationHost"
@export var actor_path: NodePath = ^"Actor"
@export var ask_along_path: NodePath = ^"AskAlong"
## The actor id this companion stands in for.
@export var npc_id: StringName = &"q"
## Retrieval distance: past this, Q stops chasing and waits to be asked along.
@export var follow_distance: float = 2.6
## Q stops here, so it does not walk into the player's back.
@export var stop_distance: float = 1.8
## Faster than the player's walk (3.6) so being left behind is recoverable.
@export var catch_up_speed: float = 4.4
## Past this separation Q gives up chasing and waits.
@export var give_up_distance: float = 11.0
## How often Q looks somewhere else while standing still.
@export var idle_look_interval: float = 5.0
## Story flag written on the first join, so later visits know Q came along.
@export var joined_flag: StringName = StoryFlags.Q_COMPANION

var _player: Node3D = null
var _host: LocationHost = null
var _actor: NpcActor = null
var _ask: Interactable = null
var _joined := false
var _waiting := false
var _look_timer := 0.0
var _look_aside := false


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	if _player == null:
		push_error("CompanionController: player_path '%s' did not resolve." % player_path)
	_host = get_node_or_null(host_path) as LocationHost
	if _host == null:
		push_error("CompanionController: host_path '%s' did not resolve." % host_path)
	else:
		_host.location_entered.connect(_on_location_entered)
	_actor = get_node_or_null(actor_path) as NpcActor
	_ask = get_node_or_null(ask_along_path) as Interactable
	if _actor == null:
		push_error("CompanionController: actor_path did not resolve to an NpcActor.")
	_refresh_visibility(null)


## Called by the director when the player has actually left the classroom during
## the free period. Idempotent: joining twice does not duplicate anything.
func join() -> void:
	if _joined:
		return
	_joined = true
	_look_timer = 0.0
	_set_waiting(false)
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state != null and not String(joined_flag).is_empty():
		game_state.set_flag(joined_flag, true)
	_refresh_visibility(_host.get_current() if _host != null else null)
	joined.emit()


func is_joined() -> bool:
	return _joined


func is_waiting() -> bool:
	return _waiting


func is_with_player() -> bool:
	return _joined and visible


## True when the companion is far enough behind to be worth asking along.
func can_ask_along() -> bool:
	return _joined and visible and _waiting


## Resumes following. The interaction that calls this is an ordinary conversation;
## afterwards Q simply catches up again.
func resume_following() -> void:
	if not _joined:
		return
	_set_waiting(false)


func _process(delta: float) -> void:
	if not _joined or not visible or _player == null or _actor == null:
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance > give_up_distance:
		if not _waiting:
			_set_waiting(true)
		return
	if _waiting:
		_face_player()
		return
	if distance > follow_distance:
		var direction := to_player / maxf(distance, 0.001)
		var target := _player.global_position - direction * stop_distance
		target.y = global_position.y
		global_position = global_position.move_toward(target, catch_up_speed * delta)
		_actor.face_towards(_player.global_position)
		_look_timer = 0.0
		_look_aside = false
	elif distance > stop_distance:
		# Within the follow band: close the last bit slowly instead of jittering.
		_actor.face_towards(_player.global_position)
		_idle_look(delta)
	else:
		_face_player()
		_idle_look(delta)
	if _ask != null:
		_ask.interaction_enabled = _waiting


## Q does not stare. Every few seconds it looks off to one side and comes back,
## which is enough to read as a person standing with you rather than a statue.
func _idle_look(delta: float) -> void:
	_look_timer += delta
	if _look_timer < idle_look_interval:
		return
	_look_timer = 0.0
	_look_aside = not _look_aside
	if _look_aside:
		var aside := global_position + global_basis.x * 2.0
		_actor.face_towards(aside)
	else:
		_face_player()


func _face_player() -> void:
	if _player != null and _actor != null:
		_actor.face_towards(_player.global_position)


func _set_waiting(value: bool) -> void:
	if _waiting == value:
		return
	_waiting = value
	if _ask != null:
		_ask.interaction_enabled = value
	waiting_changed.emit(_waiting)


## Places Q just behind the player without a walk animation: a location change is
## not something the player can see, so walking Q across the seam would be a lie.
func _place_behind_player() -> void:
	if _player == null or _actor == null:
		return
	var back := _player.global_basis.z
	back.y = 0.0
	if back.length_squared() <= 0.0001:
		back = Vector3.BACK
	global_position = _player.global_position + back.normalized() * stop_distance
	global_position.y = _player.global_position.y
	_face_player()


func _on_location_entered(location: LocationRoot, _spawn_id: StringName) -> void:
	_refresh_visibility(location)


## Q is visible only where it belongs: joined, and not standing in a location that
## already has its own authored Q.
func _refresh_visibility(location: LocationRoot) -> void:
	var authored := location.find_actor(npc_id) if location != null else null
	var should_show := _joined and authored == null
	if should_show:
		_place_behind_player()
	visible = should_show
	_set_waiting(false)
	if _ask != null:
		_ask.interaction_enabled = false

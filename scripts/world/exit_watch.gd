class_name ExitWatch
extends Node
## While a closed exit is refusing the player, the people it names as watching really are.
##
## The classroom door's blocked text says the player takes their hand off the door because
## someone is looking at them. Before this, nobody was: the room stood still while the text
## said otherwise (#174). The exit declares who is watching (`LocationExit.blocked_watcher_ids`
## - only them, never the whole room), and this node runs one watch from the moment the
## blocked text is presented:
##
## - **begins with the text**, in the same frame: each named, visible actor starts turning
##   towards the player's eyes (`NpcActor.watch()`), head first, the body only for what the
##   neck cannot reach. A watcher the game camera cannot see is brought into view by
##   borrowing the framing (`CameraRig.frame_point()`, the rig's existing API for a beat
##   that shows the player where to look) just far enough towards them that both faces
##   show, while the text is up;
## - **follows the player** every frame, wherever they stand, for as long as it lasts;
## - **ends** when the player walks out of the doorway once the text is closed (the zone
##   is the exit's own radius plus a margin, never smaller than where they stood when they
##   tried it), when a beat takes the room, when the exit opens, or when the room goes.
##   The framing goes back to the player as soon as the text closes. Ending lets go of the
##   head and returns the body to its own facing, so nobody stares forever.
##
## The rule that the door does not open is untouched: this only makes the room agree
## with the text.

## The player's eyes above their origin (the protagonist model stands 1.77 m).
const EYE_HEIGHT := 1.6
## How far past the exit's radius the doorway still counts as "at the door".
const ZONE_MARGIN := 1.0
## The doorway never reaches further than this past the exit's radius, however far away
## the attempt was made from.
const ZONE_LIMIT := 2.5
## How much further than where the attempt was made the player may stand.
const ZONE_SLACK := 0.5
## When a watcher is off screen, the view is moved towards them (0 = the player, 1 = the
## watchers) in this many steps until both faces show; half way if no step does. The glide
## takes FRAME_SECONDS, and a face closer to the edge than FRAME_EDGE (of the shorter side)
## does not count as shown.
const FRAME_STEPS := 10
const FRAME_SHARE := 0.5
const FRAME_SECONDS := 0.35
const FRAME_EDGE := 0.05

var _player: PlayerController = null
var _dialogue: DialogueController = null
var _host: Node = null
var _exit: LocationExit = null
var _watchers: Array[NpcActor] = []
var _zone := 0.0
var _framed := false
var _frame_share := 0.0


func setup(player: PlayerController, dialogue: DialogueController, host: Node) -> void:
	_player = player
	_dialogue = dialogue
	_host = host
	set_process(false)


## Starts the watch for `exit`, which has just refused the player in `location`.
func begin(exit: LocationExit, location: LocationRoot) -> void:
	release()
	if exit == null or location == null or _player == null:
		return
	for id in exit.blocked_watcher_ids:
		var actor := location.find_actor(id)
		if actor == null:
			push_warning("ExitWatch: exit '%s' names watcher '%s', who is not in this room." % [exit.interact_id, id])
			continue
		# Someone not in the room yet (N before the lesson) cannot be the one watching.
		if not actor.is_visible_in_tree():
			continue
		_watchers.append(actor)
	if _watchers.is_empty():
		return
	_exit = exit
	_zone = clampf(_planar_distance_to_exit() + ZONE_SLACK, exit.radius + ZONE_MARGIN, exit.radius + ZONE_LIMIT)
	for actor in _watchers:
		actor.watch(_player, EYE_HEIGHT)
	_frame_watchers()
	set_process(true)


func is_watching() -> bool:
	return not _watchers.is_empty()


func get_watchers() -> Array[NpcActor]:
	return _watchers.duplicate()


## How far from the exit the player may stand and still be watched, in metres.
func get_zone_radius() -> float:
	return _zone


func is_framing() -> bool:
	return _framed


## How far towards the watchers the view was moved for the last watch (0: not at all).
func get_frame_share() -> float:
	return _frame_share


## Ends the watch now: heads let go, bodies return, the view goes back to the player.
func release() -> void:
	for actor in _watchers:
		if is_instance_valid(actor):
			actor.stop_watching()
	_watchers.clear()
	_exit = null
	_unframe()
	set_process(false)


func _process(_delta: float) -> void:
	if not is_instance_valid(_exit) or not _exit.is_inside_tree():
		release()
		return
	if _exit.is_open():
		release()
		return
	if _host != null and _host.has_method("is_beat_active") and bool(_host.call("is_beat_active")):
		release()
		return
	var reading := _dialogue != null and _dialogue.is_busy()
	if reading:
		return
	_unframe()
	if _planar_distance_to_exit() > _zone:
		release()


func _planar_distance_to_exit() -> float:
	var offset := _player.global_position - _exit.global_position
	offset.y = 0.0
	return offset.length()


## Moves the view towards the watchers if the game camera cannot see one of them: by the
## smallest share of the way that shows the player's face and theirs, tried as instant
## cuts within this frame (nothing is drawn in between), then glided to.
func _frame_watchers() -> void:
	var rig := _player.camera_rig
	if rig == null or rig.camera == null:
		return
	var centre := Vector3.ZERO
	for actor in _watchers:
		centre += actor.global_position
	centre /= float(_watchers.size())
	_frame_share = 0.0
	if _shows_everyone(rig.camera):
		return
	var share := FRAME_SHARE
	for step in range(1, FRAME_STEPS):
		var candidate := float(step) / float(FRAME_STEPS)
		rig.frame_point(_player.global_position.lerp(centre, candidate), 0.0)
		if _shows_everyone(rig.camera):
			share = candidate
			break
	rig.release_frame(0.0)
	_framed = true
	_frame_share = share
	rig.frame_point(_player.global_position.lerp(centre, share), FRAME_SECONDS)


## True when the player's face and every watcher's are inside the view, clear of its edges.
func _shows_everyone(camera: Camera3D) -> bool:
	if not _in_view(camera, _player.global_position + Vector3.UP * EYE_HEIGHT):
		return false
	for actor in _watchers:
		if not _in_view(camera, actor.global_position + Vector3.UP * EYE_HEIGHT):
			return false
	return true


static func _in_view(camera: Camera3D, point: Vector3) -> bool:
	if camera.is_position_behind(point) or not camera.is_position_in_frustum(point):
		return false
	var rect := camera.get_viewport().get_visible_rect()
	return rect.grow(-minf(rect.size.x, rect.size.y) * FRAME_EDGE).has_point(camera.unproject_position(point))


func _unframe() -> void:
	if not _framed:
		return
	_framed = false
	if _player != null and is_instance_valid(_player) and _player.camera_rig != null:
		_player.camera_rig.release_frame(FRAME_SECONDS)

class_name CharacterFaceDirector
extends Node
## Presentation -> face states and close-up gaze bridge (#387).
##
## `CharacterDialogueAnimation` drives the body; this node drives what a close-up
## actually reads: the directed face state on every visible incarnation (listening to
## the line, a friendly face while speaking, `attention` while the camera holds an
## insert on that actor, and settling to rest when the presentation ends), and the
## insert subject's gaze - while a `camera_focus` insert is held, the actor it is held
## on looks into the camera (from a dialogue insert that is where the player is), and
## lets go when the insert or the conversation ends.
##
## **Order matters:** this node is placed *after* `OpeningSequence` in `main.tscn`, so
## its `line_presented` handler runs after the camera's own bookkeeping and reads the
## glance the frame actually shows - the line that ends a glance is already past it
## here, and the actor's face returns to its line-based state in the same frame.
##
## **Single request writer:** this node only ever *asks* for a state
## (`CharacterLookApplier.set_face_state()`) or for a watch (`NpcActor.watch()`);
## morph weights are composed in one place (`CharacterLookApplier`), and a gaze owned
## by `ExitWatch` is never engaged or released here - a conversation and a refused
## exit cannot hold the player at the same time, so the two never overlap.

@export var controller_path: NodePath = ^"../DialogueController"
@export var sequence_path: NodePath = ^"../OpeningSequence"
@export var player_path: NodePath = ^"../Player"
@export var location_host_path: NodePath = ^"../LocationHost"

## Seconds for a face to enter a state, and to settle out of one. The settle is the
## slower of the two: an expression that leaves as fast as it arrives reads as a cut.
const STATE_BLEND := 0.35
const SETTLE_BLEND := 0.45
## Where a face's eyes are, for the player the camera stands in for (same height
## `ExitWatch` aims at).
const EYE_HEIGHT := 1.6

var _controller: DialogueController = null
var _sequence: OpeningSequence = null
var _player: PlayerController = null
var _locations: LocationHost = null
## The actor whose gaze this node engaged on an insert (null when it owns none).
var _gaze_actor: NpcActor = null


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as DialogueController
	_sequence = get_node_or_null(sequence_path) as OpeningSequence
	_player = get_node_or_null(player_path) as PlayerController
	_locations = get_node_or_null(location_host_path) as LocationHost
	if _controller == null or _sequence == null:
		push_error("CharacterFaceDirector: needs a DialogueController and an OpeningSequence.")
		return
	_controller.line_presented.connect(_on_line_presented)
	_controller.presentation_active_changed.connect(_on_presentation_active_changed)
	_on_line_presented(_controller.get_current_line() if _controller.is_busy() else {})


func _on_line_presented(line: Dictionary) -> void:
	var speaker := StringName(String(line.get("speaker_id", "")))
	if bool(line.get("subjective", false)):
		speaker = &""
	var focus := _sequence.get_camera_focus()
	var glance := focus.get_glance() if focus != null else null
	var glance_actor := _actor_of(glance)
	for node in get_tree().get_nodes_in_group("npc_actor"):
		var actor := node as NpcActor
		if actor == null:
			continue
		var animator := actor.get_character_animator()
		if animator != null:
			_apply_state(animator, line, speaker, actor == glance_actor, actor.npc_id)
	for node in get_tree().get_nodes_in_group("seated_dialogue_speaker"):
		var visual := node as CharacterVisualAnimation
		if visual != null:
			_apply_state(visual, line, speaker, false, visual.dialogue_speaker_id)
	if _player != null:
		var visual := _player.get_character_animator()
		if visual != null:
			_apply_state(visual, line, speaker, false, &"protagonist")
	_sync_gaze(glance_actor)


## Asks one incarnation's applier for the state this line puts it in: `attention`
## while the camera holds an insert on it (the line's own state is next, so a look
## without an `attention` table still reacts to the line), `friendly` when it is the
## speaker, `listening` when someone else is, and a settle when nobody is speaking or
## the incarnation is gone. A look with no face states (N, the seated student) is
## skipped rather than given another character's.
func _apply_state(animator: CharacterVisualAnimation, line: Dictionary, speaker: StringName,
		in_insert: bool, own_id: StringName) -> void:
	var applier := animator.get_node_or_null(^"Look") as CharacterLookApplier
	if applier == null or applier.look == null or applier.look.face_states.is_empty():
		return
	if line.is_empty() or not animator.is_visible_in_tree():
		applier.clear_face_state(SETTLE_BLEND)
		return
	if in_insert and applier.set_face_state(&"attention", STATE_BLEND):
		return
	if not speaker.is_empty() and speaker == own_id:
		applier.set_face_state(&"friendly", STATE_BLEND)
	elif speaker.is_empty():
		applier.clear_face_state(SETTLE_BLEND)
	else:
		applier.set_face_state(&"listening", STATE_BLEND)


## The insert's subject looks into the lens while the insert is held; anything else
## lets go of the gaze this node engaged (and only that one).
func _sync_gaze(glance_actor: NpcActor) -> void:
	var wanted := glance_actor \
		if glance_actor != null and glance_actor.is_visible_in_tree() else null
	if _gaze_actor != null and is_instance_valid(_gaze_actor) and _gaze_actor != wanted:
		_gaze_actor.stop_watching()
		_gaze_actor = null
	if wanted == null:
		return
	var camera := _camera()
	if camera == null:
		push_warning("CharacterFaceDirector: insert gaze on '%s' found no camera to look into."
			% String(wanted.npc_id))
		return
	wanted.watch(camera, 0.0)
	_gaze_actor = wanted


func _on_presentation_active_changed(active: bool) -> void:
	if not active:
		# An empty line settles every face and releases the gaze this node engaged;
		# the camera's glance is already gone by here (OpeningSequence runs first).
		_on_line_presented({})


## The interactable's actor, when the glance is held on one that names a speaker.
func _actor_of(subject: Interactable) -> NpcActor:
	if subject == null or _locations == null or String(subject.speaker_id).is_empty():
		return null
	var room := _locations.get_current()
	return room.find_actor(subject.speaker_id) if room != null else null


## The game camera - a dialogue insert's point of view, and therefore where the
## player's eyes are from inside the shot. The rig is the normal answer; a viewport
## lookup covers a rig that has not bound yet, and is still the camera on screen.
func _camera() -> Camera3D:
	if _player != null and _player.camera_rig != null and _player.camera_rig.camera != null:
		return _player.camera_rig.camera
	if is_inside_tree():
		return get_viewport().get_camera_3d()
	return null

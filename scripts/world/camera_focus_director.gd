class_name CameraFocusDirector
extends RefCounted
## Decides when the game camera focuses on an important interaction (see `CameraShot`).
##
## The rule is small on purpose: a shot is engaged when the player activates an
## interactable that carries one, held for as long as the player is locked by what that
## interaction started (its beat, its conversation, its inspection text), and released
## the moment the player gets control back. Walking past, hovering or highlighting never
## moves the camera - the framing only changes when the game has taken the controls
## anyway, so a shot can never fight the player's own steering.
##
## The lock is the director's (`OpeningSequence.sync_player_locks`), which reports every
## change here. An activation that never ends up locking the player (refused, or an error
## path) is released on the next frame instead of hanging on. A location change drops the
## shot at once (`clear`), alongside `release_frame`.
##
## A conversation can also ask for a short look of its own (`glance`, from a dialogue
## `camera_focus` effect): the camera turns to an object of the room while the next line
## is read, then goes back to what the conversation was framed on. Nothing is stored; a
## glance never outlives the conversation that asked for it.

## Glide and framing for a glance at an object that carries no `CameraShot` of its own.
const GLANCE_SUBJECT_MIX := 0.72
const GLANCE_DISTANCE_SCALE := 0.72
const GLANCE_FOV := 46.0
## Lines a glance holds for: the one shown when it starts, then it lets go as the next
## one appears.
const GLANCE_LINES := 1

var _rig: CameraRig = null
var _subject: Interactable = null
## Whether the player has been locked since the shot was engaged; only then does an
## unlock mean "the interaction is over".
var _lock_seen := false
## The interactable a conversation asked to look at, and how many lines have been shown
## since. Null when no glance is held.
var _glance: Interactable = null
var _glance_lines := 0
var _glance_nameplate: CharacterNameplate = null


func _init(rig: CameraRig) -> void:
	_rig = rig


## Called for every activation the director accepts. A subject without a shot leaves the
## framing alone (and releases a shot still held from a previous moment).
func engage(interactable: Interactable) -> void:
	if _rig == null or interactable == null:
		return
	var shot := interactable.camera_shot
	if shot == null:
		return
	_subject = interactable
	_lock_seen = false
	_rig.focus_on(interactable, shot)
	_release_if_never_locked.call_deferred(interactable)


## Called whenever the player's lock is recomputed.
func on_lock_changed(locked: bool) -> void:
	if _subject == null and _glance == null:
		return
	if locked:
		_lock_seen = true
	elif _lock_seen:
		release()


## Glides back to the default framing.
func release() -> void:
	_subject = null
	_drop_glance()
	_lock_seen = false
	if _rig != null:
		_rig.release_focus()


## Back to the default framing at once (location change).
func clear() -> void:
	_subject = null
	_drop_glance()
	_lock_seen = false
	if _rig != null:
		_rig.clear_focus()


## Looks at `subject` for the line that is about to be shown (a dialogue `camera_focus`
## effect). Prefer an authored insert for this room and subject; ordinary activation still
## uses the wide interaction shot. A missing insert cannot stop or prolong the dialogue.
func glance(subject: Interactable, shot: CameraShot = null) -> void:
	if _rig == null or subject == null:
		return
	_drop_glance()
	var insert := shot if shot != null else subject.dialogue_shot
	if insert != null and _rig.focus_on(subject, insert):
		if not insert.insert_nameplate_path.is_empty():
			_glance_nameplate = subject.get_node_or_null(insert.insert_nameplate_path) as CharacterNameplate
			if _glance_nameplate != null:
				_glance_nameplate.set_hidden_for_insert(true)
	else:
		var fallback := subject.camera_shot if subject.camera_shot != null else glance_shot()
		_rig.focus_on(subject, fallback)
	_glance = subject
	_lock_seen = true


## Called for every dialogue line that reaches the screen; ends a glance once the line it
## was asked for has been read.
func on_line_presented() -> void:
	if _glance == null:
		return
	_glance_lines += 1
	if _glance_lines > GLANCE_LINES:
		end_glance()


## Gives the framing back to the interaction's own shot, or to the default.
func end_glance() -> void:
	if _glance == null:
		return
	_drop_glance()
	if _rig == null:
		return
	if is_instance_valid(_subject) and _subject.camera_shot != null:
		_rig.focus_on(_subject, _subject.camera_shot)
	else:
		_rig.release_focus()


func _drop_glance() -> void:
	if is_instance_valid(_glance_nameplate):
		_glance_nameplate.set_hidden_for_insert(false)
	_glance_nameplate = null
	_glance = null
	_glance_lines = 0


## The interactable a glance is held on, or null.
func get_glance() -> Interactable:
	return _glance


## The framing for a glance at an object without a shot of its own.
static func glance_shot() -> CameraShot:
	var shot := CameraShot.new()
	shot.subject_mix = GLANCE_SUBJECT_MIX
	shot.distance_scale = GLANCE_DISTANCE_SCALE
	shot.fov = GLANCE_FOV
	return shot


## The interactable whose shot is held, or null.
func get_subject() -> Interactable:
	return _subject


func _release_if_never_locked(interactable: Interactable) -> void:
	if _subject == interactable and not _lock_seen:
		release()

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

var _rig: CameraRig = null
var _subject: Interactable = null
## Whether the player has been locked since the shot was engaged; only then does an
## unlock mean "the interaction is over".
var _lock_seen := false


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
	if _subject == null:
		return
	if locked:
		_lock_seen = true
	elif _lock_seen:
		release()


## Glides back to the default framing.
func release() -> void:
	_subject = null
	_lock_seen = false
	if _rig != null:
		_rig.release_focus()


## Back to the default framing at once (location change).
func clear() -> void:
	_subject = null
	_lock_seen = false
	if _rig != null:
		_rig.clear_focus()


## The interactable whose shot is held, or null.
func get_subject() -> Interactable:
	return _subject


func _release_if_never_locked(interactable: Interactable) -> void:
	if _subject == interactable and not _lock_seen:
		release()

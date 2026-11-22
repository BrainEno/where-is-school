extends StagedInteractable
## A silent look, not a conversation or an inspection text. The normal staged beat
## holds the controls and returns from the authored shot; it writes no story state.

@export_range(0.1, 15.0, 0.05) var hold_seconds: float = 2.15


func _ready() -> void:
	if camera_shot == null:
		push_error("Camera look '%s' needs a camera_shot." % interact_id)
		interaction_enabled = false
	else:
		stage_handler = _hold_view
	super._ready()


func _hold_view(director: Node) -> Dictionary:
	await director.wait_seconds(camera_shot.glide_seconds + hold_seconds)
	return {}

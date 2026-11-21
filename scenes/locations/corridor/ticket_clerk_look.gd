extends StagedInteractable
## Observe the clerk without asking her to stop, speak or sell anything. The normal
## staged beat owns both the control lock and the return from the authored shot.

const FACE_HOLD_SECONDS := 2.15


func _ready() -> void:
	stage_handler = _hold_view
	super._ready()


func _hold_view(director: Node) -> Dictionary:
	await director.wait_seconds(camera_shot.glide_seconds + FACE_HOLD_SECONDS)
	return {}

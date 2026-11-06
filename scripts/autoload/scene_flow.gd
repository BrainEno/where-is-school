extends Node
## Scene transition service shared by all location scenes.
## Fades the screen out, swaps the active scene, and fades back in.
## Story state is NOT stored here; it lives in GameState and survives the swap.
## Carries an optional spawn identifier so the destination scene can place
## the player without knowing which location it came from.

signal travel_started(target_scene: String)
signal travel_finished(target_scene: String)

const FADE_TIME: float = 0.45

var _overlay: CanvasLayer = null
var _fade_rect: ColorRect = null
var _traveling: bool = false
var _pending_spawn_id: StringName = &""


func _ready() -> void:
	# Persist across scene changes; process always so fades never freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	_overlay.name = "SceneFlowOverlay"
	add_child(_overlay)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.modulate = Color(1, 1, 1, 0)
	_overlay.add_child(_fade_rect)


func travel(target_scene: String, spawn_id: StringName = &"") -> void:
	if _traveling:
		push_error("SceneFlow.travel called while a transition is already running.")
		return
	if not ResourceLoader.exists(target_scene):
		push_error("SceneFlow.travel: scene does not exist: %s" % target_scene)
		return
	_traveling = true
	_pending_spawn_id = spawn_id
	travel_started.emit(target_scene)
	await _fade_to(1.0)
	var err := get_tree().change_scene_to_file(target_scene)
	if err != OK:
		push_error("SceneFlow.travel: change_scene_to_file(%s) failed with error %d." % [target_scene, err])
		_traveling = false
		await _fade_to(0.0)
		return
	# Wait one frame so the new scene is in the tree before fading in.
	await get_tree().process_frame
	await _fade_to(0.0)
	_traveling = false
	travel_finished.emit(target_scene)


func consume_spawn_id() -> StringName:
	var spawn_id: StringName = _pending_spawn_id
	_pending_spawn_id = &""
	return spawn_id


func begin_fade_in() -> void:
	## Used by the very first scene to fade from black on game start.
	_fade_rect.modulate = Color(1, 1, 1, 1)
	_fade_to(0.0)


func _fade_to(alpha: float) -> void:
	if _fade_rect == null:
		return
	var tween := create_tween()
	var target := Color(1, 1, 1, alpha)
	tween.tween_property(_fade_rect, "modulate", target, FADE_TIME)
	await tween.finished

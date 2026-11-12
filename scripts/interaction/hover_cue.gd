class_name HoverCue
extends Node3D
## The cue on the object the player can use right now - the thing E would act on.
##
## It is an outline traced around the object itself, in the manner of Disco Elysium: the
## object's own silhouette gets a thin warm line, a dark rim and a faint wash, and nothing
## is added to the floor. The previous cue was a dashed ring on the ground with a halo and
## a floating diamond; the owner rejected it because a big circle next to a timetable says
## "here is a circle", not "this sheet". An outline can only mean the thing it traces.
##
## Which meshes are traced is the interactable's decision (`Interactable.get_outline_meshes`:
## its `outline_paths`, else its `support_paths`, plus anything parented under it). How
## they are traced is `OutlineOverlay`'s. This node only owns the fade and the hand-over:
##
## * `reveal()` collects the meshes *now* - a character's model is instanced at runtime and a
##   placeholder may have been hidden since the last time - hands them to the overlay and
##   fades the outline in;
## * `conceal()` fades it out and releases the meshes. If another object was highlighted in
##   the meantime the overlay already belongs to it, and the release is ignored there.
##
## An object with nothing visible to trace (content still being built) falls back to a
## small tumbling diamond above it, so it is never silently unmarked. Every shipped
## interactable is checked to resolve to at least one mesh, so the fallback is a safety net
## and never the design.

const REVEAL_SECONDS := 0.12
const CONCEAL_SECONDS := 0.16
## The fallback diamond: its size, its height above the object's origin, its motion.
const SHARD_SIZE := 0.045
const SHARD_HEIGHT := 0.35
const SHARD_TUMBLE_DEGREES_PER_SECOND := 26.0
const BOB_HEIGHT := 0.05
const BOB_SECONDS := 2.6

var _source: Interactable = null
var _revealed: bool = false
var _opacity: float = 0.0
var _tween: Tween = null
var _meshes: Array[GeometryInstance3D] = []
var _overlay: OutlineOverlay = null
var _shard: MeshInstance3D = null
var _time: float = 0.0


## Ties the cue to the object whose meshes it outlines. Without a source the cue still
## fades and reports its state, and always draws the fallback.
func bind(source: Interactable) -> void:
	_source = source


func is_revealed() -> bool:
	return _revealed


func get_opacity() -> float:
	return _opacity


## The meshes the outline was drawn on the last time the cue was revealed. Empty when the
## fallback was used instead.
func get_outline_meshes() -> Array[GeometryInstance3D]:
	return _meshes.duplicate()


## True when the last reveal traced the object's meshes rather than falling back.
func is_outlining() -> bool:
	return not _meshes.is_empty()


func get_overlay() -> OutlineOverlay:
	return _overlay


func get_parts() -> Dictionary:
	return {"shard": _shard}


func _ready() -> void:
	visible = false
	set_process(false)


func reveal() -> void:
	_revealed = true
	_meshes.clear()
	if _source != null:
		_meshes = _source.get_outline_meshes()
	_overlay = OutlineOverlay.for_node(self) if not _meshes.is_empty() else null
	if _overlay != null:
		_overlay.show_meshes(self, _meshes)
	else:
		_meshes.clear()
		_ensure_shard()
	if _shard != null:
		_shard.visible = _overlay == null
	visible = true
	set_process(true)
	_fade_to(1.0, REVEAL_SECONDS)


## Fades the outline out. `immediate` skips the fade, for a room that is going away.
func conceal(immediate: bool = false) -> void:
	_revealed = false
	if immediate or not is_inside_tree():
		_kill_tween()
		_set_opacity(0.0)
		_finish()
		return
	_fade_to(0.0, CONCEAL_SECONDS)


func _process(delta: float) -> void:
	_time += delta
	if _shard == null or not _shard.visible:
		return
	_shard.rotation.y = deg_to_rad(SHARD_TUMBLE_DEGREES_PER_SECOND) * _time
	_shard.position.y = SHARD_HEIGHT + sin(_time * TAU / BOB_SECONDS) * BOB_HEIGHT


func _fade_to(target: float, seconds: float) -> void:
	_kill_tween()
	if not is_inside_tree():
		_set_opacity(target)
		if target <= 0.0:
			_finish()
		return
	_tween = create_tween()
	_tween.tween_method(_set_opacity, _opacity, target, seconds)
	if target <= 0.0:
		_tween.tween_callback(_finish)


func _set_opacity(value: float) -> void:
	_opacity = clampf(value, 0.0, 1.0)
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.set_opacity(self, _opacity)
	if _shard != null:
		_shard.transparency = 1.0 - _opacity


func _finish() -> void:
	if _revealed:
		return
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.release(self)
	_overlay = null
	visible = false
	set_process(false)


func _ensure_shard() -> void:
	if _shard != null:
		return
	_shard = MeshInstance3D.new()
	_shard.name = "Shard"
	_shard.mesh = WorldCue.shard_mesh(SHARD_SIZE)
	_shard.material_override = WorldCue.material_for(WorldCue.ROLE_TARGET)
	_shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shard.position = Vector3(0.0, SHARD_HEIGHT, 0.0)
	_shard.transparency = 1.0
	add_child(_shard)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _exit_tree() -> void:
	# A room being freed takes its interactables with it; the overlay lives in the main
	# scene and must not keep marking meshes that are about to disappear.
	_kill_tween()
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.release(self)
	_overlay = null

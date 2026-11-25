class_name HoverCue
extends Node3D
## The cue on the object the player can use right now - the thing E would act on.
##
## Three looks, chosen by the object (`Interactable.CueStyle`, `docs/ARCHITECTURE.md, "Marker or outline"`):
##
## * **Marker** (things to look at, controls): a small green ring with a pale dot, sitting on
##   the middle of the object - Disco Elysium's look mark. It is a billboard of constant pixel
##   size (`assets/shaders/interaction/look_marker.gdshader`) and follows the object if it
##   moves. The owner asked for it in round 24: the outline on every prop and every window
##   made the whole hall light up under a wandering cursor.
## * **Talk** (a person to talk to, `Interactable.uses_talk_cue`): the same marker, pen and
##   size, drawn as a small green speech bubble with three dots above the person's head
##   (`Interactable.get_talk_marker_position`) - Disco Elysium's talk mark. It follows the
##   person as they walk to their talk spot.
## * **Outline** (ways out: doors, gates, stairs): the object's own silhouette gets a thin
##   warm line, a dark rim and a faint wash, and nothing is added to the floor. The cue
##   before that was a dashed ring on the ground with a halo and a floating diamond; the
##   owner rejected it because a big circle next to a timetable says "here is a circle",
##   not "this sheet". The marker is not that circle: it is small and on the thing itself.
##
## Which meshes are traced is the interactable's decision (`Interactable.get_outline_meshes`:
## its `outline_paths`, else its `support_paths`, plus anything parented under it). How
## they are traced is `OutlineOverlay`'s. This node only owns the fade and the hand-over:
##
## * `reveal()` collects the meshes *now* - a character's model is instanced at runtime and a
##   placeholder may have been hidden since the last time - hands them to the overlay (or
##   places the marker on them) and fades the cue in;
## * `conceal()` fades it out and releases the meshes. If another object was highlighted in
##   the meantime the overlay already belongs to it, and the release is ignored there.
##
## An outlined object with nothing visible to trace (content still being built) falls back
## to a small tumbling diamond above it, so it is never silently unmarked. Every shipped
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
const MARKER_SHADER := preload("res://assets/shaders/interaction/look_marker.gdshader")
## The ring's diameter in pixels at a 900-pixel-high window (the shader scales it with the
## window). Small on purpose: a mark on the thing, not a target painted over it.
const MARKER_PIXEL_SIZE := 24.0
const MARKER_COLOR := Color(0.55, 0.92, 0.5, 1.0)
const MARKER_PULSE_SECONDS := 1.8

var _source: Interactable = null
var _revealed: bool = false
var _opacity: float = 0.0
var _tween: Tween = null
var _meshes: Array[GeometryInstance3D] = []
var _overlay: OutlineOverlay = null
var _shard: MeshInstance3D = null
var _marker: MeshInstance3D = null
var _marker_material: ShaderMaterial = null
var _marking: bool = false
var _talking: bool = false
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


## True when the last reveal traced the object's meshes rather than marking or falling back.
func is_outlining() -> bool:
	return not _marking and not _meshes.is_empty()


## True when the last reveal drew the small ring instead of an outline.
func is_marking() -> bool:
	return _marking


## True when the last reveal drew the talk bubble (a marker, but for a person to talk to).
func is_talking() -> bool:
	return _talking


## The ring, or null when this cue has never marked anything. Public for tests.
func get_marker() -> MeshInstance3D:
	return _marker


func get_overlay() -> OutlineOverlay:
	return _overlay


func get_parts() -> Dictionary:
	return {"shard": _shard, "marker": _marker}


func _ready() -> void:
	visible = false
	set_process(false)


func reveal() -> void:
	_revealed = true
	_meshes.clear()
	if _source != null:
		_meshes = _source.get_outline_meshes()
	_marking = _source != null and _source.uses_marker_cue()
	_talking = _marking and _source.uses_talk_cue()
	if _marking:
		# A previous outline reveal of this same object may still own the overlay.
		if _overlay != null and is_instance_valid(_overlay):
			_overlay.release(self)
		_overlay = null
		_ensure_marker()
		_marker_material.set_shader_parameter(&"glyph", 1 if _talking else 0)
		_place_marker()
	else:
		_overlay = OutlineOverlay.for_node(self) if not _meshes.is_empty() else null
		if _overlay != null:
			_overlay.show_meshes(self, _meshes)
		else:
			_meshes.clear()
			_ensure_shard()
	if _shard != null:
		_shard.visible = not _marking and _overlay == null
	if _marker != null:
		_marker.visible = _marking
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
	if _marking and _marker != null:
		_place_marker()
		_marker_material.set_shader_parameter(
			&"pulse", 0.5 + 0.5 * sin(_time * TAU / MARKER_PULSE_SECONDS)
		)
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
	if _marker_material != null:
		_marker_material.set_shader_parameter(&"opacity", _opacity)


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


## The ring is built once per object, the first time it is marked. Its material is its own
## because the opacity is a shader parameter (the per-node `transparency` is not applied to a
## custom shader on every renderer the game ships for).
func _ensure_marker() -> void:
	if _marker != null:
		return
	_marker_material = ShaderMaterial.new()
	_marker_material.shader = MARKER_SHADER
	_marker_material.set_shader_parameter(&"ring_color", MARKER_COLOR)
	_marker_material.set_shader_parameter(&"pixel_size", MARKER_PIXEL_SIZE)
	_marker_material.set_shader_parameter(&"opacity", _opacity)
	_marker_material.set_shader_parameter(&"pulse", 0.0)
	_marker_material.render_priority = Material.RENDER_PRIORITY_MAX
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_marker = MeshInstance3D.new()
	_marker.name = "Marker"
	_marker.mesh = quad
	_marker.material_override = _marker_material
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader sizes the quad in pixels, so far away it is wider than one metre.
	_marker.extra_cull_margin = 4.0
	# Placed in world space on the object's centre, whatever the anchor's transform is.
	_marker.top_level = true
	add_child(_marker)


func _place_marker() -> void:
	if _marker == null or _source == null or not _marker.is_inside_tree():
		return
	var at := _source.get_talk_marker_position() if _talking else _source.get_marker_position()
	_marker.global_transform = Transform3D(Basis.IDENTITY, at)


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

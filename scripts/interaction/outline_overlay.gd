class_name OutlineOverlay
extends CanvasLayer
## Draws the outline around the object the player can use right now.
##
## The owner asked for the highlight to trace the object's own silhouette, the way Disco
## Elysium does, instead of a ring on the floor next to it. This node is how that outline is
## made, for any mesh and without touching a single prop:
##
## 1. The meshes to outline get one extra visual layer bit (`MASK_LAYER`). The main camera
##    sees every layer, so nothing changes in the frame the player sees.
## 2. `Mask`, a `SubViewport` in the same world, renders *only* that layer from a camera that
##    copies the player's camera every frame, unshaded, over a transparent background. Its
##    alpha channel is the object's silhouette in screen space.
## 3. `Ink`, a full-screen `ColorRect`, runs `assets/shaders/interaction/highlight_outline.gdshader`
##    over that silhouette and draws a thin warm line just outside it, a dark rim outside
##    that, and a faint wash over the object.
##
## Why not the inverted-hull trick the environment already uses for its ink lines
## (`assets/shaders/painterly/environment_outline.gdshader`): growing a box along its split
## normals tears the outline open at every corner, and half the interactables in this game
## are boxes. Why not the stencil outline in `BaseMaterial3D`: it would need a material
## change on every highlighted surface and it does not exist in the Compatibility renderer
## the capture run uses. The mask costs one extra render of a handful of meshes, and only
## while something is highlighted - the viewport is not updated at all otherwise.
##
## One object is outlined at a time, because the interaction controller highlights one at a
## time. `show_meshes` from a new owner replaces the previous owner's meshes at once; the
## fade belongs to the owner (`HoverCue`), which drives `set_opacity`.
##
## The node normally lives in `scenes/main/main.tscn`. A scene run on its own (a test that
## builds one interactable on the root) gets one created on demand by `for_node`.

## Visual layer 20 (bit 19). Nothing else in the project uses it; `tests/interaction_outline_content_test.gd`
## checks that no shipped mesh is authored on it.
const MASK_LAYER := 1 << 19
const GROUP := &"outline_overlay"
const SHADER := preload("res://assets/shaders/interaction/highlight_outline.gdshader")
## The pen at 900 px of screen height; it scales with the window so a 4K screen does not get
## a hairline.
const LINE_PX := 2.0
const RIM_PX := 1.5
const REFERENCE_HEIGHT := 900.0

static var _fallback: WeakRef = null

var _mask: SubViewport = null
var _mask_camera: Camera3D = null
var _ink: ColorRect = null
var _ink_material: ShaderMaterial = null
var _owner_ref: WeakRef = null
## Mesh -> the visual layers it had before it was marked, so releasing it restores exactly
## what the scene authored.
var _marked: Dictionary = {}
var _opacity: float = 0.0


## The overlay serving `node`'s tree: the one in the main scene if there is one, otherwise
## one created under the root for this run.
static func for_node(node: Node) -> OutlineOverlay:
	if node == null or not node.is_inside_tree():
		return null
	var tree := node.get_tree()
	var found := tree.get_first_node_in_group(GROUP) as OutlineOverlay
	if found != null and not found.is_queued_for_deletion():
		return found
	if _fallback != null:
		var pending := _fallback.get_ref() as OutlineOverlay
		if pending != null and is_instance_valid(pending) and not pending.is_queued_for_deletion():
			return pending
	var created := OutlineOverlay.new()
	created.name = "OutlineOverlay"
	_fallback = weakref(created)
	# Deferred: the request usually arrives from inside a physics step, where the root may
	# be busy. The overlay accepts meshes before it is in the tree and applies them in
	# `_ready`.
	tree.root.add_child.call_deferred(created)
	return created


func _init() -> void:
	layer = 0
	add_to_group(GROUP)


func _ready() -> void:
	_build()
	_refresh()


## Marks `meshes` for the outline on behalf of `owner_object`, replacing whatever another
## owner had marked. Meshes that are not visible are skipped: outlining a hidden placeholder
## would draw the shape of something the player cannot see.
func show_meshes(owner_object: Object, meshes: Array[GeometryInstance3D]) -> void:
	_clear_marks()
	_owner_ref = weakref(owner_object) if owner_object != null else null
	for mesh in meshes:
		if mesh == null or not is_instance_valid(mesh) or _marked.has(mesh):
			continue
		_marked[mesh] = mesh.layers
		mesh.layers = mesh.layers | MASK_LAYER
	_refresh()


## Ends `owner_object`'s outline. A stale owner (one that was already replaced) is ignored,
## so a fade-out that finishes late cannot erase the next object's outline.
func release(owner_object: Object) -> void:
	if not is_owned_by(owner_object):
		return
	_clear_marks()
	_owner_ref = null
	_opacity = 0.0
	_refresh()


## The outline's opacity, 0..1. Only the current owner may set it.
func set_opacity(owner_object: Object, value: float) -> void:
	if not is_owned_by(owner_object):
		return
	_opacity = clampf(value, 0.0, 1.0)
	_refresh()


func get_opacity() -> float:
	return _opacity


func is_owned_by(owner_object: Object) -> bool:
	return owner_object != null and _owner_ref != null and _owner_ref.get_ref() == owner_object


## True while an outline is being drawn: something is marked and it is not fully faded.
func is_active() -> bool:
	return not _live_meshes().is_empty() and _opacity > 0.0


## The meshes currently carrying the outline. Public for tests and the capture run.
func get_meshes() -> Array[GeometryInstance3D]:
	return _live_meshes()


func get_mask_viewport() -> SubViewport:
	return _mask


func _process(_delta: float) -> void:
	if not is_active():
		return
	_sync_camera()


func _build() -> void:
	if _mask != null:
		return
	_mask = SubViewport.new()
	_mask.name = "Mask"
	_mask.transparent_bg = true
	_mask.own_world_3d = false
	_mask.disable_3d = false
	_mask.gui_disable_input = true
	_mask.handle_input_locally = false
	_mask.msaa_3d = Viewport.MSAA_DISABLED
	_mask.positional_shadow_atlas_size = 0
	# Unshaded: the mask only needs coverage, and lighting it would cost a second shadow
	# pass for nothing.
	_mask.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_mask)

	_mask_camera = Camera3D.new()
	_mask_camera.name = "MaskCamera"
	_mask_camera.cull_mask = MASK_LAYER
	# Its own environment, so the room's fog, glow and background colour never reach the
	# mask: only coverage, over nothing.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_mask_camera.environment = environment
	_mask.add_child(_mask_camera)
	_mask_camera.current = true

	_ink = ColorRect.new()
	_ink.name = "Ink"
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ink.color = Color(1, 1, 1, 1)
	_ink_material = ShaderMaterial.new()
	_ink_material.shader = SHADER
	_ink_material.set_shader_parameter("mask", _mask.get_texture())
	_ink_material.set_shader_parameter("line_color", WorldCue.OUTLINE_COLOR)
	_ink_material.set_shader_parameter("rim_color", WorldCue.OUTLINE_RIM_COLOR)
	_ink.material = _ink_material
	_ink.visible = false
	add_child(_ink)


func _refresh() -> void:
	if _mask == null:
		return
	var active := is_active()
	_ink.visible = active
	_mask.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	)
	_ink_material.set_shader_parameter("opacity", _opacity)
	if active:
		_sync_camera()


## The mask has to be the same picture as the frame, pixel for pixel, or the outline
## floats off the object: same size, same camera, every frame.
func _sync_camera() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var frame := Vector2i(viewport.get_visible_rect().size)
	if frame.x > 0 and frame.y > 0 and _mask.size != frame:
		_mask.size = frame
	var pen_scale := maxf(float(frame.y) / REFERENCE_HEIGHT, 1.0)
	_ink_material.set_shader_parameter("line_px", LINE_PX * pen_scale)
	_ink_material.set_shader_parameter("rim_px", RIM_PX * pen_scale)
	var source := viewport.get_camera_3d()
	if source == null:
		return
	_mask_camera.global_transform = source.global_transform
	_mask_camera.projection = source.projection
	_mask_camera.fov = source.fov
	_mask_camera.size = source.size
	_mask_camera.near = source.near
	_mask_camera.far = source.far
	_mask_camera.keep_aspect = source.keep_aspect
	_mask_camera.h_offset = source.h_offset
	_mask_camera.v_offset = source.v_offset


func _live_meshes() -> Array[GeometryInstance3D]:
	var live: Array[GeometryInstance3D] = []
	for key: Variant in _marked.keys():
		if is_instance_valid(key):
			live.append(key as GeometryInstance3D)
	return live


func _clear_marks() -> void:
	for key: Variant in _marked.keys():
		if is_instance_valid(key):
			var mesh := key as GeometryInstance3D
			mesh.layers = int(_marked[key])
	_marked.clear()


func _exit_tree() -> void:
	# The meshes outlive the overlay only in a test that frees it first; give them their
	# layers back either way.
	_clear_marks()
	_owner_ref = null
	_opacity = 0.0

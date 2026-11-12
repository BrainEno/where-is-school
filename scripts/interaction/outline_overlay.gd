class_name OutlineOverlay
extends CanvasLayer
## Draws the outline around the object the player can use right now.
##
## The owner asked for the highlight to trace the object's own silhouette, the way Disco
## Elysium does, instead of a ring on the floor next to it. This node is how that outline is
## made, for any mesh and without touching a single prop:
##
## 1. The meshes to outline get one extra visual layer bit (`MASK_LAYER`), given back exactly
##    as it was on release, and a twin: an internal child that draws the same mesh on
##    `MASK_LAYER` only, with the key material (`KEY_SHADER_CODE`), freed on release. The
##    mesh's own materials and overlay are not touched. The player's camera never draws
##    `MASK_LAYER` (the overlay clears that bit from it) and the key collapses itself for any
##    camera but the mask's, so nothing changes in the frame the player sees.
## 2. `Mask`, a `SubViewport` in the same world, renders the scene from a camera that copies the
##    player's camera every frame - unshaded, and only as far as the farthest highlighted mesh,
##    because nothing behind the object can hide it. That fills its depth buffer with what is
##    in front of the object. A full-screen quad (`BLANK_SHADER_CODE`, on `MASK_LAYER` only)
##    then paints the colour black without touching depth, and the twins, drawn last with the
##    depth test on, paint white exactly where the highlighted meshes are the nearest surface. Its red channel is the *visible* part of the object's silhouette.
## 3. `Ink`, a full-screen `ColorRect`, runs `assets/shaders/interaction/highlight_outline.gdshader`
##    over that silhouette and draws a thin warm line just outside it, a dark rim outside
##    that, and a faint wash over the object. Because the mask is depth-tested, an object
##    behind a wall has no outline, and one half behind a post is outlined only where it shows.
##
## Why the mask renders the scene again instead of reading the frame's depth: the outline is
## composited in 2D, over the tonemapped frame, so that its colours are exactly the colours
## below. A canvas shader cannot read the 3D depth buffer, and a 3D pass that could (a
## `hint_depth_texture` quad in the main view) would be tonemapped, glowed and colour-adjusted
## with the room, so the warm line would change colour from room to room. The extra pass only
## runs while something is highlighted, without lights (`DEBUG_DRAW_UNSHADED` drops them) or
## shadows (the viewport has no shadow atlas, and the engine prepares no shadow maps for a
## viewport without one), and its far plane stops at the object. Nothing in it needs more than
## Godot's Compatibility renderer offers: overlay materials, `CAMERA_VISIBLE_LAYERS`,
## `POSITION`, render priority.
##
## Why not the inverted-hull trick the environment already uses for its ink lines
## (`assets/shaders/painterly/environment_outline.gdshader`): growing a box along its split
## normals tears the outline open at every corner, and half the interactables in this game
## are boxes. Why not the stencil outline in `BaseMaterial3D`: it would need a material
## change on every highlighted surface. The viewport is not updated at all while nothing is
## highlighted.
##
## One object is outlined at a time, because the interaction controller highlights one at a
## time. `show_meshes` from a new owner replaces the previous owner's meshes at once; the
## fade belongs to the owner (`HoverCue`), which drives `set_opacity`.
##
## The node normally lives in `scenes/main/main.tscn`. A scene run on its own (a test that
## builds one interactable on the root) gets one created on demand by `for_node`.

## Visual layer 20 (bit 19). Nothing else in the project uses it; `tests/interaction_outline_content_test.gd`
## checks that no shipped mesh is authored on it. The two mask shaders below test the same
## bit (524288) against `CAMERA_VISIBLE_LAYERS`; change all three together.
const MASK_LAYER := 1 << 19
const GROUP := &"outline_overlay"
const SHADER := preload("res://assets/shaders/interaction/highlight_outline.gdshader")

## The key: the highlighted meshes' own pixels in the mask, drawn by each mesh's twin. It is
## a transparent-pass material, so it is drawn after the scene's opaque geometry, with the
## depth test on, over the same surface as the mesh: it lands exactly on the parts of the mesh
## that are in front of everything else and on nothing a wall or a desk hides. That is the
## whole of the occlusion: the depth buffer the mask pass has just filled, used the way every
## overlay uses it. No depth texture is read.
##
## It moves itself off screen for any camera that does not see `MASK_LAYER` - the player's
## camera never does - so in the frame the player sees it costs a vertex pass, no pixels. The
## small pull towards the camera (2 mm + 1 mm per metre of distance, along the view ray, so
## no pixel moves) keeps it from losing the depth test to the very surface it covers: its
## vertex code is not the mesh material's, and two programs need not round alike.
const KEY_SHADER_CODE := """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

const uint MASK_LAYER = 524288u;
uniform float pull_m = 0.002;
uniform float pull_per_m = 0.001;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float distance_m = length(view.xyz);
	if (distance_m > 0.0001) {
		view.xyz -= view.xyz / distance_m * (pull_m + pull_per_m * distance_m);
	}
	POSITION = PROJECTION_MATRIX * view;
	if ((CAMERA_VISIBLE_LAYERS & MASK_LAYER) == 0u) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = 1.0;
}
"""

## The blank: a full-screen quad on `MASK_LAYER` that paints the mask black after the scene
## was drawn into it for depth. It neither tests nor writes depth, so the depth buffer
## survives for the key, and it sorts after every other transparent surface. Its corners are
## (-1, -1)..(1, 1), straight to clip space; z = 0.5 is inside the clip volume for both depth
## conventions. Mask camera only, like the key.
const BLANK_SHADER_CODE := """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, blend_mix;

const uint MASK_LAYER = 524288u;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
	if ((CAMERA_VISIBLE_LAYERS & MASK_LAYER) == 0u) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 1.0;
}
"""
## Transparent surfaces draw in ascending priority. The scene's own sit at 0 (one nameplate at
## 1); the blank goes over all of them and the key over the blank.
const BLANK_PRIORITY := Material.RENDER_PRIORITY_MAX - 1
const KEY_PRIORITY := Material.RENDER_PRIORITY_MAX
## How far past the farthest corner of the highlighted meshes the mask camera still draws.
const FAR_MARGIN := 1.0
## The pen at 900 px of screen height; it scales with the window so a 4K screen does not get
## a hairline.
const LINE_PX := 2.0
const RIM_PX := 1.5
const REFERENCE_HEIGHT := 900.0

static var _fallback: WeakRef = null

var _mask: SubViewport = null
var _mask_camera: Camera3D = null
var _blank: MeshInstance3D = null
var _key_material: ShaderMaterial = null
var _ink: ColorRect = null
var _ink_material: ShaderMaterial = null
var _owner_ref: WeakRef = null
## Mesh -> what it had before it was marked ({"layers": int, "overlay": Material or null}),
## so releasing it restores exactly what the scene authored.
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
	# Late in the frame: the mask camera copies the player's camera after everything that
	# moves it this frame has run.
	process_priority = 1000
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
		var twin := _make_twin(mesh)
		_marked[mesh] = {
			"layers": mesh.layers,
			"overlay": mesh.material_overlay,
			"twin": twin,
		}
		mesh.layers = mesh.layers | MASK_LAYER
		if twin == null:
			mesh.material_overlay = _keyed(mesh.material_overlay)
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


func get_mask_camera() -> Camera3D:
	return _mask_camera


## The material the overlay puts at the end of a marked mesh's overlay chain.
func get_key_material() -> ShaderMaterial:
	_ensure_key_material()
	return _key_material


## The key's carrier for a mesh: an internal child that draws the same mesh, with the same
## skeleton and skin, on `MASK_LAYER` only, with the key as its material. The mesh itself -
## its materials and its own overlay (the classroom desks share one) - is not touched. Null
## for a geometry that is not a `MeshInstance3D` (none of the outlined ones today); that one
## gets the key appended to its overlay chain instead (`_keyed`).
func _make_twin(mesh: GeometryInstance3D) -> MeshInstance3D:
	_ensure_key_material()
	var source := mesh as MeshInstance3D
	if source == null or source.mesh == null:
		return null
	var twin := MeshInstance3D.new()
	twin.name = "OutlineKey"
	twin.mesh = source.mesh
	twin.skin = source.skin
	twin.material_override = _key_material
	twin.layers = MASK_LAYER
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	twin.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	twin.extra_cull_margin = source.extra_cull_margin
	twin.custom_aabb = source.custom_aabb
	twin.lod_bias = source.lod_bias
	twin.visibility_range_begin = source.visibility_range_begin
	twin.visibility_range_end = source.visibility_range_end
	# Internal: `get_children` and `get_child_count` do not see it, so the interactable's own
	# mesh collection and pick boxes never count it. (`find_children` does list internal
	# children; `_process` keeps the one walk that matters - the occluder fader - off it.)
	source.add_child(twin, false, Node.INTERNAL_MODE_BACK)
	var skeleton := source.get_node_or_null(source.skeleton) if not source.skeleton.is_empty() else null
	if skeleton != null:
		twin.skeleton = twin.get_path_to(skeleton)
	return twin


## The twins standing in for the marked meshes in the mask (tests look at them).
func get_key_twins() -> Array[MeshInstance3D]:
	var twins: Array[MeshInstance3D] = []
	for key: Variant in _marked.keys():
		var twin: Variant = (_marked[key] as Dictionary)["twin"]
		if twin != null and is_instance_valid(twin):
			twins.append(twin as MeshInstance3D)
	return twins


## The mesh's own overlay with the key appended, or the key alone. The authored overlay is
## copied rather than changed: it may be shared by every desk in the room (the classroom's
## ink overlay is), and only this mesh is highlighted.
func _keyed(authored: Material) -> Material:
	_ensure_key_material()
	if authored == null:
		return _key_material
	var head := authored.duplicate() as Material
	var tail := head
	while tail.next_pass != null:
		tail.next_pass = tail.next_pass.duplicate() as Material
		tail = tail.next_pass
	tail.next_pass = _key_material
	return head


static func _shader(code: String) -> Shader:
	var shader := Shader.new()
	shader.code = code
	return shader


func _ensure_key_material() -> void:
	if _key_material != null:
		return
	_key_material = ShaderMaterial.new()
	_key_material.shader = _shader(KEY_SHADER_CODE)
	_key_material.render_priority = KEY_PRIORITY


func _process(_delta: float) -> void:
	if not is_active():
		return
	_sync_camera()
	# The camera's occluder fader dims whole branches it finds with `find_children`, which
	# also returns internal children. A twin must stay opaque: a dimmed key would leave a
	# faint mask, and the outline is not the fader's to dim.
	for twin in get_key_twins():
		if twin.transparency != 0.0:
			twin.transparency = 0.0


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
	# Unshaded: the mask only needs depth and coverage. Lights are dropped from the pass.
	_mask.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_mask)

	_mask_camera = Camera3D.new()
	_mask_camera.name = "MaskCamera"
	# The whole scene, so that what stands in front of the object is in the depth buffer;
	# `_sync_camera` keeps it equal to the player's camera's layers plus `MASK_LAYER`.
	_mask_camera.cull_mask = (1 << 20) - 1
	# Its own environment, so the room's fog, glow and background colour never reach the
	# mask: only coverage, over nothing.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_mask_camera.environment = environment
	_mask.add_child(_mask_camera)
	_mask_camera.current = true

	_blank = MeshInstance3D.new()
	_blank.name = "MaskBlank"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_blank.mesh = quad
	var blank_material := ShaderMaterial.new()
	blank_material.shader = _shader(BLANK_SHADER_CODE)
	blank_material.render_priority = BLANK_PRIORITY
	_blank.material_override = blank_material
	# On `MASK_LAYER` only while an outline is up (`_refresh`): at rest nothing in the tree
	# sits on the reserved layer.
	_blank.layers = 0
	_blank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blank.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The shader places it on the whole screen; the margin keeps the engine from culling it
	# by the small box it occupies in the scene.
	_blank.extra_cull_margin = 16384.0
	_blank.position = Vector3(0.0, 0.0, -1.0)
	_blank.visible = false
	_mask_camera.add_child(_blank, false, Node.INTERNAL_MODE_BACK)

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
	# Camera first: it takes `MASK_LAYER` off the player's camera before the blank quad on
	# that layer becomes visible to it.
	if active:
		_sync_camera()
	_blank.visible = active
	_blank.layers = MASK_LAYER if active else 0
	_ink.visible = active
	_mask.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	)
	_ink_material.set_shader_parameter("opacity", _opacity)


## The mask has to be the same picture as the frame, pixel for pixel, or the outline
## floats off the object: same size, same camera, every frame. The far plane is the one
## exception: it stops just past the object, which changes which pixels have depth behind the
## object (none are needed) and not where anything lands on screen.
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
	# The player's camera must not draw the mask's own quad. Nothing authored is on this
	# layer (`interaction_outline_content_test`), so clearing it changes nothing else.
	if source.cull_mask & MASK_LAYER != 0:
		source.cull_mask = source.cull_mask & ~MASK_LAYER
	_mask_camera.cull_mask = source.cull_mask | MASK_LAYER
	_mask.mesh_lod_threshold = viewport.mesh_lod_threshold
	_mask_camera.global_transform = source.global_transform
	_mask_camera.projection = source.projection
	_mask_camera.fov = source.fov
	_mask_camera.size = source.size
	_mask_camera.near = source.near
	_mask_camera.far = _far_plane(source)
	_mask_camera.keep_aspect = source.keep_aspect
	_mask_camera.h_offset = source.h_offset
	_mask_camera.v_offset = source.v_offset


## Just past the farthest corner of the marked meshes, never beyond the player's own far plane.
func _far_plane(source: Camera3D) -> float:
	var eye := source.global_position
	var farthest := 0.0
	for mesh in _live_meshes():
		var box := mesh.get_aabb()
		var to_world := mesh.global_transform
		for corner in 8:
			var point := to_world * box.get_endpoint(corner)
			farthest = maxf(farthest, eye.distance_to(point))
	if farthest <= 0.0:
		return source.far
	return clampf(farthest + FAR_MARGIN, source.near + FAR_MARGIN, source.far)


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
			var authored: Dictionary = _marked[key]
			mesh.layers = int(authored["layers"])
			var twin: Variant = authored["twin"]
			if twin == null:
				mesh.material_overlay = authored["overlay"] as Material
			elif is_instance_valid(twin):
				var node := twin as Node
				node.get_parent().remove_child(node)
				node.queue_free()
	_marked.clear()


func _exit_tree() -> void:
	# The meshes outlive the overlay only in a test that frees it first; give them their
	# layers back either way.
	_clear_marks()
	_owner_ref = null
	_opacity = 0.0

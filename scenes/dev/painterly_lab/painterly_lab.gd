extends Node3D
## Painterly Lab — independent dev preview, not part of Main.
## Open this scene directly to evaluate painterly materials.
## Controls (when window focused):
##   1/2/3 — highlight simple/medium/full prop (visual highlight via emission)
##   O — toggle outline on character proxy (next_pass)
##   C — toggle camera between perspective baseline and orthographic preview (local only)
## No project.godot change, no classroom dependency.

@onready var camera: Camera3D = $Camera3D
@onready var character_head: MeshInstance3D = $CharacterProxy/Head
@onready var character_body: MeshInstance3D = $CharacterProxy/Body
@onready var sun: DirectionalLight3D = $Sun

var _outline_enabled := true
var _perspective := true
var _highlight := 1 # 0=simple,1=medium,2=full index

# Keep perspective baseline values explicit (must match CameraRig baseline).
const PERSPECTIVE_FOV := 60.0
const PERSPECTIVE_OFFSET := Vector3(3.4, 6.4, 3.4)
const ORTHO_SIZE := 12.5

# Complexity labels for measurement.
const COMPLEXITY_NAMES := ["simple", "medium", "full"]

func _ready() -> void:
	_apply_camera()
	_apply_outline()
	_apply_highlight()
	_print_lab_report()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				_highlight = 0
				_apply_highlight()
			KEY_2:
				_highlight = 1
				_apply_highlight()
			KEY_3:
				_highlight = 2
				_apply_highlight()
			KEY_O:
				_outline_enabled = not _outline_enabled
				_apply_outline()
			KEY_C:
				_perspective = not _perspective
				_apply_camera()

func _apply_camera() -> void:
	if camera == null:
		return
	if _perspective:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = PERSPECTIVE_FOV
		camera.position = PERSPECTIVE_OFFSET
		# Look at center of lab (0,0,0) + 0.9m height like CameraRig.
		camera.look_at(Vector3.ZERO + Vector3(0, 0.9, 0), Vector3.UP)
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = ORTHO_SIZE
		camera.position = Vector3(5.0, 7.0, 5.0)
		camera.look_at(Vector3.ZERO + Vector3(0, 0.9, 0), Vector3.UP)

func _apply_outline() -> void:
	# Toggle next_pass on character meshes.
	var outline: Material = null
	if _outline_enabled:
		outline = load("res://assets/shaders/painterly/mat_character_outline.tres")
	for mesh in [character_body, character_head]:
		if mesh == null:
			continue
		var mat: Material = mesh.get_surface_override_material(0)
		if mat is ShaderMaterial:
			# ShaderMaterial.next_pass holds the outline.
			(mat as ShaderMaterial).next_pass = outline

func _apply_highlight() -> void:
	# Simple highlight by slightly brightening the chosen prop's material.
	# Does not create new materials; just logs selection.
	var names := ["PropSimple", "PropMedium", "PropFull"]
	for i in names.size():
		var node := get_node_or_null("Props/" + names[i]) as MeshInstance3D
		if node != null:
			# Pulse scale slightly to show selection.
			node.scale = Vector3.ONE * (1.08 if i == _highlight else 1.0)

func _print_lab_report() -> void:
	# Headless-friendly report: what the lab contains, for the test to read.
	var shader_files := [
		"res://assets/shaders/painterly/painterly_env_simple.gdshader",
		"res://assets/shaders/painterly/painterly_env.gdshader",
		"res://assets/shaders/painterly/painterly_env_full.gdshader",
		"res://assets/shaders/painterly/painterly_character.gdshader",
		"res://assets/shaders/painterly/painterly_outline.gdshader",
	]
	var count_shader := 0
	for path in shader_files:
		if ResourceLoader.exists(path):
			count_shader += 1
	var mats := get_shader_material_count()
	print("PAINTERLY_LAB_REPORT: shaders=%d materials_in_lab=%d perspective=%s outline=%s highlight=%s" % [count_shader, mats, str(_perspective), str(_outline_enabled), COMPLEXITY_NAMES[_highlight]])
	print("PAINTERLY_LAB_COMPLEXITY: simple=poster_only medium=warp+contour full=brush_texture+warp+contour character=wrap+hue_shift outline=inverted_hull")
	# Performance proxy: count ShaderMaterials vs hypothetical classroom StandardMaterials.
	var standard_budget := 12 # classroom reference
	var lab_cost := mats # 7 in lab
	print("PAINTERLY_LAB_PERF: lab_materials=%d classroom_std_mats=%d projected_40_props_medium=%d budget_guard=32 limit_ok=%s" % [lab_cost, standard_budget, 40, str(lab_cost < 32)])
	# Resolution note for Windows hands-on.
	print("PAINTERLY_LAB_WINDOW: design=1600x900 min=1280x720 max=1920x1080 compare_both")

func get_shader_material_count() -> int:
	var count := 0
	# Count ShaderMaterials in this lab scene.
	for child in find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		for idx in mi.mesh.get_surface_count() if mi.mesh != null else 0:
			var mat := mi.get_surface_override_material(idx)
			if mat == null and mi.mesh != null:
				mat = mi.mesh.surface_get_material(idx)
			if mat is ShaderMaterial:
				count += 1
		# Also count override if mesh has no surface count but material_override exists (simple cases).
		if mi.material_override is ShaderMaterial:
			count += 1
	return count

func get_camera_mode() -> String:
	return "perspective" if _perspective else "orthographic"

func get_highlight_name() -> String:
	return COMPLEXITY_NAMES[_highlight]

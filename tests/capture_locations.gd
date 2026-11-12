extends SceneTree
## Photographs every non-classroom location from the game's own camera, plus one wide
## establishing view, so an environment art change can be compared before and after.
##
## Not an assertion suite and not part of the headless checks. It needs a real window:
##
##   xvfb-run -a godot --path . --resolution 1600x900 --rendering-driver opengl3 \
##     --script res://tests/capture_locations.gd -- label=after
##
## The standing spots are derived from the scene, not written down here, so the same
## script photographs an older commit at the same places: every spawn marker, plus the
## navigation mesh's centre and two points along its long axis (snapped to the mesh).
## A spawn and a derived spot closer than `MIN_SPACING` metres are one spot. The HUD is
## hidden: the frames are about the space, and the HUD is the same in every location.
##
## Output: res://docs/screenshots/map_art/<label>/<location>_<nn>_<spot>.jpg and an
## index, LOCATIONS.md, in the same folder. `docs/` is ignored by the importer.

const Harness = preload("res://tests/test_harness.gd")

const OUT_ROOT := "res://docs/screenshots/map_art"
const LOCATIONS := [
	["corridor", "res://scenes/locations/corridor/corridor.tscn"],
	["street", "res://scenes/locations/street/street.tscn"],
	["residential", "res://scenes/locations/residential/residential.tscn"],
	["alley", "res://scenes/locations/alley/alley.tscn"],
	["playground", "res://scenes/locations/playground/playground.tscn"],
]
const MIN_SPACING := 4.5
## The wide view looks along the game camera's own bearing, from further away.
const WIDE_FOV := 46.0

var _max_spots := 5
## Frames are scaled to this width before saving (0 keeps the window size). CI uses a
## smaller frame because it publishes the JPEGs inline, through annotations.
var _width := 0
var _quality := 0.9
var _only := ""

var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null
var _rig: Node3D = null
var _label := "capture"
var _lines: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 600.0, "capture_locations.gd")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("label="):
			_label = arg.substr(6).strip_edges()
		elif arg.begins_with("spots="):
			_max_spots = maxi(1, int(arg.substr(6)))
		elif arg.begins_with("width="):
			_width = maxi(0, int(arg.substr(6)))
		elif arg.begins_with("quality="):
			_quality = clampf(float(arg.substr(8)), 0.3, 1.0)
		elif arg.begins_with("only="):
			_only = arg.substr(5).strip_edges()
	call_deferred("_run")


func _run() -> void:
	var out_dir := "%s/%s" % [OUT_ROOT, _label]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null:
		_finish(["State autoloads are unavailable."])
		return
	Harness.clear_session_state(self)
	var loc := Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	if loc != null:
		loc.set_locale("en")
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_finish(["main.tscn could not be loaded."])
		return
	_main = packed.instantiate()
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(_main)
	await _wait(0.3)
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_rig = _main.get_node_or_null("CameraRig") as Node3D
	if _host == null or _player == null or _rig == null:
		_finish(["main.tscn did not expose LocationHost, Player and CameraRig."])
		return
	var ui := _main.get_node_or_null("GameUI")
	if ui is CanvasLayer:
		(ui as CanvasLayer).visible = false
	_lines.append("# Location frames: %s" % _label)
	_lines.append("")
	_lines.append("Captured by `tests/capture_locations.gd` under Xvfb (opengl3, 1600x900).")
	_lines.append("The game camera frames stand the player on each spot; `wide` looks along")
	_lines.append("the same bearing from further away. HUD hidden.")
	_lines.append("")
	for entry: Array in LOCATIONS:
		if not _only.is_empty() and String(entry[0]) != _only:
			continue
		await _capture_location(String(entry[0]), String(entry[1]), out_dir)
	var file := FileAccess.open("%s/LOCATIONS.md" % out_dir, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	_finish(_failures)


func _capture_location(location_id: String, scene_path: String, out_dir: String) -> void:
	if not _host.load_location(scene_path, &"", _player, StringName(location_id)):
		_failures.append("%s did not load" % location_id)
		return
	await _wait(1.2)
	var current := _host.get_current()
	var spots := _spots(current)
	_lines.append("## %s" % location_id)
	_lines.append("")
	var index := 0
	for spot: Array in spots:
		_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(-45.0)), spot[1]))
		await _wait(0.5)
		if _rig.has_method("snap"):
			_rig.call("snap")
		await _wait(0.4)
		var shot_name := "%s_%02d_%s" % [location_id, index, spot[0]]
		_save(out_dir, shot_name)
		_lines.append("- `%s.jpg` (%s) at %s" % [shot_name, spot[0], str(spot[1])])
		index += 1
	await _wide(current, location_id, out_dir)
	_lines.append("")


## Spawn markers first, then the derived spots, each at least MIN_SPACING from the rest.
func _spots(current: LocationRoot) -> Array:
	var spots: Array = []
	for spawn_id: StringName in current.get_spawn_ids():
		var marker := current.get_spawn(spawn_id)
		if marker != null:
			_add_spot(spots, String(spawn_id).to_snake_case(), marker.global_position)
	var bounds := _nav_bounds(current)
	var region := current.get_node_or_null("Navigation") as NavigationRegion3D
	if bounds.size != Vector3.ZERO and region != null:
		var map := region.get_navigation_map()
		var long_x := bounds.size.x >= bounds.size.z
		var centre := bounds.get_center()
		var derived := {"centre": centre}
		for t: float in [0.2, 0.8]:
			var point := centre
			if long_x:
				point.x = bounds.position.x + bounds.size.x * t
			else:
				point.z = bounds.position.z + bounds.size.z * t
			derived["axis_%d" % int(t * 100.0)] = point
		for key: String in derived:
			var snapped := NavigationServer3D.map_get_closest_point(map, derived[key])
			_add_spot(spots, key, snapped)
	return spots.slice(0, _max_spots)


func _add_spot(spots: Array, label: String, position: Vector3) -> void:
	for existing: Array in spots:
		if (existing[1] as Vector3).distance_to(position) < MIN_SPACING:
			return
	spots.append([label, position + Vector3(0.0, 0.05, 0.0)])


func _nav_bounds(current: LocationRoot) -> AABB:
	var region := current.get_node_or_null("Navigation") as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		return AABB()
	var vertices := region.navigation_mesh.get_vertices()
	if vertices.is_empty():
		return AABB()
	var box := AABB(region.global_transform * vertices[0], Vector3.ZERO)
	for vertex: Vector3 in vertices:
		box = box.expand(region.global_transform * vertex)
	return box


func _wide(current: LocationRoot, location_id: String, out_dir: String) -> void:
	var bounds := _nav_bounds(current)
	if bounds.size == Vector3.ZERO:
		_failures.append("%s has no baked navigation to frame" % location_id)
		return
	var bearing := Vector3(3.4, 6.4, 3.4).normalized()
	if _rig.get("offset") is Vector3:
		bearing = (_rig.get("offset") as Vector3).normalized()
	var radius := Vector2(bounds.size.x, bounds.size.z).length() * 0.5
	var distance := radius / tan(deg_to_rad(WIDE_FOV * 0.5)) * 0.95
	var camera := Camera3D.new()
	camera.name = "LocationCaptureCamera"
	camera.fov = WIDE_FOV
	camera.far = 600.0
	_main.add_child(camera)
	var target := bounds.get_center()
	camera.global_position = target + bearing * distance
	camera.look_at(target, Vector3.UP)
	camera.current = true
	await _wait(0.4)
	var shot_name := "%s_wide" % location_id
	_save(out_dir, shot_name)
	_lines.append("- `%s.jpg` (wide) looking at %s from %.1f m" % [shot_name, str(target), distance])
	camera.queue_free()
	await _wait(0.1)


func _save(out_dir: String, name: String) -> void:
	RenderingServer.force_draw(true)
	var image: Image = root.get_texture().get_image()
	if image == null:
		_failures.append("no image for %s" % name)
		return
	if _width > 0 and image.get_width() > _width:
		var height := int(round(float(image.get_height()) * _width / image.get_width()))
		image.resize(_width, height, Image.INTERPOLATE_LANCZOS)
	var err := image.save_jpg("%s/%s.jpg" % [out_dir, name], _quality)
	if err != OK:
		_failures.append("%s could not be saved (error %d)" % [name, err])
		return
	print("LOCATION_CAPTURE %s (%dx%d)" % [name, image.get_width(), image.get_height()])


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame
	await process_frame


func _finish(failures: Array) -> void:
	Harness.finish(self, failures, "location frames written for %s" % _label)

extends Node3D
## Visual experiments lab — "a school assembled from other media".
##
## A standalone art and rendering study, not part of the game. Four rooms in a row, each a
## different answer to "what if this place did not have to match the last one":
##
##   A  Collage room      paper sheets, torn edges, reprinted textures, cut-out furniture
##   B  Corridor          repetition, scale that does not hold, a door too large, a loop
##   C  Staff room        expressionist colour fields, one hard light, painted lies
##   D  Threshold         an ordinary 3D classroom, a doorway, a stage of painted flats;
##                        crossing it switches the medium from 3D to painting
##
## The rooms are open-topped, like a set seen from the flies, so one overview shows them
## all. Each room swaps the WorldEnvironment as you enter it — a separate "renderer mood"
## per space, at the cost of one property assignment.
##
## You walk through it as the game's protagonist, in third person (`observer.gd`): each
## room asks the follow camera for its own framing, the way every location in the game
## authors its camera angle. Narrow passages get a low chase framing so the walls do not
## hide the character.
##
## Controls (also on the HUD): WASD walk relative to the camera, Shift jog, Q/E turn the
## view, mouse orbits (click; Esc releases), wheel zoom, R reset the view, F free camera,
## 1-8 stations, M force the medium switch, H hide the HUD, P print a performance sample.
##
## Nothing in the game references this scene. It lives under `scenes/dev/`, which every
## export preset excludes; `tests/visual_experiments_test.gd` checks both.

const Kit := preload("res://scenes/dev/visual_experiments/collage_kit.gd")

const ZONE_OUTSIDE := &"outside"
const ZONE_COLLAGE := &"collage"
const ZONE_CORRIDOR := &"corridor"
const ZONE_EXPRESSION := &"expression"
const ZONE_CLASSROOM := &"classroom"
const ZONE_STAGE := &"stage"

## Each zone's footprint in world XZ: [zone, Rect2(x, z, width, depth)].
const ZONE_RECTS: Array = [
	[&"collage", Rect2(-6.5, -12.0, 13.0, 18.0)],
	[&"corridor", Rect2(-1.6, -56.5, 3.2, 44.5)],
	[&"expression", Rect2(1.6, -47.5, 18.5, 15.0)],
	[&"classroom", Rect2(20.1, -46.5, 16.2, 13.0)],
	[&"stage", Rect2(36.3, -47.5, 16.0, 15.0)],
]

## The follow camera's framing per room: (yaw, pitch, distance). Yaw 0 puts the camera
## south of the character (+Z), 90 east, -90 west. The game's own is (45, 53, 8).
const ZONE_FRAMINGS := {
	&"outside": Vector3(30.0, 50.0, 8.0),
	&"collage": Vector3(15.0, 50.0, 7.5),
	&"corridor": Vector3(0.0, 16.0, 4.2),
	&"expression": Vector3(-35.0, 58.0, 9.0),
	&"classroom": Vector3(-30.0, 58.0, 6.5),
	&"stage": Vector3(-70.0, 32.0, 7.0),
}
## Behind the flats the stage's own framing would look at their painted fronts from the
## wrong side; this one looks back at the plywood from the east.
const STAGE_FRAMING_BACK := Vector3(110.0, 40.0, 6.0)
## Places inside a room that want another framing: [Rect2(x, z, width, depth), framing],
## checked before the zone's. Passages too narrow to look into from above get a low chase
## framing looking along them; the strip behind the flats looks back at them.
const PASSAGE_FRAMINGS: Array = [
	[Rect2(1.6, -41.2, 6.4, 2.4), Vector3(-90.0, 14.0, 4.5)],
	[Rect2(20.1, -41.0, 6.0, 2.0), Vector3(-90.0, 14.0, 4.5)],
	[Rect2(49.8, -47.5, 2.5, 15.0), STAGE_FRAMING_BACK],
]

## Stations: id, the character's feet, where it faces, the camera (a framing, or
## `Vector3.ZERO` for the room's own; the overview is a free camera: [eye, look]).
const STATIONS: Array = [
	[&"overview", Vector3(0.0, 0.0, 4.2), Vector3(0.0, 0.0, -6.0),
		[Vector3(-14.0, 30.0, 14.0), Vector3(22.0, 0.0, -28.0)]],
	[&"start", Vector3(0.0, 0.0, 4.2), Vector3(0.0, 0.0, -6.0), Vector3.ZERO],
	[&"collage", Vector3(2.4, 0.0, -3.4), Vector3(-2.0, 0.0, -8.0), Vector3.ZERO],
	[&"corridor", Vector3(0.0, 0.0, -16.5), Vector3(0.0, 0.0, -50.0), Vector3.ZERO],
	[&"expression", Vector3(11.0, 0.0, -37.6), Vector3(15.0, 0.0, -41.0), Vector3.ZERO],
	[&"threshold", Vector3(31.5, 0.0, -40.0), Vector3(40.0, 0.0, -40.0), Vector3.ZERO],
	[&"stage", Vector3(41.0, 0.0, -39.6), Vector3(48.0, 0.0, -40.5), Vector3.ZERO],
	[&"backstage", Vector3(51.6, 0.0, -45.6), Vector3(45.0, 0.0, -39.0), Vector3.ZERO],
]

const ZONE_NOTES := {
	&"outside": "Between rooms: the stage floor the set is built on.",
	&"collage": "A  Collage - paper sheets (procedural shader), reprinted game textures, Sprite3D cut-outs, Y-billboard pupils, a Decal seal.",
	&"corridor": "B  Surreal corridor - MultiMesh doors shrinking 15% each, a door taller than the wall, a SubViewport window, a 40 m loop.",
	&"expression": "C  Expressionist - vertex-colour fields, leaning walls, one shadowed SpotLight through a slot, painted shadow and painted light.",
	&"classroom": "D  Threshold (3D side) - real models, plaster, a picture that is a live SubViewport of the stage.",
	&"stage": "D  Threshold (painted side) - the 3D view is rendered at half size and painted on canvas; the flats are still solid.",
}

var _environments: Dictionary = {}
var _sun_energy: Dictionary = {}
var _zone: StringName = &""
var _hud_clock: float = 0.0
var _manual_medium: bool = false
var _framing_key: Vector3 = Vector3(-1.0, -1.0, -1.0)

@onready var observer: CharacterBody3D = $Observer
@onready var medium_switch: Node = $MediumSwitch
@onready var collage: Node3D = $Zones/Collage
@onready var corridor: Node3D = $Zones/Corridor
@onready var expression: Node3D = $Zones/Expression
@onready var threshold: Node3D = $Zones/Threshold
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _hud: CanvasLayer = $HUD
@onready var _hud_text: Label = $HUD/Panel/Text


func _ready() -> void:
	_build_ground()
	_build_environments()
	_sun.rotation_degrees = Vector3(-56.0, 32.0, 0.0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 90.0
	medium_switch.call("bind", observer.get("camera"))
	threshold.connect("threshold_changed", _on_threshold_changed)
	corridor.call("aim_window", Vector3(0.0, 10.5, -1.0), Vector3(0.0, 0.0, -6.5))
	threshold.call("aim_stage_window")
	go_to_station(&"start")
	print(
		(
			"VISUAL_LAB ready renderer=%s driver=%s sheets=%d cut_outs=%d generated_textures=%d"
			+ " (%.0f KiB)"
		)
		% [
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_current_rendering_driver_name(),
			(collage.get("sheets") as Array).size(),
			(collage.get("cut_outs") as Array).size(),
			Kit.generated_count(),
			Kit.generated_bytes() / 1024.0,
		]
	)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	var plane := PlaneMesh.new()
	plane.size = Vector2(150.0, 150.0)
	var visual := MeshInstance3D.new()
	visual.name = "StageFloor"
	visual.mesh = plane
	visual.material_override = Kit.flat(Color(0.09, 0.085, 0.08))
	visual.position = Vector3(22.0, -0.01, -26.0)
	ground.add_child(visual)
	add_child(ground)


func _build_environments() -> void:
	# [zone, background, ambient colour, ambient energy, sun energy, fog density]
	var moods: Array = [
		[ZONE_OUTSIDE, Color(0.1, 0.095, 0.09), Color(0.8, 0.76, 0.7), 0.6, 1.0, 0.0],
		[ZONE_COLLAGE, Color(0.16, 0.14, 0.12), Color(0.95, 0.88, 0.75), 0.45, 0.85, 0.0],
		[ZONE_CORRIDOR, Color(0.11, 0.14, 0.12), Color(0.62, 0.7, 0.65), 0.55, 0.8, 0.045],
		[ZONE_EXPRESSION, Color(0.04, 0.06, 0.18), Color(0.16, 0.24, 0.62), 0.6, 0.35, 0.0],
		[ZONE_CLASSROOM, Color(0.13, 0.13, 0.12), Color(0.82, 0.82, 0.78), 0.7, 1.0, 0.0],
		[ZONE_STAGE, Color(0.02, 0.02, 0.025), Color(0.3, 0.26, 0.24), 0.25, 0.12, 0.0],
	]
	for mood: Array in moods:
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = mood[1]
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = mood[2]
		environment.ambient_light_energy = float(mood[3])
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var fog := float(mood[5])
		if fog > 0.0:
			environment.fog_enabled = true
			environment.fog_light_color = (mood[1] as Color).lightened(0.35)
			environment.fog_density = fog
		_environments[mood[0]] = environment
		_sun_energy[mood[0]] = float(mood[4])


func _process(delta: float) -> void:
	_update_zone()
	_update_framing(false)
	_hud_clock += delta
	if _hud_clock >= 0.25 and _hud.visible:
		_hud_clock = 0.0
		_update_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_8:
		var index := int(key.keycode - KEY_1)
		if index < STATIONS.size():
			go_to_station(STATIONS[index][0])
		return
	match key.keycode:
		KEY_H:
			_hud.visible = not _hud.visible
		KEY_M:
			_manual_medium = true
			medium_switch.call("set_painted", not bool(medium_switch.call("is_painted")))
		KEY_P:
			_print_sample()


func _print_sample() -> void:
	var sample: Dictionary = await sample_performance(60)
	print("VISUAL_LAB_PERF zone=%s %s" % [String(_zone), JSON.stringify(sample)])


## Puts the character at a named station. Returns false for an unknown id.
func go_to_station(id: StringName) -> bool:
	for station: Array in STATIONS:
		if station[0] != id:
			continue
		var feet: Vector3 = station[1]
		var facing: Vector3 = station[2]
		if station[3] is Array:
			var shot: Array = station[3]
			observe(feet, facing)
			look_from(shot[0], shot[1])
		else:
			var framing: Vector3 = station[3]
			observe(feet, facing, framing)
		return true
	return false


## Stands the character at `feet` facing `target`, with the follow camera behind it in
## the room's framing, or in `framing` (yaw, pitch, distance) until it enters another
## room (captures, walkthrough, tests).
func observe(feet: Vector3, target: Vector3, framing: Vector3 = Vector3.ZERO) -> void:
	observer.call("place", feet, target)
	_update_zone()
	_update_framing(true)
	if framing != Vector3.ZERO:
		observer.call("set_framing", framing, true)


## A free camera at `eye` looking at `target`; the character stays where it is.
func look_from(eye: Vector3, target: Vector3) -> void:
	observer.call("director", eye, target)


## The framing the room (or passage) at `point` asks for.
func framing_at(point: Vector3) -> Vector3:
	var flat := Vector2(point.x, point.z)
	for entry: Array in PASSAGE_FRAMINGS:
		if (entry[0] as Rect2).has_point(flat):
			return entry[1]
	var framing: Vector3 = ZONE_FRAMINGS.get(zone_at(point), ZONE_FRAMINGS[ZONE_OUTSIDE])
	return framing


func current_zone() -> StringName:
	return _zone


func zone_at(point: Vector3) -> StringName:
	var flat := Vector2(point.x, point.z)
	for entry: Array in ZONE_RECTS:
		if (entry[1] as Rect2).has_point(flat):
			return entry[0]
	return ZONE_OUTSIDE


func environment_for(zone: StringName) -> Environment:
	return _environments.get(zone, null) as Environment


func set_hud_visible(shown: bool) -> void:
	_hud.visible = shown


## Asks the camera for a new framing when the character crosses into a room or passage
## that wants a different one (and only then, so a station's framing holds until you leave).
func _update_framing(instant: bool) -> void:
	var framing := framing_at(observer.global_position)
	if not instant and framing == _framing_key:
		return
	_framing_key = framing
	observer.call("set_framing", framing, instant)


func _update_zone() -> void:
	var zone := zone_at(observer.global_position)
	if zone == _zone:
		return
	_zone = zone
	_world_environment.environment = environment_for(zone)
	_sun.light_energy = float(_sun_energy.get(zone, 1.0))
	# The two SubViewport windows render only while someone can see them.
	corridor.call("set_window_live", zone == ZONE_CORRIDOR)
	threshold.call("set_stage_window_live", zone == ZONE_CLASSROOM)
	if _hud.visible:
		_update_hud()


func _on_threshold_changed(on_painted_side: bool) -> void:
	# An Area3D leaving the tree reports its bodies as exited; a lab being freed has no
	# medium left to switch.
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_manual_medium = false
	medium_switch.call("set_painted", on_painted_side)


func _update_hud() -> void:
	var painted := bool(medium_switch.call("is_painted"))
	var lines: Array[String] = [
		"WHERE IS SCHOOL - visual experiments (dev only, not in the game)",
		String(ZONE_NOTES.get(_zone, "")),
		"renderer %s / %s   medium: %s%s" % [
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_current_rendering_driver_name(),
			"PAINTED" if painted else "3D",
			" (manual)" if _manual_medium else "",
		],
		"fps %d   draw calls %d   primitives %d   objects %d   video mem %.1f MiB" % [
			int(Performance.get_monitor(Performance.TIME_FPS)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		],
		"WASD walk  Shift jog  Q/E turn view  mouse orbit (click)  wheel zoom  R reset view",
		"F free camera (WASD fly, Q/E down/up)  1-8 stations  M switch medium  P perf  H hide",
	]
	_hud_text.text = "\n".join(lines)


## Averages the renderer's own monitors over `frames` frames. Frame time is wall clock
## between frames, so on a software rasteriser (CI) it is CPU time, not GPU time.
func sample_performance(frames: int = 30) -> Dictionary:
	var draw_calls := 0.0
	var primitives := 0.0
	var objects := 0.0
	var frame_ms := 0.0
	var worst_ms := 0.0
	var tree := get_tree()
	await tree.process_frame
	var last := Time.get_ticks_usec()
	for _frame in frames:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now - last) / 1000.0
		last = now
		frame_ms += elapsed
		worst_ms = maxf(worst_ms, elapsed)
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var count := float(maxi(frames, 1))
	return {
		"renderer": RenderingServer.get_current_rendering_method(),
		"draw_calls": snappedf(draw_calls / count, 0.1),
		"primitives": int(primitives / count),
		"objects": snappedf(objects / count, 0.1),
		"frame_ms": snappedf(frame_ms / count, 0.01),
		"worst_ms": snappedf(worst_ms, 0.01),
		"video_mem_mib": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mib": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mem_mib": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"generated_texture_kib": int(Kit.generated_bytes() / 1024),
		"painted": bool(medium_switch.call("is_painted")),
	}

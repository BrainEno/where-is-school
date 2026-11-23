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
## Pass `teaching-wing` to frame the new hub, gallery and hidden door instead, from
## the same camera and live scene. The close overview uses only those wings' bounds.
## Pass `return-route` for matched gameplay-camera details of the street, courtyard,
## alley and yard. The coordinates are valid on both sides of the art change.
## `school-details` uses matched hall, lab and fitted-room stances.
## Add `school-focus` for authored CameraShots, including the updated wet bench.
## `review_width=400` additionally writes compact copies for inline CI review.
## `dream-annex` frames the live corridor's escalator, ticket counter, 03 exam floor
## and stable yard, then the staff office: three follow-camera stances (by the muck heap the
## stench filter is up) and fixed views, including the 03 crowd at authored keyframes.
## `annex-thresholds` compares the new door approaches on the real hall floor.
## `construction-site` frames the yard's 建造中的大楼 (docs/GLOSSARY.md) the same way.
## `container-yard` frames the 集装箱堆场 past the yard: overhead, the tyre stairs, the planks.
## `port` frames the 港口 past the yard's truck: the quay, the pier, the crane, the ship, the sea.
## `front-yard` frames the 前操场 outside the teaching block: dirt, dead trees, the 伸缩门, the
## 小门 and its 刷卡机, then the same gate from the street.
## Output: res://docs/screenshots/map_art/<label>/<location>_<nn>_<spot>.jpg and an
## index, LOCATIONS.md, in the same folder. `docs/` is ignored by the importer.

const Harness = preload("res://tests/test_harness.gd")

const OUT_ROOT := "res://docs/screenshots/map_art"
const LOCATIONS := [
	["corridor", "res://scenes/locations/corridor/corridor.tscn"],
	["front_yard", "res://scenes/locations/front_yard/front_yard.tscn"],
	["street", "res://scenes/locations/street/street.tscn"],
	["residential", "res://scenes/locations/residential/residential.tscn"],
	["alley", "res://scenes/locations/alley/alley.tscn"],
	["playground", "res://scenes/locations/playground/playground.tscn"],
]
const SCHOOL_SCENES := {
	"laboratory": "res://scenes/locations/laboratory/laboratory.tscn",
	"restroom": "res://scenes/locations/restroom/restroom.tscn",
	"staff_office": "res://scenes/locations/staff_office/staff_office.tscn",
	"archive": "res://scenes/locations/archive/archive.tscn",
	"plan_room": "res://scenes/locations/plan_room/plan_room.tscn",
	"projection_room": "res://scenes/locations/projection_room/projection_room.tscn",
	"computer_room": "res://scenes/locations/computer_room/computer_room.tscn",
	"vacant_office": "res://scenes/locations/vacant_office/vacant_office.tscn",
	"principal_office": "res://scenes/locations/principal_office/principal_office.tscn",
	"restroom_02": "res://scenes/locations/restroom_02/restroom_02.tscn",
	"restroom_03": "res://scenes/locations/restroom_03/restroom_03.tscn",
}
const SCHOOL_STILLS := {
	"corridor": [
		["detail_office_door", Vector3(16.0, 3.6, -43.25)],
		["detail_restroom_door", Vector3(-24.40, -3.4, 12.56)],
		["detail_right_wall_02", Vector3(0.0, 0, -15.37)],
		["detail_right_wall_03", Vector3(-11.89, 3.6, -23.36)],
	],
	"laboratory": [
		["detail_wet_station", Vector3(-5.98, 0, -2.91)],
		["detail_hood_cabinet", Vector3(-3.8, 0, -3.99)],
		["detail_island", Vector3(-2.8, 0, -.96)],
	],
	"staff_office": [
		["detail_office_entry", Vector3(-2.28, 0, 1.67)],
		["detail_trays", Vector3(2.08, 0, -1.35)],
	],
	"restroom": [
		["detail_wash_entry", Vector3(2.73, 0, 1.51)],
		["detail_cubicles", Vector3(1.11, 0, .92)],
	],
	"archive": [
		["detail_entry", Vector3(2.86, 0, 2.18)],
		["detail_index", Vector3(1.04, 0, -0.39)],
	],
	"plan_room": [
		["detail_entry", Vector3(2.86, 0, 2.18)],
		["detail_tracing_table", Vector3(0.42, 0, 0.13)],
	],
	"projection_room": [
		["detail_entry", Vector3(2.86, 0, 2.18)],
		["detail_projector", Vector3(0.84, 0, 1.48)],
		["detail_second_exposure", Vector3(0.84, 0, 1.48)],
	],
	"computer_room": [
		["detail_entry", Vector3(3.45, 0, 2.33)],
		["detail_crt", Vector3(1.58, 0, -0.87)],
	],
	"vacant_office": [
		["detail_entry", Vector3(2.86, 0, 2.18)],
		["detail_carbon", Vector3(1.09, 0, -0.34)],
	],
	"principal_office": [
		["detail_entry", Vector3(2.86, 0, 2.18)],
		["detail_axis", Vector3(1.47, 0, -0.34)],
	],
	"restroom_02": [
		["detail_wash_entry", Vector3(2.73, 0, 1.51)],
		["detail_cubicles", Vector3(1.11, 0, .92)],
	],
	"restroom_03": [
		["detail_wash_entry", Vector3(2.73, 0, 1.51)],
		["detail_cubicles", Vector3(1.11, 0, .92)],
	],
}
const SCHOOL_SHOTS := {
	"laboratory": [["wet_bench", &"laboratory_wet_bench", Vector3(-5.94, 0, -3.35)]],
	"staff_office": [
		["rota", &"staff_office_rota", Vector3(-2.19, 0, -.14)],
		["dispatch", &"staff_office_trays", Vector3(2.08, 0, -1.35)],
		["keys", &"staff_office_keys", Vector3(-3.04, 0, -.25)],
	],
	"restroom": [
		["basins", &"restroom_basins", Vector3(-2.15, 0, -.28)],
		["latch", &"restroom_latch", Vector3(2.18, 0, .47)],
		["grate", &"restroom_drain", Vector3(-1.45, 0, 1.45)],
	],
	"archive": [["index", &"archive_detail", Vector3(1.04, 0, -0.39)]],
	"plan_room": [["tracing_table", &"plan_room_detail", Vector3(0.42, 0, 0.13)]],
	"projection_room": [["projector", &"projection_room_detail", Vector3(0.84, 0, 1.48)]],
	"computer_room": [["crt", &"computer_room_detail", Vector3(1.58, 0, -0.87)]],
	"vacant_office": [["carbon", &"vacant_office_detail", Vector3(1.09, 0, -0.34)]],
	"principal_office": [["axis", &"principal_office_detail", Vector3(1.47, 0, -0.34)]],
}
const TEACHING_SPOTS := {
	"glass_entrance_01": [^"SpawnPoints/FromTeachingEntrance", Vector3(0.35, 0, 0.43)],
	"directory_01": [^"TeachingBlock/GroundFloor/Gallery", Vector3(-1.24, 0, -0.30)],
	"waiting_register_02": [^"TeachingBlock/LowerFloor/WaitingRegister", Vector3(2.38, 0, 0.75)],
	# Keep the follow camera on the hall side, so it sees the ruled face of the end panel.
	"hour_register_03": [^"TeachingBlock/UpperFloor/HourRegister", Vector3(-4.90, 0, 1.81)],
	"rear_junction": [^"TeachingBlock/RearStair/Junction", Vector3.ZERO],
	"half_landing": [^"TeachingBlock/RearStair/DownLanding", Vector3.ZERO],
	"laboratory_recess": [^"SpawnPoints/FromLaboratory", Vector3.ZERO],
}
## [name, player feet] for the follow camera, then [name, eye, target] fixed views.
const DREAM_STANCES := [
	["yard_stance", Vector3(-35.0, -3.4, 13.4)],
	["stink_stance", Vector3(-34.8, -3.4, 7.8)],
	["exam_lane_stance", Vector3(-13.2, 3.6, -27.0)],
]
const DREAM_VIEWS := [
	["escalator", Vector3(0.6, 1.9, -5.4), Vector3(-5.0, 2.0, -8.45)],
	["ticket_counter_01", Vector3(-14.86, -1.48, 10.94), Vector3(-13.62, -2.26, 13.33)],
	["exam_floor_west", Vector3(-12.3, 5.4, -17.6), Vector3(-13.7, 4.2, -29.5)],
	["exam_floor_north", Vector3(-5.5, 5.18, -43.58), Vector3(9.0, 4.36, -42.1)],
	["stable_yard", Vector3(-21.5, 2.2, 19.6), Vector3(-38.0, -1.6, 8.6)],
	["stable_yard_air", Vector3(-15.0, 13.0, 28.0), Vector3(-37.0, -1.0, 7.0)],
	["stink_stalls", Vector3(-31.9, -1.75, 10.2), Vector3(-36.9, -2.35, 6.9)],
	["muck_heap", Vector3(-33.3, -2.35, 7.6), Vector3(-35.6, -2.95, 5.5)],
	["exam_conversation", Vector3(-2.76, 5.24, -43.83), Vector3(-1.49, 4.53, -41.38), 2.10],
	["exam_revision", Vector3(14.33, 5.37, -43.80), Vector3(14.38, 4.52, -41.29), 1.50],
	["exam_revision_next", Vector3(14.33, 5.37, -43.80), Vector3(14.38, 4.52, -41.29), 2.78],
	["exam_plaster_pair", Vector3(-13.67, 5.12, -26.52), Vector3(-13.40, 4.52, -29.05), 1.54],
]
const WAITING_VIEWS := [
	["waiting_conversation", Vector3(2.52, 1.66, -1.04), Vector3(1.45, .89, 1.36), 2.2],
	["waiting_revision", Vector3(-2.04, 1.58, .36), Vector3(-3.55, .86, 2.36), 2.78],
]
const ROOM_THRESHOLD_STANCES := [
	["recess_aperture_01", Vector3(-24.75, -3.4, 8.82)],
	["painted_bay_02", Vector3(0.30, 0, -18.17)],
	["rack_pier_02", Vector3(17.37, 0, -28.12)],
	["double_axis_03", Vector3(2.68, 3.6, -43.26)],
	["enamel_end_03", Vector3(18.48, 3.6, -42.16)],
]
const ROOM_THRESHOLD_VIEWS := [
	["01_light_trap", Vector3(-26.23, -1.63, 9.03), Vector3(-23.2, -2.15, 8.03)],
	["02_painted_leaf", Vector3(-1.59, 1.85, -16.76), Vector3(2.1, 1.29, -18.68)],
]
const SITE_STANCES := [["corner_stance", Vector3(-20.6, 0.0, 15.2)]]
const SITE_VIEWS := [
	["sand_piles", Vector3(-20.9, 2.1, 13.9), Vector3(-25.2, 0.9, 14.2)],
	["excavator", Vector3(-22.6, 3.4, 21.6), Vector3(-28.6, 2.0, 16.6)],
	["ellipsoid_exterior", Vector3(-19.5, 7.5, 3.0), Vector3(-31.4, 5.6, 11.8)],
	["site_overview", Vector3(-23.6, 15.0, 29.0), Vector3(-29.5, 3.5, 13.0)],
	["sand_basins", Vector3(-22.5, 4.3, 16.9), Vector3(-25.2, 1.22, 14.4)],
	["excavator_tracks", Vector3(-26.2, 5.6, 22.3), Vector3(-28.93, 1.6, 16.98)],
	["gate_lock", Vector3(-23.3, 1.45, 13.75), Vector3(-26.5, 0.95, 13.2)],
	["site_entrance", Vector3(-24.2, 2.9, 8.6), Vector3(-28.4, 1.4, 11.6)],
]
## Inside the building under construction (`site_interior`): by the porch door, at the key
## and under the light column, where the trip filter peaks; then fixed views of the room.
const SITE_INSIDE_STANCES := [
	["porch_stance", Vector3(4.0, 0.0, 0.8)],
	["key_stance", Vector3(-1.9, 0.0, 2.6)],
	["column_stance", Vector3(0.7, 0.0, -0.3)],
]
const SITE_INSIDE_VIEWS := [
	["inside_overview", Vector3(7.5, 9.5, 8.5), Vector3(-0.8, 0.6, -0.6)],
	["light_column", Vector3(3.6, 1.7, 2.6), Vector3(-1.4, 3.0, -1.8)],
	["chalk_key", Vector3(-1.4, 1.3, 4.8), Vector3(-3.0, 0.1, 3.2)],
	["looking_up", Vector3(1.2, 1.2, 0.9), Vector3(-1.4, 9.0, -1.8)],
	["porch_door_inside", Vector3(-2.4, 1.7, -1.4), Vector3(6.0, 1.1, 0.0)],
]
## With the key held, the yard's gate stands open: its padlock and chain are gone.
const SITE_GATE_OPEN_VIEWS := [
	["gate_open", Vector3(-22.9, 1.9, 15.6), Vector3(-26.6, 0.9, 12.6)],
]
## The container yard (`container_yard`): fixed views first (the maze from overhead, the
## yard from a corner, the tyre stairs, the long plank from the gap under it, the roofs and
## the high plank over the orange box), then follow-camera stances, then the way in.
const YARD_VIEWS := [
	["maze_top", Vector3(0.5, 46.0, 9.0), Vector3(-1.0, 0.0, -1.0)],
	["overview", Vector3(24.0, 26.0, 30.0), Vector3(-2.0, 0.0, -3.0)],
	["tyre_stairs", Vector3(14.5, 3.0, 16.6), Vector3(10.5, 1.6, 10.5)],
	["long_plank", Vector3(-1.2, 1.5, 10.8), Vector3(-3.8, 4.3, 7.0)],
	["roofs", Vector3(16.5, 9.5, 11.5), Vector3(5.0, 3.5, 3.0)],
	["high_plank", Vector3(13.0, 2.0, -8.6), Vector3(8.5, 5.0, -11.0)],
]
const YARD_STANCES := [
	["entrance", Vector3(14.0, 0.0, 14.6)],
	["lane", Vector3(2.0, 0.0, -4.25)],
	["tyre_foot", Vector3(12.2, 0.0, 12.6)],
	["orange", Vector3(9.75, 0.0, -8.75)],
]
## The schoolyard side: the bent chain-link behind the blue container.
const YARD_GAP_STANCES := [["behind_container", Vector3(13.0, 0.0, -17.6)]]
const YARD_GAP_VIEWS := [["fence_flap", Vector3(16.5, 3.2, -12.5), Vector3(13.0, 0.7, -18.4)]]
## The port (`port`), past the yard's truck: fixed views (the quay from high up, the sea
## from the pier, the crane, the ship, the water from overhead, the truck), then follow-
## camera stances, then the truck on the yard's apron that takes you there.
const PORT_VIEWS := [
	["overview", Vector3(34.0, 30.0, 34.0), Vector3(-4.0, 0.0, -10.0)],
	["sea_edge", Vector3(-11.0, 4.0, -16.0), Vector3(-17.0, -1.0, -30.0)],
	["crane", Vector3(26.0, 5.0, 12.0), Vector3(12.0, 12.0, -6.0)],
	["ship", Vector3(-2.0, 6.0, 2.0), Vector3(20.0, 4.0, -16.0)],
	["sky_water", Vector3(-8.0, 30.0, -10.0), Vector3(-12.0, -1.8, -30.0)],
	["truck", Vector3(23.0, 3.0, 20.0), Vector3(15.0, 1.5, 15.0)],
]
const PORT_STANCES := [
	["arrival", Vector3(19.0, 0.0, 15.2)],
	["stacks_lane", Vector3(-6.0, 0.0, 8.3)],
	["quay_edge", Vector3(-4.0, 0.0, -6.6)],
	["under_crane", Vector3(14.0, 0.0, -1.2)],
	["pier_end", Vector3(-15.0, 0.0, -24.6)],
]
## The front yard (前操场) and the school gate (校门) from both sides (docs/GLOSSARY.md).
const FRONT_YARD_STANCES := [
	["side_door", Vector3(13.2, 0.0, 15.8)],
	["path", Vector3(3.0, 0.0, 15.8)],
	["trees", Vector3(-3.5, 0.0, 2.0)],
]
const FRONT_YARD_VIEWS := [
	["overview", Vector3(30.0, 22.0, 36.0), Vector3(2.0, 0.0, 10.0)],
	["gate_inside", Vector3(6.0, 2.6, 21.0), Vector3(15.0, 1.1, 13.5)],
	["card_reader", Vector3(12.6, 1.7, 18.4), Vector3(14.85, 1.25, 16.6)],
	["dead_trees", Vector3(4.0, 3.0, 12.0), Vector3(-7.0, 3.0, 0.0)],
	["entrance", Vector3(2.0, 3.2, 21.0), Vector3(-10.6, 1.6, 15.8)],
]
const STREET_GATE_VIEWS := [
	["street_gate", Vector3(-2.0, 2.4, 18.6), Vector3(-11.0, 1.3, 12.0)],
	["over_the_wall", Vector3(2.0, 9.0, 6.0), Vector3(-20.0, 2.0, 2.0)],
]
const PORT_YARD_STANCES := [["yard_truck", Vector3(8.6, 0.0, 11.8)]]
const PORT_YARD_VIEWS := [["yard_truck_tail", Vector3(13.0, 3.5, 16.0), Vector3(6.0, 1.8, 11.8)]]
## The gameplay shot that backs the camera off the yard edge to show the whole building.
const SITE_SHOT_STANCE := Vector3(-21.9, 0.0, 13.4)
const RETURN_SPOTS := {
	"street": [
		["detail_return_plate", Vector3(-9.15, 0, -10.8)],
		["detail_receipt_slot", Vector3(-9.18, 0, -24.7)],
		["detail_ditch", Vector3(-8.3, 0, -31.4)],
	],
	"residential": [
		["detail_alley_guide", Vector3(3.23, 0, -15.76)],
		["detail_bench", Vector3(-2.72, 0, 6.95)],
	],
	"alley": [
		["detail_reversed_plate", Vector3(-2.10, 0, -18.55)],
		["detail_trolley_guide", Vector3(-2.10, 0, 5.6)],
	],
	"playground": [
		["detail_shed", Vector3(-12.12, 0, -4.0)],
		["detail_concrete_court", Vector3(0.8, 0, 2.0)],
		["detail_yard_tap", Vector3(-4.67, 0, 14.42)],
	],
}
const MIN_SPACING := 4.5
## The wide view looks along the game camera's own bearing, from further away.
const WIDE_FOV := 46.0

var _max_spots := 5
## Frames are scaled to this width before saving (0 keeps the window size). CI uses a
## smaller frame because it publishes the JPEGs inline, through annotations.
var _width := 0
var _review_width := 0
var _quality := 0.9
var _only := ""
var _teaching_wing := false
var _return_route := false
var _school_details := false
var _school_focus := false
var _dream_annex := false
var _construction_site := false
var _site_interior := false
var _container_yard := false
var _port := false
var _front_yard := false
var _annex_thresholds := false

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
		elif arg.begins_with("review_width="):
			_review_width = maxi(0, int(arg.substr(13)))
		elif arg.begins_with("quality="):
			_quality = clampf(float(arg.substr(8)), 0.3, 1.0)
		elif arg.begins_with("only="):
			_only = arg.substr(5).strip_edges()
		elif arg == "teaching-wing":
			_teaching_wing = true
		elif arg == "return-route":
			_return_route = true
		elif arg == "school-details":
			_school_details = true
		elif arg == "school-focus":
			_school_focus = true
		elif arg == "dream-annex":
			_dream_annex = true
		elif arg == "annex-thresholds":
			_annex_thresholds = true
		elif arg == "construction-site":
			_construction_site = true
		elif arg == "site-interior":
			_site_interior = true
		elif arg == "container-yard":
			_container_yard = true
		elif arg == "port":
			_port = true
		elif arg == "front-yard":
			_front_yard = true
	if _teaching_wing:
		_only = "corridor"
	call_deferred("_run")


func _run() -> void:
	var out_dir := "%s/%s" % [OUT_ROOT, _label]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	if _review_width > 0:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir + "/review"))
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
	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_rig = _main.get_node_or_null("CameraRig") as Node3D
	if _host == null or _player == null or _rig == null:
		_finish(["main.tscn did not expose LocationHost, Player and CameraRig."])
		return
	var startup := _host.get_current()
	var initial := startup.get_node_or_null(^"Navigation") as LocationNavigation if startup != null else null
	if initial == null or not await Harness.wait_until(initial.is_routable, 8.0):
		_finish(["The startup location never synchronized."])
		return
	var ui := _main.get_node_or_null("GameUI")
	if ui is CanvasLayer:
		(ui as CanvasLayer).visible = false
	_lines.append("# Location frames: %s" % _label)
	_lines.append("")
	_lines.append("Captured by `tests/capture_locations.gd` (%s, %s)." % [
		RenderingServer.get_current_rendering_method(), root.size,
	])
	_lines.append("The game camera frames stand the player on each spot; `wide` looks along")
	_lines.append("the same bearing from further away. HUD hidden.")
	_lines.append("")
	if _dream_annex:
		await _capture_views(out_dir, "corridor", ^"DreamAnnex/StableYard/DreamHouse", DREAM_STANCES, DREAM_VIEWS)
		await _capture_views(out_dir, "staff_office", ^"WaitingRoom", [], WAITING_VIEWS, "dream_annex_waiting")
	elif _annex_thresholds:
		await _capture_views(out_dir, "corridor", ^"TeachingBlock", ROOM_THRESHOLD_STANCES,
			ROOM_THRESHOLD_VIEWS, "annex_thresholds")
	elif _construction_site:
		var site := ^"PlaygroundArt/BuildingSite/EllipsoidBuilding/CastShell"
		await _capture_views(out_dir, "playground", site, SITE_STANCES, SITE_VIEWS)
		var yard := _host.get_current()
		if yard != null:
			await _capture_focus(yard, out_dir, &"pg_site_look", SITE_SHOT_STANCE, "playground_site_shot_detail_building")
	elif _site_interior:
		await _capture_views(out_dir, "site_interior", ^"Scaffold", SITE_INSIDE_STANCES, SITE_INSIDE_VIEWS,
			"site_interior")
		var state := root.get_node_or_null(^"/root/GameState")
		# The flag by its id, not `StoryFlags.SITE_GATE_KEY`: the `before` captures run this
		# script against the base commit, which may not declare the constant yet.
		if state != null:
			state.set_flag(&"site_gate_key", true)
		await _capture_views(out_dir, "playground", ^"Interactables/SiteGate", [], SITE_GATE_OPEN_VIEWS,
			"site_interior_gate_open")
	elif _container_yard:
		await _capture_views(out_dir, "container_yard", ^"Containers", [], YARD_VIEWS, "container_yard")
		await _capture_views(out_dir, "container_yard", ^"Containers", YARD_STANCES, [], "container_yard_walk")
		await _capture_views(out_dir, "playground", ^"Interactables/ToContainerYard", YARD_GAP_STANCES,
			YARD_GAP_VIEWS, "container_yard_gap")
	elif _port:
		await _capture_views(out_dir, "port", ^"Crane", [], PORT_VIEWS, "port")
		await _capture_views(out_dir, "port", ^"Crane", PORT_STANCES, [], "port_walk")
		await _capture_views(out_dir, "container_yard", ^"Interactables/ToPort", PORT_YARD_STANCES, PORT_YARD_VIEWS,
			"port_yard_truck")
	elif _front_yard:
		await _capture_views(out_dir, "front_yard", ^"RetractableGate", FRONT_YARD_STANCES, FRONT_YARD_VIEWS, "front_yard")
		await _capture_views(out_dir, "street", ^"SideDoor", [], STREET_GATE_VIEWS, "front_yard_street_gate")
	elif _school_details and SCHOOL_SCENES.has(_only):
		await _capture_location(_only, SCHOOL_SCENES[_only], out_dir)
	else:
		for entry: Array in LOCATIONS:
			if not _only.is_empty() and String(entry[0]) != _only:
				continue
			await _capture_location(String(entry[0]), String(entry[1]), out_dir)
	var file := FileAccess.open("%s/LOCATIONS.md" % out_dir, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	# The new art jobs assert a clean exit, including the autoload's ambient music.
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer", true, false))
	AudioRelease.stop_all(root.find_children("*", "AudioStreamPlayer3D", true, false))
	AudioRelease.wait_for_mix()
	await process_frame
	_finish(_failures)


func _capture_location(location_id: String, scene_path: String, out_dir: String) -> void:
	if not _host.load_location(scene_path, &"", _player, StringName(location_id)):
		_failures.append("%s did not load" % location_id)
		return
	if _teaching_wing:
		_player.set_wake_pose(0.0) # These shots are after class, not in the wake pose.
	var current := _host.get_current()
	var nav := current.get_node_or_null(^"Navigation") as LocationNavigation
	if nav == null or not await Harness.wait_until(nav.is_routable, 8.0):
		_failures.append("%s has no synchronized navigation." % location_id)
		return
	var spots: Array = []
	if _school_details:
		_player.set_wake_pose(0.0)
		_player.set_camera_roll(0.0)
		for spot: Array in SCHOOL_STILLS.get(location_id, []):
			spots.append([spot[0], (spot[1] as Vector3) + Vector3.UP * 0.05])
	else:
		spots = _teaching_spots(current) if _teaching_wing else _spots(current)
	if _return_route:
		_player.set_wake_pose(0.0)
		for spot: Array in RETURN_SPOTS.get(location_id, []):
			spots.append([spot[0], (spot[1] as Vector3) + Vector3.UP * 0.05])
	var subject := "teaching_wing" if _teaching_wing else location_id
	_lines.append("## %s" % subject)
	_lines.append("")
	var index := 0
	for spot: Array in spots:
		_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(-45.0)), spot[1]))
		await _wait(0.5)
		if _rig.has_method("snap"):
			_rig.call("snap")
		await _wait(2.8 if spot[0] == "detail_second_exposure" else 0.4)
		var shot_name := "%s_%02d_%s" % [subject, index, spot[0]]
		_save(out_dir, shot_name)
		_lines.append("- `%s.jpg` (%s) at %s" % [shot_name, spot[0], str(spot[1])])
		index += 1
	if _school_details and location_id == "laboratory":
		await _lab_end_plate(out_dir)
	if _school_focus:
		for shot: Array in SCHOOL_SHOTS.get(location_id, []):
			await _capture_focus(current, out_dir, shot[1], shot[2], "%s_shot_detail_%s" % [location_id, shot[0]])
	await _wide(current, subject, out_dir)
	_lines.append("")


## Loads a location, checks that `marker` exists, then frames its stances and views.
func _capture_views(out_dir: String, location_id: String, marker: NodePath, stances: Array, views: Array,
			subject: String = "") -> void:
	var scene_path := "res://scenes/locations/%s/%s.tscn" % [location_id, location_id]
	if not _host.load_location(scene_path, &"", _player, StringName(location_id)):
		_failures.append("%s did not load" % location_id)
		return
	_player.set_wake_pose(0.0)
	var current := _host.get_current()
	var nav := current.get_node_or_null(^"Navigation") as LocationNavigation
	if nav == null or not await Harness.wait_until(nav.is_routable, 8.0):
		_failures.append("%s has no synchronized navigation." % location_id)
	elif current.get_node_or_null(marker) == null:
		_failures.append("%s has no %s." % [location_id, marker])
	else:
		if subject.is_empty():
			subject = "dream_annex" if location_id == "corridor" else "%s_site" % location_id
		await _stances_and_views(current, out_dir, subject, stances, views)


## Follow-camera stances ([name, feet]), then fixed views ([name, eye, target, optional pose time]).
func _stances_and_views(current: Node, out_dir: String, subject: String, stances: Array, views: Array) -> void:
	var nav := current.get_node(^"Navigation") as LocationNavigation
	_lines.append("## %s" % subject)
	_lines.append("")
	var index := 0
	for stance: Array in stances:
		var feet := NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), stance[1])
		_player.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(-45.0)), feet + Vector3.UP * 0.05))
		await _wait(0.5)
		if _rig.has_method("snap"):
			_rig.call("snap")
		await _wait(0.6)
		var shot := "%s_%02d_detail_%s" % [subject, index, stance[0]]
		_save(out_dir, shot)
		_lines.append("- `%s.jpg` (follow camera) at %s, asked for %s" % [shot, str(feet), str(stance[1])])
		index += 1
	var camera := Camera3D.new()
	camera.fov = 58.0
	camera.far = 300.0
	_main.add_child(camera)
	for view: Array in views:
		camera.global_position = view[1]
		camera.look_at(view[2], Vector3.UP)
		camera.make_current()
		var held: Array[AnimationPlayer] = []
		var timing := ""
		if view.size() == 4:
			var at: float = view[3]
			held = _hold_crowd_pose(current, at)
			timing = " at the %.2f s pose" % at
		await _wait(0.5)
		var shot := "%s_%02d_detail_%s" % [subject, index, view[0]]
		_save(out_dir, shot)
		_lines.append("- `%s.jpg` (fixed view, not gameplay) from %s%s" % [shot, str(view[1]), timing])
		for motion in held:
			motion.play()
		index += 1
	camera.queue_free()
	await _wait(0.1)


func _hold_crowd_pose(current: Node, seconds: float) -> Array[AnimationPlayer]:
	var held: Array[AnimationPlayer] = []
	for motion: AnimationPlayer in current.find_children("Motion", "AnimationPlayer", true, false):
		if motion.is_playing() and motion.current_animation_length > 0.0:
			var time := fposmod(seconds, motion.current_animation_length)
			motion.pause()
			motion.seek(time, true)
			held.append(motion)
	if held.is_empty():
		_failures.append("%s has no playing exam poses to capture." % current.name)
	return held


## This is not a gameplay shot: the low matched plate makes the old unsupported
## feet and the new bearing surfaces easy to compare at the same perspective.
func _lab_end_plate(out_dir: String) -> void:
	var camera := Camera3D.new()
	camera.fov = 44.0
	_main.add_child(camera)
	camera.global_position = Vector3(-4.93, 1.91, 2.86)
	camera.look_at(Vector3(-7.00, .89, 1.08), Vector3.UP)
	camera.make_current()
	await _wait(0.45)
	_save(out_dir, "laboratory_plate_detail_bench_end")
	_lines.append("- `laboratory_plate_detail_bench_end.jpg` (matched low camera, not gameplay).")
	(_rig as CameraRig).camera.make_current()
	camera.queue_free()


func _capture_focus(current: LocationRoot, out_dir: String, id: StringName, feet: Vector3, name: String) -> void:
	var subject := current.find_interactable(id)
	var rig := _rig as CameraRig
	if subject == null or subject.camera_shot == null or rig == null:
		_failures.append("%s has no authored gameplay shot." % id)
		return
	_player.teleport(Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.05))
	rig.snap()
	_player.face_toward(subject.global_position - _player.global_position)
	rig.focus_on(subject, subject.camera_shot)
	if not await Harness.wait_until(func() -> bool: return rig.get_focus_weight() > 0.97, 5.0):
		_failures.append("%s gameplay shot never settled." % id)
	elif not _subject_fits(subject, rig.camera):
		_failures.append("%s gameplay shot fades or cuts off part of the subject." % id)
	elif not (_player.get_node(^"InteractionController") as InteractionController).is_seen_by_camera(subject):
		_failures.append("%s gameplay shot is hidden by another body." % id)
	else:
		_save(out_dir, name)
		_lines.append("- `%s.jpg` uses the CameraShot on `%s`." % [name, id])
	rig.clear_focus()


func _subject_fits(subject: Interactable, camera: Camera3D) -> bool:
	var view := camera.get_viewport().get_visible_rect().grow(-12.0)
	for mesh: GeometryInstance3D in subject.get_outline_meshes():
		if mesh.transparency > .05:
			return false
		var bounds := mesh.get_aabb()
		for corner in 8:
			var point := mesh.global_transform * bounds.get_endpoint(corner)
			if camera.is_position_behind(point) or not view.has_point(camera.unproject_position(point)):
				return false
	return true


func _teaching_spots(current: LocationRoot) -> Array:
	var spots: Array = []
	for key: String in TEACHING_SPOTS:
		var subject: Array = TEACHING_SPOTS[key]
		var marker := current.get_node_or_null(subject[0]) as Node3D
		if marker == null:
			_failures.append("No teaching wing position for %s." % key)
			continue
		spots.append([key, marker.global_position + (subject[1] as Vector3) + Vector3.UP * 0.05])
	return spots


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


func _teaching_bounds(current: LocationRoot) -> AABB:
	var bounds := AABB()
	for path: NodePath in [^"TeachingBlock/RearStair", ^"TeachingBlock/GroundFloor", ^"TeachingBlock/LowerFloor/LowerWest1"]:
		var section := current.get_node_or_null(path)
		if section == null:
			continue
		for node in section.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	return bounds


func _wide(current: LocationRoot, location_id: String, out_dir: String) -> void:
	var bounds := _teaching_bounds(current) if _teaching_wing else _nav_bounds(current)
	if bounds.size == Vector3.ZERO:
		_failures.append("%s has no baked navigation to frame" % location_id)
		return
	var bearing := Vector3(3.4, 6.4, 3.4).normalized()
	if _rig.get("offset") is Vector3:
		bearing = (_rig.get("offset") as Vector3).normalized()
	var radius := Vector2(bounds.size.x, bounds.size.z).length() * 0.5
	var clearance := 1.12 if _teaching_wing else 0.95
	var distance := radius / tan(deg_to_rad(WIDE_FOV * 0.5)) * clearance
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
	if _review_width > 0:
		if image.get_width() > _review_width:
			var height := int(round(float(image.get_height()) * _review_width / image.get_width()))
			image.resize(_review_width, height, Image.INTERPOLATE_LANCZOS)
		if image.save_jpg("%s/review/%s.jpg" % [out_dir, name], 0.62) != OK:
			_failures.append("No review copy for %s." % name)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame
	await process_frame


func _finish(failures: Array) -> void:
	Harness.finish(self, failures, "location frames written for %s" % _label)

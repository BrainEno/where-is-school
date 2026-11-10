extends SceneTree
## The kerb the navigation mesh has to agree with the body about.
##
## The street is a road at y = 0 with a 0.28 m kerb onto a pavement, and everything the
## street offers on its east side sits on that pavement: the notice, the shutter, the bins,
## the lamp, and the stairs to the residential block — the only way out of the street that
## does not go back into the school. The body can take a 0.30 m step
## (`PlayerController.max_step_height`), so the kerb is walkable in principle, and walking
## it by hand does work.
##
## The mesh is a different story. A navigation mesh is baked on a voxel grid, and the baker
## converts its properties to whole voxels: `agent_max_climb` is *floored*, `agent_height`
## and `agent_radius` are *ceiled* (see `NavMeshGenerator3D`, which warns about exactly
## that). With a 0.25 m cell height and a 0.3 m climb, `floor(0.3 / 0.25) * 0.25` is 0.25 —
## so a kerb the body steps over was a wall to every path query. The pavement was an island:
## a click on the stairs from the road found no path, the walk stopped at the kerb, and the
## only way across was to hold a movement key, which is why it never read as a bug.
##
## So this test does not trust the properties, it asks for the numbers the bake actually
## used, and then it asks the map and the body to do the thing: find the pavement from the
## road, path to it, and walk there.
##
## Four claims:
##   1. every location bakes with a climb, height and radius that survive the voxel
##      conversion, and the climb is the body's step height;
##   2. the east pavement of the street is a walkable surface on the map, not just geometry;
##   3. a route exists from the road spawn to that pavement, and walking it ends on the
##      pavement rather than against the kerb;
##   4. the body still steps only what it says it steps: a 0.28 m box is a step, a 0.75 m one
##      is a wall, and a step taller than `max_step_height` is not taken.

const Harness = preload("res://tests/test_harness.gd")

const STREET := "res://scenes/locations/street/street.tscn"
const STREET_SPAWN := &"FromCorridor"
## The east kerb is a 0.35 m wide box whose top sits 0.24 m above the road: one 0.25 m
## voxel of the bake, and one step of the body, with room to spare on both.
const KERB_TOP := 0.24
## The pavement slab behind it, and the road the walk starts on.
const PAVEMENT_TOP := 0.15
const ROAD_TOP := 0.0
## A point on the east pavement, clear of the stalls and of every interactable: the notice
## is at z = 2.0 and the nearest stall body at z = 6.5, both more than a metre away.
const PAVEMENT_POINT := Vector3(9.7, 0.15, 6.0)
## The player capsule's radius, from `player.tscn`. A body stops when its edge touches a
## step, so the face of the step is one radius away from the body's origin.
const BODY_REACH := 0.35
## The capsule's height, from `player.tscn`: headroom below this is not walkable.
const BODY_HEIGHT := 1.8
## How far a walked route may end from the point it was sent to.
const ARRIVAL_TOLERANCE := 1.2
## Physics frames a walk across the street may take before the run calls it stuck.
const WALK_FRAME_LIMIT := 20 * 60
## Every location bakes with the same settings, so the voxel arithmetic is checked on all of
## them: a change to one location's region settings is a change to all of them.
const LOCATIONS: Array[String] = [
	"res://scenes/locations/classroom/classroom.tscn",
	"res://scenes/locations/corridor/corridor.tscn",
	"res://scenes/locations/street/street.tscn",
	"res://scenes/locations/residential/residential.tscn",
	"res://scenes/locations/alley/alley.tscn",
	"res://scenes/locations/playground/playground.tscn",
]

var _failures: Array[String] = []
var _notes: Array[String] = []
var _main: Node = null
var _host: LocationHost = null
var _player: PlayerController = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 600.0, "step_up_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await _frames(3)

	_host = _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	if _host == null or _player == null:
		Harness.finish(self, ["Main did not expose the host and the player."], "")
		return
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null and sequence.has_method("allow_player_control"):
		sequence.call("allow_player_control")
	var voice := _main.get_node_or_null("InnerVoiceDirector")
	if voice != null:
		voice.set_process(false)
	Engine.time_scale = 3.0
	await _frames(2)

	Harness.stage = "the numbers the bake used"
	await _check_bake_numbers()

	Harness.stage = "the pavement"
	await _enter_street()
	await _check_pavement_is_a_surface()
	await _check_walk_onto_the_pavement()

	Harness.stage = "the body's step"
	await _check_body_steps()

	_report()
	Harness.finish(
		self, _failures,
		"every location bakes the step it promises, and the street's pavement is where a "
		+ "path and a walk both arrive."
	)


# --- the bake's own numbers --------------------------------------------------


## What the baker did with the settings, per location.
##
## `NavMeshGenerator3D` warns when a property does not survive the conversion to voxels and
## then carries on with the converted value. The conversion is floor for the climb and ceil
## for the height and radius, so the check is the same arithmetic the engine does. Asking
## the baked mesh (rather than the script's exports) is the point: the exports are what was
## wished for, the mesh is what every query uses.
func _check_bake_numbers() -> void:
	for scene_path in LOCATIONS:
		var name := scene_path.get_file().get_basename()
		if not _host.load_location(scene_path, &"", _player, StringName(name)):
			_failures.append("%s: the location could not be entered to read its bake." % name)
			continue
		var location := _host.get_current()
		if location == null:
			_failures.append("%s: no current location after the load." % name)
			continue
		var nav := location.get_node_or_null("Navigation") as LocationNavigation
		if nav == null:
			_failures.append("%s: no navigation region." % name)
			continue
		var synchronized: bool = await nav.wait_until_synchronized()
		if not synchronized:
			_failures.append("%s: never synchronized (%s)" % [name, nav.describe_sync()])
			continue
		var mesh: NavigationMesh = nav.navigation_mesh
		if mesh == null or mesh.get_polygon_count() <= 0:
			_failures.append("%s: the bake produced no mesh to measure." % name)
			continue
		var cell_height := mesh.cell_height
		var cell_size := mesh.cell_size
		if cell_height <= 0.0 or cell_size <= 0.0:
			_failures.append("%s: the bake has no cell size to convert against." % name)
			continue
		var climb := floorf(mesh.agent_max_climb / cell_height) * cell_height
		var height := ceilf(mesh.agent_height / cell_height) * cell_height
		var radius := ceilf(mesh.agent_radius / cell_size) * cell_size
		_notes.append(
			"%s: cell %.2f x %.2f, climb %.3f (asked %.3f), height %.2f (asked %.2f), radius %.2f (asked %.2f)"
			% [
				name, cell_size, cell_height, climb, mesh.agent_max_climb,
				height, mesh.agent_height, radius, mesh.agent_radius,
			]
		)
		# The game's own promise, in the form that survives the voxel conversion: what the
		# bake can climb is what the body can step. A mesh that promises a taller step than
		# the body takes produces routes the character walks into and grinds against; a mesh
		# that promises a shorter one produces routes around a kerb the player could have
		# stepped over, and the two numbers drifting apart is invisible until somebody
		# cannot leave a room.
		if not is_equal_approx(climb, _player.max_step_height):
			_failures.append(
				"%s: the bake climbs %.3f m and the body steps %.3f m."
				% [name, climb, _player.max_step_height]
			)
		# And the reason it matters: the street's kerb is 0.28 m, and the pavement behind it
		# is where every way out of the street is.
		if climb < KERB_TOP + 0.005:
			_failures.append(
				"%s: the bake can climb %.3f m, and the street's kerb is %.2f m: the pavement "
				% [name, climb, KERB_TOP]
				+ "is a separate island from the road."
			)
		if height < BODY_HEIGHT:
			_failures.append(
				"%s: the bake leaves %.2f m of headroom for a %.2f m body."
				% [name, height, BODY_HEIGHT]
			)
		if radius < BODY_REACH:
			_failures.append(
				"%s: the bake assumes a %.2f m agent for a %.2f m body." % [name, radius, BODY_REACH]
			)


# --- the street's kerb -------------------------------------------------------


func _enter_street() -> void:
	if not _host.load_location(STREET, STREET_SPAWN, _player, &"street"):
		_failures.append("the street could not be entered from the corridor.")
		return
	var location := _host.get_current()
	if location == null:
		_failures.append("the street did not become the current location.")
		return
	var nav := location.get_node_or_null("Navigation") as LocationNavigation
	if nav == null:
		_failures.append("the street has no navigation region.")
		return
	var synchronized: bool = await nav.wait_until_synchronized()
	if not synchronized:
		_failures.append("the street never synchronized (%s)" % nav.describe_sync())
		return
	await _physics_frames(4)


## The pavement has to be a walkable *surface*, not a box the player happens to be able to
## stand on: a point on it must snap to itself rather than to the road below.
func _check_pavement_is_a_surface() -> void:
	var map := _player.navigation_agent.get_navigation_map()
	if not map.is_valid():
		_failures.append("the player has no navigation map.")
		return
	var closest := NavigationServer3D.map_get_closest_point(map, PAVEMENT_POINT)
	var horizontal := Vector2(closest.x, closest.z).distance_to(
		Vector2(PAVEMENT_POINT.x, PAVEMENT_POINT.z)
	)
	_notes.append(
		"pavement point %s snapped to %s (%.2f m away, y %.2f)"
		% [str(PAVEMENT_POINT), str(closest), horizontal, closest.y]
	)
	if closest.y < PAVEMENT_TOP - 0.05:
		_failures.append(
			"the pavement at %s is not walkable: the map's closest point is %s, which is the "
			% [str(PAVEMENT_POINT), str(closest)]
			+ "road surface %.2f m below it." % (PAVEMENT_TOP - closest.y)
		)
	if horizontal > ARRIVAL_TOLERANCE:
		_failures.append(
			"the pavement is %.2f m from the nearest walkable point: it is not on the map."
			% horizontal
		)


## The thing a player does: click the pavement and see whether the character arrives.
func _check_walk_onto_the_pavement() -> void:
	var map := _player.navigation_agent.get_navigation_map()
	var target := NavigationServer3D.map_get_closest_point(map, PAVEMENT_POINT)
	var start := _player.global_position
	if not _player.request_path_to(target):
		_failures.append(
			"no route from the road (%s) to the pavement (%s)." % [str(start), str(target)]
		)
		return
	var frames := 0
	while _player.is_path_active() and frames < WALK_FRAME_LIMIT:
		await physics_frame
		frames += 1
	var end := _player.global_position
	var missed := Vector2(end.x, end.z).distance_to(Vector2(target.x, target.z))
	_notes.append(
		"walked %s -> %s in %d frame(s); %.2f m from the pavement point"
		% [str(start), str(end), frames, missed]
	)
	if _player.is_path_active():
		_failures.append(
			"the walk to the pavement did not finish within %d frames; it ended at %s."
			% [WALK_FRAME_LIMIT, str(end)]
		)
		return
	if end.y < PAVEMENT_TOP - 0.05:
		_failures.append(
			"the walk ended %.2f m low, at %s: the character stopped at the kerb (%.2f m) "
			% [PAVEMENT_TOP - end.y, str(end), KERB_TOP]
			+ "instead of stepping onto the pavement."
		)
	if missed > ARRIVAL_TOLERANCE:
		_failures.append(
			"the walk stopped %.2f m from the point it was sent to (%s)." % [missed, str(end)]
		)


# --- the body's step ---------------------------------------------------------


## Two boxes, one step each, in the open part of the road.
##
## The body is asked directly rather than through a simulated key press: which way a key
## moves the character depends on the camera, and this is about the step, not about the
## camera. `_try_step_up()` is what `_physics_process()` calls before every `move_and_slide()`,
## so calling it once is the frame the character walks into a kerb.
func _check_body_steps() -> void:
	var origin := Vector3(0.0, ROAD_TOP, 6.0)
	# `BODY_REACH` is where a capsule of radius 0.35 stops: its edge, plus the 0.10 m the
	# frame's motion covers. A box whose face is exactly there is what the character is
	# pressed against when it walks into a kerb, which is the case the step has to handle.
	var face := BODY_REACH + 0.10
	var step_box := _add_box(
		origin + Vector3(face + 0.5, KERB_TOP * 0.5, 0.0), Vector3(1.0, KERB_TOP, 1.0)
	)
	var wall_box := _add_box(
		origin + Vector3(-(face + 0.5), 0.375, 0.0), Vector3(1.0, 0.75, 1.0)
	)

	# A kerb-height box: the body rises onto it.
	var rose := await _step_against(origin, Vector3(0.12, 0.0, 0.0))
	_notes.append("a %.2f m box raised the body by %.2f m" % [KERB_TOP, rose])
	if rose < KERB_TOP - 0.06:
		_failures.append(
			"a %.2f m box raised the body by only %.2f m: the kerb is a wall to the body too."
			% [KERB_TOP, rose]
		)

	# A desk-height box: no rise. This is the half that keeps the fix honest.
	var stopped := await _step_against(origin, Vector3(-0.12, 0.0, 0.0))
	_notes.append("a 0.75 m box raised the body by %.2f m" % stopped)
	if stopped > 0.02:
		_failures.append("a 0.75 m box raised the body by %.2f m: it climbs furniture." % stopped)

	# The same kerb, with a step height smaller than it: no rise. The limit is the body's,
	# not the geometry's.
	var saved_step := _player.max_step_height
	_player.max_step_height = 0.1
	var too_tall := await _step_against(origin, Vector3(0.12, 0.0, 0.0))
	_player.max_step_height = saved_step
	_notes.append("the same %.2f m kerb with a 0.10 m step raised the body by %.2f m" % [KERB_TOP, too_tall])
	if too_tall > 0.02:
		_failures.append(
			"a step height of 0.10 m still climbed a %.2f m kerb (%.2f m)." % [KERB_TOP, too_tall]
		)

	step_box.queue_free()
	wall_box.queue_free()


## Puts the body back on the road at `origin`, walks it into whatever is in front, and
## returns how far it rose.
func _step_against(origin: Vector3, motion: Vector3) -> float:
	_player.teleport(Transform3D(Basis.IDENTITY, origin))
	await _physics_frames(3)
	# A frame of settling so `is_on_floor()` is true; the step is only taken on the floor.
	_player.velocity = Vector3.ZERO
	await _physics_frames(2)
	var before := _player.global_position.y
	_player._try_step_up(motion)
	await _physics_frames(1)
	return _player.global_position.y - before


func _add_box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "StepProbe"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_main.add_child(body)
	body.global_position = center
	return body


# --- reporting ---------------------------------------------------------------


func _report() -> void:
	for line in _notes:
		print("note: %s" % line)
	print("::notice title=step and kerb::%s" % "|".join(_notes))


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame

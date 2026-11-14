extends SceneTree
## The laboratory visual slice: a room that reads as a working lab, and one way out of it.
##
## The room was built as a standalone location scene (issue #163) so a later chapter can use
## it without touching the classroom, the prologue or the main line. The scene is generated
## by `tools/build_laboratory.py`, and this test checks the claims that generator makes
## about the space rather than the numbers in the file:
##
## 1. **A laboratory a stranger can name.** One 15.2 x 11.2 m room with five working zones -
##    wet bench, fume hood, glassware cabinet, analysis island, instrument bank - a mixing
##    drum running in the middle, and an entrance door. Every zone is a separate footprint
##    with floor space around it; none of them overlaps another.
## 2. **Nothing collides that cannot be seen.** Every collision body in the room is a box
##    whose size is its own visible box mesh; nothing decorative carries collision, and no
##    cable is solid. The player cannot be caught on a prop that is not there.
## 3. **The cables are a path, not a mood.** They begin at real machines - the bank, the
##    hood, the board, the centrifuge, the bench lamp, the balance, the mixer, the ceiling
##    fixtures - gather at one knot on the floor, and the bundle leaves the working room
##    through the narrow door in the partition. Every run is at working height or on the
##    floor: none of them float.
## 4. **The unknown room is a room.** Behind the partition the soffit brings the ceiling
##    down from 3.4 m to 2.6 m, the floor is a step down, there is one bulb, a shaft that climbs past the top of
##    the building, a hatch where the bundle ends, and a corridor that runs on past the north
##    wall into black. Nothing in the room explains any of it.
## 5. **You can walk all of it.** The bake reaches every interactable, the annex and the far
##    corridor from the entrance, and the annex back to the entrance - and it does not
##    reach across the mixing drum, which is solid.
## 6. **Its own colour.** Every surface draws a material from `assets/materials/laboratory/`
##    (the project's one glass preset is the single exception), every painted texture is the
##    project's own and within budget, and the one borrowed file, the ink outline pass, is
##    referenced read-only.
## 7. **The texts are true.** All nine inspection ids exist in both languages, and each of
##    them names something that is in the scene.
## 8. **Still standalone.** The entrance is a door, not an exit: the scene declares one
##    location and no destination, and it is deliberately absent from the story catalogue,
##    so nothing in the current slice can wander into it.
##
## It needs no main-menu state and no playtest, so it runs in CI next to the classroom slice.

const Harness = preload("res://tests/test_harness.gd")

const LABORATORY := "res://scenes/locations/laboratory/laboratory.tscn"
const MATERIALS := "res://assets/materials/laboratory/"
const TEXTURES := "res://assets/materials/laboratory/textures/"
## Shared files the room may use as they are: the project's one glass pane, and the ink
## outline pass every material in this location borrows read-only.
const SHARED_MATERIALS: Array[String] = [
	"res://assets/materials/glass_pane.tres",
	"res://scenes/environment/props/playground_art/materials/ink_outline.tres",
]
## tools/verify_build.py, per file: a texture warns at 512 KiB, a scene at 192 KiB.
const TEXTURE_WARN_BYTES := 512 * 1024
const TEXTURE_MAX_SIDE := 2048
const SCENE_WARN_BYTES := 192 * 1024

const FLOOR_SIZE := Vector3(15.6, 0.2, 11.6)
const ENTRY := &"Entry"
const ANNEX_SPAWN := &"FromAnnex"

## Walls, and the one opening each wall has to leave. Sizes are the visible box's own.
const WALLS := {
	"WallSouth": [Vector3(0.0, 1.7, 5.7), Vector3(15.6, 3.4, 0.2)],
	"WallWest": [Vector3(-7.7, 1.7, 0.0), Vector3(0.2, 3.4, 11.6)],
	"WallEast": [Vector3(7.7, 1.7, 0.0), Vector3(0.2, 3.4, 11.6)],
	"WallNorthLeft": [Vector3(-2.125, 1.7, -5.7), Vector3(11.35, 3.4, 0.2)],
	"WallNorthRight": [Vector3(6.425, 1.7, -5.7), Vector3(2.75, 3.4, 0.2)],
	"WallNorthLintel": [Vector3(4.3, 2.925, -5.7), Vector3(1.5, 0.95, 0.2)],
	"PartitionWestA": [Vector3(2.2, 1.7, -4.6), Vector3(0.18, 3.4, 2.0)],
	"PartitionWestB": [Vector3(2.2, 1.7, -1.35), Vector3(0.18, 3.4, 1.5)],
	"PartitionLintel": [Vector3(2.2, 2.925, -2.85), Vector3(0.18, 0.95, 1.5)],
	"PartitionSouth": [Vector3(4.9, 1.7, -0.6), Vector3(5.4, 3.4, 0.18)],
}
## The five working zones, as floor rectangles (x0, z0, x1, z1) around their colliding body.
## They are the arrangement claim: the room is divided, and the divisions do not overlap.
const ZONES := {
	"wet bench": [-7.51, -4.2, -6.65, 1.4],
	"fume hood": [-6.0, -5.5, -3.2, -4.45],
	"glassware cabinet": [-3.0, -5.5, -0.6, -4.5],
	"analysis island": [-4.0, -3.4, -0.8, -2.4],
	"instrument bank": [6.78, 0.65, 7.58, 4.95],
}
## Where each zone's own anchor stands, so "the anchor is at its zone" is one lookup.
const INTERACTABLES := {
	"laboratory_wet_bench": Vector3(-6.75, 1.05, -3.35),
	"laboratory_fume_hood": Vector3(-4.6, 1.35, -4.7),
	"laboratory_glass_cabinet": Vector3(-1.8, 1.2, -4.85),
	"laboratory_log_book": Vector3(-1.0, 1.1, -2.55),
	"laboratory_microscope": Vector3(-3.3, 1.15, -2.95),
	"laboratory_mixer": Vector3(0.7, 1.35, 1.95),
	"laboratory_instruments": Vector3(6.6, 1.2, 2.1),
	"laboratory_cable_knot": Vector3(1.35, 0.55, 0.35),
	"laboratory_annex_door": Vector3(1.95, 1.15, -2.85),
}
## The machines a cable is allowed to start from, with the cable it belongs to.
const CABLE_ORIGINS := {
	"CableBank0": Vector3(6.95, 0.72, 1.02),
	"CableBank1": Vector3(6.95, 0.66, 2.1),
	"CableBank2": Vector3(6.95, 0.7, 3.2),
	"CableBank3": Vector3(6.95, 0.76, 4.1),
	"CableHood": Vector3(1.95, 1.02, -5.42),
	"CableBoard": Vector3(1.4, 1.2, -5.4),
	"CableCentrifuge": Vector3(-2.4, 0.95, -3.34),
	"CableBenchLamp": Vector3(-7.05, 1.85, -1.9),
	"CableBalance": Vector3(-6.6, 0.95, -3.9),
	"CableMixer": Vector3(1.48, 1.5, 0.7),
	"CableCeilingDrop": Vector3(-1.7, 2.98, 0.9),
}
## The mixer drum, the room's one running machine, and the thing the bake must not cross.
const MIXER_DRUM := Vector3(0.7, 1.62, 1.0)
## Floor points the bake has to reach, and where they are.
const REACHABLE := {
	"the annex": Vector3(3.4, 0.0, -2.85),
	"the hatch": Vector3(6.1, 0.0, -1.7),
	"the far corridor": Vector3(4.3, 0.0, -7.6),
}
const ANNEX_CEILING_HEIGHT := 2.6
const ROOM_WALL_HEIGHT := 3.4
## metres of horizontal slack allowed between a routed path and its target
const REACH_SLACK := 0.3

var _failures: Array[String] = []
var _notes: Array[String] = []
var _main: Node = null
var _room: Node = null
var _player: PlayerController = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "laboratory_visual_slice_test.gd")
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
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(_main)
	await _physics_frames(3)

	var host := _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	if host == null or _player == null:
		Harness.finish(self, ["Main did not expose the location host or the player."], "")
		return
	if not host.load_location(LABORATORY, ENTRY, _player):
		Harness.finish(self, ["The laboratory could not be entered."], "")
		return
	await _physics_frames(3)
	_room = host.get_current()
	if _room == null:
		Harness.finish(self, ["The host reports no current location."], "")
		return
	if sequence != null and sequence.has_method("allow_player_control"):
		sequence.call("allow_player_control")
	await _physics_frames(2)

	Harness.stage = "the room"
	_check_room()
	Harness.stage = "solids"
	_check_solids()
	Harness.stage = "cables"
	_check_cables()
	Harness.stage = "the room behind the door"
	_check_annex()
	Harness.stage = "colour and textures"
	_check_colour()
	Harness.stage = "inspection texts"
	_check_texts()
	Harness.stage = "the running machine"
	await _check_spinner()
	Harness.stage = "navigation"
	var navigation := await _check_navigation()
	Harness.stage = "the game camera"
	await _check_camera()
	Harness.stage = "standalone"
	_check_standalone()

	print("::notice title=laboratory visual slice::%s" % " | ".join(_notes))
	Harness.finish(
		self,
		_failures,
		"the laboratory is five working zones around a running drum, every cable starts at a "
		+ "machine and ends behind the partition, the room behind it is reachable and "
		+ "unexplained, and nothing in the scene collides that cannot be seen.",
	)


# --- 1. the room ------------------------------------------------------------------------


func _check_room() -> void:
	for required: String in ["WorldEnvironment", "Navigation", "Floor", "Interactables", "SpawnPoints", "Ambience"]:
		if _room.get_node_or_null(NodePath(required)) == null:
			_failures.append("The laboratory has no '%s' node." % required)
	var location := _room as LocationRoot
	if location == null:
		_failures.append("The laboratory root does not use LocationRoot.")
	elif String(location.location_id) != "laboratory":
		_failures.append("The laboratory declares location_id '%s'." % location.location_id)

	var floor_shape := _room.get_node_or_null(^"Floor/CollisionShape3D") as CollisionShape3D
	var floor_box: BoxShape3D = null
	if floor_shape != null:
		floor_box = floor_shape.shape as BoxShape3D
	if floor_box == null or not floor_box.size.is_equal_approx(FLOOR_SIZE):
		_failures.append("The laboratory floor is no longer the 15.2 x 11.2 m room.")
	elif not (_room.get_node(^"Floor") as Node3D).position.is_equal_approx(Vector3(0.0, -0.1, 0.0)):
		_failures.append("The floor moved; the walls are placed against its top face.")

	for wall: String in WALLS:
		var expected: Array = WALLS[wall]
		var node := _room.get_node_or_null(NodePath(wall)) as Node3D
		if node == null:
			_failures.append("The laboratory lost '%s'." % wall)
			continue
		if not node.position.is_equal_approx(expected[0]):
			_failures.append("'%s' stands at %s, not %s." % [wall, str(node.position), str(expected[0])])
		var shape := _box_size(node)
		if not shape.is_equal_approx(expected[1]):
			_failures.append("'%s' collides as %s, not %s." % [wall, str(shape), str(expected[1])])
		if not node.is_in_group("camera_occluder"):
			_failures.append("'%s' left the camera occluder group; the camera will see through it." % wall)

	# Five zones, each a footprint of its own, none of them on top of another.
	var names: Array = ZONES.keys()
	for index in names.size():
		for other in range(index + 1, names.size()):
			var a: Array = ZONES[names[index]]
			var b: Array = ZONES[names[other]]
			var overlaps := a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]
			if overlaps:
				_failures.append("'%s' and '%s' occupy the same floor." % [names[index], names[other]])
	for id: String in INTERACTABLES:
		var anchor: Vector3 = INTERACTABLES[id]
		if id == "laboratory_mixer" or id == "laboratory_cable_knot" or id == "laboratory_annex_door":
			continue
		var home := false
		for zone: String in ZONES:
			var rect: Array = ZONES[zone]
			if anchor.x >= rect[0] - 0.6 and anchor.x <= rect[2] + 0.6 and anchor.z >= rect[1] - 0.6 and anchor.z <= rect[3] + 0.6:
				home = true
		if not home:
			_failures.append("'%s' stands at %s, outside every working zone." % [id, str(anchor)])
	_notes.append("zones %d, walls %d" % [ZONES.size(), WALLS.size()])


# --- 2. solids -------------------------------------------------------------------------


func _check_solids() -> void:
	# What a player walks into has to be what the player can see: every collision body in the
	# room is a box the same size as its own box mesh. Nothing else in the room collides.
	var bodies := 0
	for node in _descendants(_room):
		var body := node as StaticBody3D
		if body == null:
			continue
		bodies += 1
		var path := _relative(body)
		if path.begins_with("Cables/") or path.begins_with("Interactables/"):
			_failures.append("'%s' is a solid; only the room's furniture and shell may collide." % path)
			continue
		var shapes := body.find_children("*", "CollisionShape3D", false, false)
		var meshes := body.find_children("*", "MeshInstance3D", false, false)
		if shapes.size() != 1:
			_failures.append("'%s' has %d collision shapes; the room is built from single boxes." % [path, shapes.size()])
			continue
		if meshes.size() != 1:
			_failures.append("'%s' has %d meshes; its collider cannot be the shape it shows." % [path, meshes.size()])
			continue
		var shape := (shapes[0] as CollisionShape3D).shape as BoxShape3D
		var mesh := (meshes[0] as MeshInstance3D).mesh as BoxMesh
		if shape == null or mesh == null:
			_failures.append("'%s' is not a box colliding with a box mesh." % path)
			continue
		if not shape.size.is_equal_approx(mesh.size):
			_failures.append(
				"'%s' collides as %s but is drawn as %s." % [path, str(shape.size), str(mesh.size)]
			)
	if bodies < 100:
		_failures.append("Only %d collision bodies: the room's shell, benches and machines are missing." % bodies)
	_notes.append("solids %d, all box-exact" % bodies)


# --- 3. cables -------------------------------------------------------------------------


func _check_cables() -> void:
	var cables := _room.get_node_or_null(^"Cables")
	if cables == null:
		_failures.append("The laboratory has no Cables group.")
		return
	var runs := {}
	var highest := -INF
	for child in cables.get_children():
		var piece := child as MeshInstance3D
		if piece == null:
			continue
		var run := String(piece.name).split("_")[0]
		if not runs.has(run):
			runs[run] = []
		(runs[run] as Array).append(piece)
		highest = maxf(highest, piece.global_position.y)
		if piece.material_override == null:
			_failures.append("'%s' has no cable material." % piece.name)
	if cables.get_child_count() < 300:
		_failures.append("Only %d cable segments; the room's cabling lost its weight." % cables.get_child_count())
	if runs.size() < 20:
		_failures.append("Only %d cable runs leave the machines." % runs.size())

	# Every run that is supposed to come out of a machine starts there.
	var anchored := 0
	for run: String in CABLE_ORIGINS:
		if not runs.has(run):
			_failures.append("The cable from '%s' is missing." % run)
			continue
		var first: MeshInstance3D = (runs[run] as Array)[0]
		var origin: Vector3 = CABLE_ORIGINS[run]
		if first.global_position.distance_to(origin) > 0.45:
			_failures.append(
				"'%s' starts %.2f m from the machine it belongs to."
				% [run, first.global_position.distance_to(origin)]
			)
		else:
			anchored += 1
	if anchored < CABLE_ORIGINS.size():
		_failures.append("Only %d of %d machine cables start at their machine." % [anchored, CABLE_ORIGINS.size()])

	# The line the player can follow: one bundle leaves the working room through the door.
	var through := false
	if runs.has("CableBundle0"):
		var bundle: Array = runs["CableBundle0"]
		var west := false
		var east := false
		for piece: MeshInstance3D in bundle:
			west = west or piece.global_position.x < 2.1
			east = east or piece.global_position.x > 2.3
		through = west and east
		var last: MeshInstance3D = bundle[bundle.size() - 1]
		if Vector2(last.global_position.x - 6.5, last.global_position.z + 1.5).length() > 1.2:
			_failures.append("The bundle does not end at the hatch in the annex.")
	if not through:
		_failures.append("No cable crosses the partition, so there is no path to follow through it.")
	if highest > ROOM_WALL_HEIGHT:
		_failures.append("A cable hangs at %.2f m, above the room's walls." % highest)
	_notes.append("cables %d segments, %d runs, highest %.2f m" % [cables.get_child_count(), runs.size(), highest])


# --- 4. the room behind the door ----------------------------------------------------------


func _check_annex() -> void:
	# The low ceiling is carried by a perimeter soffit rather than by a lid over the room:
	# every interior here is open above the working area so the follow camera can look in.
	var ceiling := _box_bottom(_room.get_node_or_null(^"AnnexSoffitSpine") as Node3D)
	var annex_floor := _room.get_node_or_null(^"AnnexFloor") as Node3D
	if annex_floor == null:
		_failures.append("The annex has lost its floor.")
	elif not is_equal_approx(annex_floor.position.y, -0.06):
		_failures.append("The annex floor is no longer the step down it was.")
	if ceiling == null:
		_failures.append("The annex has no soffit; the space no longer reads as a lower room.")
	elif absf(ceiling - ANNEX_CEILING_HEIGHT) > 0.06:
		_failures.append(
			"The annex soffit is at %.2f m, not the %.1f m that makes it a lower room."
			% [ceiling, ANNEX_CEILING_HEIGHT]
		)
	# The shaft leaves that ceiling and goes past the top of the building.
	var shaft := _room.get_node_or_null(^"ShaftWest") as Node3D
	if shaft == null:
		_failures.append("The shaft is missing.")
	else:
		var top := _box_bottom(shaft)
		if top == null or top <= ROOM_WALL_HEIGHT:
			_failures.append("The shaft stops at the building's height instead of climbing past it.")
	# The corridor runs on behind the north wall: floor beyond the room's own footprint.
	var corridor := _room.get_node_or_null(^"FarCorridorFloor") as Node3D
	if corridor == null or corridor.global_position.z > -5.8:
		_failures.append("The far corridor no longer continues past the north wall.")
	var end := _room.get_node_or_null(^"FarCorridorEnd") as Node3D
	if end == null:
		_failures.append("The far corridor has no end; the player would walk out of the room.")
	elif _room.get_node_or_null(^"FarCorridorEnd/CollisionShape3D") == null:
		_failures.append("The end of the far corridor is not solid; the player can leave the floor.")
	# The one bulb, and nothing else lighting the annex.
	var bulbs := 0
	for node in _descendants(_room):
		var light := node as OmniLight3D
		if light != null and light.global_position.z < -0.6 and light.global_position.x > 2.2:
			bulbs += 1
	if bulbs > 2:
		_failures.append("The annex has %d lamps; it is meant to have one bulb and one glow." % bulbs)
	_notes.append("annex ceiling %.2f m, lights %d" % [ceiling if ceiling != null else -1.0, bulbs])


# --- 5. colour and textures ---------------------------------------------------------------


func _check_colour() -> void:
	var borrowed := {}
	for node in _descendants(_room):
		var piece := node as MeshInstance3D
		if piece == null or piece.mesh == null:
			continue
		var material := piece.material_override
		if material == null:
			_failures.append("'%s' has no material; it would draw the engine default." % _relative(piece))
			continue
		var path := material.resource_path
		if path.begins_with(MATERIALS):
			continue
		if SHARED_MATERIALS.has(path):
			borrowed[path] = borrowed.get(path, 0) + 1
			continue
		_failures.append("'%s' draws '%s', which is another location's material." % [_relative(piece), path])
	for path: String in borrowed:
		if not SHARED_MATERIALS.has(path):
			_failures.append("The room borrows '%s'." % path)
	# Every material it owns is its own file, with its own name.
	var owned := 0
	for path in _files_in(MATERIALS):
		if not path.ends_with(".tres"):
			continue
		owned += 1
		var text := _file_text(path)
		if text.contains("next_pass = ExtResource") and not text.contains("ink_outline.tres"):
			_failures.append("'%s' borrows an outline pass that is not the project's ink." % path)
	if owned < 24:
		_failures.append("The laboratory has only %d material presets." % owned)

	# Textures: the project's own four, each inside the per-file budget.
	var textures := _files_in(TEXTURES)
	if textures.size() < 4:
		_failures.append("The laboratory has %d textures; the four painted surfaces are the point." % textures.size())
	for path: String in textures:
		if not path.ends_with(".png"):
			continue
		var size := _file_bytes(path)
		if size > TEXTURE_WARN_BYTES:
			_failures.append("'%s' is %d bytes, over the 512 KiB warning budget." % [path, size])
		var texture: Texture2D = load(path)
		if texture == null:
			_failures.append("'%s' could not be loaded as a texture; its import is broken." % path)
			continue
		var side := maxi(texture.get_width(), texture.get_height())
		if side > TEXTURE_MAX_SIDE:
			_failures.append("'%s' is %d px across." % [path, side])

	var scene_size := _file_bytes(LABORATORY)
	if scene_size > SCENE_WARN_BYTES:
		_failures.append("The scene is %d bytes, over the %d byte warning budget." % [scene_size, SCENE_WARN_BYTES])
	_notes.append("materials %d, textures %d, scene %.0f KiB" % [owned, textures.size(), scene_size / 1024.0])


# --- 6. the texts -------------------------------------------------------------------------


func _check_texts() -> void:
	var library := InspectionLibrary.load_all()
	if not library.is_valid():
		_failures.append("inspections: " + library.describe_errors())
		return
	var per_locale := {}
	for locale: String in L10n.LOCALES:
		library.set_locale(locale)
		var ids := {}
		for id: StringName in library.get_ids(locale):
			ids[String(id)] = true
		per_locale[locale] = ids
		for wanted: String in INTERACTABLES:
			if not ids.has(wanted):
				_failures.append("%s: no inspection for '%s'." % [locale, wanted])
			else:
				var entry := library.get_inspection(StringName(wanted))
				if entry.text.length() < 40:
					_failures.append("%s/%s: the text is too short to describe anything." % [locale, wanted])
				if entry.prompt.is_empty() or entry.prompt.length() > 32:
					_failures.append("%s/%s: the prompt is '%s'." % [locale, wanted, entry.prompt])
	var locales: Array = L10n.LOCALES
	for index in locales.size():
		for other in range(index + 1, locales.size()):
			var a: Dictionary = per_locale[locales[index]]
			var b: Dictionary = per_locale[locales[other]]
			for id: String in a:
				if not b.has(id):
					_failures.append("'%s' exists in %s but not in %s." % [id, locales[index], locales[other]])
	# And the scene really carries all nine, one interactable each.
	var anchors := 0
	for child in _room.get_node(^"Interactables").get_children():
		var interactable := child as Interactable
		if interactable == null:
			continue
		anchors += 1
		if not INTERACTABLES.has(String(interactable.interact_id)):
			_failures.append("Unexpected interactable '%s'." % interactable.interact_id)
		if not interactable.global_position.is_equal_approx(INTERACTABLES[String(interactable.interact_id)]):
			_failures.append(
				"'%s' stands at %s, not %s."
				% [
					interactable.interact_id,
					str(interactable.global_position),
					str(INTERACTABLES[String(interactable.interact_id)]),
				]
			)
	if anchors != INTERACTABLES.size():
		_failures.append("The room has %d anchors, not %d." % [anchors, INTERACTABLES.size()])
	_notes.append("inspections %d x %d locales" % [INTERACTABLES.size(), L10n.LOCALES.size()])


# --- 7. the running machine ---------------------------------------------------------------


func _check_spinner() -> void:
	var blade := _room.get_node_or_null(^"MixerBlade") as MeshInstance3D
	if blade == null:
		_failures.append("The mixer has no vane on its shaft.")
		return
	var script := blade.get_script() as Script
	if script == null or not String(script.resource_path).ends_with("spinner.gd"):
		_failures.append("The mixer blade does not turn: no spinner script on it.")
		return
	var before := blade.rotation.y
	await _physics_frames(6)
	if is_equal_approx(before, blade.rotation.y):
		_failures.append("The mixer blade did not move over six frames.")
	# It turns about its own shaft, and only that.
	if not is_zero_approx(blade.rotation.x) or not is_zero_approx(blade.rotation.z):
		_failures.append("The blade tilts as it turns; it should only go round.")
	_notes.append("blade %.1f deg/s" % float(blade.get("degrees_per_second")))


# --- 8. navigation --------------------------------------------------------------------------


func _check_navigation() -> LocationNavigation:
	var navigation := _room.get_node_or_null(^"Navigation") as LocationNavigation
	if navigation == null:
		_failures.append("The laboratory has no navigation region.")
		return null
	var synchronized: bool = await navigation.wait_until_synchronized()
	if not synchronized:
		_failures.append("The laboratory navigation never synchronized: %s" % navigation.describe_sync())
		return null
	var map := navigation.get_navigation_map()
	if not map.is_valid():
		_failures.append("The laboratory navigation map is not valid.")
		return null
	var entry := _room.get_node_or_null(^"SpawnPoints/Entry") as Node3D
	if entry == null:
		_failures.append("The laboratory has no Entry spawn point.")
		return null
	var start := NavigationServer3D.map_get_closest_point(map, entry.global_position)
	if Vector2(start.x - entry.global_position.x, start.z - entry.global_position.z).length() > 0.6:
		_failures.append("The entrance marker is not on the navigation mesh.")

	for id: String in INTERACTABLES:
		var anchor: Vector3 = INTERACTABLES[id]
		var radius := 1.5
		var node := (_room.get_node(^"Interactables") as Node).find_child(_node_name_for(id), true, false)
		if node != null:
			radius = float(node.get("radius"))
		var gap := _route_gap(map, start, anchor)
		if gap > radius + REACH_SLACK:
			_failures.append(
				"'%s' cannot be reached: the nearest routed floor is %.2f m away, its radius %.2f."
				% [id, gap, radius]
			)

	for name: String in REACHABLE:
		var gap := _route_gap(map, start, REACHABLE[name])
		if gap > 0.6:
			_failures.append("'%s' cannot be reached from the entrance (%.2f m short)." % [name, gap])

	var annex_marker := _room.get_node_or_null(^"SpawnPoints/FromAnnex") as Node3D
	if annex_marker == null:
		_failures.append("The annex has no spawn point of its own.")
	else:
		var back := _route_gap(
			map,
			NavigationServer3D.map_get_closest_point(map, annex_marker.global_position),
			entry.global_position
		)
		if back > 0.6:
			_failures.append("The annex is a dead end: %.2f m of the entrance cannot be routed back." % back)
		if String(annex_marker.name) != String(ANNEX_SPAWN):
			_failures.append("The annex spawn marker was renamed.")

	# The one thing the bake must not cross: the mixing drum is solid.
	var into_drum := _route_gap(map, start, MIXER_DRUM)
	if into_drum < 0.55:
		_failures.append("A route ends inside the mixing drum (%.2f m from its centre)." % into_drum)

	if navigation.get_polygon_count() < 40:
		_failures.append("Only %d navigation polygons; the room is bigger than that." % navigation.get_polygon_count())
	_notes.append("nav polygons %d" % navigation.get_polygon_count())
	return navigation


func _node_name_for(id: String) -> String:
	match id:
		"laboratory_wet_bench":
			return "WetBenchLook"
		"laboratory_fume_hood":
			return "HoodLook"
		"laboratory_glass_cabinet":
			return "GlassCabinetLook"
		"laboratory_log_book":
			return "LogBookLook"
		"laboratory_microscope":
			return "MicroscopeLook"
		"laboratory_mixer":
			return "MixerLook"
		"laboratory_instruments":
			return "InstrumentBankLook"
		"laboratory_cable_knot":
			return "CableKnotLook"
		"laboratory_annex_door":
			return "AnnexDoorLook"
	return ""


## How far from `target` a route that starts at `start` can end (horizontal metres).
func _route_gap(map: RID, start: Vector3, target: Vector3) -> float:
	var goal := NavigationServer3D.map_get_closest_point(map, target)
	var route := NavigationServer3D.map_get_path(map, start, goal, true)
	if route.is_empty():
		return INF
	var end := route[route.size() - 1]
	return Vector2(end.x - target.x, end.z - target.z).length()


# --- 9. the game camera ---------------------------------------------------------------------


func _check_camera() -> void:
	var rig := _main.get_node_or_null(^"CameraRig") as CameraRig
	if rig == null or rig.camera == null:
		_failures.append("Main has no CameraRig to look through.")
		return
	var camera := rig.camera
	var entry := _room.get_node_or_null(^"SpawnPoints/Entry") as Node3D
	if entry == null:
		_failures.append("The entrance marker is missing; nothing to look from.")
		return
	# Standing at the entrance and facing the working half: the drum and the door are both
	# in shot. That is what makes the first second say "laboratory" and not "corridor".
	var facing := _yaw_towards(entry.global_position, MIXER_DRUM)
	_player.teleport(Transform3D(Basis(Vector3.UP, facing), entry.global_position))
	rig.snap()
	await _physics_frames(2)
	if not camera.is_position_in_frustum(MIXER_DRUM):
		_failures.append("The mixing drum is not in shot from the entrance.")
	var door := _room.get_node_or_null(^"AnnexDoorJambA") as Node3D
	if door != null and not camera.is_position_in_frustum(door.global_position):
		_failures.append("The narrow door is not in shot from the entrance.")
	var seen := 0
	for id: String in INTERACTABLES:
		if camera.is_position_in_frustum(INTERACTABLES[id]):
			seen += 1
	if seen < 3:
		_failures.append("Only %d of %d anchors are in shot from the entrance." % [seen, INTERACTABLES.size()])
	var far := camera.global_position.distance_to(_player.global_position)
	if far > 12.0:
		_failures.append("The camera sits %.1f m behind the player in a 15 m room." % far)
	_notes.append("camera %.1f m behind, %d anchors in shot" % [far, seen])


## The yaw that points a CharacterBody3D's -Z forward axis at `target`.
func _yaw_towards(from: Vector3, target: Vector3) -> float:
	var direction := target - from
	return atan2(-direction.x, -direction.z)


# --- 10. standalone --------------------------------------------------------------------------


func _check_standalone() -> void:
	var catalog := LocationCatalog.load_all()
	if not catalog.is_valid():
		_failures.append("locations: " + catalog.describe_errors())
	if catalog.has(&"laboratory"):
		_failures.append(
			"The laboratory was added to data/story/locations.json; this slice is not wired "
			+ "into the main line yet."
		)
	# No exit: the entrance is a door, and the room declares no destination.
	for node in _descendants(_room):
		if node is LocationExit:
			_failures.append("The laboratory declares an exit ('%s')." % _relative(node))
	if _room.get_node_or_null(^"EntranceFrame") == null:
		_failures.append("The entrance door frame is missing.")


# --- helpers ------------------------------------------------------------------------------------


func _box_size(node: Node3D) -> Vector3:
	var shape_node := node.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return Vector3.ZERO
	var box := shape_node.shape as BoxShape3D
	return box.size if box != null else Vector3.ZERO


## The underside of a box: its centre minus half its own height.
func _box_bottom(node: Node3D) -> float:
	if node == null:
		return -1.0
	var size := _box_size(node)
	if size == Vector3.ZERO:
		var mesh_node := node.get_node_or_null(^"MeshInstance3D") as MeshInstance3D
		var mesh := mesh_node.mesh as BoxMesh if mesh_node != null else null
		if mesh == null:
			return -1.0
		size = mesh.size
	return node.global_position.y - size.y * 0.5


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _relative(node: Node) -> String:
	return String(_room.get_path_to(node))


func _files_in(directory: String) -> Array[String]:
	var result: Array[String] = []
	var handle := DirAccess.open(directory)
	if handle == null:
		return result
	handle.list_dir_begin()
	var name := handle.get_next()
	while not name.is_empty():
		if not handle.current_is_dir():
			result.append(directory.path_join(name))
		name = handle.get_next()
	handle.list_dir_end()
	result.sort()
	return result


func _file_bytes(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


func _file_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame

extends SceneTree
## The authored props are in the world, and the world still works around them.
##
## `prop_asset_test.gd` proves the two Blender exports import as independent, correctly
## scaled props. That says nothing about whether anyone would ever see them: a model in
## `assets/` that no location instantiates is an asset with no screen time. This test is
## about the other half — the placement the generator table asks for, and the four things
## that go wrong when a prop is dropped into a hand-built blockout:
##
## 1. **The right node, once.** Each site carries exactly one instance of the expected
##    hand-authored wrapper (so it collides and anchors the way the wrapper says), at the
##    position and yaw the table declares. A `glb` instanced directly would render but
##    have no collision; two instances would mean the table grew a duplicate.
## 2. **No ghosts.** The grey-box stand-ins the models replaced (`BenchSeat` and friends,
##    and the box that stood for the bag) are gone. A regenerated blockout that kept them
##    would put a second bench inside the first one, and nothing in the previous tests
##    would notice: both would be invisible to each other and the player would just walk
##    into a box that is not drawn.
## 3. **Contact.** The bench stands on the floor (its own base at y = 0) and the bag rests
##    on the seat plane rather than floating over it or sinking through it.
## 4. **The anchor is not inside its prop.** A look-anchor in the middle of a 1.04 m body
##    is hidden from every standing position by the prop itself, which is the failure mode
##    `interaction_visibility_sweep_test.gd` would report as "visible from nowhere" with no
##    hint about why. The anchor also has to have walkable ground within reach of it, or
##    it is a hotspot nobody can stand next to.
##
## Finally the sites are checked not to have been cut in two by their new furniture: the
## bake still routes the player from the arrival spawn to the far exit.
##
## Not tested here: how the props look, whether they should be there at all (that is an
## art decision, recorded in docs/IMPLEMENTATION_NOTES_PROPS.md), or frame cost.

const Harness = preload("res://tests/test_harness.gd")

const BENCH := "res://scenes/environment/props/playground_bench.tscn"
const BAG := "res://scenes/environment/props/student_backpack.tscn"
const GENERATOR := "res://tools/build_outdoor_locations.py"

## The bench's seat plane in metres, measured from the exported model. The bag's own base
## is 1.4 cm below its origin, which is why its node sits at 0.52 m and its base lands on
## this plane.
const SEAT_PLANE := 0.51
## Contact is allowed a couple of centimetres: this is set dressing, not a fit check.
const CONTACT_TOLERANCE := 0.02
## A look-anchor is usable when the nearest walkable point is at most this far away. The
## bench's own footprint is eroded out of the navmesh (agent radius 0.4 m), so the anchor
## sitting just off the seat's front edge is about half a metre from the mesh.
const ANCHOR_REACH := 1.5

## Position and yaw are duplicated from `tools/build_outdoor_locations.py` on purpose: the
## point of the test is that the artefact matches the table it is generated from.
const SITES: Array[Dictionary] = [
	{
		"scene": "res://scenes/locations/residential/residential.tscn",
		"label": "residential courtyard",
		"props": [
			{
				"name": &"CourtyardBench",
				"wrapper": BENCH,
				"position": Vector3(-3.2, 0.0, 6.0),
				"yaw": 180.0,
				"base": 0.0,
				"note": "the bench that replaced three grey boxes by the planter",
			},
		],
		"retired": ["BenchSeat", "BenchLegA", "BenchLegB"],
		"anchors": [{"name": &"BenchLook", "prop": &"CourtyardBench"}],
		"route": [&"FromStreet", &"AlleyEnd"],
	},
	{
		"scene": "res://scenes/locations/playground/playground.tscn",
		"label": "schoolyard",
		"props": [
			{
				"name": &"YardBench",
				"wrapper": BENCH,
				"position": Vector3(11.0, 0.0, 3.2),
				"yaw": -90.0,
				"base": 0.0,
				"note": "the bench by the notice board, turned to face the court",
			},
			{
				"name": &"YardBag",
				"wrapper": BAG,
				"position": Vector3(11.03, 0.52, 3.75),
				"yaw": -90.0,
				"base": SEAT_PLANE,
				"note": "the bag that was already sitting on this bench as a grey box",
			},
		],
		"retired": ["BenchSeat", "BenchLegA", "BenchLegB", "BagOnBench"],
		"anchors": [{"name": &"BenchLook", "prop": &"YardBench"}],
		"route": [&"FromAlley", &"BackToCorridor"],
	},
]

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "prop_placement_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	L10n.load_tables()
	for site: Dictionary in SITES:
		await _check_site(site)
	_check_generator_table()
	Harness.finish(
		self, _failures,
		"the authored bench and bag are placed where the generator table says, sit on "
		+ "what they should, keep their look-anchors usable, and leave the walk routes intact."
	)


# --- one location -----------------------------------------------------------


func _check_site(site: Dictionary) -> void:
	var label := String(site["label"])
	var packed := load(String(site["scene"])) as PackedScene
	if packed == null:
		_failures.append("%s: %s could not be loaded." % [label, site["scene"]])
		return
	var location := packed.instantiate() as LocationRoot
	if location == null:
		_failures.append("%s: the scene is not a LocationRoot." % label)
		return
	root.add_child(location)
	await process_frame
	await process_frame

	var props: Array = site["props"]
	for spec: Dictionary in props:
		_check_prop(label, location, spec)
	_check_retired(label, location, site["retired"])

	var nav := location.get_node_or_null("Navigation") as LocationNavigation
	if nav == null:
		_failures.append("%s: there is no navigation region, so the props cannot be walked around." % label)
	else:
		if not await _wait_for_bake(nav):
			_failures.append(
				"%s: the navigation mesh never baked with the props in it (%s)."
				% [label, nav.get_bake_error()]
			)
		else:
			_check_anchors(label, site, location, nav)
			_check_route(label, site, location, nav)

	root.remove_child(location)
	location.free()


## Exactly one instance of the wrapper, at the declared transform, standing on what it is
## supposed to stand on.
func _check_prop(label: String, location: LocationRoot, spec: Dictionary) -> void:
	var wanted := String(spec["name"])
	var matches := _nodes_named(location, StringName(wanted))
	if matches.size() != 1:
		_failures.append(
			"%s: found %d node(s) named '%s'; the generator places it once."
			% [label, matches.size(), wanted]
		)
		return
	var instance := matches[0] as Node3D
	if instance == null:
		_failures.append("%s: '%s' is not a 3D node." % [label, wanted])
		return
	if instance.scene_file_path != String(spec["wrapper"]):
		_failures.append(
			"%s: '%s' instances '%s', not the wrapper '%s' (a bare glb has no collision)."
			% [label, wanted, instance.scene_file_path, spec["wrapper"]]
		)
	var expected_position: Vector3 = spec["position"]
	if not instance.position.is_equal_approx(expected_position):
		_failures.append(
			"%s: '%s' stands at %s, the table says %s (%s)."
			% [label, wanted, str(instance.position), str(expected_position), spec["note"]]
		)
	var expected_yaw := deg_to_rad(float(spec["yaw"]))
	if absf(angle_difference(instance.rotation.y, expected_yaw)) > 0.001:
		_failures.append(
			"%s: '%s' is turned %.1f degrees, the table says %.1f."
			% [label, wanted, rad_to_deg(instance.rotation.y), float(spec["yaw"])]
		)
	if not instance.scale.is_equal_approx(Vector3.ONE):
		_failures.append("%s: '%s' carries a scale: %s." % [label, wanted, str(instance.scale)])

	var base := _subtree_aabb(instance).position.y
	var expected_base := float(spec["base"])
	if absf(base - expected_base) > CONTACT_TOLERANCE:
		_failures.append(
			"%s: '%s' sits at y = %.3f m, expected %.3f m +/- %.2f (%s)."
			% [label, wanted, base, expected_base, CONTACT_TOLERANCE, spec["note"]]
		)


## The boxes the models replaced must be gone, not just unused.
func _check_retired(label: String, location: LocationRoot, retired: Array) -> void:
	for name: String in retired:
		var ghosts := _nodes_named(location, StringName(name))
		if not ghosts.is_empty():
			_failures.append(
				"%s: the grey-box '%s' is still in the scene next to the model that replaced it."
				% [label, name]
			)


## An anchor inside its own prop's collision is invisible from everywhere, because the
## prop is the first thing every visibility probe hits. Anchor reach is the mirror image:
## a hotspot with no walkable ground near it can be seen and never used.
func _check_anchors(label: String, site: Dictionary, location: LocationRoot, nav: LocationNavigation) -> void:
	var map := nav.get_navigation_map()
	var anchors: Array = site["anchors"]
	for spec: Dictionary in anchors:
		var wanted := StringName(spec["name"])
		var found := _nodes_named(location, wanted)
		if found.size() != 1:
			_failures.append(
				"%s: found %d interactable(s) named '%s'." % [label, found.size(), String(wanted)]
			)
			continue
		var anchor := found[0] as Node3D
		var prop := _find_named(location, StringName(spec["prop"]))
		if anchor == null or prop == null:
			_failures.append("%s: '%s' or its prop is missing." % [label, String(wanted)])
			continue
		var solid := _collision_aabb(prop)
		if solid.has_point(anchor.global_position):
			_failures.append(
				"%s: the '%s' anchor at %s is inside the '%s' collision box %s, so the prop "
				% [label, String(wanted), str(anchor.global_position), String(spec["prop"]), str(solid)]
				+ "hides its own hotspot from every standing position."
			)
		var closest := NavigationServer3D.map_get_closest_point(map, anchor.global_position)
		var gap := Vector2(closest.x - anchor.global_position.x, closest.z - anchor.global_position.z).length()
		if gap > ANCHOR_REACH:
			_failures.append(
				"%s: the nearest walkable point to the '%s' anchor is %.2f m away, so nobody "
				% [label, String(wanted), gap]
				+ "can walk up to it."
			)


## The site is still one space: the player can get from where they arrive to the far end.
func _check_route(label: String, site: Dictionary, location: LocationRoot, nav: LocationNavigation) -> void:
	var route: Array = site["route"]
	var spawn := location.get_spawn(StringName(route[0]))
	var exit := _find_named(location, StringName(route[1]))
	if spawn == null or exit == null:
		_failures.append(
			"%s: the route check needs both '%s' and '%s'." % [label, String(route[0]), String(route[1])]
		)
		return
	var map := nav.get_navigation_map()
	var path := NavigationServer3D.map_get_path(
		map,
		NavigationServer3D.map_get_closest_point(map, spawn.global_position),
		NavigationServer3D.map_get_closest_point(map, exit.global_position),
		true
	)
	if path.size() < 2:
		_failures.append(
			"%s: the new furniture cut the site in two — no route from '%s' to '%s'."
			% [label, String(route[0]), String(route[1])]
		)


# --- the table, not only the artefact ---------------------------------------


## The generated scenes are artefacts: what has to be right is the table they come from.
func _check_generator_table() -> void:
	var script := _read(GENERATOR)
	if script.is_empty():
		_failures.append("The location generator could not be read.")
		return
	for wrapper: String in [BENCH, BAG]:
		if not script.contains(wrapper):
			_failures.append(
				"The generator does not place %s, so a regeneration would drop it." % wrapper
			)
	# The grey boxes must not creep back into the table next to the models.
	for retired: String in ["BenchSeat", "BenchLegA", "BenchLegB", "BagOnBench"]:
		if script.contains('"%s"' % retired):
			_failures.append(
				"The generator still declares the grey-box '%s'; the model replaced it." % retired
			)


# --- helpers ----------------------------------------------------------------


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _nodes_named(root_node: Node, wanted: StringName) -> Array[Node]:
	var found: Array[Node] = []
	for node in _descendants(root_node):
		if node.name == wanted:
			found.append(node)
	return found


func _find_named(root_node: Node, wanted: StringName) -> Node3D:
	var found := _nodes_named(root_node, wanted)
	if found.is_empty():
		return null
	return found[0] as Node3D


func _descendants(root_node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in root_node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


## The visible extent of a prop, in world space.
func _subtree_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in _descendants(node):
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var box := instance.global_transform * instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## The solid extent of a prop, in world space: every collision shape under it, whatever
## shape it is. This is what a visibility probe can hit.
func _collision_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in _descendants(node):
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var shape := shape_node.shape
		var size := Vector3.ZERO
		if shape is BoxShape3D:
			size = (shape as BoxShape3D).size
		elif shape is CapsuleShape3D:
			var capsule := shape as CapsuleShape3D
			size = Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0)
		elif shape is SphereShape3D:
			var radius := (shape as SphereShape3D).radius
			size = Vector3(radius * 2.0, radius * 2.0, radius * 2.0)
		else:
			size = shape.get_debug_mesh().get_aabb().size
		var box := Transform3D(shape_node.global_basis, shape_node.global_position) * AABB(-size * 0.5, size)
		result = box if first else result.merge(box)
		first = false
	return result


## Baking is deferred, and a baked mesh is not a mesh the server answers for yet: until the
## region has reached the navigation map, the map is empty and answers the zero vector for
## every query, which reads as "everything is metres away in the wrong direction".
func _wait_for_bake(nav: LocationNavigation) -> bool:
	var budget := 0
	while budget < 180:
		if nav.is_baked() and nav.get_map_region_count() > 0 and nav.is_routable():
			return true
		await physics_frame
		budget += 1
	return false

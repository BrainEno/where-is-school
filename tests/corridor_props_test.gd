extends SceneTree
## The three corridor models from the #90 library, placed in the walkway.
##
##   godot --headless --path . --script res://tests/corridor_props_test.gd
##
## `tools/model_library.py --check` proves the files obey the model contract. That says
## nothing about the game: a model nobody instantiates has no screen time, and a model
## dropped into a hand-built blockout can be wrong in ways no file check sees. This test
## loads the real `corridor.tscn` and checks the walkway the player gets:
##
## 1. **Wrappers, not bare files.** Each model is reached through its hand-authored
##    wrapper in `scenes/environment/props/` - a `StaticBody3D` on the world layer, one
##    box collider that covers the model - and appears once, at the transform the table
##    below declares, with no scale.
## 2. **Against the right surface.** The noticeboard and the extinguisher have their
##    backs on the building wall's face (x = -2.1); the trolley stands on the floor and
##    parks against the parapet without reaching into its rail. Floating, sinking and
##    passing through the wall are all measured on the instantiated meshes.
## 3. **The working face looks into the walkway.** The library records two facing
##    conventions in one set (docs/MODEL_LIBRARY.md 2.5): the board's notices and the
##    extinguisher's gauge are authored on +Z, so a yaw that is right for a -Z model
##    would hang them face-to-the-wall with every size still matching. The front-detail
##    node of each model is found and required to sit on the walkway side.
## 4. **No ghosts.** The grey boxes the models replaced are gone.
## 5. **Still usable.** Every look-anchor is outside its prop's collision, declares the
##    prop as support for the line-of-sight probe, has walkable ground within reach, and
##    the walkway still connects the classroom door, the yard door and the gate.

const Harness = preload("res://tests/test_harness.gd")

const CORRIDOR := "res://scenes/locations/corridor/corridor.tscn"
const NOTICEBOARD := "res://scenes/environment/props/corridor_noticeboard.tscn"
const EXTINGUISHER := "res://scenes/environment/props/corridor_fire_extinguisher.tscn"
const TROLLEY := "res://scenes/environment/props/corridor_cleaning_trolley.tscn"

## The building wall's face on the walkway side: `WallBuilding` is 0.2 m thick at
## x = -2.2. The parapet's face is at x = 2.03 below its rail; the rail's face is at 1.97.
const WALL_FACE_X := -2.1
const RAIL_FACE_X := 1.97
## How far a back may stand off the wall, or a base off its surface, before it reads as
## floating. Set dressing, not a fit check.
const CONTACT_TOLERANCE := 0.02
## How far a collider may fall short of the visible model on any side.
const COLLIDER_SLACK := 0.01
## A look-anchor is usable when the nearest walkable point is at most this far away.
const ANCHOR_REACH := 1.2

## Position and yaw are repeated from `corridor.tscn` on purpose: the point is that the
## scene matches the decision, and a stray edit in the editor shows up here.
const PROPS: Array[Dictionary] = [
	{
		"name": &"CorridorNoticeboard",
		"wrapper": NOTICEBOARD,
		"model": "res://assets/models/corridor/corridor_noticeboard.glb",
		"position": Vector3(-1.99, 0.0, -2.0),
		"yaw": 90.0,
		# The board's origin is on the floor under it (min y 0.862 in the library), so it
		# is placed standing at the wall and its frame starts at that height.
		"base": 0.862,
		"wrapper_base": 0.862,
		"against": "wall",
		"front": "Notice_ink_mark",
		"anchor": &"NoticeboardInspect",
	},
	{
		"name": &"CorridorExtinguisher",
		"wrapper": EXTINGUISHER,
		"model": "res://assets/models/corridor/corridor_fire_extinguisher.glb",
		"position": Vector3(-1.98, 0.3, 0.1),
		"yaw": 90.0,
		# Wall-mounted on its own plate, clear of the 0.14 m skirting: the wrapper puts
		# the model's lowest point at its origin, and the instance lifts it to 0.30 m.
		"base": 0.30,
		"wrapper_base": 0.0,
		"against": "wall",
		"front": "Gauge_face",
		"anchor": &"ExtinguisherInspect",
	},
	{
		"name": &"CorridorTrolley",
		"wrapper": TROLLEY,
		"model": "res://assets/models/corridor/corridor_cleaning_trolley.glb",
		"position": Vector3(1.59, 0.0, 3.6),
		"yaw": -90.0,
		"base": 0.0,
		"wrapper_base": 0.0,
		"against": "parapet",
		"front": "Trolley_front_panel",
		"anchor": &"TrolleyInspect",
	},
]

## The grey boxes the three models replaced.
const RETIRED: Array[String] = [
	"NoticeboardFrame", "NoticeboardCork", "NoticePaperA", "NoticePaperB",
	"Extinguisher", "ExtinguisherBracket",
	"TrolleyBody", "TrolleyLid", "TrolleyBucket",
]

## Spawn -> exit pairs that must still be connected with the trolley's collider baked in.
const ROUTES: Array[Array] = [
	[&"FromClassroom", &"SchoolGateExit"],
	[&"FromClassroom", &"YardDoor"],
	[&"FromSchoolyard", &"SchoolGateExit"],
	[&"FromStreet", &"BackToClassroom"],
]

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "corridor_props_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	L10n.load_tables()
	for spec: Dictionary in PROPS:
		_check_wrapper(spec)

	var packed := load(CORRIDOR) as PackedScene
	if packed == null:
		Harness.finish(self, ["corridor.tscn could not be loaded."], "")
		return
	var location := packed.instantiate() as LocationRoot
	if location == null:
		Harness.finish(self, ["corridor.tscn is not a LocationRoot."], "")
		return
	root.add_child(location)
	await process_frame
	await process_frame

	for spec: Dictionary in PROPS:
		_check_placement(location, spec)
	_check_retired(location)

	var nav := location.get_node_or_null("Navigation") as LocationNavigation
	if nav == null:
		_failures.append("The corridor has no navigation region.")
	elif not await _wait_for_bake(nav):
		_failures.append("The corridor's navigation never baked with the props in it (%s)." % nav.get_bake_error())
	else:
		for spec: Dictionary in PROPS:
			_check_anchor(location, nav, spec)
		_check_routes(location, nav)

	root.remove_child(location)
	location.free()
	print("corridor props: %d checks" % _checks)
	Harness.finish(
		self,
		_failures,
		"the corridor noticeboard, extinguisher and trolley are placed through their wrappers, against the right surfaces, facing the walkway, with usable anchors and the walkway intact."
	)


# --- the wrapper on its own ---------------------------------------------------


func _check_wrapper(spec: Dictionary) -> void:
	var label := String(spec["name"])
	var packed := load(String(spec["wrapper"])) as PackedScene
	if packed == null:
		_failures.append("%s: the wrapper %s could not be loaded." % [label, spec["wrapper"]])
		return
	var wrapper := packed.instantiate() as StaticBody3D
	if wrapper == null:
		_failures.append("%s: the wrapper root is not a StaticBody3D." % label)
		return
	root.add_child(wrapper)
	_checks += 1
	if wrapper.collision_layer != 1 or wrapper.collision_mask != 0:
		_failures.append(
			"%s: the wrapper is on layer %d / mask %d, expected the world layer 1 / mask 0."
			% [label, wrapper.collision_layer, wrapper.collision_mask]
		)
	var model := wrapper.get_node_or_null("Model") as Node3D
	if model == null:
		_failures.append("%s: the wrapper has no Model child." % label)
	elif model.scene_file_path != String(spec["model"]):
		_failures.append(
			"%s: Model instances '%s', expected '%s'." % [label, model.scene_file_path, spec["model"]]
		)
	var shapes: Array[CollisionShape3D] = []
	for node in _descendants(wrapper):
		if node is CollisionShape3D:
			shapes.append(node as CollisionShape3D)
	if shapes.size() != 1 or not (shapes[0].shape is BoxShape3D):
		_failures.append("%s: the wrapper should carry exactly one box collider." % label)
	elif model != null:
		var drawn := _subtree_aabb(model)
		var solid := _collision_aabb(wrapper)
		for axis in 3:
			if solid.position[axis] > drawn.position[axis] + COLLIDER_SLACK \
					or solid.end[axis] < drawn.end[axis] - COLLIDER_SLACK:
				_failures.append(
					"%s: the collider %s does not cover the model %s." % [label, solid, drawn]
				)
				break
		# Floor and wall-plate props start at their origin (Model at y = -min y); the
		# noticeboard keeps its authored origin on the floor under the board.
		var wrapper_base := float(spec["wrapper_base"])
		if absf(drawn.position.y - wrapper_base) > CONTACT_TOLERANCE * 0.5:
			_failures.append(
				"%s: the wrapper's model starts at y = %.3f, expected %.3f."
				% [label, drawn.position.y, wrapper_base]
			)
	root.remove_child(wrapper)
	wrapper.free()


# --- the placement in the corridor -------------------------------------------


func _check_placement(location: LocationRoot, spec: Dictionary) -> void:
	var label := String(spec["name"])
	var matches := _nodes_named(location, StringName(spec["name"]))
	_checks += 1
	if matches.size() != 1:
		_failures.append("%s: found %d node(s) with that name, expected 1." % [label, matches.size()])
		return
	var instance := matches[0] as Node3D
	if instance.scene_file_path != String(spec["wrapper"]):
		_failures.append(
			"%s: instances '%s', not the wrapper '%s' (a bare glb has no collision)."
			% [label, instance.scene_file_path, spec["wrapper"]]
		)
	var expected_position: Vector3 = spec["position"]
	if not instance.position.is_equal_approx(expected_position):
		_failures.append("%s: stands at %s, expected %s." % [label, instance.position, expected_position])
	if absf(angle_difference(instance.rotation.y, deg_to_rad(float(spec["yaw"])))) > 0.001 \
			or absf(instance.rotation.x) > 0.001 or absf(instance.rotation.z) > 0.001:
		_failures.append(
			"%s: turned %s degrees, expected a pure yaw of %.1f."
			% [label, instance.rotation_degrees, float(spec["yaw"])]
		)
	if not instance.scale.is_equal_approx(Vector3.ONE):
		_failures.append("%s: carries a scale %s." % [label, instance.scale])

	var box := _subtree_aabb(instance)
	if absf(box.position.y - float(spec["base"])) > CONTACT_TOLERANCE:
		_failures.append(
			"%s: its lowest point is at y = %.3f, expected %.3f." % [label, box.position.y, float(spec["base"])]
		)
	var centre := box.get_center()
	var front := _front_centre(instance, String(spec["front"]))
	if front == Vector3.INF:
		_failures.append("%s: the front-detail node '%s' was not found in the model." % [label, spec["front"]])

	match String(spec["against"]):
		"wall":
			# Back on the wall face: not floating off it, not buried in it.
			if absf(box.position.x - WALL_FACE_X) > CONTACT_TOLERANCE:
				_failures.append(
					"%s: its back is at x = %.3f, the wall face is at %.3f." % [label, box.position.x, WALL_FACE_X]
				)
			if front != Vector3.INF and front.x <= centre.x:
				_failures.append(
					"%s: '%s' is on the wall side (x %.3f vs centre %.3f): it is hung facing the wall."
					% [label, spec["front"], front.x, centre.x]
				)
		"parapet":
			if box.end.x > RAIL_FACE_X + 0.001:
				_failures.append(
					"%s: reaches x = %.3f, into the parapet rail at %.3f." % [label, box.end.x, RAIL_FACE_X]
				)
			if RAIL_FACE_X - box.end.x > 0.05:
				_failures.append(
					"%s: stands %.2f m off the parapet; it is meant to be parked against it."
					% [label, RAIL_FACE_X - box.end.x]
				)
			if front != Vector3.INF and front.x >= centre.x:
				_failures.append(
					"%s: '%s' faces the parapet (x %.3f vs centre %.3f), not the walkway."
					% [label, spec["front"], front.x, centre.x]
				)


func _check_retired(location: LocationRoot) -> void:
	for name in RETIRED:
		_checks += 1
		if not _nodes_named(location, StringName(name)).is_empty():
			_failures.append("The grey box '%s' is still in the corridor next to the model that replaced it." % name)


# --- anchors and routes ---------------------------------------------------------


func _check_anchor(location: LocationRoot, nav: LocationNavigation, spec: Dictionary) -> void:
	var label := String(spec["name"])
	var found := _nodes_named(location, StringName(spec["anchor"]))
	var prop := _nodes_named(location, StringName(spec["name"]))
	_checks += 1
	if found.size() != 1 or prop.size() != 1:
		_failures.append("%s: the anchor '%s' or the prop is missing." % [label, spec["anchor"]])
		return
	var anchor := found[0] as Interactable
	if anchor == null:
		_failures.append("%s: '%s' is not an Interactable." % [label, spec["anchor"]])
		return
	var solid := _collision_aabb(prop[0])
	if solid.has_point(anchor.global_position):
		_failures.append(
			"%s: the anchor %s is inside the prop's collision %s." % [label, anchor.global_position, solid]
		)
	var body := prop[0] as CollisionObject3D
	if body == null or not anchor.get_support_rids().has(body.get_rid()):
		_failures.append(
			"%s: '%s' does not declare its prop in support_paths, so the prop can hide its own hotspot."
			% [label, spec["anchor"]]
		)
	var map := nav.get_navigation_map()
	var closest := NavigationServer3D.map_get_closest_point(map, anchor.global_position)
	var gap := Vector2(closest.x - anchor.global_position.x, closest.z - anchor.global_position.z).length()
	if gap > ANCHOR_REACH:
		_failures.append("%s: the nearest walkable point is %.2f m from '%s'." % [label, gap, spec["anchor"]])


func _check_routes(location: LocationRoot, nav: LocationNavigation) -> void:
	var map := nav.get_navigation_map()
	for pair: Array in ROUTES:
		_checks += 1
		var spawn := location.get_spawn(StringName(pair[0]))
		var targets := _nodes_named(location, StringName(pair[1]))
		if spawn == null or targets.is_empty():
			_failures.append("Route %s -> %s: one end is missing." % [pair[0], pair[1]])
			continue
		var goal := (targets[0] as Node3D).global_position
		var start := NavigationServer3D.map_get_closest_point(map, spawn.global_position)
		var end := NavigationServer3D.map_get_closest_point(map, goal)
		var path := NavigationServer3D.map_get_path(map, start, end, true)
		if path.size() < 2 or path[path.size() - 1].distance_to(end) > 0.3:
			_failures.append("Route %s -> %s: the walkway no longer connects them." % [pair[0], pair[1]])


# --- helpers ------------------------------------------------------------------


## World-space centre of every mesh in `instance` whose name starts with `prefix`
## (Godot turns the glTF `Notice_ink_mark.001` into `Notice_ink_mark_001`).
func _front_centre(instance: Node, prefix: String) -> Vector3:
	var box := AABB()
	var first := true
	for node in _descendants(instance):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or not String(mesh.name).begins_with(prefix):
			continue
		var world := mesh.global_transform * mesh.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return Vector3.INF if first else box.get_center()


func _nodes_named(root_node: Node, wanted: StringName) -> Array[Node]:
	var found: Array[Node] = []
	for node in _descendants(root_node):
		if node.name == wanted:
			found.append(node)
	return found


func _descendants(root_node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in root_node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


## The visible extent, in world space.
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


## The solid extent, in world space: every box collider under the node.
func _collision_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in _descendants(node):
		var shape_node := child as CollisionShape3D
		if shape_node == null or not (shape_node.shape is BoxShape3D):
			continue
		var size := (shape_node.shape as BoxShape3D).size
		var box := shape_node.global_transform * AABB(-size * 0.5, size)
		result = box if first else result.merge(box)
		first = false
	return result


func _wait_for_bake(nav: LocationNavigation) -> bool:
	var budget := 0
	while budget < 180:
		if nav.is_baked() and nav.get_map_region_count() > 0 and nav.is_routable():
			return true
		await physics_frame
		budget += 1
	return false

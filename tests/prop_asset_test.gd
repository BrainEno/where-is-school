extends SceneTree
## Prop asset check: the two Blender props import as independent, correctly scaled
## scenes and compose the way the Blender source does.
##
##   godot --headless --path . --script res://tests/prop_asset_test.gd
##
## The sizes and the seat height are the asset's own, measured from the exported
## GLB (see docs/IMPLEMENTATION_NOTES_PROPS.md). The tolerances are loose enough to
## survive a re-export that keeps the proportions, but not a silent rescale.

const Harness = preload("res://tests/test_harness.gd")

const BENCH_SCENE := "res://scenes/environment/props/playground_bench.tscn"
const BAG_SCENE := "res://scenes/environment/props/student_backpack.tscn"
const PREVIEW_SCENE := "res://scenes/dev/prop_asset_preview.tscn"

const BENCH_SIZE := Vector3(2.043, 1.040, 0.527)
const BAG_SIZE := Vector3(0.528, 0.498, 0.386)
const SIZE_TOLERANCE := 0.05

## The backpack's lowest point sits a little under its origin because of the lean
## it was authored with, so its base is measured against a small band, not an exact
## zero. What matters is that it is near its own base and not offset by the bench.
const BAG_BASE_MIN := -0.05
const BAG_BASE_MAX := 0.05

## The seat plane of this bench in metres. The backpack must rest on it, neither
## floating above it nor sunk through it.
const SEAT_HEIGHT := 0.501
const SEAT_TOLERANCE := 0.06

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 90.0, "prop_asset_test.gd")
	call_deferred("_run")


func _run() -> void:
	var bench := _instantiate(BENCH_SCENE, "playground_bench.tscn")
	var bag := _instantiate(BAG_SCENE, "student_backpack.tscn")
	if bench == null or bag == null:
		Harness.finish(self, _failures, "")
		return

	var holder := Node3D.new()
	holder.name = "PropTestHolder"
	root.add_child(holder)
	holder.add_child(bench)
	bag.position = Vector3(20, 0, 0)  # keep the two AABBs from overlapping
	holder.add_child(bag)
	await process_frame
	await process_frame

	Harness.stage = "bench"
	_expect_size("bench", _subtree_aabb(bench), BENCH_SIZE)
	_expect_single_mesh("bench", bench, 7)
	Harness.stage = "backpack"
	_expect_size("backpack", _subtree_aabb(bag), BAG_SIZE)
	_expect_single_mesh("backpack", bag, 6)
	_expect_independent(bench, bag)

	var bag_aabb := _subtree_aabb(bag)
	if bag_aabb.position.y < BAG_BASE_MIN or bag_aabb.position.y > BAG_BASE_MAX:
		_failures.append(
			(
				"The backpack does not rest on its own base: min y is %.4f, outside [%.2f, %.2f]. "
				+ "The standalone asset must not keep the bench-relative offset."
			)
			% [bag_aabb.position.y, BAG_BASE_MIN, BAG_BASE_MAX]
		)

	holder.queue_free()
	await process_frame

	Harness.stage = "preview"
	await _check_preview()

	Harness.finish(self, _failures, "both props import independently and compose on the bench.")


func _check_preview() -> void:
	var preview := _instantiate(PREVIEW_SCENE, "prop_asset_preview.tscn")
	if preview == null:
		return
	root.add_child(preview)
	await process_frame
	await process_frame

	var bench := preview.get_node_or_null("PlaygroundBench") as Node3D
	var bag := preview.get_node_or_null("StudentBackpack") as Node3D
	if bench == null or bag == null:
		_failures.append("The preview scene must expose PlaygroundBench and StudentBackpack.")
		preview.queue_free()
		return

	var ba := _subtree_aabb(bench)
	var ga := _subtree_aabb(bag)
	if ga.position.y < SEAT_HEIGHT - SEAT_TOLERANCE or ga.position.y > SEAT_HEIGHT + SEAT_TOLERANCE:
		_failures.append(
			(
				"The backpack does not sit on the seat: its base is y=%.4f, expected %.3f +/- %.2f."
			)
			% [ga.position.y, SEAT_HEIGHT, SEAT_TOLERANCE]
		)
	if not (ga.position.x > ba.position.x and ga.end.x < ba.end.x):
		_failures.append("The backpack is not within the bench's length.")
	if not (ga.position.z > ba.position.z and ga.end.z < ba.end.z):
		_failures.append("The backpack is not within the bench's depth.")

	var camera := preview.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		_failures.append("The preview scene has no Camera3D.")
	elif not camera.current:
		_failures.append("The preview camera is not current.")
	if preview.get_node_or_null("KeyLight") == null:
		_failures.append("The preview scene has no key light.")
	var environment := preview.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment == null or environment.environment == null:
		_failures.append("The preview scene has no environment.")

	preview.queue_free()
	await process_frame


func _instantiate(path: String, label: String) -> Node3D:
	var packed: PackedScene = load(path)
	if packed == null:
		_failures.append("%s could not be loaded (%s)." % [label, path])
		return null
	var node := packed.instantiate()
	if node == null:
		_failures.append("%s could not be instantiated." % label)
		return null
	return node as Node3D


func _expect_size(label: String, aabb: AABB, expected: Vector3) -> void:
	for axis in 3:
		var actual := aabb.size[axis]
		if absf(actual - expected[axis]) > SIZE_TOLERANCE:
			_failures.append(
				(
					"%s size on axis %d is %.3f m, expected %.3f m +/- %.2f "
					+ "(a scale or export problem)."
				)
				% [label, axis, actual, expected[axis], SIZE_TOLERANCE]
			)


func _expect_single_mesh(label: String, node: Node3D, surfaces: int) -> void:
	var mesh_nodes := node.find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.size() != 1:
		_failures.append("%s should be one MeshInstance3D, found %d." % [label, mesh_nodes.size()])
		return
	var mesh := (mesh_nodes[0] as MeshInstance3D).mesh
	if mesh == null:
		_failures.append("%s has no mesh." % label)
		return
	if mesh.get_surface_count() != surfaces:
		_failures.append(
			"%s has %d material surfaces, expected %d." % [label, mesh.get_surface_count(), surfaces]
		)


func _expect_independent(bench: Node3D, bag: Node3D) -> void:
	if bench.get_node_or_null("Model") == null or bag.get_node_or_null("Model") == null:
		_failures.append("A prop scene is missing its Model child.")
	var bench_mesh := _first_mesh(bench)
	var bag_mesh := _first_mesh(bag)
	if bench_mesh == null or bag_mesh == null:
		_failures.append("A prop scene has no mesh to compare.")
		return
	if bench_mesh == bag_mesh:
		_failures.append("The two props share one mesh resource; they must stay independent.")


func _first_mesh(node: Node) -> Mesh:
	var mesh_nodes := node.find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.is_empty():
		return null
	return (mesh_nodes[0] as MeshInstance3D).mesh


func _subtree_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		var box := instance.global_transform * instance.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result

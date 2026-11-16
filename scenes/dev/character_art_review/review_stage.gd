extends RefCounted
## Puts one character art review direction (issue #188) on the production protagonist and Q
## wrappers, at run time, without changing anything on disk.
##
## Used by the review scene (`character_art_review.tscn`) and by the in-game capture
## (`tests/capture_character_art_review.gd`). Everything it does is reversible in the same
## session and goes through the production wrappers' own public surface:
##   - the look: `CharacterLookApplier.look` is pointed at a review `CharacterLook` and
##     `apply_treatment(PAINTED)` is called, exactly as for the shipped look;
##   - the body language: a review `SkeletonModifier3D` (`pose_overlay.gd`) is added under
##     the model's skeleton, like the production `NpcGaze`; intensity 0 is the production pose;
##   - the hair: the protagonist's hair mesh instance is given a softened copy of its mesh
##     (`wilt_hair`), built in rest space before skinning. The GLB is not touched; the next
##     `apply_treatment()` puts the applier's own mesh back.
## No class_name: development code must not add to the game's global namespace.

const PoseOverlay = preload("res://scenes/dev/character_art_review/pose_overlay.gd")
const HERE := "res://scenes/dev/character_art_review"

## id -> what the direction is. `c` is the shipped look (production resources, read only),
## with the same body language and hair as the others so the comparison is the surface only.
const DIRECTIONS := {
	"c": {
		"label": "C (shipped look)",
		"protagonist": "res://assets/characters/protagonist/protagonist_look.tres",
		"q": "res://assets/characters/q/q_look.tres",
	},
	"d1": {
		"label": "D1 stage light",
		"protagonist": HERE + "/looks/d1_stage_protagonist.tres",
		"q": HERE + "/looks/d1_stage_q.tres",
	},
	"d2": {
		"label": "D2 charcoal + pastel",
		"protagonist": HERE + "/looks/d2_pastel_protagonist.tres",
		"q": HERE + "/looks/d2_pastel_q.tres",
	},
	"d3": {
		"label": "D3 colour planes",
		"protagonist": HERE + "/looks/d3_planes_protagonist.tres",
		"q": HERE + "/looks/d3_planes_q.tres",
	},
}
const ORDER: Array[String] = ["c", "d1", "d2", "d3"]

const POSE_NODE := "ReviewPose"
const HAIR_MESH := "Protagonist_Hair"
## Rest-space centre of the cranium and the radius past which hair is softened (metres),
## measured from Protagonist_Character.glb: head mesh x ±0.086, y 1.433-1.701, z -0.057-0.146;
## hair reaches y 1.767 and z 0.183 (spikes 4 cm in front of the face).
const HAIR_CENTER := Vector3(0.0, 1.61, 0.025)
const HAIR_KEEP_RADIUS := 0.1
const HAIR_KEEP_SHARE := 0.42
const HAIR_DROOP := 0.3

static var _wilted: Dictionary = {}


## Applies direction `id` to one wrapper (`who` is "protagonist" or "q"). Returns the
## applier's report, or {"error": ...}.
static func apply_look(wrapper: Node, who: String, id: String) -> Dictionary:
	if not DIRECTIONS.has(id):
		return {"error": "unknown direction %s" % id}
	var applier := wrapper.get_node_or_null(^"Look") as CharacterLookApplier
	if applier == null:
		return {"error": "%s has no Look applier" % wrapper.name}
	var look := load(String(DIRECTIONS[id][who])) as CharacterLook
	if look == null:
		return {"error": "look %s did not load" % String(DIRECTIONS[id][who])}
	applier.look = look
	return applier.apply_treatment(CharacterLookApplier.Treatment.PAINTED)


## Back to the shipped look, the GLB meshes and no review pose.
static func restore(wrapper: Node, who: String) -> void:
	apply_look(wrapper, who, "c")
	set_pose(wrapper, "", 0.0)


## Adds (or reuses) the review pose modifier. An empty profile removes it.
static func set_pose(wrapper: Node, profile: String, intensity: float = 1.0) -> Node:
	var animator := wrapper as CharacterVisualAnimation
	var skeleton: Skeleton3D = animator.get_skeleton() if animator != null else null
	if skeleton == null:
		return null
	var existing := skeleton.get_node_or_null(NodePath(POSE_NODE))
	if profile.is_empty():
		if existing != null:
			existing.queue_free()
		return null
	if existing == null:
		existing = PoseOverlay.new()
		existing.name = POSE_NODE
		skeleton.add_child(existing)
	existing.call("setup", animator, profile, intensity)
	return existing


static func get_pose(wrapper: Node) -> Node:
	var animator := wrapper as CharacterVisualAnimation
	var skeleton: Skeleton3D = animator.get_skeleton() if animator != null else null
	return skeleton.get_node_or_null(NodePath(POSE_NODE)) if skeleton != null else null


## Softens the protagonist's spikes: every hair vertex further than HAIR_KEEP_RADIUS from the
## cranium's centre is pulled in to HAIR_KEEP_SHARE of its excess and drooped, in rest space.
## Returns the number of vertices moved (0 when there is no hair mesh on this model).
static func wilt_hair(wrapper: Node) -> int:
	var hair: MeshInstance3D = null
	for node in wrapper.find_children(HAIR_MESH, "MeshInstance3D", true, false):
		hair = node as MeshInstance3D
	if hair == null or not (hair.mesh is ArrayMesh):
		return 0
	var source := hair.mesh as ArrayMesh
	var key := source.get_instance_id()
	if not _wilted.has(key):
		_wilted[key] = _wilt(source)
	var entry: Array = _wilted[key]
	var overrides: Array[Material] = []
	for surface in hair.get_surface_override_material_count():
		overrides.append(hair.get_surface_override_material(surface))
	hair.mesh = entry[0]
	for surface in overrides.size():
		hair.set_surface_override_material(surface, overrides[surface])
	return int(entry[1])


static func _wilt(source: ArrayMesh) -> Array:
	var wilted := ArrayMesh.new()
	wilted.resource_name = source.resource_name + " (review wilt)"
	var moved := 0
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var rest: PackedFloat32Array = PackedFloat32Array()
		var has_rest := arrays[Mesh.ARRAY_CUSTOM0] != null
		if has_rest:
			rest = arrays[Mesh.ARRAY_CUSTOM0]
		for index in vertices.size():
			var v := vertices[index]
			var offset := v - HAIR_CENTER
			var radius := offset.length()
			if radius <= HAIR_KEEP_RADIUS:
				continue
			var excess := radius - HAIR_KEEP_RADIUS
			var softened := HAIR_CENTER + offset / radius * (HAIR_KEEP_RADIUS + excess * HAIR_KEEP_SHARE)
			softened.y -= excess * HAIR_DROOP
			vertices[index] = softened
			moved += 1
			if has_rest and rest.size() >= (index + 1) * 4:
				rest[index * 4] = softened.x
				rest[index * 4 + 1] = softened.y
				rest[index * 4 + 2] = softened.z
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var flags := 0
		if has_rest:
			arrays[Mesh.ARRAY_CUSTOM0] = rest
			flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if int(source.surface_get_format(surface)) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		wilted.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], {}, flags)
		wilted.surface_set_material(surface, source.surface_get_material(surface))
		wilted.surface_set_name(surface, source.surface_get_name(surface))
	wilted.custom_aabb = source.custom_aabb
	return [wilted, moved]


## The whole review state on both characters at once.
static func apply(protagonist: Node, q: Node, id: String, posed: bool, soften_hair: bool) -> Dictionary:
	var report := {
		"direction": id,
		"protagonist": apply_look(protagonist, "protagonist", id),
		"q": apply_look(q, "q", id),
		"hair_vertices_moved": 0,
	}
	if soften_hair:
		report["hair_vertices_moved"] = wilt_hair(protagonist)
	set_pose(protagonist, "protagonist_withdrawn" if posed else "", 1.0)
	set_pose(q, "q_overfamiliar" if posed else "", 1.0)
	return report

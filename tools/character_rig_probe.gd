extends SceneTree
## Prints what Godot actually imported for each character model: the node tree, the
## Skeleton3D and its bones (rest and global rest axes), every embedded AnimationPlayer clip
## with its tracks and whether each track resolves, how meshes bind to the skeleton, and the
## report `CharacterAnimation.bind()` gives for the model.
##
##   godot --headless --path . --script res://tools/character_rig_probe.gd
##
## It is a diagnostic, not a test: it never fails, it reports. Every line starts with
## `RIG|` so a CI step can pick them out of the engine's own output.

const MODELS := [
	"res://assets/models/protagonist/Protagonist_Character.glb",
	"res://assets/models/protagonist/protagonist.glb",
	"res://assets/models/q/q.glb",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in MODELS:
		await _probe(path)
	_out("done")
	quit(0)


func _out(line: String) -> void:
	print("RIG|%s" % line)


func _v(value: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [value.x, value.y, value.z]


func _q(value: Quaternion) -> String:
	return "(%.4f,%.4f,%.4f,%.4f)" % [value.x, value.y, value.z, value.w]


func _probe(path: String) -> void:
	_out("== model %s" % path)
	var packed := load(path) as PackedScene
	if packed == null:
		_out("LOAD FAILED")
		return
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	_dump_tree(model)
	var skeletons := CharacterAnimation.skeletons_in(model)
	for skeleton in skeletons:
		_dump_skeleton(model, skeleton)
	for node in model.find_children("*", "AnimationPlayer", true, false):
		_dump_player(model, node as AnimationPlayer)
	var player := AnimationPlayer.new()
	model.add_child(player)
	player.root_node = player.get_path_to(model)
	var report := CharacterAnimation.bind(model, player)
	_out("bind %s" % CharacterAnimation.describe(report))
	_out("bind resolved %s" % str(report.get("resolved", {})))
	if not skeletons.is_empty():
		_dump_frames(model, skeletons[0], report.get("resolved", {}))
	model.queue_free()
	await process_frame


func _dump_tree(model: Node) -> void:
	var nodes: Array[Node] = [model]
	nodes.append_array(model.find_children("*", "", true, false))
	for node in nodes:
		var line := "node %s [%s]" % [String(model.get_path_to(node)), node.get_class()]
		var spatial := node as Node3D
		if spatial != null and not spatial.transform.is_equal_approx(Transform3D.IDENTITY):
			line += " pos=%s rot=%s scale=%s" % [
				_v(spatial.position), _v(spatial.rotation_degrees), _v(spatial.scale)
			]
		var mesh := node as MeshInstance3D
		if mesh != null:
			var surfaces := mesh.mesh.get_surface_count() if mesh.mesh != null else 0
			var shapes := 0
			if mesh.mesh is ArrayMesh:
				shapes = (mesh.mesh as ArrayMesh).get_blend_shape_count()
			line += " surfaces=%d blend_shapes=%d skeleton=%s skin=%s aabb=%s+%s" % [
				surfaces, shapes, String(mesh.skeleton), "yes" if mesh.skin != null else "no",
				_v(mesh.get_aabb().position), _v(mesh.get_aabb().size)
			]
			if mesh.skin != null:
				line += " skin_binds=%d" % mesh.skin.get_bind_count()
		_out(line)


func _dump_skeleton(model: Node3D, skeleton: Skeleton3D) -> void:
	_out("skeleton %s bones=%d" % [String(model.get_path_to(skeleton)), skeleton.get_bone_count()])
	for index in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(index)
		var global := skeleton.get_bone_global_rest(index)
		var parent := skeleton.get_bone_parent(index)
		_out(
			"bone %d %s parent=%s rest_pos=%s rest_rot=%s rest_scale=%s g_pos=%s g_x=%s g_y=%s g_z=%s"
			% [
				index, skeleton.get_bone_name(index),
				skeleton.get_bone_name(parent) if parent >= 0 else "-",
				_v(rest.origin), _q(rest.basis.get_rotation_quaternion()), _v(rest.basis.get_scale()),
				_v(global.origin), _v(global.basis.x.normalized()), _v(global.basis.y.normalized()),
				_v(global.basis.z.normalized()),
			]
		)


func _dump_player(model: Node3D, player: AnimationPlayer) -> void:
	var anim_root := player.get_node_or_null(player.root_node)
	_out(
		"player %s root=%s autoplay='%s' playing=%s current='%s'"
		% [
			String(model.get_path_to(player)), String(player.root_node), player.autoplay,
			str(player.is_playing()), player.current_animation,
		]
	)
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		for clip_name in library.get_animation_list():
			var animation := library.get_animation(clip_name)
			var kinds := {}
			var unresolved: Array[String] = []
			var targets := {}
			for track in animation.get_track_count():
				var kind := animation.track_get_type(track)
				kinds[kind] = int(kinds.get(kind, 0)) + 1
				var track_path := animation.track_get_path(track)
				targets[String(track_path)] = true
				var node_path := NodePath(String(track_path).get_slice(":", 0))
				var target: Node = anim_root.get_node_or_null(node_path) if anim_root != null else null
				if target == null:
					unresolved.append(String(track_path))
					continue
				var sub := track_path.get_concatenated_subnames()
				if target is Skeleton3D and not sub.is_empty():
					if (target as Skeleton3D).find_bone(sub) < 0 and (kind == Animation.TYPE_ROTATION_3D
							or kind == Animation.TYPE_POSITION_3D or kind == Animation.TYPE_SCALE_3D):
						unresolved.append(String(track_path))
			_out(
				"clip '%s/%s' length=%.4f loop=%d tracks=%d kinds=%s targets=%d unresolved=%d %s"
				% [
					String(library_name), String(clip_name), animation.length, animation.loop_mode,
					animation.get_track_count(), str(kinds), targets.size(), unresolved.size(),
					str(unresolved.slice(0, 6)),
				]
			)
			var sample: Array[String] = []
			for track in mini(animation.get_track_count(), 4):
				sample.append(String(animation.track_get_path(track)))
			_out("clip '%s' sample tracks %s" % [String(clip_name), str(sample)])


## For every resolved canonical bone: where it sits, which way it points, and how far its
## local X is from the character's side axis (+X, orthogonalised against the bone). This is
## the twist a local-axis clip offset inherits.
func _dump_frames(model: Node3D, skeleton: Skeleton3D, resolved: Dictionary) -> void:
	var to_model := model.global_transform.affine_inverse() * skeleton.global_transform
	for canonical: String in resolved:
		var index := skeleton.find_bone(String(resolved[canonical]))
		var basis := (to_model * skeleton.get_bone_global_rest(index)).basis.orthonormalized()
		var origin := to_model * skeleton.get_bone_global_rest(index).origin
		var along := basis.y.normalized()
		var side := (Vector3.RIGHT - along * along.dot(Vector3.RIGHT)).normalized()
		var twist := rad_to_deg(basis.x.normalized().signed_angle_to(side, along))
		_out(
			"frame %s=%s at=%s y=%s x=%s twist_from_side_axis=%.1f down_cos=%.3f"
			% [
				canonical, String(resolved[canonical]), _v(origin), _v(along),
				_v(basis.x.normalized()), twist, along.dot(Vector3.DOWN),
			]
		)

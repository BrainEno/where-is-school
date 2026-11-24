extends SceneTree
## Temporary diagnostic for issue #383 (removed once the budget question is settled).
## Prints the imported protagonist scene's mesh composition as a couple of PROBE lines;
## CI rewrites them into annotations, because the run log is not readable from the
## sandbox that needs this data. Every line is one annotation, so keep the count tiny.


func _initialize() -> void:
	var packed: PackedScene = load(
		"res://.godot/imported/Protagonist_Character.glb-ebb3eaa66604bdacba98b8035a6a4ac8.scn")
	if packed == null:
		print("PROBE failed: could not load the imported protagonist scene")
		quit(1)
		return
	var inst: Node = packed.instantiate()
	var meshes: PackedStringArray = []
	_collect_meshes(inst, "", meshes)
	print("PROBE meshes=", meshes.size(), " :: ", " | ".join(meshes))
	_walk_free(inst)
	var players: PackedStringArray = []
	_collect_animations(inst, "", players)
	print("PROBE animations :: ", " | ".join(players))
	quit(0)


func _collect_meshes(node: Node, path: String, out: PackedStringArray) -> void:
	var here: String = path + "/" + node.name
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		if mesh is ArrayMesh:
			var array_mesh: ArrayMesh = mesh
			var verts: PackedInt32Array = []
			for surface in array_mesh.get_surface_count():
				verts.append(array_mesh.surface_get_array_len(surface))
			out.append("%s s=%d bs=%d v=%s" % [here, array_mesh.get_surface_count(),
				array_mesh.get_blend_shape_count(), str(verts)])
		else:
			out.append("%s (not ArrayMesh)" % here)
	for child in node.get_children():
		_collect_meshes(child, here, out)


func _collect_animations(node: Node, path: String, out: PackedStringArray) -> void:
	var here: String = path + "/" + node.name
	if node is AnimationPlayer:
		var names: PackedStringArray = []
		var length: float = 0.0
		for library_name in node.get_animation_library_list():
			var library: AnimationLibrary = node.get_animation_library(library_name)
			for animation_name in library.get_animation_names():
				names.append(str(animation_name))
				length += library.get_animation(animation_name).length
		out.append("%s n=%d len=%.2f" % [here, names.size(), length])
	for child in node.get_children():
		_collect_animations(child, here, out)


func _walk_free(node: Node) -> void:
	for child in node.get_children():
		_walk_free(child)
	node.free()

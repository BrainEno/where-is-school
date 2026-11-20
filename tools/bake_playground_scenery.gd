extends SceneTree
## Offline builder run in build_playground_art.py's temporary import project.
## Save the same indexed meshes and material values in Godot's compressed format.

const ART := "res://scenes/environment/props/playground_art/"
const MESH_DIR := ART + "meshes/"
const SITE_MESH_PREFIX := MESH_DIR + "site_"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Expected source, output and any scenery-only material names.")
		quit(1)
		return
	var source := ResourceLoader.load(args[0], "PackedScene") as PackedScene
	if source == null or not source.can_instantiate():
		push_error("Could not load scenery source: %s" % args[0])
		quit(1)
		return
	var scenery := source.instantiate()
	var saved := _save_scenery(scenery, args[1], args.slice(2))
	scenery.free()
	quit(0 if saved and _save_detail_meshes() else 1)


func _save_scenery(scenery: Node, path: String, material_names: PackedStringArray) -> bool:
	var materials := {}
	for name in material_names:
		var material_path := ART + "materials/" + name + ".tres"
		var material := load(material_path) as StandardMaterial3D
		if material == null:
			push_error("Could not load scenery material: %s" % material_path)
			return false
		materials[material_path] = material.duplicate()
	var meshes := {}
	for node in scenery.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or instance.material_override == null:
			push_error("Missing mesh or material on scenery node %s." % instance.name)
			return false
		var material_path := instance.material_override.resource_path
		if materials.has(material_path):
			instance.material_override = materials[material_path] as Material
		var mesh_path := instance.mesh.resource_path
		if not mesh_path.begins_with(SITE_MESH_PREFIX):
			continue
		if not meshes.has(mesh_path):
			var local := instance.mesh.duplicate() as ArrayMesh
			if local == null or local.get_surface_count() == 0:
				push_error("Empty site mesh: %s" % mesh_path)
				return false
			meshes[mesh_path] = local
		instance.mesh = meshes[mesh_path] as ArrayMesh
	var baked := PackedScene.new()
	if baked.pack(scenery) != OK or ResourceSaver.save(baked, path, ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("Could not pack scenery: %s" % path)
		return false
	for dep in ResourceLoader.get_dependencies(path):
		if dep.contains(SITE_MESH_PREFIX) or _has_material_path(dep, materials):
			push_error("Scenery depends on a temporary resource: %s" % dep)
			return false
	print("PLAYGROUND_SCENERY_BAKE: embedded %d meshes and %d materials" % [meshes.size(), materials.size()])
	return true


func _has_material_path(dependency: String, materials: Dictionary) -> bool:
	for path: String in materials:
		if dependency.contains(path):
			return true
	return false


func _save_detail_meshes() -> bool:
	# Keep the existing props' .tscn files and node paths; only their mesh format changes.
	for obj in DirAccess.get_files_at(MESH_DIR):
		if not obj.ends_with(".obj") or obj.begins_with("site_"):
			continue
		var mesh := load(MESH_DIR + obj) as ArrayMesh
		var path := MESH_DIR + obj.get_basename() + ".mesh"
		if mesh == null or mesh.get_surface_count() == 0:
			push_error("Missing detail mesh: %s" % obj)
			return false
		if ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS) != OK:
			push_error("Could not save detail mesh: %s" % path)
			return false
	return true

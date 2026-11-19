@tool
extends EditorScenePostImport
## Godot 4.7.2 can see COLOR_0 only after choosing the first primitive's
## material. Keep the imported vertex channel and explicitly enable its use on
## this asset only, so the GLB's own materials work without the review wrapper.


func _post_import(scene: Node) -> Object:
	for part in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := (part as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR] != null:
				material.vertex_color_use_as_albedo = true
				# glTF COLOR_0 is linear; never ask the renderer to decode it twice.
				material.vertex_color_is_srgb = false
	return scene

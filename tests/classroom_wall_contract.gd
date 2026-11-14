extends RefCounted
## Live classroom wall checks, called by classroom_visual_slice_test.gd in CI.
## This is not a static .tres audit: the real camera/fader and physics world run.

const WALLS := {
	"WallNorth": Vector3.BACK,
	"WallWest": Vector3.RIGHT,
	"WallEast": Vector3.LEFT,
	"WallSouthLeft": Vector3.FORWARD,
	"WallSouthRight": Vector3.FORWARD,
}
const SPOTS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.85),
	Vector3(1.6, 0.0, 2.7),
	Vector3(3.5, 0.0, 0.9),
	Vector3(3.2, 0.0, 2.85),
	Vector3(-3.8, 0.0, 2.7),
	Vector3(-3.8, 0.0, -2.4),
	Vector3(0.0, 0.0, -2.5),
	Vector3(2.5, 0.0, 1.7),
	Vector3(5.6, 0.0, -3.55),
	Vector3(5.6, 0.0, 3.55),
	Vector3(-5.6, 0.0, 2.2),
]


static func verify(tree: SceneTree, main: Node, room: Node3D, failures: Array[String]) -> void:
	var player := main.get_node("Player") as PlayerController
	var start := player.global_transform
	var original: Dictionary = {}
	player.teleport(Transform3D(Basis(), Vector3(0.0, 0.0, 0.85)))
	await _frames(tree, 25)
	for wall_name: String in WALLS:
		var wall := room.get_node(NodePath(wall_name)) as StaticBody3D
		var paint := wall.get_node("Paint") as MeshInstance3D
		var normal := paint.global_basis.z.normalized()
		_expect(
			normal.dot(WALLS[wall_name]) > 0.999,
			"%s paint faces out of the room." % wall_name,
			failures
		)
		var shell := wall.get_node("MeshInstance3D") as MeshInstance3D
		var shell_size := (shell.mesh as BoxMesh).size
		var half_depth := (shell_size.x if absf(normal.x) > 0.5 else shell_size.z) * 0.5
		var separation := (paint.position.dot(WALLS[wall_name])) - half_depth
		_expect(
			separation >= 0.003 and separation < 0.02,
			(
				"%s paint/shell separation %.5f risks z-fighting or floating paint."
				% [wall_name, separation]
			),
			failures
		)
		for node in wall.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			original[mesh] = mesh.material_override
			var material := mesh.material_override as BaseMaterial3D
			_expect(
				material != null,
				"%s has no fade-compatible authored material." % mesh.name,
				failures
			)
			if mesh == paint or mesh == shell:
				_expect(
					material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
					"%s is authored transparent." % room.get_path_to(mesh),
					failures
				)
				_expect(
					material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY,
					"%s has a non-opaque depth policy." % room.get_path_to(mesh),
					failures
				)
				_expect(
					(
						material.cull_mode == BaseMaterial3D.CULL_BACK
						and material.albedo_color.a == 1.0
					),
					"%s lost opaque, inward-facing wall rendering." % room.get_path_to(mesh),
					failures
				)

	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	var faded_states := 0
	for spot in SPOTS:
		for facing: Vector3 in [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD]:
			var yaw := atan2(-facing.x, -facing.z)
			if is_zero_approx(yaw):
				yaw = 0.0001
			player.teleport(Transform3D(Basis(Vector3.UP, yaw), spot))
			await _frames(tree, 20)
			for key: Variant in original:
				var mesh := key as MeshInstance3D
				var authored := original[key] as BaseMaterial3D
				var drawn := mesh.material_override as BaseMaterial3D
				if mesh.transparency > 0.01:
					faded_states += 1
					if forward_plus:
						_expect(
							drawn == authored,
							(
								"Forward+ multiplied material alpha into the instance fade: %s."
								% room.get_path_to(mesh)
							),
							failures
						)
					else:
						_expect(
							(
								drawn != null
								and drawn.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
							),
							"Compatibility/Mobile has no real material fade: %s." % mesh.name,
							failures
						)
						if drawn != null:
							var expected_alpha := (
								(1.0 - mesh.transparency) * authored.albedo_color.a
							)
							_expect(
								absf(drawn.albedo_color.a - expected_alpha) < 0.001,
								"%s has an incorrect fade alpha." % mesh.name,
								failures
							)
				else:
					_expect(
						drawn == authored,
						"%s did not restore its exact authored material." % mesh.name,
						failures
					)
				_expect(
					not mesh.name.contains("Banner"),
					"The removed banner is still drawable.",
					failures
				)
	_expect(faded_states > 0, "The wall sweep never exercised a real camera occlusion.", failures)
	player.teleport(Transform3D(Basis(), Vector3(0.0, 0.0, 0.85)))
	await _frames(tree, 30)
	for key: Variant in original:
		var mesh := key as MeshInstance3D
		_expect(
			is_zero_approx(mesh.transparency) and mesh.material_override == original[key],
			"%s stayed transparent after leaving the wall." % room.get_path_to(mesh),
			failures
		)
	print(
		(
			"CLASSROOM_WALL_CONTRACT spots=%d facings=3 faded_states=%d renderer=%s"
			% [
				SPOTS.size(),
				faded_states,
				RenderingServer.get_current_rendering_method(),
			]
		)
	)
	player.teleport(start)
	await _frames(tree, 25)


static func _frames(tree: SceneTree, count: int) -> void:
	for _index in count:
		await tree.physics_frame


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)

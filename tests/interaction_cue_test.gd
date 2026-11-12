extends SceneTree
## The two cues the mouse draws: the outline on the object you can use, and the mark where a
## click lands.
##
## These are not rendering tests - a headless run draws nothing. They pin down what a code
## reviewer can check without a picture:
##
## 1. the ground mark is a thin ring with a dot, not a filled disc: small, open, and in the
##    shared unshaded material; it lands (contracts onto its radius), sends one echo outwards,
##    and is then still, because the walk is the animation;
## 2. the role decides the colour, and a refused click is a different gesture from an
##    accepted one - no dot, no echo, a contraction, and it ends by itself;
## 3. the mark lies on the surface it was given (the ground normal);
## 4. the object cue is an *outline of the object*: highlighting a prop marks that prop's own
##    meshes for `OutlineOverlay`, un-highlighting gives the meshes back exactly the layers
##    they had, a second object takes the outline over without the first one's late fade
##    erasing it, and an object with no mesh falls back to a small diamond rather than to
##    nothing;
## 5. the pointer finds an object where its outline is drawn: each outline mesh adds a pick
##    box to the object's area, and a ray at the mesh hits the object.
##
## Shipped content (every interactable resolves meshes; nothing authored sits on the outline
## overlay's visual layer) is `tests/interaction_outline_content_test.gd`.

const Harness = preload("res://tests/test_harness.gd")
const InteractableScene := preload("res://scenes/interaction/interactable.tscn")

const TIMEOUT_SECONDS := 90.0
## Long enough for every fade in this file to finish.
const FADE_WAIT := 0.4

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "interaction_cue_test.gd")
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 1.0
	await _check_world_cue_geometry()
	await _check_destination_roles()
	await _check_destination_lands_then_holds()
	await _check_destination_geometry()
	await _check_refusal_contracts()
	await _check_dismiss()
	await _check_outline_of_the_object()
	await _check_outline_hand_over()
	await _check_outline_fallback()
	await _check_pick_where_drawn()
	Harness.finish(
		self,
		_failures,
		"%d checks: the ground mark is a small ring that lands, echoes once and holds; the "
		% _checks
		+ "object cue outlines the object's own meshes, hands over cleanly, restores what it "
		+ "marked, falls back when there is nothing to trace, and is pointable where drawn."
	)


# --- shared geometry --------------------------------------------------------


func _check_world_cue_geometry() -> void:
	Harness.stage = "world cue geometry"
	var ring := WorldCue.ring_mesh(0.3, 0.02)
	_expect(ring != null and ring.get_surface_count() > 0, "The ring mesh has no surface.")
	if ring != null and ring.get_surface_count() > 0:
		var aabb := ring.get_aabb()
		_expect(
			absf(aabb.size.x - 0.62) < 0.03 and absf(aabb.size.z - 0.62) < 0.03,
			"A 0.3 m ring with a 2 cm pen is %.3f x %.3f across, not 0.62 m."
			% [aabb.size.x, aabb.size.z]
		)
		# Open, not filled: a ring covers its pen's width times its circumference, a small
		# fraction of the disc it encloses.
		var disc := WorldCue.disc_mesh(0.31, 40)
		_expect(
			_mesh_area(ring) < _mesh_area(disc) * 0.25,
			"The ring covers %.4f m2 against %.4f for the disc it encloses; it is filled."
			% [_mesh_area(ring), _mesh_area(disc)]
		)

	var mark := WorldCue.destination_mark_mesh()
	_expect(mark.get_surface_count() > 0, "The destination mark has no surface.")
	var radius := WorldCue.mark_footprint_radius()
	# About 30 cm across: big enough to read at the camera's distance, a fraction of the
	# 0.52 m rings of the first design.
	_expect(
		radius > 0.12 and radius < 0.2,
		"The mark's footprint radius is %.3f m; it should be about 0.16." % radius
	)
	_expect(
		_mesh_area(mark) < 0.035,
		"The mark covers %.3f m2 of floor; it is a ring and a dot, not a decal." % _mesh_area(mark)
	)

	for role: String in WorldCue.ROLES:
		var material := WorldCue.material_for(role)
		_expect(material != null, "Role '%s' has no material." % role)
		if material == null:
			continue
		_expect(
			material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
			"Role '%s' is shaded; a cue must not be lit by the room it sits in." % role
		)
		_expect(
			material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
			"Role '%s' is not alpha-blended." % role
		)
		_expect(
			material.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"Role '%s' culls its back faces; a ring tilted onto a ramp would vanish." % role
		)
		_expect(
			material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED,
			"Role '%s' writes depth; it would punch a hole in what is behind it." % role
		)
		_expect(
			material.albedo_color.a > 0.0 and material.albedo_color.a < 1.0,
			"Role '%s' is drawn at alpha %.2f." % [role, material.albedo_color.a]
		)
	_expect(
		WorldCue.color_for(WorldCue.ROLE_TARGET) != WorldCue.color_for(WorldCue.ROLE_DESTINATION),
		"A click on an object and a click on the floor are drawn in the same colour."
	)
	_expect(
		WorldCue.color_for(WorldCue.ROLE_REFUSED) != WorldCue.color_for(WorldCue.ROLE_DESTINATION),
		"A refused click looks like an accepted one."
	)
	_expect(
		WorldCue.is_known_role(WorldCue.ROLE_TARGET) and not WorldCue.is_known_role("nonsense"),
		"Role validation does not tell a role from a typo."
	)
	_expect(WorldCue.shard_mesh(0.05).get_surface_count() > 0, "The fallback shard has no surface.")
	await process_frame


# --- destination cue --------------------------------------------------------


func _check_destination_roles() -> void:
	Harness.stage = "destination roles"
	var cue := DestinationCue.new()
	root.add_child(cue)
	await process_frame
	_expect(not cue.is_shown(), "A fresh destination cue claims to be shown.")
	_expect(cue.get_role() == "", "A fresh destination cue already has a role: '%s'." % cue.get_role())
	cue.dismiss()
	cue.dismiss(true)
	await process_frame

	cue.show_destination(Vector3(1.0, 0.0, 2.0))
	_expect(cue.is_shown(), "show_destination() did not show the cue.")
	_expect(cue.get_role() == WorldCue.ROLE_DESTINATION, "A floor click is drawn as '%s'." % cue.get_role())
	_expect(
		(cue.global_position - Vector3(1.0, 0.0, 2.0)).length() < 0.1,
		"The cue was not placed at the clicked point: %s." % str(cue.global_position)
	)
	var parts := cue.get_parts()
	for part_name: String in ["ring", "dot", "echo"]:
		var part := parts.get(part_name, null) as MeshInstance3D
		_expect(part != null, "The ground mark has no '%s'." % part_name)
		if part == null:
			continue
		_expect(part.mesh != null, "The ground mark's '%s' has no mesh." % part_name)
		_expect(part.visible, "The '%s' of an accepted click is hidden." % part_name)
		_expect(
			part.material_override == WorldCue.material_for(WorldCue.ROLE_DESTINATION),
			"The '%s' of a floor click is not in the destination material." % part_name
		)
		_expect(
			part.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"The ground mark's '%s' casts a shadow." % part_name
		)
	_expect(
		absf(cue.get_footprint_radius() - WorldCue.mark_footprint_radius()) < 0.03,
		"The cue's ring (%.3f m) is not the shipped mark (%.3f m)."
		% [cue.get_footprint_radius(), WorldCue.mark_footprint_radius()]
	)

	cue.show_target(Vector3(1.0, 0.0, 2.0))
	_expect(cue.get_role() == WorldCue.ROLE_TARGET, "A click on an object is drawn as '%s'." % cue.get_role())
	var ring := cue.get_parts()["ring"] as MeshInstance3D
	if ring != null:
		_expect(
			ring.material_override == WorldCue.material_for(WorldCue.ROLE_TARGET),
			"A click on an object is not drawn in the target colour."
		)
	cue.queue_free()
	await process_frame


func _check_destination_lands_then_holds() -> void:
	Harness.stage = "destination lands"
	var cue := DestinationCue.new()
	root.add_child(cue)
	await process_frame
	cue.show_destination(Vector3.ZERO)
	var ring := cue.get_parts()["ring"] as MeshInstance3D
	var dot := cue.get_parts()["dot"] as MeshInstance3D
	if ring == null or dot == null:
		_failures.append("The ground mark's parts could not be inspected.")
		cue.queue_free()
		return
	# It lands: wide first, onto its radius after a fifth of a second.
	_expect(
		ring.scale.x > 1.4,
		"The ring does not start wide (scale %.2f); it should land, not appear." % ring.scale.x
	)
	_expect(dot.scale.x < 0.2, "The dot is already full size before the ring has landed.")
	var echo_seen := 0.0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 450:
		await process_frame
		echo_seen = maxf(echo_seen, cue.get_echo_opacity())
	_expect(
		absf(ring.scale.x - 1.0) < 0.02,
		"The ring did not settle on its radius (scale %.3f)." % ring.scale.x
	)
	_expect(absf(dot.scale.x - 1.0) < 0.05, "The dot never reached full size (%.3f)." % dot.scale.x)
	_expect(cue.get_opacity() > 0.95, "The mark never became fully visible (%.2f)." % cue.get_opacity())
	_expect(echo_seen > 0.2, "The echo never went out (peak opacity %.2f)." % echo_seen)
	# The echo goes once and is gone; the mark then holds still for the rest of the walk.
	await _wait(0.6)
	_expect(cue.get_echo_opacity() < 0.02, "The echo is still drawn (%.2f)." % cue.get_echo_opacity())
	var scale_before := ring.scale.x
	var rotation_before := ring.rotation.y
	await _wait(0.4)
	_expect(is_equal_approx(ring.scale.x, scale_before), "The ring breathes after it landed.")
	_expect(is_equal_approx(ring.rotation.y, rotation_before), "The ring turns after it landed.")
	_expect(cue.visible and cue.is_shown(), "The mark disappeared while the walk was still going.")
	cue.queue_free()
	await process_frame


func _check_destination_geometry() -> void:
	Harness.stage = "destination geometry"
	var cue := DestinationCue.new()
	root.add_child(cue)
	await process_frame
	var slope := Vector3(0.35, 0.92, 0.0).normalized()
	cue.show_destination(Vector3.ZERO, slope)
	await process_frame
	var up := cue.global_transform.basis.y.normalized()
	_expect(up.dot(slope) > 0.98, "The mark was not laid on the ground normal (dot %.3f)." % up.dot(slope))
	_expect(
		cue.global_position.dot(slope) > 0.0 and cue.global_position.length() < 0.05,
		"The mark is not lifted just off the surface it lies on: %s." % str(cue.global_position)
	)
	cue.queue_free()
	await process_frame


func _check_refusal_contracts() -> void:
	Harness.stage = "refusal"
	var cue := DestinationCue.new()
	root.add_child(cue)
	await process_frame
	cue.show_refused(Vector3.ZERO)
	_expect(cue.get_role() == WorldCue.ROLE_REFUSED, "A refused click has role '%s'." % cue.get_role())
	var ring := cue.get_parts()["ring"] as MeshInstance3D
	var dot := cue.get_parts()["dot"] as MeshInstance3D
	var echo := cue.get_parts()["echo"] as MeshInstance3D
	_expect(ring != null and ring.visible, "A refused click draws nothing.")
	if ring == null:
		cue.queue_free()
		return
	_expect(
		ring.material_override == WorldCue.material_for(WorldCue.ROLE_REFUSED),
		"A refused click is not drawn in the refusal colour."
	)
	_expect(dot != null and not dot.visible, "A refused click draws the dot of an accepted one.")
	_expect(echo != null and not echo.visible, "A refused click sends the echo of an accepted one.")
	await _wait(0.25)
	_expect(ring.scale.x < 0.95, "The refusal does not contract (scale %.2f at 0.25 s)." % ring.scale.x)
	await _wait(0.5)
	_expect(not cue.is_shown(), "The refusal cue did not end itself.")
	_expect(not cue.visible, "The refusal cue is still drawn after it ended.")
	cue.queue_free()
	await process_frame


func _check_dismiss() -> void:
	Harness.stage = "dismiss"
	var cue := DestinationCue.new()
	root.add_child(cue)
	await process_frame
	cue.show_destination(Vector3.ZERO)
	await _wait(0.05)
	cue.dismiss()
	_expect(not cue.is_shown(), "The cue still reports itself shown after dismiss().")
	await _wait(FADE_WAIT)
	_expect(not cue.visible, "The dismissed cue is still visible.")
	_expect(cue.get_opacity() < 0.05, "The dismissed cue is still drawn at opacity %.2f." % cue.get_opacity())
	cue.show_destination(Vector3.ZERO)
	await process_frame
	_expect(cue.visible, "The cue cannot be shown again after being dismissed.")
	cue.dismiss(true)
	_expect(not cue.visible, "dismiss(true) did not remove the cue at once.")
	cue.queue_free()
	await process_frame


# --- the object outline -----------------------------------------------------


## A prop with a mesh of its own beside it, named through `outline_paths`, and a second
## mesh parented under the interactable, which is always included.
func _make_prop(id: StringName, at: Vector3) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "Prop_%s" % String(id)
	holder.position = at
	root.add_child(holder)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 1.2, 0.4)
	body.mesh = box
	body.position = Vector3(0.0, 0.6, -1.2)
	body.layers = 1 | 4
	holder.add_child(body)
	var probe := InteractableScene.instantiate() as Interactable
	probe.interact_id = id
	probe.radius = 0.8
	probe.position = Vector3(0.0, 0.9, 0.0)
	probe.outline_paths = PackedStringArray(["../Body"])
	var tag := MeshInstance3D.new()
	tag.name = "Tag"
	var tag_mesh := BoxMesh.new()
	tag_mesh.size = Vector3(0.1, 0.1, 0.1)
	tag.mesh = tag_mesh
	probe.add_child(tag)
	holder.add_child(probe)
	return {"holder": holder, "probe": probe, "body": body, "tag": tag}


func _check_outline_of_the_object() -> void:
	Harness.stage = "outline of the object"
	var prop := _make_prop(&"outline_probe", Vector3(0.0, 0.0, 0.0))
	var probe := prop["probe"] as Interactable
	var body := prop["body"] as MeshInstance3D
	var tag := prop["tag"] as MeshInstance3D
	await process_frame
	await process_frame
	var meshes := probe.get_outline_meshes()
	_expect(meshes.has(body), "The mesh named in outline_paths is not traced.")
	_expect(meshes.has(tag), "A mesh parented under the interactable is not traced.")

	probe.set_highlighted(true)
	var cue := probe.get_cue()
	_expect(cue != null, "The highlighted prop has no cue.")
	if cue == null:
		(prop["holder"] as Node).queue_free()
		return
	_expect(cue.is_revealed(), "The highlighted prop's cue was not revealed.")
	_expect(cue.is_outlining(), "The prop has meshes but the cue fell back instead of outlining.")
	var shard := cue.get_parts().get("shard", null) as MeshInstance3D
	_expect(shard == null or not shard.visible, "An outlined prop also draws the fallback shard.")
	var overlay := cue.get_overlay()
	_expect(overlay != null, "The outline has no overlay to draw it.")
	await _wait(FADE_WAIT)
	if overlay != null:
		_expect(overlay.is_owned_by(cue), "The overlay is not drawing this prop's outline.")
		_expect(overlay.is_active(), "The overlay is not active while the prop is highlighted.")
		_expect(overlay.get_opacity() > 0.95, "The outline never faded in (%.2f)." % overlay.get_opacity())
		var viewport := overlay.get_mask_viewport()
		_expect(
			viewport != null and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
			"The silhouette mask is not being rendered while an outline is shown."
		)
	_expect(
		body.layers & OutlineOverlay.MASK_LAYER != 0,
		"The traced mesh is not on the outline layer while highlighted."
	)
	_expect(body.layers & 1 != 0 and body.layers & 4 != 0, "Marking the mesh removed its own layers.")

	probe.set_highlighted(false)
	_expect(not cue.is_revealed(), "The cue stayed revealed after the prop was un-highlighted.")
	await _wait(FADE_WAIT)
	_expect(body.layers == (1 | 4), "Releasing the outline did not restore the mesh's layers (%d)." % body.layers)
	_expect(tag.layers == 1, "Releasing the outline did not restore the child mesh's layers (%d)." % tag.layers)
	if overlay != null:
		_expect(not overlay.is_active(), "The overlay is still drawing after the outline was released.")
		var viewport := overlay.get_mask_viewport()
		_expect(
			viewport == null or viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"The silhouette mask keeps rendering with nothing to outline."
		)
	_expect(not cue.visible, "The cue is still drawn after the prop was un-highlighted.")
	(prop["holder"] as Node).queue_free()
	await process_frame


## The controller moves the highlight from one object to the next in a single frame: the
## first object's fade-out is still running when the second one takes the overlay. That
## late fade must not dim or erase the second outline.
func _check_outline_hand_over() -> void:
	Harness.stage = "outline hand-over"
	var first := _make_prop(&"outline_first", Vector3(-2.0, 0.0, 0.0))
	var second := _make_prop(&"outline_second", Vector3(2.0, 0.0, 0.0))
	var first_probe := first["probe"] as Interactable
	var second_probe := second["probe"] as Interactable
	await process_frame
	first_probe.set_highlighted(true)
	await _wait(FADE_WAIT)
	first_probe.set_highlighted(false)
	second_probe.set_highlighted(true)
	await _wait(FADE_WAIT)
	var overlay := second_probe.get_cue().get_overlay() if second_probe.get_cue() != null else null
	_expect(overlay != null, "The second object has no overlay.")
	if overlay != null:
		_expect(overlay.is_owned_by(second_probe.get_cue()), "The overlay did not pass to the second object.")
		_expect(overlay.is_active(), "The first object's fade-out erased the second object's outline.")
		_expect(overlay.get_opacity() > 0.95, "The first object's fade-out dimmed the second outline.")
	var first_body := first["body"] as MeshInstance3D
	var second_body := second["body"] as MeshInstance3D
	_expect(
		first_body.layers & OutlineOverlay.MASK_LAYER == 0,
		"The first object is still marked after the highlight moved on."
	)
	_expect(
		second_body.layers & OutlineOverlay.MASK_LAYER != 0,
		"The second object is not marked while it holds the highlight."
	)
	second_probe.set_highlighted(false)
	await _wait(FADE_WAIT)
	# Freeing a highlighted object hands its meshes back as well.
	first_probe.set_highlighted(true)
	await process_frame
	(first["holder"] as Node).queue_free()
	await process_frame
	await process_frame
	if overlay != null:
		_expect(not overlay.is_active(), "The overlay kept drawing a prop that was freed.")
	(second["holder"] as Node).queue_free()
	await process_frame


func _check_outline_fallback() -> void:
	Harness.stage = "outline fallback"
	var probe := InteractableScene.instantiate() as Interactable
	probe.interact_id = &"bare_probe"
	probe.radius = 0.8
	root.add_child(probe)
	await process_frame
	_expect(probe.get_outline_meshes().is_empty(), "A bare interactable claims meshes to outline.")
	probe.set_highlighted(true)
	var cue := probe.get_cue()
	_expect(cue != null and cue.is_revealed(), "A bare interactable cannot be highlighted.")
	if cue != null:
		_expect(not cue.is_outlining(), "A bare interactable reports an outline with nothing to trace.")
		var shard := cue.get_parts().get("shard", null) as MeshInstance3D
		_expect(shard != null and shard.visible, "A bare interactable is highlighted by nothing at all.")
		await _wait(FADE_WAIT)
		_expect(cue.get_opacity() > 0.95, "The fallback never faded in (%.2f)." % cue.get_opacity())
		if shard != null:
			var tumble_before := shard.rotation.y
			await _wait(0.2)
			_expect(tumble_before != shard.rotation.y, "The fallback shard does not move.")
		probe.set_highlighted(false)
		await _wait(FADE_WAIT)
		_expect(not cue.visible, "The fallback is still drawn after the highlight ended.")
	probe.queue_free()
	await process_frame


# --- picking where the outline is -------------------------------------------


func _check_pick_where_drawn() -> void:
	Harness.stage = "pick where drawn"
	var prop := _make_prop(&"pick_probe", Vector3(0.0, 0.0, 6.0))
	var probe := prop["probe"] as Interactable
	var body := prop["body"] as MeshInstance3D
	await process_frame
	await process_frame
	await physics_frame
	await physics_frame
	var shapes := probe.get_pick_shapes()
	_expect(shapes.size() == 2, "Two outline meshes built %d pick boxes, not 2." % shapes.size())
	var centre := body.global_transform * body.get_aabb().get_center()
	var covering := false
	for shape in shapes:
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		var local := shape.global_transform.affine_inverse() * centre
		if absf(local.x) <= box.size.x * 0.5 and absf(local.y) <= box.size.y * 0.5 \
				and absf(local.z) <= box.size.z * 0.5:
			covering = true
	_expect(covering, "No pick box covers the centre of the outlined mesh.")
	# A ray at the middle of the body, from the side away from the anchor, finds the object:
	# the anchor sphere (0.8 m radius, 1.2 m in front of the body) does not reach there.
	var space := probe.get_world_3d().direct_space_state
	var from := centre + Vector3(2.5, 0.0, -0.1)
	var query := PhysicsRayQueryParameters3D.create(from, centre + Vector3(-0.1, 0.0, 0.0), Interactable.INTERACTION_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := space.intersect_ray(query)
	_expect(
		not hit.is_empty() and hit.get("collider") == probe,
		"A ray at the outlined mesh does not find the object (hit: %s)." % str(hit.get("collider", null))
	)
	(prop["holder"] as Node).queue_free()
	await process_frame


# --- helpers ----------------------------------------------------------------


## Total area of a mesh's triangles in the XZ plane.
func _mesh_area(mesh: ArrayMesh) -> float:
	var total := 0.0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		# `SurfaceTool.commit()` writes a plain triangle list unless `index()` was called, and
		# a missing index array is `null`, not an empty one.
		var raw_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var order: Array[int] = []
		if raw_indices is PackedInt32Array:
			for value: int in (raw_indices as PackedInt32Array):
				order.append(value)
		else:
			for vertex in vertices.size():
				order.append(vertex)
		var index := 0
		while index + 2 < order.size():
			var a := vertices[order[index]]
			var b := vertices[order[index + 1]]
			var c := vertices[order[index + 2]]
			total += absf((b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)) * 0.5
			index += 3
	return total


func _wait(seconds: float) -> void:
	if seconds > 0.0:
		await create_timer(seconds).timeout
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)

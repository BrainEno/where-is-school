extends SceneTree
## The two cues the mouse draws: the one on the object you can use, and the one where a
## click lands.
##
## These are not rendering tests — a headless run draws nothing. They pin down the things
## that made the old cues feel cheap and that a code reviewer can check without a picture:
##
## 1. the cue has the parts it promises (`GroundRing`, `Halo`, `Shard` for the object;
##    one mark for the ground), and the parts are meshes with the shared unshaded material
##    rather than nothing or a placeholder;
## 2. the ground mark is *small and still*: its footprint is a fraction of the old ring's,
##    it inks in once and then does not rotate, breathe or grow, because the walk is the
##    animation; the object cue is the half that moves (it spins, bobs and breathes);
## 3. the role decides the colour, and a refused click is a different role from an
##    accepted one — an accepted mark sits still, a refused one contracts and leaves;
## 4. the ring lies on the surface it was given (the ground normal), so a ramp gets a ring
##    on the ramp;
## 5. a cue hides itself when it is finished and does not linger, and the ring's radius
##    follows the interaction radius instead of being one fixed size for every prop.
##
## `Interactable` and `PointerNavigator` are exercised at their seams — `set_highlighted`
## and the cue's own API — because a navigation mesh and a camera are not needed to ask
## whether the cue is drawn, and making the test depend on them would test the room.

const Harness = preload("res://tests/test_harness.gd")
const InteractableScene := preload("res://scenes/interaction/interactable.tscn")

const TIMEOUT_SECONDS := 60.0
## Long enough for every fade in this file to finish, short enough that three of them do
## not dominate the run.
const FADE_WAIT := 0.32

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "interaction_cue_test.gd")
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 1.0
	await _check_world_cue_geometry()
	await _check_hover_cue_shape()
	await _check_hover_cue_animates()
	await _check_interactable_wiring()
	await _check_destination_roles()
	await _check_destination_geometry()
	await _check_mark_footprint()
	await _check_refusal_collapses()
	await _check_dismiss()
	Harness.finish(
		self,
		_failures,
		"the object cue is built and animated, the ground mark is small, still and laid on "
		+ "the ground, both are tied to a role, and both hide when they are finished."
	)


# --- shared geometry --------------------------------------------------------


func _check_world_cue_geometry() -> void:
	Harness.stage = "world cue geometry"
	var ring := WorldCue.dashed_ring_mesh(0.3)
	_expect(ring != null and ring.get_surface_count() > 0, "The dashed ring mesh has no surface.")
	if ring != null and ring.get_surface_count() > 0:
		var aabb := ring.get_aabb()
		_expect(
			absf(aabb.size.x - 0.6) < 0.08 and absf(aabb.size.z - 0.6) < 0.08,
			"The dashed ring's footprint is %.3f x %.3f, not the 0.6 m it was asked for."
			% [aabb.size.x, aabb.size.z]
		)

	# Real dashes, not a solid hoop: a ring with gaps covers well under the full
	# circumference, and the gaps are what make its rotation visible at all.
	var solid := WorldCue.dashed_ring_mesh(0.3, WorldCue.RING_ARCS, 0.0)
	var dashed := WorldCue.dashed_ring_mesh(0.3, WorldCue.RING_ARCS, 0.5)
	_expect(
		_mesh_area(solid) > _mesh_area(dashed) * 1.5,
		"A ring with 50%% gaps covers about as much as a solid one (%.4f vs %.4f)."
		% [_mesh_area(dashed), _mesh_area(solid)]
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

	# The roles must be tellable apart, or the colour is decoration.
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
	_expect(WorldCue.disc_mesh(0.05).get_surface_count() > 0, "The dot mesh has no surface.")
	_expect(WorldCue.shard_mesh(0.05).get_surface_count() > 0, "The shard mesh has no surface.")
	await process_frame


# --- hover cue --------------------------------------------------------------


func _check_hover_cue_shape() -> void:
	Harness.stage = "hover cue shape"
	var cue := HoverCue.new()
	cue.setup(1.0, 0.0)
	root.add_child(cue)
	await process_frame

	var parts := cue.get_parts()
	for part_name: String in ["ring", "halo", "shard"]:
		var part: Variant = parts.get(part_name, null)
		_expect(part is MeshInstance3D, "The hover cue has no '%s' part." % part_name)
		var mesh_part := part as MeshInstance3D
		if mesh_part == null:
			continue
		_expect(mesh_part.mesh != null, "The hover cue's '%s' has no mesh." % part_name)
		var material := mesh_part.material_override as StandardMaterial3D
		_expect(material != null, "The hover cue's '%s' has no material." % part_name)
		_expect(
			mesh_part.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"The hover cue's '%s' casts a shadow." % part_name
		)
	_expect(not cue.visible, "The hover cue is visible before it was revealed.")
	_expect(not cue.is_revealed(), "The hover cue reports itself revealed before it was.")

	# The ring follows the interaction radius: the same cue on a wide prop and on a narrow
	# one must not be the same size, because the ring marks where the player stands.
	var narrow := HoverCue.new()
	narrow.setup(0.5, 0.0)
	root.add_child(narrow)
	var wide := HoverCue.new()
	wide.setup(2.0, 0.0)
	root.add_child(wide)
	await process_frame
	var narrow_ring := (narrow.get_parts()["ring"] as MeshInstance3D).mesh
	var wide_ring := (wide.get_parts()["ring"] as MeshInstance3D).mesh
	_expect(
		wide_ring.get_aabb().size.x > narrow_ring.get_aabb().size.x * 1.4,
		"The hover ring is the same size for a 0.5 m prop and a 2.0 m one (%.3f vs %.3f)."
		% [wide_ring.get_aabb().size.x, narrow_ring.get_aabb().size.x]
	)
	narrow.queue_free()
	wide.queue_free()
	await process_frame

	cue.queue_free()
	await process_frame


func _check_hover_cue_animates() -> void:
	Harness.stage = "hover cue animation"
	var cue := HoverCue.new()
	cue.setup(1.0, 0.0)
	root.add_child(cue)
	await process_frame
	await _wait(FADE_WAIT)
	_expect(cue.get_opacity() < 0.05, "An unrevealed hover cue is not fully transparent.")

	cue.reveal()
	await process_frame
	_expect(cue.visible, "The hover cue is not visible after reveal().")
	_expect(cue.is_revealed(), "The hover cue does not report itself revealed.")
	await _wait(FADE_WAIT)
	_expect(
		cue.get_opacity() > 0.95,
		"The hover cue never finished fading in (opacity %.2f)." % cue.get_opacity()
	)
	var ring := cue.get_parts()["ring"] as MeshInstance3D
	var shard := cue.get_parts()["shard"] as MeshInstance3D
	_expect(
		ring.transparency < 0.05,
		"The revealed ring is drawn at transparency %.2f." % ring.transparency
	)
	var spin_before := ring.rotation.y
	var bob_before := shard.position.y
	var tumble_before := shard.rotation.y
	await _wait(0.25)
	_expect(spin_before != ring.rotation.y, "The hover ring does not turn.")
	_expect(bob_before != shard.position.y, "The shard above the object does not bob.")
	_expect(tumble_before != shard.rotation.y, "The shard does not tumble.")

	cue.conceal()
	await _wait(FADE_WAIT)
	_expect(not cue.is_revealed(), "The hover cue still reports itself revealed after conceal().")
	_expect(cue.get_opacity() < 0.05, "The concealed hover cue is still drawn.")
	_expect(not cue.visible, "The concealed hover cue is still visible.")
	cue.queue_free()
	await process_frame


## The object's side of the same promise: highlighting the prop draws the cue, and only
## then. The controller owns *which* object is highlighted; this test owns the wiring.
func _check_interactable_wiring() -> void:
	Harness.stage = "interactable wiring"
	var probe := InteractableScene.instantiate() as Interactable
	_expect(probe != null, "The interactable scene did not instantiate as an Interactable.")
	if probe == null:
		return
	probe.interact_id = &"cue_probe"
	probe.radius = 1.0
	root.add_child(probe)
	await process_frame
	_expect(probe.get_cue() == null or not probe.is_highlighted(), "A fresh prop is already lit.")
	probe.set_highlighted(true)
	_expect(probe.is_highlighted(), "set_highlighted(true) did not take.")
	var cue := probe.get_cue()
	_expect(cue != null, "The highlighted prop has no cue.")
	if cue != null:
		_expect(cue.is_revealed(), "The highlighted prop's cue was not revealed.")
		await _wait(FADE_WAIT)
		_expect(cue.get_opacity() > 0.95, "The prop's cue never became visible.")
	probe.set_highlighted(false)
	_expect(not probe.is_highlighted(), "set_highlighted(false) did not take.")
	if cue != null:
		_expect(not cue.is_revealed(), "The cue stayed lit after the prop was un-highlighted.")
		await _wait(FADE_WAIT)
		_expect(not cue.visible, "The cue is still drawn after the prop was un-highlighted.")
	probe.queue_free()
	await process_frame


# --- destination cue --------------------------------------------------------


func _check_destination_roles() -> void:
	Harness.stage = "destination roles"
	var cue := DestinationCue.new()
	root.add_child(cue)
	await process_frame
	_expect(not cue.is_shown(), "A fresh destination cue claims to be shown.")
	_expect(cue.get_role() == "", "A fresh destination cue already has a role: '%s'." % cue.get_role())
	# Dismissing something that was never shown must be a no-op, not an error.
	cue.dismiss()
	cue.dismiss(true)
	await process_frame

	cue.show_destination(Vector3(1.0, 0.0, 2.0))
	_expect(cue.is_shown(), "show_destination() did not show the cue.")
	_expect(
		cue.get_role() == WorldCue.ROLE_DESTINATION,
		"A floor click is drawn as '%s'." % cue.get_role()
	)
	_expect(
		(cue.global_position - Vector3(1.0, 0.0, 2.0)).length() < 0.1,
		"The cue was not placed at the clicked point: %s." % str(cue.global_position)
	)
	var mark := cue.get_parts()["mark"] as MeshInstance3D
	_expect(mark != null, "An accepted click draws nothing.")
	if mark != null:
		_expect(mark.visible, "The mark of an accepted click is not visible.")
		_expect(
			mark.material_override == WorldCue.material_for(WorldCue.ROLE_DESTINATION),
			"A floor click is not drawn with the destination material."
		)
		_expect(mark.mesh != null, "The mark has no mesh.")
	# One part, not four: the redesign replaced the ripple/dot/core/refusal set with a single
	# mark, and a second part appearing again would mean the old vocabulary came back.
	_expect(
		cue.get_parts().size() == 1,
		"The ground cue has %d parts; it is one mark now." % cue.get_parts().size()
	)

	cue.show_target(Vector3(1.0, 0.0, 2.0))
	_expect(
		cue.get_role() == WorldCue.ROLE_TARGET,
		"A click on an object is drawn as '%s'." % cue.get_role()
	)
	if mark != null:
		_expect(
			mark.material_override == WorldCue.material_for(WorldCue.ROLE_TARGET),
			"A click on an object is not drawn in the target colour."
		)
	cue.queue_free()
	await process_frame


func _check_destination_geometry() -> void:
	Harness.stage = "destination geometry"
	var cue := DestinationCue.new()
	root.add_child(cue)
	await process_frame
	# A tilted surface: the ring has to lie on it, not cut through it.
	var slope := Vector3(0.35, 0.92, 0.0).normalized()
	cue.show_destination(Vector3.ZERO, slope)
	await process_frame
	var up := cue.global_transform.basis.y.normalized()
	_expect(
		up.dot(slope) > 0.98,
		"The mark was not laid on the ground normal (dot %.3f)." % up.dot(slope)
	)
	var mark := cue.get_parts()["mark"] as MeshInstance3D
	if mark == null:
		_failures.append("The destination mark could not be inspected.")
		return
	# It inks in over a seventh of a second...
	var scale_at_start := mark.scale.x
	await _wait(0.25)
	_expect(cue.get_opacity() > 0.95, "The mark never became visible (%.2f)." % cue.get_opacity())
	_expect(
		mark.scale.x > scale_at_start,
		"The mark did not settle into place (%.2f -> %.2f)." % [scale_at_start, mark.scale.x]
	)
	# ...and then it is still. The old cue spun and breathed for the whole walk, which is
	# exactly what made it feel like a generic effect rather than a mark on the floor.
	var rotation_before := mark.rotation.y
	var scale_before := mark.scale.x
	await _wait(0.6)
	_expect(
		is_equal_approx(mark.rotation.y, rotation_before),
		"The ground mark turns after it was drawn; the walk is the animation."
	)
	_expect(
		is_equal_approx(mark.scale.x, scale_before),
		"The ground mark breathes after it was drawn (%.3f -> %.3f)."
		% [scale_before, mark.scale.x]
	)
	_expect(cue.visible, "The mark disappeared while the walk was still going.")
	cue.queue_free()
	await process_frame


func _check_refusal_collapses() -> void:
	Harness.stage = "refusal"
	var cue := DestinationCue.new()
	root.add_child(cue)
	await process_frame
	cue.show_refused(Vector3.ZERO)
	_expect(cue.get_role() == WorldCue.ROLE_REFUSED, "A refused click has role '%s'." % cue.get_role())
	var mark := cue.get_parts()["mark"] as MeshInstance3D
	_expect(mark != null and mark.visible, "A refused click draws nothing.")
	if mark == null:
		return
	_expect(
		mark.material_override == WorldCue.material_for(WorldCue.ROLE_REFUSED),
		"A refused click is not drawn in the refusal colour."
	)
	# Inward is the meaning: an outward gesture promises a walk, and here there is none.
	await _wait(0.22)
	_expect(
		mark.scale.x < 1.0,
		"The refusal does not contract (scale %.2f at 0.22 s)." % mark.scale.x
	)
	# It ends by itself: a refusal is not something the player has to dismiss.
	await _wait(0.6)
	_expect(not cue.is_shown(), "The refusal cue did not end itself.")
	_expect(not cue.visible, "The refusal cue is still drawn after it ended.")
	cue.queue_free()
	await process_frame


## The redesign's headline claim, measured rather than asserted in prose: the mark is a
## fraction of the ring it replaced, and it still puts ink on the floor.
func _check_mark_footprint() -> void:
	Harness.stage = "mark footprint"
	var mark := WorldCue.destination_mark_mesh()
	_expect(mark.get_surface_count() > 0, "The destination mark has no surface.")
	var box := mark.get_aabb()
	var width := box.end.x - box.position.x
	var depth := box.end.z - box.position.z
	# 0.26 m was the radius of the old core ring, i.e. 0.52 m across. The mark has to be
	# well under half of that, or the round did not actually make it smaller.
	_expect(
		maxf(width, depth) < 0.26,
		"The mark is %.2f m across; the ring it replaced was 0.52 m." % maxf(width, depth)
	)
	_expect(
		maxf(width, depth) > 0.08,
		"The mark is only %.2f m across: small is not the same as invisible." % maxf(width, depth)
	)
	var radius := WorldCue.mark_footprint_radius()
	_expect(
		radius > 0.03 and radius < 0.13,
		"The mark's footprint radius is %.3f m." % radius
	)
	# Open, not closed: the old cue was a ring, and a ring encloses an area. If the mark ever
	# grows a closed outline again, its filled area would jump — this is the cheapest way to
	# notice while still allowing any hand-drawn shape.
	var area := _mesh_area(mark)
	_expect(
		area < 0.02,
		"The mark covers %.3f m² of floor; it is meant to be strokes, not a filled shape." % area
	)
	var strokes := WorldCue.stroke_mesh(Vector2.ZERO, Vector2(0.1, 0.0), 0.02, 0.4)
	_expect(strokes.get_surface_count() > 0, "A single stroke of the pen builds no surface.")
	_expect(
		_mesh_area(strokes) > 0.0,
		"A single stroke of the pen covers no area; it would be invisible."
	)
	var arc := WorldCue.arc_mesh(0.08, 0.0, 70.0, 0.02)
	_expect(arc.get_surface_count() > 0, "An arc of the pen builds no surface.")


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


# --- helpers ----------------------------------------------------------------


## Total area of a mesh's triangles, in the XZ plane. Used to prove a dashed ring has
## gaps instead of trusting the parameter that was passed in.
func _mesh_area(mesh: ArrayMesh) -> float:
	var total := 0.0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		# `SurfaceTool.commit()` writes a plain triangle list unless `index()` was called,
		# so both shapes have to be read here — and the missing index array is `null`, not
		# an empty array, which is why it is kept in a Variant first.
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
			# The meshes lie in XZ, so the area is half the 2D cross product.
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

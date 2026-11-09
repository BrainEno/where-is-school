extends SceneTree
## The two cues the mouse draws: the one on the object you can use, and the one where a
## click lands.
##
## These are not rendering tests — a headless run draws nothing. They pin down the things
## that made the old cues feel cheap and that a code reviewer can check without a picture:
##
## 1. the cue has the parts it promises (`GroundRing`, `Halo`, `Shard`; ripple, dot, core,
##    refusal), and the parts are meshes with the shared unshaded material rather than
##    nothing or a placeholder;
## 2. the cue is *animated*: it spins, it bobs, it breathes and it fades in and out over
##    time instead of switching between two frames;
## 3. the role decides the colour, and a refused click is a different role from an
##    accepted one — an expanding ring means "walk", a collapsing one means "no";
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
	await _check_refusal_collapses()
	await _check_dismiss()
	Harness.finish(
		self,
		_failures,
		"both cues are built, animated, tied to a role, laid on the ground, and hide when "
		+ "they are finished."
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
	var parts := cue.get_parts()
	var ripple := parts["ripple"] as MeshInstance3D
	var core := parts["core"] as MeshInstance3D
	var refusal := parts["refusal"] as MeshInstance3D
	_expect(ripple != null and ripple.visible, "An accepted click has no ripple.")
	_expect(core != null and core.visible, "An accepted click leaves no ring to walk towards.")
	_expect(refusal != null and not refusal.visible, "An accepted click also shows the refusal ring.")
	_expect(
		(cue.get_parts()["ripple"] as MeshInstance3D).material_override
			== WorldCue.material_for(WorldCue.ROLE_DESTINATION),
		"A floor click is not drawn with the destination material."
	)

	cue.show_target(Vector3(1.0, 0.0, 2.0))
	_expect(
		cue.get_role() == WorldCue.ROLE_TARGET,
		"A click on an object is drawn as '%s'." % cue.get_role()
	)
	_expect(
		(cue.get_parts()["core"] as MeshInstance3D).material_override
			== WorldCue.material_for(WorldCue.ROLE_TARGET),
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
		"The ring was not laid on the ground normal (dot %.3f)." % up.dot(slope)
	)
	var ripple := cue.get_parts()["ripple"] as MeshInstance3D
	var start_scale := ripple.scale.x
	await _wait(0.2)
	_expect(
		ripple.scale.x > start_scale * 1.15,
		"The ripple does not expand (%.2f -> %.2f)." % [start_scale, ripple.scale.x]
	)
	var core := cue.get_parts()["core"] as MeshInstance3D
	var spin_before := core.rotation.y
	await _wait(0.2)
	_expect(spin_before != core.rotation.y, "The ring left for the player to walk towards does not turn.")
	# The ripple is a gesture: it is over well before the walk is.
	await _wait(0.5)
	_expect(not ripple.visible, "The ripple is still drawn half a second after the click.")
	_expect(core.visible, "The walk's own ring disappeared while the walk was still going.")
	cue.queue_free()
	await process_frame


func _check_refusal_collapses() -> void:
	Harness.stage = "refusal"
	var cue := DestinationCue.new()
	root.add_child(cue)
	await process_frame
	cue.show_refused(Vector3.ZERO)
	_expect(cue.get_role() == WorldCue.ROLE_REFUSED, "A refused click has role '%s'." % cue.get_role())
	var parts := cue.get_parts()
	var refusal := parts["refusal"] as MeshInstance3D
	var ripple := parts["ripple"] as MeshInstance3D
	_expect(refusal.visible, "A refused click draws nothing.")
	_expect(not ripple.visible, "A refused click draws an expanding ring, which promises a walk.")
	var start := refusal.scale.x
	await _wait(0.18)
	_expect(
		refusal.scale.x < start * 0.92,
		"The refused ring expands (%.2f -> %.2f) instead of collapsing." % [start, refusal.scale.x]
	)
	# It ends by itself: a refusal is not something the player has to dismiss.
	await _wait(0.6)
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

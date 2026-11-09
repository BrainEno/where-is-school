class_name WorldCue
extends RefCounted
## The visual language of the cues the mouse draws in the world.
##
## Two things get drawn: the cue on the object the player would use, and the cue where a
## click lands. They live in one place — the palette, the pen width, the dash rhythm and
## the material rules — because two cues that disagree about thickness and colour read as
## two different tools rather than one instrument.
##
## Everything here is unshaded, untextured and alpha-only, and every mesh is built from
## code. No art asset, no shader, no import step, and nothing that has to be re-authored
## when a scene, a prop or a camera distance changes.
##
## The palette, in the language of `docs/ART_BIBLE.md` (restrained: no gloss, no
## gradients, no ornamental frames):
##
## * **bone** — where you clicked. Paper-coloured and quiet; a destination is information,
##   not an event.
## * **amber** — the thing you clicked or the thing you can use. The one warm accent the
##   world already carries, kept to a single hue so the two cues feel related.
## * **rose** — refused. Duller than either, and never a bright red: a refusal, not an
##   alarm. The player learns it in one click and it never competes with the scene.
##
## Motion is what separates a cue from a decal: the callers animate their own parts (see
## `hover_cue.gd` and `destination_cue.gd`). This file only knows how a cue is *drawn*.

## Roles. Strings, not an enum: a role ends up in a test assertion and in a log line, and
## `"target"` is worth more there than `2`.
const ROLE_DESTINATION := "destination"
const ROLE_TARGET := "target"
const ROLE_REFUSED := "refused"
const ROLES: Array[String] = [ROLE_DESTINATION, ROLE_TARGET, ROLE_REFUSED]

## Ring stroke width in metres. Shared by every cue so the pen looks the same at the
## player's feet and on a door frame four metres away.
const RING_THICKNESS := 0.035
## How much of each arc is left empty, as a fraction of the arc. This is what makes a ring
## read as a mark someone drew rather than a glowing hoop.
const RING_GAP_RATIO := 0.42
const RING_ARCS := 8
## Vertices per drawn arc. Six is enough that the arc looks curved at gameplay distance
## and keeps the mesh a few hundred triangles.
const ARC_STEPS := 6

## Opacity per role. The refused cue is dimmer than the other two on purpose.
const ALPHA_DESTINATION := 0.62
const ALPHA_TARGET := 0.58
const ALPHA_REFUSED := 0.42
## Emission, kept low: the cue has to survive a dusk-lit room without glowing in it.
const EMISSION_ENERGY := 0.75

## One material per role, shared by every instance of that role. Instances fade
## themselves through `GeometryInstance3D.transparency`, which is per node, so a shared
## material costs nothing and a per-instance copy would be pure waste.
static var _materials: Dictionary = {}


## The colour of a role, at full strength. Unknown roles fall back to bone rather than to
## an invisible white: a typo should look wrong in a screenshot, not vanish.
static func color_for(role: String) -> Color:
	match role:
		ROLE_TARGET:
			return Color(1.0, 0.82, 0.52)
		ROLE_REFUSED:
			return Color(0.82, 0.55, 0.49)
		_:
			return Color(0.91, 0.88, 0.79)


## The alpha a role is drawn at when it is fully revealed.
static func alpha_for(role: String) -> float:
	match role:
		ROLE_TARGET:
			return ALPHA_TARGET
		ROLE_REFUSED:
			return ALPHA_REFUSED
		_:
			return ALPHA_DESTINATION


static func is_known_role(role: String) -> bool:
	return ROLES.has(role)


## The shared material for a role. Unshaded, alpha-blended, visible from both sides (a
## ring tilted onto a ramp is seen from below on one edge) and writing no depth, so a cue
## laid on the floor never punches a hole in the furniture behind it.
static func material_for(role: String) -> StandardMaterial3D:
	if _materials.has(role):
		return _materials[role] as StandardMaterial3D
	var base := color_for(role)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# No shadow flags to set: an unshaded material is not lit and does not receive them.
	material.albedo_color = Color(base.r, base.g, base.b, alpha_for(role))
	material.emission_enabled = true
	material.emission = base
	material.emission_energy_multiplier = EMISSION_ENERGY
	_materials[role] = material
	return material


## A ring drawn as `arcs` dashes lying in the XZ plane, centred on the origin.
##
## Solid tori were tried first and read as machine UI: a perfect glowing hoop is the
## single most generic way to mark a point in a 3D game. Gaps give the eye something to
## argue with, and they also make the ring's slow rotation visible — a solid torus can
## spin forever and nobody can tell.
static func dashed_ring_mesh(
	radius: float,
	arcs: int = RING_ARCS,
	gap_ratio: float = RING_GAP_RATIO
) -> ArrayMesh:
	var safe_radius := maxf(radius, 0.02)
	var inner := maxf(safe_radius - RING_THICKNESS * 0.5, 0.005)
	var outer := safe_radius + RING_THICKNESS * 0.5
	var count := maxi(arcs, 1)
	var span := TAU / float(count)
	var drawn := span * (1.0 - clampf(gap_ratio, 0.0, 0.9))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for arc in count:
		var start := span * float(arc)
		for step in ARC_STEPS:
			var from_angle := start + drawn * float(step) / float(ARC_STEPS)
			var to_angle := start + drawn * float(step + 1) / float(ARC_STEPS)
			_add_annulus_quad(tool, inner, outer, from_angle, to_angle)
	return tool.commit()


## A flat disc in the XZ plane: the quiet centre point of a destination ring.
static func disc_mesh(radius: float, segments: int = 20) -> ArrayMesh:
	var safe_radius := maxf(radius, 0.01)
	var count := maxi(segments, 3)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for index in count:
		var from_angle := TAU * float(index) / float(count)
		var to_angle := TAU * float(index + 1) / float(count)
		tool.add_vertex(Vector3.ZERO)
		tool.add_vertex(Vector3(cos(from_angle), 0.0, sin(from_angle)) * safe_radius)
		tool.add_vertex(Vector3(cos(to_angle), 0.0, sin(to_angle)) * safe_radius)
	return tool.commit()


## A small octahedron: the mark that floats over the object you can use. It reads as a
## diamond from every angle the camera can put it at, and it tumbles, which is the whole
## point — a static dot over a prop looks like a bug in the prop.
static func shard_mesh(size: float) -> ArrayMesh:
	var reach := maxf(size, 0.005)
	var top := Vector3(0.0, reach, 0.0)
	var bottom := Vector3(0.0, -reach, 0.0)
	var equator: Array[Vector3] = [
		Vector3(reach, 0.0, 0.0),
		Vector3(0.0, 0.0, reach),
		Vector3(-reach, 0.0, 0.0),
		Vector3(0.0, 0.0, -reach),
	]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in equator.size():
		var current := equator[index]
		var following := equator[(index + 1) % equator.size()]
		_add_triangle(tool, top, current, following)
		_add_triangle(tool, bottom, following, current)
	return tool.commit()


## A basis whose +Y axis is `normal`: the orientation a cue needs to lie on the surface it
## landed on. A ramp, a kerb or a tilted floor plate would otherwise leave a flat ring
## floating on one side and buried on the other, which reads as a rendering fault.
static func ground_basis(normal: Vector3) -> Basis:
	var up := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var reference := Vector3.RIGHT
	if absf(up.dot(reference)) > 0.9:
		reference = Vector3.FORWARD
	var x_axis := (reference - up * reference.dot(up)).normalized()
	var z_axis := x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)


static func _add_annulus_quad(
	tool: SurfaceTool,
	inner: float,
	outer: float,
	from_angle: float,
	to_angle: float
) -> void:
	var from_direction := Vector3(cos(from_angle), 0.0, sin(from_angle))
	var to_direction := Vector3(cos(to_angle), 0.0, sin(to_angle))
	var inner_from := from_direction * inner
	var inner_to := to_direction * inner
	var outer_from := from_direction * outer
	var outer_to := to_direction * outer
	tool.add_vertex(inner_from)
	tool.add_vertex(outer_from)
	tool.add_vertex(outer_to)
	tool.add_vertex(inner_from)
	tool.add_vertex(outer_to)
	tool.add_vertex(inner_to)


static func _add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Unshaded material or not, a vertex normal is cheaper to supply than to explain.
	var normal := (b - a).cross(c - a).normalized()
	tool.set_normal(normal)
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)

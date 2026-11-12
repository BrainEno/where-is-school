class_name WorldCue
extends RefCounted
## The visual language of the cues the mouse draws in the world.
##
## Two things get drawn: the outline around the object the player would use, and the mark
## where a click lands. They live in one place - the palette, the pen widths and the
## material rules - because two cues that disagree about thickness and colour read as two
## different tools rather than one instrument.
##
## The ground mark is unshaded, untextured and alpha-only, and every mesh is built from
## code. The object outline is drawn in screen space by `OutlineOverlay`
## (`scripts/interaction/outline_overlay.gd`) and takes its colour from here.
##
## The palette, in the language of `docs/ART_BIBLE.md` (restrained: no gloss, no
## gradients, no ornamental frames):
##
## * **bone** - where you clicked. Paper-coloured and quiet; a destination is information,
##   not an event.
## * **amber** - the thing you clicked or the thing you can use. The one warm accent the
##   world already carries, kept to a single hue so the outline and the mark feel related.
## * **rose** - refused. Duller than either, and never a bright red: a refusal, not an
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

## The ground mark: a thin ring with a dot in the middle, the shape a click leaves in
## Disco Elysium and in most isometric games that are read rather than played fast. It is
## small (`MARK_RADIUS`), its pen is thin (`MARK_RING_WIDTH`), and the dot is what keeps it
## readable as a point when the ring is foreshortened at a low camera angle.
const MARK_RADIUS := 0.15
const MARK_RING_WIDTH := 0.022
const MARK_DOT_RADIUS := 0.024
## Segments around the ring. Forty is round at the closest camera distance and still only
## eighty triangles.
const MARK_SEGMENTS := 40
## The echo is the same ring drawn once more, thinner, and sent outwards when the mark
## lands. It is the "the floor heard you" half of the gesture and it plays once.
const ECHO_RING_WIDTH := 0.012

## The colour of the outline drawn around the object the pointer or E would use. A warm,
## nearly white amber: it has to read on the dusk-lit brick of the street and on the pale
## walls of the classroom alike, which a saturated hue does not.
const OUTLINE_COLOR := Color(1.0, 0.87, 0.62, 1.0)
## The dark rim drawn just outside the outline, so it still separates from a pale wall.
const OUTLINE_RIM_COLOR := Color(0.1, 0.075, 0.06, 0.55)

## Opacity per role. The refused cue is dimmer than the other two on purpose. The accepted
## roles are nearly opaque: a two-centimetre pen at 0.6 alpha disappears into a pale floor.
const ALPHA_DESTINATION := 0.86
const ALPHA_TARGET := 0.86
const ALPHA_REFUSED := 0.62
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


## A solid thin ring lying in the XZ plane, centred on the origin. `width` is the pen,
## measured across the ring.
static func ring_mesh(radius: float, width: float, segments: int = MARK_SEGMENTS) -> ArrayMesh:
	var safe_radius := maxf(radius, 0.02)
	var inner := maxf(safe_radius - width * 0.5, 0.002)
	var outer := safe_radius + width * 0.5
	var count := maxi(segments, 8)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for index in count:
		var from_angle := TAU * float(index) / float(count)
		var to_angle := TAU * float(index + 1) / float(count)
		_add_annulus_quad(tool, inner, outer, from_angle, to_angle)
	return tool.commit()


## A flat disc in the XZ plane: the centre point of the ground mark.
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


## A small octahedron. Only drawn by `HoverCue` for an interactable that has no visible mesh
## to outline (content still being built): it reads as a diamond from every camera angle,
## and a tumbling diamond over an empty spot still says "something is here".
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


## The ring of the ground mark, on its own, so `DestinationCue` can animate it apart from
## the dot.
static func destination_ring_mesh() -> ArrayMesh:
	return ring_mesh(MARK_RADIUS, MARK_RING_WIDTH)


## The dot at the centre of the ground mark.
static func destination_dot_mesh() -> ArrayMesh:
	return disc_mesh(MARK_DOT_RADIUS, 16)


## The thinner ring the mark sends outwards once, as it lands.
static func destination_echo_mesh() -> ArrayMesh:
	return ring_mesh(MARK_RADIUS, ECHO_RING_WIDTH)


## The whole mark drawn where a click lands, ring and dot in one mesh.
##
## The previous mark was four chalk strokes. It was small, but it read as a scribble rather
## than as a place, and the owner asked for the language of Disco Elysium instead: a thin
## ring that lands on the floor with a dot at its centre. The ring is about 30 cm across,
## its pen is two centimetres, and nothing in it is filled except the dot - so it is a
## mark on the floor, not a decal covering it. `DestinationCue` draws the two parts
## separately to animate them; this combined mesh is what the tests and the capture run
## measure.
static func destination_mark_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	tool.append_from(destination_ring_mesh(), 0, Transform3D())
	tool.append_from(destination_dot_mesh(), 0, Transform3D())
	return tool.commit()


## How far the shipped mark reaches from its centre, in metres — the half-width of its
## footprint. Read off the built mesh rather than restated as a constant, so a change to the
## strokes above cannot leave the tests measuring the old size.
static func mark_footprint_radius() -> float:
	var box := destination_mark_mesh().get_aabb()
	return maxf(maxf(absf(box.position.x), absf(box.position.z)),
		maxf(box.end.x, box.end.z))


## One stroke of the pen, as a quad lying in the XZ plane, from `from` to `to`.
##
## `taper` narrows the far end by that fraction of the width, which is the difference
## between a line and a mark someone made: a stroke of constant width with a square end reads
## as geometry, a stroke that thins out reads as pressure. Public so a test (or the capture
## tool that compares candidate marks) can compose a shape without copying this file.
static func stroke_mesh(from: Vector2, to: Vector2, width: float, taper: float = 0.0) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	_add_stroke(tool, from, to, width, taper)
	return tool.commit()


## A short arc of the same pen, in the XZ plane, centred on the origin.
static func arc_mesh(
	radius: float,
	start_degrees: float,
	span_degrees: float,
	width: float,
	taper: float = 0.0,
	steps: int = 5
) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	_add_arc(tool, radius, start_degrees, span_degrees, width, taper, steps)
	return tool.commit()


static func _add_stroke(
	tool: SurfaceTool,
	from: Vector2,
	to: Vector2,
	width: float,
	taper: float
) -> void:
	var along := to - from
	if along.length_squared() < 0.000001:
		return
	var direction := along.normalized()
	var across := Vector2(-direction.y, direction.x)
	var half := maxf(width, 0.001) * 0.5
	var far_half := half * (1.0 - clampf(taper, 0.0, 0.9))
	var start_left := from + across * half
	var start_right := from - across * half
	var end_left := to + across * far_half
	var end_right := to - across * far_half
	# Two triangles, wound so the face looks up in a Y-up space.
	tool.add_vertex(Vector3(start_left.x, 0.0, start_left.y))
	tool.add_vertex(Vector3(end_left.x, 0.0, end_left.y))
	tool.add_vertex(Vector3(end_right.x, 0.0, end_right.y))
	tool.add_vertex(Vector3(start_left.x, 0.0, start_left.y))
	tool.add_vertex(Vector3(end_right.x, 0.0, end_right.y))
	tool.add_vertex(Vector3(start_right.x, 0.0, start_right.y))


static func _add_arc(
	tool: SurfaceTool,
	radius: float,
	start_degrees: float,
	span_degrees: float,
	width: float,
	taper: float,
	steps: int
) -> void:
	var count := maxi(steps, 1)
	var safe_radius := maxf(radius, 0.01)
	for step in count:
		var from_degrees := start_degrees + span_degrees * float(step) / float(count)
		var to_degrees := start_degrees + span_degrees * float(step + 1) / float(count)
		var from_angle := deg_to_rad(from_degrees)
		var to_angle := deg_to_rad(to_degrees)
		var from := Vector2(cos(from_angle), sin(from_angle)) * safe_radius
		var to := Vector2(cos(to_angle), sin(to_angle)) * safe_radius
		# Only the last segment carries the taper, so the arc thins towards its end
		# instead of turning into a dotted line.
		var segment_taper := taper if step == count - 1 else 0.0
		_add_stroke(tool, from, to, width, segment_taper)


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

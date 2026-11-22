@tool
extends RefCounted
## Convex cut-paper faces grouped by pigment, with smooth normals only around rolled parts.
## Winding is clockwise (Godot); `outward` lets callers describe a silhouette either way.

var _surfaces: Dictionary[StringName, SurfaceTool] = {}


func face(ink: StringName, points: Array[Vector3], outward: Vector3 = Vector3.ZERO,
		normals: Array[Vector3] = []) -> void:
	var normal := (points[2] - points[0]).cross(points[1] - points[0]).normalized()
	var reverse := normal.dot(outward) < 0.0
	if reverse:
		normal = -normal
	if not _surfaces.has(ink):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[ink] = tool
	var surface: SurfaceTool = _surfaces[ink]
	for i: int in range(1, points.size() - 1):
		for j: int in [0, i + 1 if reverse else i, i if reverse else i + 1]:
			surface.set_normal(normal if normals.is_empty() else normals[j])
			surface.add_vertex(points[j])


func box(center: Vector3, size: Vector3, ink: StringName) -> void:
	var p := center - size * 0.5
	var q := center + size * 0.5
	prism_x(p.x, q.x,
		[Vector2(p.z, p.y), Vector2(q.z, p.y), Vector2(q.z, q.y), Vector2(p.z, q.y)],
		ink, [ink, ink, ink, ink])


## Extrude a convex profile (depth, height) between two x positions. Inks follow its edges.
func prism_x(low: float, high: float, profile: Array[Vector2], end_ink: StringName,
		edges: Array[StringName]) -> void:
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	var center := Vector3.ZERO
	for point: Vector2 in profile:
		left.append(Vector3(low, point.y, point.x))
		right.append(Vector3(high, point.y, point.x))
		center += Vector3(0, point.y, point.x) / profile.size()
	face(end_ink, left, Vector3.LEFT)
	face(end_ink, right, Vector3.RIGHT)
	for i: int in profile.size():
		var j := (i + 1) % profile.size()
		var outside := Vector3(0, (left[i].y + left[j].y) / 2.0,
			(left[i].z + left[j].z) / 2.0) - center
		face(edges[i], [left[i], right[i], right[j], left[j]], outside)


## Flat-cut site pieces. XZ outlines are convex and run counterclockwise in plan coordinates.
func plate(outline: PackedVector2Array, bottom: float, top: float, ink: StringName,
		edge: StringName) -> void:
	var lower: Array[Vector3] = []
	var upper: Array[Vector3] = []
	for point: Vector2 in outline:
		lower.append(Vector3(point.x, bottom, point.y))
		upper.append(Vector3(point.x, top, point.y))
	face(ink, upper, Vector3.UP)
	face(edge, lower, Vector3.DOWN)
	skin(lower, upper, edge)


func skin(low: Array[Vector3], high: Array[Vector3], ink: StringName) -> void:
	for i: int in low.size():
		var j := (i + 1) % low.size()
		face(ink, [low[i], low[j], high[j], high[i]])


## Revolve (radius, height) rings, in order. A path from outside up over the lip and
## down the inside gives a real hollow with inward-facing normals, not a painted disc.
func roll(profile: Array[Vector2], inks: Array[StringName], origin: Vector3 = Vector3.ZERO,
		stretch: float = 1.0, sides: int = 48, cap: bool = true) -> void:
	var rings: Array[Array] = []
	for ring: Vector2 in profile:
		var vertices: Array[Vector3] = []
		for i: int in sides:
			var radial := Vector2.from_angle(TAU * i / sides)
			vertices.append(origin + Vector3(ring.x * radial.x, ring.y, ring.x * radial.y * stretch))
		rings.append(vertices)
	for band: int in range(inks.size()):
		var low: Array[Vector3] = rings[band]
		var high: Array[Vector3] = rings[band + 1]
		var change := profile[band + 1] - profile[band]
		for i: int in sides:
			var j := (i + 1) % sides
			var a := Vector2.from_angle(TAU * i / sides)
			var b := Vector2.from_angle(TAU * j / sides)
			var na := Vector3(a.x * change.y, -change.x, a.y * change.y / stretch).normalized()
			var nb := Vector3(b.x * change.y, -change.x, b.y * change.y / stretch).normalized()
			face(inks[band], [low[i], low[j], high[j], high[i]], Vector3.ZERO, [na, nb, nb, na])
	if cap:
		face(inks.front(), rings.front(), Vector3.DOWN)
		face(inks.back(), rings.back(), Vector3.UP)


## Folded louvre blades: extrude a convex XZ loop vertically with a pigment on each flank.
func prism_y(bottom: float, top: float, outline: PackedVector2Array, edge_inks: Array[StringName]) -> void:
	var lower: Array[Vector3] = []
	var upper: Array[Vector3] = []
	for point: Vector2 in outline:
		lower.append(Vector3(point.x, bottom, point.y))
		upper.append(Vector3(point.x, top, point.y))
	face(edge_inks.front(), lower, Vector3.DOWN)
	face(edge_inks.front(), upper, Vector3.UP)
	for i: int in outline.size():
		var j := (i + 1) % outline.size()
		face(edge_inks[i], [lower[i], lower[j], upper[j], upper[i]])


## Local +Y is the tube axis. A section is (radius, axial origin, share of final miter).
## At each cut section the actual vertices follow y = axial_origin + slope.dot(xz).
## Rings with the same axial origin and share form a planar elliptical annulus.
func mitered_pipe(sections: Array[Vector3], inks: Array[StringName], slope: Vector2) -> void:
	const SIDES := 64
	var last: Array[Vector3] = []
	var last_tangent: Array[Vector3] = []
	for i: int in sections.size():
		var section := sections[i]
		var ring: Array[Vector3] = []
		var tangent: Array[Vector3] = []
		for j: int in SIDES:
			var xy := Vector2.from_angle(TAU * j / SIDES) * section.x
			var t := Vector2(-xy.y, xy.x)
			ring.append(Vector3(xy.x, section.y + slope.dot(xy) * section.z, xy.y))
			tangent.append(Vector3(t.x, slope.dot(t) * section.z, t.y))
		if i > 0:
			for j: int in SIDES:
				var k := (j + 1) % SIDES
				var na := (ring[j] - last[j]).cross(tangent[j] + last_tangent[j]).normalized()
				var nb := (ring[k] - last[k]).cross(tangent[k] + last_tangent[k]).normalized()
				face(inks[i - 1], [last[j], last[k], ring[k], ring[j]], Vector3.ZERO, [na, nb, nb, na])
		else:
			face(inks.front(), ring, Vector3.DOWN)
		last = ring
		last_tangent = tangent
	# The only cap inside the bore is buried at the socket, more than four units away.
	face(inks.back(), last, Vector3.UP)


func commit(parent: Node3D, name: String, palette: Dictionary[StringName, Material]) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for ink: StringName in _surfaces:
		var surface: SurfaceTool = _surfaces[ink]
		surface.set_material(palette[ink])
		surface.index()
		surface.commit(mesh)
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	parent.add_child(instance, false, Node.INTERNAL_MODE_BACK)
	return instance

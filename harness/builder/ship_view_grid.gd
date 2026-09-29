class_name ShipViewGrid
extends RefCounted
## THE FLOOR GRID AND THE BEACON - the 3D view's ground plane, as pure geometry.
##
## PURE AND STATIC: colours and sizes in, one [ImmediateMesh] out. It touches no node, reads no
## view state and reaches back into `ship_view3d.gd` for nothing, which is what makes it a real
## extraction rather than a file split (`.gdlintrc`: "A good extraction is a self-contained,
## statically testable unit with no reference back to the file it came from"). It can be built and
## asserted on in a test with four colours and no scene at all.
##
## It came out of `ShipView3D` when that file passed the two-thousand-line alarm while FLY was
## landing (ADR 0049). The alarm was right: the grid is scenery, and scenery is not what a view
## class is about.


## Lines every [param step] metres out to [param extent], the two world axes picked out in
## [param axis], and the BEACON at the origin.
##
## THE BEACON (ADR 0033) is the ship's build centre, drawn as a three-armed dot - "it can be
## entirely internal and viewable as a dot" (2026-09-21). Every class is laid out around it and the
## root module is anchored to it, so this is where a ship grows FROM rather than wherever its first
## module happens to sit. It reads THROUGH the hull, like every other overlay line in this view: a
## reference the ship is built around is no use only when nothing stands on it.
static func build(
	grid_mat: StandardMaterial3D,
	axis_mat: StandardMaterial3D,
	beacon_mat: StandardMaterial3D,
	extent: float,
	step: float,
	beacon_arm: float
) -> ImmediateMesh:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_mat)
	var n: int = int(extent / maxf(step, 0.001))
	for i: int in range(-n, n + 1):
		var t: float = float(i) * step
		# The two centre lines are the AXES and are drawn in their own colour below; drawing them
		# here as well would z-fight one against the other.
		if absf(t) < 0.001:
			continue
		mesh.surface_add_vertex(Vector3(t, 0.0, -extent))
		mesh.surface_add_vertex(Vector3(t, 0.0, extent))
		mesh.surface_add_vertex(Vector3(-extent, 0.0, t))
		mesh.surface_add_vertex(Vector3(extent, 0.0, t))
	mesh.surface_end()

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, axis_mat)
	mesh.surface_add_vertex(Vector3(-extent, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(extent, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(0.0, 0.0, -extent))
	mesh.surface_add_vertex(Vector3(0.0, 0.0, extent))
	mesh.surface_end()

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, beacon_mat)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		mesh.surface_add_vertex(-axis * beacon_arm)
		mesh.surface_add_vertex(axis * beacon_arm)
	mesh.surface_end()
	return mesh

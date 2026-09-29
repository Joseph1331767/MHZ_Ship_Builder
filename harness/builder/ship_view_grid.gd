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


## THE MAX BOUNDING BOX as eight CORNER BRACKETS, not a full cage.
##
## The shipped budget is 250 x 120 x 250 m against a 5 m starting hull: twelve full edges at that
## scale is a box drawn around the entire grid floor and reads as scenery. Eight short brackets read
## as LIMITS, which is the CAD convention and is what the thing actually is.
##
## [param half] is half the budget per axis; [param fraction] how far along each edge a bracket
## reaches. Pure geometry - the colour is the caller's, because the colour IS the readout: line
## while the ship fits, warning the moment it does not.
static func brackets(mat: StandardMaterial3D, half: Vector3, fraction: float) -> ImmediateMesh:
	var arm: Vector3 = Vector3(
		minf(half.x * fraction, half.x),
		minf(half.y * fraction, half.y),
		minf(half.z * fraction, half.z)
	)
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var corner: Vector3 = Vector3(half.x * sx, half.y * sy, half.z * sz)
				mesh.surface_add_vertex(corner)
				mesh.surface_add_vertex(corner - Vector3(arm.x * sx, 0.0, 0.0))
				mesh.surface_add_vertex(corner)
				mesh.surface_add_vertex(corner - Vector3(0.0, arm.y * sy, 0.0))
				mesh.surface_add_vertex(corner)
				mesh.surface_add_vertex(corner - Vector3(0.0, 0.0, arm.z * sz))
	mesh.surface_end()
	return mesh


## Does [param box] reach outside [param half] on any axis? Measured from the SCENE bounds rather
## than by re-running the metrics pass, which costs a full attach solve and this runs every sync.
static func outside(box: AABB, half: Vector3) -> bool:
	var reach: Vector3 = Vector3(
		maxf(absf(box.position.x), absf(box.end.x)),
		maxf(absf(box.position.y), absf(box.end.y)),
		maxf(absf(box.position.z), absf(box.end.z))
	)
	return reach.x > half.x or reach.y > half.y or reach.z > half.z

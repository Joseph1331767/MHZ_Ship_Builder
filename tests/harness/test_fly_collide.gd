extends GdUnitTestSuite
## ShipFlyCollide - solid walls actually stop the camera (ADR 0049).
##
## A PHYSICS feature deserves a physics test. One 4 m box, one motion straight through it, and the
## assertion that the step lands ON the surface rather than beyond it - because "I turned collision
## on and flew through the hull anyway" is exactly the failure this cannot be allowed to regress to.


func _box_at_origin(size: float) -> Node3D:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(size, size, size)
	mi.mesh = bm
	holder.add_child(mi)
	return holder


func _collider() -> ShipFlyCollide:
	var c: ShipFlyCollide = auto_free(ShipFlyCollide.new())
	add_child(c)
	return c


## THE WHOLE POINT: a step that would pass through the hull stops at its surface instead.
##
## The box half-extent is 2 m and the body is a sphere of [constant ShipFlyCollide.BODY_RADIUS], so
## a correct stop is a shade over 2.35 m out. Measured 2.4375 - the extra is the physics server's
## own contact margin, which is why this asserts a band rather than a number.
func test_a_built_collider_stops_a_step_at_the_surface() -> void:
	var holder: Node3D = _box_at_origin(4.0)
	var collide: ShipFlyCollide = _collider()
	collide.build([holder] as Array[Node3D])
	assert_bool(collide.is_built()).is_true()
	# The static bodies have to reach the physics server before anything can hit them.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var from: Vector3 = Vector3(0.0, 0.0, 12.0)
	var through: Vector3 = Vector3(0.0, 0.0, -12.0)
	var landed: Vector3 = collide.resolve(from, through)
	(
		assert_float(landed.z)
		. append_failure_message("the step went through the hull instead of stopping on it")
		. is_between(2.0, 3.2)
	)


## GHOST IS THE RESTING STATE and has to be a real pass-through, not a weaker collision.
func test_an_empty_collider_passes_everything_through() -> void:
	var holder: Node3D = _box_at_origin(4.0)
	var collide: ShipFlyCollide = _collider()
	collide.build([holder] as Array[Node3D])
	await get_tree().physics_frame
	collide.clear()
	assert_bool(collide.is_built()).is_false()
	var through: Vector3 = Vector3(0.0, 0.0, -12.0)
	assert_vector(collide.resolve(Vector3(0.0, 0.0, 12.0), through)).is_equal(through)


## A WIREFRAME IS NOT A WALL. Line meshes carry no faces, so they contribute no collider - without
## this the edge overlay would be a second, slightly larger, invisible hull.
func test_a_line_mesh_contributes_no_collider() -> void:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var am: ArrayMesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3(-2.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)]
	)
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mi.mesh = am
	holder.add_child(mi)

	var collide: ShipFlyCollide = _collider()
	collide.build([holder] as Array[Node3D])
	await get_tree().physics_frame
	await get_tree().physics_frame
	var through: Vector3 = Vector3(0.0, 0.0, -12.0)
	assert_vector(collide.resolve(Vector3(0.0, 0.0, 12.0), through)).is_equal(through)


## THE VELOCITY A BLOCKED STEP KEEPS is the component along the WALL.
##
## THIS TEST USED TO BE WRITTEN ALONG THE ONE AXIS WHERE THE BUG WAS INVISIBLE. It fed a pure -Z
## block against an axis-aligned box face, where the direction of blocked travel and the surface
## normal coincide - so the old implementation, which derived its "normal" from (wanted - landed),
## passed while being wrong for every oblique hit on a curved hull, which is the normal case here.
## It asks for an OBLIQUE hit now, and takes the normal from the collision itself.
func test_slide_velocity_keeps_only_what_runs_along_the_wall() -> void:
	var collide: ShipFlyCollide = _collider()
	# A wall facing +Z, approached at 45 degrees.
	var normal: Vector3 = Vector3(0.0, 0.0, 1.0)
	var kept: Vector3 = collide.slide_velocity(Vector3(4.0, 0.0, -4.0), normal)
	assert_float(kept.z).is_equal_approx(0.0, 1e-4)
	# The along-wall component survives untouched - that is what sliding means.
	assert_float(kept.x).is_equal_approx(4.0, 1e-4)

	# And on a SLANTED wall the answer is not simply "drop z": a 45-degree normal takes a
	# straight-ahead velocity and turns it along the surface.
	var slanted: Vector3 = Vector3(1.0, 0.0, 1.0).normalized()
	var turned: Vector3 = collide.slide_velocity(Vector3(0.0, 0.0, -5.0), slanted)
	assert_float(turned.length()).is_greater(0.5)
	assert_float(turned.dot(slanted)).is_equal_approx(0.0, 1e-4)

	# A zero normal means nothing was hit, so nothing is taken away.
	assert_vector(collide.slide_velocity(Vector3(1.0, 2.0, 3.0), Vector3.ZERO)).is_equal(
		Vector3(1.0, 2.0, 3.0)
	)


## A BLOCKED STEP SLIDES rather than stopping dead - the behaviour the docstring always claimed and
## the first implementation did not have.
func test_a_grazing_step_carries_on_along_the_wall() -> void:
	var holder: Node3D = _box_at_origin(4.0)
	var collide: ShipFlyCollide = _collider()
	collide.build([holder] as Array[Node3D])
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Aimed diagonally INTO the box's +Z face: blocked in z, free in x.
	var from: Vector3 = Vector3(-3.0, 0.0, 6.0)
	var landed: Vector3 = collide.resolve(from, from + Vector3(6.0, 0.0, -6.0))
	assert_float(landed.z).is_greater(1.9)
	(
		assert_float(landed.x)
		. append_failure_message("the step stopped dead instead of sliding along the face")
		. is_greater(from.x + 1.0)
	)
	assert_vector(collide.last_normal()).is_not_equal(Vector3.ZERO)


## THE BUDGET IS REPORTED, NOT SILENT. A ship too big to make fully solid has to say so, or the
## player finds out by flying through a wall and concludes the feature is broken.
func test_coverage_reports_what_was_built() -> void:
	var holder: Node3D = _box_at_origin(4.0)
	var collide: ShipFlyCollide = _collider()
	collide.build([holder] as Array[Node3D])
	await get_tree().physics_frame
	var cover: Dictionary = collide.coverage()
	assert_int(int(cover["bodies"])).is_equal(1)
	assert_int(int(cover["triangles"])).is_greater(0)
	assert_int(int(cover["skipped"])).is_equal(0)
	# And clearing resets the tally, so a later build cannot inherit a stale one.
	collide.clear()
	assert_int(int(collide.coverage()["bodies"])).is_equal(0)


## COLLIDERS ONLY EXIST WHILE FLYING. `_solid` is a remembered preference that survives landing, so
## a bake finishing in the orbit view used to rebuild a full set of trimesh shapes nobody could
## touch - and over BOTH the preview parts and the baked pieces, because both were visible.
func test_rebuild_does_nothing_when_not_flying() -> void:
	var collide: ShipFlyCollide = _collider()
	# A mode with no fly rig is never flying, which is the condition under test.
	var mode: ShipFlyMode = ShipFlyMode.new(
		null, null, null, null, null, null, null, null, null, collide
	)
	mode.set_solid(true)
	mode.rebuild_solids()
	assert_bool(collide.is_built()).is_false()
	assert_int(int(collide.coverage()["bodies"])).is_equal(0)

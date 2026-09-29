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


## The velocity a blocked step keeps is the part ALONG the wall. Without this the camera stores up
## speed while pressed against a hull and fires off the moment it clears the edge.
func test_slide_velocity_drops_the_component_into_the_wall() -> void:
	var collide: ShipFlyCollide = _collider()
	var holder: Node3D = _box_at_origin(4.0)
	collide.build([holder] as Array[Node3D])
	await get_tree().physics_frame
	# Blocked straight along -Z, moving down and forward.
	var wanted: Vector3 = Vector3(0.0, -5.0, -5.0)
	var landed: Vector3 = Vector3(0.0, -5.0, 0.0)
	var kept: Vector3 = collide.slide_velocity(Vector3(0.0, -3.0, -4.0), landed, wanted)
	assert_float(kept.z).is_equal_approx(0.0, 1e-4)
	# And the sideways part is untouched, which is what "slide" means.
	assert_float(kept.y).is_equal_approx(-3.0, 1e-4)

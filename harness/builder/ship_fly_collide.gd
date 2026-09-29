class_name ShipFlyCollide
extends Node3D
## SOLID WALLS WHILE FLYING - the ship stops being a hologram you drift through.
##
## The author, 2026-09-28: "i need a btn on screen when in fly mode that turns on collision both
## inner and outer."
##
## BOTH INNER AND OUTER IS WHY THESE ARE TRIMESH SHAPES. The picking bodies this builder has are
## CONVEX hulls (`create_convex_shape`) - a convex hull of a hollow room is a solid block, so with
## those you could not enter a room at all, and once inside you could leave through a wall.
## A [ConcavePolygonShape3D] built from the drawn triangles is the actual surface, so the outer hull
## stops you from outside and the cavity wall stops you from inside, which is the ask exactly.
##
## OFF BY DEFAULT, and that is deliberate: the reason to fly is usually to LOOK, and a camera that
## catches on geometry while you are trying to inspect something is infuriating. It is a button and
## a key, not a mode you are put into.
##
## WHY A CharacterBody3D AND NOT A RAYCAST. `docs/FOLLOWUPS.md` records that concave pick bodies get
## no raycast hits in this SubViewport, which is why picking uses convex hulls. Rather than
## re-fight that, the motion is resolved by MOVING A BODY: `move_and_collide` is the physics server
## sweeping a sphere, not a ray query, and it slides along a surface instead of stopping dead at
## it - which is also the nicer feel. The sphere is the player's personal space.
##
## ITS OWN COLLISION LAYER. Picking owns layer 1 and must not start returning these; this is layer 2
## and collides with nothing else, so nothing in the document can be disturbed by turning it on.

## The layer these bodies live on - NOT [constant ShipSceneBuilder.PICK_LAYER].
const FLY_LAYER: int = 2

## How much room the camera keeps around itself, in metres. Roughly a person's shoulder width: big
## enough that the near clip plane never ends up inside a wall (which renders as the hull
## vanishing), small enough to get through a hatch.
const BODY_RADIUS: float = 0.35

## Ship meshes bigger than this many triangles are skipped rather than turned into a trimesh shape.
const MAX_TRIANGLES: int = 120000

## AND A BUDGET ACROSS THE WHOLE SHIP, which the per-mesh cap alone does not give. A diced hull is
## hundreds of pieces; capping each one at 120k while building an unbounded NUMBER of them is not a
## cap at all. Every [ConcavePolygonShape3D] is built synchronously on the frame the button was
## pressed and lives in the physics server until collision is switched off, so the total is what
## actually costs - and an out-of-memory in the physics server is a native crash, not a GDScript
## error you would see in the log.
##
## 600k triangles is about 22 MB of vertices alone (36 bytes a triangle), and Godot builds a BVH per
## shape on top of that - call it 50-60 MB all in. A lot of ship, and still not dangerous.
const MAX_TOTAL_TRIANGLES: int = 600000

## How many meshes to build shapes for at most, whatever their size. A guard against a pathological
## piece count rather than a pathological triangle count.
const MAX_BODIES: int = 512

var _body: CharacterBody3D = null
var _shapes: Node3D = null
var _built: bool = false
var _triangles: int = 0
var _bodies: int = 0
var _skipped: int = 0
var _normal: Vector3 = Vector3.ZERO


func _ready() -> void:
	_shapes = Node3D.new()
	_shapes.name = "FlyColliders"
	add_child(_shapes)
	_body = CharacterBody3D.new()
	_body.name = "FlyBody"
	# It collides with the colliders below and with nothing else, and nothing else can see it.
	_body.collision_layer = 0
	_body.collision_mask = FLY_LAYER
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = BODY_RADIUS
	shape.shape = sphere
	_body.add_child(shape)
	add_child(_body)


func is_built() -> bool:
	return _built


## Build a collider for every drawn mesh under [param roots]. Called when collision is switched on,
## and again after a bake, because the pieces it was built from are gone by then.
func build(roots: Array[Node3D]) -> void:
	clear()
	for root: Node3D in roots:
		if root == null or not root.visible:
			continue
		for node: Node in _meshes_under(root):
			_add_collider(node as MeshInstance3D)
	_built = true


## What the last [method build] covered, as `{bodies, triangles, skipped}` - so a caller can TELL
## THE PLAYER when the ship was too big to make fully solid, rather than leaving them to find out by
## flying through a wall. No silent caps.
func coverage() -> Dictionary:
	return {"bodies": _bodies, "triangles": _triangles, "skipped": _skipped}


func clear() -> void:
	_built = false
	_triangles = 0
	_bodies = 0
	_skipped = 0
	if _shapes == null:
		return
	for child: Node in _shapes.get_children():
		# REMOVED FROM THE TREE FIRST, not just queued. `queue_free` is deferred to the end of the
		# frame, and `build` re-adds immediately after calling this - so without the remove, a
		# rebuild leaves the old bodies live in the physics server for a frame alongside the new
		# ones, and a toggle-happy player stacks them up.
		_shapes.remove_child(child)
		child.queue_free()


## Resolve a step. Returns where the camera actually ends up: [param to] when nothing is in the way,
## or the point it slid to. Returns [param to] unchanged when nothing has been built, so the caller
## needs no branch of its own.
##
## IT REALLY SLIDES. The first version called `move_and_collide` once and returned the stop point,
## which stops the camera DEAD on contact - the opposite of what its own docstring claimed. The
## remainder of the step is now projected onto the surface and attempted again, so grazing a hull
## carries you along it.
func resolve(from: Vector3, to: Vector3) -> Vector3:
	_normal = Vector3.ZERO
	if not _built or _body == null or not _body.is_inside_tree():
		return to
	var step: Vector3 = to - from
	if step.length() < 1e-6:
		return to
	_body.global_position = from
	var hit: KinematicCollision3D = _body.move_and_collide(step)
	if hit == null:
		return to
	# THE REAL SURFACE NORMAL, from the collision itself. Deriving one from (wanted - landed) gives
	# the direction of BLOCKED TRAVEL, which only coincides with the surface normal on a head-on
	# hit - the single case an axis-aligned test would cover, and not the case a curved hull is.
	_normal = hit.get_normal()
	var left: Vector3 = hit.get_remainder()
	var along: Vector3 = left.slide(_normal)
	if along.length() > 1e-6:
		_body.move_and_collide(along)
	return _body.global_position


## The surface normal of the last blocked step, or zero when nothing was hit.
func last_normal() -> Vector3:
	return _normal


## The velocity a blocked step should keep: the component along the WALL, with whatever pointed into
## it removed. Without this the camera stores up speed while pressed against a hull and fires off
## the moment it clears the edge.
func slide_velocity(velocity: Vector3, normal: Vector3) -> Vector3:
	if normal.length_squared() < 1e-12:
		return velocity
	return velocity.slide(normal.normalized())


func _add_collider(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
		return
	if _bodies >= MAX_BODIES or _triangles >= MAX_TOTAL_TRIANGLES:
		_skipped += 1
		return
	# THE SIZE IS CHECKED BEFORE THE DE-INDEX. `get_faces()` materialises the whole surface into a
	# fresh PackedVector3Array, so testing the cap on its result paid exactly the allocation the cap
	# exists to avoid. An ArrayMesh can be asked its length without building anything.
	if _estimated_triangles(mi.mesh) > MAX_TRIANGLES:
		_skipped += 1
		return
	var faces: PackedVector3Array = mi.mesh.get_faces()
	# Empty covers every non-triangle surface, a wireframe included: a line mesh has no faces, so it
	# contributes no wall. Measured on the real wire mesh, indexed and with normals.
	if faces.is_empty():
		return
	_triangles += int(faces.size() / 3)
	_bodies += 1
	# BAKED INTO WORLD SPACE, with the body left at identity.
	#
	# A MIRRORED PART'S COLLIDER WAS INERT. Handing the body `mi.global_transform` works for a plain
	# part, but a mirror twin's basis has a NEGATIVE DETERMINANT (ShipAttach.resolve_all emits one;
	# ShipMirror: "a reflection has determinant -1") and the physics server will not collide through
	# a mirrored basis at all. Measured: identity stops at z=2.500, a (1,2,3) scale stops at 6.406,
	# and a (-1,2,3) mirror PASSES STRAIGHT THROUGH from every direction. So on any symmetric ship,
	# half of it was not solid and nothing said so.
	#
	# Transforming the vertices instead costs one pass over the faces and is immune to mirroring,
	# shear and non-uniform scale together.
	var xf: Transform3D = mi.global_transform
	var world: PackedVector3Array = PackedVector3Array()
	world.resize(faces.size())
	for i: int in faces.size():
		world[i] = xf * faces[i]
	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	# BOTH SIDES, which is the whole of "collision both inner and outer". A concave shape collides
	# on its front faces only by default, so the inside of a room would have been a one-way wall you
	# could leave through - and a MIRRORED part, whose winding is reversed by its own reflection,
	# would have been solid from the wrong side entirely.
	shape.backface_collision = true
	shape.set_faces(world)
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = FLY_LAYER
	body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	_shapes.add_child(body)


## Triangles in [param mesh] WITHOUT de-indexing it. Exact for an ArrayMesh, which every baked piece
## and every preview part is; anything else answers 0 and is let through to the real check.
static func _estimated_triangles(mesh: Mesh) -> int:
	var am: ArrayMesh = mesh as ArrayMesh
	if am == null:
		return 0
	var total: int = 0
	for i: int in am.get_surface_count():
		var indexed: int = am.surface_get_array_index_len(i)
		var verts: int = am.surface_get_array_len(i)
		total += int((indexed if indexed > 0 else verts) / 3)
	return total


## Every drawn mesh under [param root]. A wireframe is not a wall, and is dropped by
## [method _add_collider] because a line mesh has no faces.
func _meshes_under(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var mi: MeshInstance3D = root as MeshInstance3D
	if mi != null and mi.mesh != null and mi.is_visible_in_tree():
		# No primitive-type check: `surface_get_primitive_type` lives on ArrayMesh, not on Mesh, so
		# asking a BoxMesh for it throws. `get_faces()` in _add_collider already answers the real
		# question - it returns nothing for a line mesh, so a wireframe is skipped for free.
		out.append(mi)
	for child: Node in root.get_children():
		out.append_array(_meshes_under(child))
	return out

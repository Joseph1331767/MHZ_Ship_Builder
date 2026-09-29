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
## A diced hull can run to hundreds of thousands of triangles and building a concave shape for every
## one of them would stall the frame that the button was pressed on.
const MAX_TRIANGLES: int = 120000

var _body: CharacterBody3D = null
var _shapes: Node3D = null
var _built: bool = false


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


func clear() -> void:
	_built = false
	if _shapes == null:
		return
	for child: Node in _shapes.get_children():
		child.queue_free()


## Resolve a step. Returns where the camera actually ends up: [param to] when nothing is in the way,
## or the point it slid to. Returns [param to] unchanged when nothing has been built, so the caller
## needs no branch of its own.
func resolve(from: Vector3, to: Vector3) -> Vector3:
	if not _built or _body == null or not _body.is_inside_tree():
		return to
	var step: Vector3 = to - from
	if step.length() < 1e-6:
		return to
	_body.global_position = from
	# SLIDE, not stop: a camera that halts dead on contact reads as a bug, and sliding along a hull
	# is how every flying camera in every game behaves.
	var hit: KinematicCollision3D = _body.move_and_collide(step)
	if hit == null:
		return to
	return _body.global_position


## The velocity a step should keep after a collision - the component along the wall, with the part
## going INTO it removed. Without this the camera keeps its full speed while pressed against a hull
## and shoots off the moment it clears the edge.
func slide_velocity(velocity: Vector3, landed: Vector3, wanted: Vector3) -> Vector3:
	if not _built:
		return velocity
	var blocked: Vector3 = wanted - landed
	if blocked.length_squared() < 1e-10:
		return velocity
	var normal: Vector3 = blocked.normalized()
	# Project onto the wall: drop the whole component pointing into it, keep the rest.
	return velocity - normal * velocity.dot(normal)


func _add_collider(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
		return
	var faces: PackedVector3Array = mi.mesh.get_faces()
	if faces.is_empty() or faces.size() > MAX_TRIANGLES * 3:
		return
	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = FLY_LAYER
	body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	_shapes.add_child(body)
	body.global_transform = mi.global_transform


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

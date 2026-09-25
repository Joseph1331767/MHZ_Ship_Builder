class_name ShipMirror
extends RefCounted

## Mirroring — SPEC section 6, API_CONTRACT section 19. Static only, no state.
##
## A mirrored part is a *derivative*: one record with `mirror_source` set, whose world transform is
## generated at rebuild by reflecting its source's world transform across a plane through the ship
## root (x = 0, y = 0 or z = 0). Symmetric ships are half-size on disk and cannot drift, because a
## derivative has no independent geometry of its own until `break_link` materialises it.
##
## A reflection has determinant -1, so mirrored geometry has REVERSED WINDING. The renderer must
## draw derivative parts with front-face culling (or a determinant-aware material) or they turn
## inside out. This is a property of the maths, not a bug to be fixed here.
##
## Mirroring a mirror is illegal and is refused (API_CONTRACT section 14, `mirror_of_mirror`).

const PLANE_X: String = "x"
const PLANE_Y: String = "y"
const PLANE_Z: String = "z"

## Appended to a derivative's display name so the part tree reads honestly.
const MIRROR_SUFFIX: String = " (mirror)"


## The normal of the ship-root plane named by `plane`; Vector3.ZERO for anything unrecognised.
static func plane_normal(plane: String) -> Vector3:
	match plane:
		PLANE_X:
			return Vector3.RIGHT
		PLANE_Y:
			return Vector3.UP
		PLANE_Z:
			return Vector3.BACK
	return Vector3.ZERO


static func is_valid_plane(plane: String) -> bool:
	return plane_normal(plane) != Vector3.ZERO


## The reflection as a Basis: the plane's axis negated, everything else left alone.
static func reflection_basis(plane: String) -> Basis:
	var n: Vector3 = plane_normal(plane)
	if n == Vector3.ZERO:
		return Basis.IDENTITY
	var s: Vector3 = Vector3.ONE - 2.0 * n * n
	return Basis(Vector3(s.x, 0.0, 0.0), Vector3(0.0, s.y, 0.0), Vector3(0.0, 0.0, s.z))


## Reflect a SHIP-space transform across the named ship-root plane. Both the basis and the origin
## are reflected, so the mirrored part sits where its source's mirror image sits and faces the way
## its mirror image faces. An unrecognised plane returns the transform untouched.
static func reflect(t: Transform3D, plane: String) -> Transform3D:
	var r: Basis = reflection_basis(plane)
	return Transform3D(r * t.basis, r * t.origin)


## [param t] reflected across EVERY plane named in [param axes] - "x", "xy", "xyz" - in order.
##
## Reflections compose: mirroring across x and then y is the same rigid motion as the single
## reflection a document with both planes wants for its "xy" twin (ADR 0043). An empty string
## returns [param t] untouched, so a caller need not test for it.
static func reflect_axes(t: Transform3D, axes: String) -> Transform3D:
	var out: Transform3D = t
	for axis: String in ShipSymmetry.axes_of(axes):
		out = reflect(out, axis)
	return out


## The attach numbers a real part would need to land where the reflection puts a derivative.
## Returns `{"yaw": float, "pitch": float, "rot": Vector3}`.
##
## Any reflection reverses the sense of rotation about the mount axis, so `rot.z` - the spin about
## the surface normal - always negates. That is the whole of the old behaviour and it is preserved
## exactly.
##
## [b]The TILT components (rot.x, rot.y) pass through UNCHANGED, and that is not exact.[/b] A
## correct reflection of a tilt has to account for the mount frame being rebuilt right-handed from
## the already-reflected normal, so the axis map and the sign flip partially cancel in a way that
## depends on the plane. It is not derived here because nothing a player touches goes through this
## function: [method mirror_subtree] is the RETIRED opt-in mirror model (ADR-era; superseded by
## [ShipSymmetry], where symmetry is on by default), and the LIVE twin path does not use attach
## angles at all - [ShipAttach] resolves the source part and calls [method reflect] on the finished
## [Transform3D], which is exact for any orientation. Deriving the angle map here would add a
## second, subtly different answer to a path that is already correct elsewhere.
##
## RETIRED(ADR 0004, 2026-08-31): the (yaw, pitch, roll) Vector3 return -> this Dictionary, because
## `roll` is now the three-axis `ShipPart.rot`.
static func mirror_attach_angles(
	yaw_deg: float, pitch_deg: float, rot: Vector3, plane: String
) -> Dictionary:
	var yaw: float = yaw_deg
	var pitch: float = pitch_deg
	match plane:
		PLANE_X:
			yaw = -yaw_deg
		PLANE_Y:
			pitch = -pitch_deg
		PLANE_Z:
			yaw = 180.0 - yaw_deg
	return {
		"yaw": _wrap_deg(yaw),
		"pitch": clampf(pitch, -90.0, 90.0),
		"rot": Vector3(rot.x, rot.y, _wrap_deg(-rot.z)),
	}


## Add derivative records for `part_id` and everything under it. Returns the new derivative ids in
## creation order (parents before children), or an empty array if the operation was refused.
##
## Refused when: the part does not exist, the plane is not x/y/z, any part in the subtree is itself
## a derivative (a mirror of a mirror), or this subtree is already mirrored across this plane.
static func mirror_subtree(doc: ShipDoc, part_id: String, plane: String) -> PackedStringArray:
	var made: PackedStringArray = PackedStringArray()
	if doc == null or not doc.parts.has(part_id) or not is_valid_plane(plane):
		return made
	var ids: PackedStringArray = subtree_ids(doc, part_id)
	for id: String in ids:
		var member: ShipPart = doc.parts[id]
		if member.is_mirror():
			push_warning("ShipMirror: '%s' is a mirror; a mirror of a mirror is illegal." % id)
			return made
	if _already_mirrored(doc, part_id, plane):
		return made
	var id_map: Dictionary = {}
	for id: String in ids:
		var source: ShipPart = doc.parts[id]
		var copy: ShipPart = source.duplicate_part()
		copy.mirror_source = id
		copy.mirror_plane = plane
		copy.locked = false
		if copy.display_name != "":
			copy.display_name = source.display_name + MIRROR_SUFFIX
		var angles: Dictionary = mirror_attach_angles(source.yaw, source.pitch, source.rot, plane)
		copy.yaw = angles["yaw"]
		copy.pitch = angles["pitch"]
		copy.rot = angles["rot"]
		var mapped_parent: String = id_map.get(source.parent, source.parent)
		copy.parent = mapped_parent
		copy.id = doc.new_part_id()
		var added: String = doc.add_part(copy)
		if added == "":
			added = copy.id
		id_map[id] = added
		made.append(added)
	return made


## Materialise a derivative subtree into real, independently editable parts with fresh ids, and
## drop the derivative records. Returns the new part ids in creation order.
##
## The attach numbers are re-derived from the live source at break time, so a derivative that was
## never rebuilt still materialises in the right place. Caveat worth knowing: a reflected frame is
## left-handed and the attach model only produces right-handed mount frames, so for a shape that is
## not symmetric about its own local X the materialised part is the nearest legal placement rather
## than a bit-exact copy of the reflection.
static func break_link(doc: ShipDoc, part_id: String) -> PackedStringArray:
	var made: PackedStringArray = PackedStringArray()
	if doc == null or not doc.parts.has(part_id):
		return made
	var head: ShipPart = doc.parts[part_id]
	if not head.is_mirror():
		push_warning("ShipMirror.break_link: '%s' is not a mirror derivative." % part_id)
		return made
	var ids: PackedStringArray = subtree_ids(doc, part_id)
	var id_map: Dictionary = {}
	for old_id: String in ids:
		var source: ShipPart = doc.parts[old_id]
		var copy: ShipPart = source.duplicate_part()
		_materialise(doc, source, copy)
		var mapped_parent: String = id_map.get(source.parent, source.parent)
		copy.parent = mapped_parent
		copy.id = doc.new_part_id()
		var added: String = doc.add_part(copy)
		if added == "":
			added = copy.id
		id_map[old_id] = added
		made.append(added)
	doc.remove_part(part_id)
	return made


## Every derivative part id in the doc, sorted, so reports and rebuilds are deterministic.
static func derivative_ids(doc: ShipDoc) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null:
		return out
	var ids: Array = doc.parts.keys()
	ids.sort()
	for id: String in ids:
		var part: ShipPart = doc.parts[id]
		if part.is_mirror():
			out.append(id)
	return out


## `part_id` followed by its descendants, depth first, parents before children.
static func subtree_ids(doc: ShipDoc, part_id: String) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray([part_id])
	ids.append_array(doc.descendants_of(part_id))
	return ids


# --- private -------------------------------------------------------------------------------


# Turn a copied derivative record into a standalone one, re-reading the live source.
static func _materialise(doc: ShipDoc, source: ShipPart, copy: ShipPart) -> void:
	copy.mirror_source = ""
	copy.mirror_plane = ""
	if copy.display_name.ends_with(MIRROR_SUFFIX):
		copy.display_name = copy.display_name.trim_suffix(MIRROR_SUFFIX)
	if not source.is_mirror() or not doc.parts.has(source.mirror_source):
		return
	var origin: ShipPart = doc.parts[source.mirror_source]
	copy.kind = origin.kind
	copy.family = origin.family
	copy.manufacturer = origin.manufacturer
	copy.params = origin.params.duplicate(true)
	copy.scale = origin.scale
	copy.blend = origin.blend
	copy.offset = origin.offset
	var angles: Dictionary = mirror_attach_angles(
		origin.yaw, origin.pitch, origin.rot, source.mirror_plane
	)
	copy.yaw = angles["yaw"]
	copy.pitch = angles["pitch"]
	copy.rot = angles["rot"]


static func _already_mirrored(doc: ShipDoc, part_id: String, plane: String) -> bool:
	var ids: Array = doc.parts.keys()
	ids.sort()
	for id: String in ids:
		var part: ShipPart = doc.parts[id]
		if part.mirror_source == part_id and part.mirror_plane == plane:
			return true
	return false


static func _wrap_deg(deg: float) -> float:
	return fposmod(deg + 180.0, 360.0) - 180.0

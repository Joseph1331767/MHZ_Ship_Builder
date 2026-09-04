class_name ShipPart
extends RefCounted

## One part record — SPEC section 5.1, API_CONTRACT section 9.
##
## A pure record: it holds what the player set and nothing derived. No resolved shape,
## no transform, no cached SDF. [ShapeGen] turns (family, manufacturer, params, scale)
## into a [ResolvedShape]; [ShipAttach] turns (yaw, pitch, rot, offset) into a
## transform. Both are recomputed, never stored, so a part can never disagree with itself.
##
## [member id] is immutable once created — Phase 2 regions, damage state and routing all
## reference it — and lives as the key in [member ShipDoc.parts], so [method to_dict]
## does not repeat it.

const KIND_PRIMITIVE: String = "primitive"
const KIND_COMPONENT_INSTANCE: String = "component_instance"

const PLANE_NONE: String = ""
const PLANE_X: String = "x"
const PLANE_Y: String = "y"
const PLANE_Z: String = "z"

const VALID_KINDS: Array = [KIND_PRIMITIVE, KIND_COMPONENT_INSTANCE]
const VALID_PLANES: Array = [PLANE_NONE, PLANE_X, PLANE_Y, PLANE_Z]

## [member role] values the builder writes. A room is what every part is unless it says
## otherwise - see [member role] and [method is_room].
const ROLE_ROOM: String = "room"
const ROLE_HALLWAY: String = "hallway"

## [member absolute] serializes as a flat array of exactly this many floats:
## basis.x.xyz, basis.y.xyz, basis.z.xyz, origin.xyz. [Basis.x] / [Basis.y] / [Basis.z]
## are the matrix COLUMNS and the [Basis] constructor takes columns, so writing and
## reading them in that order round-trips bit-for-bit.
const ABSOLUTE_FLOATS: int = 12

## Keys of one [member paint] region record. Pinned as constants because API_CONTRACT_SPORE
## section 2 pins the VALUE SHAPE, not just the field name (FOLLOWUPS F0): a paint entry is
## always exactly {"color": int, "texture": String}.
const PAINT_COLOR: String = "color"
const PAINT_TEXTURE: String = "texture"

## Stable id, e.g. "p_0007". Assigned by [method ShipDoc.new_part_id], never reused.
var id: String = ""

## Parent part id; "" for the root.
var parent: String = ""

## [constant KIND_PRIMITIVE] or [constant KIND_COMPONENT_INSTANCE].
var kind: String = KIND_PRIMITIVE

## Shape family id, or the component definition id when [member kind] is
## [constant KIND_COMPONENT_INSTANCE].
var family: String = ""

## Manufacturer id — a legible style preset that narrows the family's ranges.
var manufacturer: String = ""

## Author-set shape parameters. Stored explicitly, so retuning a manufacturer's ranges
## later never moves a saved ship (SPEC section 4).
var params: Dictionary = {}

## Ray azimuth in the parent's local frame, degrees, [-180, 180).
var yaw: float = 0.0

## Ray elevation, degrees, [-90, 90].
var pitch: float = 0.0

## Orientation in the MOUNT FRAME, degrees per axis, composed Rz then Ry then Rx
## (EULER_ORDER_ZYX). The mount frame's +Z IS the parent's outward surface normal at the anchor,
## so:
##   [code]rot.x[/code] tilts the part off the surface about the mount +X
##   [code]rot.y[/code] tilts it off the surface about the mount +Y
##   [code]rot.z[/code] spins it ON the surface about the normal
##
## RETIRED(ADR 0004, 2026-08-31): [code]roll: float[/code] -> this. `roll` was the only
## orientation a part had - `yaw`/`pitch` choose WHERE on the parent it lands, not which way it
## faces - so a placed part could be spun like a dial and never tilted. [method from_dict] still
## reads a legacy `roll` scalar into [code]rot.z[/code].
var rot: Vector3 = Vector3.ZERO

## Metres along the parent surface normal. 0 is flush; positive floats out.
var offset: float = 0.0

## Per-axis scale applied to the resolved shape.
var scale: Vector3 = Vector3.ONE

## Smooth-union radius against the parent. 0.0 is a hard union.
var blend: float = 0.0

## "" = attached via yaw/pitch/rot/offset to [member parent] (the existing path).
## Non-empty = snapped to that [SnapTargets] id on the parent. Attach angles are then
## DERIVED from the target, not authored, and yaw/pitch are ignored on load.
var snap_id: String = ""

## Spore allows floating parts — bodies "require no base" and cockpits "do not have to be
## attached" (SPORE_CLONE_SPEC section 5). When [member parent] is "" and this part is NOT
## the doc root, this transform positions it in ship space directly.
##
## Serialized as a flat array of [constant ABSOLUTE_FLOATS] floats; see that constant.
var absolute: Transform3D = Transform3D.IDENTITY

## [b]Symmetry is ON by default[/b] (Spore 2008 behaviour, SPORE_CLONE_SPEC section 4):
## false = this part is mirrored, true = the player broke symmetry on it (hold A).
##
## [b]Never read this field alone.[/b] Breaking symmetry CASCADES to every descendant and
## to every part attached later, so the question "is this part mirrored?" is answered by
## [method ShipSymmetry.is_effectively_asymmetric], which walks the ancestor chain. This
## raw flag only records where the player pressed A.
var asymmetric: bool = false

## Paint state — API_CONTRACT_SPORE section 2/10. Keys are region ids from the family's
## `paint_regions`; each value is exactly
## {[constant PAINT_COLOR]: int (index into the active palette),
##  [constant PAINT_TEXTURE]: String (texture id, or "")}.
##
## Normalized on load and on save: a JSON file storing the colour index as 4.0 rather than
## 4 would otherwise hash differently from the same ship painted in the editor, because
## [method ShipCanonical.canonical_json] emits "4" for an int and "4.000000" for a float.
var paint: Dictionary = {}

## RETIRED(2026-08-31): [member mirror_source] / [member mirror_plane] as the mirroring
## MECHANISM -> [ShipSymmetry] (`core/ship_symmetry.gd`), which derives twins from
## [member asymmetric] plus [member ShipDoc.symmetry_plane] and stores no derivative
## records at all. These two fields are still READ so files written under the old model
## open unchanged, and [method to_dict] still writes them for a record that actually is a
## legacy derivative (otherwise [method duplicate_part] and [method ShipDoc.duplicate_doc],
## which both round-trip through [method to_dict], would silently drop the link). Nothing
## new ever sets them.
##
## Source part id when this record is a legacy mirror derivative; "" when it is a real part.
var mirror_source: String = ""

## Reflection plane through the ship root: "" | "x" | "y" | "z". RETIRED — see
## [member mirror_source].
var mirror_plane: String = ""

## Player-facing label. Serialized as "name" (SPEC section 5.1); the field is renamed
## here only because `name` collides with too much Godot vocabulary to be safe.
var display_name: String = ""

## Locked parts are not editable through the UI. Purely an authoring flag.
var locked: bool = false

## RESERVED, Phase 2: an MHZ_Materials id. Read by nothing in Phase 1, present so no
## Phase 1 ship needs migrating.
var material_ref: String = ""

## What this part is FOR. Live values, written by the builder today:
##   [code]"room"[/code]    a habitable module - THE DEFAULT. Every primitive is a room the moment
##                          it is placed ("each and every primitave should by default be a room",
##                          2026-09-02): a sphere, a tunnel, a plate, all of them, so any two parts
##                          that meet can be hatched to each other (ShipJoint) with nothing to
##                          declare first. Named through [member display_name].
##   [code]"hallway"[/code] a tunnel joining two rooms. Written by the templates.
##
## RESERVED, Phase 3: [code]"structural"[/code] | [code]"greeble"[/code] | [code]"mount"[/code].
##
## Deliberately one field rather than a `room` flag beside it: this already round-trips through
## [method to_dict] / [method from_dict] and is already part of the canonical form, so classifying
## a part as a room needs no new schema and no ruleset bump. The vocabulary is open on purpose -
## nothing switches on an unrecognised value.
##
## [method from_dict] still reads a missing or empty role as "" rather than as this default: a
## saved ship keeps the exact record it was hashed with (AGENTS section 8b), and [method is_room]
## treats "" as a room, so an old file gets the new behaviour without a rewritten record.
var role: String = ROLE_ROOM

## Builds a part from its serialized form. [param part_id] comes from the dictionary key
## in [member ShipDoc.parts], not from the record itself.
##
## Tolerant of both the nested spec layout (`attach`, `mirror` sub-objects) and flat
## keys, and maps a JSON null in `mirror.source` / `mirror.plane` to "". Anything it
## cannot read keeps the field default rather than failing the load: a part with one
## bad number should be fixable in the editor, not unopenable.
@warning_ignore("shadowed_variable")
static func from_dict(id: String, d: Dictionary) -> ShipPart:
	var p: ShipPart = ShipPart.new()
	p.id = id
	p.parent = _as_string(d.get("parent", null), "")
	p.kind = _as_enum(d.get("kind", null), VALID_KINDS, KIND_PRIMITIVE)
	p.family = _as_string(d.get("family", null), "")
	p.manufacturer = _as_string(d.get("manufacturer", null), "")
	p.params = _as_dict(d.get("params", null))

	var attach: Dictionary = _as_dict(d.get("attach", null))
	p.yaw = _as_float(_pick(attach, "yaw", d, "yaw"), 0.0)
	p.pitch = _as_float(_pick(attach, "pitch", d, "pitch"), 0.0)
	# Legacy: a 1.0.0 document stores a scalar `roll`, which is exactly this triple's z.
	p.rot = _as_vec3(_pick(attach, "rot", d, "rot"), Vector3.ZERO)
	if not attach.has("rot") and not d.has("rot"):
		p.rot.z = _as_float(_pick(attach, "roll", d, "roll"), 0.0)
	p.offset = _as_float(_pick(attach, "offset", d, "offset"), 0.0)

	p.snap_id = _as_string(_pick(attach, "snap_id", d, "snap_id"), "")
	p.absolute = _as_transform(d.get("absolute", null), Transform3D.IDENTITY)

	p.scale = _as_vec3(d.get("scale", null), Vector3.ONE)
	p.blend = _as_float(d.get("blend", null), 0.0)
	p.asymmetric = _as_bool(d.get("asymmetric", null), false)
	p.paint = _as_paint(d.get("paint", null))

	# RETIRED(2026-08-31): read-only legacy mirroring — see the field docs above.
	# A record written under the old model was a MIRRORED part, so the symmetry that
	# produced it was on for it: `asymmetric` defaults to false and stays false, which is
	# exactly the mapping the new model needs.
	var mirror: Dictionary = _as_dict(d.get("mirror", null))
	p.mirror_source = _as_string(_pick(mirror, "source", d, "mirror_source"), "")
	var plane: String = _as_string(_pick(mirror, "plane", d, "mirror_plane"), "")
	p.mirror_plane = _as_enum(plane.to_lower(), VALID_PLANES, PLANE_NONE)

	p.display_name = _as_string(_pick(d, "name", d, "display_name"), "")
	p.locked = _as_bool(d.get("locked", null), false)
	p.material_ref = _as_string(d.get("material_ref", null), "")
	p.role = _as_string(d.get("role", null), "")
	return p


## The serialized form, matching SPEC section 5.1 plus the API_CONTRACT_SPORE section 2
## additions. [member id] is deliberately absent: it is the dictionary key in
## [member ShipDoc.parts]. Round-trips losslessly with [method from_dict].
##
## `absolute` is written for every part, not only for floating ones. A conditional key
## would be a second file-format rule every other reader has to know about, and identity
## costs twelve zeros; being able to say "every part has an absolute" is worth more.
##
## `mirror` is the opposite case and is written ONLY for a record that really is a legacy
## derivative. RETIRED(2026-08-31): nothing new sets those fields, so no ship saved from
## here on carries the key at all — but dropping it unconditionally would make
## [method duplicate_part] and [method ShipDoc.duplicate_doc] (both of which round-trip
## through this function, the latter on every undo snapshot) silently unlink an old ship's
## derivatives mid-session.
func to_dict() -> Dictionary:
	var out: Dictionary = {
		"parent": parent,
		"kind": kind,
		"family": family,
		"manufacturer": manufacturer,
		"params": params.duplicate(true),
		"attach": {"yaw": yaw, "pitch": pitch, "rot": [rot.x, rot.y, rot.z], "offset": offset},
		"snap_id": snap_id,
		"absolute": _transform_to_array(absolute),
		"scale": [scale.x, scale.y, scale.z],
		"blend": blend,
		"asymmetric": asymmetric,
		"paint": _as_paint(paint),
		"name": display_name,
		"locked": locked,
		"material_ref": material_ref,
		"role": role,
	}
	if not mirror_source.is_empty() or not mirror_plane.is_empty():
		var mirror_source_value: Variant = null
		if not mirror_source.is_empty():
			mirror_source_value = mirror_source
		var mirror_plane_value: Variant = null
		if not mirror_plane.is_empty():
			mirror_plane_value = mirror_plane
		out["mirror"] = {"source": mirror_source_value, "plane": mirror_plane_value}
	return out


## True when this record is generated by reflecting another part rather than authored.
## A derivative is not independently editable until "break link" materializes it.
func is_mirror() -> bool:
	return not mirror_source.is_empty()


## Is this part a room - a module the crew can be in, one that can be named and hatched to?
##
## True for [constant ROLE_ROOM] and for "" alike: "" is what every part saved before the
## room-by-default rule carries, and what [method from_dict] keeps for it, and those parts are rooms
## too. Only a part that says it is something else - a hallway, or a Phase 3 structural/greeble/
## mount - is not. Ask this, never compare [member role] to a string.
func is_room() -> bool:
	return role == ROLE_ROOM or role.is_empty()


## A deep copy carrying the same id. Callers that want a distinct part must assign a
## fresh id from [method ShipDoc.new_part_id] — ids are never reused, so this cannot
## be done for them safely.
func duplicate_part() -> ShipPart:
	return ShipPart.from_dict(id, to_dict())


# --- internals ---------------------------------------------------------------------


## Reads [param key_a] from [param primary], falling back to [param key_b] in
## [param fallback]. Lets a part be written either nested or flat.
static func _pick(
	primary: Dictionary, key_a: String, fallback: Dictionary, key_b: String
) -> Variant:
	if primary.has(key_a):
		return primary[key_a]
	if fallback.has(key_b):
		return fallback[key_b]
	return null


static func _as_string(v: Variant, def: String) -> String:
	if v is String:
		var s: String = v
		return s
	if v is StringName:
		return str(v)
	return def


static func _as_enum(v: Variant, allowed: Array, def: String) -> String:
	var s: String = _as_string(v, def)
	if allowed.has(s):
		return s
	return def


static func _as_float(v: Variant, def: float) -> float:
	if v is float:
		var f: float = v
		return f
	if v is int:
		var i: int = v
		return float(i)
	return def


static func _as_int(v: Variant, def: int) -> int:
	if v is int:
		var i: int = v
		return i
	if v is float:
		var f: float = v
		if is_finite(f):
			return int(round(f))
		return def
	if v is String:
		var s: String = v
		if s.strip_edges().is_valid_int():
			return s.strip_edges().to_int()
	return def


static func _as_bool(v: Variant, def: bool) -> bool:
	if v is bool:
		var b: bool = v
		return b
	return def


static func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


## [member absolute] -> the flat 12-float array. Columns first, then the origin; see
## [constant ABSOLUTE_FLOATS].
static func _transform_to_array(t: Transform3D) -> Array:
	var b: Basis = t.basis
	var o: Vector3 = t.origin
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]


## Inverse of [method _transform_to_array]. Also accepts a live [Transform3D] so a
## hand-built dictionary can pass one straight through. Anything else — wrong length,
## non-numeric entries, a non-finite value — falls back to [param def] rather than
## producing a degenerate basis that would make the part unresolvable.
static func _as_transform(v: Variant, def: Transform3D) -> Transform3D:
	if v is Transform3D:
		var t: Transform3D = v
		return t
	if not (v is Array):
		return def
	var a: Array = v
	if a.size() < ABSOLUTE_FLOATS:
		return def
	var f: PackedFloat64Array = PackedFloat64Array()
	for i: int in ABSOLUTE_FLOATS:
		var value: float = _as_float(a[i], NAN)
		if not is_finite(value):
			return def
		f.append(value)
	return Transform3D(
		Basis(Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), Vector3(f[6], f[7], f[8])),
		Vector3(f[9], f[10], f[11])
	)


## Normalizes [member paint] to the pinned value shape: region id -> {"color": int,
## "texture": String}. A region whose value is not an object is dropped, because a
## half-typed entry would put a Variant of unknown type into the document hash.
static func _as_paint(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (v is Dictionary):
		return out
	var d: Dictionary = v
	for key: Variant in d:
		var region: String = str(key)
		var raw: Variant = d[key]
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		out[region] = {
			PAINT_COLOR: _as_int(entry.get(PAINT_COLOR, null), 0),
			PAINT_TEXTURE: _as_string(entry.get(PAINT_TEXTURE, null), ""),
		}
	return out


static func _as_vec3(v: Variant, def: Vector3) -> Vector3:
	if v is Vector3:
		var v3: Vector3 = v
		return v3
	if v is Array:
		var a: Array = v
		if a.size() >= 3:
			return Vector3(_as_float(a[0], def.x), _as_float(a[1], def.y), _as_float(a[2], def.z))
	if v is Dictionary:
		var d: Dictionary = v
		return Vector3(
			_as_float(d.get("x", null), def.x),
			_as_float(d.get("y", null), def.y),
			_as_float(d.get("z", null), def.z)
		)
	return def

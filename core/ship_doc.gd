class_name ShipDoc
extends RefCounted

## The ship document — SPEC section 5.1, API_CONTRACT section 11.
##
## This is the truth. The scene view, the SDF and the bake are three views of it and
## none of them writes back. A strict tree over [member parts]: one [member root], every
## other part with exactly one parent, no cycles.
##
## [b]Id monotonicity is a contract.[/b] Part ids are immutable once created and are never
## reused, because Phase 2 regions, damage state and routing will reference them. Deleting
## p_0007 does not free the name p_0007. The counters that guarantee this are serialized
## into `settings.next_id` (see [method to_dict]) so monotonicity survives a save/load
## cycle; a legacy file without that field has its counters recovered from the highest
## id actually present.
##
## [b][method part_order] is the stable iteration order[/b] for everything downstream —
## hashing, SDF build, metrics, bake. Root first, then depth-first with children visited
## in sorted-id order.

const FORMAT: String = "mhz_ship"
const VERSION: int = 1
## 4.0.0 (ADR 0007): SHEAR. A fourth morph verb - "spore has handles that ... stretch, skew, twist,
## rotate" - and the first op inserted into the domain-warp stage rather than appended, because a
## domain warp cannot be appended: everything after the base operates on a distance. At its default
## of zero it is the identity, so NO shape moves; the bump is for the canonical form, which now
## carries two more params, and for the op order, which AGENTS section 8b makes a version event
## whatever its visible effect.
const RULESET_VERSION: String = "4.0.0"

const UNITS_METRES: String = "metres"

const PART_ID_PREFIX: String = "p_"
const JOINT_ID_PREFIX: String = "j_"
const ID_DIGITS: int = 4

## Schema addition beyond the SPEC section 5.1 sample: `settings.next_id` is
## `{"part": int, "joint": int}`, the next unhanded-out counter value for each id space.
## Without it, saving a ship whose last part was deleted and reloading it would hand the
## dead part's id back out to the next new part, and every Phase 2 reference to that id
## would silently retarget.
const NEXT_ID_KEY: String = "next_id"
const NEXT_ID_PART: String = "part"
const NEXT_ID_JOINT: String = "joint"

const JOINT_KEY_SEP: String = "|"

## "metres". Recorded so a future unit system cannot silently reinterpret old files.
var units: String = UNITS_METRES

## Part id of the tree root; "" for an empty document.
var root: String = ""

## Bilateral symmetry plane: "x", "y", "z", or "" for off. Defaults to "x".
##
## SYMMETRY IS ON BY DEFAULT — see [ShipSymmetry]. In Spore 2008 it was automatic and unbreakable;
## breaking it per-part came later and CASCADES to descendants. Never read a part's `asymmetric`
## flag directly; ask [method ShipSymmetry.is_effectively_asymmetric].
var symmetry_plane: String = "x"

## Per-document authoring settings — snap increments and the id counters.
## [member ShipConfig] holds the dev levers; this holds what the player chose for
## [b]this ship[/b].
var settings: Dictionary = {}

## String -> [ShipPart].
var parts: Dictionary = {}

## String -> [ShipJoint], keyed by [method joint_key_for] or by "j_NNNN".
var joints: Dictionary = {}

## String -> Dictionary {label, root, parts}. Component definitions, stored raw:
## [ShipComponents] owns their interpretation.
var components: Dictionary = {}

## The ruleset this document was authored under. A ship that hashed to X today must hash
## to X forever [i]under its recorded ruleset version[/i], so the version travels with the
## document rather than being assumed to be the current build's.
var ruleset_version: String = RULESET_VERSION

## Problems found by [method from_dict]. A format or version mismatch lands here rather
## than crashing the load: an unopenable ship is worse than a flagged one.
var load_errors: PackedStringArray = PackedStringArray()

## Next part number to hand out. Only ever increases. See [constant NEXT_ID_KEY].
var _next_part: int = 1

## Next joint number to hand out. Only ever increases.
var _next_joint: int = 1


## A one-part ship: a single root primitive of [param family_id] / [param manufacturer_id]
## with that combination's default params and no attach values (the root has no parent to attach
## to).
##
## [param data] supplies the default params and the snap settings. Passing null yields
## empty params and the shipped snap defaults, which keeps this callable from a test that
## has no data packs loaded.
##
## [param span_m] is the widest bounding-box axis the root is scaled to; 0 or less leaves it at
## unit scale, which is what every pre-existing call site gets. A trailing optional parameter,
## for the reason FOLLOWUPS F1 gives: the API contract is frozen, and an additive optional
## argument keeps every existing call compiling. Passing [member ShipConfig.root_span_m] here is
## what stops the first part's size from being an accident of which family the player clicked.
static func create_new(
	family_id: String, manufacturer_id: String, data: ShipData, span_m: float = 0.0
) -> ShipDoc:
	var doc: ShipDoc = ShipDoc.new()
	doc.units = UNITS_METRES
	doc.ruleset_version = RULESET_VERSION

	var cfg: ShipConfig = ShipConfig.defaults()
	if data != null and data.config != null:
		cfg = data.config
	doc.settings = {
		"snap_deg": cfg.snap_deg,
		"snap_m": cfg.snap_m,
		"snap_scale": cfg.snap_scale,
	}

	var part: ShipPart = ShipPart.new()
	part.parent = ""
	part.kind = ShipPart.KIND_PRIMITIVE
	part.family = family_id
	part.manufacturer = manufacturer_id
	if data != null:
		part.params = ShapeGen.default_params(data, family_id, manufacturer_id)
	part.yaw = 0.0
	part.pitch = 0.0
	part.rot = Vector3.ZERO
	part.offset = 0.0
	part.scale = _span_scale(data, family_id, manufacturer_id, part.params, span_m, cfg)
	part.blend = 0.0
	part.display_name = family_id

	doc.root = doc.add_part(part)
	return doc


## Uniform scale that puts the widest axis of this family's resolved bounding box at
## [param span_m] metres. Falls back to unit scale for a non-positive span, a missing pack, or a
## degenerate shape - a root that silently collapsed to nothing would be far worse than one that
## started at its authored size.
static func _span_scale(
	data: ShipData,
	family_id: String,
	manufacturer_id: String,
	params: Dictionary,
	span_m: float,
	cfg: ShipConfig
) -> Vector3:
	if span_m <= 0.0 or data == null:
		return Vector3.ONE
	var shape: ResolvedShape = ShapeGen.resolve(
		data, family_id, manufacturer_id, params, Vector3.ONE
	)
	var extent: Vector3 = shape.local_aabb().size
	var widest: float = maxf(extent.x, maxf(extent.y, extent.z))
	if widest <= 0.0:
		return Vector3.ONE
	var k: float = clampf(span_m / widest, cfg.part_scale_min, cfg.part_scale_max)
	return Vector3(k, k, k)


## Reads a serialized document. Round-trips losslessly with [method to_dict].
##
## A wrong `format`, `version` or `ruleset_version` is recorded in [member load_errors]
## and the load continues. The three exemptions in SPEC section 8 exist for the same
## reason: the day a lever moves, every ship that was legal yesterday must still open.
static func from_dict(d: Dictionary) -> ShipDoc:
	var doc: ShipDoc = ShipDoc.new()

	var format: String = _as_string(d.get("format", null), "")
	if format != FORMAT:
		doc.load_errors.append('format mismatch: expected "%s", got "%s"' % [FORMAT, format])
	var version: int = _as_int(d.get("version", null), 0)
	if version != VERSION:
		doc.load_errors.append("version mismatch: expected %d, got %d" % [VERSION, version])

	doc.ruleset_version = _as_string(d.get("ruleset_version", null), RULESET_VERSION)
	if doc.ruleset_version != RULESET_VERSION:
		doc.load_errors.append(
			(
				'ruleset mismatch: document is "%s", this build generates "%s"'
				% [doc.ruleset_version, RULESET_VERSION]
			)
		)

	doc.units = _as_string(d.get("units", null), UNITS_METRES)
	doc.root = _as_string(d.get("root", null), "")
	# Absent in pre-symmetry files: default to "x" so an old ship gains mirroring
	# rather than silently losing it.
	doc.symmetry_plane = _as_string(d.get("symmetry_plane", null), "x")

	var raw_settings: Dictionary = _as_dict(d.get("settings", null))
	var next_part: int = 1
	var next_joint: int = 1
	if raw_settings.has(NEXT_ID_KEY):
		var next_id: Variant = raw_settings[NEXT_ID_KEY]
		if next_id is Dictionary:
			var nd: Dictionary = next_id
			next_part = maxi(1, _as_int(nd.get(NEXT_ID_PART, null), 1))
			next_joint = maxi(1, _as_int(nd.get(NEXT_ID_JOINT, null), 1))
		else:
			next_part = maxi(1, _as_int(next_id, 1))
		# Held in the counters, re-emitted by to_dict(). Keeping it out of `settings`
		# stops the UI from ever presenting a bookkeeping field as a player setting.
		raw_settings.erase(NEXT_ID_KEY)
	doc.settings = raw_settings

	var raw_parts: Dictionary = _as_dict(d.get("parts", null))
	for key: Variant in raw_parts:
		var part_id: String = str(key)
		var value: Variant = raw_parts[key]
		if value is Dictionary:
			var pd: Dictionary = value
			doc.parts[part_id] = ShipPart.from_dict(part_id, pd)
		else:
			doc.load_errors.append('part "%s" is not an object' % part_id)

	var raw_joints: Dictionary = _as_dict(d.get("joints", null))
	for key: Variant in raw_joints:
		var joint_id: String = str(key)
		var value: Variant = raw_joints[key]
		if value is Dictionary:
			var jd: Dictionary = value
			doc.joints[joint_id] = ShipJoint.from_dict(joint_id, jd)
		else:
			doc.load_errors.append('joint "%s" is not an object' % joint_id)

	doc.components = _as_dict(d.get("components", null))

	doc._next_part = next_part
	doc._next_joint = next_joint
	doc._recover_counters()

	if doc.root.is_empty():
		if not doc.parts.is_empty():
			doc.load_errors.append("document has parts but no root")
	elif not doc.parts.has(doc.root):
		doc.load_errors.append('root "%s" is not present in parts' % doc.root)

	return doc


## The serialized form. Parts are written in [method part_order] and joints in sorted key
## order, so two identical documents produce byte-identical files.
##
## `settings.next_id` is written here and stripped again by [method from_dict]; see
## [constant NEXT_ID_KEY] for why it exists.
func to_dict() -> Dictionary:
	var out_settings: Dictionary = settings.duplicate(true)
	out_settings[NEXT_ID_KEY] = {
		NEXT_ID_PART: _next_part,
		NEXT_ID_JOINT: _next_joint,
	}

	var out_parts: Dictionary = {}
	var order: PackedStringArray = part_order()
	var part_count: int = order.size()
	for i: int in part_count:
		var part_id: String = order[i]
		var value: Variant = parts.get(part_id, null)
		if value is ShipPart:
			var p: ShipPart = value
			out_parts[part_id] = p.to_dict()

	var out_joints: Dictionary = {}
	var joint_ids: PackedStringArray = _sorted_keys(joints)
	var joint_count: int = joint_ids.size()
	for i: int in joint_count:
		var joint_id: String = joint_ids[i]
		var value: Variant = joints.get(joint_id, null)
		if value is ShipJoint:
			var j: ShipJoint = value
			out_joints[joint_id] = j.to_dict()

	return {
		"format": FORMAT,
		"version": VERSION,
		"ruleset_version": ruleset_version,
		"units": units,
		"root": root,
		"symmetry_plane": symmetry_plane,
		"settings": out_settings,
		"parts": out_parts,
		"joints": out_joints,
		"components": components.duplicate(true),
	}


## A deep copy, sharing no [ShipPart] or [ShipJoint] instance with this document.
## This is what [ShipHistory] snapshots and what an edit operates on.
func duplicate_doc() -> ShipDoc:
	var copy: ShipDoc = ShipDoc.from_dict(to_dict())
	copy.load_errors = load_errors.duplicate()
	return copy


## The next unused part id, "p_0001" style. Monotonic and never reused: the counter only
## moves forward, and deleting a part does not wind it back.
##
## The while loop is a safety net for a hand-edited file whose counter is behind the ids
## it actually contains; [method from_dict] normally fixes that up front.
func new_part_id() -> String:
	var candidate: String = _format_id(PART_ID_PREFIX, _next_part)
	while parts.has(candidate):
		_next_part += 1
		candidate = _format_id(PART_ID_PREFIX, _next_part)
	_next_part += 1
	return candidate


## The next unused joint id, "j_0001" style. Same monotonicity contract as
## [method new_part_id].
func new_joint_id() -> String:
	var candidate: String = _format_id(JOINT_ID_PREFIX, _next_joint)
	while joints.has(candidate):
		_next_joint += 1
		candidate = _format_id(JOINT_ID_PREFIX, _next_joint)
	_next_joint += 1
	return candidate


## Inserts [param part] and returns the id it now carries.
##
## The document takes ownership of the instance rather than copying it, and assigns
## [member ShipPart.id] when it is empty — the one place in [code]core/[/code] where an
## argument is written to, and the reason the function returns the id at all. Pass
## [method ShipPart.duplicate_part] if the caller wants to keep an independent copy.
##
## A parentless part added to a document with no root becomes the root.
func add_part(part: ShipPart) -> String:
	if part == null:
		return ""
	if part.id.is_empty():
		part.id = new_part_id()
	parts[part.id] = part
	_bump_part_counter(part.id)
	if root.is_empty() and part.parent.is_empty():
		root = part.id
	return part.id


## Stored parts with no parent that are not the root.
##
## These are LEGAL. Spore's vehicle/ship editor has no contiguity requirement at all — bodies
## "require no base" and cockpits "do not have to be attached", and a creation with floating pieces
## still saves. The bake reports them as islands; nothing refuses them.
func floating_part_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: String in part_order():
		if id == root:
			continue
		var v: Variant = parts.get(id, null)
		if not (v is ShipPart):
			continue
		var part: ShipPart = v
		if part.parent == "":
			out.append(id)
	return out


## Removes [param id] and everything that depends on it, returning every removed part id
## in sorted order.
##
## What goes with it:
## [br]- the whole descendant subtree, because a part whose parent is gone has no frame
##   to resolve against;
## [br]- every joint referencing any removed part, because a joint over a missing part is
##   not authorable data;
## [br]- every mirror derivative whose source was removed, and that derivative's own
##   subtree, iterated to a fixed point.
## [br]
## The id counters are deliberately not wound back. Removing the root leaves
## [member root] empty rather than promoting a child — which child would be arbitrary,
## and the validator reports `no_root` clearly.
func remove_part(id: String) -> PackedStringArray:
	if not parts.has(id):
		return PackedStringArray()

	var index: Dictionary = _children_index()
	var removed: Dictionary = {}
	_collect_subtree(id, index, removed)

	var changed: bool = true
	while changed:
		changed = false
		for key: Variant in parts:
			var part_id: String = str(key)
			if removed.has(part_id):
				continue
			var value: Variant = parts[key]
			if not (value is ShipPart):
				continue
			var p: ShipPart = value
			if p.is_mirror() and removed.has(p.mirror_source):
				_collect_subtree(part_id, index, removed)
				changed = true

	var ids: PackedStringArray = _sorted_keys(removed)
	var removed_count: int = ids.size()
	for i: int in removed_count:
		parts.erase(ids[i])

	var dead_joints: PackedStringArray = PackedStringArray()
	for key: Variant in joints:
		var value: Variant = joints[key]
		if not (value is ShipJoint):
			continue
		var j: ShipJoint = value
		if removed.has(j.a) or removed.has(j.b):
			dead_joints.append(str(key))
	var dead_count: int = dead_joints.size()
	for i: int in dead_count:
		joints.erase(dead_joints[i])

	if removed.has(root):
		root = ""

	return ids


## Direct children of [param id], sorted by id.
func children_of(id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: Variant in parts:
		var part_id: String = str(key)
		if part_id == id:
			continue
		var value: Variant = parts[key]
		if not (value is ShipPart):
			continue
		var p: ShipPart = value
		if p.parent == id:
			out.append(part_id)
	out.sort()
	return out


## Every descendant of [param id], depth-first with children in sorted-id order,
## excluding [param id] itself. Cycle-safe: a malformed document terminates rather
## than recursing forever.
func descendants_of(id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	seen[id] = true
	_walk(id, _children_index(), out, seen)
	return out


## Every ancestor of [param id], nearest first, excluding [param id] itself. Stops at the
## root, at a missing parent, or at the first repeat if the document contains a cycle.
func ancestors_of(id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	seen[id] = true
	var current: String = id
	while true:
		var value: Variant = parts.get(current, null)
		if not (value is ShipPart):
			break
		var p: ShipPart = value
		var parent_id: String = p.parent
		if parent_id.is_empty() or seen.has(parent_id) or not parts.has(parent_id):
			break
		out.append(parent_id)
		seen[parent_id] = true
		current = parent_id
	return out


## The stable iteration order for every downstream system: root first, then depth-first
## with children visited in sorted-id order.
##
## Parts unreachable from the root are appended afterwards, each followed by its own
## subtree, in sorted-id order. Such parts mean the document is invalid — the validator
## reports `orphan_part` — but dropping them here would make a bake silently disagree
## with the tree panel, so they are ordered rather than hidden. Every id in
## [member parts] appears exactly once.
func part_order() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var index: Dictionary = _children_index()

	if not root.is_empty() and parts.has(root):
		out.append(root)
		seen[root] = true
		_walk(root, index, out, seen)

	var rest: PackedStringArray = PackedStringArray()
	for key: Variant in parts:
		var part_id: String = str(key)
		if not seen.has(part_id):
			rest.append(part_id)
	rest.sort()

	var rest_count: int = rest.size()
	for i: int in rest_count:
		var part_id: String = rest[i]
		if seen.has(part_id):
			continue
		out.append(part_id)
		seen[part_id] = true
		_walk(part_id, index, out, seen)

	return out


## The canonical key for the unordered pair ([param a], [param b]).
##
## Sorted lexicographically, so joint_key_for("p_0007", "p_0001") and
## joint_key_for("p_0001", "p_0007") are the same string and one pair of parts can only
## ever carry one joint.
static func joint_key_for(a: String, b: String) -> String:
	if a <= b:
		return a + JOINT_KEY_SEP + b
	return b + JOINT_KEY_SEP + a


# --- internals ---------------------------------------------------------------------


static func _format_id(prefix: String, n: int) -> String:
	return prefix + str(n).pad_zeros(ID_DIGITS)


## Numeric suffix of "p_0007" -> 7, or -1 when the id does not follow the pattern.
static func _id_number(id: String, prefix: String) -> int:
	if not id.begins_with(prefix):
		return -1
	var tail: String = id.substr(prefix.length())
	if tail.is_empty() or not tail.is_valid_int():
		return -1
	return tail.to_int()


func _bump_part_counter(id: String) -> void:
	var n: int = _id_number(id, PART_ID_PREFIX)
	if n >= _next_part:
		_next_part = n + 1


func _bump_joint_counter(id: String) -> void:
	var n: int = _id_number(id, JOINT_ID_PREFIX)
	if n >= _next_joint:
		_next_joint = n + 1


## Drags the counters past every id actually present. Covers legacy files with no
## `settings.next_id` and hand-edited files whose counter is behind reality; a correctly
## written file makes this a no-op.
func _recover_counters() -> void:
	for key: Variant in parts:
		_bump_part_counter(str(key))
	for key: Variant in joints:
		_bump_joint_counter(str(key))


## parent_id -> sorted Array of child ids, built in one pass over [member parts].
##
## [method children_of] scans every part, so walking the tree with it is quadratic.
## [method part_order] runs on every undo snapshot, every document hash, every SDF
## build and every bake, so the walks index once and share it. Buckets are Arrays
## rather than PackedStringArrays deliberately: Arrays are shared references, so
## appending into one does not copy it.
func _children_index() -> Dictionary:
	var index: Dictionary = {}
	for key: Variant in parts:
		var part_id: String = str(key)
		var value: Variant = parts[key]
		if not (value is ShipPart):
			continue
		var p: ShipPart = value
		if p.parent.is_empty() or p.parent == part_id:
			continue
		if not index.has(p.parent):
			index[p.parent] = []
		var bucket: Array = index[p.parent]
		bucket.append(part_id)
	for key: Variant in index:
		var bucket: Array = index[key]
		bucket.sort()
	return index


## Depth-first walk from [param id], appending children (never [param id] itself).
## [param seen] doubles as the cycle guard.
func _walk(id: String, index: Dictionary, out: PackedStringArray, seen: Dictionary) -> void:
	var kids: Array = index.get(id, [])
	var n: int = kids.size()
	for i: int in n:
		var kid: String = kids[i]
		if seen.has(kid):
			continue
		seen[kid] = true
		out.append(kid)
		_walk(kid, index, out, seen)


func _collect_subtree(id: String, index: Dictionary, acc: Dictionary) -> void:
	if acc.has(id):
		return
	acc[id] = true
	var kids: Array = index.get(id, [])
	var n: int = kids.size()
	for i: int in n:
		_collect_subtree(str(kids[i]), index, acc)


static func _sorted_keys(d: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: Variant in d:
		out.append(str(key))
	out.sort()
	return out


static func _as_string(v: Variant, def: String) -> String:
	if v is String:
		var s: String = v
		return s
	if v is StringName:
		return str(v)
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


static func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}

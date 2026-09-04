class_name ShipSymmetry
extends RefCounted

## Bilateral symmetry — API_CONTRACT_SPORE section 4, SPORE_CLONE_SPEC section 4.
##
## [b]SYMMETRY IS ON BY DEFAULT.[/b] That is the opposite of what this project originally built,
## and it is not a preference: in Spore 2008 symmetry was automatic and could not be broken at all
## (an "Asymmetry Mod" existed precisely because there was no in-game way), and a later patch added
## hold-[code]A[/code] to break it for one part. Placing a part off the centre line CREATES a
## mirrored duplicate; it never refuses the placement.
##
## [b]Breaking symmetry CASCADES.[/b] Sourced, verbatim, from a player tutorial describing the
## spaceship editor: "This will remove the base part's double as well as all those from the detail
## parts attached to it... This will make all new parts attached to it asymmetric." The engine's own
## parent/child structure backs this up. So [member ShipPart.asymmetric] is a per-part FLAG, not a
## per-part ANSWER — always ask [method is_effectively_asymmetric], which walks the ancestors.
## Reading the raw flag alone is a bug, and the test suite asserts against exactly that.
##
## RETIRED(2026-08-31): [member ShipPart.mirror_source] / [member ShipPart.mirror_plane] were the
## old opt-in mechanism. They are still READ so old files load, never written. This class is the
## authority (AGENTS section 8a).

## Twin id suffix. FIXED FORMAT — other modules parse it, so changing it breaks saved documents
## and every consumer at once.
const TWIN_SUFFIX: String = "~m"

## The planes a document may mirror across. "" means symmetry is off entirely.
# A plain Array, not a PackedStringArray: a Packed*Array constructor is a CALL, and GDScript
# rejects a call in a const initialiser ("isn't a constant expression"). gdparse accepts it,
# the engine does not.
const PLANES: Array = ["x", "y", "z"]


## True when [param part_id] or ANY ancestor is flagged asymmetric. THIS is the cascade, and it is
## the only correct way to ask the question.
static func is_effectively_asymmetric(doc: ShipDoc, part_id: String) -> bool:
	if doc == null or part_id == "":
		return false
	var part: ShipPart = _part(doc, part_id)
	if part != null and part.asymmetric:
		return true
	for ancestor_id: String in doc.ancestors_of(part_id):
		var ancestor: ShipPart = _part(doc, ancestor_id)
		if ancestor != null and ancestor.asymmetric:
			return true
	return false


## Set the flag on one part. Returns every id whose EFFECTIVE state changed — the part plus any
## descendant that was not already overridden by a nearer asymmetric ancestor.
##
## The return is what the UI repaints and what the complexity readout re-totals, so it must be the
## effective set and not merely [param part_id].
static func set_asymmetric(doc: ShipDoc, part_id: String, value: bool) -> PackedStringArray:
	var changed: PackedStringArray = PackedStringArray()
	if doc == null:
		return changed
	var part: ShipPart = _part(doc, part_id)
	if part == null or part.asymmetric == value:
		return changed

	var before: Dictionary = {}
	before[part_id] = is_effectively_asymmetric(doc, part_id)
	for descendant_id: String in doc.descendants_of(part_id):
		before[descendant_id] = is_effectively_asymmetric(doc, descendant_id)

	part.asymmetric = value

	for id: Variant in before:
		var key: String = String(id)
		if is_effectively_asymmetric(doc, key) != bool(before[id]):
			changed.append(key)
	return changed


## Would this part generate a mirrored twin?
##
## False when it is effectively asymmetric, when the document has symmetry off, or when it sits ON
## the plane within [member ShipConfig.symmetry_plane_epsilon] — a part straddling the centre line
## mirrors onto itself, so emitting a twin there would double-draw it and double-bill its
## complexity. The document root always lands in that band.
static func generates_twin(
	doc: ShipDoc, part_id: String, xform: Transform3D, cfg: ShipConfig
) -> bool:
	if doc == null or cfg == null:
		return false
	if not PLANES.has(doc.symmetry_plane):
		return false
	if is_effectively_asymmetric(doc, part_id):
		return false
	var axis: int = plane_axis(doc.symmetry_plane)
	if axis < 0:
		return false
	return absf(xform.origin[axis]) > absf(cfg.symmetry_plane_epsilon)


## Twin id for a source part. Format is fixed: "<source_id>~m".
static func twin_id(source_id: String) -> String:
	return source_id + TWIN_SUFFIX


static func is_twin_id(id: String) -> bool:
	return id.ends_with(TWIN_SUFFIX) and id.length() > TWIN_SUFFIX.length()


## Source part id for a twin. Returns [param twin] unchanged when it is not a twin id, so callers
## can pass any id without testing first.
static func source_of_twin(twin: String) -> String:
	if not is_twin_id(twin):
		return twin
	return twin.substr(0, twin.length() - TWIN_SUFFIX.length())


## Axis index for a plane name: 0/1/2, or -1 when symmetry is off or the name is unknown.
static func plane_axis(plane: String) -> int:
	match plane:
		"x":
			return 0
		"y":
			return 1
		"z":
			return 2
	return -1


## Every stored part that would currently emit a twin, in document order. Used by the complexity
## pass and by anything reporting how many physical parts a ship really has.
static func twinning_part_ids(
	doc: ShipDoc, xforms: Dictionary, cfg: ShipConfig
) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null:
		return out
	for id: String in doc.part_order():
		if not xforms.has(id):
			continue
		var xf_v: Variant = xforms[id]
		if not (xf_v is Transform3D):
			continue
		var xf: Transform3D = xf_v
		if generates_twin(doc, id, xf, cfg):
			out.append(id)
	return out


## Migrate a legacy document. A part carrying the retired `mirror_source` was, under the old opt-in
## model, an explicitly created derivative — which means the author had ALREADY chosen mirroring
## there, so the part maps to symmetric (`asymmetric = false`) and the stale fields are cleared.
## Everything else in an old file was, under the old model, un-mirrored on purpose.
##
## Returns the ids it touched. Idempotent: running it twice changes nothing the second time.
static func migrate_legacy(doc: ShipDoc) -> PackedStringArray:
	var touched: PackedStringArray = PackedStringArray()
	if doc == null:
		return touched
	for id: Variant in doc.parts:
		var part: ShipPart = _part(doc, String(id))
		if part == null or part.mirror_source == "":
			continue
		part.asymmetric = false
		part.mirror_source = ""
		part.mirror_plane = ""
		touched.append(String(id))
	return touched


static func _part(doc: ShipDoc, part_id: String) -> ShipPart:
	if doc == null or not doc.parts.has(part_id):
		return null
	var v: Variant = doc.parts[part_id]
	if v is ShipPart:
		return v
	return null

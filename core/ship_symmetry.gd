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

## The planes a document may mirror across, one letter each. "" means symmetry is off entirely.
# A plain Array, not a PackedStringArray: a Packed*Array constructor is a CALL, and GDScript
# rejects a call in a const initialiser ("isn't a constant expression"). gdparse accepts it,
# the engine does not.
const PLANES: Array = ["x", "y", "z"]

## The order axes are always written in, so one set of planes has exactly one spelling and a
## document that hashed under it keeps hashing the same.
const AXIS_ORDER: String = "xyz"


## The planes [param doc] mirrors across, as single letters in [constant AXIS_ORDER].
##
## [member ShipDoc.symmetry_plane] HOLDS A SET, not one plane (ADR 0043): "x", "xy", "xyz", or ""
## for off. A document written before that carries a single letter and still means exactly what it
## always did, which is why the field was widened rather than replaced - "x" spells the same, so
## every saved ship hashes the same.
static func planes_of(doc: ShipDoc) -> PackedStringArray:
	return axes_of(doc.symmetry_plane) if doc != null else PackedStringArray()


## [param planes] as single letters, in [constant AXIS_ORDER], each at most once. Anything that is
## not an axis letter is dropped, so a malformed field reads as fewer planes rather than as an
## error.
static func axes_of(planes: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for axis: String in AXIS_ORDER:
		if planes.contains(axis):
			out.append(axis)
	return out


## [param planes] in the one spelling this class writes: ordered, deduplicated, letters only.
static func normalise_planes(planes: String) -> String:
	return "".join(axes_of(planes.to_lower()))


## [param planes] with [param axis] turned on or off - the and/or the author asked for, "where
## reflections can happen across all 3 axis at once" (2026-09-21).
static func with_plane(planes: String, axis: String, on: bool) -> String:
	var out: String = ""
	for candidate: String in axes_of(planes):
		if candidate != axis:
			out += candidate
	if on and PLANES.has(axis):
		out += axis
	return normalise_planes(out)


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
	return not reflections_of(doc, part_id, xform, cfg).is_empty()


## EVERY reflection [param part_id] generates, as axis sets - `["x"]`, or `["x", "y", "xy"]`.
##
## A part off the plane on n of the document's planes has 2^n - 1 twins: one per non-empty subset
## of those axes (ADR 0043). A part sitting ON a plane within
## [member ShipConfig.symmetry_plane_epsilon] mirrors onto itself there, so that axis is left out
## of the reckoning entirely rather than producing a twin on top of the original - which is what
## keeps the document root single whatever the planes say.
static func reflections_of(
	doc: ShipDoc, part_id: String, xform: Transform3D, cfg: ShipConfig
) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null or cfg == null or is_effectively_asymmetric(doc, part_id):
		return out
	var off: PackedStringArray = PackedStringArray()
	for axis: String in planes_of(doc):
		var index: int = plane_axis(axis)
		if index >= 0 and absf(xform.origin[index]) > absf(cfg.symmetry_plane_epsilon):
			off.append(axis)
	# Every non-empty subset, counted in binary so the order is deterministic and the single-plane
	# case comes out as the one entry it always was.
	for mask: int in range(1, 1 << off.size()):
		var chosen: String = ""
		for i: int in off.size():
			if (mask >> i) & 1 == 1:
				chosen += off[i]
		out.append(chosen)
	return out


## EVERY twin id [param source_id] could take under [param doc]'s planes - not the ones it does.
##
## The shape pass aliases a twin's shape "for anything that COULD twin rather than anything that
## DOES, because whether a twin exists depends on where the part landed and only the transform
## pass knows that" (`ShipAttach.resolve_shapes`). Before ADR 0043 that was one key, `id~m`, and
## the alias was written directly. With a SET of planes the transform pass emits `id~mx`, `id~my`
## and `id~mxy`, so the one bare alias matched none of them and every consumer - which pairs the
## shape and transform maps by key and skips anything in only one - silently built no twin at all.
##
## Returns the bare `~m` for a one-plane document, exactly as [method reflections_of] does, so a
## single-plane ship keys identically to the way it always has.
static func possible_twin_ids(doc: ShipDoc, source_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var planes: PackedStringArray = planes_of(doc)
	if planes.is_empty():
		return out
	if planes.size() == 1:
		out.append(twin_id(source_id))
		return out
	# Every non-empty subset, in the same binary order reflections_of counts them.
	for mask: int in range(1, 1 << planes.size()):
		var chosen: String = ""
		for i: int in planes.size():
			if (mask >> i) & 1 == 1:
				chosen += planes[i]
		out.append(twin_id(source_id, chosen))
	return out


## EVERY twin id of [param source_id] across any axis subset at all, whatever the document says.
##
## For DESTRUCTION, not creation: turning a plane off has to remove the visuals its twins left
## behind, and by then the document no longer names the planes they were made under.
static func all_twin_ids(source_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray([twin_id(source_id)])
	for mask: int in range(1, 1 << AXIS_ORDER.length()):
		var chosen: String = ""
		for i: int in AXIS_ORDER.length():
			if (mask >> i) & 1 == 1:
				chosen += str(AXIS_ORDER[i])
		out.append(twin_id(source_id, chosen))
	return out


## Twin id for a source part, reflected across [param axes].
##
## FORMAT: "<source_id>~m" for a document with ONE plane, and "<source_id>~m<axes>" for one with
## several - "p_0007~mxy". The bare form is kept deliberately: it is what every saved ship, every
## consumer and every test has always seen, and a document with one plane must not change because
## the field can now hold more (ADR 0043). Twin ids are DERIVED and never stored, so the longer
## form breaks no file.
static func twin_id(source_id: String, axes: String = "") -> String:
	return source_id + TWIN_SUFFIX + normalise_planes(axes)


static func is_twin_id(id: String) -> bool:
	var at: int = id.rfind(TWIN_SUFFIX)
	if at <= 0:
		return false
	# Whatever follows the marker has to be axis letters and nothing else, or this is a part whose
	# own id merely happens to contain the marker.
	for letter: String in id.substr(at + TWIN_SUFFIX.length()):
		if not PLANES.has(letter):
			return false
	return true


## Which axes a twin id is reflected across: "" for the bare single-plane form.
static func axes_of_twin(twin: String) -> String:
	if not is_twin_id(twin):
		return ""
	return twin.substr(twin.rfind(TWIN_SUFFIX) + TWIN_SUFFIX.length())


## Source part id for a twin. Returns [param twin] unchanged when it is not a twin id, so callers
## can pass any id without testing first.
static func source_of_twin(twin: String) -> String:
	if not is_twin_id(twin):
		return twin
	return twin.substr(0, twin.rfind(TWIN_SUFFIX))


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

class_name ShipJoint
extends RefCounted

## One joint record — SPEC section 7, API_CONTRACT section 10.
##
## A joint is keyed over an [b]unordered pair[/b] of parts, not over a parent/child edge:
## siblings overlap too. [member a] is always lexicographically less than [member b] so
## that one pair of parts can only ever produce one joint key
## (see [method ShipDoc.joint_key_for]).
##
## Phase 1 ships the full authoring UI and stores everything below, but the SDF partition
## geometry is not implemented, so the Phase 1 bake produces the all-open "studio" hull
## with no walls. That is by design (SPEC section 7) and must not be read as a bug.

const MODE_OPEN: String = "open"
const MODE_HATCHED: String = "hatched"
const MODE_SEALED: String = "sealed"
## A plain opening in the seam wall with no hatch hardware - the "internal door" between two
## rooms that share a bulkhead. Sized by ShipConfig.doorway_width_m / doorway_height_m, cut
## centred on the seam like a hatch (ADR 0008). ADDITIVE to API_CONTRACT section 10's
## vocabulary; recorded in FOLLOWUPS F19.
const MODE_DOORWAY: String = "doorway"

const VALID_MODES: Array = [MODE_OPEN, MODE_HATCHED, MODE_SEALED, MODE_DOORWAY]

## SEAM STYLES (ADR 0009) - which surface the two solids are resolved against where they meet.
## The MODE above says whether the seam is open, walled or doored; the STYLE says what SHAPE the
## seam is. The author's three: "parent indents child > child indents parent > and flat plane at
## intersection".
##
## [constant SEAM_FLAT] cuts both solids on the flat plane through the attach anchor - the
## original ADR 0008 behaviour and still the default. [constant SEAM_PARENT] follows the PARENT's
## surface, so the child ends up with a dent shaped like the parent and the overlap volume stays
## with the parent. [constant SEAM_CHILD] follows the CHILD's surface, so the parent ends up with
## a socket and the overlap stays with the child. All three are exact partitions of the same
## union: no volume is counted twice or lost, whichever is chosen.
## A seam style is TWO INDEPENDENT CHOICES, and the id spells both (ADR 0013).
##
##   WHICH SOLID INDENTS THE OTHER - `small_` or `big_`, by VOLUME. "i think its more appropriate
##   to classify it as big indents small, or small indents big." Volume, not the attach tree: a
##   small part is perfectly able to be the parent of a large one, and which one presses into
##   which is a fact about the shapes rather than about who was placed first.
##
##   WHAT THE LINKAGE SURFACE IS - `flat_insert`, `flat_cutoff` or `native`:
##     flat_insert  a flat plane, and only the indenting solid's own cross-section is let in, so
##                  the other keeps its shape everywhere the joint does not reach.
##     flat_cutoff  the same flat plane, taken straight through - a facet across the whole solid.
##     native       no flattening at all: the interface follows the indenting solid's real
##                  surface, which is an exact fit on any shape.
##
## The plane, for both flat surfaces, is the one through the extreme point where the two surfaces
## ACTUALLY CROSS - deepest when the small indents the big, outermost when the big indents the
## small (ADR 0012). Never the tangent at the attach anchor.
const SEAM_SMALL_FLAT_INSERT: String = "small_flat_insert"
const SEAM_SMALL_FLAT_CUTOFF: String = "small_flat_cutoff"
const SEAM_SMALL_NATIVE: String = "small_native"
const SEAM_BIG_FLAT_INSERT: String = "big_flat_insert"
const SEAM_BIG_FLAT_CUTOFF: String = "big_flat_cutoff"
const SEAM_BIG_NATIVE: String = "big_native"

## The two axes, for a caller that wants to offer them as toggles rather than as six names.
const INDENT_SMALL: String = "small"
const INDENT_BIG: String = "big"
const SURFACE_FLAT_INSERT: String = "flat_insert"
const SURFACE_FLAT_CUTOFF: String = "flat_cutoff"
const SURFACE_NATIVE: String = "native"

## RETIRED(ADR 0013, 2026-09-04): the six ids of ADR 0012 - `flat_in`, `flat_out`, `slice_in`,
## `slice_out`, `parent`, `child` - which named the same six behaviours by two DIFFERENT and
## unrelated schemes: two of them by the attach tree and four by a plane position. The behaviours
## are unchanged; only the naming and the input scheme are, and every old string still LOADS.
## RETIRED(ADR 0012, 2026-09-03e): SEAM_FLAT = "flat", the tangent cut at the attach anchor.
const SEAM_FLAT: String = SEAM_SMALL_FLAT_INSERT
const LEGACY_SEAM_STYLES: Dictionary = {
	"flat": SEAM_SMALL_FLAT_INSERT,
	"flat_in": SEAM_SMALL_FLAT_INSERT,
	"slice_in": SEAM_SMALL_FLAT_CUTOFF,
	"child": SEAM_SMALL_NATIVE,
	"flat_out": SEAM_BIG_FLAT_INSERT,
	"slice_out": SEAM_BIG_FLAT_CUTOFF,
	"parent": SEAM_BIG_NATIVE,
}

const VALID_SEAM_STYLES: Array = [
	SEAM_SMALL_FLAT_INSERT,
	SEAM_SMALL_FLAT_CUTOFF,
	SEAM_SMALL_NATIVE,
	SEAM_BIG_FLAT_INSERT,
	SEAM_BIG_FLAT_CUTOFF,
	SEAM_BIG_NATIVE,
]

## Stable id, e.g. "j_0003". Assigned by [method ShipDoc.new_joint_id].
var id: String = ""

## First part id. Always lexicographically less than or equal to [member b].
var a: String = ""

## Second part id.
var b: String = ""

## [constant MODE_OPEN], [constant MODE_HATCHED] or [constant MODE_SEALED].
var mode: String = MODE_OPEN

## Hatch family id. Only meaningful when [member mode] is [constant MODE_HATCHED].
var hatch_family: String = ""

## Hatch manufacturer id.
var hatch_manufacturer: String = ""

## Hatch shape parameters, same contract as [member ShipPart.params].
var hatch_params: Dictionary = {}

## One of [constant SEAM_FLAT], [constant SEAM_PARENT], [constant SEAM_CHILD] - see the SEAM
## STYLES block above.
var seam_style: String = SEAM_FLAT

## Builds a joint from its serialized form. [param joint_id] comes from the dictionary
## key in [member ShipDoc.joints].
##
## The pair is normalised on the way in: a file that stored (b, a) loads as (a, b), which
## keeps the unordered-pair invariant true for every joint in memory regardless of how the
## file was written. An unrecognised mode falls back to [constant MODE_OPEN].
@warning_ignore("shadowed_variable")
static func from_dict(id: String, d: Dictionary) -> ShipJoint:
	var j: ShipJoint = ShipJoint.new()
	j.id = id
	var raw_a: String = _as_string(d.get("a", null), "")
	var raw_b: String = _as_string(d.get("b", null), "")
	if raw_a <= raw_b:
		j.a = raw_a
		j.b = raw_b
	else:
		j.a = raw_b
		j.b = raw_a
	j.mode = _as_mode(d.get("mode", null))
	j.seam_style = _as_seam_style(d.get("seam", d.get("seam_style", null)))

	var hatch: Dictionary = _as_dict(d.get("hatch", null))
	j.hatch_family = _as_string(_pick(hatch, "family", d, "hatch_family"), "")
	j.hatch_manufacturer = _as_string(_pick(hatch, "manufacturer", d, "hatch_manufacturer"), "")
	j.hatch_params = _as_dict(_pick(hatch, "params", d, "hatch_params"))
	return j


## The serialized form, matching SPEC section 5.1. [member id] is the dictionary key in
## [member ShipDoc.joints] and is deliberately absent.
##
## [member seam_style] IS WRITTEN ONLY WHEN IT IS NOT THE DEFAULT. Every joint ever saved before
## ADR 0009 is flat, so emitting the key unconditionally would change the canonical form - and
## therefore [method ShipHash.doc_hash] - of every existing file for a field none of them uses.
## Omitting the default keeps those files hashing exactly as they did, which is why this costs no
## ruleset bump. Same technique the `role` default used (FOLLOWUPS F18).
func to_dict() -> Dictionary:
	var hatch: Dictionary = {
		"family": hatch_family,
		"manufacturer": hatch_manufacturer,
		"params": hatch_params.duplicate(true),
	}
	var out: Dictionary = {
		"a": a,
		"b": b,
		"mode": mode,
		"hatch": hatch,
	}
	if seam_style != SEAM_FLAT:
		out["seam"] = seam_style
	return out


# --- internals ---------------------------------------------------------------------


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


static func _as_mode(v: Variant) -> String:
	var s: String = _as_string(v, MODE_OPEN).to_lower()
	if VALID_MODES.has(s):
		return s
	return MODE_OPEN


## An unrecognised or absent style is FLAT, which is both the default and what every file
## written before ADR 0009 means by saying nothing.
## Which solid indents the other under [param style]: [constant INDENT_SMALL] or
## [constant INDENT_BIG].
static func indent_of(style: String) -> String:
	return INDENT_BIG if style.begins_with(INDENT_BIG + "_") else INDENT_SMALL


## The linkage surface [param style] asks for: one of the SURFACE_* constants.
static func surface_of(style: String) -> String:
	if style.ends_with(SURFACE_FLAT_CUTOFF):
		return SURFACE_FLAT_CUTOFF
	if style.ends_with(SURFACE_NATIVE):
		return SURFACE_NATIVE
	return SURFACE_FLAT_INSERT


## The style id for a pair of axis choices, which is how the two toggles become one stored value.
static func style_for_axes(indent: String, surface: String) -> String:
	var id: String = "%s_%s" % [indent, surface]
	return id if VALID_SEAM_STYLES.has(id) else SEAM_FLAT


static func _as_seam_style(v: Variant) -> String:
	var s: String = _as_string(v, SEAM_FLAT).to_lower()
	# Every id this project has ever written still loads. The behaviours never changed; the names
	# have twice, and a document is not the place to make a reader pay for that.
	if LEGACY_SEAM_STYLES.has(s):
		return LEGACY_SEAM_STYLES[s]
	if VALID_SEAM_STYLES.has(s):
		return s
	return SEAM_FLAT


static func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}

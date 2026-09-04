## ShipPaint - the paint rules as pure functions over a [ShipDoc] (API_CONTRACT_SPORE 10).
##
## [b]THIS IS THE VEHICLE/SHIP EDITOR'S PAINT MODEL, NOT THE CREATURE EDITOR'S.[/b] The
## creature editor paints procedurally over a whole creature - one style, projected across
## everything, with the player never choosing a surface. The vehicle, building and UFO
## editors do the opposite: the player clicks ONE region of ONE part and that region alone
## changes (SPORE_CLONE_SPEC section 6). Almost everything written about "Spore painting"
## describes the creature system; it is the wrong one and it is not implemented here.
##
## WHAT A REGION IS. Every family in `data/shapes/families.json` carries
## `"paint_regions": ["base", "coat", "detail"]`. Those ids are the keys of
## [member ShipPart.paint] and the values are exactly
## {"color": int (an INDEX into the active palette), "texture": String}. A colour is never
## a hex value here, which is the whole reason a budget alert can swap the 16-entry LUT and
## recolour every painted ship with it (SPEC section 11). A family that omits the key gets
## [constant DEFAULT_REGIONS].
##
## PLAN, THEN APPLY - AND WHY IT IS TWO STEPS. Every `plan_*` function is a pure read: it
## works out what the click WOULD do and returns it, touching nothing. [method apply_plan]
## is the only function in this file that writes to a document. The split exists because
## the edit protocol (`ShipBuilder.begin_edit()` / `commit_edit()`) owns every mutation -
## a caller that wants a hover preview, a status line, or an "n parts would change" count
## can ask for the plan without opening an edit, and the caller that really is editing
## wraps [b]only[/b] [method apply_plan] in begin/commit. Nothing here may be called
## between those two without going through [method apply_plan].
##
## A PLAN is { part_id: { region_id: {"color": int, "texture": String} } }. Entries are
## COMPLETE records, already merged against what the part carries, so applying a plan is a
## dumb overwrite of the named regions and every region the plan does not name is left
## exactly as the player left it.
##
## `core/` PURITY (AGENTS section 3): no Node, no SceneTree, no signals, no `res://`. The
## paint style pack is handed in as an already-parsed Dictionary - [ShipData] does not load
## `data/paint_styles.json`, so the harness reads it and passes it down.
class_name ShipPaint
extends RefCounted

## Which half of a brush a write touches. Bound to the sourced hotkeys `3` / `4` / `5`
## (SPORE_CLONE_SPEC section 2, "eyedropper: colour only / texture only / both"), and used
## for the paint direction too so a texture pass can be laid over a colour the player
## already chose.
enum Channel { COLOR, TEXTURE, BOTH }

## Region list for a family that does not author `paint_regions`. The order is load-bearing
## downstream: PaintMode's height-band hit test maps index 0 to the -Y (keel) end.
const DEFAULT_REGIONS: PackedStringArray = ["base", "coat", "detail"]

## Pack block names. `textures` is the shared finish vocabulary both style blocks reference
## by id and the only place a texture id is defined.
const BLOCK_COMPLETE: String = "complete"
const BLOCK_PARTIAL: String = "partial"
const BLOCK_TEXTURES: String = "textures"

## Keys inside a `complete` style entry.
const STYLE_COLORS: String = "colors"
const STYLE_TEXTURE: String = "texture"
## Key inside a `partial` style entry.
const STYLE_REGIONS: String = "regions"

## Family key holding the region ids.
const FAMILY_REGIONS: String = "paint_regions"

## Extra key on a [method resolve_part] record: the real [Color] the index resolves to.
const RESOLVED_RGB: String = "rgb"
## Extra key on a [method resolve_part] record: false when the region has never been painted.
const RESOLVED_PAINTED: String = "painted"

## [member ShipPart.paint] colour index meaning "never painted". Deliberately NOT 0 - index
## 0 is a real palette entry (deep ink) and a part painted deep ink must not read as blank.
const UNPAINTED: int = -1

## Keys a pack entry that is not a catalogue entry starts with; `_description` and friends.
const META_PREFIX: String = "_"

# ---------------------------------------------------------------- regions


## The family's paint regions, or [constant DEFAULT_REGIONS] when it authors none.
##
## Never returns empty: a family with an empty or malformed `paint_regions` array would
## otherwise be unpaintable with no error anywhere, which is exactly the silent failure
## AGENTS section 10b exists to prevent.
static func regions_for_family(data: ShipData, family_id: String) -> PackedStringArray:
	if data == null or family_id == "":
		return DEFAULT_REGIONS
	var raw: Variant = data.families.get(family_id, null)
	if not (raw is Dictionary):
		return DEFAULT_REGIONS
	var entry: Dictionary = raw
	var listed: Variant = entry.get(FAMILY_REGIONS, null)
	if not (listed is Array):
		return DEFAULT_REGIONS
	var arr: Array = listed
	var out: PackedStringArray = PackedStringArray()
	for item: Variant in arr:
		if item is String:
			var region: String = item
			if region != "" and not out.has(region):
				out.append(region)
	if out.is_empty():
		return DEFAULT_REGIONS
	return out


## The paint regions of one part, resolved through its family.
static func regions_for_part(doc: ShipDoc, data: ShipData, part_id: String) -> PackedStringArray:
	var part: ShipPart = _part(doc, part_id)
	if part == null:
		return DEFAULT_REGIONS
	return regions_for_family(data, part.family)


# ---------------------------------------------------------------- records


## One paint record in the pinned value shape. The only place this file builds one, so the
## shape API_CONTRACT_SPORE section 2 pins cannot drift key by key (FOLLOWUPS F0).
static func make_entry(color: int, texture: String) -> Dictionary:
	return {ShipPart.PAINT_COLOR: color, ShipPart.PAINT_TEXTURE: texture}


## What the eyedropper reads: the stored record for one region, or {} when that region has
## never been painted. Callers must treat {} as "nothing to pick up" rather than as black.
static func region_paint(doc: ShipDoc, part_id: String, region: String) -> Dictionary:
	var part: ShipPart = _part(doc, part_id)
	if part == null or region == "":
		return {}
	var raw: Variant = part.paint.get(region, null)
	if not (raw is Dictionary):
		return {}
	var stored: Dictionary = raw
	return make_entry(
		_as_int(stored.get(ShipPart.PAINT_COLOR, null), UNPAINTED),
		_as_string(stored.get(ShipPart.PAINT_TEXTURE, null))
	)


## Every region of a part, resolved to a real [Color] through [param palette].
##
## Returns region_id -> {"color": int, "texture": String, "rgb": Color, "painted": bool},
## covering EVERY region the family declares, painted or not, so a UI can render the full
## region list without asking a second question. [param fallback] is the colour an
## unpainted region reports - handed in rather than looked up, because `core/` may not know
## what a palette role means and nothing here is allowed to hardcode an index (SPEC 11).
static func resolve_part(
	doc: ShipDoc, data: ShipData, part_id: String, palette: PackedColorArray, fallback: Color
) -> Dictionary:
	var out: Dictionary = {}
	var regions: PackedStringArray = regions_for_part(doc, data, part_id)
	for region: String in regions:
		var stored: Dictionary = region_paint(doc, part_id, region)
		var index: int = _as_int(stored.get(ShipPart.PAINT_COLOR, null), UNPAINTED)
		var painted: bool = not stored.is_empty() and index != UNPAINTED
		var record: Dictionary = make_entry(
			index, _as_string(stored.get(ShipPart.PAINT_TEXTURE, null))
		)
		record[RESOLVED_RGB] = color_at(palette, index, fallback) if painted else fallback
		record[RESOLVED_PAINTED] = painted
		out[region] = record
	return out


## A palette index resolved to a [Color]. Out of range - including [constant UNPAINTED] -
## returns [param fallback] rather than clamping, because clamping would silently paint an
## out-of-range index as a real colour and hide the pack error that produced it.
static func color_at(palette: PackedColorArray, index: int, fallback: Color) -> Color:
	if index < 0 or index >= palette.size():
		return fallback
	return palette[index]


# ---------------------------------------------------------------- part sets


## Every part of [param family_id], in document order.
static func parts_of_family(doc: ShipDoc, family_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null or family_id == "":
		return out
	for pid: String in doc.part_order():
		var part: ShipPart = _part(doc, pid)
		if part != null and part.family == family_id:
			out.append(pid)
	return out


## Spore's "all IDENTICAL blocks" (hotkey `2`), as distinct from "all parts of the same
## family" (`Shift+Ctrl+LMB`, which is [method parts_of_family]).
##
## Two parts are identical when they came off the same catalogue entry - see
## [method part_signature] for why that is family plus manufacturer and nothing else.
static func identical_part_ids(doc: ShipDoc, part_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var source: ShipPart = _part(doc, part_id)
	if source == null:
		return out
	var want: String = part_signature(source)
	for pid: String in doc.part_order():
		var part: ShipPart = _part(doc, pid)
		if part != null and part_signature(part) == want:
			out.append(pid)
	return out


## The "same block" key: family plus manufacturer, and deliberately NOTHING else.
##
## Spore's identical-blocks pass compares CATALOGUE ENTRIES, and a block the player has
## stretched or morphed is still the same block. Our nearest equivalent of a catalogue
## entry is (family, manufacturer): `params` and `scale` are per-instance morphs - the
## direct analogue of Spore's morph handles - so folding them in would make two copies of
## one part stop being identical the moment one of them was resized, which is exactly the
## behaviour the hotkey exists to avoid.
static func part_signature(part: ShipPart) -> String:
	if part == null:
		return ""
	return part.family + "|" + part.manufacturer


# ---------------------------------------------------------------- plans


## LMB: the clicked region on the clicked part.
static func plan_region(
	doc: ShipDoc, data: ShipData, part_id: String, region: String, brush: Dictionary, channel: int
) -> Dictionary:
	var regions: PackedStringArray = regions_for_part(doc, data, part_id)
	if region == "" or not regions.has(region):
		return {}
	return _plan_for(doc, PackedStringArray([part_id]), PackedStringArray([region]), brush, channel)


## Shift+LMB: EVERY region on that part.
static func plan_part(
	doc: ShipDoc, data: ShipData, part_id: String, brush: Dictionary, channel: int
) -> Dictionary:
	var regions: PackedStringArray = regions_for_part(doc, data, part_id)
	return _plan_for(doc, PackedStringArray([part_id]), regions, brush, channel)


## Shift+Ctrl+LMB: that region on ALL parts of the same family.
##
## A family whose region list does not contain [param region] contributes nothing, which
## cannot happen while every family declares the same three regions but will the moment one
## does not - and quietly inventing the region on those parts would put a key in
## [member ShipPart.paint] that the family's own renderer never reads.
static func plan_family(
	doc: ShipDoc, data: ShipData, family_id: String, region: String, brush: Dictionary, channel: int
) -> Dictionary:
	var ids: PackedStringArray = parts_of_family(doc, family_id)
	return _plan_restricted(doc, data, ids, region, brush, channel)


## Hotkey `1`: the same region on ALL blocks, whatever family they are.
static func plan_all(
	doc: ShipDoc, data: ShipData, region: String, brush: Dictionary, channel: int
) -> Dictionary:
	if doc == null:
		return {}
	return _plan_restricted(doc, data, doc.part_order(), region, brush, channel)


## Hotkey `2`: the same region on all blocks IDENTICAL to this one.
static func plan_identical(
	doc: ShipDoc, data: ShipData, part_id: String, region: String, brush: Dictionary, channel: int
) -> Dictionary:
	var ids: PackedStringArray = identical_part_ids(doc, part_id)
	return _plan_restricted(doc, data, ids, region, brush, channel)


## A `complete` style from `data/paint_styles.json`, applied to one part.
##
## The pack's own description is the contract: a complete style "carries one ordered colour
## per paint region plus a single texture and leaves NO region untouched". So `colors[i]`
## goes to `regions[i]`, the single `texture` goes to every region, and every region is
## written. A short `colors` array repeats its last entry rather than leaving a region
## behind; a long one drops the extras. Both cases are pack errors the schema catches, and
## neither is worth refusing the whole style over at runtime.
static func plan_complete_style(
	doc: ShipDoc, data: ShipData, part_id: String, style: Dictionary
) -> Dictionary:
	var part: ShipPart = _part(doc, part_id)
	if part == null:
		return {}
	var regions: PackedStringArray = regions_for_part(doc, data, part_id)
	var colors: PackedInt32Array = _as_int_array(style.get(STYLE_COLORS, null))
	if colors.is_empty() or regions.is_empty():
		return {}
	var texture: String = _as_string(style.get(STYLE_TEXTURE, null))
	var painted: Dictionary = {}
	var count: int = regions.size()
	for i: int in count:
		var index: int = colors[mini(i, colors.size() - 1)]
		painted[regions[i]] = make_entry(index, texture)
	return {part_id: painted}


## A `partial` style from `data/paint_styles.json`, applied to one part.
##
## Partial styles "name only the regions they care about and leave every other region
## exactly as the player left it", so a trim pack layers over a complete style instead of
## replacing it. Two consequences, both taken straight from the authored pack:
##
##   - a named region the part's family does not declare is SKIPPED, not invented;
##   - an empty `texture` inside a named region means "no texture change" and the part's
##     existing texture is carried through. `teal_wash` says so in prose - "mid-teal on the
##     body with no texture change" - and it is the only reading under which a two-region
##     tint does not silently strip the finish it was layered onto.
static func plan_partial_style(
	doc: ShipDoc, data: ShipData, part_id: String, style: Dictionary
) -> Dictionary:
	var part: ShipPart = _part(doc, part_id)
	if part == null:
		return {}
	var raw: Variant = style.get(STYLE_REGIONS, null)
	if not (raw is Dictionary):
		return {}
	var wanted: Dictionary = raw
	var regions: PackedStringArray = regions_for_part(doc, data, part_id)
	var painted: Dictionary = {}
	for key: Variant in wanted:
		var region: String = str(key)
		if not regions.has(region):
			continue
		var value: Variant = wanted[key]
		if not (value is Dictionary):
			continue
		var record: Dictionary = value
		var existing: Dictionary = region_paint(doc, part_id, region)
		var texture: String = _as_string(record.get(ShipPart.PAINT_TEXTURE, null))
		if texture == "":
			texture = _as_string(existing.get(ShipPart.PAINT_TEXTURE, null))
		painted[region] = make_entry(
			_as_int(record.get(ShipPart.PAINT_COLOR, null), UNPAINTED), texture
		)
	if painted.is_empty():
		return {}
	return {part_id: painted}


# ---------------------------------------------------------------- apply


## The ONLY function here that writes. Merges [param plan] into the named parts and returns
## the ids that actually changed - a re-paint with the colour already there returns empty,
## so a caller can skip a pointless undo entry.
##
## [b]Callers must be inside `begin_edit()` / `commit_edit()`.[/b] This function cannot
## enforce that from `core/` (it knows nothing about the harness), so it is a contract on
## the caller and the reason every other function in this file is a pure read.
static func apply_plan(doc: ShipDoc, plan: Dictionary) -> PackedStringArray:
	var changed: PackedStringArray = PackedStringArray()
	if doc == null:
		return changed
	for key: Variant in plan:
		var part_id: String = str(key)
		var part: ShipPart = _part(doc, part_id)
		if part == null:
			continue
		var value: Variant = plan[key]
		if not (value is Dictionary):
			continue
		if _write_regions(part, value):
			changed.append(part_id)
	return changed


# ---------------------------------------------------------------- pack readers


## Catalogue ids inside one block of a parsed `data/paint_styles.json`, sorted, with the
## pack's `_description` and any other underscore-prefixed metadata key excluded.
static func catalogue_ids(pack: Dictionary, block: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var raw: Variant = pack.get(block, null)
	if not (raw is Dictionary):
		return out
	var entries: Dictionary = raw
	for key: Variant in entries:
		var id: String = str(key)
		if id.begins_with(META_PREFIX):
			continue
		if entries[key] is Dictionary:
			out.append(id)
	out.sort()
	return out


## One catalogue entry, or {} when the block or the id is absent.
##
## Returned BY REFERENCE - a [Dictionary] is a reference type in Godot, so this is the
## pack's own entry and not a copy. Treat it as read-only. Nothing here duplicates it
## because every caller only reads, and a per-part copy inside a spread loop would be pure
## waste; the plans built from it are always fresh dictionaries from [method make_entry],
## so no pack object ever reaches a [ShipPart].
static func catalogue_entry(pack: Dictionary, block: String, id: String) -> Dictionary:
	var raw: Variant = pack.get(block, null)
	if not (raw is Dictionary):
		return {}
	var entries: Dictionary = raw
	var entry: Variant = entries.get(id, null)
	if entry is Dictionary:
		var out: Dictionary = entry
		return out
	return {}


# ---------------------------------------------------------------- internals


## Plan one region across a set of parts, dropping every part whose family does not declare
## that region.
static func _plan_restricted(
	doc: ShipDoc,
	data: ShipData,
	ids: PackedStringArray,
	region: String,
	brush: Dictionary,
	channel: int
) -> Dictionary:
	if region == "":
		return {}
	var eligible: PackedStringArray = PackedStringArray()
	for pid: String in ids:
		if regions_for_part(doc, data, pid).has(region):
			eligible.append(pid)
	return _plan_for(doc, eligible, PackedStringArray([region]), brush, channel)


## The one place a plan is built: every (part, region) pair gets a COMPLETE record, merged
## against what the part already carries so a colour-only pass keeps the texture under it.
static func _plan_for(
	doc: ShipDoc,
	ids: PackedStringArray,
	regions: PackedStringArray,
	brush: Dictionary,
	channel: int
) -> Dictionary:
	var out: Dictionary = {}
	if ids.is_empty() or regions.is_empty():
		return out
	var color: int = _as_int(brush.get(ShipPart.PAINT_COLOR, null), UNPAINTED)
	var texture: String = _as_string(brush.get(ShipPart.PAINT_TEXTURE, null))
	for pid: String in ids:
		if _part(doc, pid) == null:
			continue
		var painted: Dictionary = {}
		for region: String in regions:
			var existing: Dictionary = region_paint(doc, pid, region)
			painted[region] = _merge(existing, color, texture, channel)
		if not painted.is_empty():
			out[pid] = painted
	return out


## Brush over stored, honouring the channel. A [constant Channel.COLOR] pass never touches
## the texture and a [constant Channel.TEXTURE] pass never touches the colour, which is
## what makes the `3` / `4` / `5` eyedropper modes symmetrical with the paint direction.
static func _merge(existing: Dictionary, color: int, texture: String, channel: int) -> Dictionary:
	var out_color: int = _as_int(existing.get(ShipPart.PAINT_COLOR, null), UNPAINTED)
	var out_texture: String = _as_string(existing.get(ShipPart.PAINT_TEXTURE, null))
	if channel == Channel.COLOR or channel == Channel.BOTH:
		out_color = color
	if channel == Channel.TEXTURE or channel == Channel.BOTH:
		out_texture = texture
	return make_entry(out_color, out_texture)


## Write one part's regions. True when anything actually moved.
static func _write_regions(part: ShipPart, painted: Dictionary) -> bool:
	var dirty: bool = false
	for key: Variant in painted:
		var region: String = str(key)
		var value: Variant = painted[key]
		if not (value is Dictionary):
			continue
		var record: Dictionary = value
		var next: Dictionary = make_entry(
			_as_int(record.get(ShipPart.PAINT_COLOR, null), UNPAINTED),
			_as_string(record.get(ShipPart.PAINT_TEXTURE, null))
		)
		var current: Variant = part.paint.get(region, null)
		if current is Dictionary:
			var stored: Dictionary = current
			var same_color: bool = (
				_as_int(stored.get(ShipPart.PAINT_COLOR, null), UNPAINTED)
				== int(next[ShipPart.PAINT_COLOR])
			)
			var same_texture: bool = (
				_as_string(stored.get(ShipPart.PAINT_TEXTURE, null))
				== str(next[ShipPart.PAINT_TEXTURE])
			)
			if same_color and same_texture:
				continue
		part.paint[region] = next
		dirty = true
	return dirty


static func _part(doc: ShipDoc, part_id: String) -> ShipPart:
	if doc == null or part_id == "":
		return null
	var raw: Variant = doc.parts.get(part_id, null)
	if raw is ShipPart:
		var part: ShipPart = raw
		return part
	return null


## Colour indices are stored as ints but a hand-edited pack may carry 4.0. Rounded rather
## than truncated so 3.9999 does not become 3 (see [member ShipPart.paint] on why the
## document hash cares).
static func _as_int(v: Variant, def: int) -> int:
	if v is int:
		var i: int = v
		return i
	if v is float:
		var f: float = v
		if is_finite(f):
			return int(round(f))
	return def


static func _as_string(v: Variant) -> String:
	if v is String:
		var s: String = v
		return s
	return ""


static func _as_int_array(v: Variant) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if not (v is Array):
		return out
	var arr: Array = v
	for item: Variant in arr:
		out.append(_as_int(item, UNPAINTED))
	return out

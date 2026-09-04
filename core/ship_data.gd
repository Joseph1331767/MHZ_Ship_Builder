class_name ShipData
extends RefCounted

## The loaded data packs — SPEC section 5.3, API_CONTRACT section 4.
##
## [b]The only class in [code]core/[/code] permitted to touch [code]res://[/code].[/b]
## Everything else takes a [ShipData] as an argument, which is what keeps the rest of
## [code]core/[/code] testable with hand-built dictionaries and portable into
## MHZ_Origins with nothing but its data directory.
##
## Loading never pushes an error and never crashes. Problems accumulate in
## [member load_errors] and [method load_all] returns false, because a missing pack is
## something a tool should report in one readable block, not something that should take
## the process down mid-parse.
##
## Pack entries are stored raw. [ShapeGen] owns their interpretation; this class only
## finds them, keys them by id and reports what it could not read.

const FILE_FAMILIES: String = "shapes/families.json"
const FILE_MANUFACTURERS: String = "shapes/manufacturers.json"
const FILE_HATCHES: String = "shapes/hatches.json"
const FILE_PALETTE: String = "palette.json"
const FILE_TUNING: String = "tuning.json"
const FILE_TEMPLATES: String = "templates.json"

## Top-level keys a pack file may use to wrap its entries, tried in this order before
## falling back to treating the file itself as an id -> entry map.
const SECTION_KEYS: Array = ["entries", "items"]

## Top-level keys that are pack metadata rather than entries, skipped by the flat
## fallback so that a `"version": 1` line never becomes a shape family.
const META_KEYS: Array = [
	"$schema",
	"schema",
	"format",
	"version",
	"ruleset_version",
	"description",
	"notes",
	"comment",
	"_comment",
	"meta",
]

## Keys under a manufacturer entry that may carry its per-family narrowing. Whichever is
## present is read as a set of family ids; results are filtered against the families that
## actually loaded, so a manufacturer whose "ranges" turn out to be parameter names
## rather than family names degrades to "applies to every family" instead of inventing
## families that do not exist.
const FAMILY_LINK_KEYS: Array = [
	"families",
	"family_overrides",
	"per_family",
	"family_ranges",
	"overrides",
	"supports",
	"family_ids",
	"ranges",
]

## family_id -> Dictionary (raw pack entry).
var families: Dictionary = {}

## manufacturer_id -> Dictionary.
var manufacturers: Dictionary = {}

## hatch_id -> Dictionary. Authored in Phase 1, geometry unbuilt (SPEC section 7).
var hatches: Dictionary = {}

## The raw palette pack: the 16-entry base ramp plus one alert palette per budget.
var palette: Dictionary = {}

## Dev levers from `data/tuning.json`, or the shipped defaults when it is unreadable.
## The stock ship templates pack, whole - arrangements, elements and molecules. Kept raw rather
## than flattened through _load_pack(), because it carries three sections and ShipTemplates is
## the class that knows what they mean. Empty is not an error: a pack with no templates costs a
## palette section, not a builder.
var templates: Dictionary = {}

var config: ShipConfig = ShipConfig.defaults()

## Everything that went wrong during the last [method load_all], in the order it was
## found. Empty exactly when that call returned true.
var load_errors: PackedStringArray = PackedStringArray()


## Loads every pack under [param base_path]. Returns true only when nothing went wrong.
##
## Always clears and reloads all five packs, so calling it twice is a full reload rather
## than a merge. On any failure the affected pack is left empty and [member config] keeps
## the shipped defaults — a builder with no data is inert, not broken.
func load_all(base_path: String = "res://data") -> bool:
	families = {}
	manufacturers = {}
	hatches = {}
	palette = {}
	templates = {}
	config = ShipConfig.defaults()
	load_errors = PackedStringArray()

	var families_path: String = base_path.path_join(FILE_FAMILIES)
	var manufacturers_path: String = base_path.path_join(FILE_MANUFACTURERS)
	var hatches_path: String = base_path.path_join(FILE_HATCHES)
	var palette_path: String = base_path.path_join(FILE_PALETTE)
	var tuning_path: String = base_path.path_join(FILE_TUNING)
	var templates_path: String = base_path.path_join(FILE_TEMPLATES)

	families = _load_pack(families_path, "families")
	manufacturers = _load_pack(manufacturers_path, "manufacturers")
	hatches = _load_pack(hatches_path, "hatches")

	var raw_palette: Variant = _read_json(palette_path)
	if raw_palette is Dictionary:
		var pd: Dictionary = raw_palette
		palette = pd.duplicate(true)
	elif raw_palette != null:
		load_errors.append("%s: expected a JSON object at the top level" % palette_path)

	var raw_templates: Variant = _read_json(templates_path)
	if raw_templates is Dictionary:
		var tp: Dictionary = raw_templates
		templates = tp.duplicate(true)
	elif raw_templates != null:
		load_errors.append("%s: expected a JSON object at the top level" % templates_path)

	var raw_tuning: Variant = _read_json(tuning_path)
	if raw_tuning is Dictionary:
		var td: Dictionary = raw_tuning
		config = ShipConfig.from_dict(td)
	elif raw_tuning != null:
		load_errors.append("%s: expected a JSON object at the top level" % tuning_path)

	if families.is_empty():
		load_errors.append("no shape families loaded from " + families_path)
	if manufacturers.is_empty():
		load_errors.append("no manufacturers loaded from " + manufacturers_path)
	if palette.is_empty():
		load_errors.append("no palette loaded from " + palette_path)

	return load_errors.is_empty()


## Every loaded family id, sorted. Sorted rather than insertion-ordered so a palette
## panel and a headless report list them the same way.
func family_ids() -> PackedStringArray:
	return _sorted_ids(families)


## Every loaded manufacturer id, sorted.
func manufacturer_ids() -> PackedStringArray:
	return _sorted_ids(manufacturers)


## The manufacturers that offer [param family_id], sorted.
##
## A manufacturer that declares no family narrowing applies to every family — that is the
## useful default for an author adding a new family, who should not have to revisit every
## manufacturer entry before the family becomes selectable. Returns empty for a family
## that is not loaded at all.
func manufacturers_for(family_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if not has_family(family_id):
		return out
	for key: Variant in manufacturers:
		var value: Variant = manufacturers[key]
		if not (value is Dictionary):
			continue
		var entry: Dictionary = value
		var declared: PackedStringArray = _manufacturer_families(entry)
		if declared.is_empty() or declared.has(family_id):
			out.append(str(key))
	out.sort()
	return out


## True when [param family_id] is present in the loaded family pack.
func has_family(family_id: String) -> bool:
	return families.has(family_id)


# --- internals ---------------------------------------------------------------------


## Reads one pack file into an id -> entry dictionary, accepting three shapes:
## a wrapper object (`{"families": {...}}` or `{"entries": {...}}`), an array of entries
## each carrying an "id", or the file itself as a bare id -> entry map.
func _load_pack(path: String, section: String) -> Dictionary:
	var raw: Variant = _read_json(path)
	if raw is Dictionary:
		var rd: Dictionary = raw
		return _extract_entries(rd, section, path)
	if raw is Array:
		var ra: Array = raw
		return _entries_from_array(ra, path)
	if raw != null:
		load_errors.append("%s: expected a JSON object or array at the top level" % path)
	return {}


func _extract_entries(raw: Dictionary, section: String, path: String) -> Dictionary:
	var wrappers: Array = [section]
	wrappers.append_array(SECTION_KEYS)
	var wrapper_count: int = wrappers.size()
	for i: int in wrapper_count:
		var key: String = str(wrappers[i])
		if not raw.has(key):
			continue
		var value: Variant = raw[key]
		if value is Dictionary:
			var vd: Dictionary = value
			return vd.duplicate(true)
		if value is Array:
			var va: Array = value
			return _entries_from_array(va, path)
	return _entries_from_flat(raw)


func _entries_from_array(arr: Array, path: String) -> Dictionary:
	var out: Dictionary = {}
	var n: int = arr.size()
	for i: int in n:
		var item: Variant = arr[i]
		if not (item is Dictionary):
			load_errors.append("%s: entry %d is not an object" % [path, i])
			continue
		var entry: Dictionary = item
		var entry_id: String = str(entry.get("id", ""))
		if entry_id.is_empty():
			load_errors.append('%s: entry %d has no "id"' % [path, i])
			continue
		if out.has(entry_id):
			load_errors.append('%s: duplicate id "%s"' % [path, entry_id])
			continue
		out[entry_id] = entry.duplicate(true)
	return out


static func _entries_from_flat(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in raw:
		var name: String = str(key)
		if META_KEYS.has(name):
			continue
		var value: Variant = raw[key]
		if value is Dictionary:
			var vd: Dictionary = value
			out[name] = vd.duplicate(true)
	return out


## The family ids a manufacturer entry declares, filtered to families that actually
## loaded. Empty means "no declaration we can trust" and is read as "all families".
func _manufacturer_families(entry: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var key_count: int = FAMILY_LINK_KEYS.size()
	for i: int in key_count:
		var key: String = str(FAMILY_LINK_KEYS[i])
		if not entry.has(key):
			continue
		var value: Variant = entry[key]
		if value is Dictionary:
			var vd: Dictionary = value
			for sub: Variant in vd:
				_append_known_family(out, str(sub))
		elif value is PackedStringArray:
			var vp: PackedStringArray = value
			var vp_count: int = vp.size()
			for j: int in vp_count:
				_append_known_family(out, vp[j])
		elif value is Array:
			var va: Array = value
			var va_count: int = va.size()
			for j: int in va_count:
				_append_known_family(out, str(va[j]))
	out.sort()
	return out


func _append_known_family(out: PackedStringArray, candidate: String) -> void:
	if families.has(candidate) and not out.has(candidate):
		out.append(candidate)


## Reads and parses one JSON file. Returns null on any problem, having recorded why.
func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		load_errors.append("missing data file: " + path)
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		load_errors.append("cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return null
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		load_errors.append(_parse_error_message(path, text))
		return null
	return parsed


## Re-parses through a [JSON] instance purely to recover a line number for the message.
## Only ever runs on the failure path, where being slow does not matter and being
## specific does — "line 41: Expected ','" is fixable, "parse failed" is not.
static func _parse_error_message(path: String, text: String) -> String:
	var probe: JSON = JSON.new()
	var err: int = probe.parse(text)
	if err != OK:
		return (
			"%s: JSON parse error on line %d: %s"
			% [path, probe.get_error_line(), probe.get_error_message()]
		)
	return "%s: file parsed to null" % path


static func _sorted_ids(d: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: Variant in d:
		out.append(str(key))
	out.sort()
	return out

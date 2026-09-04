extends SceneTree

## Validates data/ against data/schema/*.schema.json, checks manufacturer -> family
## cross-references,
## and fails any catalogue entry with a missing/placeholder description.
##
##   & $env:GODOT_BIN --headless --path . -s res://tools/ship_validate_data.gd
##   ./tools/ship_run.ps1 res://tools/ship_validate_data.gd     (preferred - AGENTS §8a)
##
## A data/ change that does not pass this is not finished (AGENTS §8, point 4).
##
## Two independent passes:
##   1. ShipData.load_all() - the same loader the game itself uses. Any load_errors
##      entry is a failure.
##   2. Direct JSON reads of every data/ pack, checked against a matching
##      data/schema/*.schema.json when
##      one exists.
##
## The schema check is a working SUBSET of JSON Schema 2020-12, sized to what
## `data/schema/families.schema.json` and `data/schema/manufacturers.schema.json` actually use:
## type, required, properties, additionalProperties (bool OR schema), propertyNames
## (recurses through
## the full validator, so a pattern-based OR an enum-based propertyNames schema both work),
## items, enum, minimum/maximum/exclusiveMinimum/exclusiveMaximum, minLength, minItems/maxItems,
## minProperties/maxProperties, uniqueItems, and `$ref`/`$defs` resolution (internal refs only,
## `#/$defs/<name>` or any JSON-pointer path under the same document - no external `$ref`). That
## last one matters more than it looks: both real schemas define every reusable shape once under
## `$defs` and reference it everywhere via `$ref`, so a validator that ignores `$ref` does not fail
## loudly - it just stops checking anything past the first `$ref` it meets, silently.
##
## A pack with no matching schema file only WARNS - schemas are being authored in parallel with the
## packs themselves (AGENTS §9) and their absence must not block every other check in this tool.
##
## THE CROSS-REFERENCE CHECKS BELOW ARE THE REASON THIS FILE EXISTS. Quoting
## `manufacturers.schema.json`'s own description: this tool "additionally checks that every
## 'families' key resolves to a real family id and that every narrowed param key and disabled op
## exists on that family - checks a standalone JSON Schema cannot express." Three checks, all
## reading `data/shapes/manufacturers.json`'s `<manufacturer>.families.<family_id>` block:
##   1. every referenced family id exists in `data/shapes/families.json`.
##   2. every key under that block's `params` exists in the family's OWN authored `params` (a
##      family-specific check: `param_key` is a shared enum across all families, but not every
##      family defines every key - e.g. `sphere_pod` has no `round`).
##   3. every entry in that block's `ops_disabled` is one of the family's OWN authored `ops` (same
##      reasoning: `op_name` is shared, but a manufacturer cannot disable an op a family never had).
## `_family_block_for_manufacturer()` reads the `families` key primarily (per schema); it also
## tolerates a flat top-level shape as a defensive fallback in case a future pack shape moves the
## key, and reports UNCHECKED (a warning, never a silent pass) when neither shape is found.
##
## THE ASSUMED description LOCATION: every family/manufacturer/hatch entry is a
## Dictionary carrying a
## top-level "description" key. Confirmed against the real packs, and also schema-enforced
## (`minLength: 20`) - this check is deliberately independent of that schema rule so it still runs
## when a schema file is missing, and it additionally rejects specific placeholder PHRASES
## (`_BANNED_PHRASES`) that a bare length check would happily pass ("This is a TODO for later.").

const _BANNED_PHRASES: PackedStringArray = [
	"todo", "tbd", "lorem ipsum", "placeholder", "no description",
	"fill me in", "fill this in", "description goes here", "xxx",
]

const _PACKS: Array[Dictionary] = [
	{"path": "res://data/shapes/families.json", "schema": "families"},
	{"path": "res://data/shapes/manufacturers.json", "schema": "manufacturers"},
	{"path": "res://data/shapes/hatches.json", "schema": "hatches"},
	{"path": "res://data/palette.json", "schema": "palette"},
	{"path": "res://data/tuning.json", "schema": "tuning"},
	# paint_styles.json shipped with a schema and was never listed here, so the one pack
	# PaintPanel reads was the one pack never checked (FOLLOWUPS F10).
	{"path": "res://data/paint_styles.json", "schema": "paint_styles"},
	{"path": "res://data/templates.json", "schema": "templates"},
]

var _errors: PackedStringArray = []
var _warnings: PackedStringArray = []


func _init() -> void:
	print("=== MHZ Ship Builder data validator ===")

	var data := ShipData.new()
	var loaded := data.load_all()
	for e: String in data.load_errors:
		_errors.append("load: %s" % e)
	if not loaded:
		_finish()
		return

	print("  loaded: %d families, %d manufacturers, %d hatch families"
		% [data.families.size(), data.manufacturers.size(), data.hatches.size()])

	_check_descriptions(data)
	_check_family_manufacturer_crossrefs(data)
	_check_all_schemas()

	_finish()


# ------------------------------------------------------------------ descriptions (AGENTS §10b) --

func _check_descriptions(data: ShipData) -> void:
	var checked := 0
	checked += _check_description_block(data.families, "family")
	checked += _check_description_block(data.manufacturers, "manufacturer")
	checked += _check_description_block(data.hatches, "hatch")
	print("  descriptions: %d entries checked" % checked)


func _check_description_block(block: Dictionary, kind: String) -> int:
	for id: Variant in block.keys():
		var entry: Dictionary = _as_dict(block[id])
		var desc := String(entry.get("description", ""))
		if _is_placeholder_description(desc):
			var shown := "empty" if desc.strip_edges() == "" else "\"%s\"" % desc
			_errors.append("%s '%s' has no usable description (%s)" % [kind, String(id), shown])
	return block.size()


func _is_placeholder_description(desc: String) -> bool:
	var trimmed := desc.strip_edges()
	if trimmed.length() < 20:
		return true
	var lowered := trimmed.to_lower()
	for phrase: String in _BANNED_PHRASES:
		if lowered.find(phrase) != -1:
			return true
	return false


# --------------------------------------------------------- manufacturer -> family cross-refs --

func _check_family_manufacturer_crossrefs(data: ShipData) -> void:
	var checked := 0
	var unchecked := 0
	for mid: Variant in data.manufacturers.keys():
		var manu_id := String(mid)
		var manu: Dictionary = _as_dict(data.manufacturers[mid])
		if manu.has("families") and not (manu["families"] is Dictionary):
			_errors.append("manufacturer '%s' has a 'families' key that is not an object" % manu_id)
			continue
		var family_block := _family_block_for_manufacturer(manu)
		if family_block.is_empty():
			_warnings.append(
				(
					"manufacturer '%s' - no per-family narrowing found (declares zero"
					+ " families, or an unrecognised shape); cross-references UNCHECKED"
				)
				% manu_id
			)
			unchecked += 1
			continue
		for fid: Variant in family_block.keys():
			var family_id := String(fid)
			checked += 1
			if not data.has_family(family_id):
				_errors.append("manufacturer '%s' references unknown family '%s'" % [manu_id, family_id])
				continue
			var narrowing: Dictionary = _as_dict(family_block[fid])
			var family: Dictionary = _as_dict(data.families[family_id])

			var family_params := _family_param_names(family)
			var narrowed_params: Dictionary = _as_dict(narrowing.get("params", {}))
			if not family_params.is_empty():
				for pid: Variant in narrowed_params.keys():
					var pname := String(pid)
					if not family_params.has(pname):
						_errors.append(
							"manufacturer '%s' narrows param '%s' on family '%s', which that family does not define"
							% [manu_id, pname, family_id])

			var family_ops := _family_ops_names(family)
			for op_v: Variant in _as_array(narrowing.get("ops_disabled", [])):
				var op_name := String(op_v)
				if not family_ops.has(op_name):
					_errors.append(
						"manufacturer '%s' disables op '%s' on family '%s', which that family does not offer"
						% [manu_id, op_name, family_id])
	print(
		(
			"  cross-refs: %d manufacturer/family pairs checked, %d manufacturers"
			+ " unchecked (no recognised narrowing shape)"
		)
		% [checked, unchecked]
	)


## Returns the manufacturer entry's per-family narrowing block ({family_id: {params: {...}, ...}}),
## or an empty Dictionary if neither recognised shape matched. See the header comment.
func _family_block_for_manufacturer(manu: Dictionary) -> Dictionary:
	if manu.get("families", null) is Dictionary:
		return manu["families"]
	var flat: Dictionary = {}
	for k: Variant in manu.keys():
		var v: Variant = manu[k]
		var entry_dict: Dictionary = (v as Dictionary) if v is Dictionary else {}
		if entry_dict.has("params") or entry_dict.has("ops_disabled"):
			flat[k] = v
	return flat


func _family_param_names(family: Dictionary) -> PackedStringArray:
	for key: String in ["params", "param_ranges", "ranges"]:
		var block: Variant = family.get(key, null)
		if block is Dictionary:
			var names: PackedStringArray = []
			for k: Variant in (block as Dictionary).keys():
				names.append(String(k))
			return names
	return PackedStringArray()


func _family_ops_names(family: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for v: Variant in _as_array(family.get("ops", [])):
		out.append(String(v))
	return out


# --------------------------------------------------------------------------- schema checking --

func _check_all_schemas() -> void:
	if not DirAccess.dir_exists_absolute("res://data/schema"):
		_warnings.append("data/schema/ does not exist yet - schema checks skipped entirely")
		return
	for pack: Dictionary in _PACKS:
		_check_one_schema(String(pack["path"]), String(pack["schema"]))


func _check_one_schema(json_path: String, schema_name: String) -> void:
	if not FileAccess.file_exists(json_path):
		_warnings.append("%s does not exist yet - skipped" % json_path)
		return
	var value: Variant = _load_json(json_path)
	if value == null:
		return  # _load_json already recorded the error

	var schema_path := _find_schema(schema_name)
	if schema_path == "":
		_warnings.append(
			(
				"no schema found for '%s' (tried %s.schema.json and variants under"
				+ " data/schema/) - schema check skipped"
			)
			% [schema_name, schema_name]
		)
		return
	var schema_value: Variant = _load_json(schema_path)
	if not (schema_value is Dictionary):
		_errors.append("%s does not parse as a JSON object schema" % schema_path)
		return

	var root_schema := schema_value as Dictionary
	var before := _errors.size()
	_validate_schema(root_schema, root_schema, value, json_path)
	if _errors.size() == before:
		print("  schema: %s matches %s" % [json_path, schema_path])


func _find_schema(schema_name: String) -> String:
	var candidates: PackedStringArray = [
		"res://data/schema/%s.schema.json" % schema_name,
		"res://data/schema/%s_schema.json" % schema_name,
		"res://data/schema/shapes/%s.schema.json" % schema_name,
		"res://data/schema/shapes_%s.schema.json" % schema_name,
	]
	for c: String in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_errors.append("could not open '%s' (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var text := f.get_as_text()
	f.close()
	var result: Variant = JSON.parse_string(text)
	if result == null:
		_errors.append("'%s' is not valid JSON" % path)
	return result


## Resolves `schema`'s `$ref` (if any) against `root`'s `$defs`/`definitions` tree, following
## chained refs up to a small depth limit so a ref-to-a-ref cannot spin forever on a malformed
## schema. A schema with no `$ref` is returned unchanged.
func _resolve_ref(root: Dictionary, schema: Dictionary) -> Dictionary:
	var current := schema
	var hops := 0
	while current.has("$ref") and (current["$ref"] is String) and hops < 16:
		hops += 1
		var target: Variant = _lookup_pointer(root, String(current["$ref"]))
		if not (target is Dictionary):
			_errors.append("unresolved $ref '%s'" % String(current["$ref"]))
			return {}
		current = target as Dictionary
	return current


## A minimal JSON Pointer resolver: `#/$defs/family` -> root["$defs"]["family"]. Only internal
## (same-document) pointers are supported, which is all either real schema file uses.
func _lookup_pointer(root: Dictionary, pointer: String) -> Variant:
	if not pointer.begins_with("#/"):
		return null
	var cur: Variant = root
	for raw_part: String in pointer.substr(2).split("/"):
		var part := raw_part.replace("~1", "/").replace("~0", "~")
		if not (cur is Dictionary):
			return null
		var cur_dict := cur as Dictionary
		if not cur_dict.has(part):
			return null
		cur = cur_dict[part]
	return cur


## A working subset of JSON Schema 2020-12. See the header comment for exactly what it covers.
## [param root] is the whole schema document, threaded through every recursive call so `$ref`
## can resolve against `$defs` regardless of how deep the current [param schema] sits.
func _validate_schema(
	root: Dictionary, schema_in: Dictionary, value: Variant, path: String
) -> void:
	var schema := _resolve_ref(root, schema_in)

	if schema.has("type") and not _matches_type(value, schema["type"]):
		_errors.append("%s: expected type %s, got %s" % [path, schema["type"], _type_name(value)])
		return  # a type mismatch makes every deeper check meaningless noise

	if schema.has("enum"):
		var allowed: Array = _as_array(schema["enum"])
		if not allowed.has(value):
			_errors.append("%s: value %s is not one of %s" % [path, value, allowed])

	if value is float or value is int:
		var num := float(value)
		if schema.has("minimum") and num < float(schema["minimum"]):
			_errors.append("%s: %s is below minimum %s" % [path, num, schema["minimum"]])
		if schema.has("maximum") and num > float(schema["maximum"]):
			_errors.append("%s: %s is above maximum %s" % [path, num, schema["maximum"]])
		if schema.has("exclusiveMinimum") and num <= float(schema["exclusiveMinimum"]):
			_errors.append(
				"%s: %s is not above exclusiveMinimum %s"
				% [path, num, schema["exclusiveMinimum"]]
			)
		if schema.has("exclusiveMaximum") and num >= float(schema["exclusiveMaximum"]):
			_errors.append(
				"%s: %s is not below exclusiveMaximum %s"
				% [path, num, schema["exclusiveMaximum"]]
			)

	if value is String:
		var s := value as String
		if schema.has("minLength") and s.length() < int(schema["minLength"]):
			_errors.append("%s: string shorter than minLength %s" % [path, schema["minLength"]])
		if schema.has("pattern") and not _pattern_matches(String(schema["pattern"]), s):
			_errors.append("%s: \"%s\" does not match pattern %s" % [path, s, schema["pattern"]])

	if value is Dictionary:
		var dict := value as Dictionary
		if schema.has("minProperties") and dict.size() < int(schema["minProperties"]):
			_errors.append("%s: object has %d properties, fewer than minProperties %s"
				% [path, dict.size(), schema["minProperties"]])
		if schema.has("maxProperties") and dict.size() > int(schema["maxProperties"]):
			_errors.append("%s: object has %d properties, more than maxProperties %s"
				% [path, dict.size(), schema["maxProperties"]])
		for req: Variant in _as_array(schema.get("required", [])):
			if not dict.has(String(req)):
				_errors.append("%s: missing required key '%s'" % [path, String(req)])

		if schema.has("propertyNames"):
			# propertyNames takes an arbitrary schema and applies it to each key as if it were a
			# string VALUE - which may be pattern-based (the top-level id pattern) or enum-based
			# (`$defs/param_key`, in the real manufacturers/families schemas). Recursing through
			# the general validator handles both instead of special-casing "pattern".
			var pn_schema := _as_dict(schema["propertyNames"])
			for k: Variant in dict.keys():
				_validate_schema(root, pn_schema, String(k), "%s[key=%s]" % [path, String(k)])

		var props := _as_dict(schema.get("properties", {}))
		# patternProperties: a key matching one of these regexes is validated against that
		# subschema and is NOT "additional". Omitting this was a false-positive factory: the real
		# hatches.schema.json declares every hatch id via
		#   "patternProperties": { "^[a-z][a-z0-9_]*$": { "$ref": "#/$defs/hatch" } }
		# alongside "additionalProperties": false, which is the ordinary JSON Schema idiom for
		# "an open map of ids with a fixed value shape". Without pattern support every hatch id
		# fell through to the additionalProperties branch and was reported as an unexpected key --
		# 6 errors against a pack that the reference `jsonschema` library passes cleanly. A
		# validator that rejects valid data is worse than no validator: it trains people to
		# ignore it.
		var pattern_props := _as_dict(schema.get("patternProperties", {}))
		var additional_raw: Variant = schema.get("additionalProperties", null)
		for k: Variant in dict.keys():
			var key := String(k)
			var matched_pattern := false
			for pat: Variant in pattern_props.keys():
				var re := RegEx.new()
				if re.compile(String(pat)) != OK:
					_errors.append("%s: patternProperties key '%s' is not a valid regex" % [path, String(pat)])
					continue
				if re.search(key) == null:
					continue
				matched_pattern = true
				if pattern_props[pat] is Dictionary:
					_validate_schema(
						root, pattern_props[pat] as Dictionary, dict[k], "%s.%s" % [path, key]
					)
			if props.has(key) and (props[key] is Dictionary):
				_validate_schema(root, props[key] as Dictionary, dict[k], "%s.%s" % [path, key])
			elif matched_pattern:
				pass  # already validated against its pattern subschema above
			elif additional_raw is Dictionary:
				_validate_schema(root, additional_raw as Dictionary, dict[k], "%s.%s" % [path, key])
			elif (additional_raw is bool) and not (additional_raw as bool):
				_errors.append("%s: unexpected key '%s' (additionalProperties: false)" % [path, key])
			# additionalProperties true, or absent: extra keys are allowed and unchecked.

	if value is Array:
		var arr := value as Array
		if schema.has("minItems") and arr.size() < int(schema["minItems"]):
			_errors.append(
				"%s: array has %d items, fewer than minItems %s"
				% [path, arr.size(), schema["minItems"]]
			)
		if schema.has("maxItems") and arr.size() > int(schema["maxItems"]):
			_errors.append(
				"%s: array has %d items, more than maxItems %s"
				% [path, arr.size(), schema["maxItems"]]
			)
		if _bool_of(schema.get("uniqueItems", false)):
			var seen: Dictionary = {}
			for item: Variant in arr:
				var is_composite: bool = item is Dictionary or item is Array
				var key_repr: String = JSON.stringify(item) if is_composite else str(item)
				if seen.has(key_repr):
					_errors.append("%s: duplicate item in a uniqueItems array (%s)" % [path, key_repr])
				seen[key_repr] = true
		var items_schema: Variant = schema.get("items", null)
		if items_schema is Dictionary:
			for i in arr.size():
				_validate_schema(root, items_schema as Dictionary, arr[i], "%s[%d]" % [path, i])


func _pattern_matches(pattern: String, s: String) -> bool:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return true  # an uncompilable pattern is a schema bug, not a data bug - do not fail data for it
	return re.search(s) != null


## True when [param value] matches ONE json type name. Single exit so the dispatcher below
## stays under gdlint's max-returns without the rule being suppressed.
func _is_json_type(value: Variant, type_name: String) -> bool:
	var ok := false
	match type_name:
		"object":
			ok = value is Dictionary
		"array":
			ok = value is Array
		"string":
			ok = value is String
		"boolean":
			ok = value is bool
		"integer":
			# JSON Schema treats 2.0 as an integer; GDScript parses it as float.
			ok = (value is int) or (
				value is float and is_equal_approx(float(value), round(float(value)))
			)
		"number":
			ok = (value is int) or (value is float)
		"null":
			ok = value == null
	return ok


func _matches_type(value: Variant, type_decl: Variant) -> bool:
	var types := _as_array(type_decl) if type_decl is Array else [type_decl]
	var ok := false
	for t: Variant in types:
		if _is_json_type(value, String(t)):
			ok = true
			break
	return ok


func _type_name(value: Variant) -> String:
	var found := "unknown"
	for candidate: String in ["object", "array", "string", "boolean", "number", "null"]:
		if _is_json_type(value, candidate):
			found = candidate
			break
	return found


func _as_dict(v: Variant) -> Dictionary:
	return (v as Dictionary) if v is Dictionary else {}


func _as_array(v: Variant) -> Array:
	return (v as Array) if v is Array else []


func _bool_of(v: Variant) -> bool:
	return (v as bool) if v is bool else false


func _finish() -> void:
	for w: String in _warnings:
		print("  WARN: %s" % w)
	if _errors.is_empty():
		print("=== data validator PASSED (%d warnings) ===" % _warnings.size())
		quit(0)
	else:
		for e: String in _errors:
			printerr("  ERROR: %s" % e)
		printerr(
			"=== data validator FAILED (%d errors, %d warnings) ==="
			% [_errors.size(), _warnings.size()]
		)
		quit(1)

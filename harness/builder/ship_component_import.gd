class_name ShipComponentImport
extends RefCounted
## IMPORT COMPONENTS (ADR 0024/0025): what can be imported into a document and how. The fleet
## first - every atomic class the templates build, listed under [constant CLASS_PREFIX] - then
## the ships saved under [param ship_dir]. Static only; the builder owns the dialog and the edit.

## A list entry that names an atomic class rather than a saved file.
const CLASS_PREFIX: String = "CLASS: "


## Every source a player may import from, classes first.
static func sources(data: ShipData, ship_dir: String) -> PackedStringArray:
	var items: PackedStringArray = PackedStringArray()
	if data != null:
		for tid: String in ShipTemplates.ids(data):
			items.append(CLASS_PREFIX + tid)
	var dir: DirAccess = DirAccess.open(ship_dir)
	if dir != null:
		for entry: String in dir.get_files():
			if entry.ends_with(".json"):
				items.append(entry.get_basename())
	return items


## The document a source names - a class built in [param doc]'s own room family, or a saved
## ship - or null with [param problems] saying why.
static func source_doc(
	name: String, doc: ShipDoc, data: ShipData, cfg: ShipConfig, ship_dir: String
) -> ShipDoc:
	if name.begins_with(CLASS_PREFIX):
		var tid: String = name.trim_prefix(CLASS_PREFIX)
		return ShipTemplates.build(data, cfg, tid, template_options(doc, data))
	var path: String = "%s/%s.json" % [ship_dir, name]
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return ShipDoc.from_dict(parsed)


## The label a source's ship gets as a component.
static func label_of(name: String) -> String:
	return name.trim_prefix(CLASS_PREFIX).to_upper()


## A class imported as components is built at THIS ship's dimensions - its root's family and
## span, and its first tunnel's family, bore and length (ADR 0026) - so a nucleus dropped into a
## sphere ship of 6 m protons arrives as 6 m spheres, not at the class's own default. Measured:
## the class defaults are sized per class by a volume budget (a carbon's proton 11.8 m, a
## hydrogen's 25.5 m), nothing like a ship built from the start dialog's sliders.
static func template_options(doc: ShipDoc, data: ShipData) -> Dictionary:
	var out: Dictionary = {}
	if doc == null or data == null:
		return out
	var root: ShipPart = doc.part_at(doc.root)
	if root == null:
		return out
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, ShipConfig.defaults())
	var root_shape: ResolvedShape = shapes.get(doc.root, null)
	var family: String = root.family
	var manufacturer: String = root.manufacturer
	if root.kind == ShipPart.KIND_COMPONENT_INSTANCE:
		var definition: Dictionary = doc.components.get(root.family, {})
		var inner: Dictionary = ShipComponents.definition_parts(definition)
		var inner_root: Variant = inner.get(str(definition.get("root", "")), null)
		family = (inner_root as ShipPart).family if inner_root is ShipPart else ""
		manufacturer = (inner_root as ShipPart).manufacturer if inner_root is ShipPart else ""
	if not family.is_empty() and data.families.has(family):
		out[ShipTemplates.OPT_ROOM_FAMILY] = family
		if not manufacturer.is_empty():
			out[ShipTemplates.OPT_ROOM_MANUFACTURER] = manufacturer
	if root_shape != null:
		out[ShipTemplates.OPT_ROOM_SPAN] = _widest(root_shape)
	for pid: String in doc.part_order():
		var part: ShipPart = doc.parts[pid]
		if part.role != ShipPart.ROLE_HALLWAY or not shapes.has(pid):
			continue
		var tube: ResolvedShape = shapes[pid]
		var size: Vector3 = tube.local_aabb().size
		if data.families.has(part.family):
			out[ShipTemplates.OPT_HALL_FAMILY] = part.family
			if not part.manufacturer.is_empty():
				out[ShipTemplates.OPT_HALL_MANUFACTURER] = part.manufacturer
		out[ShipTemplates.OPT_TUNNEL_BORE] = maxf(size.x, size.z)
		out[ShipTemplates.OPT_TUNNEL_LENGTH] = size.y
		break
	return out


static func _widest(shape: ResolvedShape) -> float:
	var size: Vector3 = shape.local_aabb().size
	return maxf(size.x, maxf(size.y, size.z))

class_name ShipTemplates
extends RefCounted

## Stock ship templates — rooms joined by cylinder hallways, named after what they model.
##
## The author's brief, verbatim:
##
## > "id like some pre configured procedural ships made, i want them to model atoms and inhearit
## > atoms names. they will consist of single shape primitave rooms linked together by cylynder
## > hallways, and controllable parameters are what shape for rooms, what shape for
## > hallways/tunnels, length of tunnels, size of rooms. and the element/atom h, he, li, ... things
## > like that where theres different ways to branch 4 room nodes around a central one
## > symmetrically those variants can be down th aperiodic family list. and names like the 'water
## > molecule' and common simple varients on that theme.. these will serve as the stock options
## > templates. a hatch between each hallway/tunnel and room and room to room connection."
##
## THE GEOMETRY IS REAL CHEMISTRY, not a theme applied on top of one. An element's branch
## directions are its VSEPR arrangement — carbon really is four berths at 109.5 degrees, water
## really is two at 104.5 — so walking the periodic list walks genuinely different ways to put
## rooms around a centre, which is the thing that was asked for. `data/templates.json` holds the
## arrangements, the elements and the molecules; adding a template never touches this file
## (AGENTS section 3).
##
## THE CHAIN IS ROOM -> TUNNEL -> ROOM, never room -> tunnel and room -> room. A branch would
## otherwise cost the core TWO children, and an eight-branch core would need sixteen against a
## family cap of eight (`max_children`). Parenting the room to the far end of its own tunnel costs
## the core one child per branch and is also the truer statement of the structure: you reach the
## pod THROUGH the tunnel.
##
## SIZE COMES FROM THREE LEVERS, not from the pack: `room_span_m`, `tunnel_bore_m` and
## `tunnel_length_m` in `data/tuning.json`. The shipped values are the author's "smallest room
## module" — a 1 m bore you crawl through and a 3 m room you can just stand up in.
##
## OFFSET DOES THE WORK. A tunnel is seated on the core's surface by `ShipAttach` and the room on
## the tunnel's far cap; nothing here computes a world position. Every distance is expressed in
## the attach model's own terms, which is what keeps a template rebuildable after the levers move.
##
## BOTH JOINS ARE EMBEDDED, like every other placement (`ShipAttach.default_offset`): the tunnel
## sinks its root end into the core and the room swallows the tunnel's far end. A room seated
## flush on a flat cap touches it at one point, which is the "no real connection" the embed
## exists to remove. `tunnel_length_m` is still the OPEN run: the tunnel is built longer by
## exactly the two embeds, so the crawl between the core's surface and the room's is the lever's
## value. The embeds are measured with the tunnel at the lever's length and the tunnel is then
## lengthened by them; a tube's sole is its end cap, which does not move with its length, so the
## measurement holds for the tunnel as built.
##
## `core/` purity: static only, no state, no engine objects, no `res://`.

## Section names in `data/templates.json`.
const SECTION_ARRANGEMENTS: String = "arrangements"
const SECTION_ELEMENTS: String = "elements"
const SECTION_MOLECULES: String = "molecules"

## Template id prefixes, so one flat id space covers both sections.
const KIND_ELEMENT: String = "element"
const KIND_MOLECULE: String = "molecule"
const ID_SEP: String = ":"

## `ShipPart.role` values this builder writes. Extends the reserved Phase 3 vocabulary rather than
## adding a field: a room IS a classification of what a part is for, and `role` already
## round-trips through `to_dict`/`from_dict`. The vocabulary itself lives on [ShipPart] now that
## room is every part's default; these aliases keep the names the panels compile against.
const ROLE_ROOM: String = ShipPart.ROLE_ROOM
const ROLE_HALLWAY: String = ShipPart.ROLE_HALLWAY

## Every connection a template makes is hatched, per the brief. The hatch family is an option;
## this is the fallback when the caller does not name one and the pack has no obvious round hatch.
const DEFAULT_HATCH: String = "crawlway_round"

## Option keys accepted by [method build]. Anything omitted falls back to the config lever or to
## the first family in the pack.
const OPT_ROOM_FAMILY: String = "room_family"
const OPT_ROOM_MANUFACTURER: String = "room_manufacturer"
const OPT_HALL_FAMILY: String = "hall_family"
const OPT_HALL_MANUFACTURER: String = "hall_manufacturer"
const OPT_ROOM_SPAN: String = "room_span_m"
const OPT_TUNNEL_LENGTH: String = "tunnel_length_m"
const OPT_TUNNEL_BORE: String = "tunnel_bore_m"
const OPT_HATCH_FAMILY: String = "hatch_family"

## Guards a pathological pack: a molecule that names itself as its own parent, or a cycle, would
## otherwise walk forever.
const MAX_NODES: int = 64


## Every template id, elements first (in atomic-number order, which is the periodic list the brief
## asks for) then molecules (in pack order). Ids are `"element:carbon"`, `"molecule:water"`.
static func ids(data: ShipData) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var pack: Dictionary = _pack(data)
	var elements: Dictionary = _dict_of(pack.get(SECTION_ELEMENTS))
	var ordered: Array = elements.keys()
	ordered.sort_custom(
		func(a: String, b: String) -> bool:
			return (
				_num(_dict_of(elements[a]).get("z"), 0.0)
				< _num(_dict_of(elements[b]).get("z"), 0.0)
			)
	)
	for eid: String in ordered:
		out.append(KIND_ELEMENT + ID_SEP + eid)
	for mid: String in _dict_of(pack.get(SECTION_MOLECULES)):
		out.append(KIND_MOLECULE + ID_SEP + mid)
	return out


## The raw pack entry behind a template id, or {} when there is none.
static func entry(data: ShipData, template_id: String) -> Dictionary:
	var pack: Dictionary = _pack(data)
	var section: String = (
		SECTION_ELEMENTS if kind_of(template_id) == KIND_ELEMENT else SECTION_MOLECULES
	)
	return _dict_of(_dict_of(pack.get(section)).get(_bare_id(template_id)))


static func kind_of(template_id: String) -> String:
	return KIND_MOLECULE if template_id.begins_with(KIND_MOLECULE + ID_SEP) else KIND_ELEMENT


## Display label. Elements get their chemical symbol in front, because the symbol is the thing a
## player scanning a list of sixteen elements actually reads.
static func label_of(data: ShipData, template_id: String) -> String:
	var e: Dictionary = entry(data, template_id)
	var label: String = _text(e.get("label"), _bare_id(template_id).capitalize())
	var symbol: String = _text(e.get("symbol"), "")
	if symbol.is_empty():
		symbol = _text(e.get("formula"), "")
	if symbol.is_empty():
		return label
	return "%s  %s" % [symbol, label]


static func description_of(data: ShipData, template_id: String) -> String:
	return _text(entry(data, template_id).get("description"), "")


## How many parts this template builds, without building it — the palette shows it, and the
## complexity gate wants it before the player commits.
static func part_count(data: ShipData, template_id: String) -> int:
	var nodes: Array[Dictionary] = _nodes_for(data, template_id)
	# One room per node, plus one tunnel for every node that has a parent.
	return nodes.size() * 2 - 1 if not nodes.is_empty() else 0


## Builds a complete document from a template.
##
## Returns null when the template id is unknown or the pack cannot supply a room family, so a
## caller can report that rather than founding an empty ship.
static func build(
	data: ShipData, cfg: ShipConfig, template_id: String, options: Dictionary
) -> ShipDoc:
	if data == null:
		return null
	var nodes: Array[Dictionary] = _nodes_for(data, template_id)
	if nodes.is_empty():
		return null

	var conf: ShipConfig = cfg if cfg != null else ShipConfig.defaults()
	var room_family: String = _opt_text(options, OPT_ROOM_FAMILY, _first_family(data))
	if room_family.is_empty():
		return null
	var room_mfr: String = _opt_text(
		options, OPT_ROOM_MANUFACTURER, _first_manufacturer(data, room_family)
	)
	var hall_family: String = _opt_text(options, OPT_HALL_FAMILY, _first_tube(data, room_family))
	var hall_mfr: String = _opt_text(
		options, OPT_HALL_MANUFACTURER, _first_manufacturer(data, hall_family)
	)
	var room_span: float = _opt_num(options, OPT_ROOM_SPAN, conf.room_span_m)
	var tunnel_len: float = _opt_num(options, OPT_TUNNEL_LENGTH, conf.tunnel_length_m)
	var bore: float = _opt_num(options, OPT_TUNNEL_BORE, conf.tunnel_bore_m)
	var hatch: String = _opt_text(options, OPT_HATCH_FAMILY, _pick_hatch(data))

	var doc: ShipDoc = ShipDoc.create_new(room_family, room_mfr, data, 0.0)
	if doc == null or doc.root.is_empty():
		return null
	var room_scale: Vector3 = _uniform_span(data, room_family, room_mfr, room_span)
	var room_shape: ResolvedShape = _resolved(data, room_family, room_mfr, room_scale)
	var open_scale: Vector3 = _tube_scale(data, hall_family, hall_mfr, bore, tunnel_len)
	var hall_shape: ResolvedShape = _resolved(data, hall_family, hall_mfr, open_scale)
	# The room continues straight off the tunnel's cap; a probe standing square, exactly as
	# the room below is written. The tunnel's probe is aimed per node, because on a room that
	# is not a sphere the depth of a seat depends on where it lands.
	var hall_probe: ShipPart = ShipPart.new()
	var room_probe: ShipPart = ShipPart.new()
	var straight: Vector2 = ShipAttach.angles_from_direction(Vector3.UP)
	room_probe.yaw = straight.x
	room_probe.pitch = straight.y
	var room_offset: float = ShipAttach.default_offset(hall_shape, room_shape, room_probe, conf)

	var part_of_node: PackedStringArray = PackedStringArray()
	part_of_node.resize(nodes.size())
	var root_part: ShipPart = doc.parts[doc.root]
	root_part.scale = room_scale
	root_part.role = ROLE_ROOM
	root_part.display_name = _room_name(nodes[0], 0)
	part_of_node[0] = doc.root

	for i: int in range(1, nodes.size()):
		var node: Dictionary = nodes[i]
		var parent_index: int = int(node.get("parent", 0))
		var parent_id: String = part_of_node[parent_index]
		var dir: Vector3 = node.get("dir", Vector3.UP)
		var angles: Vector2 = ShipAttach.angles_from_direction(dir)

		var tunnel: ShipPart = ShipPart.new()
		tunnel.parent = parent_id
		tunnel.kind = ShipPart.KIND_PRIMITIVE
		tunnel.family = hall_family
		tunnel.manufacturer = hall_mfr
		tunnel.params = ShapeGen.default_params(data, hall_family, hall_mfr)
		tunnel.yaw = angles.x
		tunnel.pitch = angles.y
		hall_probe.yaw = angles.x
		hall_probe.pitch = angles.y
		var hall_offset: float = ShipAttach.default_offset(room_shape, hall_shape, hall_probe, conf)
		tunnel.offset = hall_offset
		tunnel.scale = _tube_scale(
			data, hall_family, hall_mfr, bore, tunnel_len - hall_offset - room_offset
		)
		tunnel.role = ROLE_HALLWAY
		tunnel.display_name = "TUNNEL %d" % i
		# A tunnel is a structural duct, not a silhouette: it sits on the ship's centre line as
		# often as not, and a mirrored copy of one would double every corridor in a symmetric hull.
		tunnel.asymmetric = true
		var tunnel_id: String = doc.add_part(tunnel)

		var room: ShipPart = ShipPart.new()
		room.parent = tunnel_id
		room.kind = ShipPart.KIND_PRIMITIVE
		room.family = room_family
		room.manufacturer = room_mfr
		room.params = ShapeGen.default_params(data, room_family, room_mfr)
		# Straight off the tunnel's far cap. The tunnel's own +Y already points away from the
		# core, so this is "keep going", not a second direction to get right.
		var out_angles: Vector2 = ShipAttach.angles_from_direction(Vector3.UP)
		room.yaw = out_angles.x
		room.pitch = out_angles.y
		room.offset = room_offset
		room.scale = room_scale
		room.role = ROLE_ROOM
		room.display_name = _room_name(node, i)
		room.asymmetric = true
		var room_id: String = doc.add_part(room)
		part_of_node[i] = room_id

		_hatch(doc, parent_id, tunnel_id, hatch, data)
		_hatch(doc, tunnel_id, room_id, hatch, data)
	return doc


# --- node layout -------------------------------------------------------------------------


## Flattens a template into `[{parent: int, dir: Vector3, element: String, symbol: String}]`, root
## first. The root carries no parent and no direction.
static func _nodes_for(data: ShipData, template_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e: Dictionary = entry(data, template_id)
	if e.is_empty():
		return out
	if kind_of(template_id) == KIND_ELEMENT:
		out.append(_node(0, Vector3.UP, _bare_id(template_id), _text(e.get("symbol"), "")))
		for dir: Vector3 in _dirs_of(data, _text(e.get("arrangement"), "")):
			if out.size() >= MAX_NODES:
				break
			out.append(_node(0, dir, _bare_id(template_id), _text(e.get("symbol"), "")))
		return out

	var raw: Array = e.get("nodes", []) as Array
	for i: int in raw.size():
		if out.size() >= MAX_NODES:
			break
		var spec: Dictionary = _dict_of(raw[i])
		var element_id: String = _text(spec.get("element"), "")
		var element: Dictionary = _dict_of(
			_dict_of(_pack(data).get(SECTION_ELEMENTS)).get(element_id)
		)
		var symbol: String = _text(element.get("symbol"), "")
		if i == 0 or not spec.has("parent"):
			out.append(_node(0, Vector3.UP, element_id, symbol))
			continue
		# The direction is the PARENT'S arrangement slot: a molecule says "hang this off carbon's
		# third berth", and carbon's berths are what carbon's own geometry says they are.
		var parent_index: int = clampi(int(spec.get("parent", 0)), 0, maxi(out.size() - 1, 0))
		var parent_element: Dictionary = _dict_of(
			_dict_of(_pack(data).get(SECTION_ELEMENTS)).get(
				_text(_dict_of(raw[parent_index]).get("element"), "")
			)
		)
		var dirs: Array[Vector3] = _dirs_of(data, _text(parent_element.get("arrangement"), ""))
		var slot: int = int(spec.get("slot", 0))
		var dir: Vector3 = Vector3.UP
		if not dirs.is_empty():
			dir = dirs[posmod(slot, dirs.size())]
		out.append(_node(parent_index, dir, element_id, symbol))
	return out


static func _node(parent: int, dir: Vector3, element_id: String, symbol: String) -> Dictionary:
	return {"parent": parent, "dir": dir, "element": element_id, "symbol": symbol}


## Branch directions of one named arrangement, normalised. An unknown name yields a single
## straight-up branch rather than nothing, so a typo in the pack produces a visibly wrong ship
## instead of a silently empty one.
static func _dirs_of(data: ShipData, arrangement: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var spec: Dictionary = _dict_of(
		_dict_of(_pack(data).get(SECTION_ARRANGEMENTS)).get(arrangement)
	)
	var raw: Array = spec.get("dirs", []) as Array
	for item: Variant in raw:
		if not (item is Array):
			continue
		var a: Array = item
		if a.size() < 3:
			continue
		var v: Vector3 = Vector3(_num(a[0], 0.0), _num(a[1], 0.0), _num(a[2], 0.0))
		if v.length_squared() > 0.0:
			out.append(v.normalized())
	if out.is_empty():
		out.append(Vector3.UP)
	return out


static func _room_name(node: Dictionary, index: int) -> String:
	var symbol: String = _text(node.get("symbol"), "")
	if symbol.is_empty():
		symbol = _text(node.get("element"), "ROOM").to_upper()
	return "%s CORE" % symbol if index == 0 else "%s POD %d" % [symbol, index]


# --- sizing ------------------------------------------------------------------------------


## Uniform scale putting the widest axis of a family's resolved bounds at `span` metres.
static func _uniform_span(
	data: ShipData, family_id: String, manufacturer_id: String, span: float
) -> Vector3:
	var box: Vector3 = _unscaled_size(data, family_id, manufacturer_id)
	var widest: float = maxf(box.x, maxf(box.y, box.z))
	if widest <= 0.0 or span <= 0.0:
		return Vector3.ONE
	var k: float = span / widest
	return Vector3(k, k, k)


## Per-axis scale making a hallway `bore` metres across and `length` metres long along its own +Y.
## Non-uniform on purpose: a tunnel is defined by two independent numbers, and forcing one scale
## would make the bore a function of the length.
static func _tube_scale(
	data: ShipData, family_id: String, manufacturer_id: String, bore: float, length: float
) -> Vector3:
	var box: Vector3 = _unscaled_size(data, family_id, manufacturer_id)
	var sx: float = bore / box.x if box.x > 0.0 and bore > 0.0 else 1.0
	var sy: float = length / box.y if box.y > 0.0 and length > 0.0 else 1.0
	var sz: float = bore / box.z if box.z > 0.0 and bore > 0.0 else 1.0
	return Vector3(sx, sy, sz)


static func _unscaled_size(data: ShipData, family_id: String, manufacturer_id: String) -> Vector3:
	return _resolved(data, family_id, manufacturer_id, Vector3.ONE).local_aabb().size


## The family at its default params under `scale`, resolved.
static func _resolved(
	data: ShipData, family_id: String, manufacturer_id: String, scale: Vector3
) -> ResolvedShape:
	var params: Dictionary = ShapeGen.default_params(data, family_id, manufacturer_id)
	return ShapeGen.resolve(data, family_id, manufacturer_id, params, scale)


# --- joints ------------------------------------------------------------------------------


## A hatched joint between two parts. "a hatch between each hallway/tunnel and room and room to
## room connection" — so this is not discovered, it is authored, and every template connection
## gets one.
static func _hatch(
	doc: ShipDoc, a: String, b: String, hatch_family: String, data: ShipData
) -> void:
	if a.is_empty() or b.is_empty():
		return
	var joint: ShipJoint = ShipJoint.new()
	joint.id = doc.new_joint_id()
	if a <= b:
		joint.a = a
		joint.b = b
	else:
		joint.a = b
		joint.b = a
	joint.mode = ShipJoint.MODE_HATCHED
	joint.hatch_family = hatch_family
	joint.hatch_params = _hatch_defaults(data, hatch_family)
	doc.joints[joint.id] = joint


## Default params for a hatch family, read straight off the pack's own ranges. A hatch record with
## empty params would resolve to nothing the day the hatch geometry is implemented.
static func _hatch_defaults(data: ShipData, hatch_family: String) -> Dictionary:
	var out: Dictionary = {}
	if data == null:
		return out
	var entry_d: Dictionary = _dict_of(data.hatches.get(hatch_family))
	var params: Dictionary = _dict_of(entry_d.get("params"))
	for key: String in params:
		var spec: Dictionary = _dict_of(params[key])
		out[key] = _num(spec.get("default"), _num(spec.get("min"), 0.0))
	return out


## Prefers a round crawlway — the brief's tunnels are 1 m bores, and a round duct is what goes on
## the end of one. Falls back to whatever the pack ships first.
static func _pick_hatch(data: ShipData) -> String:
	if data == null:
		return ""
	if data.hatches.has(DEFAULT_HATCH):
		return DEFAULT_HATCH
	for hid: String in data.hatches:
		return hid
	return ""


# --- pack readers ------------------------------------------------------------------------


static func _pack(data: ShipData) -> Dictionary:
	return data.templates if data != null else {}


static func _bare_id(template_id: String) -> String:
	var at: int = template_id.find(ID_SEP)
	return template_id.substr(at + 1) if at >= 0 else template_id


static func _first_family(data: ShipData) -> String:
	var ids_list: PackedStringArray = data.family_ids()
	return ids_list[0] if not ids_list.is_empty() else ""


## The family a hallway should default to: the first CYLINDER in the pack, because that is what
## the brief says a hallway is. Falls back to the room family so a pack with no cylinder still
## builds something rather than nothing.
static func _first_tube(data: ShipData, fallback: String) -> String:
	for family_id: String in data.family_ids():
		var mfrs: PackedStringArray = data.manufacturers_for(family_id)
		var mfr: String = mfrs[0] if not mfrs.is_empty() else ""
		var shape: ResolvedShape = ShapeGen.resolve(data, family_id, mfr, {}, Vector3.ONE)
		if shape.base == ResolvedShape.Base.CYLINDER:
			return family_id
	return fallback


static func _first_manufacturer(data: ShipData, family_id: String) -> String:
	var mfrs: PackedStringArray = data.manufacturers_for(family_id)
	return mfrs[0] if not mfrs.is_empty() else ""


static func _opt_text(options: Dictionary, key: String, fallback: String) -> String:
	var raw: Variant = options.get(key)
	if raw is String and not String(raw).is_empty():
		return String(raw)
	return fallback


static func _opt_num(options: Dictionary, key: String, fallback: float) -> float:
	var raw: Variant = options.get(key)
	if raw is float or raw is int:
		return float(raw)
	return fallback


static func _dict_of(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _num(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		return float(v)
	return fallback


static func _text(v: Variant, fallback: String) -> String:
	return String(v) if v is String else fallback

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
## How near two slots must be, squared, to count as each other's reflection across X. The
## arrangements are unit directions written to six places, so this only has to clear that dust.
const MIRROR_SLOT_EPSILON: float = 1.0e-6

const SECTION_ARRANGEMENTS: String = "arrangements"
const SECTION_ELEMENTS: String = "elements"
const SECTION_MOLECULES: String = "molecules"
const SECTION_PERIODS: String = "periods"

## How a node hangs off its parent (ADR 0014). A NUCLEUS body is fused straight into the one
## before it - no tunnel, no hatch, sunk far enough in that the two read as one mass - because a
## nucleus is one body with internal structure, not a cluster of modules on stalks. An EXTREMITY
## gets the tunnel and the hatch.
const LINK_ROOT: String = "root"
const LINK_FUSE: String = "fuse"
const LINK_TUNNEL: String = "tunnel"

## Halvings the nucleus radius is solved to (ADR 0034). Each one halves the bracket, which starts
## at the body's own reach: twenty puts it inside a millionth of that, far below anything a hull
## can show.
const NUCLEUS_SOLVE_STEPS: int = 20

## Nucleus bodies, capped. "1-8 for practicality": past eight the fused mass stops reading as a
## core and starts reading as gravel, and the eight-children-per-parent rule runs out of berths.
const MAX_NUCLEUS: int = 8

## How far a fused nucleus body is sunk into the one before it, as a fraction of its own span.
## Deep enough that the pair is visibly one solid rather than two touching; shallow enough that
## each body still shows.
const FUSE_OVERLAP: float = 0.34

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

## THE THREE GROUPS A TEMPLATE BUILDS, each with its own shape (dev note 2026-09-24): "the player
## options for the prebuilt structures need expanding with options for outter/electron node
## shapes, tunnel shapes, proton shapes."
##
## A PROTON is a nucleus body, fused into its neighbours; an ELECTRON is an outer node on the far
## end of a tunnel; the TUNNEL is the hallway between them, which already had `OPT_HALL_FAMILY`.
## Both node options fall back to [constant OPT_ROOM_FAMILY], which is what they were until now,
## so a caller that names only the one still gets the ship it always did.
const OPT_PROTON_FAMILY: String = "proton_family"
const OPT_ELECTRON_FAMILY: String = "electron_family"

## A SECOND SHAPE FOR EITHER GROUP, blended through it: "the new shaper should cater to multi
## shape clusters, so a protons shapes can be shape1 and shape2 ... so a proton cluster can exist
## with cubes and spheres blended". Empty, or the same as the first, means one shape throughout.
##
## MIRROR PARTNERS ALWAYS MATCH, which is how "the system will try to keep everything semetrical
## and even as normal" is honoured: the blend alternates PAIR BY PAIR, not body by body, so a
## blended cluster is as symmetric as an unblended one and ADR 0044 still holds.
const OPT_PROTON_FAMILY_B: String = "proton_family_b"
const OPT_ELECTRON_FAMILY_B: String = "electron_family_b"

## What every template connection is LINKED with - a `ShipJoint.MODE_*`. OPEN by default: "by
## default in the prebuilds we dont want any walls in our prebuilds by default" (2026-09-26).
## The hatch is still AUTHORED on every joint whatever this says - its family and its params are
## written in - so turning one link to `hatched` is a single edit and nothing has to be picked
## again. RETIRED(2026-09-26): MODE_HATCHED, from the original brief "a hatch between each
## hallway/tunnel and room and room to room connection", which is now what this option selects
## rather than what it forces.
const OPT_LINK_MODE: String = "link_mode"

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
	# THE THREE GROUPS. Each node group falls back to the one room family, so nothing changes for
	# a caller that names only that.
	var proton_a: String = _opt_text(options, OPT_PROTON_FAMILY, room_family)
	var proton_b: String = _opt_text(options, OPT_PROTON_FAMILY_B, "")
	var electron_a: String = _opt_text(options, OPT_ELECTRON_FAMILY, room_family)
	var electron_b: String = _opt_text(options, OPT_ELECTRON_FAMILY_B, "")
	var hall_family: String = _opt_text(options, OPT_HALL_FAMILY, _first_tube(data, room_family))
	var hall_mfr: String = _opt_text(
		options, OPT_HALL_MANUFACTURER, _first_manufacturer(data, hall_family)
	)
	# EVERY CLASS ENCLOSES THE SAME VOLUME (ADR 0014): the budget is divided by however many
	# bodies this class has, and the module span follows from that. A caller who names a span
	# explicitly still gets it - the budget is the default, not a cage.
	var room_span: float = _opt_num(options, OPT_ROOM_SPAN, conf.room_span_m)
	if not options.has(OPT_ROOM_SPAN):
		room_span = _span_for_volume(
			data, proton_a, room_mfr, conf.template_volume_m3 / float(maxi(nodes.size(), 1))
		)
	var tunnel_len: float = _opt_num(options, OPT_TUNNEL_LENGTH, conf.tunnel_length_m)
	# A TUNNEL HAS TO PASS ITS OWN SMALLEST HATCH (ADR 0040). The bore lever is the player's, but a
	# hallway narrower than a person in a suit is not a hallway, and the hole would just be bored
	# under the minimum and reported TIGHT - which is what a 0.66 m floor did on a 0.38 m hole.
	var bore: float = maxf(
		_opt_num(options, OPT_TUNNEL_BORE, conf.tunnel_bore_m),
		ShipDoors.bore_for_hatch(conf.hatch_min_m, conf.hull_thickness_m)
	)
	var hatch: String = _opt_text(options, OPT_HATCH_FAMILY, _pick_hatch(data))
	var link_mode: String = _opt_text(options, OPT_LINK_MODE, ShipJoint.MODE_OPEN)

	# WHICH SHAPE EVERY NODE WEARS, before the document exists - the root is a node like any
	# other, and with a blend on it may be the second shape rather than the first.
	var family_of: Dictionary = _blend_families(
		data, nodes, proton_a, proton_b, electron_a, electron_b
	)
	var kits: Dictionary = _kits_for(
		data,
		family_of,
		room_span,
		PackedStringArray([proton_a, proton_b, electron_a, electron_b, room_family])
	)
	var root_kit: Dictionary = kits[family_of[0]]

	var doc: ShipDoc = ShipDoc.create_new(str(root_kit["family"]), str(root_kit["mfr"]), data, 0.0)
	if doc == null or doc.root.is_empty():
		return null
	var room_scale: Vector3 = root_kit["scale"]
	var room_shape: ResolvedShape = root_kit["shape"]
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
	# The tunnel's length allowance, measured on the FIRST electron shape - a tunnel is cut once
	# per class, and a blend changes this by the difference between two seats rather than by a
	# room's worth.
	var room_offset: float = ShipAttach.default_offset(
		hall_shape, kits[electron_a]["shape"], room_probe, conf
	)

	var part_of_node: PackedStringArray = PackedStringArray()
	part_of_node.resize(nodes.size())
	var root_part: ShipPart = doc.parts[doc.root]
	root_part.scale = room_scale
	root_part.role = ROLE_ROOM
	root_part.display_name = _room_name(nodes[0], 0)
	# Like every other part the template makes: no mirror twin. The arrangement already places
	# every body, so a twin of this one is a second body nothing asked for. It did not matter while
	# the root sat ON the mirror plane at the origin; centred on the beacon (ADR 0033) it takes a
	# slot like any other and the plane would duplicate it - measured on helium, whose twin landed
	# exactly on its other proton.
	root_part.asymmetric = true
	# THE ROOT STANDS IN ITS OWN SLOT (ADR 0034), anchored to the beacon like every other body of
	# the nucleus. A class whose arrangement has no slot to give - a single-body one - lays its
	# root over the beacon, which is the identity anchor it already carries.
	var radius: float = _nucleus_radius(nodes, room_shape, conf)
	var root_anchor: Vector3 = nodes[0].get("anchor", Vector3.ZERO)
	if root_anchor.length_squared() > 0.0:
		root_part.absolute = _anchored_at(root_anchor, radius)
	part_of_node[0] = doc.root
	var nucleus_ids: PackedStringArray = PackedStringArray([doc.root])

	for i: int in range(1, nodes.size()):
		var node: Dictionary = nodes[i]
		var parent_index: int = int(node.get("parent", 0))
		var parent_id: String = part_of_node[parent_index]
		var dir: Vector3 = node.get("dir", Vector3.UP)
		if bool(node.get("world", false)):
			dir = _local_direction(doc, data, conf, parent_id, dir)
		var angles: Vector2 = ShipAttach.angles_from_direction(dir)

		# A NUCLEUS body is fused straight into its neighbour: no tunnel, no hatch, and sunk far
		# enough in that the two read as one mass rather than as two modules touching.
		if _text(node.get("link"), LINK_TUNNEL) == LINK_FUSE:
			var kit: Dictionary = kits[family_of[i]]
			var fused: ShipPart = ShipPart.new()
			fused.parent = parent_id
			fused.kind = ShipPart.KIND_PRIMITIVE
			fused.family = str(kit["family"])
			fused.manufacturer = str(kit["mfr"])
			fused.params = ShapeGen.default_params(data, fused.family, fused.manufacturer)
			fused.yaw = angles.x
			fused.pitch = angles.y
			var seat: ShipPart = ShipPart.new()
			seat.yaw = angles.x
			seat.pitch = angles.y
			# The seat is between the PARENT's shape and this body's own, which a blended cluster
			# makes two different shapes rather than one twice.
			fused.offset = (
				ShipAttach.default_offset(
					kits[family_of[parent_index]]["shape"], kit["shape"], seat, conf
				)
				- room_span * FUSE_OVERLAP
			)
			# ANCHORED IN ITS SLOT (ADR 0034), standing on nothing: the four attach numbers above
			# stay on the part as the record of where it WOULD have been seated, and are ignored
			# while it has no parent (ShipAttach._place_part). A class with no arrangement big
			# enough falls back to the old hub and spoke, which needs them.
			var anchor: Vector3 = node.get("anchor", Vector3.ZERO)
			if anchor.length_squared() > 0.0:
				fused.parent = ""
				fused.absolute = _anchored_at(anchor, radius)
			fused.scale = kit["scale"]
			fused.role = ROLE_ROOM
			fused.display_name = _room_name(node, i)
			fused.asymmetric = true
			part_of_node[i] = doc.add_part(fused)
			nucleus_ids.append(part_of_node[i])
			continue

		# The first body that is not fused: the nucleus is complete, so it becomes the ship's
		# root component before anything hangs off it (ADR 0024).
		if nucleus_ids.size() > 1 and doc.root == nucleus_ids[0]:
			part_of_node = _lift_nucleus(
				doc, data, conf, nucleus_ids, part_of_node, _symbol_of(nodes)
			)
			parent_id = part_of_node[parent_index]

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
		# Seated on the PARENT body, whose shape a blended cluster may have changed.
		var hall_offset: float = ShipAttach.default_offset(
			kits[family_of[parent_index]]["shape"], hall_shape, hall_probe, conf
		)
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

		var pod_kit: Dictionary = kits[family_of[i]]
		var room: ShipPart = ShipPart.new()
		room.parent = tunnel_id
		room.kind = ShipPart.KIND_PRIMITIVE
		room.family = str(pod_kit["family"])
		room.manufacturer = str(pod_kit["mfr"])
		room.params = ShapeGen.default_params(data, room.family, room.manufacturer)
		# Straight off the tunnel's far cap. The tunnel's own +Y already points away from the
		# core, so this is "keep going", not a second direction to get right.
		var out_angles: Vector2 = ShipAttach.angles_from_direction(Vector3.UP)
		room.yaw = out_angles.x
		room.pitch = out_angles.y
		room.offset = ShipAttach.default_offset(hall_shape, pod_kit["shape"], room_probe, conf)
		room.scale = pod_kit["scale"]
		room.role = ROLE_ROOM
		room.display_name = _room_name(node, i)
		room.asymmetric = true
		var room_id: String = doc.add_part(room)
		part_of_node[i] = room_id

		_hatch(doc, parent_id, tunnel_id, hatch, data, link_mode)
		_hatch(doc, tunnel_id, room_id, hatch, data, link_mode)
	if nucleus_ids.size() > 1 and doc.root == nucleus_ids[0]:
		part_of_node = _lift_nucleus(doc, data, conf, nucleus_ids, part_of_node, _symbol_of(nodes))
	_centre_on_the_beacon(doc, data, conf)
	return doc


## How far every nucleus body stands from the beacon (ADR 0034): the radius at which the CLOSEST
## pair of the arrangement sinks into each other by [constant FUSE_OVERLAP] of the body's own reach
## toward the other, which is what the chain of seats used to do one body at a time.
##
## IT IS SOLVED AGAINST THE FIELD, NOT DERIVED. The old chain could ask the attach model to seat one
## body on another and read the answer off it; a ring of bodies around a centre has no seat to read,
## and the reach of a shape along a direction is the shape's own business - 4.73 m up a box of that
## half-span, 6.69 m into its corner, and a spar is long one way and thin the other two. So the
## sink is measured straight off [method ResolvedShape.sdf], walking out along the chord between the
## two slots until the field reads exactly the depth wanted, and the radius follows from the chord.
## MEASURED: a spar nucleus sized by one axial distance came out as six rooms that never touched.
##
## The bisection is deterministic to [constant NUCLEUS_SOLVE_STEPS] halvings - well under a
## millimetre on any ship - and the pair it solves for is the tightest angle in the arrangement,
## lowest index first, so the answer cannot depend on the order the pairs come out in.
static func _nucleus_radius(
	nodes: Array[Dictionary], room_shape: ResolvedShape, cfg: ShipConfig
) -> float:
	var anchors: Array[Vector3] = []
	for node: Dictionary in nodes:
		var anchor: Vector3 = node.get("anchor", Vector3.ZERO)
		if anchor.length_squared() > 0.0:
			anchors.append(anchor.normalized())
	if anchors.size() < 2 or room_shape == null:
		return 0.0
	var first: int = -1
	var second: int = -1
	var closest: float = PI
	for i: int in anchors.size():
		for j: int in range(i + 1, anchors.size()):
			# A pathological pack naming one direction twice has no chord between that pair and
			# nothing to size against; it is skipped rather than allowed to collapse the clump onto
			# the beacon, which is what returning a zero radius would do.
			if (anchors[j] - anchors[i]).length() <= 1.0e-6:
				continue
			var angle: float = anchors[i].angle_to(anchors[j])
			if first < 0 or angle < closest - 1.0e-6:
				closest = angle
				first = i
				second = j
	if first < 0:
		return 0.0
	var chord: Vector3 = anchors[second] - anchors[first]
	var span: float = chord.length()
	# In the body's OWN frame: it is turned to face its slot (ADR 0034), so the direction of its
	# neighbour is the chord seen from there.
	var toward: Vector3 = (
		(ShipAttach.mount_frame(anchors[first]).inverse() * (chord / span)).normalized()
	)
	var reach: float = _reach_along(room_shape, toward, cfg)
	if reach <= 0.0:
		return 0.0
	# NEVER ASK THE FIELD FOR MORE DEPTH THAN IT HAS. A non-uniformly scaled SDF is a conservative
	# estimate and not a true distance: its deepest reading is bounded by the SMALLEST scale
	# factor, while the tracer above follows the real surface. Squaring a three-to-one cylinder to
	# its span (dev note 2026-09-24) makes the two disagree by just enough to starve this solve -
	# measured, a deepest of 0.667 against a wanted of 0.680 - and the whole clump collapses onto
	# the beacon. Taking the smaller of the two keeps the search on a depth the field can answer
	# for, and changes nothing wherever they agree: on a sphere both read 2.0, and on a box the
	# tracer reads 2.0 against the rounded envelope's 2.04, so the tracer still wins.
	var wanted: float = FUSE_OVERLAP * _solvable_depth(room_shape, reach)
	var near: float = 0.0
	var far: float = reach
	for _step: int in NUCLEUS_SOLVE_STEPS:
		var mid: float = (near + far) * 0.5
		if -room_shape.sdf(toward * mid) >= wanted:
			near = mid
		else:
			far = mid
	return (near + far) / span


## The depth the fuse solve may ask [param room_shape] for, given a tracer reading of [param reach].
##
## A UNIFORMLY SCALED FIELD IS A TRUE DISTANCE and the tracer is the right answer: the reach along
## the chord can exceed the half extent - on a box the diagonal does - and that is real hull, not
## an artefact. A NON-UNIFORM one is only a conservative estimate: its deepest reading anywhere is
## bounded by the SMALLEST scale factor, whatever the tracer finds. Squaring a three-to-one
## cylinder to its span (dev note 2026-09-24) makes the two disagree by just enough to starve the
## solve - measured, a deepest of 0.667 against a wanted of 0.680 - and the whole clump collapses
## onto the beacon.
##
## So the tracer is trusted wherever the field can be, and capped where it cannot. Every family
## that was uniformly scaled before this existed takes the first branch and does not move.
static func _solvable_depth(room_shape: ResolvedShape, reach: float) -> float:
	var s: Vector3 = room_shape.scale
	if is_equal_approx(s.x, s.y) and is_equal_approx(s.y, s.z):
		return reach
	return minf(reach, -room_shape.sdf(Vector3.ZERO))


## How far the surface of [param room_shape] is from its centre along [param dir], read off the
## attach model's own tracer so a template measures a shape exactly as a placement does.
static func _reach_along(room_shape: ResolvedShape, dir: Vector3, cfg: ShipConfig) -> float:
	var probe: ShipPart = ShipPart.new()
	var angles: Vector2 = ShipAttach.angles_from_direction(dir)
	probe.yaw = angles.x
	probe.pitch = angles.y
	return (ShipAttach.anchor_for(room_shape, probe, cfg)["pos"] as Vector3).length()


## A body standing in the slot [param dir] at [param radius] from the beacon, TURNED TO FACE ITS
## SLOT - its own +Y along the direction it stands in, which is where the attach model would have
## pointed it had it been seated from the centre. It matters on a family that is not round: a spar
## nucleus is a starburst of spars, not six parallel ones crossing at the middle.
static func _anchored_at(dir: Vector3, radius: float) -> Transform3D:
	var out: Vector3 = dir.normalized()
	return Transform3D(ShipAttach.mount_frame(out), out * radius)


## THE BEACON (ADR 0033): every class is built AROUND the ship's centre, not off its first module.
## The nucleus is laid out on an arrangement with nothing at its middle (ADR 0017), so the root body
## takes a slot like any other and the middle is empty - "the proper way would be to use a beacon or
## reference node thats invisible but still there where things can grow away from that"
## (2026-09-21). The whole ship is anchored by the root's [member ShipPart.absolute], so shifting
## that by the nucleus' own centroid puts the centre of the core on the beacon and moves everything
## with it. A class whose arrangement does hold a middle body simply lays that body over the beacon.
static func _centre_on_the_beacon(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> void:
	if doc == null or doc.root.is_empty() or not doc.parts.has(doc.root):
		return
	var xforms: Dictionary = ShipAttach.resolve_all(doc, data, cfg)
	var centre: Vector3 = Vector3.ZERO
	var count: int = 0
	# The nucleus: the root module and, once it is the ship's root component (ADR 0024), the bodies
	# expanded under it. Never the extremities - a pod hangs off the core, it is not part of it.
	for key: Variant in xforms.keys():
		var id: String = str(key)
		if ShipSymmetry.is_twin_id(id):
			continue
		if id != doc.root and not id.begins_with(doc.root + "/"):
			continue
		centre += (xforms[id] as Transform3D).origin
		count += 1
	if count == 0:
		return
	var root_part: ShipPart = doc.parts[doc.root]
	var anchored: Transform3D = root_part.absolute
	anchored.origin -= centre / float(count)
	root_part.absolute = anchored


# --- node layout -------------------------------------------------------------------------


## Flattens a template into `[{parent: int, dir: Vector3, element: String, symbol: String}]`, root
## first. The root carries no parent and no direction.
static func _nodes_for(data: ShipData, template_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e: Dictionary = entry(data, template_id)
	if e.is_empty():
		return out
	if kind_of(template_id) == KIND_ELEMENT:
		var id: String = _bare_id(template_id)
		var symbol: String = _text(e.get("symbol"), "")
		var plan: Dictionary = _layout(data, e)
		var nucleus: Array[Vector3] = plan["nucleus"]
		var nucleus_slots: PackedInt32Array = plan["nucleus_slots"]
		var node_of_slot: Dictionary = {}
		var slots: Array[Vector3] = plan["slots"]
		var root_slot_index: int = int(plan["root_slot"])
		# THE NUCLEUS RINGS THE BEACON (ADR 0034): every body stands in its arrangement's own slot,
		# anchored, rather than hanging off the body before it. The slot directions are what the
		# arrangement actually says; the old hang directions could only ever approximate them,
		# because a surface seat lands where the host's normal pushes it - on a box hull, four of a
		# carbon's six bodies slid sideways onto a face and the clump came out lopsided.
		var anchored: bool = root_slot_index >= 0 and slots.size() > root_slot_index
		# The root, then the rest of the nucleus, then the extremities.
		out.append(
			_node(
				0,
				Vector3.UP,
				id,
				symbol,
				LINK_ROOT,
				false,
				slots[root_slot_index] if anchored else Vector3.ZERO
			)
		)
		if root_slot_index >= 0:
			node_of_slot[root_slot_index] = 0
		for i: int in nucleus.size():
			if out.size() >= MAX_NODES:
				break
			var slot: int = nucleus_slots[i] if i < nucleus_slots.size() else -1
			if slot >= 0:
				node_of_slot[slot] = out.size()
			var anchor: Vector3 = Vector3.ZERO
			if anchored and slot >= 0 and slot < slots.size():
				anchor = slots[slot]
			out.append(_node(0, nucleus[i], id, symbol, LINK_FUSE, false, anchor))

		# A POD IS BUILT ON THE PROTON WHOSE SLOT IT SHARES, and continues straight out from it -
		# a tunnel's own +Y already points away from the core, so Vector3.UP here is "keep going".
		# Hanging every pod off the ROOT instead is what the old hub-and-spoke nucleus did, and on
		# a nucleus that fills its arrangement it does not work: the pod's slot is occupied by a
		# proton, so the tunnel would set off straight through it. Measured on a carbon class, a
		# rim proton had eaten the very face its own pod's tunnel was seated on, and the tunnel
		# joint then cut nothing at all.
		var extremity: Array[Vector3] = plan["extremity"]
		var extremity_slots: PackedInt32Array = plan["extremity_slots"]
		for i: int in extremity.size():
			if out.size() >= MAX_NODES:
				break
			var stem: int = 0
			var dir: Vector3 = extremity[i]
			var slot: int = extremity_slots[i] if i < extremity_slots.size() else -1
			var world: bool = false
			if node_of_slot.has(slot):
				# On its own proton, reaching along the SLOT'S direction in ship space - level for
				# a rim slot - not along whatever the proton's +Y turned out to be.
				stem = int(node_of_slot[slot])
				world = true
			out.append(_node(stem, dir, id, symbol, LINK_TUNNEL, world))
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
		var dirs: Array[Vector3] = extremity_dirs(data, parent_element)
		var slot: int = int(spec.get("slot", 0))
		var dir: Vector3 = Vector3.UP
		if not dirs.is_empty():
			dir = dirs[posmod(slot, dirs.size())]
		out.append(_node(parent_index, dir, element_id, symbol))
	return out


static func _node(
	parent: int,
	dir: Vector3,
	element_id: String,
	symbol: String,
	link: String = LINK_TUNNEL,
	world: bool = false,
	anchor: Vector3 = Vector3.ZERO
) -> Dictionary:
	return {
		"parent": parent,
		"dir": dir,
		"element": element_id,
		"symbol": symbol,
		"link": link,
		"world": world,
		# THE SLOT THIS BODY STANDS IN, as a unit direction from the beacon - zero for a body that
		# is placed on a surface instead (ADR 0034). The radius is [method _nucleus_radius]'s.
		"anchor": anchor,
	}


## [param dir], a direction in SHIP space, expressed in the frame [param parent_id] actually stands
## in - which is only known once the parts placed so far have been resolved.
##
## A part's own +Y is the mount normal where it landed on its parent, and that depends on the
## FAMILY: on a box a 30-degree ray strikes a side face and the normal is level; on a sphere the
## normal is the ray itself and the part tilts 30 degrees. A pod told to continue along its proton's
## +Y therefore reached level on a box hull and down on a sphere hull - "the sphere one has the
## electron pods all angled down below the craft making a pyrimid. all shaped hull versions should
## look the same" (2026-09-05). Naming the direction in ship space and converting it here is what
## makes every family lay out alike.
static func _local_direction(
	doc: ShipDoc, data: ShipData, conf: ShipConfig, parent_id: String, dir: Vector3
) -> Vector3:
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, conf)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, conf)
	if not xforms.has(parent_id):
		return dir
	var basis: Basis = (xforms[parent_id] as Transform3D).basis.orthonormalized()
	var local: Vector3 = basis.inverse() * dir
	return local.normalized() if local.length_squared() > 1.0e-12 else dir


## Nucleus body count of an element entry: one per proton, capped at [constant MAX_NUCLEUS].
static func nucleus_count(element: Dictionary) -> int:
	return clampi(int(_num(element.get("z"), 1.0)), 1, MAX_NUCLEUS)


## Extremity count: one per valence electron, and NONE in period 1 - a closed first shell has
## nothing outside it, which is what makes hydrogen a single module and helium a fused pair.
static func extremity_count(element: Dictionary) -> int:
	if int(_num(element.get("period"), 1.0)) <= 1:
		return 0
	return clampi(int(_num(element.get("valence"), 0.0)), 0, MAX_NUCLEUS)


## Every body of a class, nucleus and extremities together. What the volume budget is divided by.
static func body_count(element: Dictionary) -> int:
	return maxi(nucleus_count(element) + extremity_count(element), 1)


## Where every body of a class goes, as
## `{"nucleus": Array[Vector3], "nucleus_slots": PackedInt32Array, "extremity":
## Array[Vector3], "extremity_slots": PackedInt32Array, "root_slot": int}`.
##
## THE NUCLEUS SITS ON AN ARRANGEMENT, IT IS NOT WRAPPED AROUND A BODY AT THE CENTRE. The
## arrangement holding as many slots as the class has protons is chosen, the root takes the slot
## nearest straight up, and every other slot becomes a direction FROM the root's slot to it. A
## carbon class is six bodies on an octahedron: "the central one should be the singular top, and the
## 4 rim and lower added" (2026-09-04). The rim comes out at 45 degrees down and out, the sixth
## straight down, and the root's whole upper half stays in the open air.
##
## THE EXTREMITIES TAKE SLOTS OF THAT SAME ARRANGEMENT - "the valance electron count should be half
## or full resonant to the structure of protons at all times" - most perpendicular to the root's
## slot first, which puts them around the waist. A carbon class hangs its four valence pods on the
## four rim slots of the octahedron its six protons sit on; a neon class fills all eight slots of
## the cube. Ties fall to the earlier slot, for determinism (AGENTS section 8b).
##
## `nucleus_slots` and `extremity_slots` say WHICH slot each body took, which is how a pod finds the
## proton it belongs to: [method _nodes_for] builds it on that body rather than on the root, so the
## tunnel continues the line the proton is already on instead of cutting across it. -1 means the
## slot is not known, which happens only on the fallback below.
##
## RETIRED(ADR 0017, 2026-09-04): the arrangement holding `count - 1`, spread around a body at the
## centre. That body ends up buried under its own neighbours - "the central completely burried one
## still exists and thats incorrect" - and the seams that bury it then hollow its hull away to
## slivers. A cluster with nothing at its centre has no such body to lose. The body COUNT is
## unchanged either way: one root plus `count - 1` directions.
## [param order] rearranged so each slot is followed immediately by its mirror across X, when the
## arrangement holds one.
##
## A class takes the FIRST `wanted` of this list, so what matters is that every PREFIX is as
## balanced as it can be: an even one exactly, an odd one off by the single arm that has no
## partner. Without it the waist-first order can hand out several arms on the same side - measured,
## a silicon put all three of its arms at x = +6.4 - and the ship comes out lopsided left to right,
## which is the one asymmetry the author's rule forbids a prebuild ("we need symetry across at
## least 1 axis with reguards to our prebuilds ... with a left-right being a min", 2026-09-24).
##
## The waist-first preference is kept: pairing only reorders within it, so an arm still goes to the
## most reachable berth available.
static func _mirror_paired(slots: Array[Vector3], order: Array[int], wanted: int) -> Array[int]:
	var out: Array[int] = []
	var taken: Dictionary = {}
	# AN ODD COUNT NEEDS ONE ARM THAT IS ITS OWN MIRROR, and it has to be inside the prefix or the
	# ship is lopsided by a whole arm. Every arrangement with an odd number of berths has such a
	# slot once it is rotated to sit square on X, so this is a real berth and not a compromise; a
	# cubic nucleus has none, and a class wanting an odd number of arms off one cannot be balanced
	# left to right by slot choice at all.
	if wanted % 2 == 1:
		for index: int in order:
			if _mirror_slot(slots, index) == index:
				taken[index] = true
				out.append(index)
				break
	for index: int in order:
		if taken.has(index):
			continue
		var partner: int = _mirror_slot(slots, index)
		if partner == index:
			# Another self-mirrored berth: it balances alone, but taking it here would unpair the
			# rest, so it waits for the sweep below.
			continue
		taken[index] = true
		out.append(index)
		if partner >= 0 and not taken.has(partner):
			taken[partner] = true
			out.append(partner)
	for index: int in order:
		if not taken.has(index):
			taken[index] = true
			out.append(index)
	return out


## The slot holding [param index]'s reflection across X: [param index] itself when the slot sits ON
## the plane and so is its own mirror, or -1 when the arrangement holds no reflection of it.
static func _mirror_slot(slots: Array[Vector3], index: int) -> int:
	if index < 0 or index >= slots.size():
		return -1
	var want: Vector3 = slots[index]
	want.x = -want.x
	if slots[index].distance_squared_to(want) <= MIRROR_SLOT_EPSILON:
		return index
	for i: int in slots.size():
		if i != index and slots[i].distance_squared_to(want) <= MIRROR_SLOT_EPSILON:
			return i
	return -1


static func _layout(data: ShipData, element: Dictionary) -> Dictionary:
	var count: int = nucleus_count(element)
	var nucleus: Array[Vector3] = []
	var nucleus_slots: PackedInt32Array = PackedInt32Array()
	var slots: Array[Vector3] = _dirs_of(data, _arrangement_holding(data, count))
	var root: int = -1
	if count > 1 and slots.size() >= count:
		root = root_slot(slots)
		for i: int in slots.size():
			if i == root or nucleus.size() >= count - 1:
				continue
			var hang: Vector3 = _hang_direction(slots, root, i)
			if hang.length_squared() <= 1.0e-12:
				continue
			nucleus.append(hang)
			nucleus_slots.append(i)
	elif count > 1:
		# No arrangement in the pack is big enough. Fall back to the old hub and spoke rather than
		# hand back a short nucleus: a class with fewer bodies than its Z is a worse answer than a
		# class with a body in the middle.
		var spokes: Array[Vector3] = _dirs_of(data, _arrangement_holding(data, count - 1))
		for i: int in mini(count - 1, spokes.size()):
			nucleus.append(spokes[i])
			nucleus_slots.append(-1)

	var extremity: Array[Vector3] = []
	var extremity_slots: PackedInt32Array = PackedInt32Array()
	var wanted: int = extremity_count(element)
	if wanted > 0 and root >= 0 and slots.size() >= wanted:
		var up: Vector3 = slots[root]
		var order: Array[int] = []
		for i: int in slots.size():
			order.append(i)
		order.sort_custom(func(a: int, b: int) -> bool: return _waist_first(slots, up, a, b))
		order = _mirror_paired(slots, order, wanted)
		for i: int in wanted:
			extremity.append(slots[order[i]])
			extremity_slots.append(order[i])
	elif wanted > 0:
		# Too few slots to be resonant with: the PERIOD's own arrangement, stepped up to a larger
		# one when even that has too few berths.
		var period: int = int(_num(element.get("period"), 1.0))
		var name: String = _text(
			_dict_of(_dict_of(_pack(data).get(SECTION_PERIODS)).get(str(period))).get(
				"arrangement"
			),
			""
		)
		var dirs: Array[Vector3] = _dirs_of(data, name)
		if dirs.size() < wanted:
			dirs = _dirs_of(data, _arrangement_holding(data, wanted))
		for i: int in mini(wanted, dirs.size()):
			extremity.append(dirs[i])
			extremity_slots.append(-1)

	return {
		"nucleus": nucleus,
		"nucleus_slots": nucleus_slots,
		"extremity": extremity,
		"extremity_slots": extremity_slots,
		"root_slot": root,
		"slots": slots,
	}


## The direction the body in slot [param i] hangs off the root in.
##
## EVERY FUSED BODY SITS THE SAME DISTANCE FROM THE ROOT - the attach model seats it at one depth
## along the mount normal - so the arrangement's vertices cannot be reproduced as such: a body at
## the octahedron's far pole is twice as far from the top as one on its rim. What can be kept is
## the slot's BEARING and the slot's HEIGHT, taken as a fraction of the way from the top of the
## arrangement to its bottom. A rim slot at the equator is halfway down, so it is hung at the
## direction whose fall is half its length - 30 degrees below level - and lands halfway between the
## top body and the bottom one: "the 4 rim protons are not vertically centered between the top and
## bottom proton" (2026-09-04).
##
## Thirty degrees on a box root also strikes a SIDE face rather than an edge, so the rim body
## mounts level and the pod that grows out of it reaches sideways, not down. The old bearing -
## straight from the top vertex to the rim vertex, 45 degrees - ran exactly along the box's edge,
## where the surface normal is diagonal, which is why every valence pod pointed 45 degrees at the
## floor.
##
## A slot at the very bottom AND off to one side - the far corners of a cube - has no direction
## that puts it right at one seating depth; it keeps its plain bearing from the root rather than
## being folded onto the axis with the others.
static func _hang_direction(slots: Array[Vector3], root: int, i: int) -> Vector3:
	var rel: Vector3 = slots[i] - slots[root]
	var flat: Vector3 = Vector3(rel.x, 0.0, rel.z)
	var lowest: float = slots[root].y
	for slot: Vector3 in slots:
		lowest = minf(lowest, slot.y)
	var span: float = slots[root].y - lowest
	if span <= 1.0e-6:
		return rel.normalized()
	var drop: float = clampf((slots[root].y - slots[i].y) / span, 0.0, 1.0)
	if flat.length_squared() <= 1.0e-12:
		return Vector3.DOWN if drop > 0.0 else rel.normalized()
	var reach: float = sqrt(maxf(1.0 - drop * drop, 0.0))
	if reach <= 0.05:
		return rel.normalized()
	return (flat.normalized() * reach + Vector3.DOWN * drop).normalized()


## Slot [param a] before slot [param b] when the pods are handed out: most perpendicular to the
## root's own slot first, so they land around the waist rather than on top of the cluster. The
## index breaks a tie, because determinism is a gate.
static func _waist_first(slots: Array[Vector3], up: Vector3, a: int, b: int) -> bool:
	var ka: float = absf(slots[a].dot(up))
	var kb: float = absf(slots[b].dot(up))
	if absf(ka - kb) > 1.0e-6:
		return ka < kb
	return a < b


## Which slot of [param dirs] the root body takes: the one nearest straight up, so a cluster reads
## as a top with the rest hung below it. Ties fall to the earlier slot.
static func root_slot(dirs: Array[Vector3]) -> int:
	var best: int = 0
	for i: int in dirs.size():
		if dirs[i].y > dirs[best].y + 1.0e-6:
			best = i
	return best


## Directions the fused nucleus bodies sit in, measured FROM THE ROOT BODY - one fewer than the
## count, because the root is one of them. See [method _layout].
static func nucleus_dirs(data: ShipData, count: int) -> Array[Vector3]:
	return _layout(data, {"z": count, "period": 1.0, "valence": 0.0})["nucleus"]


## Directions the extremities reach in - the arrangement SLOTS they take. See [method _layout].
static func extremity_dirs(data: ShipData, element: Dictionary) -> Array[Vector3]:
	return _layout(data, element)["extremity"]


## The name of the smallest arrangement in the pack with at least [param wanted] directions.
##
## Sorted by (direction count, name) rather than trusting the pack's own key order, because
## determinism is a gate (AGENTS section 8b) and two arrangements of the same size - linear and
## bent, trigonal and pyramidal - would otherwise be picked between by whichever the parser
## happened to hand back first.
static func _arrangement_holding(data: ShipData, wanted: int) -> String:
	var names: Array[String] = []
	for key: Variant in _dict_of(_pack(data).get(SECTION_ARRANGEMENTS)):
		names.append(str(key))
	names.sort()
	var best: String = ""
	var best_size: int = 0
	for name: String in names:
		var size: int = _dirs_of(data, name).size()
		if size < wanted:
			continue
		if best.is_empty() or size < best_size:
			best = name
			best_size = size
	return (
		best if not best.is_empty() else (names[names.size() - 1] if not names.is_empty() else "")
	)


## The span a module of [param family] needs to enclose [param target] cubic metres.
##
## Solved rather than assumed, because a box and a sphere of the same span are nowhere near the
## same volume and the classes are defined by VOLUME. Volume goes as the cube of the span, so one
## measurement at a reference span fixes the curve: the shape is tessellated once by [ShapeMesh]
## and scaled from there. Exact for the flat-faced families and correct to the tessellation for
## the round ones, which is the same standard the bake itself is held to.
static func _span_for_volume(
	data: ShipData, family: String, manufacturer: String, target: float
) -> float:
	var reference: float = 1.0
	# MEASURED THE WAY A NODE IS ACTUALLY SCALED, or the budget is a budget for a shape nothing
	# builds - a cylinder squared to its span holds twice what a uniformly scaled one does.
	var shape: ResolvedShape = _resolved(
		data, family, manufacturer, _node_span(data, family, manufacturer, reference)
	)
	var volume: float = ShapeMesh.build(shape).volume()
	if volume <= 0.0 or target <= 0.0:
		return reference
	return reference * pow(target / volume, 1.0 / 3.0)


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
## The scale a NODE wears - a room or a proton, never a tunnel. [param span] is the size of the
## room, and the author asked for that to mean the same thing whatever shape is in the slot:
##
## > "when cylinder nodes (not linkage tunnels) is selected in pre built options, it should have
## > the length and diameter equal and set to room size not tunnel bore, as an earlier test
## > indicated that it made tiny bore rooms."
##
## [method _uniform_span] makes the WIDEST axis the span, so a cylinder whose unscaled box is
## twice as long as it is wide comes out at HALF the bore that was asked for - the tiny bore the
## note reports. Squaring the box to `span` on every axis gives length == diameter == span, and
## for a shape whose box is already cubic - a sphere, a box - the two rules agree exactly, so
## nothing that was right before moves.
static func _node_span(
	data: ShipData, family_id: String, manufacturer_id: String, span: float
) -> Vector3:
	var box: Vector3 = _unscaled_size(data, family_id, manufacturer_id)
	if span <= 0.0:
		return Vector3.ONE
	return Vector3(
		span / box.x if box.x > 0.0 else 1.0,
		span / box.y if box.y > 0.0 else 1.0,
		span / box.z if box.z > 0.0 else 1.0
	)


## WHICH SHAPE EACH NODE WEARS, as `{node index: family id}`. The nucleus bodies take the proton
## pair and everything on a tunnel takes the electron pair; with no second family named, a group
## is one shape throughout and this is a constant map.
##
## THE BLEND ALTERNATES PAIR BY PAIR. A node and its mirror always come out the same shape, so a
## blended cluster is exactly as symmetric as an unblended one - "the system will try to keep
## everything semetrical and even as normal" - and ADR 0044's balance still holds. Alternating
## body by body would put a cube opposite a sphere and move the centre of mass off the plane.
static func _blend_families(
	data: ShipData,
	nodes: Array[Dictionary],
	proton_a: String,
	proton_b: String,
	electron_a: String,
	electron_b: String
) -> Dictionary:
	var protons: PackedInt32Array = PackedInt32Array()
	var electrons: PackedInt32Array = PackedInt32Array()
	for i: int in nodes.size():
		# Node 0 is the root and always a nucleus body; the rest go by their link.
		if i == 0 or _text(nodes[i].get("link"), LINK_TUNNEL) == LINK_FUSE:
			protons.append(i)
		else:
			electrons.append(i)
	var out: Dictionary = {}
	_blend_group(data, nodes, protons, proton_a, proton_b, out)
	_blend_group(data, nodes, electrons, electron_a, electron_b, out)
	return out


## One group blended into [param out]. A second family that is empty, unknown to the pack, or the
## same as the first leaves the group on one shape.
static func _blend_group(
	data: ShipData,
	nodes: Array[Dictionary],
	group: PackedInt32Array,
	first: String,
	second: String,
	out: Dictionary
) -> void:
	var both: bool = (
		not second.is_empty() and second != first and data != null and data.family_ids().has(second)
	)
	if not both:
		for index: int in group:
			out[index] = first
		return
	var turn: int = 0
	for index: int in group:
		if out.has(index):
			continue
		out[index] = first if turn % 2 == 0 else second
		var partner: int = _mirror_node(nodes, group, index)
		if partner >= 0 and partner != index:
			out[partner] = out[index]
		turn += 1


## The mirror partner of node [param index] within [param group], the node itself when it stands
## on the mirror plane, or -1. Pairs on the node's own BERTH - its anchor where it has one (a
## nucleus body is anchored in its slot, ADR 0034) and its branch direction otherwise - through
## the same [method _mirror_slot] the arm ordering uses, so one rule decides both.
static func _mirror_node(nodes: Array[Dictionary], group: PackedInt32Array, index: int) -> int:
	var berths: Array[Vector3] = []
	var at: int = -1
	for i: int in group.size():
		if group[i] == index:
			at = i
		berths.append(_berth_of(nodes[group[i]]))
	if at < 0:
		return -1
	var found: int = _mirror_slot(berths, at)
	return group[found] if found >= 0 else -1


## Where a node sits, for mirroring: its anchor when it has one, its branch direction otherwise.
static func _berth_of(node: Dictionary) -> Vector3:
	var anchor: Vector3 = node.get("anchor", Vector3.ZERO)
	return anchor if anchor.length_squared() > 0.0 else node.get("dir", Vector3.UP)


## Every family the blend named, resolved once: `{family id: {family, mfr, scale, shape}}`. Built
## from the blend AND from the four options, so a class with no electrons still resolves the
## electron family the tunnel is measured against.
static func _kits_for(
	data: ShipData, family_of: Dictionary, span: float, named: PackedStringArray
) -> Dictionary:
	var out: Dictionary = {}
	var wanted: PackedStringArray = PackedStringArray()
	for index: Variant in family_of:
		wanted.append(str(family_of[index]))
	wanted.append_array(named)
	for family: String in wanted:
		if family.is_empty() or out.has(family):
			continue
		var mfr: String = _first_manufacturer(data, family)
		var scale: Vector3 = _node_span(data, family, mfr, span)
		out[family] = {
			"family": family,
			"mfr": mfr,
			"scale": scale,
			"shape": _resolved(data, family, mfr, scale)
		}
	return out


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


## The family at scale one, measured on THE MESH THAT GETS BUILT rather than on the field around
## it (ADR 0040).
##
## `ResolvedShape.local_aabb()` is the envelope of the signed distance field, and the tessellation
## sits inside it by the family's own rounding - the same gap F34 records for door fields. Sizing
## against the envelope therefore builds everything short of what was asked, by a factor that
## differs per family: measured at scale one, `box_hull` predicts 2.04 and builds 2.00 (0.98),
## `sphere_pod` 2.00 and 1.95 (0.975), `torus_ring` 4.00 and 4.00 (1.000), and `cylinder_spar` -
## which is what a hallway is - predicts 1.20 and builds 1.00, **0.833**. A tunnel asked for a 1.4 m
## bore was therefore built 1.166 m across, its cavity 0.766, and the widest hatch it would take
## 0.568 m: "the hatches on here are visually only about .33m acrost" (2026-09-24).
##
## Measuring the mesh costs one tessellation per size query, which [method _span_for_volume]
## already pays to weigh a shape, so nothing here is newly expensive.
static func _unscaled_size(data: ShipData, family_id: String, manufacturer_id: String) -> Vector3:
	var shape: ResolvedShape = _resolved(data, family_id, manufacturer_id, Vector3.ONE)
	var built: PolyMesh = ShapeMesh.build(shape)
	return built.aabb().size if not built.is_empty() else shape.local_aabb().size


## The family at its default params under `scale`, resolved.
static func _resolved(
	data: ShipData, family_id: String, manufacturer_id: String, scale: Vector3
) -> ResolvedShape:
	var params: Dictionary = ShapeGen.default_params(data, family_id, manufacturer_id)
	return ShapeGen.resolve(data, family_id, manufacturer_id, params, scale)


# --- joints ------------------------------------------------------------------------------


## The joint between two parts of a template. "a hatch between each hallway/tunnel and room and
## room to room connection" — so this is not discovered, it is authored, and every template
## connection gets one.
##
## THE HATCH IS ALWAYS WRITTEN IN; [param mode] only decides whether it is BUILT. A link left
## OPEN - which is the default since 2026-09-26 - still carries its family and its params, so the
## player who wants a wall there has one edit to make and nothing to choose. That is the whole of
## "for user ease, when they are adding walls to their proton chunk".
static func _hatch(
	doc: ShipDoc,
	a: String,
	b: String,
	hatch_family: String,
	data: ShipData,
	mode: String = ShipJoint.MODE_OPEN
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
	joint.mode = mode
	joint.hatch_family = hatch_family
	joint.hatch_params = _hatch_defaults(data, hatch_family)
	doc.joints[joint.id] = joint


## Default params for a hatch family, read straight off the pack's own ranges. A hatch record with
## empty params would resolve to nothing the day the hatch geometry is implemented.
## The nucleus - the root and the bodies fused into it - is ONE COMPONENT, the ship's root
## instance (ADR 0024): click one proton and the clump is selected, double-click and it opens,
## and it is in the palette to place again. Its chunks are linked OPEN in the definition (ADR
## 0025) - one room by default, and every link editable. Every node that named a nucleus body
## now names its inner part ("<instance>/<inner>") so tunnels hang off the proton they were laid
## out for; the top body is the instance's own proxy.
static func _lift_nucleus(
	doc: ShipDoc,
	data: ShipData,
	cfg: ShipConfig,
	nucleus_ids: PackedStringArray,
	part_of_node: PackedStringArray,
	symbol: String
) -> PackedStringArray:
	var names: Dictionary = {}
	for id: String in nucleus_ids:
		names[id] = (doc.parts[id] as ShipPart).display_name
	var label: String = "%s NUCLEUS" % symbol.to_upper() if not symbol.is_empty() else "NUCLEUS"
	var component_id: String = ShipComponents.make_component(doc, nucleus_ids, label)
	if component_id.is_empty():
		return part_of_node
	var instance_id: String = doc.root
	# Like every part the template makes: no mirror twins of the clump or of its protons.
	(doc.parts[instance_id] as ShipPart).asymmetric = true
	var definition: Dictionary = doc.components[component_id]
	var inner: Dictionary = ShipComponents.definition_parts(definition)
	var root_inner: String = str(definition.get("root", ""))
	var inner_by_name: Dictionary = {}
	for inner_id: String in inner:
		inner_by_name[(inner[inner_id] as ShipPart).display_name] = inner_id
	# OPEN by default (ADR 0025): every pair of the clump that meets gets an open joint IN the
	# definition, where the player can change it like any other link.
	var keys: PackedStringArray = PackedStringArray([instance_id])
	for inner_id: String in inner:
		if inner_id != root_inner:
			keys.append(instance_id + "/" + inner_id)
	for pair: PackedStringArray in _clump_pairs(doc, data, cfg, keys):
		var joint: ShipJoint = ShipJoint.new()
		joint.mode = ShipJoint.MODE_OPEN
		ShipComponents.set_inner_joint(doc, pair[0], pair[1], joint)
	var out: PackedStringArray = PackedStringArray(part_of_node)
	for node_index: int in out.size():
		var old_id: String = out[node_index]
		if not names.has(old_id):
			continue
		var inner_id: String = str(inner_by_name.get(names[old_id], ""))
		if inner_id.is_empty() or inner_id == root_inner:
			out[node_index] = instance_id
		else:
			out[node_index] = instance_id + "/" + inner_id
	return out


## Every pair of the clump that is linked: the ones that stand on each other, and - since the bodies
## ring the beacon and stand on nothing (ADR 0034) - every pair whose SOLIDS ACTUALLY MEET. Without
## the second half an anchored nucleus would carry no links at all, and each body would bake as a
## room of its own, shelled and walled against the neighbours it is fused into.
static func _clump_pairs(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, keys: PackedStringArray
) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var seen: Dictionary = {}
	for pair: PackedStringArray in ShipSeams.pairs_within(doc, keys):
		seen[ShipDoc.joint_key_for(pair[0], pair[1])] = true
		out.append(pair)
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
	var thickness: float = maxf(cfg.hull_thickness_m, 0.0) if cfg != null else 0.0
	for i: int in keys.size():
		for j: int in range(i + 1, keys.size()):
			var a: String = keys[i]
			var b: String = keys[j]
			if seen.has(ShipDoc.joint_key_for(a, b)):
				continue
			if not shapes.has(a) or not shapes.has(b) or not xforms.has(a) or not xforms.has(b):
				continue
			var state: Dictionary = ShipJoints.solid_pair_state(
				shapes[a], xforms[a], shapes[b], xforms[b], thickness
			)
			if not bool(state.get("overlaps", false)):
				continue
			seen[ShipDoc.joint_key_for(a, b)] = true
			out.append(PackedStringArray([a, b]))
	return out


## The element symbol the template's nodes carry ("C" for carbon), for the nucleus's label.
static func _symbol_of(nodes: Array[Dictionary]) -> String:
	if nodes.is_empty():
		return ""
	return _text(nodes[0].get("symbol"), "")


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

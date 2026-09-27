class_name ShipSeamMenu
extends RefCounted
## THE SEAM STYLE MENU (ADR 0009/0013) - right-click a selection, change the shape of every
## connection inside it. The whole feature: the catalogue of styles, the menu, which connections
## the selection implies, and the single edit that applies one style to all of them.
##
## A HOME OF ITS OWN, and by the criterion `.gdlintrc` states rather than by where line 2000 fell:
## "a self-contained, statically testable unit with no reference back to the file it came from."
## It reaches the builder through nothing but its PUBLIC surface - `get_doc()`, `get_selection()`,
## `get_view()`, `set_status()`, `begin_edit()`, `commit_edit()` - so it borrows no private state
## and leaves none behind. 188 lines came out of `ship_builder.gd` with it, which had been sitting
## at 1999 of its 2000 and blocking the roadmap three steps deep (FOLLOWUPS F57).
##
## The author asked for exactly this: "we keep running into that budget so do a grand seperation so
## we can have more room ... i know some of this is in benifite of agentic work having smaller more
## modular structures."

## The six seam styles, laid out as the TWO AXES they are (ADR 0013): which solid indents the
## other, and what the linkage surface is. A `header` entry is a heading rather than a choice.
##
## STRING LITERALS RATHER THAN ShipJoint's CONSTANTS, carried over verbatim with the table: a
## class-level const that names another class_name is a load-order hazard, and this one is read
## while the menu is being built. They ARE `ShipJoint.SEAM_*`.
##
## RETIRED(ADR 0013, 2026-09-04): a flat list of six names drawn from two unrelated schemes - two
## of them by the attach tree ("PARENT INDENTS CHILD") and four by a plane position ("IN-BUMP
## SLICE"). Same six behaviours, one scheme: "i think its more appropriate to classify it as big
## indents small, or small indents big. then to append on the toggles with that of flat inserted,
## flat cutoff, or native inserted."
const SEAM_STYLE_ITEMS: Array = [
	{"header": "SMALL INDENTS BIG"},
	{"id": "small_flat_insert", "label": "FLAT INSERTED"},
	{"id": "small_flat_cutoff", "label": "FLAT CUTOFF"},
	{"id": "small_native", "label": "NATIVE INSERTED"},
	{"header": "BIG INDENTS SMALL"},
	{"id": "big_flat_insert", "label": "FLAT INSERTED"},
	{"id": "big_flat_cutoff", "label": "FLAT CUTOFF"},
	{"id": "big_native", "label": "NATIVE INSERTED"},
]

var _builder: ShipBuilder = null
var _menu: ShipContextMenu = null
var _pairs: Array[PackedStringArray] = []


func _init(builder: ShipBuilder, theme: ShipTheme) -> void:
	_builder = builder
	_menu = ShipContextMenu.new()
	_menu.name = "ContextMenu"
	_menu.setup(theme)
	_menu.chosen.connect(_on_chosen)
	if builder != null:
		builder.add_child(_menu)


## The live menu, for `tools/ship_check_views.gd`, which drives it to prove the styles reach the
## document. Kept as an accessor rather than a member on the builder so the tool has one honest
## way in rather than a name to guess at.
func menu() -> ShipContextMenu:
	return _menu


## Right-clicking a selection offers the seam styles for every connection INSIDE it.
##
## ANY NUMBER OF PARTS, not two: "add ability to select as many modules as desired, right click and
## change the connection surfaces for all at same time even if they differed before." A connection
## counts when BOTH of its ends are selected, which is the reading that generalises the old
## two-part behaviour exactly - select a pair and you get their one seam, select a chain and you
## get every seam along it, and a part selected on its own has no connection to anything else in
## the selection and so offers nothing.
##
## Where the chosen ones do not already agree, nothing is marked as current, because none of them
## is.
func open_at(position: Vector2) -> void:
	var doc: ShipDoc = _doc()
	var view: ShipView3D = _builder.get_view() if _builder != null else null
	if doc == null or _menu == null or view == null or view.is_exploded():
		return
	var chosen: Dictionary = {}
	for raw: String in _builder.get_selection():
		var pid: String = ShipSymmetry.source_of_twin(raw)
		if doc.parts.has(pid):
			chosen[pid] = true
	# Inner parts of a component included (ADR 0025): pairs_within knows what hangs off what.
	_pairs = ShipSeams.pairs_within(doc, PackedStringArray(chosen.keys()))
	if _pairs.is_empty():
		if chosen.size() > 1:
			_builder.set_status("NONE OF THOSE PARTS ARE CONNECTED TO EACH OTHER")
		return

	var items: Array[Dictionary] = []
	for item: Dictionary in SEAM_STYLE_ITEMS:
		items.append(item)
	# The position arrives in the 3D VIEW's coordinates and the menu lives under the builder:
	# carry it across, or a menu opened at the pointer lands wherever the two frames differ by.
	var offset: Vector2 = (
		view.get_global_transform_with_canvas().origin
		- _builder.get_global_transform_with_canvas().origin
	)
	var title: String = (
		"SEAM: %s <-> %s" % [_label(_pairs[0][0]).to_upper(), _label(_pairs[0][1]).to_upper()]
	)
	if _pairs.size() > 1:
		title = "%d SEAMS" % _pairs.size()
	_menu.open(position + offset, title, items, _common_style())


## The id of the joint over the unordered pair, or "". Static and doc-taking, so the builder's own
## link cycling reaches it without either of them owning the other.
static func joint_id_for(doc: ShipDoc, a: String, b: String) -> String:
	if doc == null:
		return ""
	var key: String = ShipDoc.joint_key_for(a, b)
	for jid: String in doc.joints:
		var joint: ShipJoint = doc.joints[jid]
		if ShipDoc.joint_key_for(joint.a, joint.b) == key:
			return jid
	return ""


## The menu label for a style, qualified by the group it sits under.
##
## SEAM_STYLE_ITEMS carries heading rows as well as choices (ADR 0013), and a heading has no id -
## reading one cost a runtime error the PASSED banner said nothing about, which is exactly the
## case AGENTS section 8a exists for.
static func style_label(style: String) -> String:
	var group: String = ""
	for item: Dictionary in SEAM_STYLE_ITEMS:
		if item.has("header"):
			group = str(item["header"])
			continue
		if str(item.get("id", "")) == style:
			var label: String = str(item.get("label", style))
			return label if group.is_empty() else "%s - %s" % [group, label]
	return style.to_upper()


func _doc() -> ShipDoc:
	return _builder.get_doc() if _builder != null else null


## The style every chosen connection already carries, or "" when they differ - which is what the
## menu shows as "no current choice" rather than picking one of them to look current.
func _common_style() -> String:
	var common: String = ""
	for pair: PackedStringArray in _pairs:
		var style: String = _style_of(pair[0], pair[1])
		if common.is_empty():
			common = style
		elif common != style:
			return ""
	return common


func _style_of(a: String, b: String) -> String:
	return ShipSeams.style_for(_doc(), a, b)


## Applies one style to every connection the menu was opened over, as a SINGLE edit - so a
## selection of a dozen seams is one undo, not a dozen.
func _on_chosen(style: String) -> void:
	if _doc() == null or _pairs.is_empty():
		return
	var live: Array[PackedStringArray] = []
	for pair: PackedStringArray in _pairs:
		if _alive(pair[0]) and _alive(pair[1]):
			live.append(pair)
	if live.is_empty():
		_builder.set_status("THOSE PARTS ARE GONE")
		return
	if live.size() == 1 and _style_of(live[0][0], live[0][1]) == style:
		_builder.set_status("SEAM ALREADY %s" % style_label(style))
		return

	_builder.begin_edit("seam style")
	var changed: int = 0
	for pair: PackedStringArray in live:
		if _apply(pair[0], pair[1], style):
			changed += 1
	_builder.commit_edit(PackedStringArray())
	if live.size() == 1:
		_builder.set_status(
			(
				"SEAM %s <-> %s: %s"
				% [_label(live[0][0]).to_upper(), _label(live[0][1]).to_upper(), style_label(style)]
			)
		)
	else:
		_builder.set_status("%d OF %d SEAMS -> %s" % [changed, live.size(), style_label(style)])


## Sets one connection's style, creating the joint record if the pair never had one. Returns
## whether anything actually moved.
func _apply(a: String, b: String, style: String) -> bool:
	if _style_of(a, b) == style:
		return false
	var doc: ShipDoc = _doc()
	# Two chunks of one component: the style lives in the definition's joint (ADR 0025).
	if ShipSeams.within_one_instance(doc, a, b):
		var inner: ShipJoint = ShipComponents.inner_joint_for(doc, a, b)
		if inner == null:
			inner = ShipJoint.new()
			inner.mode = ShipJoint.MODE_SEALED
		inner.seam_style = style
		return ShipComponents.set_inner_joint(doc, a, b, inner)
	var existing: String = joint_id_for(doc, a, b)
	var joint: ShipJoint = null
	if existing.is_empty():
		# A style needs a record to live on. A pair with no joint is a WALL, so the record this
		# creates says exactly what was already true and changes only the seam's SHAPE.
		joint = ShipJoint.new()
		joint.id = doc.new_joint_id()
		joint.a = a if a <= b else b
		joint.b = b if a <= b else a
		joint.mode = ShipJoint.MODE_SEALED
		doc.joints[joint.id] = joint
	else:
		joint = doc.joints[existing]
	joint.seam_style = style
	return true


## A document part, or an inner part of a component (ADR 0024).
func _alive(pid: String) -> bool:
	var doc: ShipDoc = _doc()
	return doc.parts.has(pid) or ShipComponents.inner_exists(doc, pid)


## A part's display name, or its id when it has none.
func _label(pid: String) -> String:
	var part: ShipPart = _doc().part_at(pid)
	if part == null:
		return pid
	return part.display_name if not part.display_name.is_empty() else pid

# SketchUp-true definition + instances (SPEC section 6): make_component lifts parts into a
# shared definition, instantiate drops a live-linked copy, make_unique detaches exactly one
# instance from further definition edits, and check_cycles catches self-containment.
class_name TestComponents
extends GdUnitTestSuite
var _data: ShipData
var _cfg: ShipConfig = ShipConfig.defaults()
var _family_id: String
var _manufacturer_id: String


## TEMPLATE LINKS ARE OPEN BY DEFAULT since 2026-09-26 ("by default in the prebuilds we dont want
## any walls in our prebuilds by default"). This suite is about what a ship with LINKS does - its
## walls, its doors, the rooms they bound or the meshes they cut - so it asks for the hatches the
## templates used to place, instead of resting on a default that no longer says that.
func _linked(extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {ShipTemplates.OPT_LINK_MODE: ShipJoint.MODE_HATCHED}
	out.merge(extra)
	return out


func before() -> void:
	_data = ShipData.new()
	var ok: bool = _data.load_all()
	(
		assert_bool(ok)
		. append_failure_message(
			"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
		)
		. is_true()
	)
	var families: PackedStringArray = _data.family_ids()
	(
		assert_array(families)
		. append_failure_message("no families loaded from res://data")
		. is_not_empty()
	)
	_family_id = families[0]
	var mfrs: PackedStringArray = _data.manufacturers_for(_family_id)
	(
		assert_array(mfrs)
		. append_failure_message("no manufacturers for family '%s'" % _family_id)
		. is_not_empty()
	)
	_manufacturer_id = mfrs[0]


func _add_child(doc: ShipDoc, parent_id: String) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.id = doc.new_part_id()
	part.parent = parent_id
	part.kind = "primitive"
	part.family = _family_id
	part.manufacturer = _manufacturer_id
	part.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	part.yaw = 15.0
	part.pitch = 0.0
	part.rot = Vector3.ZERO
	part.offset = 0.0
	part.scale = Vector3.ONE
	part.blend = 0.0
	part.mirror_source = ""
	part.mirror_plane = ""
	part.display_name = "part " + part.id
	@warning_ignore("return_value_discarded")
	doc.add_part(part)
	return part


func _flush_attach() -> Dictionary:
	return {"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "offset": 0.0}


func _instance_dict(component_id: String) -> Dictionary:
	return {
		"parent": "",
		"kind": "component_instance",
		"family": component_id,
		"manufacturer": "",
		"params": {},
		"attach": _flush_attach(),
		"scale": [1.0, 1.0, 1.0],
		"blend": 0.0,
		"mirror": {"source": null, "plane": null},
		"name": "nested instance",
		"locked": false,
	}


func test_make_component_creates_a_definition() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var comp_id: String = ShipComponents.make_component(doc, PackedStringArray([child.id]), "Wing")
	assert_str(comp_id).is_not_empty()
	assert_bool(doc.components.has(comp_id)).is_true()
	var def_dict: Dictionary = doc.components[comp_id] as Dictionary
	assert_str(String(def_dict.get("label", ""))).is_equal("Wing")


func test_instantiate_creates_a_component_instance_part() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var comp_id: String = ShipComponents.make_component(doc, PackedStringArray([child.id]), "Wing")
	var instance_id: String = ShipComponents.instantiate(doc, comp_id, doc.root)
	assert_str(instance_id).is_not_empty()
	assert_bool(doc.parts.has(instance_id)).is_true()
	var inst_part: ShipPart = doc.parts[instance_id] as ShipPart
	assert_str(inst_part.kind).is_equal("component_instance")
	assert_str(inst_part.family).is_equal(comp_id)
	assert_str(inst_part.parent).is_equal(doc.root)


func test_make_unique_detaches_one_instance_from_definition_edits() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var comp_id: String = ShipComponents.make_component(doc, PackedStringArray([child.id]), "Wing")
	var instance_a_id: String = ShipComponents.instantiate(doc, comp_id, doc.root)
	var instance_b_id: String = ShipComponents.instantiate(doc, comp_id, doc.root)

	var new_def_id: String = ShipComponents.make_unique(doc, instance_b_id)
	assert_str(new_def_id).is_not_equal(comp_id)
	assert_bool(doc.components.has(new_def_id)).is_true()

	var part_a: ShipPart = doc.parts[instance_a_id] as ShipPart
	var part_b: ShipPart = doc.parts[instance_b_id] as ShipPart
	(
		assert_str(part_a.family)
		. append_failure_message("make_unique() repointed an instance it was not asked to touch")
		. is_equal(comp_id)
	)
	(
		assert_str(part_b.family)
		. append_failure_message(
			"make_unique() did not repoint the target instance to its cloned definition"
		)
		. is_equal(new_def_id)
	)

	var original_def: Dictionary = doc.components[comp_id] as Dictionary
	original_def["label"] = "Wing Mk2"
	doc.components[comp_id] = original_def
	var relabeled: String = String((doc.components[comp_id] as Dictionary).get("label", ""))
	var clone_label: String = String((doc.components[new_def_id] as Dictionary).get("label", ""))
	assert_str(relabeled).is_equal("Wing Mk2")
	(
		assert_str(clone_label)
		. append_failure_message(
			"editing the original definition leaked into the made-unique clone"
		)
		. is_not_equal("Wing Mk2")
	)


func test_check_cycles_detects_transitive_self_containment() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	doc.components["comp_a"] = {
		"label": "A", "root": "cp_0001", "parts": {"cp_0001": _instance_dict("comp_b")}
	}
	doc.components["comp_b"] = {
		"label": "B", "root": "cp_0002", "parts": {"cp_0002": _instance_dict("comp_a")}
	}
	var cycles: PackedStringArray = ShipComponents.check_cycles(doc)
	assert_array(cycles).is_not_empty()
	var flagged_a: bool = false
	var flagged_b: bool = false
	for id: String in cycles:
		if id == "comp_a":
			flagged_a = true
		if id == "comp_b":
			flagged_b = true
	(
		assert_bool(flagged_a or flagged_b)
		. append_failure_message(
			"check_cycles() did not flag either component in the cycle, got: %s" % [str(cycles)]
		)
		. is_true()
	)


func test_check_cycles_is_empty_for_an_acyclic_doc() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	assert_array(ShipComponents.check_cycles(doc)).is_empty()


func test_expand_flattens_component_instances() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var comp_id: String = ShipComponents.make_component(doc, PackedStringArray([child.id]), "Wing")
	var instance_id: String = ShipComponents.instantiate(doc, comp_id, doc.root)
	var cfg: ShipConfig = ShipConfig.defaults()
	var expanded: Dictionary = ShipComponents.expand(doc, _data, cfg)
	assert_dict(expanded).is_not_empty()

	var found_prefixed_key: bool = false
	for key: String in expanded.keys():
		if key.begins_with(instance_id + "/"):
			found_prefixed_key = true
			var entry: Dictionary = expanded[key] as Dictionary
			assert_bool(entry.has("shape")).is_true()
			assert_bool(entry.has("xform")).is_true()
	(
		assert_bool(found_prefixed_key)
		. append_failure_message(
			(
				"expand() produced no 'instance_id/inner_id' entry for instance '%s', got keys: %s"
				% [instance_id, str(expanded.keys())]
			)
		)
		. is_true()
	)


func _carbon_doc() -> ShipDoc:
	var data: ShipData = ShipData.new()
	assert_bool(data.load_all()).is_true()
	return ShipTemplates.build(data, ShipConfig.defaults(), "carbon", _linked())


## IMPORT COMPONENTS (ADR 0024/0026): every definition of another ship comes across under a
## fresh id, then every ARM off its root (a class's four identical tunnel+pod arms once), then
## the ship itself with a PRIMITIVE root - its nucleus instance dissolved into it - so an
## instance of the ship has a proxy shape and expands whole.
func test_import_from_brings_every_definition_the_arms_and_the_ship_itself() -> void:
	var data: ShipData = ShipData.new()
	assert_bool(data.load_all()).is_true()
	var cfg: ShipConfig = ShipConfig.defaults()
	var other: ShipDoc = ShipTemplates.build(data, cfg, "carbon", _linked())
	var other_parts: int = other.parts.size()
	var doc: ShipDoc = ShipTemplates.build(data, cfg, "hydrogen", _linked())
	var before: int = doc.components.size()
	var added: PackedStringArray = ShipComponents.import_from(doc, other, "CARBON")
	# The nucleus, one arm, the ship.
	assert_int(added.size()).append_failure_message(str(added)).is_equal(
		other.components.size() + 2
	)
	assert_int(doc.components.size()).is_equal(before + added.size())
	assert_int(other.parts.size()).is_equal(other_parts)
	var arm: Dictionary = doc.components[added[added.size() - 2]]
	assert_str(str(arm["label"])).is_equal("CARBON ARM 1")
	assert_int((arm["parts"] as Dictionary).size()).is_equal(2)
	var ship_id: String = added[added.size() - 1]
	var ship: Dictionary = doc.components[ship_id]
	var ship_parts: Dictionary = ship["parts"]
	# Nine document parts, less the nucleus instance, plus its six protons.
	assert_int(ship_parts.size()).is_equal(other_parts - 1 + 6)
	assert_str(str((ship_parts[str(ship["root"])] as Dictionary).get("kind", ""))).is_equal(
		ShipPart.KIND_PRIMITIVE
	)
	for inner_id: String in ship_parts:
		assert_str(str((ship_parts[inner_id] as Dictionary).get("kind", ""))).is_not_equal(
			ShipComponents.KIND_INSTANCE
		)
	# The ship's joints travel with it, their ends inside it (ADR 0025).
	var ship_joints: Dictionary = ship.get("joints", {})
	assert_int(ship_joints.size()).is_greater_equal(other.joints.size())
	for jid: String in ship_joints:
		var record: Dictionary = ship_joints[jid]
		(
			assert_bool(
				(
					ship_parts.has(str(record.get("a", "")))
					and ship_parts.has(str(record.get("b", "")))
				)
			)
			. append_failure_message("joint %s names something outside the ship" % jid)
			. is_true()
		)
	assert_int(ShipComponents.check_cycles(doc).size()).is_equal(0)
	var instance: String = ShipComponents.instantiate(doc, ship_id, doc.root)
	assert_str(instance).is_not_empty()
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	(
		assert_bool(shapes.has(instance))
		. append_failure_message("the ship instance has no proxy")
		. is_true()
	)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
	var expanded: int = 0
	for key: Variant in xforms:
		if str(key).begins_with(instance + "/") and not ShipSymmetry.is_twin_id(str(key)):
			expanded += 1
	assert_int(expanded).append_failure_message(str(xforms.keys())).is_equal(ship_parts.size() - 1)


## MAKE COMP refuses a head that is an instance: a definition's root is its proxy shape, and an
## instance has none (ADR 0026).
func test_make_component_refuses_an_instance_head() -> void:
	var doc: ShipDoc = _carbon_doc()
	var ids: PackedStringArray = doc.part_order()
	assert_str(ShipComponents.make_component(doc, ids, "WHOLE")).is_empty()
	assert_str((doc.parts[doc.root] as ShipPart).kind).is_equal(ShipPart.KIND_COMPONENT_INSTANCE)


## DISSOLVE (ADR 0024): the inverse of MAKE COMP for one instance - the inner parts come back as
## document parts, the definition's root in the instance's place, the parts hung off inner
## parts and the joints naming them following.
func test_dissolve_puts_the_inner_parts_back() -> void:
	var doc: ShipDoc = _carbon_doc()
	var instance: String = doc.root
	var before: int = doc.parts.size()
	var joints_before: int = doc.joints.size()
	var back: PackedStringArray = ShipComponents.dissolve(doc, instance)
	assert_int(back.size()).is_equal(6)
	assert_bool(doc.parts.has(instance)).is_false()
	assert_str(doc.root).is_equal(back[0])
	assert_str((doc.parts[doc.root] as ShipPart).kind).is_equal(ShipPart.KIND_PRIMITIVE)
	assert_int(doc.parts.size()).is_equal(before - 1 + 6)
	# The definition's open links come back as document joints (ADR 0025).
	assert_int(doc.joints.size()).is_greater(joints_before)
	var open_back: int = 0
	for jid: String in doc.joints:
		if (doc.joints[jid] as ShipJoint).mode == ShipJoint.MODE_OPEN:
			open_back += 1
	assert_int(open_back).is_greater_equal(5)
	for pid: String in doc.part_order():
		var part: ShipPart = doc.parts[pid]
		if pid != doc.root:
			# A part either stands on a part of this document or on NOTHING - anchored to the
			# beacon (ADR 0033), which is how a nucleus body comes back out (ADR 0034). What may
			# not happen is a parent that is not there any more.
			(
				assert_bool(doc.parts.has(part.parent) or part.parent.is_empty())
				. append_failure_message("%s hangs off %s" % [pid, part.parent])
				. is_true()
			)
	for jid: String in doc.joints:
		var joint: ShipJoint = doc.joints[jid]
		(
			assert_bool(doc.parts.has(joint.a) and doc.parts.has(joint.b))
			. append_failure_message("joint %s-%s" % [joint.a, joint.b])
			. is_true()
		)
	var data: ShipData = ShipData.new()
	assert_bool(data.load_all()).is_true()
	var xforms: Dictionary = ShipAttach.resolve_all(doc, data, ShipConfig.defaults())
	for pid: String in doc.part_order():
		assert_bool(xforms.has(pid)).append_failure_message(pid).is_true()


## An inner part edited through the document's cache (isolation, ADR 0024) reaches its
## definition once stored, and every instance reads it from there.
func test_part_at_edits_an_inner_part_through_the_cache() -> void:
	var doc: ShipDoc = _carbon_doc()
	var definition: Dictionary = doc.components[(doc.parts[doc.root] as ShipPart).family]
	var inner_id: String = ""
	for candidate: String in definition["parts"]:
		if candidate != str(definition["root"]):
			inner_id = candidate
			break
	var expanded: String = "%s/%s" % [doc.root, inner_id]
	assert_bool(ShipComponents.inner_exists(doc, expanded)).is_true()
	var part: ShipPart = doc.part_at(expanded)
	assert_object(part).is_not_null()
	var was: Vector3 = part.scale
	part.scale = was * 1.5
	# Not stored yet: a fresh read of the definition still says the old scale.
	assert_vector(ShipComponents.inner_part(doc, expanded).scale).is_equal(was)
	doc.store_inner(expanded)
	assert_vector(ShipComponents.inner_part(doc, expanded).scale).is_equal(was * 1.5)
	assert_object(doc.part_at("nobody/cp_0001")).is_null()


## The links between a component's chunks live in its definition (ADR 0025): the inner parts
## of a carbon nucleus pair with what they hang from and read OPEN - the template's joints -
## and erasing one puts the wall back; a tunnel on an inner proton keeps its own hatch.
func test_a_components_inner_parts_pair_and_read_their_definitions_joints() -> void:
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "carbon", _linked())
	var definition: Dictionary = doc.components[(doc.parts[doc.root] as ShipPart).family]
	var ids: PackedStringArray = PackedStringArray([doc.root])
	for inner_id: String in definition["parts"]:
		if inner_id != str(definition["root"]):
			ids.append("%s/%s" % [doc.root, inner_id])
	var pairs: Array[PackedStringArray] = ShipSeams.pairs_within(doc, ids)
	assert_int(pairs.size()).append_failure_message(str(pairs)).is_greater_equal(5)
	for pair: PackedStringArray in pairs:
		assert_bool(ShipSeams.within_one_instance(doc, pair[0], pair[1])).is_true()
		assert_str(ShipSeams.mode_for(doc, pair[0], pair[1])).is_equal(ShipSeams.MODE_OPEN)
	assert_str(ShipSeams.shared_mode(doc, pairs)).is_equal(ShipSeams.MODE_OPEN)
	# Erase one link: that pair is a wall again, the rest still open; set it back to a doorway.
	var first: PackedStringArray = pairs[0]
	assert_bool(ShipComponents.set_inner_joint(doc, first[0], first[1], null)).is_true()
	assert_str(ShipSeams.mode_for(doc, first[0], first[1])).is_equal(ShipSeams.MODE_WALL)
	assert_str(ShipSeams.shared_mode(doc, pairs)).is_equal(ShipSeams.MODE_WALL)
	var doorway: ShipJoint = ShipJoint.new()
	doorway.mode = ShipJoint.MODE_DOORWAY
	assert_bool(ShipComponents.set_inner_joint(doc, first[0], first[1], doorway)).is_true()
	assert_str(ShipSeams.mode_for(doc, first[0], first[1])).is_equal(ShipSeams.MODE_DOORWAY)
	# A tunnel on an inner proton is NOT within the instance: its seam keeps its own joint.
	var tunnel: String = ""
	for pid: String in doc.part_order():
		if (doc.parts[pid] as ShipPart).role == ShipPart.ROLE_HALLWAY:
			tunnel = pid
			break
	var host: String = (doc.parts[tunnel] as ShipPart).parent
	assert_bool(ShipSeams.within_one_instance(doc, tunnel, host)).is_false()
	assert_str(ShipSeams.mode_for(doc, tunnel, host)).is_equal(ShipSeams.MODE_HATCHED)


## The default link of a fresh seam (ADR 0027): a tunnel on a module, or a module on a tunnel,
## is HATCHED; two modules are a WALL; an instance answers with its definition root's role, so an
## imported arm (a tunnel with its pod) placed on a proton hatches too.
func test_a_tunnel_meeting_a_module_is_hatched_by_default() -> void:
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "carbon", _linked())
	var tunnel: String = ""
	var pod: String = ""
	for pid: String in doc.part_order():
		var part: ShipPart = doc.parts[pid]
		if part.role == ShipPart.ROLE_HALLWAY and tunnel.is_empty():
			tunnel = pid
		if part.role == ShipPart.ROLE_ROOM and part.parent == tunnel and not tunnel.is_empty():
			pod = pid
	var host: String = (doc.parts[tunnel] as ShipPart).parent
	assert_str(ShipSeams.role_of(doc, host)).is_equal(ShipPart.ROLE_ROOM)
	assert_str(ShipSeams.default_link_for(doc, tunnel, host)).is_equal(ShipSeams.MODE_HATCHED)
	assert_str(ShipSeams.default_link_for(doc, pod, tunnel)).is_equal(ShipSeams.MODE_HATCHED)
	assert_str(ShipSeams.default_link_for(doc, pod, doc.root)).is_equal(ShipSeams.MODE_WALL)
	# An instance of an arm: its root is the tunnel, so it hatches onto a room.
	var other: ShipDoc = ShipTemplates.build(_data, _cfg, "carbon", _linked())
	var added: PackedStringArray = ShipComponents.import_from(doc, other, "CARBON")
	var arm_id: String = added[added.size() - 2]
	var arm: String = ShipComponents.instantiate(doc, arm_id, doc.root)
	assert_str(ShipSeams.role_of(doc, arm)).is_equal(ShipPart.ROLE_HALLWAY)
	assert_str(ShipSeams.default_link_for(doc, arm, doc.root)).is_equal(ShipSeams.MODE_HATCHED)


## A definition's parts come out PARENT BEFORE CHILD even when the ids say otherwise: an anchored
## member (ADR 0034) is unreachable from the root, and appending it with the leftovers in id order
## put its own child ahead of it. Both readers of this order - the attach pass and dissolve - fail
## silently rather than loudly on that, so it is asserted here rather than left to a ship to show.
func test_definition_order_walks_an_anchored_members_subtree() -> void:
	var inner: Dictionary = {}
	for record: Array in [["cp_0001", ""], ["cp_0002", "cp_0009"], ["cp_0009", ""]]:
		var part: ShipPart = ShipPart.new()
		part.id = str(record[0])
		part.parent = str(record[1])
		part.kind = ShipPart.KIND_PRIMITIVE
		part.family = "sphere_pod"
		inner[part.id] = part
	var order: PackedStringArray = ShipComponents.definition_order(inner, "cp_0001")
	assert_array(Array(order)).contains_exactly(["cp_0001", "cp_0009", "cp_0002"])


## "by default in the prebuilds we dont want any walls in our prebuilds by default" (2026-09-26).
## The hatch stays AUTHORED on every link whatever the mode, which is what makes adding a wall
## later one edit rather than a round of choices.
func test_a_template_links_open_and_still_authors_its_hatches() -> void:
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "carbon", {})
	assert_int(doc.joints.size()).is_greater(0)
	for jid: String in doc.joints:
		var joint: ShipJoint = doc.joints[jid]
		assert_str(joint.mode).append_failure_message("a prebuild link stands a wall").is_equal(
			ShipJoint.MODE_OPEN
		)
		(
			assert_str(joint.hatch_family)
			. append_failure_message("the hatch was not authored, so adding a wall costs a choice")
			. is_not_empty()
		)
		assert_bool(joint.hatch_params.is_empty()).is_false()


## And the picker's lever brings them back, one option, nothing else changed.
func test_the_link_mode_option_brings_the_hatches_back() -> void:
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "carbon", _linked())
	assert_int(doc.joints.size()).is_greater(0)
	for jid: String in doc.joints:
		assert_str((doc.joints[jid] as ShipJoint).mode).is_equal(ShipJoint.MODE_HATCHED)


## "the player options for the prebuilt structures need expanding with options for outter/electron
## node shapes, tunnel shapes, proton shapes" (dev note 2026-09-24). Three groups, three shapes.
func test_each_group_takes_its_own_shape() -> void:
	var doc: ShipDoc = ShipTemplates.build(
		_data,
		_cfg,
		"carbon",
		{
			ShipTemplates.OPT_PROTON_FAMILY: "box_hull",
			ShipTemplates.OPT_ELECTRON_FAMILY: "sphere_pod",
			ShipTemplates.OPT_HALL_FAMILY: "cylinder_spar"
		}
	)
	# Counted on the RESOLVED shapes, not on doc.parts: the nucleus is lifted into a component
	# (ADR 0024), so its protons live in the definition and never appear as plain parts.
	var bases: Dictionary = {}
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	for pid: String in shapes:
		if ShipSymmetry.is_twin_id(pid):
			continue
		var base: int = (shapes[pid] as ResolvedShape).base
		bases[base] = int(bases.get(base, 0)) + 1
	# A carbon: six protons, four tunnels, four electrons.
	(
		assert_int(int(bases.get(ResolvedShape.Base.BOX, 0)))
		. append_failure_message("protons are not boxes: %s" % str(bases))
		. is_equal(6)
	)
	(
		assert_int(int(bases.get(ResolvedShape.Base.CYLINDER, 0)))
		. append_failure_message("tunnels are not cylinders: %s" % str(bases))
		. is_equal(4)
	)
	(
		assert_int(int(bases.get(ResolvedShape.Base.SPHERE, 0)))
		. append_failure_message("electrons are not spheres: %s" % str(bases))
		. is_equal(4)
	)


## "the new shaper should cater to multi shape clusters, so a protons shapes can be shape1 and
## shape2 ... and the system will try to keep everything semetrical and even as normal".
##
## THE BLEND IS THE SYMMETRY TEST. A cluster with two shapes in it must still balance, which is
## only true if a body and its mirror take the SAME shape - alternating body by body would put a
## cube opposite a sphere.
func test_a_blended_cluster_is_still_symmetric() -> void:
	var blended: ShipDoc = (
		ShipTemplates
		. build(
			_data,
			_cfg,
			"carbon",
			{
				ShipTemplates.OPT_PROTON_FAMILY: "box_hull",
				ShipTemplates.OPT_PROTON_FAMILY_B: "sphere_pod",
				# Cylinders outside, so BOX and SPHERE below can only be nucleus bodies.
				ShipTemplates.OPT_ELECTRON_FAMILY: "cylinder_spar"
			}
		)
	)
	# On the RESOLVED shapes: the nucleus is a component, so its protons are never plain parts.
	var bases: Dictionary = {}
	var shapes: Dictionary = ShipAttach.resolve_shapes(blended, _data, _cfg)
	for pid: String in shapes:
		if ShipSymmetry.is_twin_id(pid):
			continue
		var base: int = (shapes[pid] as ResolvedShape).base
		bases[base] = int(bases.get(base, 0)) + 1
	(
		assert_int(int(bases.get(ResolvedShape.Base.BOX, 0)))
		. append_failure_message("no boxes in the blend: %s" % str(bases))
		. is_greater(0)
	)
	(
		assert_int(int(bases.get(ResolvedShape.Base.SPHERE, 0)))
		. append_failure_message("the blend put one shape everywhere: %s" % str(bases))
		. is_greater(0)
	)
	(
		assert_int(
			int(bases.get(ResolvedShape.Base.BOX, 0)) + int(bases.get(ResolvedShape.Base.SPHERE, 0))
		)
		. append_failure_message("the blend leaked outside the nucleus: %s" % str(bases))
		. is_equal(6)
	)
	# Balanced on some axis, exactly as an unblended class is (ADR 0044/0045).
	var balance: Dictionary = ShipMetrics.balance(blended, _data, _cfg)
	(
		assert_float(float(balance.get("best", 0.0)))
		. append_failure_message("a blended cluster came out lopsided: %s" % str(balance))
		. is_greater(0.97)
	)


## "when cylinder nodes (not linkage tunnels) is selected in pre built options, it should have the
## length and diameter equal and set to room size not tunnel bore, as an earlier test indicated
## that it made tiny bore rooms" (dev note 2026-09-24). cylinder_spar is authored three to one.
func test_a_cylinder_node_is_as_wide_as_it_is_long() -> void:
	var span: float = 4.0
	var doc: ShipDoc = ShipTemplates.build(
		_data,
		_cfg,
		"carbon",
		{
			ShipTemplates.OPT_PROTON_FAMILY: "cylinder_spar",
			ShipTemplates.OPT_ELECTRON_FAMILY: "cylinder_spar",
			ShipTemplates.OPT_ROOM_SPAN: span
		}
	)
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var rooms: int = 0
	for pid: String in shapes:
		var part: ShipPart = doc.parts.get(ShipSymmetry.source_of_twin(pid), null)
		if part == null or part.role != ShipTemplates.ROLE_ROOM:
			continue
		rooms += 1
		var box: Vector3 = ShapeMesh.build(shapes[pid]).aabb().size
		for axis: int in 3:
			(
				assert_float(box[axis])
				. append_failure_message("%s came out %s, not %.1f cubed" % [pid, str(box), span])
				. is_equal_approx(span, span * 0.02)
			)
	assert_int(rooms).is_greater(0)

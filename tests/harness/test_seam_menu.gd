# The seam-style feature, after it left ship_builder.gd on 2026-09-27. Only the two pure statics
# are asserted here - the menu itself needs a builder and a GPU slot, and is driven end to end by
# `tools/ship_check_views.gd::check_seam_menu`.
class_name TestSeamMenu
extends GdUnitTestSuite


## A HEADING HAS NO `id`, and reading one as a choice cost a runtime error that the tool's own
## PASSED banner said nothing about - which is the case AGENTS section 8a exists for.
func test_every_choice_has_an_id_and_every_heading_has_none() -> void:
	var choices: int = 0
	for item: Dictionary in ShipSeamMenu.SEAM_STYLE_ITEMS:
		if item.has("header"):
			assert_bool(item.has("id")).is_false()
			assert_str(str(item["header"])).is_not_empty()
			continue
		choices += 1
		assert_str(str(item.get("id", ""))).is_not_empty()
		assert_str(str(item.get("label", ""))).is_not_empty()
	# ADR 0013: two groups of three - which solid indents the other, times the linkage surface.
	assert_int(choices).is_equal(6)


## THE IDS ARE ShipJoint's, spelt out. The table uses literals deliberately - a class-level const
## naming another class_name is a load-order hazard - so nothing but a test keeps them in step.
func test_the_ids_are_the_joint_constants() -> void:
	var ids: PackedStringArray = PackedStringArray()
	for item: Dictionary in ShipSeamMenu.SEAM_STYLE_ITEMS:
		if item.has("id"):
			ids.append(str(item["id"]))
	(
		assert_array(ids)
		. contains_exactly(
			[
				ShipJoint.SEAM_SMALL_FLAT_INSERT,
				ShipJoint.SEAM_SMALL_FLAT_CUTOFF,
				ShipJoint.SEAM_SMALL_NATIVE,
				ShipJoint.SEAM_BIG_FLAT_INSERT,
				ShipJoint.SEAM_BIG_FLAT_CUTOFF,
				ShipJoint.SEAM_BIG_NATIVE,
			]
		)
	)


func test_a_label_is_qualified_by_its_group() -> void:
	assert_str(ShipSeamMenu.style_label(ShipJoint.SEAM_BIG_NATIVE)).is_equal(
		"BIG INDENTS SMALL - NATIVE INSERTED"
	)
	assert_str(ShipSeamMenu.style_label(ShipJoint.SEAM_SMALL_FLAT_CUTOFF)).is_equal(
		"SMALL INDENTS BIG - FLAT CUTOFF"
	)
	# A style the table does not carry falls back to itself rather than to a heading.
	assert_str(ShipSeamMenu.style_label("something_else")).is_equal("SOMETHING_ELSE")


func test_the_joint_lookup_is_unordered_and_safe_on_null() -> void:
	assert_str(ShipSeamMenu.joint_id_for(null, "a", "b")).is_empty()
	var doc: ShipDoc = ShipDoc.new()
	var joint: ShipJoint = ShipJoint.new()
	joint.id = "j_0001"
	joint.a = "p_0001"
	joint.b = "p_0002"
	doc.joints[joint.id] = joint
	assert_str(ShipSeamMenu.joint_id_for(doc, "p_0001", "p_0002")).is_equal("j_0001")
	(
		assert_str(ShipSeamMenu.joint_id_for(doc, "p_0002", "p_0001"))
		. append_failure_message("the pair is UNORDERED - a joint is one joint either way round")
		. is_equal("j_0001")
	)
	assert_str(ShipSeamMenu.joint_id_for(doc, "p_0001", "p_0009")).is_empty()

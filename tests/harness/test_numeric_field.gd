# A field shows as many decimals as its step can produce, and no more.
#
# The author, 2026-09-27: "angles are to a precision of x.xxx when our smallest snap precision is
# much smaller." At the shipped 0.5 degree default, two of three decimals on YAW were structurally
# zero - a digit that can never be anything but zero is noise a child has to read past.
class_name TestNumericField
extends GdUnitTestSuite


func test_decimals_follow_the_step() -> void:
	# step -> decimals. A whole-number step needs none; a tenth needs one.
	var cases: Dictionary = {
		1.0: 0,
		5.0: 0,
		15.0: 0,
		0.5: 1,
		0.1: 1,
		0.05: 2,
		0.01: 2,
		0.005: 3,
		0.001: 3,
	}
	for step: float in cases:
		(
			assert_int(NumericField.decimals_for(step))
			. append_failure_message("a step of %s" % str(step))
			. is_equal(int(cases[step]))
		)


## AN UNQUANTIZED FIELD KEEPS ALL THREE, and that is honest rather than a special case: a snapped
## yaw really can be 37.418, which is why those two fields are read-only to begin with.
func test_an_unquantized_field_keeps_full_precision() -> void:
	assert_int(NumericField.decimals_for(0.0)).is_equal(NumericField.DECIMALS)
	assert_int(NumericField.decimals_for(-1.0)).is_equal(NumericField.DECIMALS)


## THE STATIC IS UNTOUCHED. Twenty callers outside this class read it, and a field's decimals are
## a property of the field and not of the number.
func test_the_shared_formatter_still_gives_three() -> void:
	assert_str(NumericField.format_number(1.5)).is_equal("1.500")
	assert_str(NumericField.format_number(0.0)).is_equal("0.000")
	assert_str(NumericField.format_number(-0.0001)).is_equal("0.000")
	assert_str(NumericField.format_number(NAN)).is_equal("---")
	assert_str(NumericField.format_number(INF)).is_equal("INF")


## There is one format string per decimal count, written out - Godot's format operator is a
## printf SUBSET and dynamic precision is not something to bet a whole UI's numbers on.
func test_there_is_a_written_format_for_every_count() -> void:
	assert_int(NumericField.FORMATS.size()).is_equal(NumericField.DECIMALS + 1)
	assert_int(NumericField.DECIMAL_STEPS.size()).is_equal(NumericField.DECIMALS)
	for i: int in NumericField.FORMATS.size():
		assert_str(str(NumericField.FORMATS[i])).is_equal("%%.%df" % i)


## WHAT IS ACTUALLY ON SCREEN, asserted through the same private formatter `_refresh_text()` uses.
func test_a_field_reads_at_its_own_step() -> void:
	var cases: Array = [
		# step, value, what the box shows
		[5.0, 35.0, "35"],
		[5.0, -0.0001, "0"],
		[1.0, 12.0, "12"],
		[0.5, 12.5, "12.5"],
		[0.1, 1.2, "1.2"],
		[0.01, 0.02, "0.02"],
		[0.0, 37.418, "37.418"],
	]
	for case: Array in cases:
		var field: NumericField = auto_free(NumericField.new())
		add_child(field)
		field.configure("N", -1000.0, 1000.0, float(case[0]), false)
		(
			assert_str(str(field.call("_format_own", float(case[1]))))
			. append_failure_message("%s at a step of %s" % [str(case[1]), str(case[0])])
			. is_equal(str(case[2]))
		)


## A WHOLE-NUMBER STEP MUST NOT PRINT "-0", which reads as a different number from "0" - the
## epsilon that kills it has to follow the decimals down, not stay at three.
func test_negative_zero_never_reaches_the_box() -> void:
	var field: NumericField = auto_free(NumericField.new())
	add_child(field)
	field.configure("N", -10.0, 10.0, 1.0, false)
	for tiny: float in [-0.0, -0.2, -0.49]:
		assert_str(str(field.call("_format_own", tiny))).is_equal("0")

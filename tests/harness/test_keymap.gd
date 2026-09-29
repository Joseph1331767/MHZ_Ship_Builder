class_name TestKeymap
extends GdUnitTestSuite
## The gate that keeps [ShipKeymap] honest.
##
## IT RUNS ONE-DIRECTIONALLY, ON PURPOSE. Nothing dispatches from the table yet
## (docs/future/ux.md section 5.1 step 5), so there is no second source to compare against and a
## test that tried would only be asserting that two hand-written lists match. What it checks
## instead is that the table is WELL FORMED - no blank column, no invented context, no handler
## pointing at a file that is not there - and INTERNALLY CONSISTENT, which is the half that rots.
##
## THE DUPLICATE-CHORD CHECK IS THE POINT OF THE WHOLE FILE. ESC already means five things in
## this application and the next agent to bind a letter key has no way to know what is taken. One
## chord twice in one context is a collision; the test names both actions and fails. Everything
## else here is shape-checking around that one assertion.
##
## No GPU slot and no scene: the table is static data and every assertion is arithmetic on
## strings. It is safe to run in the same pass as the `core/` suites.

## The contexts a row may claim. Written out here rather than read from [ShipKeymap.contexts],
## which reports what the table happens to contain - a typo would define itself as legal.
const ALLOWED_CONTEXTS: Array[String] = [
	ShipKeymap.CONTEXT_ALWAYS,
	ShipKeymap.CONTEXT_VIEW,
	ShipKeymap.CONTEXT_SELECTED,
	ShipKeymap.CONTEXT_MULTI,
	ShipKeymap.CONTEXT_PLACING,
	ShipKeymap.CONTEXT_LOCKED,
	ShipKeymap.CONTEXT_ISOLATED,
	ShipKeymap.CONTEXT_EXPLODED,
	ShipKeymap.CONTEXT_DIALOG,
	ShipKeymap.CONTEXT_MENU,
	ShipKeymap.CONTEXT_FIELD,
	ShipKeymap.CONTEXT_PAINT,
]

const ALLOWED_GROUPS: Array[String] = [
	ShipKeymap.GROUP_LOOK,
	ShipKeymap.GROUP_PLACE,
	ShipKeymap.GROUP_CHANGE,
	ShipKeymap.GROUP_FILE,
]

const ALLOWED_STATUSES: Array[String] = [
	ShipKeymap.STATUS_LIVE,
	ShipKeymap.STATUS_LIES,
	ShipKeymap.STATUS_DEAD,
	ShipKeymap.STATUS_UNBOUND,
]

## Every column a row must carry. A missing one is how a half-written row reaches the card.
const REQUIRED_FIELDS: Array[String] = [
	ShipKeymap.FIELD_ACTION,
	ShipKeymap.FIELD_CHORD,
	ShipKeymap.FIELD_ALTS,
	ShipKeymap.FIELD_CODE,
	ShipKeymap.FIELD_MODS,
	ShipKeymap.FIELD_LABEL,
	ShipKeymap.FIELD_CONTEXT,
	ShipKeymap.FIELD_TIER,
	ShipKeymap.FIELD_GROUP,
	ShipKeymap.FIELD_HANDLER,
	ShipKeymap.FIELD_STATUS,
	ShipKeymap.FIELD_NOTE,
]

## Modifier word in a chord -> the bit the row must carry, both ways.
const MOD_WORDS: Dictionary = {
	"SHIFT": ShipKeymap.MOD_SHIFT,
	"CTRL": ShipKeymap.MOD_CTRL,
	"ALT": ShipKeymap.MOD_ALT,
}


func _chords_of(row: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray([str(row[ShipKeymap.FIELD_CHORD])])
	for alt: Variant in row[ShipKeymap.FIELD_ALTS]:
		out.append(str(alt))
	return out


func _actions_of(rows: Array[Dictionary]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for row: Dictionary in rows:
		out.append(str(row[ShipKeymap.FIELD_ACTION]))
	return out


func test_the_table_is_not_empty_and_every_row_has_every_column() -> void:
	assert_int(ShipKeymap.ROWS.size()).is_greater(30)
	for row: Dictionary in ShipKeymap.ROWS:
		for field: String in REQUIRED_FIELDS:
			(
				assert_bool(row.has(field))
				. append_failure_message(
					"row %s is missing the %s column" % [str(row.get("action", "?")), field]
				)
				. is_true()
			)
		assert_int(row.size()).is_equal(REQUIRED_FIELDS.size())


func test_no_row_is_blank_where_it_must_speak() -> void:
	for row: Dictionary in ShipKeymap.ROWS:
		var action: String = str(row[ShipKeymap.FIELD_ACTION])
		assert_str(action).is_not_empty()
		(
			assert_str(str(row[ShipKeymap.FIELD_CHORD]))
			. append_failure_message(
				"%s has no chord - an unbound verb takes ShipKeymap.UNBOUND_CHORD" % action
			)
			. is_not_empty()
		)
		(
			assert_str(str(row[ShipKeymap.FIELD_LABEL]))
			. append_failure_message(
				"%s has no label; a card row with no words is furniture" % action
			)
			. is_not_empty()
		)
		assert_str(str(row[ShipKeymap.FIELD_HANDLER])).is_not_empty()


func test_action_ids_are_unique_and_snake_case() -> void:
	var seen: PackedStringArray = PackedStringArray()
	for row: Dictionary in ShipKeymap.ROWS:
		var action: String = str(row[ShipKeymap.FIELD_ACTION])
		(
			assert_bool(seen.has(action))
			. append_failure_message(
				"the action id %s is used twice; chord_for() is ambiguous" % action
			)
			. is_false()
		)
		seen.append(action)
		(
			assert_str(action)
			. append_failure_message("action ids are snake_case, per AGENTS section 2")
			. is_equal(action.to_snake_case())
		)


func test_every_context_tier_group_and_status_is_one_we_named() -> void:
	for row: Dictionary in ShipKeymap.ROWS:
		var action: String = str(row[ShipKeymap.FIELD_ACTION])
		(
			assert_bool(ALLOWED_CONTEXTS.has(str(row[ShipKeymap.FIELD_CONTEXT])))
			. append_failure_message("%s claims a context nobody declared" % action)
			. is_true()
		)
		(
			assert_bool(ShipKeymap.tiers().has(str(row[ShipKeymap.FIELD_TIER])))
			. append_failure_message("%s claims a tier outside the ladder" % action)
			. is_true()
		)
		assert_bool(ALLOWED_GROUPS.has(str(row[ShipKeymap.FIELD_GROUP]))).is_true()
		assert_bool(ALLOWED_STATUSES.has(str(row[ShipKeymap.FIELD_STATUS]))).is_true()


## The handler anchor is the only thing tying a row to the code that runs it. A path that has gone
## stale means the binding may have moved or gone; either way the row needs a human.
func test_every_handler_anchor_names_a_file_that_exists() -> void:
	for row: Dictionary in ShipKeymap.ROWS:
		var anchor: String = str(row[ShipKeymap.FIELD_HANDLER])
		var parts: PackedStringArray = anchor.split(":")
		(
			assert_int(parts.size())
			. append_failure_message("%s is not in file:method form" % anchor)
			. is_equal(2)
		)
		(
			assert_bool(FileAccess.file_exists("res://" + parts[0]))
			. append_failure_message("%s points at a file that is not on disk" % anchor)
			. is_true()
		)
		assert_str(parts[1]).is_not_empty()


## The whole reason the table exists. Two rows offering the same chord in the same context is a
## collision the player experiences as one of them silently not working.
func test_no_chord_is_claimed_twice_in_one_context() -> void:
	var claimed: Dictionary = {}
	for row: Dictionary in ShipKeymap.ROWS:
		var context: String = str(row[ShipKeymap.FIELD_CONTEXT])
		var action: String = str(row[ShipKeymap.FIELD_ACTION])
		for chord: String in _chords_of(row):
			if chord == ShipKeymap.UNBOUND_CHORD:
				continue
			var slot: String = "%s / %s" % [context, chord]
			(
				assert_bool(claimed.has(slot))
				. append_failure_message(
					"%s is claimed by both %s and %s" % [slot, str(claimed.get(slot, "")), action]
				)
				. is_false()
			)
			claimed[slot] = action


## A chord's modifier words and its `mods` bits have to agree, or a dispatcher built on this table
## later will match on something the legend never printed.
func test_the_modifier_bits_agree_with_the_printed_chord() -> void:
	for row: Dictionary in ShipKeymap.ROWS:
		var chord: String = str(row[ShipKeymap.FIELD_CHORD])
		var mods: int = int(row[ShipKeymap.FIELD_MODS])
		for word: String in MOD_WORDS:
			var bit: int = int(MOD_WORDS[word])
			(
				assert_bool((mods & bit) != 0)
				. append_failure_message(
					"%s: the chord and the mods disagree about %s" % [chord, word]
				)
				. is_equal(chord.contains(word))
			)


## LABEL_MAX is a rendering budget, not a style preference - see its docstring. A label over it
## is clipped on the hold-`?` card, which is exactly where a beginner is reading.
func test_every_label_fits_the_card() -> void:
	for row: Dictionary in ShipKeymap.ROWS:
		var label: String = str(row[ShipKeymap.FIELD_LABEL])
		(
			assert_int(label.length())
			. append_failure_message(
				(
					'"%s" is %d characters; the card budget is %d'
					% [label, label.length(), ShipKeymap.LABEL_MAX]
				)
			)
			. is_less_equal(ShipKeymap.LABEL_MAX)
		)


## A table that lies is worse than no table: anything not LIVE has to say what is actually true,
## and an UNBOUND row has to admit it in its chord rather than inventing a key.
func test_a_row_that_is_not_live_explains_itself() -> void:
	for row: Dictionary in ShipKeymap.ROWS:
		var status: String = str(row[ShipKeymap.FIELD_STATUS])
		var action: String = str(row[ShipKeymap.FIELD_ACTION])
		var unbound: bool = str(row[ShipKeymap.FIELD_CHORD]) == ShipKeymap.UNBOUND_CHORD
		(
			assert_bool(unbound)
			. append_failure_message("%s: UNBOUND_CHORD and STATUS_UNBOUND go together" % action)
			. is_equal(status == ShipKeymap.STATUS_UNBOUND)
		)
		if status == ShipKeymap.STATUS_LIVE:
			continue
		(
			assert_str(str(row[ShipKeymap.FIELD_NOTE]))
			. append_failure_message("%s is %s and says nothing about why" % [action, status])
			. is_not_empty()
		)


## The three defects docs/future/ux.md section 2.5 verified by hand, pinned so they cannot quietly
## become a LIVE row. If you have fixed one, change its row AND this assertion in the same commit.
func test_the_known_broken_bindings_are_on_the_record() -> void:
	var expected: Dictionary = {
		"undo": ShipKeymap.STATUS_DEAD,  # B1 - the 3D view eats CTRL+Z as a Z axis lock
		"redo": ShipKeymap.STATUS_DEAD,  # B1 - and CTRL+Y as a Y axis lock
		"scale_wheel": ShipKeymap.STATUS_LIES,  # B7 - the legend prints WHEEL ZOOM
		"snap_bypass": ShipKeymap.STATUS_UNBOUND,  # B8 - no key survived the Shift reassignment
		"isolate_exit": ShipKeymap.STATUS_DEAD,  # ESC is promised and never leaves isolation
	}
	for action: String in expected:
		var row: Dictionary = ShipKeymap.row_for(action)
		(
			assert_dict(row)
			. append_failure_message("%s has been dropped from the table" % action)
			. is_not_empty()
		)
		(
			assert_str(str(row[ShipKeymap.FIELD_STATUS]))
			. append_failure_message(
				"%s changed status; if the defect is fixed, update this test too" % action
			)
			. is_equal(str(expected[action]))
		)


## FLY's thirteen bindings are all listed, at their own context, and reachable by action name -
## which is what makes the legend and the hint chips able to print the flying meaning of A, X and E
## instead of the building one (ADR 0049).
func test_the_fly_rows_are_listed_at_their_own_context() -> void:
	var fly: Array[Dictionary] = ShipKeymap.for_context(ShipKeymap.CONTEXT_FLY)
	assert_int(fly.size()).is_equal(13)
	for row: Dictionary in fly:
		(
			assert_str(str(row[ShipKeymap.FIELD_GROUP]))
			. append_failure_message("every fly row belongs to the fly group")
			. is_equal(ShipKeymap.GROUP_FLY)
		)
		# BASIC flies too, so none of these may be gated above the first tier.
		assert_str(str(row[ShipKeymap.FIELD_TIER])).is_equal(ShipKeymap.TIER_BUILD)
		assert_bool(ShipKeymap.is_live(row)).is_true()
	# The brake and the guaranteed non-ESC exit are the two a player cannot do without.
	assert_str(ShipKeymap.chord_for("fly_brake")).is_equal("X")
	assert_str(ShipKeymap.chord_for("fly_land")).is_equal("V")
	# ESC is offered as an ALTERNATE, never as the only way out - the diegetic host eats it.
	var land: Dictionary = ShipKeymap.row_for("fly_land")
	assert_array(land[ShipKeymap.FIELD_ALTS] as Array).contains(["ESC"])


func test_the_lookups_answer_and_all_returns_a_copy() -> void:
	assert_str(ShipKeymap.chord_for("frame_all")).is_equal("F")
	assert_str(ShipKeymap.chord_for("snap_bypass")).is_equal(ShipKeymap.UNBOUND_CHORD)
	(
		assert_str(ShipKeymap.chord_for("no_such_action"))
		. append_failure_message('an unknown action is "", never the unbound chord')
		. is_empty()
	)
	assert_dict(ShipKeymap.row_for("no_such_action")).is_empty()
	assert_int(ShipKeymap.tier_rank(ShipKeymap.TIER_BUILD)).is_equal(0)
	assert_int(ShipKeymap.tier_rank("SANDBOX")).is_equal(-1)

	var copy: Array[Dictionary] = ShipKeymap.all()
	# all() is ROWS PLUS the generated FLY rows (ADR 0049) - thirteen bindings built rather than
	# written out, because thirteen rows identical but for a chord is where a typo hides. So this is
	# deliberately `greater`, not `equal`: the old equality quietly asserted that nothing is ever
	# generated, which is no longer true and was never the thing this case is about.
	(
		assert_int(copy.size())
		. append_failure_message("all() must include the generated rows, not just the const")
		. is_greater(ShipKeymap.ROWS.size())
	)
	copy.clear()
	(
		assert_int(ShipKeymap.ROWS.size())
		. append_failure_message("all() handed out the const itself")
		. is_greater(0)
	)


## Nothing that cannot be pressed may be offered. The filters are what the card and the chips
## call, so a DEAD row leaking through one of them puts a broken key in front of a child.
func test_the_filters_never_offer_a_dead_row() -> void:
	for context: String in ALLOWED_CONTEXTS:
		for row: Dictionary in ShipKeymap.for_context(context):
			assert_str(str(row[ShipKeymap.FIELD_CONTEXT])).is_equal(context)
			assert_bool(ShipKeymap.is_live(row)).is_true()
	for tier: String in ShipKeymap.tiers():
		for row: Dictionary in ShipKeymap.for_tier(tier):
			assert_bool(ShipKeymap.is_live(row)).is_true()
	assert_array(ShipKeymap.for_tier("SANDBOX")).is_empty()
	assert_array(ShipKeymap.for_context("NOWHERE")).is_empty()


## ENGINEER is a strict superset (docs/future/ux.md section 3.1 rule 1). Stated as a test rather
## than a promise, which is the only form of that rule worth having.
func test_each_rung_of_the_ladder_contains_the_one_below_it() -> void:
	var build: PackedStringArray = _actions_of(ShipKeymap.for_tier(ShipKeymap.TIER_BUILD))
	var shape: PackedStringArray = _actions_of(ShipKeymap.for_tier(ShipKeymap.TIER_SHAPE))
	var engineer: PackedStringArray = _actions_of(ShipKeymap.for_tier(ShipKeymap.TIER_ENGINEER))
	assert_int(build.size()).is_greater(0)
	for action: String in build:
		(
			assert_bool(shape.has(action))
			. append_failure_message("SHAPE lost %s, which BUILD offers" % action)
			. is_true()
		)
	for action: String in shape:
		(
			assert_bool(engineer.has(action))
			. append_failure_message("ENGINEER lost %s, which SHAPE offers" % action)
			. is_true()
		)
	(
		assert_int(engineer.size())
		. append_failure_message("ENGINEER must be every renderable row")
		. is_greater(shape.size())
	)


## SHIFT+F is the author's most-used binding and appears on no surface in the running application
## (docs/future/ux.md section 3.6). It is in the table because that is the whole reason for one.
func test_the_developer_note_chord_is_in_the_table() -> void:
	var row: Dictionary = ShipKeymap.row_for("dev_note")
	assert_str(str(row[ShipKeymap.FIELD_CHORD])).is_equal("SHIFT+F")
	assert_str(str(row[ShipKeymap.FIELD_TIER])).is_equal(ShipKeymap.TIER_ENGINEER)
	assert_bool(ShipKeymap.is_live(row)).is_true()

class_name TestHintText
extends GdUnitTestSuite
## [ShipHintText] - the hint bar's words, its priority ladder and its verbosity decay.
## `docs/future/ux.md` section 3.2. No scene, no theme, no GPU slot: the resolver is static and
## engine-free, which is the whole reason the wording was split out of the renderer that does not
## exist yet.
##
## WHAT THIS SUITE IS FOR. Every literal the application says to the player lives in one file, and
## a sentence is the easiest thing in a codebase to change by accident - a tidy-up, a reflow, a
## well-meant rewording. Each line is asserted EXACTLY here, so moving one is a deliberate edit to
## a test and never a side effect. The second half pins the ladder, which is the part ux.md says
## "will be wrong if it is improvised": what wins when a refusal, a modal and a drag are all true
## at the same moment is a decision, not an emergent property of the order somebody wrote the ifs.
##
## ONE gdUnit4 CASE PER STATE, through `test_parameters` rather than one function apiece, because
## `.gdlintrc` caps a class at thirty public methods and a test function is a public method. The
## coverage case asserts the parameter list and [constant ShipHintText.STATE_IDS] are the same
## set, so a state cannot be added without a line here that pins its sentence.

## The exact LEDE every state produces, for the state [method _states] builds for it. These are the
## strings a child reads. Keep them verb-first, plain, and inside sixty-two characters.
const CASES: Dictionary = {
	ShipHintText.ID_REFUSED_ROLLBACK: "THAT WOULD MAKE IT TOO BIG - SO I PUT IT BACK",
	ShipHintText.ID_REFUSED_PLACE: "TOO HEAVY - TAKE SOMETHING OFF FIRST",
	ShipHintText.ID_REFUSED_OFF_SHIP: "LET GO OUT HERE AND THE PART GOES IN THE BIN",
	ShipHintText.ID_REFUSED_DISABLED: "NEEDS A PART PICKED UP FIRST - CLICK ONE",
	ShipHintText.ID_REFUSED_CELL: "THAT ONE WILL NOT FIT YET - TAKE SOMETHING OFF FIRST",
	ShipHintText.ID_REFUSED_NO_TOUCH: "THESE TWO DO NOT TOUCH - SLIDE ONE INTO THE OTHER",
	ShipHintText.ID_MODAL_TUTORIAL: "",
	ShipHintText.ID_MODAL_LEGEND: "LET GO OF ? TO CLOSE",
	ShipHintText.ID_MODAL_DIALOG: "ANSWER THE BOX ON THE SCREEN TO CARRY ON",
	ShipHintText.ID_BAKING: "BUILDING YOUR SHIP - THIS TAKES A MOMENT",
	ShipHintText.ID_TYPING: "TYPE THE NUMBER THEN PRESS ENTER",
	ShipHintText.ID_FLY: "FLYING - W A S D MOVES YOU, SPACE STOPS YOU, V BRINGS YOU BACK",
	ShipHintText.ID_DRAG_RING: "TURNING - LET GO TO KEEP IT, ESC TO PUT IT BACK",
	ShipHintText.ID_DRAG_STRETCH: "STRETCHING - LET GO TO KEEP IT",
	ShipHintText.ID_DRAG_OFFSET: "LIFTING IT OFF - LET GO TO KEEP IT",
	ShipHintText.ID_DRAG_COLLAR: "SLIDING IT ROUND - LET GO WHEN IT LOOKS RIGHT",
	ShipHintText.ID_PLACE_MIRRORED: "THIS MAKES TWO - ONE ON EACH SIDE. CLICK TO PLACE.",
	ShipHintText.ID_PLACE_SNAPPED: "SNAPPED TO THE NOSE - CLICK TO STICK IT ON",
	ShipHintText.ID_PLACE_FREE: "GOOD SPOT - CLICK TO STICK IT ON",
	ShipHintText.ID_PLACE_EMPTY: "POINT AT YOUR SHIP - PARTS STICK ONTO OTHER PARTS",
	ShipHintText.ID_AXIS_LOCK: "LOCKED TO X - PRESS X AGAIN TO FREE IT",
	ShipHintText.ID_PROMOTION: "YOU HAVE THE HANG OF THIS - SHOW THE NUMBERS?",
	ShipHintText.ID_ECHO_UNDO_EMPTY: "NOTHING LEFT TO UNDO - THIS IS WHERE YOU STARTED",
	ShipHintText.ID_ECHO_UNDO: "UNDID: PLACE PART",
	ShipHintText.ID_ECHO_DELETE: "REMOVED 3 PARTS",
	ShipHintText.ID_ECHO_COMMIT: "PUT THE WING ON. CTRL+Z IF THAT WAS WRONG.",
	ShipHintText.ID_ECHO_STATUS: "SELECTED p_0003",
	ShipHintText.ID_HOVER_RING: "DRAG THIS RING TO TURN IT - IT CLICKS EVERY 5 DEGREES",
	ShipHintText.ID_HOVER_COLLAR: "DRAG THIS COLLAR TO SLIDE IT ROUND THE PART BELOW",
	ShipHintText.ID_HOVER_STRETCH: "DRAG THIS ARROW TO MAKE IT LONGER OR SHORTER",
	ShipHintText.ID_HOVER_OFFSET: "DRAG THIS STALK TO LIFT IT OFF THE PART BELOW",
	ShipHintText.ID_MODE_CHANGED: "SHAPE MODE - NUMBERS ON THE RIGHT, PART LIST ON THE LEFT",
	ShipHintText.ID_EMPTY_DOC: "PICK A SHAPE ON THE LEFT TO START YOUR SHIP",
	ShipHintText.ID_EXPLODED: "CLICK A PIECE TO LOOK AT IT - PRESS E TO PUT IT BACK",
	ShipHintText.ID_BAKED: "THIS IS THE FINISHED SHIP - PRESS EDIT TO CHANGE IT",
	ShipHintText.ID_COMPONENT_OPEN: "INSIDE A COMPONENT - PRESS ESC TO COME BACK OUT",
	ShipHintText.ID_SEAM_READY: "PRESS L TO PUT A DOOR BETWEEN THESE TWO",
	ShipHintText.ID_SELECTED_MANY: "4 PARTS PICKED UP - BIN, COPY AND MIRROR HIT THEM ALL",
	ShipHintText.ID_SELECTED_ONE: "BOX HULL PICKED UP - DRAG THE RING TO TURN IT",
	ShipHintText.ID_IDLE: "CLICK A PART TO PICK IT UP - OR PICK A SHAPE TO ADD ONE",
}

## The two states that never own the LEDE (ux.md 3.2.5). They are asserted on their FACTS instead,
## and the ladder underneath them is asserted to be untouched.
const FACTS_ONLY: Dictionary = {
	ShipHintText.ID_HOVER_PART: "BOX HULL · KESSLER",
	ShipHintText.ID_HOVER_CELL: "a round pod for one pilot",
}

## Key names that must never be spelt into a sentence, because `ShipKeymap` is the single source of
## them and a rebound key would leave the prose lying. Single letters are excluded: they appear in
## ordinary words, and the templates reach them through `{turn}`, `{fit}` and the rest regardless.
const SPELT_OUT: Array = ["CTRL", "SHIFT", "ESC", "ENTER", "LMB", "RMB", "DELETE"]


func _state(fields: Dictionary) -> Dictionary:
	var out: Dictionary = ShipHintText.default_state()
	out.merge(fields, true)
	return out


## One state per id, built once and shared by every case below. Each is the smallest state that
## reaches its row of ux.md 3.2.6 - anything extra would make the case assert two things at once.
func _states() -> Dictionary:
	var out: Dictionary = {}
	out[ShipHintText.ID_REFUSED_ROLLBACK] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_REFUSAL: ShipHintText.REFUSAL_ROLLBACK,
			ShipHintText.STATE_GATE: "BBOX 42.0 M > 40.0 M",
		}
	)
	out[ShipHintText.ID_REFUSED_PLACE] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_PLACE: ShipHintText.PLACE_REFUSED,
			ShipHintText.STATE_PLACING: "SPHERE POD",
			ShipHintText.STATE_GATE: "COMPLEXITY 148 + 4 > 148",
		}
	)
	out[ShipHintText.ID_REFUSED_OFF_SHIP] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_DRAG: ShipHintText.DRAG_MOVE,
			ShipHintText.STATE_REFUSAL: ShipHintText.REFUSAL_OFF_SHIP,
			ShipHintText.STATE_OBJECT: "BOX HULL",
		}
	)
	out[ShipHintText.ID_REFUSED_DISABLED] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_REFUSAL: ShipHintText.REFUSAL_DISABLED,
		}
	)
	out[ShipHintText.ID_REFUSED_CELL] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_HOVER_CELL: "HULL RING",
			ShipHintText.STATE_CELL_OK: false,
		}
	)
	out[ShipHintText.ID_REFUSED_NO_TOUCH] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_SELECTION: 2,
			ShipHintText.STATE_TOUCHING: false,
		}
	)
	out[ShipHintText.ID_MODAL_TUTORIAL] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_MODAL: ShipHintText.MODAL_TUTORIAL,
		}
	)
	out[ShipHintText.ID_MODAL_LEGEND] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_MODAL: ShipHintText.MODAL_LEGEND,
		}
	)
	out[ShipHintText.ID_MODAL_DIALOG] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_MODAL: ShipHintText.MODAL_DIALOG,
		}
	)
	out[ShipHintText.ID_BAKING] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_BAKING: true,
			ShipHintText.STATE_STEP: 3,
			ShipHintText.STATE_STEPS: 7,
		}
	)
	out[ShipHintText.ID_TYPING] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_TYPED: "4",
			ShipHintText.STATE_DEGREES: 45.0,
		}
	)
	out[ShipHintText.ID_FLY] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_FLYING: true,
			ShipHintText.STATE_SPEED: 4.0,
		}
	)
	out[ShipHintText.ID_DRAG_RING] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_DRAG: ShipHintText.DRAG_RING,
			ShipHintText.STATE_DELTA: 45.0,
			ShipHintText.STATE_DEGREES: 45.0,
		}
	)
	out[ShipHintText.ID_DRAG_STRETCH] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_DRAG: ShipHintText.DRAG_STRETCH,
			ShipHintText.STATE_METRES: 3.15,
		}
	)
	out[ShipHintText.ID_DRAG_OFFSET] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_DRAG: ShipHintText.DRAG_OFFSET,
			ShipHintText.STATE_METRES: 0.35,
		}
	)
	out[ShipHintText.ID_DRAG_COLLAR] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_DRAG: ShipHintText.DRAG_COLLAR,
			ShipHintText.STATE_HOST: "HULL RING",
		}
	)
	out[ShipHintText.ID_PLACE_MIRRORED] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_PLACE: ShipHintText.PLACE_FREE,
			ShipHintText.STATE_MIRROR: "X",
		}
	)
	out[ShipHintText.ID_PLACE_SNAPPED] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_PLACE: ShipHintText.PLACE_SNAPPED,
			ShipHintText.STATE_TARGET: "THE NOSE",
		}
	)
	out[ShipHintText.ID_PLACE_FREE] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_PLACE: ShipHintText.PLACE_FREE,
		}
	)
	out[ShipHintText.ID_PLACE_EMPTY] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_PLACE: ShipHintText.PLACE_EMPTY,
			ShipHintText.STATE_PLACING: "SPHERE POD",
		}
	)
	out[ShipHintText.ID_AXIS_LOCK] = _state(
		{ShipHintText.STATE_PART_COUNT: 3, ShipHintText.STATE_LOCK: "X"}
	)
	out[ShipHintText.ID_PROMOTION] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_PROMOTION: ShipHintText.MODE_SHAPE,
		}
	)
	out[ShipHintText.ID_ECHO_UNDO_EMPTY] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_ECHO: ShipHintText.ECHO_UNDO_EMPTY,
		}
	)
	out[ShipHintText.ID_ECHO_UNDO] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_ECHO: ShipHintText.ECHO_UNDO,
			ShipHintText.STATE_LABEL: "PLACE PART",
		}
	)
	out[ShipHintText.ID_ECHO_DELETE] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 1,
			ShipHintText.STATE_ECHO: ShipHintText.ECHO_DELETE,
			ShipHintText.STATE_COUNT: 3,
		}
	)
	out[ShipHintText.ID_ECHO_COMMIT] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 4,
			ShipHintText.STATE_ECHO: ShipHintText.ECHO_COMMIT,
			ShipHintText.STATE_LABEL: "WING",
			ShipHintText.STATE_COMPLEXITY: "ROOMY",
		}
	)
	out[ShipHintText.ID_ECHO_STATUS] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_ECHO: ShipHintText.ECHO_STATUS,
			ShipHintText.STATE_STATUS: "SELECTED p_0003",
		}
	)
	out[ShipHintText.ID_HOVER_RING] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_SELECTION: 1,
			ShipHintText.STATE_HOVER_HANDLE: ShipHintText.HANDLE_RING,
			ShipHintText.STATE_AXIS: "Y",
		}
	)
	out[ShipHintText.ID_HOVER_COLLAR] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_SELECTION: 1,
			ShipHintText.STATE_HOVER_HANDLE: ShipHintText.HANDLE_COLLAR,
			ShipHintText.STATE_HOST: "HULL RING",
		}
	)
	out[ShipHintText.ID_HOVER_STRETCH] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_SELECTION: 1,
			ShipHintText.STATE_HOVER_HANDLE: ShipHintText.HANDLE_STRETCH,
			ShipHintText.STATE_AXIS: "+Y",
			ShipHintText.STATE_METRES: 4.0,
		}
	)
	out[ShipHintText.ID_HOVER_OFFSET] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_SELECTION: 1,
			ShipHintText.STATE_HOVER_HANDLE: ShipHintText.HANDLE_OFFSET,
		}
	)
	out[ShipHintText.ID_MODE_CHANGED] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_MODE: ShipHintText.MODE_SHAPE,
			ShipHintText.STATE_MODE_CHANGED: true,
		}
	)
	out[ShipHintText.ID_EMPTY_DOC] = _state({ShipHintText.STATE_PART_COUNT: 0})
	out[ShipHintText.ID_EXPLODED] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_BAKED: true,
			ShipHintText.STATE_EXPLODED: true,
			ShipHintText.STATE_PIECES: 13,
			ShipHintText.STATE_SEAMS: 12,
		}
	)
	out[ShipHintText.ID_BAKED] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_BAKED: true,
			ShipHintText.STATE_PIECES: 13,
		}
	)
	out[ShipHintText.ID_COMPONENT_OPEN] = _state(
		{ShipHintText.STATE_PART_COUNT: 3, ShipHintText.STATE_COMPONENT: "POD BAY"}
	)
	out[ShipHintText.ID_SEAM_READY] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_SELECTION: 2,
			ShipHintText.STATE_TOUCHING: true,
			ShipHintText.STATE_SEAM: "WALL",
		}
	)
	out[ShipHintText.ID_SELECTED_MANY] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 6,
			ShipHintText.STATE_SELECTION: 4,
			ShipHintText.STATE_DIFFER: true,
		}
	)
	out[ShipHintText.ID_SELECTED_ONE] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_SELECTION: 1,
			ShipHintText.STATE_INDEX: 1,
			ShipHintText.STATE_OBJECT: "BOX HULL",
		}
	)
	out[ShipHintText.ID_IDLE] = _state({ShipHintText.STATE_PART_COUNT: 3})
	out[ShipHintText.ID_HOVER_PART] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_HOVER_PART: "BOX HULL",
			ShipHintText.STATE_MAKER: "KESSLER",
		}
	)
	out[ShipHintText.ID_HOVER_CELL] = _state(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_HOVER_CELL: "SPHERE POD",
			ShipHintText.STATE_CELL_DESC: "a round pod for one pilot",
		}
	)
	return out


func _expect(id: String) -> Dictionary:
	var out: Dictionary = ShipHintText.resolve(_states()[id] as Dictionary)
	(
		assert_str(str(out[ShipHintText.OUT_ID]))
		. append_failure_message("the ladder picked the wrong state for %s" % id)
		. is_equal(id)
	)
	assert_str(str(out[ShipHintText.OUT_LEDE])).is_equal(str(CASES[id]))
	return out


func _lede(fields: Dictionary) -> String:
	return str(ShipHintText.resolve(_state(fields))[ShipHintText.OUT_LEDE])


func _id(fields: Dictionary) -> String:
	return str(ShipHintText.resolve(_state(fields))[ShipHintText.OUT_ID])


## Every line the file can put on the LEDE, with the chords filled in from the fallbacks. Used by
## the length sweep and by the no-spelt-out-keys case, so neither can miss a table.
func _every_template() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for text: Variant in ShipHintText.LEDE.values():
		out.append(str(text))
	for text: Variant in ShipHintText.PROMOTION_LEDE.values():
		out.append(str(text))
	for text: Variant in ShipHintText.MODE_LEDE.values():
		out.append(str(text))
	out.append(ShipHintText.HOVER_RING_FREE)
	return out


# --- one case per state -------------------------------------------------------------------------


## The whole of ux.md 3.2.6, asserted string by string. A failure here is either a deliberate
## rewording - change the literal in CASES too - or a state that has started resolving to the
## wrong row of the table.
##
## `test_parameters` is gdUnit4's own name for the case list and the runner reads it off the
## signature rather than out of the body, so gdlint is told once that it is not dead.
func test_every_state_says_its_exact_line(
	id: String,
	# gdlint:ignore = unused-argument
	test_parameters := [
		["refused_rollback"],
		["refused_place"],
		["refused_off_ship"],
		["refused_disabled"],
		["refused_cell"],
		["refused_no_touch"],
		["modal_tutorial"],
		["modal_legend"],
		["modal_dialog"],
		["baking"],
		["typing"],
		["fly"],
		["drag_ring"],
		["drag_stretch"],
		["drag_offset"],
		["drag_collar"],
		["place_mirrored"],
		["place_snapped"],
		["place_free"],
		["place_empty"],
		["axis_lock"],
		["promotion"],
		["echo_undo_empty"],
		["echo_undo"],
		["echo_delete"],
		["echo_commit"],
		["echo_status"],
		["hover_ring"],
		["hover_collar"],
		["hover_stretch"],
		["hover_offset"],
		["mode_changed"],
		["empty_doc"],
		["exploded"],
		["baked"],
		["component_open"],
		["seam_ready"],
		["selected_many"],
		["selected_one"],
		["idle"],
	]
) -> void:
	_expect(id)


## The parameter list above and the file's own list must be the same set, minus the two states
## that write FACTS and never the LEDE. Without this, adding a state and forgetting its case
## costs nothing and the new sentence ships untested.
func test_every_state_is_covered_once() -> void:
	var ids: Array = ShipHintText.STATE_IDS
	assert_int(CASES.size() + FACTS_ONLY.size()).is_equal(ids.size())
	for id: String in ids:
		(
			assert_bool(CASES.has(id) or FACTS_ONLY.has(id))
			. append_failure_message("state %s has no case" % id)
			. is_true()
		)


## Four tables, one row each, or a state resolves to a missing key at runtime.
func test_the_tables_have_an_entry_for_every_state() -> void:
	for id: String in ShipHintText.STATE_IDS:
		(
			assert_bool(
				(
					ShipHintText.LEDE.has(id)
					and ShipHintText.SUB.has(id)
					and ShipHintText.FACTS.has(id)
					and ShipHintText.CHIPS.has(id)
					and ShipHintText.RUNG.has(id)
				)
			)
			. append_failure_message("state %s is missing from a table" % id)
			. is_true()
		)


## The 62-character cap of ux.md 3.2.1, on the templates AND on what actually comes out. The
## resolver clamps, so this is really asserting that no literal ever needs the clamp - a clamped
## sentence loses its last word, which for an instruction is the worst possible place to cut.
func test_every_line_fits_the_lede_zone() -> void:
	for id: String in CASES:
		var line: String = str(CASES[id])
		assert_int(line.length()).append_failure_message("%s: %s" % [id, line]).is_less_equal(62)
		if id != ShipHintText.ID_MODAL_TUTORIAL:
			assert_str(line).append_failure_message("%s is blank" % id).is_not_empty()
	for id: String in _states():
		var out: Dictionary = ShipHintText.resolve(_states()[id] as Dictionary)
		assert_int(str(out[ShipHintText.OUT_LEDE]).length()).is_less_equal(62)
		assert_int(str(out[ShipHintText.OUT_NEXT]).length()).is_less_equal(62)
	# And the clamp itself, for the one input the resolver cannot vet: a caller's own line.
	var long: String = _lede(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_ECHO: ShipHintText.ECHO_STATUS,
			ShipHintText.STATE_STATUS: "X".repeat(200),
		}
	)
	assert_int(long.length()).is_equal(62)


## `ShipKeymap` owns the key names (ux.md 3.6). A sentence with one typed into it is a second
## source that goes stale the day a binding moves, which is exactly how today's legend ended up
## advertising WHEEL ZOOM for a wheel that scales.
func test_no_sentence_spells_out_a_key() -> void:
	for template: String in _every_template():
		for spelt: String in SPELT_OUT:
			(
				assert_bool(template.contains(spelt))
				. append_failure_message("'%s' spells out %s" % [template, spelt])
				. is_false()
			)


func test_a_chord_passed_in_replaces_the_fallback() -> void:
	var fields: Dictionary = _states()[ShipHintText.ID_ECHO_COMMIT] as Dictionary
	var swapped: Dictionary = fields.duplicate()
	swapped[ShipHintText.STATE_CHORDS] = {"undo": "CMD+Z"}
	var out: Dictionary = ShipHintText.resolve(swapped)
	assert_str(str(out[ShipHintText.OUT_LEDE])).is_equal(
		"PUT THE WING ON. CMD+Z IF THAT WAS WRONG."
	)
	var chips: Array = out[ShipHintText.OUT_CHIPS] as Array
	assert_str(str((chips[0] as Dictionary)[ShipHintText.CHIP_KEY])).is_equal("CMD+Z")


# --- the two FACTS-only channels -----------------------------------------------------------------


## ux.md 3.2.5: "Hovering a part is self-evident and is demoted to FACTS, where it can change at
## 60 Hz without disturbing the instruction." The instruction here is the idle invitation, and it
## must survive the pointer crossing the ship.
func test_a_hovered_part_writes_facts_and_not_the_lede() -> void:
	var out: Dictionary = ShipHintText.resolve(_states()[ShipHintText.ID_HOVER_PART] as Dictionary)
	assert_str(str(out[ShipHintText.OUT_ID])).is_equal(ShipHintText.ID_IDLE)
	assert_str(str(out[ShipHintText.OUT_LEDE])).is_equal(str(CASES[ShipHintText.ID_IDLE]))
	assert_str(str(out[ShipHintText.OUT_FACTS])).is_equal(
		str(FACTS_ONLY[ShipHintText.ID_HOVER_PART])
	)


func test_a_hovered_cell_writes_facts_and_the_chip() -> void:
	var out: Dictionary = ShipHintText.resolve(_states()[ShipHintText.ID_HOVER_CELL] as Dictionary)
	assert_str(str(out[ShipHintText.OUT_ID])).is_equal(ShipHintText.ID_IDLE)
	assert_str(str(out[ShipHintText.OUT_FACTS])).is_equal(
		str(FACTS_ONLY[ShipHintText.ID_HOVER_CELL])
	)
	var chips: Array = out[ShipHintText.OUT_CHIPS] as Array
	assert_int(chips.size()).is_equal(1)
	assert_str(str((chips[0] as Dictionary)[ShipHintText.CHIP_VERB])).is_equal("TAKE IT")


# --- the priority ladder --------------------------------------------------------------------------
# ux.md 3.2.5, rung by rung. Each case makes two or three conditions true at once and asserts which
# one owns the LEDE, because that is the part the design document says will be wrong if improvised.


func test_a_refusal_outranks_a_modal() -> void:
	var id: String = _id(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_REFUSAL: ShipHintText.REFUSAL_ROLLBACK,
			ShipHintText.STATE_MODAL: ShipHintText.MODAL_DIALOG,
		}
	)
	assert_str(id).is_equal(ShipHintText.ID_REFUSED_ROLLBACK)


func test_a_modal_outranks_a_gesture() -> void:
	var id: String = _id(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_MODAL: ShipHintText.MODAL_DIALOG,
			ShipHintText.STATE_DRAG: ShipHintText.DRAG_RING,
		}
	)
	assert_str(id).is_equal(ShipHintText.ID_MODAL_DIALOG)


## A gesture beats the echo of the last one, and an echo beats a hovered handle: the thing the
## hands are doing now, then the thing that just happened, then the thing they might do next.
func test_a_gesture_then_an_echo_then_a_hover() -> void:
	var live: String = _id(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_DRAG: ShipHintText.DRAG_RING,
			ShipHintText.STATE_ECHO: ShipHintText.ECHO_COMMIT,
			ShipHintText.STATE_HOVER_HANDLE: ShipHintText.HANDLE_RING,
		}
	)
	assert_str(live).is_equal(ShipHintText.ID_DRAG_RING)
	var echoed: String = _id(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_ECHO: ShipHintText.ECHO_COMMIT,
			ShipHintText.STATE_HOVER_HANDLE: ShipHintText.HANDLE_RING,
		}
	)
	assert_str(echoed).is_equal(ShipHintText.ID_ECHO_COMMIT)


## Rung 4 over rung 5 - the one arbitration the design turns on. A ring, an arrow, a stalk and a
## collar are visually indistinguishable, so naming the one under the pointer beats naming the
## part that is already selected and visibly highlighted.
func test_a_handle_hover_outranks_the_selection() -> void:
	var id: String = _id(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_SELECTION: 1,
			ShipHintText.STATE_OBJECT: "BOX HULL",
			ShipHintText.STATE_HOVER_HANDLE: ShipHintText.HANDLE_COLLAR,
		}
	)
	assert_str(id).is_equal(ShipHintText.ID_HOVER_COLLAR)


## The standing "these two do not touch" is filed at rung 0, but it must not sit on top of the
## very drag that fixes it - the only rung-0 state that waits for the hands to be free.
func test_a_standing_no_seam_yields_to_a_live_drag() -> void:
	var fields: Dictionary = {
		ShipHintText.STATE_PART_COUNT: 3,
		ShipHintText.STATE_SELECTION: 2,
		ShipHintText.STATE_TOUCHING: false,
	}
	assert_str(_id(fields)).is_equal(ShipHintText.ID_REFUSED_NO_TOUCH)
	var dragging: Dictionary = fields.duplicate()
	dragging[ShipHintText.STATE_DRAG] = ShipHintText.DRAG_COLLAR
	assert_str(_id(dragging)).is_equal(ShipHintText.ID_DRAG_COLLAR)


## Inside rung 2: a bake takes the view away, so it heads the rung; the axis lock ends it, being a
## flag that is true BETWEEN gestures and already carried by the mode strip.
func test_the_bake_heads_the_gesture_rung_and_the_lock_ends_it() -> void:
	var baking: String = _id(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_BAKING: true,
			ShipHintText.STATE_TYPED: "4",
			ShipHintText.STATE_DRAG: ShipHintText.DRAG_RING,
		}
	)
	assert_str(baking).is_equal(ShipHintText.ID_BAKING)
	var locked_and_dragging: String = _id(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_LOCK: "X",
			ShipHintText.STATE_DRAG: ShipHintText.DRAG_RING,
		}
	)
	assert_str(locked_and_dragging).is_equal(ShipHintText.ID_DRAG_RING)
	var locked: String = _id({ShipHintText.STATE_PART_COUNT: 3, ShipHintText.STATE_LOCK: "X"})
	assert_str(locked).is_equal(ShipHintText.ID_AXIS_LOCK)


## A legal ghost with symmetry on announces the twin before the surface: the surprise is that one
## click makes two parts, and FACTS still names the plane underneath.
func test_symmetry_speaks_before_the_surface() -> void:
	var out: Dictionary = (
		ShipHintText
		. resolve(
			_state(
				{
					ShipHintText.STATE_PART_COUNT: 3,
					ShipHintText.STATE_PLACE: ShipHintText.PLACE_SNAPPED,
					ShipHintText.STATE_TARGET: "THE NOSE",
					ShipHintText.STATE_MIRROR: "X",
				}
			)
		)
	)
	assert_str(str(out[ShipHintText.OUT_ID])).is_equal(ShipHintText.ID_PLACE_MIRRORED)
	assert_str(str(out[ShipHintText.OUT_FACTS])).is_equal("MIRROR X · COSTS DOUBLE")


## Inside rung 3 the offer heads the rung: an echo that loses two seconds costs nothing, an
## unanswered question costs the eight it was given.
func test_the_promotion_offer_heads_the_transient_rung() -> void:
	var out: Dictionary = (
		ShipHintText
		. resolve(
			_state(
				{
					ShipHintText.STATE_PART_COUNT: 3,
					ShipHintText.STATE_PROMOTION: ShipHintText.MODE_ENGINEER,
					ShipHintText.STATE_ECHO: ShipHintText.ECHO_COMMIT,
					ShipHintText.STATE_LABEL: "WING",
				}
			)
		)
	)
	assert_str(str(out[ShipHintText.OUT_ID])).is_equal(ShipHintText.ID_PROMOTION)
	assert_str(str(out[ShipHintText.OUT_LEDE])).is_equal(
		"DOORS, ROOMS AND SHAPE DIALS LIVE IN ENGINEER - TURN IT ON?"
	)


## Three deep, which is the case an improvised ladder gets wrong: the lowest rung still wins.
func test_the_lowest_rung_wins_three_deep() -> void:
	var out: Dictionary = (
		ShipHintText
		. resolve(
			_state(
				{
					ShipHintText.STATE_PART_COUNT: 3,
					ShipHintText.STATE_PLACE: ShipHintText.PLACE_REFUSED,
					ShipHintText.STATE_MODAL: ShipHintText.MODAL_TUTORIAL,
					ShipHintText.STATE_DRAG: ShipHintText.DRAG_RING,
					ShipHintText.STATE_HOVER_HANDLE: ShipHintText.HANDLE_RING,
					ShipHintText.STATE_SELECTION: 1,
				}
			)
		)
	)
	assert_int(int(out[ShipHintText.OUT_RUNG])).is_equal(0)
	assert_str(str(out[ShipHintText.OUT_ID])).is_equal(ShipHintText.ID_REFUSED_PLACE)


## Inside rung 5: a mode change announces itself first, an empty document next, and an exploded
## view before the baked one it is a sub-state of.
func test_the_last_rung_orders_mode_then_document_then_view() -> void:
	var changed: String = _id(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_MODE_CHANGED: true,
			ShipHintText.STATE_SELECTION: 1,
		}
	)
	assert_str(changed).is_equal(ShipHintText.ID_MODE_CHANGED)
	var empty: String = _id({ShipHintText.STATE_PART_COUNT: 0, ShipHintText.STATE_SELECTION: 1})
	assert_str(empty).is_equal(ShipHintText.ID_EMPTY_DOC)
	var blown: String = _id(
		{
			ShipHintText.STATE_PART_COUNT: 3,
			ShipHintText.STATE_BAKED: true,
			ShipHintText.STATE_EXPLODED: true,
		}
	)
	assert_str(blown).is_equal(ShipHintText.ID_EXPLODED)


## The tutorial card is the only teacher on screen while it is up (ux.md 3.2.5 rung 1), but the
## readout and the chips underneath it stay live.
func test_the_tutorial_card_blanks_the_lede_and_keeps_the_rest() -> void:
	var out: Dictionary = (
		ShipHintText
		. resolve(
			_state(
				{
					ShipHintText.STATE_PART_COUNT: 3,
					ShipHintText.STATE_MODAL: ShipHintText.MODAL_TUTORIAL,
					ShipHintText.STATE_SELECTION: 1,
					ShipHintText.STATE_INDEX: 1,
					ShipHintText.STATE_OBJECT: "BOX HULL",
				}
			)
		)
	)
	assert_str(str(out[ShipHintText.OUT_LEDE])).is_empty()
	assert_str(str(out[ShipHintText.OUT_SUB])).is_empty()
	assert_str(str(out[ShipHintText.OUT_FACTS])).is_equal("BOX HULL · 1 OF 3")
	assert_int((out[ShipHintText.OUT_CHIPS] as Array).size()).is_equal(3)


# --- verbosity decay ------------------------------------------------------------------------------


## Four exposures drop line two; nine drop the sentence to the object's name. The decay state is
## the caller's - the resolver only ever reads the count it is handed, which is what keeps it pure.
## The thresholds are asserted first because everything below them is built on the boundaries.
func test_decay_drops_the_second_line_then_the_sentence() -> void:
	assert_int(ShipHintText.verbosity(0)).is_equal(ShipHintText.FULL)
	assert_int(ShipHintText.verbosity(3)).is_equal(ShipHintText.FULL)
	assert_int(ShipHintText.verbosity(4)).is_equal(ShipHintText.SHORT)
	assert_int(ShipHintText.verbosity(8)).is_equal(ShipHintText.SHORT)
	assert_int(ShipHintText.verbosity(9)).is_equal(ShipHintText.QUIET)
	assert_int(ShipHintText.verbosity(900)).is_equal(ShipHintText.QUIET)
	var fields: Dictionary = _states()[ShipHintText.ID_SELECTED_ONE] as Dictionary
	var full: Dictionary = ShipHintText.resolve(fields)
	assert_str(str(full[ShipHintText.OUT_SUB])).is_equal("or drag the collar to slide it round")
	var short_form: Dictionary = fields.duplicate()
	short_form[ShipHintText.STATE_SEEN] = 4
	var out: Dictionary = ShipHintText.resolve(short_form)
	assert_str(str(out[ShipHintText.OUT_LEDE])).is_equal(str(CASES[ShipHintText.ID_SELECTED_ONE]))
	assert_str(str(out[ShipHintText.OUT_SUB])).is_empty()
	var quiet: Dictionary = fields.duplicate()
	quiet[ShipHintText.STATE_SEEN] = 9
	out = ShipHintText.resolve(quiet)
	assert_str(str(out[ShipHintText.OUT_LEDE])).is_equal("BOX HULL")
	assert_int((out[ShipHintText.OUT_CHIPS] as Array).size()).is_equal(3)


## A quiet state with no object to name falls back to the readout rather than going blank: ux.md
## 3.2.5 says the bar is never silent, and rung 5 always exists.
func test_a_quiet_state_with_no_object_falls_back_to_the_readout() -> void:
	var out: Dictionary = ShipHintText.resolve(
		_state({ShipHintText.STATE_PART_COUNT: 3, ShipHintText.STATE_SEEN: 12})
	)
	assert_str(str(out[ShipHintText.OUT_LEDE])).is_equal("3 PARTS")


## The inverse ramp. "Guidance that only ever recedes abandons exactly the person it was written
## for" - three refusals of a kind and the caller insists, which restores the full form and adds
## the remedy to line two.
func test_insisting_restores_the_full_form_with_a_remedy() -> void:
	var out: Dictionary = (
		ShipHintText
		. resolve(
			_state(
				{
					ShipHintText.STATE_PART_COUNT: 3,
					ShipHintText.STATE_SELECTION: 1,
					ShipHintText.STATE_OBJECT: "BOX HULL",
					ShipHintText.STATE_INDEX: 1,
					ShipHintText.STATE_SEEN: 40,
					ShipHintText.STATE_INSIST: true,
					ShipHintText.STATE_REMEDY: "the green ring is the one that turns it",
				}
			)
		)
	)
	assert_int(int(out[ShipHintText.OUT_LEVEL])).is_equal(ShipHintText.FULL)
	assert_str(str(out[ShipHintText.OUT_LEDE])).is_equal(str(CASES[ShipHintText.ID_SELECTED_ONE]))
	assert_str(str(out[ShipHintText.OUT_SUB])).is_equal(
		"or drag the collar to slide it round - the green ring is the one that turns it"
	)


## A refusal that has gone quiet is a refusal the player cannot act on, and a modal's line is the
## only thing naming what has taken the screen. Neither rung decays, at any exposure count.
func test_a_refusal_and_a_modal_never_decay() -> void:
	var refused: Dictionary = (_states()[ShipHintText.ID_REFUSED_PLACE] as Dictionary).duplicate()
	refused[ShipHintText.STATE_SEEN] = 99
	var out: Dictionary = ShipHintText.resolve(refused)
	assert_int(int(out[ShipHintText.OUT_LEVEL])).is_equal(ShipHintText.FULL)
	assert_str(str(out[ShipHintText.OUT_LEDE])).is_equal(str(CASES[ShipHintText.ID_REFUSED_PLACE]))
	assert_str(str(out[ShipHintText.OUT_SUB])).is_equal("COMPLEXITY 148 + 4 > 148")
	var modal: Dictionary = (_states()[ShipHintText.ID_MODAL_LEGEND] as Dictionary).duplicate()
	modal[ShipHintText.STATE_SEEN] = 99
	assert_int(int(ShipHintText.resolve(modal)[ShipHintText.OUT_LEVEL])).is_equal(ShipHintText.FULL)


## The three modes are three seed values for one counter (ux.md 3.2.3) - the cheapest structural
## idea in the set, and the reason the prose is not maintained three times over.
func test_the_modes_are_three_seeds_for_one_counter() -> void:
	assert_int(ShipHintText.seed_for(ShipHintText.MODE_BUILD)).is_equal(0)
	assert_int(ShipHintText.seed_for(ShipHintText.MODE_SHAPE)).is_equal(4)
	assert_int(ShipHintText.seed_for(ShipHintText.MODE_ENGINEER)).is_equal(9)
	var seeded: Dictionary = (_states()[ShipHintText.ID_SELECTED_ONE] as Dictionary).duplicate()
	seeded[ShipHintText.STATE_SEEN] = ShipHintText.seed_for(ShipHintText.MODE_ENGINEER)
	assert_int(int(ShipHintText.resolve(seeded)[ShipHintText.OUT_LEVEL])).is_equal(
		ShipHintText.QUIET
	)


# --- the mode strip, the chips and NEXT -----------------------------------------------------------


## The strip of ux.md 3.2.4, character for character as the document draws it. It exists because
## deleting the ten-line legend deletes the only display of two stateful toggles, one of which
## forks a ring drag into a different geometric verb.
func test_the_mode_strip_is_the_documented_format() -> void:
	var fields: Dictionary = {
		ShipHintText.STATE_PART_COUNT: 3,
		ShipHintText.STATE_MODE: ShipHintText.MODE_ENGINEER,
		ShipHintText.STATE_MIRROR: "X",
	}
	var out: Dictionary = ShipHintText.resolve(_state(fields))
	assert_str(str(out[ShipHintText.OUT_STRIP])).is_equal(
		"PIVOT FLOAT · AIM NORM · SNAP 5° · MIRROR X · LOCK -"
	)
	# BUILD binds neither toggle nor the lock, so it carries the two fields that are true there.
	var build: Dictionary = fields.duplicate()
	build[ShipHintText.STATE_MODE] = ShipHintText.MODE_BUILD
	out = ShipHintText.resolve(_state(build))
	assert_str(str(out[ShipHintText.OUT_STRIP])).is_equal("SNAP 5° · MIRROR X")
	var off: Dictionary = build.duplicate()
	off[ShipHintText.STATE_SNAP_DEG] = 0.0
	off[ShipHintText.STATE_MIRROR] = ""
	out = ShipHintText.resolve(_state(off))
	assert_str(str(out[ShipHintText.OUT_STRIP])).is_equal("SNAP OFF · MIRROR OFF")


## "Always present, never rewritten by hover" - the strip is the one zone the ladder does not own.
func test_the_mode_strip_ignores_hover_and_the_rung() -> void:
	var fields: Dictionary = {
		ShipHintText.STATE_PART_COUNT: 3,
		ShipHintText.STATE_MODE: ShipHintText.MODE_SHAPE,
		ShipHintText.STATE_PIVOT_HELD: true,
	}
	var idle: String = str(ShipHintText.resolve(_state(fields))[ShipHintText.OUT_STRIP])
	var busy: Dictionary = fields.duplicate()
	busy[ShipHintText.STATE_HOVER_HANDLE] = ShipHintText.HANDLE_RING
	busy[ShipHintText.STATE_DRAG] = ShipHintText.DRAG_RING
	busy[ShipHintText.STATE_REFUSAL] = ShipHintText.REFUSAL_ROLLBACK
	assert_str(str(ShipHintText.resolve(_state(busy))[ShipHintText.OUT_STRIP])).is_equal(idle)
	assert_str(idle).contains("PIVOT STUCK")


## ux.md 3.2.1 caps the row at three chips in BUILD. Today every state fits that, which is worth
## asserting: the day a state wants a fourth, the cap silently drops it in the mode a child uses.
func test_the_chip_row_fits_the_smallest_mode() -> void:
	assert_array(ShipHintText.CHIP_CAP).contains_exactly([3, 4, 6])
	for id: String in ShipHintText.STATE_IDS:
		var chips: Array = ShipHintText.CHIPS[id] as Array
		(
			assert_int(chips.size())
			. append_failure_message("%s declares %d chips" % [id, chips.size()])
			. is_less_equal(3)
		)


## NEXT reads the document and the budget only. A gesture cannot move it, which is how "frozen for
## the entire duration of any gesture" is kept structurally instead of by a renderer remembering.
func test_the_next_button_is_frozen_during_a_gesture() -> void:
	var fields: Dictionary = {ShipHintText.STATE_PART_COUNT: 3, ShipHintText.STATE_STALE: true}
	var still: Dictionary = ShipHintText.resolve(_state(fields))
	var busy: Dictionary = fields.duplicate()
	busy[ShipHintText.STATE_DRAG] = ShipHintText.DRAG_RING
	busy[ShipHintText.STATE_HOVER_HANDLE] = ShipHintText.HANDLE_RING
	busy[ShipHintText.STATE_HOVER_PART] = "SPHERE POD"
	var moving: Dictionary = ShipHintText.resolve(_state(busy))
	assert_str(str(moving[ShipHintText.OUT_NEXT])).is_equal(str(still[ShipHintText.OUT_NEXT]))
	assert_str(str(moving[ShipHintText.OUT_TONE])).is_equal(str(still[ShipHintText.OUT_TONE]))


func test_the_next_button_names_the_blocker() -> void:
	var empty: Dictionary = ShipHintText.resolve(_state({}))
	assert_str(str(empty[ShipHintText.OUT_NEXT])).is_equal(ShipHintText.NEXT_PICK)
	assert_str(str(empty[ShipHintText.OUT_TONE])).is_equal(ShipHintText.TONE_DIM)
	var stale: Dictionary = ShipHintText.resolve(
		_state({ShipHintText.STATE_PART_COUNT: 3, ShipHintText.STATE_STALE: true})
	)
	assert_str(str(stale[ShipHintText.OUT_NEXT])).is_equal(ShipHintText.NEXT_STALE)
	assert_str(str(stale[ShipHintText.OUT_TONE])).is_equal(ShipHintText.TONE_ACCENT)
	var over: Dictionary = (
		ShipHintText
		. resolve(
			_state(
				{
					ShipHintText.STATE_PART_COUNT: 3,
					ShipHintText.STATE_STALE: true,
					ShipHintText.STATE_BUDGET: "TOO BIG",
				}
			)
		)
	)
	assert_str(str(over[ShipHintText.OUT_NEXT])).is_equal("TOO BIG")
	assert_str(str(over[ShipHintText.OUT_TONE])).is_equal(ShipHintText.TONE_WARNING)
	var baked: Dictionary = ShipHintText.resolve(_states()[ShipHintText.ID_BAKED] as Dictionary)
	assert_str(str(baked[ShipHintText.OUT_NEXT])).is_equal(ShipHintText.NEXT_EDIT)


# --- purity ------------------------------------------------------------------------------


## Same state in, same strings out, and the caller's Dictionary comes back untouched. AGENTS
## section 2: "Never mutate an argument - return new values." A resolver that edited the state it
## was handed would corrupt the very snapshot the renderer diffs against to decide whether to
## repaint, and the bar would flicker at 60 Hz for reasons nobody could find.
func test_the_resolver_is_pure_and_repeatable() -> void:
	var fields: Dictionary = _states()[ShipHintText.ID_DRAG_RING] as Dictionary
	var before: Dictionary = fields.duplicate(true)
	var first: Dictionary = ShipHintText.resolve(fields)
	var second: Dictionary = ShipHintText.resolve(fields)
	assert_dict(fields).is_equal(before)
	assert_str(str(first[ShipHintText.OUT_LEDE])).is_equal(str(second[ShipHintText.OUT_LEDE]))
	assert_str(str(first[ShipHintText.OUT_FACTS])).is_equal(str(second[ShipHintText.OUT_FACTS]))
	assert_str(str(first[ShipHintText.OUT_STRIP])).is_equal(str(second[ShipHintText.OUT_STRIP]))
	# A partial state is legal: anything the caller leaves out comes from the defaults.
	assert_str(str(ShipHintText.resolve({})[ShipHintText.OUT_ID])).is_equal(
		ShipHintText.ID_EMPTY_DOC
	)
	# compose() is resolve() with the mode supplied the way ShipHintBar will supply it.
	var composed: Dictionary = ShipHintText.compose(fields, ShipHintText.MODE_ENGINEER)
	assert_str(str(composed[ShipHintText.OUT_ID])).is_equal(ShipHintText.ID_DRAG_RING)
	assert_int(ShipHintText.rung(fields)).is_equal(2)

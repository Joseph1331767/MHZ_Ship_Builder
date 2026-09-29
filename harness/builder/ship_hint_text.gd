class_name ShipHintText
extends RefCounted
## Every sentence the builder says to the player, and the rules for which one it says.
## `docs/future/ux.md` section 3.2 - the hint bar. Static only, engine-free, deterministic:
## a Dictionary of plain builder state goes in, a Dictionary of finished strings comes out.
##
## THE BRIEF THIS ANSWERS, verbatim: "there needs to be a large hint/tip/directive bar at the
## bottom that should react to any state of the builder, any mouse hover and any state of
## operation. so if user clicks an object, the hint will tell them possible things they can do
## next." The survey behind ux.md section 2.4 found why that does not happen today: `set_status()`
## is the whole guidance channel, 78 call sites, 60 distinct strings, of which FIVE contain an
## instruction and one of those five is a refusal. `SELECTED p_0003` reports; it does not teach.
##
## WHY THE TEXT IS A FILE OF ITS OWN AND NOT A RENDERER. The renderer needs a GPU slot, a theme
## and a scene; the wording, the ladder and the decay need none of the three, and they are the
## parts that will be got wrong. Split here, every literal string and every arbitration rule is a
## headlessly tested artifact - which is also what `.gdlintrc` asks an extraction to be: "a
## self-contained, statically testable unit with no reference back to the file it came from."
## `ShipHintBar` (ux.md section 5.1 step 11) will render what this returns. Nothing reads it yet.
##
## THE FOUR ZONES (ux.md 3.2.1) come back from [method resolve] together:
##   LEDE  - line one, the largest type in the application, an instruction, capped at 62 chars
##   SUB   - line two, dim, the secondary clause or a gate's verbatim refusal
##   FACTS - right-aligned schema line, plus STRIP, the always-present toggle strip (3.2.4)
##   CHIPS - `[KEY] VERB` buttons, each one a real verb the renderer wires up
##   NEXT  - one button carrying the highest-priority blocker, with the palette role to draw it in
##
## VERB FIRST, AND SHORT. Written for a child: plain words, no jargon, no part ids in the LEDE.
## The 62-character cap is not a style preference - it is what fits the LEDE zone at
## `font_title()` in a 1280-wide virtual console, so [method resolve] CLAMPS rather than trusts.
##
## NO KEY NAME IS SPELT INTO A SENTENCE. Every chord arrives through [constant STATE_CHORDS] with
## a fallback from [constant CHORD_FALLBACK], because `ShipKeymap` (ux.md 3.6, step 5) is being
## written to be the single source of those strings and a sentence with `CTRL+Z` baked into it
## would be a second source the day a binding moves. This file does not reference that class: it
## may not be on disk yet, and an unimported `class_name` does not parse.
##
## THE DECAY STATE LIVES OUTSIDE (ux.md 3.2.3). The caller passes [constant STATE_SEEN], an
## exposure count for the state it is about to show, and gets full / short / quiet wording back.
## Keeping the counter out here is what keeps this function pure: same state in, same strings out,
## no clock, no file, no `user://`. The three UI modes are three SEED values for that counter -
## 0, 4, 9, see [method seed_for] - so three verbosity levels cost one integer rather than three
## maintained copies of the prose.

## UI modes. `ShipUiMode` (ux.md step 14) will own the enum and is the single owner of the live
## value; these three ints exist only so this file can be written and tested before it lands, and
## they MUST keep matching it. Nothing here branches on mode to change behaviour - only how much
## is said (chip count, strip fields), per ux.md 3.1 rule 2.
const MODE_BUILD: int = 0
const MODE_SHAPE: int = 1
const MODE_ENGINEER: int = 2

## Hard cap on LEDE, in characters. [method resolve] truncates to it; the suite asserts it.
const LEDE_MAX: int = 62

## Verbosity levels out of [method verbosity].
const FULL: int = 0  # LEDE + SUB
const SHORT: int = 1  # LEDE only
const QUIET: int = 2  # chips only; LEDE falls back to the object's name

## How many chips a mode may show at once (ux.md 3.2.1: at 13 px three fit in the 300 px zone and
## six do not, so the cap is per mode and not per state).
const CHIP_CAP: Array = [3, 4, 6]

## Exposure seeds per mode - the whole of the mode's effect on wording (ux.md 3.2.3).
const SEEN_SEED: Array = [0, 4, 9]

# --- state keys -------------------------------------------------------------------------------
# The named-constant-per-key habit is [ShipSeams]'s (`SEAM_CHILD`, `SEAM_HOST`, ...): a typo in a
# key is then a parse error rather than a silently missing hint.

const STATE_MODE: String = "mode"  # int, one of MODE_*
const STATE_SEEN: String = "seen"  # int, times the resolved state has been COMPLETED before
const STATE_INSIST: String = "insist"  # bool, the inverse ramp - force full wording back on
const STATE_REMEDY: String = "remedy"  # String, what to append when insisting
const STATE_PART_COUNT: String = "part_count"  # int, parts in the document
const STATE_SELECTION: String = "selection"  # int, how many parts are selected
const STATE_INDEX: String = "index"  # int, 1-based rank of the selected part
const STATE_OBJECT: String = "object"  # String, display name of the selected part
const STATE_HOST: String = "host"  # String, display name of the part it stands on
const STATE_DIFFER: String = "differ"  # bool, a multi-selection whose values disagree
const STATE_TOUCHING: String = "touching"  # bool, the two selected parts overlap
const STATE_SEAM: String = "seam"  # String, the seam's kind between them, e.g. "WALL"
const STATE_MODAL: String = "modal"  # String, "" or one of MODAL_*
const STATE_REFUSAL: String = "refusal"  # String, "" or one of REFUSAL_*
const STATE_GATE: String = "gate"  # String, the gate's own message, printed verbatim in SUB
const STATE_DRAG: String = "drag"  # String, "" or one of DRAG_*
const STATE_HOVER_HANDLE: String = "hover_handle"  # String, "" or one of HANDLE_*
const STATE_HOVER_PART: String = "hover_part"  # String, display name of the part under the mouse
const STATE_MAKER: String = "maker"  # String, that part's manufacturer
const STATE_HOVER_CELL: String = "hover_cell"  # String, display name of a palette cell
const STATE_CELL_DESC: String = "cell_desc"  # String, that family's pack description
const STATE_CELL_OK: String = "cell_ok"  # bool, false when a gate refuses the cell
const STATE_PLACING: String = "placing"  # String, display name of the part on the cursor
const STATE_PLACE: String = "place"  # String, "" or one of PLACE_*
const STATE_TARGET: String = "target"  # String, the typed mount point the ghost snapped to
const STATE_MIRROR: String = "mirror"  # String, "" or the mirror plane: "X", "Y", "Z"
const STATE_AXIS: String = "axis"  # String, the axis of the hovered or dragged handle
const STATE_LOCK: String = "lock"  # String, "" or the locked axis
const STATE_DEGREES: String = "degrees"  # float, the live absolute angle
const STATE_DELTA: String = "delta"  # float, the angle turned so far in this drag
const STATE_METRES: String = "metres"  # float, the live length or lift
const STATE_SNAP_DEG: String = "snap_deg"  # float, the angular snap; 0.0 is off
const STATE_SNAP_M: String = "snap_m"  # float, the linear snap
const STATE_TYPED: String = "typed"  # String, digits captured so far; "" when not capturing
const STATE_FLYING: String = "flying"  # bool
const STATE_SPEED: String = "speed"  # float, fly speed in m/s
const STATE_BAKING: String = "baking"  # bool, a bake is running
const STATE_STEP: String = "step"  # int, CSG pass reached
const STATE_STEPS: String = "steps"  # int, CSG passes in total
const STATE_BAKED: String = "baked"  # bool, the baked view is on screen
const STATE_EXPLODED: String = "exploded"  # bool
const STATE_STALE: String = "stale"  # bool, the built meshes no longer match the document
const STATE_PIECES: String = "pieces"  # int, solids in the bake
const STATE_SEAMS: String = "seams"  # int, seams in the bake
const STATE_COMPONENT: String = "component"  # String, name of the component being looked inside
const STATE_ECHO: String = "echo"  # String, "" or one of ECHO_*
const STATE_LABEL: String = "label"  # String, what was done - `ShipHistory.undo_label()`
const STATE_COUNT: String = "count"  # int, how many it was done to
const STATE_STATUS: String = "status"  # String, a raw `set_status()` line
const STATE_PROMOTION: String = "promotion"  # int, -1 or the MODE_* being offered
const STATE_MODE_CHANGED: String = "mode_changed"  # bool, the mode changed a moment ago
const STATE_COMPLEXITY: String = "complexity"  # String, ROOMY / FILLING UP / NEARLY FULL / FULL
const STATE_BUDGET: String = "budget"  # String, "" or the budget that is over
const STATE_PIVOT_HELD: String = "pivot_held"  # bool, attached pivot rather than floating
const STATE_AIM_NORMAL: String = "aim_normal"  # bool, aim at the surface normal
const STATE_CHORDS: String = "chords"  # Dictionary, chord name -> key text, over CHORD_FALLBACK

# --- state vocabularies -----------------------------------------------------------------------

const MODAL_TUTORIAL: String = "tutorial"
const MODAL_LEGEND: String = "legend"
const MODAL_DIALOG: String = "dialog"

const REFUSAL_ROLLBACK: String = "rollback"  # `commit_edit` put the document back
const REFUSAL_OFF_SHIP: String = "off_ship"  # a move drag is out over empty space
const REFUSAL_DISABLED: String = "disabled"  # a control that cannot act was pressed

const DRAG_RING: String = "ring"
const DRAG_STRETCH: String = "stretch"
const DRAG_OFFSET: String = "offset"
const DRAG_COLLAR: String = "collar"
const DRAG_MOVE: String = "move"  # shares the collar's wording - ux.md 3.2.6 pairs the two rows

const HANDLE_RING: String = "ring"
const HANDLE_COLLAR: String = "collar"
const HANDLE_STRETCH: String = "stretch"
const HANDLE_OFFSET: String = "offset"

const PLACE_EMPTY: String = "empty"  # the ghost is over nothing
const PLACE_FREE: String = "free"  # legal, on a bare surface
const PLACE_SNAPPED: String = "snapped"  # legal, on a typed mount point
const PLACE_REFUSED: String = "refused"  # GhostState.PREVENT / INVALID

const ECHO_COMMIT: String = "commit"
const ECHO_DELETE: String = "delete"
const ECHO_UNDO: String = "undo"
const ECHO_UNDO_EMPTY: String = "undo_empty"
const ECHO_STATUS: String = "status"  # the 2.5 s transient every `set_status()` call becomes

# --- output keys ------------------------------------------------------------------------------

const OUT_ID: String = "id"  # String, the state that won - the key the exposure counter counts
const OUT_RUNG: String = "rung"  # int, which rung of the ladder it came from
const OUT_LEVEL: String = "level"  # int, FULL / SHORT / QUIET after decay
const OUT_LEDE: String = "lede"  # String, line one
const OUT_SUB: String = "sub"  # String, line two
const OUT_FACTS: String = "facts"  # String, the schema line
const OUT_STRIP: String = "strip"  # String, the always-present toggle strip
const OUT_CHIPS: String = "chips"  # Array of {CHIP_KEY, CHIP_VERB}
const OUT_NEXT: String = "next"  # String, the NEXT button's label
const OUT_TONE: String = "tone"  # String, palette role for NEXT: text_dim / accent / warning

const CHIP_KEY: String = "key"
const CHIP_VERB: String = "verb"

const TONE_DIM: String = "text_dim"
const TONE_ACCENT: String = "accent"
const TONE_WARNING: String = "warning"

# --- state ids --------------------------------------------------------------------------------
# One per row of ux.md 3.2.6, plus the three the table is silent on (see the file's report).

const ID_REFUSED_ROLLBACK: String = "refused_rollback"
const ID_REFUSED_PLACE: String = "refused_place"
const ID_REFUSED_OFF_SHIP: String = "refused_off_ship"
const ID_REFUSED_DISABLED: String = "refused_disabled"
const ID_REFUSED_CELL: String = "refused_cell"
const ID_REFUSED_NO_TOUCH: String = "refused_no_touch"
const ID_MODAL_TUTORIAL: String = "modal_tutorial"
const ID_MODAL_LEGEND: String = "modal_legend"
const ID_MODAL_DIALOG: String = "modal_dialog"
const ID_BAKING: String = "baking"
const ID_TYPING: String = "typing"
const ID_FLY: String = "fly"
const ID_DRAG_RING: String = "drag_ring"
const ID_DRAG_STRETCH: String = "drag_stretch"
const ID_DRAG_OFFSET: String = "drag_offset"
const ID_DRAG_COLLAR: String = "drag_collar"
const ID_PLACE_MIRRORED: String = "place_mirrored"
const ID_PLACE_SNAPPED: String = "place_snapped"
const ID_PLACE_FREE: String = "place_free"
const ID_PLACE_EMPTY: String = "place_empty"
const ID_AXIS_LOCK: String = "axis_lock"
const ID_PROMOTION: String = "promotion"
const ID_ECHO_UNDO_EMPTY: String = "echo_undo_empty"
const ID_ECHO_UNDO: String = "echo_undo"
const ID_ECHO_DELETE: String = "echo_delete"
const ID_ECHO_COMMIT: String = "echo_commit"
const ID_ECHO_STATUS: String = "echo_status"
const ID_HOVER_RING: String = "hover_ring"
const ID_HOVER_COLLAR: String = "hover_collar"
const ID_HOVER_STRETCH: String = "hover_stretch"
const ID_HOVER_OFFSET: String = "hover_offset"
const ID_MODE_CHANGED: String = "mode_changed"
const ID_EMPTY_DOC: String = "empty_doc"
const ID_EXPLODED: String = "exploded"
const ID_BAKED: String = "baked"
const ID_COMPONENT_OPEN: String = "component_open"
const ID_SEAM_READY: String = "seam_ready"
const ID_SELECTED_MANY: String = "selected_many"
const ID_SELECTED_ONE: String = "selected_one"
const ID_IDLE: String = "idle"
## The two states that never own the LEDE. ux.md 3.2.5: "a part hover writes only FACTS ... it can
## change at 60 Hz without disturbing the instruction." A shelf cell writes FACTS and CHIPS.
const ID_HOVER_PART: String = "hover_part"
const ID_HOVER_CELL: String = "hover_cell"

## Every state this file can name. The suite asserts it has a case and a literal apiece, so a new
## state cannot be added without a test that pins its sentence.
const STATE_IDS: Array = [
	ID_REFUSED_ROLLBACK,
	ID_REFUSED_PLACE,
	ID_REFUSED_OFF_SHIP,
	ID_REFUSED_DISABLED,
	ID_REFUSED_CELL,
	ID_REFUSED_NO_TOUCH,
	ID_MODAL_TUTORIAL,
	ID_MODAL_LEGEND,
	ID_MODAL_DIALOG,
	ID_BAKING,
	ID_TYPING,
	ID_FLY,
	ID_DRAG_RING,
	ID_DRAG_STRETCH,
	ID_DRAG_OFFSET,
	ID_DRAG_COLLAR,
	ID_PLACE_MIRRORED,
	ID_PLACE_SNAPPED,
	ID_PLACE_FREE,
	ID_PLACE_EMPTY,
	ID_AXIS_LOCK,
	ID_PROMOTION,
	ID_ECHO_UNDO_EMPTY,
	ID_ECHO_UNDO,
	ID_ECHO_DELETE,
	ID_ECHO_COMMIT,
	ID_ECHO_STATUS,
	ID_HOVER_RING,
	ID_HOVER_COLLAR,
	ID_HOVER_STRETCH,
	ID_HOVER_OFFSET,
	ID_MODE_CHANGED,
	ID_EMPTY_DOC,
	ID_EXPLODED,
	ID_BAKED,
	ID_COMPONENT_OPEN,
	ID_SEAM_READY,
	ID_SELECTED_MANY,
	ID_SELECTED_ONE,
	ID_IDLE,
	ID_HOVER_PART,
	ID_HOVER_CELL,
]

## Which rung each state sits on. Lowest wins (ux.md 3.2.5): 0 REFUSED, 1 MODAL, 2 GESTURE,
## 3 TRANSIENT, 4 HANDLE HOVER, 5 SELECTION / IDLE. The two FACTS-only states are parked at 5
## because they never reach the ladder at all.
const RUNG: Dictionary = {
	ID_REFUSED_ROLLBACK: 0,
	ID_REFUSED_PLACE: 0,
	ID_REFUSED_OFF_SHIP: 0,
	ID_REFUSED_DISABLED: 0,
	ID_REFUSED_CELL: 0,
	ID_REFUSED_NO_TOUCH: 0,
	ID_MODAL_TUTORIAL: 1,
	ID_MODAL_LEGEND: 1,
	ID_MODAL_DIALOG: 1,
	ID_BAKING: 2,
	ID_TYPING: 2,
	ID_FLY: 2,
	ID_DRAG_RING: 2,
	ID_DRAG_STRETCH: 2,
	ID_DRAG_OFFSET: 2,
	ID_DRAG_COLLAR: 2,
	ID_PLACE_MIRRORED: 2,
	ID_PLACE_SNAPPED: 2,
	ID_PLACE_FREE: 2,
	ID_PLACE_EMPTY: 2,
	ID_AXIS_LOCK: 2,
	ID_PROMOTION: 3,
	ID_ECHO_UNDO_EMPTY: 3,
	ID_ECHO_UNDO: 3,
	ID_ECHO_DELETE: 3,
	ID_ECHO_COMMIT: 3,
	ID_ECHO_STATUS: 3,
	ID_HOVER_RING: 4,
	ID_HOVER_COLLAR: 4,
	ID_HOVER_STRETCH: 4,
	ID_HOVER_OFFSET: 4,
	ID_MODE_CHANGED: 5,
	ID_EMPTY_DOC: 5,
	ID_EXPLODED: 5,
	ID_BAKED: 5,
	ID_COMPONENT_OPEN: 5,
	ID_SEAM_READY: 5,
	ID_SELECTED_MANY: 5,
	ID_SELECTED_ONE: 5,
	ID_IDLE: 5,
	ID_HOVER_PART: 5,
	ID_HOVER_CELL: 5,
}

# --- the words --------------------------------------------------------------------------------
# Templates, filled by `String.format` from one Dictionary built in `_vars`. No branch per state
# and no key name spelt out: `{undo}` is whatever `ShipKeymap` ends up calling it.

## Line one. Verb first, capped at [constant LEDE_MAX]. `""` where the table prints a dash
## (the state does not own the LEDE) or blanks the line on purpose (the tutorial card).
const LEDE: Dictionary = {
	ID_REFUSED_ROLLBACK: "THAT WOULD MAKE IT TOO BIG - SO I PUT IT BACK",
	ID_REFUSED_PLACE: "TOO HEAVY - TAKE SOMETHING OFF FIRST",
	ID_REFUSED_OFF_SHIP: "LET GO OUT HERE AND THE PART GOES IN THE BIN",
	ID_REFUSED_DISABLED: "NEEDS A PART PICKED UP FIRST - CLICK ONE",
	ID_REFUSED_CELL: "THAT ONE WILL NOT FIT YET - TAKE SOMETHING OFF FIRST",
	ID_REFUSED_NO_TOUCH: "THESE TWO DO NOT TOUCH - SLIDE ONE INTO THE OTHER",
	ID_MODAL_TUTORIAL: "",
	ID_MODAL_LEGEND: "LET GO OF {legend} TO CLOSE",
	ID_MODAL_DIALOG: "ANSWER THE BOX ON THE SCREEN TO CARRY ON",
	ID_BAKING: "BUILDING YOUR SHIP - THIS TAKES A MOMENT",
	ID_TYPING: "TYPE THE NUMBER THEN PRESS {enter}",
	ID_FLY: "FLYING - W A S D MOVES YOU, {brake} STOPS YOU, {land} BRINGS YOU BACK",
	ID_DRAG_RING: "TURNING - LET GO TO KEEP IT, {cancel} TO PUT IT BACK",
	ID_DRAG_STRETCH: "STRETCHING - LET GO TO KEEP IT",
	ID_DRAG_OFFSET: "LIFTING IT OFF - LET GO TO KEEP IT",
	ID_DRAG_COLLAR: "SLIDING IT ROUND - LET GO WHEN IT LOOKS RIGHT",
	ID_PLACE_MIRRORED: "THIS MAKES TWO - ONE ON EACH SIDE. CLICK TO PLACE.",
	ID_PLACE_SNAPPED: "SNAPPED TO {target} - CLICK TO STICK IT ON",
	ID_PLACE_FREE: "GOOD SPOT - CLICK TO STICK IT ON",
	ID_PLACE_EMPTY: "POINT AT YOUR SHIP - PARTS STICK ONTO OTHER PARTS",
	ID_AXIS_LOCK: "LOCKED TO {lock} - PRESS {lock} AGAIN TO FREE IT",
	ID_PROMOTION: "",  # two offers, one per target mode - see PROMOTION_LEDE
	ID_ECHO_UNDO_EMPTY: "NOTHING LEFT TO UNDO - THIS IS WHERE YOU STARTED",
	ID_ECHO_UNDO: "UNDID: {label}",
	ID_ECHO_DELETE: "REMOVED {count} PARTS",
	ID_ECHO_COMMIT: "PUT THE {label} ON. {undo} IF THAT WAS WRONG.",
	ID_ECHO_STATUS: "{status}",
	ID_HOVER_RING: "DRAG THIS RING TO TURN IT - IT CLICKS EVERY {snap} DEGREES",
	ID_HOVER_COLLAR: "DRAG THIS COLLAR TO SLIDE IT ROUND THE PART BELOW",
	ID_HOVER_STRETCH: "DRAG THIS ARROW TO MAKE IT LONGER OR SHORTER",
	ID_HOVER_OFFSET: "DRAG THIS STALK TO LIFT IT OFF THE PART BELOW",
	ID_MODE_CHANGED: "",  # one line per mode - see MODE_LEDE
	ID_EMPTY_DOC: "PICK A SHAPE ON THE LEFT TO START YOUR SHIP",
	ID_EXPLODED: "CLICK A PIECE TO LOOK AT IT - PRESS {explode} TO PUT IT BACK",
	ID_BAKED: "THIS IS THE FINISHED SHIP - PRESS {edit} TO CHANGE IT",
	ID_COMPONENT_OPEN: "INSIDE A COMPONENT - PRESS {cancel} TO COME BACK OUT",
	ID_SEAM_READY: "PRESS {link} TO PUT A DOOR BETWEEN THESE TWO",
	ID_SELECTED_MANY: "{n} PARTS PICKED UP - BIN, COPY AND MIRROR HIT THEM ALL",
	ID_SELECTED_ONE: "{obj} PICKED UP - DRAG THE RING TO TURN IT",
	ID_IDLE: "CLICK A PART TO PICK IT UP - OR PICK A SHAPE TO ADD ONE",
	ID_HOVER_PART: "",
	ID_HOVER_CELL: "",
}

## A ring with the snap off has no click to promise, so it says the other true thing instead.
const HOVER_RING_FREE: String = "DRAG THIS RING TO TURN IT TO ANY ANGLE"

## The promotion offers of ux.md 3.1.2, keyed by the mode being offered.
const PROMOTION_LEDE: Dictionary = {
	MODE_SHAPE: "YOU HAVE THE HANG OF THIS - SHOW THE NUMBERS?",
	MODE_ENGINEER: "DOORS, ROOMS AND SHAPE DIALS LIVE IN ENGINEER - TURN IT ON?",
}

## What each mode says about itself the moment it is entered.
const MODE_LEDE: Dictionary = {
	MODE_BUILD: "BUILD MODE - PICK A SHAPE, PUT IT ON, TURN IT",
	MODE_SHAPE: "SHAPE MODE - NUMBERS ON THE RIGHT, PART LIST ON THE LEFT",
	MODE_ENGINEER: "ENGINEER MODE - EVERY DIAL, DOOR AND ROOM IS HERE",
}

const MODE_NAME: Dictionary = {
	MODE_BUILD: "BUILD",
	MODE_SHAPE: "SHAPE",
	MODE_ENGINEER: "ENGINEER",
}

## Line two: lower case on purpose, so the eye reads one instruction and one aside, not two
## shouts. A gate's own message goes here verbatim (ux.md 3.2.6: "never paraphrased").
const SUB: Dictionary = {
	ID_REFUSED_ROLLBACK: "it is back the way it was",
	ID_REFUSED_PLACE: "there is not enough room for it",
	ID_REFUSED_OFF_SHIP: "bring it back over the ship to keep it",
	ID_REFUSED_DISABLED: "",
	ID_REFUSED_CELL: "take a part off, or break one pair's mirror",
	ID_REFUSED_NO_TOUCH: "a door needs two parts that overlap",
	ID_MODAL_TUTORIAL: "",
	ID_MODAL_LEGEND: "the keys you can use now are lit",
	ID_MODAL_DIALOG: "nothing else can be touched until it is answered",
	ID_BAKING: "it is working, nothing is broken",
	ID_TYPING: "esc forgets it and keeps the drag",
	ID_FLY: "you keep drifting - that is space. {brake} stops you dead",
	ID_DRAG_RING: "or type a number for an exact angle",
	ID_DRAG_STRETCH: "or type a number in metres",
	ID_DRAG_OFFSET: "it stops every {snap_m} m",
	ID_DRAG_COLLAR: "",
	ID_PLACE_MIRRORED: "hold {only_one} to place just one",
	ID_PLACE_SNAPPED: "the dots are where this part likes to sit",
	ID_PLACE_FREE: "slide around to find the place",
	ID_PLACE_EMPTY: "nothing under the pointer yet",
	ID_AXIS_LOCK: "every ring now turns around {lock}",
	ID_PROMOTION: "say no and it will not ask again for a while",
	ID_ECHO_UNDO_EMPTY: "",
	ID_ECHO_UNDO: "{redo} does it again",
	ID_ECHO_DELETE: "{undo} brings them back",
	ID_ECHO_COMMIT: "",
	ID_ECHO_STATUS: "",
	ID_HOVER_RING: "hold {free} for any angle",
	ID_HOVER_COLLAR: "it stays stuck to that surface",
	ID_HOVER_STRETCH: "",
	ID_HOVER_OFFSET: "push down to sink it in",
	ID_MODE_CHANGED: "",
	ID_EMPTY_DOC: "every ship begins with one piece",
	ID_EXPLODED: "",
	ID_BAKED: "or press {explode} to pull it apart",
	ID_COMPONENT_OPEN: "the parts in here belong to it",
	ID_SEAM_READY: "press again for wall, hatch or open",
	ID_SELECTED_MANY: "",
	ID_SELECTED_ONE: "or drag the collar to slide it round",
	ID_IDLE: "drag the background to look around",
	ID_HOVER_PART: "",
	ID_HOVER_CELL: "",
}

## The schema line. Ids and three-decimal values belong HERE and never in the LEDE - the LEDE is
## an instruction a child reads, FACTS is the readout the author reads.
const FACTS: Dictionary = {
	ID_REFUSED_ROLLBACK: "NOTHING CHANGED",
	ID_REFUSED_PLACE: "CANNOT PLACE",
	ID_REFUSED_OFF_SHIP: "MOVING {obj}",
	ID_REFUSED_DISABLED: "",
	ID_REFUSED_CELL: "{cell}",
	ID_REFUSED_NO_TOUCH: "NO SEAM",
	ID_MODAL_TUTORIAL: "",  # filled from the state underneath - the card is the only teacher
	ID_MODAL_LEGEND: "",
	ID_MODAL_DIALOG: "",
	ID_BAKING: "CSG PASS {step} OF {steps}",
	ID_TYPING: "{deg}° → {typed}_",
	ID_FLY: "FLY · {speed} M/S",
	ID_DRAG_RING: "{delta}° ({deg}°)",
	ID_DRAG_STRETCH: "{metres} M",
	ID_DRAG_OFFSET: "LIFT {metres} M",
	ID_DRAG_COLLAR: "ON {host}",
	ID_PLACE_MIRRORED: "MIRROR {plane} · COSTS DOUBLE",
	ID_PLACE_SNAPPED: "SNAP: {target}",
	ID_PLACE_FREE: "FREE SURFACE",
	ID_PLACE_EMPTY: "PLACING {placing}",
	ID_AXIS_LOCK: "LOCK {lock}",
	ID_PROMOTION: "MODE: {mode}",
	ID_ECHO_UNDO_EMPTY: "",
	ID_ECHO_UNDO: "",
	ID_ECHO_DELETE: "{parts_n}",
	ID_ECHO_COMMIT: "{parts_n} · {complexity}",
	ID_ECHO_STATUS: "",
	ID_HOVER_RING: "RING {axis} · {deg}°",
	ID_HOVER_COLLAR: "ON {host}",
	ID_HOVER_STRETCH: "STRETCH {axis} · {metres} M",
	ID_HOVER_OFFSET: "LIFT · {metres} M",
	ID_MODE_CHANGED: "MODE: {mode}",
	ID_EMPTY_DOC: "{parts_n}",
	ID_EXPLODED: "{pieces} MODULES · {seams} SEAMS",
	ID_BAKED: "BAKED · {pieces} PIECES",
	ID_COMPONENT_OPEN: "INSIDE {comp}",
	ID_SEAM_READY: "SEAM: {seam}",
	ID_SELECTED_MANY: "{n} PARTS{differ}",
	ID_SELECTED_ONE: "{obj} · {index} OF {parts}",
	ID_IDLE: "{parts_n}",
	ID_HOVER_PART: "{hovered}",
	ID_HOVER_CELL: "{cell_desc}",
}

## `[KEY] VERB` buttons, as `[chord name, verb]`. A name absent from [constant CHORD_FALLBACK] is
## looked up in the state instead, which is how `[X] FREE` gets the axis that is actually locked.
const CHIPS: Dictionary = {
	ID_REFUSED_ROLLBACK: [["undo", "UNDO"]],
	ID_REFUSED_PLACE: [["cancel", "CANCEL"]],
	ID_REFUSED_OFF_SHIP: [["cancel", "KEEP IT"]],
	ID_REFUSED_DISABLED: [],
	ID_REFUSED_CELL: [],
	ID_REFUSED_NO_TOUCH: [["slide", "SLIDE"]],
	ID_MODAL_TUTORIAL: [],  # filled from the state underneath
	ID_MODAL_LEGEND: [],
	ID_MODAL_DIALOG: [],
	ID_BAKING: [],
	ID_TYPING: [["enter", "SET"], ["cancel", "DROP"]],
	ID_FLY: [["brake", "STOP"], ["land", "LAND"], ["fast", "FAST"]],
	ID_DRAG_RING: [["free", "FREE"], ["cancel", "BACK"]],
	ID_DRAG_STRETCH: [["cancel", "BACK"]],
	ID_DRAG_OFFSET: [["free", "FREE"]],
	ID_DRAG_COLLAR: [["lift", "LIFT"], ["cancel", "BACK"]],
	ID_PLACE_MIRRORED: [["only_one", "ONE ONLY"]],
	ID_PLACE_SNAPPED: [["cancel", "CANCEL"]],
	ID_PLACE_FREE: [["cancel", "CANCEL"]],
	ID_PLACE_EMPTY: [["cancel", "CANCEL"]],
	ID_AXIS_LOCK: [["lock", "FREE"], ["cancel", "FREE"]],
	ID_PROMOTION: [["yes", "YES"], ["no", "NOT YET"]],
	ID_ECHO_UNDO_EMPTY: [["redo", "REDO"]],
	ID_ECHO_UNDO: [["redo", "REDO"]],
	ID_ECHO_DELETE: [["undo", "UNDO"]],
	ID_ECHO_COMMIT: [["undo", "UNDO"]],
	ID_ECHO_STATUS: [],
	ID_HOVER_RING: [["free", "FREE"]],
	ID_HOVER_COLLAR: [["lift", "LIFT"]],
	ID_HOVER_STRETCH: [["type", "EXACT"]],
	ID_HOVER_OFFSET: [["type", "EXACT"]],
	ID_MODE_CHANGED: [["legend", "KEYS"]],
	ID_EMPTY_DOC: [["legend", "KEYS"]],
	ID_EXPLODED: [["explode", "ASSEMBLE"]],
	ID_BAKED: [["edit", "BUILD"], ["explode", "PULL APART"], ["fit", "FIT"]],
	ID_COMPONENT_OPEN: [["cancel", "OUT"]],
	ID_SEAM_READY: [["link", "NEXT KIND"]],
	ID_SELECTED_MANY: [["mirror", "MIRROR"], ["bin", "BIN"]],
	ID_SELECTED_ONE: [["turn", "TURN"], ["bin", "BIN IT"], ["undo", "OOPS"]],
	ID_IDLE: [["look", "LOOK"], ["fit", "FIT"], ["legend", "KEYS"]],
	ID_HOVER_PART: [],
	ID_HOVER_CELL: [["take", "TAKE IT"]],
}

## What a key is called when the caller passes nothing. `ShipKeymap` supplies the live text through
## [constant STATE_CHORDS]; these are only so a sentence is never half-written.
##
## A NAME HERE IS A SLOT IN A SENTENCE, NOT A KEYMAP ACTION, and the two lists are deliberately not
## the same. "cancel" is the key that backs out of whatever is happening - which is a different
## binding while placing, while a field has the digits, and while a component is open - so the
## renderer decides which action fills the slot and this file only asks for "the one that backs
## out". Aligning the names would force a sentence to know its own context, which is the renderer's
## job and not the text's.
const CHORD_FALLBACK: Dictionary = {
	"undo": "CTRL+Z",
	"redo": "CTRL+Y",
	"cancel": "ESC",
	"enter": "ENTER",
	"free": "ALT",
	"lift": "CTRL",
	"fast": "SHIFT",
	"legend": "?",
	"fit": "F",
	"mirror": "M",
	"bin": "DEL",
	"turn": "R",
	"slide": "G",
	"link": "L",
	"explode": "E",
	"edit": "EDIT",
	"only_one": "A",
	"take": "LMB",
	"look": "RMB",
	"type": "TYPE",
	"yes": "Y",
	"no": "N",
	# FLY (ADR 0049). "land" is deliberately NOT "cancel": `diegetic_host.gd` eats ESCAPE to unfocus
	# the device, so a mode whose only advertised exit is ESC would be a trap in the shipping path.
	# V is the guaranteed exit and is the same key that entered.
	"brake": "X",
	"land": "V",
	"roll": "Q/E",
}

## The NEXT button, in the order it asks (ux.md 3.2.1: "the highest-priority blocker"). It reads
## nothing about a gesture, which is how "frozen for the entire duration of any gesture" is kept -
## structurally, rather than by a renderer remembering to hold still.
const NEXT_PICK: String = "PICK A SHAPE"
const NEXT_STALE: String = "BUILD IT *"
const NEXT_EDIT: String = "EDIT IT"
const NEXT_IDLE: String = "BUILD IT"


## A fully populated state with nothing happening: an empty document in BUILD. Callers fill in
## what they know and leave the rest, so adding a key here never breaks an existing caller.
static func default_state() -> Dictionary:
	return {
		STATE_MODE: MODE_BUILD,
		STATE_SEEN: 0,
		STATE_INSIST: false,
		STATE_REMEDY: "",
		STATE_PART_COUNT: 0,
		STATE_SELECTION: 0,
		STATE_INDEX: 0,
		STATE_OBJECT: "",
		STATE_HOST: "",
		STATE_DIFFER: false,
		STATE_TOUCHING: false,
		STATE_SEAM: "",
		STATE_MODAL: "",
		STATE_REFUSAL: "",
		STATE_GATE: "",
		STATE_DRAG: "",
		STATE_HOVER_HANDLE: "",
		STATE_HOVER_PART: "",
		STATE_MAKER: "",
		STATE_HOVER_CELL: "",
		STATE_CELL_DESC: "",
		STATE_CELL_OK: true,
		STATE_PLACING: "",
		STATE_PLACE: "",
		STATE_TARGET: "",
		STATE_MIRROR: "",
		STATE_AXIS: "",
		STATE_LOCK: "",
		STATE_DEGREES: 0.0,
		STATE_DELTA: 0.0,
		STATE_METRES: 0.0,
		STATE_SNAP_DEG: 5.0,
		STATE_SNAP_M: 0.05,
		STATE_TYPED: "",
		STATE_FLYING: false,
		STATE_SPEED: 0.0,
		STATE_BAKING: false,
		STATE_STEP: 0,
		STATE_STEPS: 0,
		STATE_BAKED: false,
		STATE_EXPLODED: false,
		STATE_STALE: false,
		STATE_PIECES: 0,
		STATE_SEAMS: 0,
		STATE_COMPONENT: "",
		STATE_ECHO: "",
		STATE_LABEL: "",
		STATE_COUNT: 0,
		STATE_STATUS: "",
		STATE_PROMOTION: -1,
		STATE_MODE_CHANGED: false,
		STATE_COMPLEXITY: "",
		STATE_BUDGET: "",
		STATE_PIVOT_HELD: false,
		STATE_AIM_NORMAL: true,
		STATE_CHORDS: {},
	}


## The whole of it. Pure: the argument is never mutated, nothing is read from the engine, and the
## same Dictionary in gives the same strings out. Returns the six zones of ux.md 3.2.1 plus the
## winning state's id (what the caller counts exposures against), its rung and its decay level.
static func resolve(state: Dictionary) -> Dictionary:
	var s: Dictionary = default_state()
	s.merge(state, true)
	var id: String = _select(s)
	var under: String = id
	if id == ID_MODAL_TUTORIAL:
		# The card is a teacher of its own. Two teachers talking at once is the thing ux.md 3.2.5
		# forbids, so the LEDE goes blank - but FACTS and the chips stay live underneath it.
		var quiet_state: Dictionary = s.duplicate()
		quiet_state[STATE_MODAL] = ""
		under = _select(quiet_state)
	var vars: Dictionary = _vars(s)
	var rung_of: int = int(RUNG[id])
	var level: int = _level_for(s, rung_of)
	var out: Dictionary = {
		OUT_ID: id,
		OUT_RUNG: rung_of,
		OUT_LEVEL: level,
		OUT_LEDE: _fit(_lede_for(id, s, vars)),
		OUT_SUB: _sub_for(id, s, vars),
		OUT_FACTS: _facts_for(id, under, s, vars),
		OUT_STRIP: _strip_for(s, vars),
		OUT_CHIPS: _chips_for(id, under, s, vars),
		OUT_NEXT: _next_for(s),
		OUT_TONE: _tone_for(s),
	}
	_decay(out, level, vars)
	return out


## Which rung of ux.md 3.2.5's ladder owns the LEDE for this state. Lowest wins.
static func rung(state: Dictionary) -> int:
	return int(resolve(state)[OUT_RUNG])


## [method resolve] with the mode supplied separately, which is how `ShipHintBar` will call it -
## the mode comes from `ShipUiMode` and the rest from the document and the view.
static func compose(state: Dictionary, mode: int) -> Dictionary:
	var s: Dictionary = state.duplicate()
	s[STATE_MODE] = mode
	return resolve(s)


## FULL / SHORT / QUIET from an exposure count (ux.md 3.2.3: 0-3 full, 4-8 short, 9+ chips only).
static func verbosity(seen: int) -> int:
	var level: int = FULL
	if seen >= 9:
		level = QUIET
	elif seen >= 4:
		level = SHORT
	return level


## What a mode seeds a fresh exposure counter to. Three verbosity levels for one integer, which
## is the whole reason the wording is not maintained three times over.
static func seed_for(mode: int) -> int:
	var index: int = clampi(mode, 0, SEEN_SEED.size() - 1)
	return int(SEEN_SEED[index])


# --- the ladder -------------------------------------------------------------------------------
# One function per rung, each returning "" when nothing on it is true. Order INSIDE a rung is as
# load-bearing as the rung numbers and is pinned by the suite.


static func _select(s: Dictionary) -> String:
	var id: String = _rung0(s)
	if id == "":
		id = _rung1(s)
	if id == "":
		id = _rung2(s)
	if id == "":
		id = _rung3(s)
	if id == "":
		id = _rung4(s)
	if id == "":
		id = _rung5(s)
	return id


## Rung 0, REFUSED. A refusal outranks everything, including a modal: the player just did a thing
## and nothing happened, and that is the only moment where silence is a bug.
static func _rung0(s: Dictionary) -> String:
	var id: String = ""
	if str(s[STATE_REFUSAL]) == REFUSAL_ROLLBACK:
		id = ID_REFUSED_ROLLBACK
	elif str(s[STATE_PLACE]) == PLACE_REFUSED:
		id = ID_REFUSED_PLACE
	elif str(s[STATE_REFUSAL]) == REFUSAL_OFF_SHIP:
		id = ID_REFUSED_OFF_SHIP
	elif str(s[STATE_REFUSAL]) == REFUSAL_DISABLED:
		id = ID_REFUSED_DISABLED
	elif str(s[STATE_HOVER_CELL]) != "" and not bool(s[STATE_CELL_OK]):
		id = ID_REFUSED_CELL
	elif _two_apart(s):
		id = ID_REFUSED_NO_TOUCH
	return id


## Two parts selected that do not meet. ux.md 3.2.6 files it under rung 0, but unlike the other
## five it is a STANDING condition rather than a thing that just happened - so it waits for the
## hands to be free. Without the guard it would sit on top of the very drag that fixes it.
static func _two_apart(s: Dictionary) -> bool:
	if int(s[STATE_SELECTION]) != 2 or bool(s[STATE_TOUCHING]):
		return false
	return str(s[STATE_DRAG]) == "" and str(s[STATE_PLACE]) == ""


static func _rung1(s: Dictionary) -> String:
	var modal: String = str(s[STATE_MODAL])
	var id: String = ""
	if modal == MODAL_TUTORIAL:
		id = ID_MODAL_TUTORIAL
	elif modal == MODAL_LEGEND:
		id = ID_MODAL_LEGEND
	elif modal == MODAL_DIALOG:
		id = ID_MODAL_DIALOG
	return id


## Rung 2, GESTURE. A bake takes the view away entirely, so it heads the rung; the axis lock ends
## it, because it is a flag that is true BETWEEN gestures and the mode strip carries it anyway.
static func _rung2(s: Dictionary) -> String:
	var drag: String = str(s[STATE_DRAG])
	var id: String = ""
	if bool(s[STATE_BAKING]):
		id = ID_BAKING
	elif str(s[STATE_TYPED]) != "":
		id = ID_TYPING
	elif bool(s[STATE_FLYING]):
		id = ID_FLY
	elif drag == DRAG_RING:
		id = ID_DRAG_RING
	elif drag == DRAG_STRETCH:
		id = ID_DRAG_STRETCH
	elif drag == DRAG_OFFSET:
		id = ID_DRAG_OFFSET
	elif drag == DRAG_COLLAR or drag == DRAG_MOVE:
		id = ID_DRAG_COLLAR
	else:
		id = _placing(s)
	if id == "" and str(s[STATE_LOCK]) != "":
		id = ID_AXIS_LOCK
	return id


## A legal ghost with symmetry on says "this makes two" before it says where it landed: the
## surprise is the twin, not the surface, and FACTS still names the target underneath.
static func _placing(s: Dictionary) -> String:
	var place: String = str(s[STATE_PLACE])
	var legal: bool = place == PLACE_FREE or place == PLACE_SNAPPED
	var id: String = ""
	if legal and str(s[STATE_MIRROR]) != "":
		id = ID_PLACE_MIRRORED
	elif place == PLACE_SNAPPED:
		id = ID_PLACE_SNAPPED
	elif place == PLACE_FREE:
		id = ID_PLACE_FREE
	elif place == PLACE_EMPTY:
		id = ID_PLACE_EMPTY
	return id


## Rung 3, TRANSIENT. The promotion offer heads it because it is the only rung-3 state with a
## question in it: an echo that loses two seconds costs nothing, an unanswered offer costs the
## eight it was given.
static func _rung3(s: Dictionary) -> String:
	var echo: String = str(s[STATE_ECHO])
	var id: String = ""
	if int(s[STATE_PROMOTION]) >= 0:
		id = ID_PROMOTION
	elif echo == ECHO_UNDO_EMPTY:
		id = ID_ECHO_UNDO_EMPTY
	elif echo == ECHO_UNDO:
		id = ID_ECHO_UNDO
	elif echo == ECHO_DELETE:
		id = ID_ECHO_DELETE
	elif echo == ECHO_COMMIT:
		id = ID_ECHO_COMMIT
	elif echo == ECHO_STATUS and str(s[STATE_STATUS]) != "":
		id = ID_ECHO_STATUS
	return id


## Rung 4, HANDLE HOVER - the one arbitration ux.md 3.2.5 says the design turns on. A ring, an
## arrow, a stalk and a collar look alike and none of them is guessable, so a hovered HANDLE
## outranks the selection. A hovered PART is self-evident and is demoted to FACTS.
static func _rung4(s: Dictionary) -> String:
	var handle: String = str(s[STATE_HOVER_HANDLE])
	var id: String = ""
	if handle == HANDLE_RING:
		id = ID_HOVER_RING
	elif handle == HANDLE_COLLAR:
		id = ID_HOVER_COLLAR
	elif handle == HANDLE_STRETCH:
		id = ID_HOVER_STRETCH
	elif handle == HANDLE_OFFSET:
		id = ID_HOVER_OFFSET
	return id


## Rung 5, SELECTION / IDLE - never empty, which is what keeps the bar from ever going silent.
static func _rung5(s: Dictionary) -> String:
	var picked: int = int(s[STATE_SELECTION])
	var id: String = ID_IDLE
	if bool(s[STATE_MODE_CHANGED]):
		id = ID_MODE_CHANGED
	elif int(s[STATE_PART_COUNT]) <= 0:
		id = ID_EMPTY_DOC
	elif bool(s[STATE_EXPLODED]):
		id = ID_EXPLODED
	elif bool(s[STATE_BAKED]):
		id = ID_BAKED
	elif str(s[STATE_COMPONENT]) != "":
		id = ID_COMPONENT_OPEN
	elif picked == 2 and bool(s[STATE_TOUCHING]):
		id = ID_SEAM_READY
	elif picked > 1:
		id = ID_SELECTED_MANY
	elif picked == 1:
		id = ID_SELECTED_ONE
	return id


# --- the words, filled in ----------------------------------------------------------------------


static func _lede_for(id: String, s: Dictionary, vars: Dictionary) -> String:
	var template: String = str(LEDE[id])
	if id == ID_PROMOTION:
		template = str(PROMOTION_LEDE.get(int(s[STATE_PROMOTION]), ""))
	elif id == ID_MODE_CHANGED:
		template = str(MODE_LEDE.get(int(s[STATE_MODE]), ""))
	elif id == ID_HOVER_RING and float(s[STATE_SNAP_DEG]) <= 0.0:
		template = HOVER_RING_FREE
	return template.format(vars)


## A gate's refusal is printed verbatim and is NOT capped, because it names a quantity and its cap
## and ux.md 3.2.6 is explicit that wrapping or trimming it buys nothing. That is also why no
## refusal puts it in the LEDE: the child-facing sentence goes on line one and fits, the gate's own
## sentence goes on line two and runs as long as it needs to. Every rung-0 state follows the rule,
## which is why a gate message is one state field rather than six templates; the literal below is
## the fallback for a refusal that arrives without one.
static func _sub_for(id: String, s: Dictionary, vars: Dictionary) -> String:
	var gate: String = str(s[STATE_GATE])
	if int(RUNG[id]) == 0 and gate != "":
		return gate
	return str(SUB[id]).format(vars)


## FACTS is a channel, not a rung: a hovered part overwrites it without touching the instruction.
## Not while a refusal, a modal or a live gesture owns the bar, though - there the readout is the
## thing being refused or driven, and swapping it for whatever the pointer grazed would be a lie.
static func _facts_for(id: String, under: String, s: Dictionary, vars: Dictionary) -> String:
	var key: String = under if id == ID_MODAL_TUTORIAL else id
	var text: String = str(FACTS[key]).format(vars)
	if int(RUNG[id]) < 3:
		return text
	if str(s[STATE_HOVER_PART]) != "":
		text = str(FACTS[ID_HOVER_PART]).format(vars)
	elif str(s[STATE_HOVER_CELL]) != "" and str(s[STATE_CELL_DESC]) != "":
		text = str(FACTS[ID_HOVER_CELL]).format(vars)
	return text


## The mode strip (ux.md 3.2.4): fixed format, always present, rewritten only by the state it
## names. It exists because deleting the ten-line legend also deletes the only display of two
## STATEFUL toggles - `P` forks a ring drag into a different geometric verb, and a hold-to-reveal
## card cannot show you a flag you must read with your hand on the mouse. BUILD binds neither
## toggle nor the axis lock, so it carries the two fields that are true there.
static func _strip_for(s: Dictionary, vars: Dictionary) -> String:
	var mode: int = int(s[STATE_MODE])
	var fields: PackedStringArray = PackedStringArray()
	if mode != MODE_BUILD:
		fields.append("PIVOT STUCK" if bool(s[STATE_PIVOT_HELD]) else "PIVOT FLOAT")
		fields.append("AIM NORM" if bool(s[STATE_AIM_NORMAL]) else "AIM PLACE")
	var snap: float = float(s[STATE_SNAP_DEG])
	fields.append("SNAP OFF" if snap <= 0.0 else "SNAP %s°" % str(vars["snap"]))
	var plane: String = str(s[STATE_MIRROR])
	fields.append("MIRROR OFF" if plane == "" else "MIRROR %s" % plane)
	if mode != MODE_BUILD:
		var lock: String = str(s[STATE_LOCK])
		fields.append("LOCK %s" % ("-" if lock == "" else lock))
	return " · ".join(fields)


## Chips come from the winning state, except that a shelf cell owns the chip row the way a hovered
## part owns FACTS - it is the one hover with a verb of its own. Capped by mode, never by state.
static func _chips_for(id: String, under: String, s: Dictionary, vars: Dictionary) -> Array:
	var key: String = under if id == ID_MODAL_TUTORIAL else id
	if int(RUNG[id]) >= 3 and str(s[STATE_HOVER_CELL]) != "" and bool(s[STATE_CELL_OK]):
		key = ID_HOVER_CELL
	var cap: int = int(CHIP_CAP[clampi(int(s[STATE_MODE]), 0, CHIP_CAP.size() - 1)])
	var chords: Dictionary = s[STATE_CHORDS] as Dictionary
	var out: Array = []
	for pair: Array in CHIPS[key] as Array:
		if out.size() >= cap:
			break
		out.append({CHIP_KEY: _chip_key(str(pair[0]), chords, vars), CHIP_VERB: str(pair[1])})
	return out


static func _chip_key(name: String, chords: Dictionary, vars: Dictionary) -> String:
	var text: String = ""
	if chords.has(name):
		text = str(chords[name])
	elif CHORD_FALLBACK.has(name):
		text = str(CHORD_FALLBACK[name])
	elif vars.has(name):
		text = str(vars[name])
	return text


## NEXT reads the document and the budget and nothing else - no drag, no hover, no rung. That is
## ux.md 3.2.1's "frozen for the entire duration of any gesture" made structural: peripheral motion
## beside the cursor during a drag is the loudest possible intrusion, and the cheapest way to never
## make it is to give the button nothing that changes while a gesture is live.
static func _next_for(s: Dictionary) -> String:
	var label: String = NEXT_IDLE
	if str(s[STATE_BUDGET]) != "":
		label = str(s[STATE_BUDGET])
	elif int(s[STATE_PART_COUNT]) <= 0:
		label = NEXT_PICK
	elif bool(s[STATE_STALE]):
		label = NEXT_STALE
	elif bool(s[STATE_BAKED]):
		label = NEXT_EDIT
	return _fit(label)


static func _tone_for(s: Dictionary) -> String:
	var tone: String = TONE_DIM
	if str(s[STATE_BUDGET]) != "":
		tone = TONE_WARNING
	elif bool(s[STATE_STALE]) or bool(s[STATE_BAKED]):
		tone = TONE_ACCENT
	return tone


# --- decay ------------------------------------------------------------------------------------


## Rungs 0 and 1 never decay. A refusal that has gone quiet is a refusal the player cannot act on,
## and the hundredth one is no less confusing than the first; a modal's line is the only thing
## telling them what has taken the screen. Everything else recedes on its exposure count.
static func _level_for(s: Dictionary, rung_of: int) -> int:
	if rung_of <= 1 or bool(s[STATE_INSIST]):
		return FULL
	return verbosity(int(s[STATE_SEEN]))


## The inverse ramp of ux.md 3.2.3 rides in on [constant STATE_INSIST]: three refusals of the same
## kind, or a minute with nothing committed after a failed attempt, and the caller raises the level
## back to FULL and hands over the specific remedy. "Guidance that only ever recedes abandons
## exactly the person it was written for."
static func _decay(out: Dictionary, level: int, vars: Dictionary) -> void:
	if level >= SHORT:
		out[OUT_SUB] = ""
	if level >= QUIET:
		var name: String = str(vars["obj"])
		if name == "":
			name = str(out[OUT_FACTS])
		out[OUT_LEDE] = _fit(name)
	if level > FULL or str(vars["remedy"]) == "":
		return
	var sub: String = str(out[OUT_SUB])
	out[OUT_SUB] = str(vars["remedy"]) if sub == "" else "%s - %s" % [sub, str(vars["remedy"])]


# --- values -----------------------------------------------------------------------------------


## Everything a template can name, formatted once. Chords first, so `{undo}` resolves like any
## other value and no sentence has to know a key's name.
static func _vars(s: Dictionary) -> Dictionary:
	var chords: Dictionary = s[STATE_CHORDS] as Dictionary
	var vars: Dictionary = {}
	for name: String in CHORD_FALLBACK:
		vars[name] = str(chords[name]) if chords.has(name) else str(CHORD_FALLBACK[name])
	vars.merge(_counts(s), true)
	vars.merge(_numbers(s), true)
	vars.merge(_names(s), true)
	return vars


static func _counts(s: Dictionary) -> Dictionary:
	var parts: int = int(s[STATE_PART_COUNT])
	var picked: int = int(s[STATE_SELECTION])
	return {
		"parts": str(parts),
		"parts_n": "1 PART" if parts == 1 else "%d PARTS" % parts,
		"n": str(picked),
		"index": str(int(s[STATE_INDEX])),
		"differ": " · VALUES DIFFER" if bool(s[STATE_DIFFER]) else "",
		"count": str(int(s[STATE_COUNT])),
		"pieces": str(int(s[STATE_PIECES])),
		"seams": str(int(s[STATE_SEAMS])),
		"step": str(int(s[STATE_STEP])),
		"steps": str(int(s[STATE_STEPS])),
	}


## Three decimals everywhere a length or an angle is shown, matching `NumericField`'s formatter, so
## what the bar prints and what a typed field prints are the same number. The snap values are
## trimmed instead: "IT CLICKS EVERY 5.000 DEGREES" reads like a machine.
static func _numbers(s: Dictionary) -> Dictionary:
	return {
		"deg": "%.3f" % float(s[STATE_DEGREES]),
		"delta": "%+.3f" % float(s[STATE_DELTA]),
		"metres": "%.3f" % float(s[STATE_METRES]),
		"speed": "%.1f" % float(s[STATE_SPEED]),
		"snap": _trim(float(s[STATE_SNAP_DEG])),
		"snap_m": _trim(float(s[STATE_SNAP_M])),
	}


static func _names(s: Dictionary) -> Dictionary:
	var maker: String = str(s[STATE_MAKER])
	var hovered: String = str(s[STATE_HOVER_PART])
	if hovered != "" and maker != "":
		hovered = "%s · %s" % [hovered, maker]
	return {
		"obj": str(s[STATE_OBJECT]),
		"host": str(s[STATE_HOST]),
		"maker": maker,
		"hovered": hovered,
		"cell": str(s[STATE_HOVER_CELL]),
		"cell_desc": str(s[STATE_CELL_DESC]),
		"placing": str(s[STATE_PLACING]),
		"target": str(s[STATE_TARGET]),
		"plane": str(s[STATE_MIRROR]),
		"axis": str(s[STATE_AXIS]),
		"lock": str(s[STATE_LOCK]),
		"typed": str(s[STATE_TYPED]),
		"seam": str(s[STATE_SEAM]),
		"comp": str(s[STATE_COMPONENT]),
		"label": str(s[STATE_LABEL]),
		"status": str(s[STATE_STATUS]),
		"complexity": str(s[STATE_COMPLEXITY]),
		"mode": str(MODE_NAME.get(int(s[STATE_MODE]), "")),
		"remedy": str(s[STATE_REMEDY]),
	}


## Clamp rather than trust. A caller can hand over a part name or a `set_status()` line of any
## length; the LEDE zone cannot grow, so overflow is cut here and the suite asserts that no
## literal in this file needs the cut in the first place.
static func _fit(text: String) -> String:
	return text.left(LEDE_MAX)


static func _trim(value: float) -> String:
	var text: String = String.num(value, 3)
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return text

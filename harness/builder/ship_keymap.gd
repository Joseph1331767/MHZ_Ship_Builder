class_name ShipKeymap
extends RefCounted
## Every binding the builder answers to, written down once.
##
## WHY A TABLE AND NOT FOUR HAND-KEPT LISTS. The ten-line legend in `ship_view3d.gd` is typed out
## by hand next to the code that dispatches nothing it names. It currently advertises `WHEEL ZOOM`
## while the plain wheel scales the selected part, it names `ESC` as the way out of an open
## component when `ESC` only clears the selection, and thirteen live verbs appear on it nowhere at
## all. A legend maintained by hand drifts from the dispatcher within weeks and nothing fails when
## it does. `tests/harness/test_keymap.gd` is the thing that fails.
##
## NOTHING READS THIS FOR DISPATCH YET, deliberately (docs/future/ux.md section 5.1 step 5). The
## table is authored first, alone, so that the hint bar's chips, the hold-`?` card and the mode
## strip all draw from one source when they land - and so that rewiring `_dispatch_press` to read
## it later is a change to one file rather than an archaeology exercise. The test runs
## one-directionally: it checks that this table is well formed and internally consistent, never
## that the live code agrees with it, because the live code is still the only authority.
##
## THE `context` COLUMN EXISTS FROM THE FIRST ROW. `ESC` means five different things in this
## application (drop the ghost, drop the selection, free the axis lock, close a dialog, abandon a
## typed number). Without a context a card built from this table prints five contradictory `ESC`
## rows and is worse than no card. Contexts are exact, not nested: a consumer showing the exploded
## view unions [constant CONTEXT_ALWAYS] with [constant CONTEXT_EXPLODED] itself.
##
## A ROW THAT IS NOT LIVE STAYS IN THE TABLE. [constant STATUS_DEAD], [constant STATUS_LIES] and
## [constant STATUS_UNBOUND] rows carry a `note` saying what is actually true. They are excluded
## from [method for_context] and [method for_tier] - nothing renders them - but [method all]
## returns them, which is what makes this file an audit as well as a legend. Deleting a row
## because the binding is broken is how the broken binding gets forgotten.
##
## Angles, distances and the rest of the API boundary rules do not apply here: this class holds
## strings and key codes and computes nothing.

## Field keys of a row. Named constants rather than bare strings so a rename is one edit and the
## test cannot drift from the table by a typo.
const FIELD_ACTION: String = "action"
const FIELD_CHORD: String = "chord"
const FIELD_ALTS: String = "alts"
const FIELD_CODE: String = "code"
const FIELD_MODS: String = "mods"
const FIELD_LABEL: String = "label"
const FIELD_CONTEXT: String = "context"
const FIELD_TIER: String = "tier"
const FIELD_GROUP: String = "group"
const FIELD_HANDLER: String = "handler"
const FIELD_STATUS: String = "status"
const FIELD_NOTE: String = "note"

## Modifier bits. Our own, not Godot's `KeyModifierMask`, because a row records the modifiers a
## binding REQUIRES and Godot's mask is what an event happens to carry.
const MOD_NONE: int = 0
const MOD_SHIFT: int = 1
const MOD_CTRL: int = 2
const MOD_ALT: int = 4

## What a consumer may render. LIVE and LIES both reach the screen - a LIES row works, it is
## some other surface that describes it wrongly, and the `label` here is the corrected wording.
const STATUS_LIVE: String = "LIVE"
const STATUS_LIES: String = "LIES"
## The key is dispatched by something else first, so the verb never runs.
const STATUS_DEAD: String = "DEAD"
## The verb exists and works; no key reaches it.
const STATUS_UNBOUND: String = "UNBOUND"

## What an UNBOUND row puts in its `chord`. Not an empty string: an empty chord is the shape of a
## row someone forgot to finish, and the test refuses those.
const UNBOUND_CHORD: String = "(none)"

## The ladder, docs/future/ux.md section 3.1. BUILD is the complete beginner's tool, SHAPE adds
## the numbers and the part list, ENGINEER is everything. A row's tier is the LOWEST rung it
## appears on, so ENGINEER renders the whole table.
const TIER_BUILD: String = "BUILD"
const TIER_SHAPE: String = "SHAPE"
const TIER_ENGINEER: String = "ENGINEER"

## Card headings, docs/future/ux.md section 3.6. Plain words, four of them, no jargon.
const GROUP_LOOK: String = "LOOK AROUND"
const GROUP_PLACE: String = "PICK AND PLACE"
const GROUP_CHANGE: String = "CHANGE A PART"
const GROUP_FILE: String = "FILE"

## The state a binding needs. Exact match, never nested - see the class docs.
const CONTEXT_ALWAYS: String = "ALWAYS"
## The 3D view has focus and the ship is assembled.
const CONTEXT_VIEW: String = "VIEW"
## At least one part is picked.
const CONTEXT_SELECTED: String = "SELECTED"
## Two or more parts are picked.
const CONTEXT_MULTI: String = "MULTI"
## A ghost is up - a new part, or a committed one being moved.
const CONTEXT_PLACING: String = "PLACING"
## An axis lock is engaged.
const CONTEXT_LOCKED: String = "LOCKED"
## A component is open and the rest of the ship is washed out.
const CONTEXT_ISOLATED: String = "ISOLATED"
## The exploded or the baked view is up.
const CONTEXT_EXPLODED: String = "EXPLODED"
## The save dialog is open.
const CONTEXT_DIALOG: String = "DIALOG"
## The seam right-click menu is open.
const CONTEXT_MENU: String = "MENU"
## A NumericField is being scrubbed or typed into.
const CONTEXT_FIELD: String = "FIELD"
## Paint mode is armed. Nothing in the harness arms it - see [constant NOTE_PAINT].
const CONTEXT_PAINT: String = "PAINT"

## Longest a `label` may be, in characters.
##
## The hold-`?` card is two columns inside a 748 px viewport at `ShipTheme.FONT_SIZE_SMALL` (11
## design px), which leaves roughly 300 px a column once the chord glyph and the gutter are paid
## for. At 11 px that is about 48 characters of this font, so 48 is the budget and it is checked.
## It is deliberately tighter than the hint bar's 62-character LEDE cap: a LEDE is one sentence
## with the whole width to itself, a label is one of forty in a grid.
const LABEL_MAX: int = 48

## B1, docs/future/ux.md section 2.5. `ShipView3D._dispatch_press` reaches `_handle_axis_key`
## with a bare keycode and no modifier test, and `_gui_input` then calls `accept_event()`, so with
## the 3D view focused - which it grabs on every left click - Ctrl+Z sets the Z axis lock and
## Ctrl+Y sets the Y one. The undo never runs and nothing on screen says so.
const NOTE_UNDO_SWALLOWED: String = (
	"Dead while the 3D view has focus: _handle_axis_key takes the bare keycode, so this sets an "
	+ "axis lock instead (ux.md B1)."
)

## The other half of B1, recorded on the lock rows as well as on the undo rows: whoever fixes one
## has to look at the other, and a table that only blames Ctrl+Z hides where the key actually goes.
const NOTE_LOCK_EATS_CTRL: String = "Also fires with CTRL held - that is what kills undo and redo."

## B3, docs/future/ux.md section 2.3(a). `_snap_degrees()` reads `doc.settings["snap_deg"]` first
## and that key is written exactly once, at document creation; the inspector's snap picker writes
## `_placement.snap_deg`, which is only reached when the document has no key at all. So the numpad
## and the arrows keep stepping the document's original increment whatever the picker says, and
## the comment at `ship_view3d.gd:128-129` claiming they share the typed fields' lattice is wrong.
const NOTE_TWO_LATTICES: String = "Steps the document's own snap, not the picker's - two lattices."

## B7, docs/future/ux.md section 2.5. The plain wheel scales whenever there is something to scale
## and only dollies as a fallback, while the legend at `ship_view3d.gd:1298` prints `WHEEL ZOOM`.
## Select a part, scroll to look closer, and the hull inflates a notch instead.
const NOTE_WHEEL_LIES: String = (
	"The legend prints WHEEL ZOOM; the plain wheel scales the picked part and only zooms when "
	+ "there is nothing to scale (ux.md B7)."
)

## B8, docs/future/ux.md section 2.5. `ShipPlacement.set_snap_bypass()` compiles, works, and is
## promised by SPEC section 6 and by `data/tuning.json`. Shift was reassigned to the horizontal
## drag mode on 2026-08-31 and no key replaced it, so the only references left in the repo are the
## definition and three comments.
const NOTE_SNAP_BYPASS: String = (
	"No key reaches it - Shift became the horizontal drag modifier and nothing took its place "
	+ "(ux.md B8)."
)

## `ShipBuilder._handle_edit_hotkey` sends ESC to `cancel_placement()` only while a ghost is up,
## and `_leave_isolation()` is reached from there and from a double click - nowhere else. With a
## component open and no ghost, ESC clears the selection and the component stays open, while
## `_isolate()` sets the status line to "ESC TO CLOSE" and the legend repeats it.
const NOTE_ISOLATE_ESC: String = (
	"Promised by the status line and the legend, but ESC only clears the selection here; the way "
	+ "out is a double click on empty space."
)

## `PaintMode.handle_key` has no caller anywhere in the repo, and `_pick_shift` / `_pick_ctrl` /
## `_pick_alt` are written on every click in `ShipView3D` and read by nothing. Keys 1-5 are free.
## Recorded rather than dropped so the next agent knows they are free and why.
const NOTE_PAINT: String = "PaintMode.handle_key has no caller anywhere in the repo; 1-5 are free."

## `_handle_camera_key` is called from the exploded view's dispatch as well as the assembled one,
## so these four keep working there even though their row's context is the assembled view.
const NOTE_CAMERA_EVERYWHERE: String = "Stays live in the exploded and baked views too."

## Every binding, in card order: look, place, change, file.
##
## `code` and `mods` are what a dispatcher would match on and are [constant MOD_NONE] / `KEY_NONE`
## where the chord is a mouse gesture or a bare held modifier. `chord` is the readable form and is
## the only field a legend prints; `alts` are the other keys the same handler already answers to,
## so `=` and `NUMPAD +` do not each earn a line on the card.
const ROWS: Array[Dictionary] = [
	# ------------------------------------------------------------------ look around
	{
		FIELD_ACTION: "orbit_drag",
		FIELD_CHORD: "RMB DRAG",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Spin the view around your ship",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/orbit_camera.gd:_handle_button",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "zoom_wheel",
		FIELD_CHORD: "SHIFT+WHEEL",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_SHIFT,
		FIELD_LABEL: "Move the camera in and out",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/orbit_camera.gd:_handle_button",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "zoom_in",
		FIELD_CHORD: "=",
		FIELD_ALTS: ["+", "NUMPAD +"],
		FIELD_CODE: KEY_EQUAL,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Move the camera closer",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_camera_key",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: NOTE_CAMERA_EVERYWHERE,
	},
	{
		FIELD_ACTION: "zoom_out",
		FIELD_CHORD: "-",
		FIELD_ALTS: ["NUMPAD -"],
		FIELD_CODE: KEY_MINUS,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Move the camera further away",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_camera_key",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: NOTE_CAMERA_EVERYWHERE,
	},
	{
		FIELD_ACTION: "orbit_left",
		FIELD_CHORD: ",",
		FIELD_ALTS: ["<"],
		FIELD_CODE: KEY_COMMA,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Spin the view left a step",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_camera_key",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: NOTE_CAMERA_EVERYWHERE,
	},
	{
		FIELD_ACTION: "orbit_right",
		FIELD_CHORD: ".",
		FIELD_ALTS: [">"],
		FIELD_CODE: KEY_PERIOD,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Spin the view right a step",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_camera_key",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: NOTE_CAMERA_EVERYWHERE,
	},
	{
		FIELD_ACTION: "orbit_here",
		FIELD_CHORD: "CTRL+LMB",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_CTRL,
		FIELD_LABEL: "Spin around the part you clicked",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_left_button",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "frame_all",
		FIELD_CHORD: "F",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_F,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Show me my whole ship",
		FIELD_CONTEXT: CONTEXT_ALWAYS,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/ship_builder.gd:_handle_view_hotkey",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "explode_toggle",
		FIELD_CHORD: "E",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_E,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Pull the ship apart, or put it back",
		FIELD_CONTEXT: CONTEXT_ALWAYS,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/ship_builder.gd:_handle_view_hotkey",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	# ------------------------------------------------------------------ pick and place
	{
		FIELD_ACTION: "pick",
		FIELD_CHORD: "LMB",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Pick up the part you click",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_left_button",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "Picks on the release, so a drag that orbits never changes what is picked.",
	},
	{
		FIELD_ACTION: "pick_add",
		FIELD_CHORD: "SHIFT+LMB",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_SHIFT,
		FIELD_LABEL: "Add that part to the ones you picked",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_left_button",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "isolate",
		FIELD_CHORD: "LMB DOUBLE",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Open the component you double-clicked",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_builder.gd:_on_part_double_clicked",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "clone_drag",
		FIELD_CHORD: "ALT+LMB DRAG",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_ALT,
		FIELD_LABEL: "Peel a copy off the part you grab",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_left_button",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "Resolves on the press, with no hit test - an ALT click anywhere clones.",
	},
	{
		FIELD_ACTION: "move_selected",
		FIELD_CHORD: "G",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_G,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Pick the part up and move it",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_builder.gd:_handle_edit_hotkey",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "Named in no legend, no tooltip and no tutorial step (ux.md section 3.7).",
	},
	{
		FIELD_ACTION: "deselect",
		FIELD_CHORD: "ESC",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_ESCAPE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Let go of what you picked",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_builder.gd:_handle_edit_hotkey",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "place_commit",
		FIELD_CHORD: "LMB",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Stick the part on where it is",
		FIELD_CONTEXT: CONTEXT_PLACING,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_placement_input",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "place_cancel",
		FIELD_CHORD: "ESC",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_ESCAPE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Put the part back and stop",
		FIELD_CONTEXT: CONTEXT_PLACING,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_builder.gd:_handle_edit_hotkey",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "place_drop_off",
		FIELD_CHORD: "LMB DRAG OFF",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Drag it off the ship to bin it",
		FIELD_CONTEXT: CONTEXT_PLACING,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_finish_placement",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "Only off a plain surface drag - a gizmo release may never remove the part.",
	},
	{
		FIELD_ACTION: "drag_vertical",
		FIELD_CHORD: "CTRL (HELD)",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_CTRL,
		FIELD_LABEL: "Slide the part off the surface",
		FIELD_CONTEXT: CONTEXT_PLACING,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_drag_mode_for",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "Wins over SHIFT when both are held.",
	},
	{
		FIELD_ACTION: "drag_horizontal",
		FIELD_CHORD: "SHIFT (HELD)",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_SHIFT,
		FIELD_LABEL: "Keep the part on the part it is on",
		FIELD_CONTEXT: CONTEXT_PLACING,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_drag_mode_for",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "With nothing picked it drags the whole ship instead.",
	},
	{
		FIELD_ACTION: "break_symmetry",
		FIELD_CHORD: "A (HELD)",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_A,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Place just one, not a mirrored pair",
		FIELD_CONTEXT: CONTEXT_PLACING,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_key",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "A hold, not a toggle; a focus change releases it.",
	},
	{
		FIELD_ACTION: "seam_menu",
		FIELD_CHORD: "RMB CLICK",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Choose what goes between two parts",
		FIELD_CONTEXT: CONTEXT_MULTI,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_track_right_button",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "A click, not a drag: a right drag that orbited asks for nothing.",
	},
	# ------------------------------------------------------------------ change a part
	{
		FIELD_ACTION: "undo",
		FIELD_CHORD: "CTRL+Z",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_Z,
		FIELD_MODS: MOD_CTRL,
		FIELD_LABEL: "Put the last thing back as it was",
		FIELD_CONTEXT: CONTEXT_ALWAYS,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_builder.gd:_handle_edit_hotkey",
		FIELD_STATUS: STATUS_DEAD,
		FIELD_NOTE: NOTE_UNDO_SWALLOWED,
	},
	{
		FIELD_ACTION: "redo",
		FIELD_CHORD: "CTRL+Y",
		FIELD_ALTS: ["CTRL+SHIFT+Z"],
		FIELD_CODE: KEY_Y,
		FIELD_MODS: MOD_CTRL,
		FIELD_LABEL: "Do that last thing over again",
		FIELD_CONTEXT: CONTEXT_ALWAYS,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_builder.gd:_handle_edit_hotkey",
		FIELD_STATUS: STATUS_DEAD,
		FIELD_NOTE: NOTE_UNDO_SWALLOWED,
	},
	{
		FIELD_ACTION: "delete",
		FIELD_CHORD: "DELETE",
		FIELD_ALTS: ["BACKSPACE"],
		FIELD_CODE: KEY_DELETE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Put the picked parts in the bin",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_builder.gd:_handle_edit_hotkey",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "handle_drag",
		FIELD_CHORD: "LMB DRAG",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Drag a handle to turn, stretch or slide",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_try_begin_handle_drag",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "Eleven handles are drawn at once and none of them light up on approach.",
	},
	{
		FIELD_ACTION: "scale_wheel",
		FIELD_CHORD: "WHEEL",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Make the picked part bigger or smaller",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_wheel",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_WHEEL_LIES,
	},
	{
		FIELD_ACTION: "scale_up",
		FIELD_CHORD: "PAGE UP",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_PAGEUP,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Make the picked part bigger",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_press_key",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "scale_down",
		FIELD_CHORD: "PAGE DOWN",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_PAGEDOWN,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Make the picked part smaller",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_press_key",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "turn_x_back",
		FIELD_CHORD: "NUMPAD 7",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_KP_7,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Turn the part back about X",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_TWO_LATTICES,
	},
	{
		FIELD_ACTION: "turn_x_zero",
		FIELD_CHORD: "NUMPAD 8",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_KP_8,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Put its X turn back to zero",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "The zeroing keys write the absolute form, so no lattice is involved.",
	},
	{
		FIELD_ACTION: "turn_x_forward",
		FIELD_CHORD: "NUMPAD 9",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_KP_9,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Turn the part forward about X",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_TWO_LATTICES,
	},
	{
		FIELD_ACTION: "turn_y_back",
		FIELD_CHORD: "NUMPAD 4",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_KP_4,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Turn the part back about Y",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_TWO_LATTICES,
	},
	{
		FIELD_ACTION: "turn_y_zero",
		FIELD_CHORD: "NUMPAD 5",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_KP_5,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Put its Y turn back to zero",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "turn_y_forward",
		FIELD_CHORD: "NUMPAD 6",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_KP_6,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Turn the part forward about Y",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_TWO_LATTICES,
	},
	{
		FIELD_ACTION: "turn_z_back",
		FIELD_CHORD: "NUMPAD 1",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_KP_1,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Turn the part back about Z",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_TWO_LATTICES,
	},
	{
		FIELD_ACTION: "turn_z_zero",
		FIELD_CHORD: "NUMPAD 2",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_KP_2,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Put its Z turn back to zero",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "turn_z_forward",
		FIELD_CHORD: "NUMPAD 3",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_KP_3,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Turn the part forward about Z",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_TWO_LATTICES,
	},
	{
		FIELD_ACTION: "turn_coarse",
		FIELD_CHORD: "SHIFT+NUMPAD",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_SHIFT,
		FIELD_LABEL: "Turn in big 15 degree steps",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "15 degrees or the snap, whichever is larger - never smaller than a tap.",
	},
	{
		FIELD_ACTION: "aim_toggle",
		FIELD_CHORD: "NUMPAD 0",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_KP_0,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Point the part at the surface it sits on",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_numpad",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "A toggle: presses alternate between the normal and the placement vector.",
	},
	{
		FIELD_ACTION: "step_yaw_left",
		FIELD_CHORD: "LEFT",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_LEFT,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Swing the part left around its parent",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_arrow",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_TWO_LATTICES,
	},
	{
		FIELD_ACTION: "step_yaw_right",
		FIELD_CHORD: "RIGHT",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_RIGHT,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Swing the part right around its parent",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_arrow",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_TWO_LATTICES,
	},
	{
		FIELD_ACTION: "step_pitch_up",
		FIELD_CHORD: "UP",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_UP,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Tip the part away from its parent",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_arrow",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_TWO_LATTICES,
	},
	{
		FIELD_ACTION: "step_pitch_down",
		FIELD_CHORD: "DOWN",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_DOWN,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Tip the part toward its parent",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_arrow",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_TWO_LATTICES,
	},
	{
		FIELD_ACTION: "step_coarse",
		FIELD_CHORD: "SHIFT+ARROW",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_SHIFT,
		FIELD_LABEL: "Swing in big 15 degree steps",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_arrow",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "lock_x",
		FIELD_CHORD: "X",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_X,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Lock every turn to the X axis",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_axis_key",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "Press the locked axis again to free it.",
	},
	{
		FIELD_ACTION: "lock_y",
		FIELD_CHORD: "Y",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_Y,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Lock every turn to the Y axis",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_axis_key",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_LOCK_EATS_CTRL,
	},
	{
		FIELD_ACTION: "lock_z",
		FIELD_CHORD: "Z",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_Z,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Lock every turn to the Z axis",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_axis_key",
		FIELD_STATUS: STATUS_LIES,
		FIELD_NOTE: NOTE_LOCK_EATS_CTRL,
	},
	{
		FIELD_ACTION: "lock_clear",
		FIELD_CHORD: "ESC",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_ESCAPE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Free the locked axis",
		FIELD_CONTEXT: CONTEXT_LOCKED,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_axis_key",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "Takes ESC before the builder sees it, so it also eats the deselect.",
	},
	{
		FIELD_ACTION: "pivot_toggle",
		FIELD_CHORD: "P",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_P,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Swap spinning in place for swinging",
		FIELD_CONTEXT: CONTEXT_VIEW,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_dispatch_press",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "Stateful between gestures: the same ring means two verbs (ux.md 3.2.4).",
	},
	{
		FIELD_ACTION: "snap_bypass",
		FIELD_CHORD: UNBOUND_CHORD,
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Turn the snap off while you drag",
		FIELD_CONTEXT: CONTEXT_SELECTED,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_placement.gd:set_snap_bypass",
		FIELD_STATUS: STATUS_UNBOUND,
		FIELD_NOTE: NOTE_SNAP_BYPASS,
	},
	{
		FIELD_ACTION: "isolate_exit",
		FIELD_CHORD: "ESC",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_ESCAPE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Close the component you opened",
		FIELD_CONTEXT: CONTEXT_ISOLATED,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/ship_builder.gd:_handle_edit_hotkey",
		FIELD_STATUS: STATUS_DEAD,
		FIELD_NOTE: NOTE_ISOLATE_ESC,
	},
	{
		FIELD_ACTION: "paint_all_parts",
		FIELD_CHORD: "1",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_1,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Paint every part at once",
		FIELD_CONTEXT: CONTEXT_PAINT,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/paint_mode.gd:handle_key",
		FIELD_STATUS: STATUS_DEAD,
		FIELD_NOTE: NOTE_PAINT,
	},
	{
		FIELD_ACTION: "paint_identical",
		FIELD_CHORD: "2",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_2,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Paint every part of the same family",
		FIELD_CONTEXT: CONTEXT_PAINT,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/paint_mode.gd:handle_key",
		FIELD_STATUS: STATUS_DEAD,
		FIELD_NOTE: NOTE_PAINT,
	},
	{
		FIELD_ACTION: "paint_colour_only",
		FIELD_CHORD: "3",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_3,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Paint the colour and leave the texture",
		FIELD_CONTEXT: CONTEXT_PAINT,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/paint_mode.gd:handle_key",
		FIELD_STATUS: STATUS_DEAD,
		FIELD_NOTE: NOTE_PAINT,
	},
	{
		FIELD_ACTION: "paint_texture_only",
		FIELD_CHORD: "4",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_4,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Paint the texture and leave the colour",
		FIELD_CONTEXT: CONTEXT_PAINT,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/paint_mode.gd:handle_key",
		FIELD_STATUS: STATUS_DEAD,
		FIELD_NOTE: NOTE_PAINT,
	},
	{
		FIELD_ACTION: "paint_both",
		FIELD_CHORD: "5",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_5,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Paint the colour and the texture",
		FIELD_CONTEXT: CONTEXT_PAINT,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/builder/paint_mode.gd:handle_key",
		FIELD_STATUS: STATUS_DEAD,
		FIELD_NOTE: NOTE_PAINT,
	},
	{
		FIELD_ACTION: "field_scrub",
		FIELD_CHORD: "LMB DRAG",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Drag the number up or down",
		FIELD_CONTEXT: CONTEXT_FIELD,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/panels/numeric_field.gd:_handle_scrub_button",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "field_fine",
		FIELD_CHORD: "SHIFT (HELD)",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_SHIFT,
		FIELD_LABEL: "Drag the number in smaller steps",
		FIELD_CONTEXT: CONTEXT_FIELD,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/panels/numeric_field.gd:_handle_scrub_motion",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "field_coarse",
		FIELD_CHORD: "CTRL (HELD)",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_CTRL,
		FIELD_LABEL: "Drag the number in bigger steps",
		FIELD_CONTEXT: CONTEXT_FIELD,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/panels/numeric_field.gd:_handle_scrub_motion",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "field_abandon",
		FIELD_CHORD: "ESC",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_ESCAPE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Forget what you typed in the box",
		FIELD_CONTEXT: CONTEXT_FIELD,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_CHANGE,
		FIELD_HANDLER: "harness/panels/numeric_field.gd:_on_entry_gui_input",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	# ------------------------------------------------------------------ exploded and baked
	{
		FIELD_ACTION: "explode_pick",
		FIELD_CHORD: "LMB",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Look at the piece you click",
		FIELD_CONTEXT: CONTEXT_EXPLODED,
		FIELD_TIER: TIER_SHAPE,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_explode_left_button",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "explode_zoom",
		FIELD_CHORD: "WHEEL",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Move the camera in and out",
		FIELD_CONTEXT: CONTEXT_EXPLODED,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_LOOK,
		FIELD_HANDLER: "harness/builder/ship_view3d.gd:_handle_explode_input",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "The plain wheel really does zoom here - there is no part to scale.",
	},
	# ------------------------------------------------------------------ file
	{
		FIELD_ACTION: "dialog_confirm",
		FIELD_CHORD: "ENTER",
		FIELD_ALTS: ["NUMPAD ENTER"],
		FIELD_CODE: KEY_ENTER,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Save it",
		FIELD_CONTEXT: CONTEXT_DIALOG,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_FILE,
		FIELD_HANDLER: "harness/panels/save_dialog.gd:_unhandled_key_input",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "In the description box Return is a newline and never reaches this.",
	},
	{
		FIELD_ACTION: "dialog_cancel",
		FIELD_CHORD: "ESC",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_ESCAPE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Close without saving",
		FIELD_CONTEXT: CONTEXT_DIALOG,
		FIELD_TIER: TIER_BUILD,
		FIELD_GROUP: GROUP_FILE,
		FIELD_HANDLER: "harness/panels/save_dialog.gd:_unhandled_key_input",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "menu_close",
		FIELD_CHORD: "ESC",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_ESCAPE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Close the menu",
		FIELD_CONTEXT: CONTEXT_MENU,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/panels/ship_context_menu.gd:_gui_input",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "menu_dismiss",
		FIELD_CHORD: "LMB",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_NONE,
		FIELD_MODS: MOD_NONE,
		FIELD_LABEL: "Click away to close the menu",
		FIELD_CONTEXT: CONTEXT_MENU,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_PLACE,
		FIELD_HANDLER: "harness/panels/ship_context_menu.gd:_gui_input",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "",
	},
	{
		FIELD_ACTION: "dev_note",
		FIELD_CHORD: "SHIFT+F",
		FIELD_ALTS: [],
		FIELD_CODE: KEY_F,
		FIELD_MODS: MOD_SHIFT,
		FIELD_LABEL: "Write a note about what you just saw",
		FIELD_CONTEXT: CONTEXT_ALWAYS,
		FIELD_TIER: TIER_ENGINEER,
		FIELD_GROUP: GROUP_FILE,
		FIELD_HANDLER: "harness/builder/ship_dev_feedback.gd:opens",
		FIELD_STATUS: STATUS_LIVE,
		FIELD_NOTE: "Debug builds only, and tested before plain F so FRAME keeps its key.",
	},
]


## Every row, dead ones included. The array is a fresh one each call, the row Dictionaries inside
## it are the shared constants - read them, never write them.
static func all() -> Array[Dictionary]:
	return ROWS.duplicate()


## Is this row one a legend may print? DEAD and UNBOUND rows are an audit record, not an offer.
static func is_live(row: Dictionary) -> bool:
	var status: String = str(row.get(FIELD_STATUS, ""))
	return status == STATUS_LIVE or status == STATUS_LIES


## The renderable rows for one state. Exact match on [constant FIELD_CONTEXT] - a consumer that
## wants "always plus what is true now" asks twice and joins the results itself, because the
## alternative is a nesting rule that has to be right in four places instead of one.
static func for_context(context: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in ROWS:
		if is_live(row) and str(row[FIELD_CONTEXT]) == context:
			out.append(row)
	return out


## The renderable rows a given rung of the ladder shows: this tier and everything below it, since
## a tier is the LOWEST rung a binding appears on and ENGINEER is a strict superset.
static func for_tier(tier: String) -> Array[Dictionary]:
	var ceiling: int = tier_rank(tier)
	var out: Array[Dictionary] = []
	if ceiling < 0:
		return out
	for row: Dictionary in ROWS:
		if is_live(row) and tier_rank(str(row[FIELD_TIER])) <= ceiling:
			out.append(row)
	return out


## Where a tier sits on the ladder, or -1 for a name that is not one. BUILD is 0.
static func tier_rank(tier: String) -> int:
	return [TIER_BUILD, TIER_SHAPE, TIER_ENGINEER].find(tier)


## The whole row for a named action, or an empty Dictionary. Actions are unique across the table.
static func row_for(action: String) -> Dictionary:
	for row: Dictionary in ROWS:
		if str(row[FIELD_ACTION]) == action:
			return row
	return {}


## The printable chord for a named action, so a hint can say which key without spelling it out a
## second time. Returns "" for an action that is not in the table, and [constant UNBOUND_CHORD]
## for one that is in the table with no key on it - two different answers on purpose.
static func chord_for(action: String) -> String:
	var row: Dictionary = row_for(action)
	return str(row.get(FIELD_CHORD, ""))


## Every context name the table uses, in first-appearance order.
static func contexts() -> PackedStringArray:
	return _distinct(FIELD_CONTEXT)


## Every group name the table uses, in first-appearance order - the card's headings.
static func groups() -> PackedStringArray:
	return _distinct(FIELD_GROUP)


## The ladder, low rung first.
static func tiers() -> PackedStringArray:
	return PackedStringArray([TIER_BUILD, TIER_SHAPE, TIER_ENGINEER])


static func _distinct(field: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for row: Dictionary in ROWS:
		var value: String = str(row[field])
		if not out.has(value):
			out.append(value)
	return out

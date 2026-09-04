## ShipTutorial - the game-style tutorial. "theres no game style tutorial", verbatim.
##
## GAME STYLE MEANS IT WATCHES, NOT THAT IT TALKS. Every step names one thing to do and clears
## itself the moment the DOCUMENT shows it was done - a part appeared, a rotation is non-zero, a
## hatch exists. Nothing here fakes an action on the player's behalf.
##
## NEXT ALWAYS ADVANCES. RETIRED(2026-09-02): "there is no NEXT button on a step that has not
## happened" - the button was disabled until the step's predicate held, which read as a broken
## button ("tutorial next btn doesnt work so i couldnt test") on any step the player wanted to
## skip, and a card that cannot be moved past blocks the whole panel it sits over. The card still
## clears itself the instant the document shows the step done, and the DONE mark still only ever
## tells the truth; NEXT is simply always there for a player who wants to move on anyway.
##
## It reads the document and never writes it. Not one line below calls begin_edit(), places a part
## or moves a camera: a tutorial that builds the ship for you is a cutscene.
##
## IN-SCENE Control, never a Window (AGENTS section 7) - it has to exist on the device's texture,
## and it sits over the 3D view rather than taking a panel slot, because the left and right columns
## are already full at 1280x800 and the thing it is teaching is in the middle.
##
## DISMISSABLE AND RECOVERABLE. SKIP hides it for the session; the header's HELP button brings it
## back at the first unfinished step. A tutorial with no way out is worse than none, and one with
## no way back is a single-use manual.
##
## The step checks are METHODS, not lambdas written into the step table: gdformat duplicates a
## file's leading comment block into every multi-line lambda it meets inside a literal (this file
## carried five copies of its own header before this was found), and a method reads better anyway.
class_name ShipTutorial
extends Control

## Emitted when the player skips or finishes, so the header can un-press its HELP button.
signal closed

const CARD_WIDTH: float = 300.0
const MARGIN: float = 10.0
## How often the step conditions are re-tested. Most of them are also driven by doc_changed, but
## a few - a rotation drag, an offset drag - commit mid-gesture and the poll is what keeps the card
## honest between commits. Cheap: it reads part records, never resolves a shape.
const POLL_SECONDS: float = 0.35

var _builder: ShipBuilder = null
var _ship_theme: ShipTheme = null
var _title: Label = null
var _body: Label = null
var _progress: Label = null
var _next_button: Button = null
var _step: int = 0
var _timer: Timer = null
var _steps: Array[Dictionary] = []


func setup(builder: ShipBuilder) -> void:
	_builder = builder
	_ship_theme = builder.get_ship_theme()
	_build_steps()
	_build()
	builder.doc_changed.connect(_on_doc_changed)
	builder.selection_changed.connect(_on_selection_changed)


## Shows the tutorial at the first step the document does not already satisfy, so a player who
## opens it after building half a ship is not told to place their first part.
func open() -> void:
	_step = _first_unfinished()
	visible = true
	_refresh()


func close() -> void:
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## The step the card is showing, zero-based. For the harness gates: a NEXT that does not move
## this is the bug this file's header retired.
func current_step() -> int:
	return _step


func step_count() -> int:
	return _steps.size()


## Presses NEXT the way the button does, for a gate that cannot click.
func press_next() -> void:
	_on_next()


# ---------------------------------------------------------------- the steps


## Each step: a title, one instruction, and a predicate over the DOCUMENT that says it happened.
## The predicates are deliberately about state and not about input - "a part has a non-zero
## rotation" rather than "a ring was dragged" - so a player who reaches the same state by typing a
## number into the inspector has genuinely done the step and is not told to do it again.
func _build_steps() -> void:
	_steps = [
		{
			"title": "1. FOUND THE HULL",
			"body":
			(
				"PICK A STARTING MODULE AND PRESS START. EVERY SHIP BEGINS AS ONE PRIMITIVE, "
				+ "OR AS A STOCK TEMPLATE - AN ATOM OR A MOLECULE BUILT FROM ROOMS AND TUNNELS."
			),
			"check": _check_founded,
		},
		{
			"title": "2. ADD A PART",
			"body":
			(
				"CLICK A SHAPE IN THE PART PALETTE, THEN DRAG ONTO YOUR HULL. THE GHOST FOLLOWS "
				+ "THE SURFACE UNDER THE POINTER; RELEASE TO PLACE IT."
			),
			"check": _check_added,
		},
		{
			"title": "3. TURN IT",
			"body":
			(
				"WITH THE NEW PART SELECTED, DRAG ONE OF THE THREE RINGS. EACH RING TURNS THE "
				+ "PART ABOUT THE CIRCLE YOU GRABBED. PRESS P TO SWITCH BETWEEN SPINNING IT IN "
				+ "PLACE AND SWINGING IT ACROSS ITS PARENT."
			),
			"check": _check_turned,
		},
		{
			"title": "4. LIFT IT OFF",
			"body":
			(
				"PULL THE LONG ARROW STANDING OUT OF THE PART. THAT IS OFFSET - HOW FAR IT "
				+ "FLOATS OFF ITS PARENT'S SURFACE. THE SIX SHORT ARROWS STRETCH IT INSTEAD."
			),
			"check": _check_lifted,
		},
		{
			"title": "5. STEP ACROSS THE PARENT",
			"body":
			(
				"PRESS THE ARROW KEYS. EACH PRESS TURNS THE PART'S PLACEMENT VECTOR BY ONE SNAP "
				+ "INCREMENT IN THE PARENT'S FRAME - LEFT AND RIGHT SWING IT ROUND, UP AND DOWN "
				+ "TIP IT - SO THE PART SLIDES ACROSS THE PARENT'S SURFACE. HOLD SHIFT FOR "
				+ "COARSE STEPS."
			),
			"check": _check_stepped,
		},
		{
			"title": "6. NAME A ROOM",
			"body":
			(
				"EVERY PART IS A ROOM. SELECT ONE AND PRESS MAKE ROOM IN THE TREE PANEL TO NAME "
				+ "IT - OR SELECT SEVERAL AND PRESS MAKE ROOM TO JOIN THEM INTO ONE ROOM."
			),
			"check": _check_named_room,
		},
		{
			"title": "7. HATCH TWO ROOMS",
			"body":
			(
				"SELECT TWO PARTS THAT MEET AND PRESS LINK HATCH. THAT IS THE CONNECTION DATA "
				+ "THE HULL IS BUILT AGAINST - PRESS IT AGAIN TO TAKE THE HATCH BACK OUT."
			),
			"check": _check_hatched,
		},
		{
			"title": "8. BAKE IT",
			"body":
			(
				"WATCH THE BUDGET BARS ALONG THE BOTTOM - COMPLEXITY, BOUNDING BOX, VOLUME, "
				+ "WEIGHT AND COST. WHEN THE HULL IS READY, PRESS BAKE. THAT IS THE WHOLE "
				+ "BUILDER."
			),
			"check": _check_never,
		},
	]


func _check_founded() -> bool:
	return _doc() != null


func _check_added() -> bool:
	return _part_count() >= 2


func _check_turned() -> bool:
	return _any_part(func(p: ShipPart) -> bool: return p.rot.length_squared() > 0.0)


func _check_lifted() -> bool:
	return _any_part(func(p: ShipPart) -> bool: return absf(p.offset) > 0.001)


## A part that has been stepped off its snap target: no target, aimed somewhere other than its
## parent's nose. A dragged part reads the same, which is fine - the card clears on the fact,
## and NEXT always advances anyway. RETIRED(2026-09-02): _check_snapped, which looked for a
## part CARRYING a snap target - the arrows used to walk the target list, and now leave it.
## A method, not a lambda: gdformat copies this file's header into every multi-line lambda it
## meets (see the header), and this predicate does not fit on one line.
func _check_stepped() -> bool:
	return _any_part(_is_stepped)


static func _is_stepped(p: ShipPart) -> bool:
	if p.parent.is_empty() or not p.snap_id.is_empty():
		return false
	return absf(p.yaw) > 0.001 or absf(p.pitch) > 0.001


## A room the PLAYER named. Every part is a room (ShipPart.is_room), so the role says nothing
## about whether MAKE ROOM was pressed; the name does. A founded root is named after its family by
## ShipDoc.create_new and a placed part starts unnamed, so any other name on a part is one the
## player gave it - through MAKE ROOM, or by joining several parts into a room, whose instance
## carries the name it was given.
func _check_named_room() -> bool:
	return _any_part(func(p: ShipPart) -> bool: return _player_named(p))


func _check_hatched() -> bool:
	return _hatch_count() > 0


func _check_never() -> bool:
	return false


func _player_named(part: ShipPart) -> bool:
	var given: String = part.display_name.strip_edges()
	return not given.is_empty() and given != part.family


func _first_unfinished() -> int:
	for i: int in _steps.size():
		if not _is_done(i):
			return i
	return _steps.size() - 1


func _is_done(index: int) -> bool:
	if index < 0 or index >= _steps.size():
		return true
	var check: Callable = _steps[index]["check"]
	return bool(check.call())


# ---------------------------------------------------------------- document readers


func _doc() -> ShipDoc:
	return _builder.get_doc() if _builder != null else null


func _part_count() -> int:
	var doc: ShipDoc = _doc()
	return doc.parts.size() if doc != null else 0


## True when ANY authored part satisfies `predicate`. Mirror derivatives are skipped: a twin
## carries a copy of its source's numbers, so counting one would mark a step done that the player
## only did once, on the other side.
func _any_part(predicate: Callable) -> bool:
	var doc: ShipDoc = _doc()
	if doc == null:
		return false
	for pid: String in doc.parts:
		var part: ShipPart = doc.parts[pid]
		if part.is_mirror():
			continue
		if bool(predicate.call(part)):
			return true
	return false


func _hatch_count() -> int:
	var doc: ShipDoc = _doc()
	if doc == null:
		return 0
	var n: int = 0
	for jid: String in doc.joints:
		if (doc.joints[jid] as ShipJoint).mode == ShipJoint.MODE_HATCHED:
			n += 1
	return n


# ---------------------------------------------------------------- construction


func _build() -> void:
	name = "TutorialLayer"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# PASS, not STOP: the tutorial must never swallow a click meant for the thing it is pointing
	# at. Only the card's own buttons take input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var card: PanelContainer = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	card.custom_minimum_size = Vector2(ShipTheme.pxf(CARD_WIDTH), 0.0)
	card.offset_top = ShipTheme.pxf(MARGIN)
	card.offset_left = -ShipTheme.pxf(CARD_WIDTH * 0.5)
	card.offset_right = ShipTheme.pxf(CARD_WIDTH * 0.5)
	add_child(card)

	var box: VBoxContainer = VBoxContainer.new()
	card.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", ShipTheme.font_normal())
	box.add_child(_title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", ShipTheme.font_small())
	box.add_child(_body)

	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	_progress = Label.new()
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.add_theme_font_size_override("font_size", ShipTheme.font_small())
	row.add_child(_progress)
	var skip: Button = Button.new()
	skip.text = "SKIP"
	skip.pressed.connect(close)
	row.add_child(skip)
	_next_button = Button.new()
	_next_button.text = "NEXT"
	_next_button.pressed.connect(_on_next)
	row.add_child(_next_button)

	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.autostart = true
	_timer.timeout.connect(_refresh)
	add_child(_timer)


# ---------------------------------------------------------------- state


func _on_next() -> void:
	if _step + 1 >= _steps.size():
		close()
		return
	_step += 1
	_refresh()


func _on_doc_changed(_doc_arg: ShipDoc) -> void:
	_refresh()


func _on_selection_changed(_ids: PackedStringArray) -> void:
	_refresh()


## Advances past every step the document already satisfies, then draws the first one it does not.
##
## Advancing on refresh rather than only on NEXT is what makes it feel like a game: the card
## changes the instant the thing happens. NEXT is never disabled (see the header): a player who
## wants to move on before the document shows the step done can.
func _refresh() -> void:
	if not visible or _steps.is_empty():
		return
	while _step + 1 < _steps.size() and _is_done(_step):
		_step += 1
	var step: Dictionary = _steps[_step]
	var done: bool = _is_done(_step)
	_title.text = String(step["title"])
	_body.text = String(step["body"])
	_progress.text = "STEP %d OF %d%s" % [_step + 1, _steps.size(), "  DONE" if done else ""]
	_next_button.text = "FINISH" if _step + 1 >= _steps.size() else "NEXT"
	if _ship_theme != null:
		var role: String = "selection" if done else "text"
		_title.add_theme_color_override("font_color", _ship_theme.color_for_role(role))
		_progress.add_theme_color_override("font_color", _ship_theme.color_for_role("text_dim"))

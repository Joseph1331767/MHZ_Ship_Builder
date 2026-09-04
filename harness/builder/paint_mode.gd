## PaintMode - the input grammar of Spore's PAINT mode, plus the region hit test.
##
## THE EDITOR HAS TWO MODES, NOT THREE. `Editors::cEditor` serves every Spore editor with
## `BuildMode`, `PaintMode` and `PlayMode`, but PLAY does not exist in the ship editor -
## confirmed by two independent research passes (API_CONTRACT_SPORE section 10). So this
## class is the whole of the second mode and there is no third.
##
## PER PART, PER REGION, MANUALLY. The creature editor paints procedurally over an entire
## creature; the vehicle, building and UFO editors do not. Here a click hits one part, the
## hit point resolves to one region on it, and that region alone changes unless a modifier
## explicitly widens the reach. See [ShipPaint] for the same warning and for every rule
## about what a region is.
##
## THE GRAMMAR - sourced from the official manual, not invented (SPORE_CLONE_SPEC 2):
## [codeblock]
## LMB                paint the clicked region on the clicked part
## Shift+LMB          paint EVERY region on that part
## Shift+Ctrl+LMB     paint that region on ALL parts of the same family
## Alt+LMB            eyedropper
## hold 1 + LMB       paint that region on ALL blocks
## hold 2 + LMB       paint that region on all IDENTICAL blocks
## 3 / 4 / 5          eyedropper channel: colour only / texture only / both
## [/codeblock]
##
## TWO READINGS THE SOURCE DOES NOT SETTLE, decided here and flagged as decisions rather
## than as facts. The manual lists `1`-`5` as one undifferentiated group ("paint whole part
## / all parts of that type / eyedropper / region + eyedropper modes") and never says
## whether any of them latch.
##   - `1` and `2` are treated as HELD modifiers, released back to single-region painting
##     the moment the key comes up. They sit in the same grammatical slot as Shift and
##     Ctrl, and a latched "repaint every block on the ship" is a trap nobody would want
##     left armed.
##   - `3`, `4` and `5` LATCH, because they select what the eyedropper reads rather than
##     amplifying a destructive action, and because the panel has to be able to show which
##     one is live.
##
## NO GLOBAL INPUT, EVER (SPEC section 10). This is a RefCounted with no viewport: it never
## reads [DisplayServer], `get_window()` or a global mouse position, and it never runs a
## physics query itself. The 3D view hands it a ray it has already built from its own
## Control-local event position, exactly as it does for [ShipPlacement], and supplies the
## surface probe as a [Callable] through [method set_surface_probe]. A direct space state
## is only valid inside a physics frame, so [method click] and [method hover] must be
## called from the view's `_physics_process`.
##
## EVERY MUTATION GOES THROUGH THE EDIT PROTOCOL. [ShipPaint] computes a plan without
## touching the document; this class opens `begin_edit()`, calls `ShipPaint.apply_plan()`
## and closes `commit_edit()`. Nothing here writes to a [ShipDoc] outside that pair.
class_name PaintMode
extends RefCounted

## Paint mode was switched on or off. BUILD and PAINT are the only two modes.
signal active_changed(painting: bool)
signal brush_changed(color: int, texture: String)
signal channel_changed(new_channel: int)
signal method_changed(new_method: int)
signal style_changed(block: String, style_id: String)
signal paint_applied(part_ids: PackedStringArray, spread: int)
signal paint_refused(reason: String)
signal eyedropper_picked(part_id: String, region: String, color: int, texture: String)
signal hover_changed(part_id: String, region: String)

## Which of the three paint sub-options is armed. "Paint Brush" is the direct
## colour+texture mode; the two style modes read `data/paint_styles.json`.
enum Method { BRUSH, COMPLETE_STYLE, PARTIAL_STYLE }

## How far one click reaches. Derived from the modifiers, never set directly.
enum Spread { REGION, PART, FAMILY, IDENTICAL, ALL }

## Edit labels, so undo reads correctly in the history stack.
const LABEL_PAINT: String = "paint"
const LABEL_STYLE: String = "paint style"

const REASON_NO_DOC: String = "NO DOCUMENT"
const REASON_NO_HIT: String = "NOTHING UNDER THE CURSOR"
const REASON_NO_BRUSH: String = "NO COLOUR ARMED"
const REASON_NO_STYLE: String = "NO STYLE SELECTED"
const REASON_UNPAINTED: String = "REGION IS UNPAINTED - NOTHING TO PICK UP"
const REASON_REFUSED: String = "EDIT REFUSED BY BUDGET GUARD"

## Probe result keys, matching [method ShipView3D.probe_surface]. Same contract as
## [ShipPlacement] uses, deliberately: there is one probe shape in this harness.
const PROBE_HIT: String = "hit"
const PROBE_POINT: String = "point"
const PROBE_PART: String = "part"

## Hit-test result keys from [method hit_test].
const HIT_PART: String = "part"
const HIT_REGION: String = "region"
const HIT_POINT: String = "point"

## Below this the shape has no usable local-Y extent and every point falls in region 0.
const MIN_BAND_SPAN_M: float = 1.0e-6

## True between [method set_active] on and off. The view routes clicks here only then.
var active: bool = false

var _builder: ShipBuilder = null
var _probe: Callable = Callable()

## The armed brush, in the pinned {"color": int, "texture": String} shape.
var _color: int = ShipPaint.UNPAINTED
var _texture: String = ""
var _channel: int = ShipPaint.Channel.BOTH
var _method: int = Method.BRUSH

## Parsed `data/paint_styles.json`, handed in by the panel - [ShipData] does not load it.
var _pack: Dictionary = {}
var _style_block: String = ShipPaint.BLOCK_COMPLETE
var _style_id: String = ""

## Held spread keys. See the class docstring for why these are momentary.
var _key_all: bool = false
var _key_identical: bool = false

var _hover_part: String = ""
var _hover_region: String = ""

## part_id -> Transform3D / ResolvedShape, rebuilt on every document change. Covers mirror
## derivatives as well as real parts, because a click can land on a twin's collider.
var _xforms: Dictionary = {}
var _shapes: Dictionary = {}
var _cache_valid: bool = false

# ---------------------------------------------------------------- wiring


func setup(builder: ShipBuilder) -> void:
	_builder = builder
	_cache_valid = false


## Bind the view's surface probe. Signature:
## `func(origin: Vector3, dir: Vector3, blocked: PackedStringArray) -> Dictionary`
## returning {"hit": bool, "point": Vector3 (ship space), "part": String}.
func set_surface_probe(probe: Callable) -> void:
	_probe = probe


## Parsed `data/paint_styles.json`. The harness reads the file; this class only reads the
## Dictionary, so `core/` purity and the no-`res://`-in-logic rule both stay intact.
func set_style_pack(pack: Dictionary) -> void:
	_pack = pack


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if not active:
		_key_all = false
		_key_identical = false
		_set_hover("", "")
	active_changed.emit(active)


func is_active() -> bool:
	return active


## Drop the resolved-transform cache. Hook to `ShipBuilder.doc_changed`.
##
## The parameter is deliberately NOT called `_doc`: that is the name of this class's own
## live-document accessor, and a parameter of that name would silently shadow it for any
## future edit to this function that reached for `_doc()`.
func notify_doc_changed(_new_doc: ShipDoc) -> void:
	_cache_valid = false
	_xforms = {}
	_shapes = {}


# ---------------------------------------------------------------- brush state


## Arm the brush. [param color] is an INDEX into the active palette, never a hex value -
## that indirection is what lets a budget alert swap the LUT and recolour every painted
## ship with it (SPEC section 11).
func set_brush(color: int, texture: String) -> void:
	if color == _color and texture == _texture:
		return
	_color = color
	_texture = texture
	brush_changed.emit(_color, _texture)


func brush() -> Dictionary:
	return ShipPaint.make_entry(_color, _texture)


## [constant ShipPaint.Channel] - which half of the brush a click writes, and which half
## the eyedropper reads back.
func set_channel(new_channel: int) -> void:
	if new_channel == _channel:
		return
	_channel = new_channel
	channel_changed.emit(_channel)


func channel() -> int:
	return _channel


func set_method(new_method: int) -> void:
	if new_method == _method:
		return
	_method = new_method
	method_changed.emit(_method)


func paint_method() -> int:
	return _method


## Select a catalogue style. [param block] is [constant ShipPaint.BLOCK_COMPLETE] or
## [constant ShipPaint.BLOCK_PARTIAL]; "" for [param style_id] disarms the style.
func set_style(block: String, style_id: String) -> void:
	if block == _style_block and style_id == _style_id:
		return
	_style_block = block
	_style_id = style_id
	style_changed.emit(_style_block, _style_id)


func style() -> Dictionary:
	return {"block": _style_block, "id": _style_id}


func hovered() -> Dictionary:
	return {HIT_PART: _hover_part, HIT_REGION: _hover_region}


# ---------------------------------------------------------------- input


## One left-click, already decoded by the view. [param origin] and [param dir] are a ray in
## SHIP space; the three booleans are the modifiers that were down on the event.
##
## Returns true when the click was consumed - which includes a click that hit nothing while
## paint mode is live, because falling through to selection there would silently drop the
## player back into BUILD behaviour.
##
## MUST be called from a physics frame: the surface probe runs a space query.
func click(origin: Vector3, dir: Vector3, shift: bool, ctrl: bool, alt: bool) -> bool:
	if not active:
		return false
	var hit: Dictionary = hit_test(origin, dir)
	var part_id: String = str(hit.get(HIT_PART, ""))
	if part_id == "":
		_set_hover("", "")
		paint_refused.emit(REASON_NO_HIT)
		return true
	var region: String = str(hit.get(HIT_REGION, ""))
	_set_hover(part_id, region)
	if alt:
		_pick(part_id, region)
		return true
	_paint(part_id, region, _spread_for(shift, ctrl))
	return true


## Pointer moved without a click: refresh the hovered part/region so the panel can show
## which region is about to be painted. Also physics-frame only.
func hover(origin: Vector3, dir: Vector3) -> void:
	if not active:
		return
	var hit: Dictionary = hit_test(origin, dir)
	_set_hover(str(hit.get(HIT_PART, "")), str(hit.get(HIT_REGION, "")))


## The `1`-`5` keys. Returns true when the key belonged to paint mode and must not reach
## the rest of the builder's hotkeys.
func handle_key(event: InputEventKey) -> bool:
	if not active or event == null or event.echo:
		return false
	match event.keycode:
		KEY_1:
			_key_all = event.pressed
		KEY_2:
			_key_identical = event.pressed
		KEY_3:
			_latch_channel(event.pressed, ShipPaint.Channel.COLOR)
		KEY_4:
			_latch_channel(event.pressed, ShipPaint.Channel.TEXTURE)
		KEY_5:
			_latch_channel(event.pressed, ShipPaint.Channel.BOTH)
		_:
			return false
	return true


## The selection-driven path, for a panel button rather than a click in the 3D view.
## Applies the current method to [param part_ids]; [param region] of "" means every region
## the part declares. Returns the number of parts that actually changed.
func apply_current(part_ids: PackedStringArray, region: String) -> int:
	var doc: ShipDoc = _doc()
	if doc == null:
		paint_refused.emit(REASON_NO_DOC)
		return 0
	# Checked ONCE, before the loop: a per-part check would fire the same refusal as many
	# times as there are selected parts and bury the status line under its own repeats.
	var blocked: String = _armed_reason()
	if blocked != "":
		paint_refused.emit(blocked)
		return 0
	var plan: Dictionary = {}
	for pid: String in part_ids:
		var source: String = _source_part_id(pid)
		var one: Dictionary = _plan_one(doc, source, region)
		for key: Variant in one:
			plan[key] = one[key]
	return _commit(plan, Spread.PART).size()


# ---------------------------------------------------------------- hit testing


## Resolve a ray to { "part": String, "region": String, "point": Vector3 }. Every field is
## empty/zero on a miss. `part` is always a REAL part id: a ray that lands on a mirror
## derivative's collider resolves to the source part, because a twin is generated, has no
## record of its own, and cannot store paint.
func hit_test(origin: Vector3, dir: Vector3) -> Dictionary:
	var miss: Dictionary = {HIT_PART: "", HIT_REGION: "", HIT_POINT: Vector3.ZERO}
	if not _probe.is_valid():
		return miss
	var raw: Variant = _probe.call(origin, dir, PackedStringArray())
	if not (raw is Dictionary):
		return miss
	var result: Dictionary = raw
	if not bool(result.get(PROBE_HIT, false)):
		return miss
	var picked: String = str(result.get(PROBE_PART, ""))
	if picked == "":
		return miss
	var point: Vector3 = result.get(PROBE_POINT, Vector3.ZERO)
	var source: String = _source_part_id(picked)
	return {
		HIT_PART: source,
		HIT_REGION: _region_at(picked, source, point),
		HIT_POINT: point,
	}


## Which paint region a SHIP-SPACE point on [param part_id] belongs to.
##
## PHASE-1 APPROACH: EQUAL HEIGHT BANDS ALONG THE PART'S LOCAL Y AXIS. The point is
## transformed into the part's own frame, its local Y is normalised against the shape's
## local-Y extent, and the resulting 0..1 fraction is cut into as many equal bands as the
## family declares regions. Band 0 (the family's FIRST region, conventionally "base") is
## the -Y end, band n-1 (conventionally "detail") is the +Y end.
##
## WHY LOCAL Y AND NOT A DOMINANT-AXIS FACE TEST. Local Y is the only axis with a
## consistent meaning across all six base primitives: [ResolvedShape] documents `size.y` as
## the local half-height for every base, the taper and rib ops are parameterised against
## it, and [method ResolvedShape.mount_inset] measures to the attach face along local -Y,
## so -Y is always the keel end and +Y always the far end. A dominant-axis test would
## produce six buckets for three regions, and it is unstable near a diagonal on a sphere or
## a cylinder, where "which face is this" has no answer. The height band also matches what
## `data/paint_styles.json` already says it is doing - "near-black at the keel rising to a
## cold instrument green at the top surfaces", "a lighter working band at the waist" - so
## the authored pack and the hit test agree about what a region means.
##
## [b]WHAT THIS IS NOT.[/b] It is an approximation and it is presented as one:
##
##   1. There is no real region decomposition to be exact about. The SDF carries no UVs, no
##      material ids and no per-face tags, so nothing in the data says where "coat" ends.
##      The band is a stand-in for authored regions, not a recovery of them.
##   2. Bands are equal slices of the shape's local-Y AABB, so on a tapered, ribbed or
##      scalloped shape the bands do not line up with the visual features a player would
##      aim at. A cone's "waist" band is a third of its height, not a third of its surface.
##   3. Two surface points at the same height are ALWAYS the same region. Port/starboard,
##      fore/aft and inside/outside splits are impossible under this scheme; a torus's hole
##      and its outer rim at the same Y are one region.
##   4. The pick collider is a convex hull of the PREVIEW mesh, not the SDF surface, so on
##      a warped shape the hit point is near, not on, the true surface. Within a few
##      centimetres of a band boundary that error can select the neighbour.
##   5. Boundaries are hard steps with no hysteresis, so a click a pixel either side of one
##      flips region.
##   6. Region ORDER is the family's authored `paint_regions` order. A pack that lists its
##      regions in another order silently re-maps which end of the part is which.
##
## The honest fix is authored regions per family (a Phase-2 data change), not a cleverer
## approximation. Until then, callers should show the resolved region name before the
## click commits - which is what [signal hover_changed] is for.
func region_at_point(part_id: String, ship_point: Vector3) -> String:
	return _region_at(part_id, part_id, ship_point)


# ---------------------------------------------------------------- internals


func _region_at(picked_id: String, source_id: String, ship_point: Vector3) -> String:
	var regions: PackedStringArray = ShipPaint.regions_for_part(_doc(), _data(), source_id)
	if regions.is_empty():
		return ""
	_refresh_cache()
	# The transform is looked up under the PICKED id so a click on a mirror derivative is
	# unprojected through the twin's own reflected basis; the paint still lands on the
	# source, which is what `source_id` is for.
	var xform_raw: Variant = _xforms.get(picked_id, null)
	var shape_raw: Variant = _shapes.get(picked_id, null)
	if not (xform_raw is Transform3D) or not (shape_raw is ResolvedShape):
		return regions[0]
	var xform: Transform3D = xform_raw
	var shape: ResolvedShape = shape_raw
	var local: Vector3 = xform.affine_inverse() * ship_point
	var half_h: float = shape.local_aabb().size.y * 0.5
	if half_h <= MIN_BAND_SPAN_M:
		return regions[0]
	var t: float = clampf((local.y + half_h) / (half_h * 2.0), 0.0, 1.0)
	var band: int = clampi(int(t * float(regions.size())), 0, regions.size() - 1)
	return regions[band]


func _refresh_cache() -> void:
	if _cache_valid:
		return
	var doc: ShipDoc = _doc()
	var data: ShipData = _data()
	var cfg: ShipConfig = _config()
	if doc == null or data == null or cfg == null:
		return
	_shapes = ShipAttach.resolve_shapes(doc, data, cfg)
	_xforms = ShipAttach.resolve_all(doc, data, cfg)
	_cache_valid = true


## A twin's id maps back to its source. A mirror derivative is generated on the fly, has no
## [ShipPart] record and therefore nowhere to store paint; painting one paints the pair,
## which is also what the player sees happen.
func _source_part_id(part_id: String) -> String:
	if ShipSymmetry.is_twin_id(part_id):
		return ShipSymmetry.source_of_twin(part_id)
	return part_id


## Modifier precedence. Shift+Ctrl beats Shift, and both beat the held `1`/`2` keys - the
## manual lists the mouse modifiers as the primary grammar and the number keys as an extra.
func _spread_for(shift: bool, ctrl: bool) -> int:
	if shift and ctrl:
		return Spread.FAMILY
	if shift:
		return Spread.PART
	if _key_all:
		return Spread.ALL
	if _key_identical:
		return Spread.IDENTICAL
	return Spread.REGION


## `3`/`4`/`5` LATCH: they select what the eyedropper reads rather than amplifying a
## destructive action, so only the press edge is acted on and the release does nothing.
func _latch_channel(pressed: bool, channel_value: int) -> void:
	if pressed:
		set_channel(channel_value)


func _paint(part_id: String, region: String, spread: int) -> void:
	var doc: ShipDoc = _doc()
	if doc == null:
		paint_refused.emit(REASON_NO_DOC)
		return
	var plan: Dictionary = _plan(doc, part_id, region, spread)
	if plan.is_empty():
		return
	_commit(plan, spread)


## Build the plan for one click. Style methods ignore the region the click resolved to -
## a complete style covers every region by definition and a partial style names its own -
## but they still honour the spread, so Shift+Ctrl spreads a style across a family exactly
## the way it spreads a brush colour.
func _plan(doc: ShipDoc, part_id: String, region: String, spread: int) -> Dictionary:
	var blocked: String = _armed_reason()
	if blocked != "":
		paint_refused.emit(blocked)
		return {}
	if _method == Method.BRUSH:
		return _plan_brush(doc, part_id, region, spread)
	var out: Dictionary = {}
	for pid: String in _targets(doc, part_id, spread):
		var one: Dictionary = _plan_style(doc, pid)
		for key: Variant in one:
			out[key] = one[key]
	return out


## "" when the current method has everything it needs to paint, else the refusal to
## report. Checked once per gesture, never once per part.
func _armed_reason() -> String:
	if _method != Method.BRUSH:
		if ShipPaint.catalogue_entry(_pack, _style_block, _style_id).is_empty():
			return REASON_NO_STYLE
		return ""
	# A texture-only pass is legal with no colour armed: it writes the finish and leaves
	# whatever colour the region already carries.
	if _color == ShipPaint.UNPAINTED and _channel != ShipPaint.Channel.TEXTURE:
		return REASON_NO_BRUSH
	return ""


func _plan_brush(doc: ShipDoc, part_id: String, region: String, spread: int) -> Dictionary:
	var data: ShipData = _data()
	var armed: Dictionary = brush()
	match spread:
		Spread.PART:
			return ShipPaint.plan_part(doc, data, part_id, armed, _channel)
		Spread.FAMILY:
			var part: ShipPart = _part(doc, part_id)
			if part == null:
				return {}
			return ShipPaint.plan_family(doc, data, part.family, region, armed, _channel)
		Spread.IDENTICAL:
			return ShipPaint.plan_identical(doc, data, part_id, region, armed, _channel)
		Spread.ALL:
			return ShipPaint.plan_all(doc, data, region, armed, _channel)
	return ShipPaint.plan_region(doc, data, part_id, region, armed, _channel)


## The set of parts one click reaches, for the STYLE methods. The brush path resolves its
## own set inside [ShipPaint] so a region that a family does not declare is dropped there.
##
## REGION and PART both land on the clicked part alone: a style already names the regions
## it touches, so the region the click resolved to only narrows the brush path.
func _targets(doc: ShipDoc, part_id: String, spread: int) -> PackedStringArray:
	match spread:
		Spread.FAMILY:
			var part: ShipPart = _part(doc, part_id)
			if part == null:
				return PackedStringArray()
			return ShipPaint.parts_of_family(doc, part.family)
		Spread.IDENTICAL:
			return ShipPaint.identical_part_ids(doc, part_id)
		Spread.ALL:
			return doc.part_order()
	return PackedStringArray([part_id])


## Already known to be armed - [method _armed_reason] proved the entry exists before the
## caller started looping, so this one does not re-report an empty style per part.
func _plan_style(doc: ShipDoc, part_id: String) -> Dictionary:
	var entry: Dictionary = ShipPaint.catalogue_entry(_pack, _style_block, _style_id)
	if entry.is_empty():
		return {}
	if _style_block == ShipPaint.BLOCK_PARTIAL:
		return ShipPaint.plan_partial_style(doc, _data(), part_id, entry)
	return ShipPaint.plan_complete_style(doc, _data(), part_id, entry)


## One target, one method - the shared body of the selection-driven path. [param region] of
## "" means every region the part declares.
func _plan_one(doc: ShipDoc, part_id: String, region: String) -> Dictionary:
	if _method != Method.BRUSH:
		return _plan_style(doc, part_id)
	var armed: Dictionary = brush()
	if region == "":
		return ShipPaint.plan_part(doc, _data(), part_id, armed, _channel)
	return ShipPaint.plan_region(doc, _data(), part_id, region, armed, _channel)


## The only write path. `commit_edit()` runs the budget guard and can roll the document
## back; paint changes no geometry so it never should, but a refusal is reported rather
## than assumed away.
func _commit(plan: Dictionary, spread: int) -> PackedStringArray:
	var empty: PackedStringArray = PackedStringArray()
	if plan.is_empty() or _builder == null:
		return empty
	var doc: ShipDoc = _doc()
	if doc == null:
		paint_refused.emit(REASON_NO_DOC)
		return empty
	var label: String = LABEL_PAINT if _method == Method.BRUSH else LABEL_STYLE
	_builder.begin_edit(label)
	var changed: PackedStringArray = ShipPaint.apply_plan(doc, plan)
	if changed.is_empty():
		# Nothing moved: the region already carried this colour. Leave the history alone
		# rather than committing an edit that undoes to an identical document.
		return empty
	_builder.commit_edit(changed)
	if _builder.get_doc() != doc:
		paint_refused.emit(REASON_REFUSED)
		return empty
	paint_applied.emit(changed, spread)
	return changed


func _pick(part_id: String, region: String) -> void:
	var stored: Dictionary = ShipPaint.region_paint(_doc(), part_id, region)
	if stored.is_empty():
		paint_refused.emit(REASON_UNPAINTED)
		return
	var color: int = int(stored.get(ShipPart.PAINT_COLOR, ShipPaint.UNPAINTED))
	var texture: String = str(stored.get(ShipPart.PAINT_TEXTURE, ""))
	var next_color: int = _color
	var next_texture: String = _texture
	if _channel == ShipPaint.Channel.COLOR or _channel == ShipPaint.Channel.BOTH:
		next_color = color
	if _channel == ShipPaint.Channel.TEXTURE or _channel == ShipPaint.Channel.BOTH:
		next_texture = texture
	set_brush(next_color, next_texture)
	eyedropper_picked.emit(part_id, region, color, texture)


func _set_hover(part_id: String, region: String) -> void:
	if part_id == _hover_part and region == _hover_region:
		return
	_hover_part = part_id
	_hover_region = region
	hover_changed.emit(_hover_part, _hover_region)


func _part(doc: ShipDoc, part_id: String) -> ShipPart:
	if doc == null:
		return null
	var raw: Variant = doc.parts.get(part_id, null)
	if raw is ShipPart:
		var part: ShipPart = raw
		return part
	return null


func _doc() -> ShipDoc:
	return _builder.get_doc() if _builder != null else null


func _data() -> ShipData:
	return _builder.get_data() if _builder != null else null


func _config() -> ShipConfig:
	return _builder.get_config() if _builder != null else null

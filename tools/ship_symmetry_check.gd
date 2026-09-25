extends SceneTree
## THE PREBUILT CLASSES' WEIGHT BALANCE, per axis. Headless; run through tools/ship_run.ps1.
##
## The author's rule (dev note 2026-09-24, clarified 2026-09-25): "we need symetry across at least 1
## axis with reguards to our prebuilds ... make it based on weight (mirrored weight)", and then:
## "com only has to adhear to the axes that are symetrical, and with 3 orthognal axies to choose
## from and the constraint that only 1 has to be symetrical means that any of our pre built shapes
## should be able to obtain that."
##
## So: ANY ONE axis passing is a pass. X is not special - that reading was the agent's, and it hid
## the fact that the four failing classes fail on all three at once.
##
## Weight is the shell model the builder already
## uses - `surface_area_m2 * areal_density_kg_m2` - and every hull is placeholdered at one density,
## so a part's weight is its surface area and a class's centre of mass is the area-weighted mean of
## its parts' centres. The offset is reported as a fraction of the class's own half extent, so a
## twenty-metre ship and a three-metre one are read on the same scale.
##
## REPORTS, IT DOES NOT GATE - yet. Four classes fail on every axis at once and the reason is
## structural rather than a mistake (see below), so failing the build on them would only stop work.
## When they are resolved this becomes a gate, and the line to change is [constant GATE].

## Exit non-zero when a class is symmetric on no axis at all. False while the four known ones stand.
const GATE: bool = false

## Off by more than this fraction of the half extent and the axis is not symmetric. Loose enough to
## ignore float dust in a tessellation, tight enough that one arm out of a dozen bodies shows.
const TOLERANCE: float = 0.02

const ELEMENTS: Array = [
	"hydrogen",
	"helium",
	"lithium",
	"beryllium",
	"boron",
	"carbon",
	"nitrogen",
	"oxygen",
	"fluorine",
	"neon",
	"sodium",
	"silicon",
	"phosphorus",
	"sulphur",
	"chlorine",
	"argon"
]


func _init() -> void:
	var data := ShipData.new()
	if not data.load_all():
		printerr("ShipData.load_all() failed: %s" % [str(data.load_errors)])
		quit(1)
		return
	var cfg: ShipConfig = data.config if data.config != null else ShipConfig.defaults()
	print("=== prebuilt symmetry check ===")
	print("  centre of mass off each plane, as a fraction of the half extent")
	print("  AT LEAST ONE axis must pass; which one is the class's own business")
	print("")
	print("  class              X        Y        Z     passing")
	var failed: PackedStringArray = PackedStringArray()
	for name: String in ELEMENTS:
		var doc: ShipDoc = ShipTemplates.build(data, cfg, name, {})
		if doc == null:
			printerr("  %s did not build" % name)
			continue
		var off: Vector3 = _balance(doc, data, cfg)
		var passing: String = ""
		for axis: int in 3:
			if off[axis] <= TOLERANCE:
				passing += ["x", "y", "z"][axis]
		if passing.is_empty():
			failed.append(name)
		print(
			(
				"  %-16s %7.4f  %7.4f  %7.4f     %-5s%s"
				% [
					name,
					off.x,
					off.y,
					off.z,
					passing,
					"   <- NO AXIS" if passing.is_empty() else ""
				]
			)
		)
	print("")
	if failed.is_empty():
		print("=== prebuilt symmetry check PASSED - every class is balanced on some axis ===")
		quit(0)
		return
	print(
		(
			"  %d of %d are symmetric on NO axis: %s"
			% [failed.size(), ELEMENTS.size(), ", ".join(failed)]
		)
	)
	print("")
	print("  WHY, and it is structural rather than a mistake: a class takes one arm per valence")
	print("  electron and its nucleus takes one body per proton, clamped to eight - which is the")
	print("  CUBIC arrangement. Arms are handed out in mirror pairs (ADR 0044), so an EVEN count")
	print("  balances exactly; all four of these have ODD valence, and the leftover arm sits on a")
	print("  CUBE CORNER, which is off all three planes at once by the same amount. That is why")
	print("  they fail every axis rather than only one, and why no slot choice fixes it.")
	print("  See FOLLOWUPS F51: resize a body to compensate, re-berth the odd arm, or cull.")
	if GATE:
		quit(1)
		return
	print("")
	print("=== prebuilt symmetry check REPORTED (not gating; see GATE) ===")
	quit(0)


## How far the area-weighted centre of mass sits off each plane, as a fraction of the half extent.
func _balance(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Vector3:
	var plan: Dictionary = ShipMeshBake.plan(doc, data, cfg)
	var outer: Dictionary = plan["outer"]
	var total: float = 0.0
	var moment: Vector3 = Vector3.ZERO
	var box: AABB = AABB()
	var first: bool = true
	for id: String in plan["ids"] as PackedStringArray:
		if not outer.has(id):
			continue
		var mesh: PolyMesh = outer[id]
		var weight: float = mesh.area()
		if weight <= 0.0:
			continue
		total += weight
		moment += mesh.aabb().get_center() * weight
		box = mesh.aabb() if first else box.merge(mesh.aabb())
		first = false
	if total <= 0.0 or first:
		return Vector3.ZERO
	var centre: Vector3 = moment / total
	var half: Vector3 = box.size * 0.5
	return Vector3(
		absf(centre.x) / maxf(half.x, 0.001),
		absf(centre.y) / maxf(half.y, 0.001),
		absf(centre.z) / maxf(half.z, 0.001)
	)

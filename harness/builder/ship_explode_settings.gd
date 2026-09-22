class_name ShipExplodeSettings
extends RefCounted
## What the player sets for the exploded view (ADR 0031), and the file that remembers it.
##
## "we will have explode specific options/toggles to configure as a player. we will have a part
## separation toggle with a slider that dictates how far it separates ... 3 orthogonal slices, and
## offer single slice or double slice in each orthogonal direction for bisection vs trisection. and
## a separation value for those pieces as well ... a nodecluster bisector includer toggle that lets
## chunks from nodes get sliced with its own isolated slicing settings" (2026-09-21).
##
## VIEW STATE, NEVER DOCUMENT STATE. Nothing here is written into a ship file or enters its hash;
## it lives in the player's own user:// file, so every ship explodes the way this player likes.
##
## TWO KINDS OF SETTING, TWO COSTS. The separations only move what is already on screen and take
## effect at once. The slice counts decide what the engine cuts, so they are made by the next
## extras bake, behind APPLY (the no-automatic-heavy-work rule, ADR 0028).

const SAVE_PATH: String = "user://explode_settings.json"
const FILE_VERSION: int = 1

## Per-axis slice counts.
const OFF: int = 0
const BISECT: int = 1
const TRISECT: int = 2

## Slider bounds, in metres.
const SEPARATION_MAX_M: float = 10.0
const SLICE_SEPARATION_MAX_M: float = 5.0

## A slice is pulled this fraction of the module separation off its cut unless the player says
## otherwise - the half gap the exploded view always used.
const SLICE_GAP_FRACTION: float = 0.35

## Modules, and the chunks of a room of several, are pulled apart at their seams.
var separate: bool = true
## How much clear space each seam opens, beyond the module's own extent.
var separation_m: float = 1.5
## How a piece standing alone - and a room shown whole - is sliced: counts per axis X, Y, Z of
## its own frame, Y the placement normal.
var slices: Vector3i = Vector3i(OFF, OFF, BISECT)
## How far each slice is pulled off its cut.
var slice_separation_m: float = 0.525
## Whether the chunks of a room of several are sliced at all - with their own settings below.
var cluster_slicing: bool = true
var cluster_slices: Vector3i = Vector3i(OFF, OFF, BISECT)
var cluster_slice_separation_m: float = 0.525


## The shipped defaults, the separations scaled off the tuning pack's explode gap.
static func defaults(cfg: ShipConfig) -> ShipExplodeSettings:
	var s: ShipExplodeSettings = ShipExplodeSettings.new()
	if cfg != null:
		s.separation_m = clampf(cfg.explode_gap_m, 0.0, SEPARATION_MAX_M)
		s.slice_separation_m = clampf(
			cfg.explode_gap_m * SLICE_GAP_FRACTION, 0.0, SLICE_SEPARATION_MAX_M
		)
		s.cluster_slice_separation_m = s.slice_separation_m
	return s


## The player's saved settings over the defaults, or the defaults when there is no file or it
## cannot be read.
static func load_or_defaults(cfg: ShipConfig, path: String = SAVE_PATH) -> ShipExplodeSettings:
	var base: ShipExplodeSettings = defaults(cfg)
	if not FileAccess.file_exists(path):
		return base
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return base
	return from_dict(parsed, base)


## [param d] read over a copy of [param base]; anything missing or malformed keeps base's value.
static func from_dict(d: Dictionary, base: ShipExplodeSettings) -> ShipExplodeSettings:
	var s: ShipExplodeSettings = base.copy()
	s.separate = bool(d.get("separate", s.separate))
	s.separation_m = clampf(float(d.get("separation_m", s.separation_m)), 0.0, SEPARATION_MAX_M)
	s.slices = _axes(d.get("slices", null), s.slices)
	s.slice_separation_m = clampf(
		float(d.get("slice_separation_m", s.slice_separation_m)), 0.0, SLICE_SEPARATION_MAX_M
	)
	s.cluster_slicing = bool(d.get("cluster_slicing", s.cluster_slicing))
	s.cluster_slices = _axes(d.get("cluster_slices", null), s.cluster_slices)
	s.cluster_slice_separation_m = clampf(
		float(d.get("cluster_slice_separation_m", s.cluster_slice_separation_m)),
		0.0,
		SLICE_SEPARATION_MAX_M
	)
	return s


func to_dict() -> Dictionary:
	return {
		"version": FILE_VERSION,
		"separate": separate,
		"separation_m": separation_m,
		"slices": [slices.x, slices.y, slices.z],
		"slice_separation_m": slice_separation_m,
		"cluster_slicing": cluster_slicing,
		"cluster_slices": [cluster_slices.x, cluster_slices.y, cluster_slices.z],
		"cluster_slice_separation_m": cluster_slice_separation_m,
	}


func copy() -> ShipExplodeSettings:
	var s: ShipExplodeSettings = ShipExplodeSettings.new()
	s.separate = separate
	s.separation_m = separation_m
	s.slices = slices
	s.slice_separation_m = slice_separation_m
	s.cluster_slicing = cluster_slicing
	s.cluster_slices = cluster_slices
	s.cluster_slice_separation_m = cluster_slice_separation_m
	return s


## Writes the settings to [param path]. False when the file cannot be opened - the settings still
## hold for this session.
func save(path: String = SAVE_PATH) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


## The slicing the engine is asked for (ShipCsgBake.bake_extras): a cluster whose chunks are not
## included is not sliced at all.
func slicing() -> Dictionary:
	return {"parts": slices, "clusters": cluster_slices if cluster_slicing else Vector3i.ZERO}


## A three-entry array of counts, each clamped to OFF..TRISECT, or [param fallback].
static func _axes(value: Variant, fallback: Vector3i) -> Vector3i:
	if not (value is Array) or (value as Array).size() != 3:
		return fallback
	var a: Array = value
	return Vector3i(
		clampi(int(a[0]), OFF, TRISECT),
		clampi(int(a[1]), OFF, TRISECT),
		clampi(int(a[2]), OFF, TRISECT)
	)

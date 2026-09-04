## ScreenSurface - a diegetic screen: a hand-built textured quad, a thin collider, a
## bezel and a focus indicator, all in one self-contained node. This is the piece
## MHZ_Origins is expected to reuse directly: give it a size and a ViewportTexture and it
## does the mesh/material/collider/focus-visual work (see docs/DIEGETIC_HOST.md).
##
## SCENE IS CODE-BUILT ON PURPOSE (SPEC section 10 / AGENTS section 7). There is no .tscn
## for this class at all - DiegeticHost creates it with `ScreenSurface.new()`, sets the
## sizing properties below, then calls `add_child()`, which is what triggers `_ready()`
## and the actual mesh/collider construction.
##
## UV / PIXEL CONVENTION - read this before touching the raycast side in diegetic_host.gd.
## The screen quad is built by hand in `_build_screen_mesh()`, not with QuadMesh, so this
## comment can be authoritative instead of trusting an opaque primitive's internal layout:
##
##   - Local space: the quad lies in the node's local XY plane at z = 0, and its face
##     normal is local +Z - the side a player standing in front of the console looks at.
##     Embed this node by rotating the NODE, never by re-authoring the mesh: the winding
##     below assumes local +Z is still "the viewing side" after any parent transform.
##   - The vertex at local (-half_width, +half_height, 0) - "top-left" to a reader facing
##     the screen - is assigned uv = (0, 0). The vertex at
##     (+half_width, -half_height, 0) - "bottom-right" - is assigned uv = (1, 1).
##   - That makes u run left(0) -> right(1) and v run top(0) -> bottom(1). That is exactly
##     the orientation of Viewport pixel space (origin top-left, x right, y down) AND of a
##     ViewportTexture sampled the way it looks in the editor / on a TextureRect (row 0 of
##     the rendered image is v = 0). Both conventions already agree, so
##     `uv_to_pixel()` needs NO vertical flip - the classic mirrored-UI bug this milestone
##     is supposed to catch. This agreement is a construction choice made here, not an
##     engine law - re-derive it if this mesh is ever swapped for a built-in primitive.
##   - Winding: front-facing triangles are counter-clockwise as seen from local +Z (the
##     viewer's side), which is Godot's default front face under `CULL_BACK`. Traced by
##     hand with the shoelace formula on both triangles in `_build_screen_mesh()`; culling
##     is left at its default (not force-disabled) specifically so a mistake here would be
##     visible - an honest signal, since this file cannot be run to check it directly.
class_name ScreenSurface
extends StaticBody3D

const COLLIDER_THICKNESS_M: float = 0.02
const BEZEL_COLOR: Color = Color(0.05, 0.06, 0.07)
const INDICATOR_UNFOCUSED_COLOR: Color = Color(0.10, 0.30, 0.30)
const INDICATOR_FOCUSED_COLOR: Color = Color(0.35, 0.95, 0.85)
const INDICATOR_UNFOCUSED_ENERGY: float = 0.35
const INDICATOR_FOCUSED_ENERGY: float = 2.4

## Physical size of the screen quad, metres. Set before `add_child()` triggers `_ready()`.
var width_m: float = 1.2
var height_m: float = 0.75
## Pixel resolution of the SubViewport this screen is expected to display. Only used by
## `uv_to_pixel()` - the mesh/collider do not depend on it.
var viewport_size: Vector2i = Vector2i(1280, 800)
## Extra frame width/depth around the screen, metres. Cosmetic only.
var bezel_margin_m: float = 0.06
var bezel_depth_m: float = 0.05

var _screen_material: StandardMaterial3D = null
var _indicator_material: StandardMaterial3D = null
var _focused: bool = false


func _ready() -> void:
	var screen_mesh: MeshInstance3D = MeshInstance3D.new()
	screen_mesh.name = "ScreenMesh"
	screen_mesh.mesh = _build_screen_mesh()
	_screen_material = StandardMaterial3D.new()
	_screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_screen_material.albedo_color = Color(0.02, 0.02, 0.03)
	_screen_material.emission_enabled = true
	_screen_material.emission = Color(0.0, 0.0, 0.0)
	_screen_material.emission_energy_multiplier = 1.2
	screen_mesh.material_override = _screen_material
	add_child(screen_mesh)

	var bezel: MeshInstance3D = _build_bezel()
	bezel.name = "Bezel"
	add_child(bezel)

	var indicator: MeshInstance3D = _build_focus_indicator()
	indicator.name = "FocusIndicator"
	add_child(indicator)

	var collision: CollisionShape3D = _build_collision_shape()
	collision.name = "ScreenCollision"
	add_child(collision)


# ---------------------------------------------------------------- wiring


## Point the screen at a live render target. Sets both albedo and emission so the panel
## reads as a lit display rather than a flat-lit surface (SPEC section 10 / task brief).
func set_viewport_texture(texture: Texture2D) -> void:
	if _screen_material == null:
		return
	_screen_material.albedo_color = Color.WHITE
	_screen_material.albedo_texture = texture
	_screen_material.emission_texture = texture


## Toggle the focus indicator. DiegeticHost calls this when the "click to focus, Escape
## to leave" state changes - see docs/DIEGETIC_HOST.md for the full focus model.
func set_focused(focused: bool) -> void:
	_focused = focused
	if _indicator_material == null:
		return
	var c: Color = INDICATOR_FOCUSED_COLOR if focused else INDICATOR_UNFOCUSED_COLOR
	_indicator_material.albedo_color = c
	_indicator_material.emission = c
	_indicator_material.emission_energy_multiplier = (
		INDICATOR_FOCUSED_ENERGY if focused else INDICATOR_UNFOCUSED_ENERGY
	)


func is_focused() -> bool:
	return _focused


# ---------------------------------------------------------------- uv / pixel conversion


## World-space hit point (e.g. `intersect_ray()`'s "position") -> local UV in [0, 1].
## See the class docstring for the convention this relies on.
func get_uv_at(world_point: Vector3) -> Vector2:
	var local_point: Vector3 = global_transform.affine_inverse() * world_point
	var half_width: float = width_m * 0.5
	var half_height: float = height_m * 0.5
	var u: float = (local_point.x + half_width) / width_m
	var v: float = (half_height - local_point.y) / height_m
	return Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))


## UV in [0, 1] -> pixel coordinates in `viewport_size`. No flip - see the class docstring.
func uv_to_pixel(uv: Vector2) -> Vector2:
	return Vector2(uv.x * float(viewport_size.x), uv.y * float(viewport_size.y))


# ---------------------------------------------------------------- mesh / collider


## Hand-built quad, not QuadMesh - see the class docstring for why. Two triangles, each
## traced counter-clockwise as seen from local +Z (verified by hand with the shoelace
## formula), so the front face is visible under Godot's default `CULL_BACK`.
func _build_screen_mesh() -> ArrayMesh:
	var half_width: float = width_m * 0.5
	var half_height: float = height_m * 0.5
	var top_left: Vector3 = Vector3(-half_width, half_height, 0.0)
	var top_right: Vector3 = Vector3(half_width, half_height, 0.0)
	var bottom_left: Vector3 = Vector3(-half_width, -half_height, 0.0)
	var bottom_right: Vector3 = Vector3(half_width, -half_height, 0.0)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0.0, 0.0, 1.0))

	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(top_left)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(bottom_left)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(top_right)

	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(top_right)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(bottom_left)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(bottom_right)

	st.index()
	return st.commit()


## Thin box, front face flush with the screen quad's z = 0 plane, so a ray from the
## viewing side lands almost exactly on the plane `get_uv_at()` assumes.
func _build_collision_shape() -> CollisionShape3D:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(width_m, height_m, COLLIDER_THICKNESS_M)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 0.0, -COLLIDER_THICKNESS_M * 0.5)
	return collision


## A slightly larger, slightly recessed plate behind the screen so it reads as a device
## panel rather than a floating rectangle. Cheap on purpose - see the task brief.
func _build_bezel() -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(
		width_m + bezel_margin_m * 2.0, height_m + bezel_margin_m * 2.0, bezel_depth_m
	)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = BEZEL_COLOR
	mesh.material = mat
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, 0.0, -(bezel_depth_m * 0.5) - 0.005)
	return mesh_instance


## A thin bar along the bottom edge of the bezel. `set_focused()` swaps its colour and
## emission - the visual half of the focus state (docs/DIEGETIC_HOST.md).
func _build_focus_indicator() -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width_m * 0.6, 0.015, 0.01)
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator_material.albedo_color = INDICATOR_UNFOCUSED_COLOR
	_indicator_material.emission_enabled = true
	_indicator_material.emission = INDICATOR_UNFOCUSED_COLOR
	_indicator_material.emission_energy_multiplier = INDICATOR_UNFOCUSED_ENERGY
	mesh.material = _indicator_material
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, -(height_m * 0.5) - (bezel_margin_m * 0.5), 0.02)
	return mesh_instance

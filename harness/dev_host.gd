class_name DevHost
extends SubViewportContainer

## Standalone development host for the builder (SPEC section 10, the two-harness rule).
##
## THE HOST OWNS THE RESOLUTION, NOT THE BUILDER. The builder must render into a fixed-size
## texture for the diegetic device in MHZ_Origins, and this used to be read as "the builder is
## 1280x800 forever", with `AppViewport.size` hard-pinned in dev_host.tscn. That made the desktop
## window unmaximisable in any useful sense: the OS window grew, the viewport did not, and the
## whole console was upscaled from a small texture.
##
## The contract that actually matters is narrower: the builder may not read `DisplayServer`, the
## OS window, or a global mouse position — it lays out from its OWN rect, whatever that is. So the
## host picks the size. Here that is "match the window". On the device it will be a fixed
## 1280x800. Neither the builder nor any panel changes.
##
## DEVICE PREVIEW (F11) locks the viewport back to the device resolution and letterboxes it, so
## the diegetic look can be checked without launching the 3D host. That is the mode to use when
## judging whether text is legible through the palette quantizer at the real device size — at a
## maximised desktop resolution everything is comfortably larger than it will be in game.

## The diegetic device's fixed resolution. Device preview locks to exactly this.
const DEVICE_SIZE: Vector2i = Vector2i(1280, 800)

## Below this the panels have nowhere to go and the layout collapses. The viewport stops
## shrinking here even if the window does; the container then crops rather than squashing.
const MIN_SIZE: Vector2i = Vector2i(1024, 640)

## Start in device preview to match the in-game look, or fill the window.
@export var device_preview: bool = false

var _viewport: SubViewport = null
## Guards the resize feedback loop: setting the viewport size changes this container's minimum
## size, which can re-emit `resized`. Without this the two chase each other for a few frames.
var _syncing: bool = false


func _ready() -> void:
	_viewport = get_node_or_null("AppViewport") as SubViewport
	if _viewport == null:
		push_error("DevHost: no AppViewport child - check harness/dev_host.tscn")
		return
	resized.connect(_sync_viewport)
	_sync_viewport()


func _sync_viewport() -> void:
	if _viewport == null or _syncing:
		return
	_syncing = true

	var want: Vector2i
	if device_preview:
		# Scale the device-sized texture to fill the container. `stretch` is what upscales it,
		# and the nearest filter on this node is what keeps the upscale blocky rather than soft.
		stretch = true
		want = DEVICE_SIZE
	else:
		# 1:1. The builder gets the real window resolution and lays out into it, so text renders
		# at native size instead of being magnified from a smaller buffer.
		stretch = true
		want = Vector2i(maxi(int(size.x), MIN_SIZE.x), maxi(int(size.y), MIN_SIZE.y))

	if _viewport.size != want:
		_viewport.size = want
	_syncing = false


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F11:
		device_preview = not device_preview
		_sync_viewport()
		get_viewport().set_input_as_handled()


## True while the host is emulating the diegetic device's fixed resolution.
func is_device_preview() -> bool:
	return device_preview

class_name ShipViewEnv
extends RefCounted
## THE 3D VIEW'S ENVIRONMENT - background, ambient, tonemap, and CLAY's ambient occlusion.
##
## PURE AND STATIC: four colours, a render mode and a flying flag in, one [Environment] out. It
## touches no node and reaches back into `ship_view3d.gd` for nothing, which is what makes it an
## extraction rather than a file split (`.gdlintrc`: "a self-contained, statically testable unit
## with no reference back to the file it came from"). It came out when that file passed the
## two-thousand-line alarm for the second time, and the alarm was right both times: lighting setup
## is not what a view class is about.

## CLAY's ambient. It LIFTS the unlit side enough to read - clay is an inspection view and there
## must be no side of the ship you simply cannot see - and no further, because everything past 1.0
## is clipped by the palette quantizer into one flat colour and the shading is lost with it.
##
## MEASURED, and the first guess was wrong by a factor of three. At 1.25 with the bright `accent`
## colour, every face of every part on a baked carbon class exceeded 1.0, the quantizer rounded them
## all onto the top palette entry, and the ship came out as a flat white blob - top, front and side
## identical, the linking tunnels merged into the pods so completely they read as missing. That is
## exactly what the author reported: "it looses the fine surgace shading that helps the player
## identify the mesh and surface". Clay needs HEADROOM on both sides.
const CLAY_AMBIENT_ENERGY: float = 0.45

## CLAY's ambient occlusion - the half of a clay view a material alone cannot give. A flat matte
## surface under even light is a silhouette with nothing inside it; occlusion in the creases is what
## makes a hull read as panels and rooms rather than as one shape. Every clay render in every
## package does this, and it is why they are legible.
const CLAY_SSAO_RADIUS: float = 0.75
const CLAY_SSAO_INTENSITY: float = 5.0

## How much the occlusion darkens DIRECT light rather than only ambient.
##
## NOT OPTIONAL HERE. Godot's SSAO modulates ambient by default, and while flying the ambient is
## ZERO - so at the stock 0.0 the occlusion would do nothing at all exactly where it is needed most,
## on a surface lit only by the flashlight. This is what puts crease shading inside the beam.
const CLAY_SSAO_LIGHT_AFFECT: float = 0.45

## Ambient for every other mode.
const BASE_AMBIENT_ENERGY: float = 0.75


## [param background] and [param ambient] are the palette's own role colours; [param clay_ambient]
## is the dimmer colour CLAY uses instead. [param clay] selects the clay view, [param void_dark]
## the deep void fly mode flies in.
static func build(
	background: Color, ambient: Color, clay_ambient: Color, clay: bool, void_dark: bool
) -> Environment:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Ambient is a MULTIPLIER on albedo, so a dark ambient colour and a dark albedo compound: two
	# mid-dark teals multiply to something the 16-entry quantizer rounds to background. Ambient
	# therefore sits high on the ramp and the albedo carries the hue.
	env.ambient_light_color = ambient
	env.ambient_light_energy = BASE_AMBIENT_ENERGY
	if clay:
		env.ambient_light_color = clay_ambient
		env.ambient_light_energy = CLAY_AMBIENT_ENERGY
		env.ssao_enabled = true
		env.ssao_radius = CLAY_SSAO_RADIUS
		env.ssao_intensity = CLAY_SSAO_INTENSITY
		# Sharp: a soft wide occlusion reads as dirt, a tight one reads as a crease, and the crease
		# is the cue that tells a player where one part ends and the next begins.
		env.ssao_detail = 1.0
		env.ssao_power = 2.0
		env.ssao_light_affect = CLAY_SSAO_LIGHT_AFFECT
	# THE VOID IS APPLIED LAST so nothing above can put the lights back on. This function is also how
	# a palette change rebuilds the environment, and CLAY swaps the palette on the way INTO fly -
	# without this ordering the void was switched on by ShipFlyMode and switched straight back off
	# one signal later, which looks exactly like the feature not working.
	if void_dark:
		env.ambient_light_energy = 0.0
	# Linear tonemap: anything filmic would re-map the ramp before the palette quantizer ever sees
	# it, and the palette is meant to be the only colour authority.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return env

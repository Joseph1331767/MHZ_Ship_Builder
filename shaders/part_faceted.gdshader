shader_type spatial;
render_mode unshaded, cull_disabled, specular_disabled;

// Banded self-shading for hull parts, quantized to the console palette BY CONSTRUCTION.
//
// WHY THIS EXISTS INSTEAD OF A LIGHT.
// StandardMaterial3D with SHADING_MODE_PER_PIXEL renders BLACK in this project's 3D SubViewport
// (docs/FOLLOWUPS.md F7). Everything checked out - mesh, normals, visibility, world, camera aim,
// framing, a DirectionalLight3D with energy 1.15 and an ambient-colour Environment - and the part
// still came out black. `unshaded` means no light is consulted; the lambert term is computed here
// against a fixed WORLD-space direction, so the shading stays put as the camera orbits instead of
// sliding around with the view.
//
// WHY IT PICKS A RAMP ENTRY INSTEAD OF MULTIPLYING AN ALBEDO.
// The whole console is quantized to a 16-entry LUT downstream (shaders/palette_post.gdshader).
// The first version of this shader multiplied one albedo by a lambert scalar and let the
// quantizer sort out the result. Measured, the two shaded bands of a selected amber part came out
// #9f752d and #ba8936, and the quantizer mapped one onto the WARNING RED and the other onto the
// BACKGROUND - so a cube rendered as one lit face floating in space with no sides at all, which is
// exactly what the author reported seeing. Feeding an explicit ramp of LUT colours makes every
// band an exact palette entry, so the quantizer is a no-op on parts and the shading is whatever
// data/palette.json's "ramps" says it is. Do not go back to multiplying.
//
// THIS SHADER IS OPAQUE AND MUST STAY OPAQUE - see the ALPHA note in fragment().
//
// TWO CUES, NOT ONE. Lambert alone leaves two parts at different depths reading identically when
// their faces happen to share an orientation. The distance term darkens whatever is further from
// the camera, which is the ask this shader was rebuilt for: near reads light, far reads dark.

// The shading bands, darkest first. Uploaded from ShipTheme.ramp_for(), so an alert LUT swap
// recolours parts along with the rest of the console.
//
// UPLOADED LINEAR, NOT sRGB. A plain `vec3` uniform carries no `source_color` hint, so nothing
// converts it: the renderer takes whatever arrives as a LINEAR value and sRGB-encodes it on the
// way out. Handing it raw palette components therefore brightened every band - measured, the four
// warm bands #4d3311/#8a5f22/#bd8734/#e4a944 came out of the pipe as #957b49/#c2a466/#dfc07c/
// #f2d48d, the middle two collapsed onto the SAME quantizer entry, and the brightest landed on
// #daf1e0 (pale mint) so the top face of a box wore a mint triangle. ShipSceneBuilder._apply_ramp
// converts with Color.srgb_to_linear() before uploading; do not "simplify" that away.
uniform vec3 ramp[8];
uniform int ramp_size : hint_range(2, 8) = 4;

// World-space direction the light travels. Default is over the viewer's left shoulder and down,
// the convention that makes a box read as a box.
uniform vec3 light_dir = vec3(-0.45, -0.80, -0.40);

// Where an unlit face sits along the ramp, 0 = darkest band. Not 0 in practice: a face pointing
// away from the light still has to be a visible silhouette against the background.
uniform float ambient : hint_range(0.0, 1.0) = 0.28;

// How far along the ramp the distance cue can pull a fragment, and the near/far distances it
// spans. ShipView3D rewrites near/far from the orbit camera so the full ramp is always in play
// whatever the zoom; with near == far the term is skipped.
uniform float depth_strength : hint_range(0.0, 1.0) = 0.34;
uniform float depth_near = 0.0;
uniform float depth_far = 0.0;

// THIRD CUE: FRESNEL. The author asked for it by (approximately) name - "i really want a frenzal
// node ... godot has it" - and it is the cue the other two cannot give: lambert and depth both
// vary slowly across a face, so where two parts meet at similar angles and similar depths the
// silhouette between them is a single band with no edge. A Fresnel term is large exactly at
// grazing angles, i.e. along every silhouette, so it draws the rim of each part in the ramp's
// TOP band. Pushed INTO t rather than added as a colour, so the rim is still one of the ramp's
// palette entries and the quantizer stays a no-op on parts (see the ramp note above): on a
// plain part the rim is pale mint, on the selected part it is the amber the warm ramp ends in.
// `rim_power` sets how tight to the edge the band sits; `rim_strength` 0 turns it off.
uniform float rim_strength : hint_range(0.0, 1.0) = 0.55;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;

// How much of the lambert term survives. 1 is the shaded read every mode but one uses; 0 drops
// the body to `ambient` and leaves the rim as the only thing lit, which is what makes
// DisplayMode.FRESNEL a distinct RENDER TYPE rather than a shaded part with a brighter edge.
// Measured before this existed: turning `ambient` down alone changed 2% of the viewport, because
// a lit face still climbed to the top band on lambert alone and the rim had nowhere left to go.
uniform float lambert_strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// NORMAL is view-space in fragment(); INV_VIEW_MATRIX takes it back to world so the lighting
	// is anchored to the ship rather than to the camera.
	// cull_disabled + FRONT_FACING instead of cull_back: a mirrored twin has a
	// negative-determinant basis, which reverses winding. Culling the back face would render the
	// twin inside-out; flipping the normal on back faces keeps both hands shading correctly with
	// one material instead of two.
	vec3 view_n = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(view_n, 0.0)).xyz);
	float lambert = max(dot(world_n, normalize(-light_dir)), 0.0);

	float t = ambient + (1.0 - ambient) * lambert * lambert_strength;

	// Distance cue, measured PER PART rather than per fragment. MODEL_MATRIX's translation column
	// is the part's own origin; pushing it through VIEW_MATRIX puts it in view space, where the
	// origin is the camera, so its length is the part's distance.
	//
	// Per fragment this looked wrong: `t` then varies across a single flat face, and where it
	// crosses a band boundary the face picks up a curved iso-distance contour - a cube came out
	// looking bowed. Shifting the whole part by one band keeps faces flat while still reading
	// near-light / far-dark across an assembly, which is what the cue is for.
	float span = depth_far - depth_near;
	if (span > 0.0001) {
		float part_dist = length((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
		// CENTRED on the middle of the range: a part at mid-depth is not shifted at all, nearer
		// parts brighten and farther ones darken. Subtracting the raw 0..1 fraction instead cost
		// a lone centred part a permanent half-strength penalty, so its lit face could never
		// reach the top band and every single-part ship rendered a band darker than intended.
		float far_ness = clamp((part_dist - depth_near) / span, 0.0, 1.0) - 0.5;
		t -= depth_strength * far_ness;
	}

	// The Fresnel rim (see the uniforms). VIEW is the view-space direction from the fragment to
	// the camera; view_n is already flipped for back faces, so a mirrored twin gets its rim on
	// the same edges as its source.
	if (rim_strength > 0.0) {
		float facing = clamp(dot(normalize(view_n), normalize(VIEW)), 0.0, 1.0);
		float fres = pow(1.0 - facing, rim_power);
		t = mix(t, 1.0, rim_strength * fres);
	}

	int last = max(ramp_size - 1, 0);
	int idx = clamp(int(floor(clamp(t, 0.0, 1.0) * float(ramp_size))), 0, last);
	ALBEDO = ramp[idx];
	// DO NOT WRITE ALPHA HERE. Any write to ALPHA - even a constant 1.0 - moves the material onto
	// Godot's transparent pipeline, which stops writing depth. The first ramp build did exactly
	// that and the cube rendered as a hollow shell: interior walls, the far side of the box and
	// the orbit rings all showed straight through the front faces. The placement ghost gets its
	// translucency from its own StandardMaterial3D (ShipSceneBuilder._ghost_material), so nothing
	// needs this shader to be transparent.
}

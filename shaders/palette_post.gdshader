// palette_post.gdshader - SPEC section 11.
//
// ONE palette-quantization post process over the WHOLE app SubViewport. It sits on a
// full-rect ColorRect inside a CanvasLayer at layer 100, so everything drawn beneath it
// in that viewport - the 3D panel and every UI panel alike - is remapped to the same
// 16 colours. That is why the 3D view and the UI share a colour language by construction
// instead of being matched by hand, and why a budget alert is one uniform write
// (ShipTheme.set_alert) rather than a UI refactor.
//
// Colour space: Godot's 2D pipeline is non-linear (sRGB) unless HDR 2D is enabled, and
// the 3D SubViewport's texture has already been tonemapped to sRGB by the time this
// canvas shader samples it. So palette entries are uploaded as raw sRGB components
// (Color.r/g/b straight from the pack) and compared in that same space. Do not
// srgb_to_linear() them on the GDScript side or the ramp will crush.

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

// The LUT. Index position is load-bearing - it is the index data/palette.json's
// "roles" map points at. palette_size lets a shorter pack work without a recompile.
uniform vec3 palette[16];
uniform int palette_size = 16;

// Optional 4x4 Bayer ordered dither. The threshold is added to the sampled colour
// BEFORE the nearest-entry search, which is what produces era-correct banding rather
// than a soft blend: neighbouring pixels tip to different palette entries.
// DEFAULT OFF. Ordered dithering and small text are incompatible under a 16-entry
// quantizer: a 10-12 px glyph whose colour falls between two palette entries gets its
// stroke scattered across the Bayer pattern, and the letterform stops being a letterform.
// The first windowed render of this builder came out as isolated dots where every label
// should have been -- see reports/crop_inspector.png and the devlog for 2026-08-31.
// Turn it on (ShipTheme.set_dither) for a 3D-only or large-type view, not for the console.
uniform bool dither_enabled = false;
uniform float dither_strength : hint_range(0.0, 0.5) = 0.06;

// Dev bypass. Uniform branch - coherent across the whole draw, so effectively free.
uniform bool enabled = true;

// DEBUG ONLY: replace the top 32px strip with the raw uploaded LUT, 64px per entry.
uniform bool debug_lut = false;

// Luma weights. The nearest-entry search runs in this weighted space rather than raw
// RGB: on a blue-green ramp raw RGB distance picks visibly wrong entries because it
// treats a shift in blue as costing the same as a shift in green, which the eye does
// not. Weighting green most makes "nearest" mean "nearest in apparent brightness first".
const vec3 LUMA_W = vec3(0.299, 0.587, 0.114);

// 2x2 Bayer in closed form: M2[y][x] = mod(2x + 3y, 4) reproduces [[0,2],[3,1]].
float bayer2(vec2 p) {
	return mod(2.0 * p.x + 3.0 * p.y, 4.0);
}

// 4x4 Bayer by the standard recursion M4 = 4*M2(low bits) + M2(high bits).
// Computed rather than table-looked-up so there is no const array and no indexing.
float bayer4(vec2 pix) {
	vec2 q = mod(floor(pix), 4.0);
	float lo = bayer2(mod(q, 2.0));
	float hi = bayer2(floor(q * 0.5));
	return (4.0 * lo + hi) * (1.0 / 16.0);
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;

	if (!enabled || palette_size < 1) {
		COLOR = vec4(src, 1.0);
	} else {
		// Bias by the ordered-dither threshold, centred so it does not shift overall
		// brightness. float(bool) avoids a second branch.
		vec3 c = src + (bayer4(FRAGCOORD.xy) - 0.5) * dither_strength * float(dither_enabled);

		// DEBUG: paint the uploaded LUT itself across the top strip, so the array that actually
		// reached the GPU can be read off the framebuffer instead of inferred.
		if (debug_lut && FRAGCOORD.y < 32.0) {
			int di = int(FRAGCOORD.x / 64.0);
			COLOR = vec4(palette[clamp(di, 0, 15)], 1.0);
		} else {

		vec3 best_c = palette[0];
		float best_d = 1.0e9;
		for (int i = 0; i < 16; i++) {
			if (i >= palette_size) { break; }
			vec3 dv = (palette[i] - c) * LUMA_W;
			float d = dot(dv, dv);
			if (d < best_d) { best_d = d; best_c = palette[i]; }
		}
		COLOR = vec4(best_c, 1.0);
		}
	}
}

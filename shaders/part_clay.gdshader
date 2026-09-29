shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// THE CLAY VIEW - the flat, evenly-lit, uniform-material read every 3D modelling package has.
//
// The author, 2026-09-28: "are you familiar with 3d modeling software clay views? its a flat,
// shadow view, sometimes shows framing.. thats what we are after."
//
// So this is Blender's clay/solid render, ZBrush's matcap clay, Maya's ambient-occlusion pass: ONE
// matte material on every part so nothing distracts from FORM, real lighting so the surface reads,
// ambient occlusion in the environment so creases and cavities read, and the wireframe overlay on
// top as the "framing".
//
// IT IS LIT - genuinely, by the engine. `part_faceted.gdshader` is `unshaded` and computes a fake
// lambert against a fixed direction; that is a deliberate STYLE for the other modes (every band
// lands on an exact palette entry, so the 16-colour quantizer is a no-op on parts). Clay wants the
// opposite: a smooth continuous gradient that shows every curve, which is what the author means by
// "the fine surface shading that helps the player identify the mesh and surface".
//
// WHY THIS IS NOT JUST A StandardMaterial3D, and this is the whole reason the file exists:
//
// **BACK FACES NEED THEIR NORMAL FLIPPED.** A `StandardMaterial3D` with `cull_mode = DISABLED`
// shades a back face with the normal it was authored with - pointing AWAY from the camera and away
// from every light - so it renders BLACK. The author found it immediately: "the linking tunnels are
// pitch black regardless of lighting". Of course they were: looking down a tunnel is looking at the
// INSIDE of a shell, which is entirely back faces. Every hollow room, every bore, every tunnel in
// this builder is back faces from the inside.
//
// `part_faceted.gdshader` has always done this flip and says why ("a mirrored twin has a
// negative-determinant basis, which reverses winding"); swapping it for a StandardMaterial3D threw
// that away. Godot has no back-face normal flip on the standard material, so the flip has to live
// in a shader, and that is all this file really is.

// The one colour every part wears. Uniform BY DESIGN: a clay view that tinted parts differently
// would be a material view, which is the thing it exists not to be.
uniform vec3 clay_color : source_color = vec3(0.52, 0.62, 0.75);

// Clay is matte. A specular highlight reads as wet plastic, which is what DisplayMode.FRESNEL is
// for. Kept as uniforms rather than baked in so the look is tunable from one place.
uniform float clay_roughness : hint_range(0.0, 1.0) = 0.92;
uniform float clay_specular : hint_range(0.0, 1.0) = 0.08;

// A touch of rim light so a silhouette separates from the background even where nothing is behind
// it to contrast against. Far weaker than FRESNEL's - this is legibility, not a style.
uniform float clay_rim : hint_range(0.0, 1.0) = 0.10;

void fragment() {
	// THE FLIP, and the reason this shader exists. NORMAL is view-space and writable here, so a
	// back face is shaded as though it faced the viewer - which is what you want when the viewer is
	// standing INSIDE the shell looking at it.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = clay_color;
	ROUGHNESS = clay_roughness;
	SPECULAR = clay_specular;
	METALLIC = 0.0;

	if (clay_rim > 0.0) {
		float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		// Lifts only the grazing edge, and lifts the ALBEDO rather than adding emission, so the
		// rim is still lit by the same lights as the rest and goes dark when the part does.
		ALBEDO = mix(ALBEDO, ALBEDO * 1.6, clay_rim * pow(1.0 - facing, 3.0));
	}
}

# 0050 - CLAY renders outside the quantizer

- **Date**: 2026-09-29
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - measured `79445dff48f81978` either side. A render type reads the
  document and stores nothing in it.
- **Deviates from**: `docs/SHIP_BUILDER_SPEC.md` section 11 - one palette over the whole app viewport
- **Builds on**: ADR 0049 (the clone target does not govern the camera)

## Context

SPEC section 11 puts ONE palette-quantization pass over the entire app `SubViewport`: a full-rect
`ColorRect` on a `CanvasLayer` at layer 100, so the 3D panel and every UI panel are remapped to the
same sixteen colours. That is a genuinely good rule and it is why the 3D view and the console share a
colour language by construction rather than by hand-matching, and why a budget alert is one uniform
write instead of a UI refactor.

`part_faceted.gdshader` is built to live inside it: every band it emits is an exact palette entry, so
the quantizer is a **no-op on parts**. That is the design, and it stays.

**CLAY is the one render type that wants the opposite.** ADR 0049 made it a genuinely lit
`StandardMaterial3D`-class surface with a real `SpotLight3D`, real shadows and a real inverse-square
falloff, because the author asked for a modelling-package clay view and a flashlight. A continuous
light gradient is precisely what a sixteen-entry nearest-colour search cannot represent: it comes out
as concentric bands. The author, 2026-09-29:

> "can we get rid of the styalized shadows in the clay flying mode.. i want real shadows, real soft
> gradiants. not these moray bands of color that i see."

**Dither was tried first and is not a fix.** Raising the ordered dither from 0.06 to 0.22 trades the
bands for noise; it cannot invent colours the LUT does not contain. It also actively harms the UI,
where ordered dithering scatters small glyphs - a failure this project already hit once and recorded
(`palette_post.gdshader`, the first windowed render, 2026-08-31).

There were only ever two honest options: give CLAY its **own banded ramp** so the light is quantized
on purpose like every other mode, or take CLAY **out of the quantizer**. Fighting the quantizer with
noise from inside it was the one position that satisfied neither goal.

## Decision

**In CLAY, and only in CLAY, the 3D panel is exempt from the palette quantizer. The console around it
is not.**

- `palette_post.gdshader` gains a `bypass_rect` uniform, in `FRAGCOORD` pixels. A fragment inside it
  is passed through untouched. Zero width or height - the default, and every mode but one - means the
  whole viewport is quantized exactly as before.
- `ShipTheme.set_bypass_rect(Rect2)` pushes it; `ShipFlyToolbar.wear_clay` sets it to the 3D view's
  own rect while CLAY is up and clears it otherwise.
- The dither goes back to its shipped `DITHER_DEFAULT`. It was raised only to fight the banding this
  removes properly.
- The key light **casts shadows in CLAY** (`shadow_enabled`, soft `shadow_blur`). It never has,
  on the stated grounds that "at 16 colours a shadow is a hard-edged blotch, not information" - which
  was true of a quantized panel and is not true of this one. The torch gains a `light_size` so its
  penumbra is soft rather than stencilled.

**The rectangle is a Control rect inside the app viewport, never a window size.** This does not touch
the render-to-texture CONTRACT (AGENTS section 7): nothing reads `DisplayServer`, and the same code
works when the builder is a texture on a diegetic quad.

## Consequences

**Easier.** CLAY becomes what a clay view is for: real shadows, smooth falloff, and surface shading
fine enough to read form. Ambient occlusion, which was already on, now actually shows instead of
being rounded away. The flashlight reads as a light rather than as a set of rings.

**Harder.** There are now two colour regimes on one screen, and a reviewer has to know which they are
looking at. The seam is a hard rectangle edge - the 3D panel's border - which is visually clean
precisely because the panel already has a frame there, but it IS a seam and it did not exist before.

**Constrained.**

- **The exemption is per render type and per rectangle, not a switch.** Any future mode that wants it
  must say so here. The default stays "everything is quantized".
- **CLAY is now the only mode whose appearance is not fully determined by the LUT.** A palette change
  recolours it only through the material's albedo, not through the post pass - so `data/palette.json`
  no longer fully describes what CLAY looks like, and the clay variant's blues matter as *albedo*
  rather than as quantizer targets.
- **It does not solve the tension, it scopes it.** The 16-colour art direction and engine lighting
  genuinely disagree; this decision says CLAY is the place where lighting wins and everywhere else
  the palette does. If a second mode ever wants real lighting, the right answer is probably the other
  option - a banded ramp indexed by lit luminance - rather than a second exemption.

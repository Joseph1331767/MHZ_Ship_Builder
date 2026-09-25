# Future phases — design notes

Ideas for phases that are **not built yet**, written down when they come up so they are not lost
and so the phases before them do not accidentally preclude them.

These files are **not CONTRACT** and nothing in `core/`, `data/` or `harness/` reads them. They are
the author's intent plus what it asks of earlier phases. When a phase starts, its decisions move
into `docs/SHIP_BUILDER_SPEC.md` and an ADR, and the note is marked in place with
`RETIRED(<ADR>): ...` per AGENTS §10a — never deleted.

The phase order comes from the Phase One Hull Review (2026-09-06): hull creation → hull section
assignment → interior equipment → exterior equipment → windows and hatches → procedural texturing.

| file | phase | contents |
|---|---|---|
| [texturing.md](texturing.md) | procedural texturing | seam bands (rivets, bolts, welds, hidden fastener ribbons) and panels textured in their primitive's own coordinates |
| [symmetry.md](symmetry.md) | hull creation (now) and later | mirror on any combination of X/Y/Z; radial, point and repeat symmetry later |
| [printing.md](printing.md) | manufacturing | the fundamental cut grid IS the smallest printer's build volume, strided for larger ones so no re-slicing ever happens |
| [walls.md](walls.md) | hull creation (next) | the three wall modes between two chunks - A keeps its surface, B keeps its surface, or a flat wall between them - with the hatch layered over whichever is chosen |

One file per phase or topic. Quote the author where the idea came from them.

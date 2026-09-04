# 0013 — A seam is two axes, not six names

- **Date**: 2026-09-04
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. `seam_style` is still written only when it is not the default, and the default still
  carries the same behaviour, so no saved document's canonical form moves.
- **Amends**: ADR 0012's six style ids and ADR 0009's `parent` / `child`, both retired in place.
- **Records**: FOLLOWUPS F25

## Context

After a round of testing:

> "i see a structure where instead of saying child-indents-parent, or parent-indents-child, i think
> its more appropriate to classify it as big indents small, or small indents big. then to append on
> the toggles with that of flat inserted, flat cutoff, or native inserted. for the linkage surface..
> what im describing changes nothing but the naming and input scheme."

The six styles had accumulated from two ADRs and named the same kind of thing in two unrelated
ways. `parent` and `child` named theirs by the **attach tree**; `flat_in`, `flat_out`, `slice_in`
and `slice_out` named theirs by a **plane position** and a **cut extent**. Nothing tied them
together, and a player reading the menu had no way to see that they were six cells of one grid.

## Decision

**A seam style is two independent choices, and the id spells both.**

| | `flat_insert` | `flat_cutoff` | `native` |
|---|---|---|---|
| **`small`** indents big | `small_flat_insert` | `small_flat_cutoff` | `small_native` |
| **`big`** indents small | `big_flat_insert` | `big_flat_cutoff` | `big_native` |

- **Which solid indents the other**, by VOLUME. A small part is perfectly able to be the parent of
  a large one, and which presses into which is a fact about the shapes rather than about which was
  placed first.
- **What the linkage surface is.** `flat_insert` lets only the indenting solid's own cross-section
  in; `flat_cutoff` takes the same plane straight through; `native` does not flatten at all and the
  interface follows the indenting solid's real surface, which fits any shape exactly.

`ShipJoint.indent_of()`, `surface_of()` and `style_for_axes()` read the axes off an id and rebuild
one from them, which is what lets the menu offer two toggles over a single stored value. The menu
is grouped under two headings rather than being a flat list of six, and `ShipContextMenu` learned
to render a `header` entry.

**Every id this project has ever written still loads** — `flat`, `flat_in`, `flat_out`, `slice_in`,
`slice_out`, `parent`, `child` — through `LEGACY_SEAM_STYLES`. The names have changed twice and the
behaviours never have; a saved document is not the place to make a reader pay for that.

## Consequences

**Six behaviours in, six behaviours out.** Measured on `helium`, every part closed:
`small_flat_insert` 70 faces, `small_flat_cutoff` 70, `big_flat_insert` 176, `big_flat_cutoff` 176,
`big_native` 70, `small_native` 1417.

**One thing does change, and it is the point of the rename rather than an accident.** `parent` and
`child` decided who lost material from the ATTACH TREE; `big` and `small` decide it from VOLUME.
Where the tree parent is the larger solid — which is most joints — the two agree exactly. Where it
is not, they differ, and the new answer is the better one. Measured on `helium`, whose tunnel is
the tree parent of a room ten times its volume: under the old `parent` the *room* was dented by the
tunnel, and under `big_native` the tunnel is dented by the room. A hab module should not be
hollowed out by the corridor bolted to it because the corridor happened to be placed first.

**The author's own reading of the overlap is worth keeping.** `small_flat_insert` and `small_native`
reach the same shape on a flat host by different routes, and that redundancy is deliberate: it
"lets people quickly switch linkage manifolds without changing base shapes".

**A runtime error the banner would have hidden.** `_seam_style_label()` walked the menu items
reading `item["id"]`, which a heading row does not have. The windowed check printed PASSED and
exited 1, and it was only caught because `tools/ship_run.ps1` fails a run on any runtime error
whatever the exit code says — AGENTS §8a, working exactly as written. It was nearly missed a second
time by a `Select-String` filter that kept the banner and dropped the error report; filtering a
verification's output is how a green result gets manufactured.

**The SDF still knows only its own three codes.** `ShipSdf.style_code()` maps the natives onto its
`STYLE_PARENT` / `STYLE_CHILD` and everything else onto its flat, so `module_view` sees the ADR 0009
model. Nothing renders from that path now, so the divergence stays cosmetic — and recorded.

# Changelog

## v0.1.2 (2026-10-05)

`Mesher`: faster `tri()` and `box()` (the eight corners are computed once; ported from the football game's venue builder) - the output is
bit-identical to v0.1.1 (`core/tools/test_mesher.gd` compares 69,500 triangles exactly; ~1.5x faster boxes), plus `uvquad()` (textured quad).
Docs: ADOPT.md - a game class named like a core class (`Mesher`) fails to compile in Godot 4.7 ("hides a global script class"): delete or
rename it (the v0.1.1 note "you may keep your inner Mesher" was wrong).

## v0.1.1 (2026-10-05)

Fix: `Fonts.DIR` pointed at `res://core/core/assets/fonts/` in v0.1.0 (the fonts did not load). Added the generated `.uid` / `.import` files so
resource UIDs are identical in every game.

## v0.1.0 (2026-10-05) - first slice, adopted by volleyball

New: `Fonts`, `Callout` (+ shader, star texture), `Mesher` (extracted verbatim from `CourtDeco.Mesher`), `Confetti`, `AlertMark`,
`AngerMark` (now uses `Mesher`), `DizzyStars` (takes any `Node3D` with `.rig.head_world()` instead of the volleyball `Athlete`).
All resource paths are `res://core/...`.

# Changelog

## v0.1.1 (2026-10-05)

Fix: `Fonts.DIR` pointed at `res://core/core/assets/fonts/` in v0.1.0 (the fonts did not load). Added the generated `.uid` / `.import` files so
resource UIDs are identical in every game.

## v0.1.0 (2026-10-05) - first slice, adopted by volleyball

New: `Fonts`, `Callout` (+ shader, star texture), `Mesher` (extracted verbatim from `CourtDeco.Mesher`), `Confetti`, `AlertMark`,
`AngerMark` (now uses `Mesher`), `DizzyStars` (takes any `Node3D` with `.rig.head_world()` instead of the volleyball `Athlete`).
All resource paths are `res://core/...`.

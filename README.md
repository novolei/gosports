# gosports-core

The shared core of the **GoSports** family (volleyball, table tennis, football, ...): sport-agnostic modules that every game
consumes **as a versioned dependency instead of copy-forking them**.

* design, rules and roadmap: [`docs/CORE.md`](docs/CORE.md)
* how a game adopts / updates / contributes back: [`docs/ADOPT.md`](docs/ADOPT.md)
* what changed: [`CHANGELOG.md`](CHANGELOG.md) · current version: [`VERSION`](VERSION)

Each game keeps this repo at `core/` (git subtree), so all resource paths here start with `res://core/`.
Godot resolves everything by `class_name`, so game code just says `Fonts`, `Callout`, `Mesher`, `AlertMark` ...

## v0.1.x contents

| module | path | notes |
|---|---|---|
| `Fonts` | `scripts/core/fonts.gd` + `assets/fonts/*.ttf` | zh upright WenDaoChaoHei + Noto fallback, Latin Rubik / Kanit |
| `Callout` | `scripts/ui/callout.gd` + `shaders/ui_text_fancy.gdshader` + `assets/gfx/star.png` | the elastic "flying text" |
| `Mesher` | `scripts/gfx/mesher.gd` + `tools/test_mesher.gd` | procedural low-poly mesh builder (was `CourtDeco.Mesher`; fast `box()`, `uvquad()`) |
| `Confetti`, `AlertMark`, `AngerMark`, `DizzyStars` | `scripts/vfx/` | small leaf effects |

Licences: the fonts are OFL (Rubik, Kanit, Noto Sans SC) and 文道潮黑 (free, shipped unmodified; confirm the licence before a
commercial release).

# GoSports core: design

## Why

GoSports is a family of independent games (volleyball = `main`, table tennis, football, shuffleboard ...). They started as forks
of one code base. A read-only diff of the volleyball tree (56 scripts) against the table-tennis and football branches showed:
10 scripts untouched by both, **32 rewritten in both**, 8 only in table tennis, 6 only in football. Fixes and features no longer
flow between the games (a font fix, a new build script, a UI polish ... has to be ported by hand). The core is the cure:
sport-agnostic code lives **once**, here; each game consumes a tagged version.

## The games stay independent

Separate repos / branches, separate `project.godot` (name, package id, save directory), separate packaging, separate release
times. The core is a *library*: a game never has to change its rules, physics or look to use it, and a game can stay on an old
core version as long as it likes.

## Layers

```
L3  tools      build / sign / encrypt scripts, key_icon, make_fonts, test_loc, check_scripts, promo pipeline
L2  content    character rig + animation baking, roster, venue decor frameworks, VFX, replay recorder
L1  foundation fonts, loc framework, UI language (UIKit / GW / MenuEntry / Callout / Stage), Game (settings, input, touch,
               haptics, scene flow), Profile engine (XP, levels, missions, achievements, cosmetics), Sfx manager
--- core above this line ------------------------------------------------------------------------------------------------
G   game       court / table / pitch + ball physics, athlete state machine, rules director, AI, input -> actions, sport
               HUD elements, sport animations and sounds, the catalogs the shared engines are configured with
```

## Dependency rules (what makes it a core and not a second fork)

1. **The core never names a sport's class** (`Court`, `Ball`, `Athlete`, `MatchDirector`, `Table`, `Goal` ...). A core file that
   needs "something athlete-like" takes a `Node3D` and uses a documented duck-typed method (see `DizzyStars.setup`).
2. **Games use the core, never the reverse.** A game customises through hooks / composition / registries, **not by editing
   files under `core/`**. A needed change goes upstream first (see ADOPT.md).
3. **Content comes in through registries / a `SportDef`** (planned, v0.2+): `Loc.register_table(...)`, `Sfx.register_bank(...)`,
   `Profile.configure(catalog)`, `SportDef` (id, display name, package id, accent colours, modes, cosmetics catalog, mission
   pool, achievements, tips, action icons). Shared menus / results / loading cards read the `SportDef`; they contain no
   volleyball (or tennis, or football) strings.
4. **Resources are addressed under `res://core/...`** (the subtree prefix) and never reach into a game folder.
5. **A module is promoted only when** at least one game consumes it AND the sibling forks' diffs of the same file have been
   reconciled (otherwise the "core" version would silently disagree with a fork). The first slice (v0.1) is therefore the
   stable intersection.
6. Names: keep the existing `class_name`s (so forks can adopt without touching call sites). Do not add sport prefixes inside
   the core. Inside a game, a sport class with the same name as a core class is a conflict: rename the sport class.

## Versioning and distribution

* This repo is `G:\NewGDP\gosports-core` (a separate git repository); the canonical remote is
  `https://github.com/novolei/gosports-core.git` (private, `main` + the release tags). A local path or the URL both work as the subtree source. Semantic version in `VERSION`, one git tag per release
  (`v0.1.0`), `CHANGELOG.md` lists every change.
* Each game embeds it at `core/` with **git subtree** (`--squash`): files physically live in the game (Godot needs them under
  `res://`, export scripts copy the tree, many worktrees make submodules painful).
* A monorepo with `games/<sport>/` was rejected: a Godot project cannot reference files outside its own folder.

## Roadmap (promotion order, each step = one minor version)

| version | adds | needs |
|---|---|---|
| v0.1 | Fonts, Callout, Mesher, Confetti, AlertMark, AngerMark, DizzyStars (volleyball adopts) | done |
| v0.2 | `Loc` framework (+ per-domain tables like football's `loc_en_core / hud / life / menu`), `Sfx` bank registry, `Prof` | reconcile `loc.gd`, `sfx.gd` (football changed both), `loc_en.gd` (tt) |
| v0.3 | UI language: `UIKit`, `GW` (game_widgets), `MenuEntry`, `Stage`, `VsCard` | reconcile ui_kit / menu_entry / stage / vs_card (football), game_widgets (tt) |
| v0.4 | `Game` autoload split into core services + game config; `Profile` engine + `SportDef` | `game.gd`, `profile.gd` are rewritten in both forks |
| v0.5 | `CharacterRig`, `PoseSolver`, `RigInfo`, clip baking pipeline, roster | rewritten in both forks |
| v0.6 | tools: `build_windows.ps1`, `build_android.ps1`, `key_icon.py`, `make_fonts.py`, `check_scripts.gd`, `test_loc.gd`, promo pipeline | parameterise project-specific names |
| v0.7 | venue frameworks (crowd, bench crew, press crew, referee animals), `ReplaySystem`, hit VFX | rewritten in both forks |

The order follows how much the siblings diverged: the least-diverged files first.

## Inputs from the sibling games (candidates, collected 2026-10-05)

Nothing here is promoted yet; each item is evaluated when its roadmap step comes up (rule 5: diff against the other forks first).

| from | candidate | goes to |
|---|---|---|
| football | `Game._dynamic_resolution` (GPU-aware: only lowers the 3D resolution when the GPU is the bottleneck), phone debug args via `user://dev_args.txt`, `Profile._daily_valid()` (re-roll today's missions when they do not match the current pool), `Loc` extra per-domain tables | v0.2 (Loc), v0.4 (Game / Profile) |
| football | `tools/phone_perf_fb.sh` (phone probe), `tools/ai_stats.sh` (AI-vs-AI stats), `check_scripts.gd` | v0.6 tools |
| football | **character / animation pipeline - the football version is the newest of the three; v0.5 starts from it, never from the older volleyball one**: `character_rig`, `rig_info`, `pose_solver`, `soc_gait`, `mixamo_source`, `bake_anims.gd`, `check_ground.gd` (skeleton-proportion classes, ground-height correction, animation LOD, runtime Mixamo retarget, 8-direction gait) | v0.5 |
| football | venue parts: `scoreboard`, `crowd`, `venue_kit`, `spectator.gdshader` (baked MultiMesh crowd + vertex sway), `hud_widgets` (charge / energy ring, score strip) | v0.7 |
| table tennis | `build_windows.ps1` / `build_android.ps1`, `test_loc` / `test_keys` / `test_touch`, `BroadcastStinger` transition, the player foot-ring shader, `CameraRig._fit` (auto framing) | v0.6 tools, v0.3 UI, v0.7 |
| volleyball | `Callout`, `Fonts`, `Mesher`, small VFX (done, v0.1.x); next: `Prof`, `ReplaySystem`, hit VFX, the promo pipeline (`promo/`), the Minitanks-style encrypted build scripts | v0.2, v0.6, v0.7 |

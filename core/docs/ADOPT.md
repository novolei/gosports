# Adopting, updating and contributing to gosports-core

The core is embedded in a game with **git subtree**. `<core>` below is `G:/NewGDP/gosports-core` (a separate repo; `main` branch) or,
equivalently, the remote `https://github.com/novolei/gosports-core.git` - use either as the repository argument of every subtree command.

## First adoption (once per game)

```bash
cd <game repo>                                   # the worktree of the game, working tree CLEAN (commit first)
git subtree add --prefix=core G:/NewGDP/gosports-core main --squash
godot --headless --editor --quit --path .        # re-import the moved assets (writes the .import files)
```

Then for every module the core provides **delete the game's own copy** and fix call sites:

1. delete the old script / asset (it is the same `class_name`, Godot reports a duplicate otherwise);
2. update hard-coded resource paths to `res://core/...` (fonts, `star.png`, `ui_text_fancy.gdshader`);
3. **a game class must not have the same name as a core class.** In Godot 4.7 an inner class (or any script class) called `Mesher`,
   `Fonts`, `Callout` ... next to the global one fails with `Class "Mesher" hides a global script class` and the **whole file stops
   compiling** (found by the football game). So a `CourtDeco.Mesher` inner class must be deleted (replace `CourtDeco.Mesher` with
   `Mesher` everywhere; the core `Mesher` already has the fast `box()` since v0.1.2) or renamed to a sport-specific name
   (`VenueMesher`) if you really need a different builder. Before adopting, grep your project for `class Mesher`, `class Fonts`,
   `class Callout`, `class_name Confetti` ... (every `class_name` of the core README table);
4. add `core` to the compile-check tool (`tools/check_scripts.gd`) if it only scans `res://scripts`;
5. run the game's normal regression (compile check, autoplay, a real match, `--fontscan`) **and grep the logs for `^ERROR:` /
   `Resource file not found`** (a broken font path still passes `--fontscan`).

If your fork modified one of those files, diff it against the core version first: improvements that are not sport-specific
go upstream (below), sport-specific behaviour must be moved into a hook / your own class (core files are not edited in a game).

## Update to a newer core version

```bash
git subtree pull --prefix=core G:/NewGDP/gosports-core main --squash
```

Read `CHANGELOG.md` first. A new minor version only adds modules (adopt them when you want); a breaking change would bump the
major version and be listed with a migration note.

## Contribute a change back (maintainer flow)

Preferred: change the core repo directly (`<core>`), commit, bump `VERSION` + `CHANGELOG.md`, `git tag vX.Y.Z`, then `subtree pull` in
the games. When it is easier to edit in place (a game's `core/` folder) do it in ONE game, test there, and push it back:

```bash
git subtree push --prefix=core G:/NewGDP/gosports-core main
```

Never edit `core/` differently in two games at the same time.

## Checklist for a new core module

- [ ] no reference to a sport class; resources under `res://core/`
- [ ] a game consumes it (the module is not speculative)
- [ ] the siblings' versions of the same file were diffed and reconciled
- [ ] `CHANGELOG.md` + `VERSION` + a line in the README table

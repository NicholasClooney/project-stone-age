# StoneAge agent workflow

- Work from this repository root with relative paths. Keep changes runnable and preserve original-game fidelity using the local reference source.
- Run all tests in the background without opening windows or taking focus. `scripts/run.sh --script …` defaults to headless and muted. Do not launch a graphical test unless the user explicitly requests it; only then use `STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --script …` (still muted). Headless tests cannot validate rendered pixels.
- Use conventional commits. Do not commit imported original assets, reference archives or verification screenshots.
- Gameplay authority lives in `client/server/backend.gd` and `client/server/automation.gd`. UI code reads `world.state` / `world.session.snapshot()` and changes anything only through `world.session`, `world.battle_session` or `world.link.request`; never mutate `world.backend` from UI. A remote client has no backend at all. See [backend interface](docs/technical/backend-interface.md).
- `scripts/test-all.sh` reports every suite; `scripts/test.sh` stops at the first failure. `scripts/test.sh` ignores its arguments and runs every suite one by one; run a single suite with `./scripts/run.sh --headless --script res://tests/<name>.gd`.

## Working in the main checkout (the session the user talks to, not subagents)

The main checkout serves the user's live game (`./scripts/relaunch.sh`). When a fix or feature there is ready:

1. **Relaunch first so the user can test.** Back up the save (`single-player.json.before-<name>-<stamp>`), stop the previous relaunch, run `./scripts/relaunch.sh` in the background and wait for `Ready:`. Tell the user it is up.
2. **Then run the tests** while the user plays: the changed suites, then `STONE_AGE_TEST_LOGS=<private dir> ./scripts/test-all.sh`. Don't make the user wait on tests before they can try the change.
3. Commit, refresh the changelog and fast-forward `main` once the tests pass. If they fail, fix and relaunch again.

Subagents working in their own worktrees don't relaunch; they test and commit, and the main session merges and relaunches.

## Required in-game changelog

Game versions are **v0.MINOR.PATCH** while the game is in beta; the `0` major means no save or protocol compatibility promise yet. Versions derive from conventional commits on first-parent history: up to v0.43.0 every `feat` or `fix` advanced MINOR, and after that a `feat` advances MINOR (resetting PATCH) while a `fix` advances PATCH. Documentation, chores and tests do not advance it. This project's scheme overrides unrelated dotfiles release instructions. Create annotated tags only for checkpoints the user asks for, not per commit. App version, `SAVE_VERSION` and the backend protocol revision are independent; see [version system](docs/versioning/version-system.md).

For every feature/fix:

1. Add concise player-facing notes to `docs/development/changelog-notes.json`, keyed by the exact conventional commit subject. Describe visible behavior and where to find it; distinguish developer conveniences from original features. Keep unavailable/incomplete behavior explicit.
2. Test the change, then commit normally.
3. Immediately run `./scripts/refresh-changelog.sh`. It regenerates the in-game JSON and `config/version`, then amends **only those two generated files** into the commit just created. Run it only for your own fresh, unpushed commit. If that commit is already shared, regenerate and make a separate `chore(changelog)` commit instead.
4. Run `python3 tools/build_changelog.py --check` (also enforced by `scripts/test.sh`). Never manually invent version numbers or edit generated entries. No commit hashes are embedded, so the amend is stable.

The game reads `client/data/changelog.json` and exposes it through **更新日志**. History is generated offline; the running game does not need Git. First-parent counting avoids double-counting merged branch histories, but a merge commit also hides the branch's feat/fix commits. Land feature branches by rebasing onto `main` and fast-forwarding. The two generated files conflict during that rebase: take either side, then regenerate them in every rebased commit with `--exec 'python3 tools/build_changelog.py && git add client/data/changelog.json client/project.godot && git commit --amend --no-edit -q'`.

## Tagging a release

Only tag when the user asks. The tag must equal the generated version, not a bump of the previous tag. Tags are sparse, so the next tag usually skips numbers (for example `v0.43.0` then `v0.47.0`).

1. Run `python3 tools/build_changelog.py --check` and fix any failure first.
2. Read the version from `client/data/changelog.json` (`version`) and tag that commit with an annotated tag: `git tag -a v<version> -m "v<version>"` (for example `v0.47.2`).

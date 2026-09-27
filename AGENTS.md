# StoneAge agent workflow

- Work from this repository root with relative paths. Keep changes runnable and preserve original-game fidelity using the local reference source.
- Run all tests in the background without opening windows or taking focus. `scripts/run.sh --script …` defaults to headless and muted. Do not launch a graphical test unless the user explicitly requests it; only then use `STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --script …` (still muted). Headless tests cannot validate rendered pixels.
- Use conventional commits. Do not commit imported original assets, reference archives or verification screenshots.

## Required in-game changelog

Game versions are **v0.MINOR.PATCH** while the game is in beta; the `0` major means no save or protocol compatibility promise yet. Versions derive from conventional commits on first-parent history: up to v0.43.0 every `feat` or `fix` advanced MINOR, and after that a `feat` advances MINOR (resetting PATCH) while a `fix` advances PATCH. Documentation, chores and tests do not advance it. This project's scheme overrides unrelated dotfiles release instructions. Create annotated tags only for checkpoints the user asks for, not per commit. App version, `SAVE_VERSION` and the backend protocol revision are independent; see [version system](docs/versioning/version-system.md).

For every feature/fix:

1. Add concise player-facing notes to `docs/development/changelog-notes.json`, keyed by the exact conventional commit subject. Describe visible behavior and where to find it; distinguish developer conveniences from original features. Keep unavailable/incomplete behavior explicit.
2. Test the change, then commit normally.
3. Immediately run `./scripts/refresh-changelog.sh`. It regenerates the in-game JSON and `config/version`, then amends **only those two generated files** into the commit just created. Run it only for your own fresh, unpushed commit. If that commit is already shared, regenerate and make a separate `chore(changelog)` commit instead.
4. Run `python3 tools/build_changelog.py --check` (also enforced by `scripts/test.sh`). Never manually invent version numbers or edit generated entries. No commit hashes are embedded, so the amend is stable.

The game reads `client/data/changelog.json` and exposes it through **更新日志**. History is generated offline; the running game does not need Git. First-parent counting avoids double-counting merged branch histories, but a merge commit also hides the branch's feat/fix commits. Land feature branches by rebasing onto `main` and fast-forwarding. The two generated files conflict during that rebase: take either side, then regenerate them in every rebased commit with `--exec 'python3 tools/build_changelog.py && git add client/data/changelog.json client/project.godot && git commit --amend --no-edit -q'`.

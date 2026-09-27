# StoneAge agent workflow

- Work from this repository root with relative paths. Keep changes runnable and preserve original-game fidelity using the local reference source.
- Run all automated/visual game tests muted through `scripts/run.sh --script …` / `--headless`, or explicitly pass `--audio-driver Dummy`.
- Use conventional commits. Do not commit imported original assets, reference archives or verification screenshots.

## Required in-game changelog

Game versions are **v0.x.0**, as requested for this project. `x` is the cumulative number of conventional `feat` and `fix` commits on first-parent history. Documentation, chores and tests do not advance it. This project's scheme overrides unrelated dotfiles release instructions; do not create release tags automatically.

For every feature/fix:

1. Add concise player-facing notes to `docs/development/changelog-notes.json`, keyed by the exact conventional commit subject. Describe visible behavior and where to find it; distinguish developer conveniences from original features. Keep unavailable/incomplete behavior explicit.
2. Test the change, then commit normally.
3. Immediately run `./scripts/refresh-changelog.sh`. It regenerates the in-game JSON and `config/version`, then amends **only those two generated files** into the commit just created. Run it only for your own fresh, unpushed commit. If that commit is already shared, regenerate and make a separate `chore(changelog)` commit instead.
4. Run `python3 tools/build_changelog.py --check` (also enforced by `scripts/test.sh`). Never manually invent version numbers or edit generated entries. No commit hashes are embedded, so the amend is stable.

The game reads `client/data/changelog.json` and exposes it through **更新日志**. History is generated offline; the running game does not need Git. First-parent counting avoids double-counting merged branch histories; a merge intended as a release must have an appropriate feat/fix subject.

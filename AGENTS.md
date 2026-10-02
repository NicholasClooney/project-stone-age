# StoneAge agent workflow

- Work from this repository root with relative paths. Keep changes runnable and preserve original-game fidelity using the local reference source.
- Run all tests in the background without opening windows or taking focus. `scripts/run.sh --script …` defaults to headless and muted. Do not launch a graphical test unless the user explicitly requests it; only then use `STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --script …` (still muted). Headless tests cannot validate rendered pixels.
- Use conventional commits. Do not commit imported original assets, reference archives or verification screenshots.
- Gameplay authority lives in `client/server/backend.gd` and `client/server/automation.gd`. UI code reads `world.state` / `world.session.snapshot()` and changes anything only through `world.session`, `world.battle_session` or `world.link.request`; never mutate `world.backend` from UI. A remote client has no backend at all. See [backend interface](docs/technical/backend-interface.md).
- `scripts/test-all.sh` reports every suite; `scripts/test.sh` stops at the first failure. `scripts/test.sh` ignores its arguments and runs every suite one by one; run a single suite with `./scripts/run.sh --headless --script res://tests/<name>.gd`.

## Effort estimates: project story points

- Use this project's **story points (SP)** for effort estimates, including research reports and delegated tasks. The user's original playable MVP / completed Samgir slice is **1 SP**; completed villager conversation is **0.5 SP**. Do not substitute a generic team's point scale or treat the later, larger M004 MVP as the 1 SP anchor.
- Read [estimate assumptions](docs/development/replication-estimates.md), the [estimate ledger](docs/development/feature-estimates.json), and the [feature catalogue](docs/product/feature-catalogue.md) before estimating. Compare the proposed scope to those completed anchors and to the **current** implementation; old backlog estimates are historical baselines, not current remaining work.
- SP measures relative scope, effort and uncertainty, **not elapsed time**. Do not invent “agent-days” or convert SP mechanically to hours/days (the early 30-minute MVP aspiration is not a conversion rate). If the user separately requests a schedule, state its assumptions and evidence separately from SP.
- Give an SP range with scope, dependencies, reusable existing systems, validation work and major unknowns. Separate shared foundations from per-task incremental work and charge foundations only once. If evidence is insufficient, mark the estimate provisional or investigate first rather than imply precision.
- Pass this calibration to subagents asked to estimate. When revising the existing catalogue, update its ledger and scope together; do not silently rescale historical estimates.

## Agent roles and messages

Three agents work together in tmux panes: main agent → coordinator → worker.

- **main agent (Claude, `claude-projects-stone-age-2`)**: interfaces with the user and the other agents: clarifies intent, turns it into self-contained tasks and relays user decisions. Does not investigate or implement.
- **coordinator (Claude, `claude-projects-stone-age-1`)**: coordinates Codex and owns the main checkout: merges Codex commits, runs importers, backs up saves, relaunches the server, runs tests and records decisions in docs. Sends anything that needs a user decision to the main agent, not to the user.
- **worker (Codex, `codex-projects-stone-age-1` and its sub agents)**: main implementer. Sub agents split work by file ownership to avoid conflicts (for example, one owns `quest_helper_menu.gd`).

Messages:

- Everything goes through `tmux-ask`. Long reports go in a file; the message is a short summary plus the path.
- The user reads coordinator→main agent messages directly, so the main agent does not restate them; it surfaces a decision as a one-line summary plus options.
- Mark FYIs "无需回复". A decision request states the default and what is blocked meanwhile.
- An instruction the user gives directly to any agent wins; that agent tells the others what changed.
- Original-source bugs: keep ones that only make play easier, with a "原版行为" note in UI/changelog; ask the user case by case about ones that affect progression or the economy (repeatable rewards, item/gold farming, skipping key gates or rebirth requirements). See the rule in [rebirth bonus quest audit](docs/reverse-engineering/rebirth-quest-bonus-audit.md) (「原版源码漏洞的通用处理规则」).

## Working in the main checkout (the coordinator session, not subagents)

The main checkout serves the user's live game (`./scripts/relaunch.sh`). When a fix or feature there is ready:

1. **Relaunch first so the user can test.** Back up the save (`single-player.json.before-<name>-<stamp>`). Stop the running server **cleanly** before anything else: `./scripts/stop-server.sh` (asks the backend through `build/server-8781.shutdown` to record the stop, save and write `<save>.resume.json`, waits until 8780/8781 are free, and falls back to TERM after 30 s). Don't `kill` it yourself: Godot skips its shutdown on TERM/INT, and then only the periodic resume snapshot (up to 10 s old) keeps the hunt. Only then stop the previous relaunch task, run `./scripts/relaunch.sh` in the background and wait for `Ready:`. Tell the user it is up.
2. **Then run the tests** while the user plays: the changed suites, then `STONE_AGE_TEST_LOGS=<private dir> ./scripts/test-all.sh`. Don't make the user wait on tests before they can try the change.
3. Commit, refresh the changelog and fast-forward `main` once the tests pass. If they fail, fix and relaunch again.

Subagents working in their own worktrees don't relaunch; they test and commit, and the main session merges and relaunches.

## Testing budget (agents in worktrees)

- While working, run only the suites your change touches (`./scripts/run.sh --headless --script res://tests/<name>.gd`). Run the full `./scripts/test-all.sh` **once**, at the end.
- After rebasing onto a moved `main`, rerun the full suite only if the rebase touched code; a rebase whose only conflicts were Markdown notes / generated changelog files needs just `python3 tools/build_changelog.py --check` and your own suites. The main session runs the full suite after merging.
- `./scripts/test-all.sh --only a_test,b_test` runs a few suites in parallel, reported like the full run.
- No suite is known to be flaky. If one fails under load, don't just rerun it: find what it waits on. Suites wait for a condition with a generous deadline (`res://tests/support/wait.gd`), never a fixed number of frames or a short wall-clock timeout; clients over WebSocket `settle` (one round trip) before another device acts; servers listen on port 0.
- Tests never use the game's real user:// folder. `scripts/run.sh --script res://tests/…` points user:// at `…/Godot/app_userdata/Stone Age tests/<checkout>-<cksum>/` (the `TestUserDir` autoload reads `STONE_AGE_TEST_USER_DIR`), and `test-all.sh` gives every suite its own folder per run, deleted when it passes. Fixed fixture names like `user://x-test.json` are safe as long as tests reach files through user://, never an absolute path into the real app-data folder.
- Several agents often run at once while the user's fast hunt uses the CPU. Don't run more than one full suite at a time per agent, and prefer fewer jobs over more.

## Worktree pool

Every agent (Claude, Codex and their subagents) borrows a worktree from one shared pool instead of creating its own. Slots are `.claude/worktrees/pool-a`, `pool-b`, … and are reused between tasks.

```sh
python3 tools/worktree_pool.py status                 # who has which slot, for how long
python3 tools/worktree_pool.py acquire --owner <agent name> --branch <branch> --task "<what>"   # prints the slot path
python3 tools/worktree_pool.py acquire ... --import    # only when the branch changes an importer
python3 tools/worktree_pool.py release pool-b          # after the branch is merged into main
```

- The pool starts at 5 slots and grows by itself up to 10 when all are leased. More than 10 needs the user's approval; only then rerun with `--approved-by-user`.
- Leases live in `.git/worktree-pool.json` (shared by every worktree, never tracked); a file lock stops two agents taking the same slot.
- `acquire` checks the slot is clean, switches it to the branch (new from `main`, or the existing branch) and sets up the folders below. `release` refuses while the slot has uncommitted changes or the branch has not landed on `main` (merged, fast-forwarded or cherry-picked, including cherry-picks whose changelog or `scripts/test.sh` suite list were regenerated; checked with `git cherry` and `git merge-tree`); `--abandon` drops uncommitted changes on purpose (the branch and its commits stay). Release as soon as the main session has merged your branch.
- A slot left leased for more than 12 hours shows as `STALE?` in `status`: ask its owner before releasing it.
- Do not create worktrees outside the pool, and do not delete slot folders by hand.

## Assets in worktrees

Imported original assets are gitignored, so a worktree has to get them from the main checkout (`M` below). Copies add up: on 2026-10-02, 89 worktrees with full copies left the disk 99% full. Share what the worktree only reads, and copy only what it rewrites:

| Folder | Size | In a worktree |
|---|---|---|
| `.tools/` (Godot, extracted originals, Python venv) | ~5 GB | **Symlink**, always: `ln -s "$M/.tools" .tools`. Read-only. |
| `references/` | ~1 GB | **Symlink**, always: `ln -s "$M/references" references`. Read-only. |
| `client/assets/legacy/` | ~1 GB | **Symlink** when the branch does not change an importer, which covers most work (server logic, automation, UI). **Clone** with `cp -c -R` only when the branch changes an importer and must regenerate assets. |
| `client/.godot/` | ~2 GB | **Clone** with `cp -c -R` (Godot writes cache files while running; a clone costs nothing until a file changes). Re-clone it after `main` re-imports. |
| `build/fast_hunt` | small | Built by `scripts/run.sh`; no need to copy. |

Rules that go with it:

- Never run an importer or `scripts/run.sh --headless --editor --import` in a worktree whose `client/assets/legacy` is a symlink: it would rewrite the main checkout, which the live server uses. Clone first if the branch needs to import.
- A functional change only needs the game to run its tests, not its own copy of the art. Symlinked assets are the default; the main session keeps them current by re-running importers in the main checkout right after merging an importer change (or in a separate assets worktree if the live server must not be disturbed).
- Remove a worktree as soon as its branch is merged: `git worktree remove <path>` keeps the branch and its commits, deletes the directory including ignored copies, removes a symlink itself without following it, and refuses when there are modified or untracked files unless `--force`. Then `git worktree prune`. Delete temporary folders (test logs, probe copies) under `/private/tmp` too.

## Required in-game changelog

Game versions are **v0.MINOR.PATCH** while the game is in beta; the `0` major means no save or protocol compatibility promise yet. Versions derive from conventional commits on first-parent history: up to v0.43.0 every `feat` or `fix` advanced MINOR, and after that a `feat` advances MINOR (resetting PATCH) while a `fix` advances PATCH. Documentation, chores and tests do not advance it. This project's scheme overrides unrelated dotfiles release instructions. Create annotated tags only for checkpoints the user asks for, not per commit. App version, `SAVE_VERSION` and the backend protocol revision are independent; see [version system](docs/versioning/version-system.md).

For every feature/fix:

1. Add one Markdown file per commit to `docs/development/changelog-notes/<YYYYMMDDTHHMMSSZ>-<slug>.md`, with JSON-quoted `subject` (exact conventional commit subject) and `title` frontmatter fields and an ordered Markdown bullet list. See [note format](docs/versioning/version-system.md#changelog-notes). Describe visible behavior and where to find it; distinguish developer conveniences from original features. Keep unavailable/incomplete behavior explicit.
2. Test the change, then commit normally.
3. Immediately run `./scripts/refresh-changelog.sh`. It regenerates the in-game JSON and `config/version`, then amends **only those two generated files** into the commit just created. Run it only for your own fresh, unpushed commit. If that commit is already shared, regenerate and make a separate `chore(changelog)` commit instead.
4. Run `python3 tools/build_changelog.py --check` (also enforced by `scripts/test.sh`). Never manually invent version numbers or edit generated entries. No commit hashes are embedded, so the amend is stable.

The game reads `client/data/changelog.json` and exposes it through **更新日志**. History is generated offline; the running game does not need Git. First-parent counting avoids double-counting merged branch histories, but a merge commit also hides the branch's feat/fix commits. Land feature branches by rebasing onto `main` and fast-forwarding. The two generated files conflict during that rebase: take either side, then regenerate them in every rebased commit with `--exec 'python3 tools/build_changelog.py && git add client/data/changelog.json client/project.godot && git commit --amend --no-edit -q'`.

## Tagging a release

Only tag when the user asks. The tag must equal the generated version, not a bump of the previous tag. Tags are sparse, so the next tag usually skips numbers (for example `v0.43.0` then `v0.47.0`).

1. Run `python3 tools/build_changelog.py --check` and fix any failure first.
2. Read the version from `client/data/changelog.json` (`version`) and tag that commit with an annotated tag: `git tag -a v<version> -m "v<version>"` (for example `v0.47.2`).

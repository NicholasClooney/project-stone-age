# One codebase, multiple profiles

A playable edition is the engine plus a resolved manifest, ruleset, feature set, and content packs. Do not create a source branch or duplicate client for each historical edition.

## Independent identities

| Identity | Meaning |
| --- | --- |
| Engine build | The executable implementation |
| Manifest schema | How profile configuration is interpreted |
| Profile revision | A reproducible edition configuration |
| Historical target | Build/region being reconstructed, if known |
| Ruleset revision | Simulation behavior and formulas |
| Content pack revision/hash | Specific resources and definitions |
| Modern protocol revision | Godot client/server wire contract (once networking exists) |
| Legacy adapter ID | A tested historical protocol variant |
| Presentation preferences | Classic/modern, scale, audio, accessibility |

M000 may hard-code `samgir-dev`. Add resolution once a second configuration is genuinely useful.

## Release versions

| Number | Source | Advances when |
| --- | --- | --- |
| App version `v0.MINOR.PATCH` | Generated from history by `tools/build_changelog.py` | `feat` advances MINOR, `fix` advances PATCH (entries through v0.43.0 keep their earlier minor-only numbers) |
| Save format `SAVE_VERSION` | `client/server/game_session.gd` | The stored profile shape changes; add a migration |
| Backend protocol `v` | Message envelope in the [backend interface](../technical/backend-interface.md) | A message changes incompatibly |

Stay on major 0 during beta. Move to 1.0.0 only when saves are promised to carry across updates. Tag checkpoints on request (`v0.43.0` marks the state before the backend split), not every version.

## Resolver contract

1. Parse and validate the manifest schema; reject unknown required fields or unsupported revisions.
2. Resolve exact pack versions and hashes, then their dependencies.
3. Validate feature dependencies and conflicts.
4. Resolve deterministic pack overrides and check every referenced definition.
5. Verify the selected ruleset and protocol are implemented.
6. Produce an immutable resolved profile and digest; use it throughout the session.

Proposed digest input: canonicalized manifest/rules revision, sorted feature set, and ordered pack identities/hashes. Exclude presentation preferences. Store the resolved result rather than trusting a mutable edition label.

Changing profiles requires ending the current session and checking save compatibility. Avoid live rule changes in a running battle/world. Add an explicit migration path for compatible saves; otherwise start a separate slot.

Historical support should be a capability matrix tied to evidence: resources, login, movement, maps, battle, pets, and saves can have different support levels.

## Changelog notes

Create one file in `docs/development/changelog-notes/` per commit, named
`<YYYYMMDDTHHMMSSZ>-<slug>.md` using a valid UTC timestamp and lowercase ASCII slug.
The frontmatter is an intentionally small subset: exactly `subject` and `title`,
each a JSON-quoted string (Unicode is allowed; escape quotes and newlines as JSON).
The subject must match the Git commit subject exactly and be unique across files.

```markdown
---
subject: "fix(ui): keep the selected pet visible"
title: "宠物选择保持可见"
---

- 宠物列表滚动后仍显示当前选择。
- 开发说明可单独列出。
  同一条目的下一行用两个空格缩进。
```

List order and continuation newlines are preserved. Empty lists are allowed.
Other YAML syntax, extra fields, malformed timestamps and duplicate subjects fail
validation rather than silently dropping notes. Timestamp/filename order provides
deterministic reading; Git first-parent order alone controls release versions and
entry display order. Notes for commits absent from that history stay in source
without generating entries. During the JSON migration, matching commit timestamps
were used; three unmatched subjects received `20000101T000000Z` plus their zero-based
original JSON entry index in seconds, preserving their relative source order.

After testing and committing, run `./scripts/refresh-changelog.sh` for your own
fresh, unshared commit, then `python3 tools/build_changelog.py --check`. It amends
only `client/data/changelog.json` and `client/project.godot`; refactor/chore notes
do not bump versions or appear in the player log. Shared commits require a separate
`chore(changelog)` regeneration commit.

For cherry-picks and rebases, retain both independent Markdown files. If a subject
is duplicated, keep one authoritative note; if a filename collides, rename one
with a distinct valid timestamp/slug. Generated JSON and project-version conflicts
still use the existing policy: take either side and regenerate for each rebased
commit with `--exec 'python3 tools/build_changelog.py && git add client/data/changelog.json client/project.godot && git commit --amend --no-edit -q'`.
Do not infer versions from note filenames or combine parallel branches with a
merge commit: rebase and fast-forward so their feat/fix commits remain first-parent.

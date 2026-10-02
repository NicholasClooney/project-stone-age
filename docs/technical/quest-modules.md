# Reviewed original quest modules

`tools/quest_import_common.py` extends the existing quest import without changing
legacy NPC IDs or enabling arbitrary source scripts. Public registration lives in
`client/data/quest-modules.json`; the importer reads its manifests and the runtime
reads its enabled events. An empty registry adds no gameplay content.

## Registration and ownership

The shared-foundation owner edits the registry and public importer. Each content
owner maintains a separate `tools/<name>_quest_sources.json` manifest and its own
source tests; it must not duplicate the public interpreter or asset exporters.

```json
{
  "version": 1,
  "modules": [
    {
      "id": "early-deliveries",
      "manifest": "tools/early_delivery_quest_sources.json",
      "enabled_events": [3, 5, 6, 7, 8, 44]
    }
  ]
}
```

This is a registration example, not current activation. The first API supports
static `changeevent` instances with existing exchange actions. Moving NPCs,
keyword gates, timed gates, NPCEnemy variants and map restoration require their
own reviewed handler support; this API does not silently turn them into exchanges.

## Manifest contract

Required fields:

- `version: 1`, a unique lowercase hyphenated `id`, and `reference_revision`.
- `sources`: reference-relative path to SHA-256. Include every selected create
  and script plus `gmsv/data/itemset.txt`, `gmsv/data/jobdaily.txt`; rewards also
  need `gmsv/data/enemy.txt` and `gmsv/data/enemybase.txt`. All are validated before
  parsing. This is the local source snapshot, not an official release claim.
- `creates`: full paths such as `gmsv/data/npc/quiz/quiz.create`.
- `scripts`: script-relative path mapped to `branches` and `events` (below).
- `items`: reviewed original item IDs, including condition-only items.
- `reward_enemies`: reviewed original GetPet enemy IDs (may be empty).

Optional `jobs` uses the existing journal schema: `id`, `event`, `title`,
`completed_label`, `active_label`. Optional `item_notes` maps string item IDs to
visible limitation text appended to the original description. The importer
preserves `raw_columns` and original logout-vanish metadata.

Example script selection for only the golden Bui reward, excluding event 47:

```json
{
  "quiz/equiz_01": {"branches": [3], "events": [44]},
  "quiz/equiz_02": {"branches": [4], "events": [44]}
}
```

Branch indices are **zero-based original EventNo blocks**, ascending and unique.
`parse_script(text, branch_indices=[4])` selects raw blocks before checking their
predicates and actions. Excluded PET77/event47 branches therefore do not require
support. Selected unsupported syntax still fails. Structural truncation fails
rather than silently discarding a partial source block. Imported branches carry
`source_branch_index` and `source_line` of their original EventNo line.

## Instance identity and import API

- `load_quest_module(reference, manifest)` accepts a path or manifest dictionary
  and returns an unrendered catalog module.
- `merge_quest_module(result, module)` returns a new merged catalog; it does not
  mutate either input. Duplicate instances/modules and conflicting shared item,
  reward or journal definitions fail. Existing shared item descriptions and
  runtime annotations remain authoritative.
- `extend_registered_modules(reference, result)` loads the explicit registry.
  `import_early_quests.run` invokes it after the unchanged brothers extension.

New NPC IDs are `<script>@<map>:<x>:<y>`, for example
`quiz/equiz_02@810:28:16` and `quiz/equiz_02@850:28:16`. They retain
`source_script`, `source_create`, and zero-based `source_create_index` provenance.
A script entry may restrict `instances` to an explicit list of these IDs; missing
bindings fail. Without that list, all actual bindings in the reviewed creates are
imported. Unlisted scripts in a mixed create are not activated. An unbound script
cannot be enabled merely because its file exists. Preexisting NPC IDs stay intact.

Image export remains the existing original-data path: static logical bitmap, or
original action-0/facing/frame-0 with original bitmap offsets. Original 2.5 sprites
100250 and 100252 were checked to contain all eight standing directions. No
replacement art or new rendering system is introduced.

## Validation

`tools/test_quest_import_common.py` imports the real 44 scripts as an isolated
fixture, validates both map instances, branch source lines, source hash rejection,
missing bindings, shared definitions and atomic merge failures. The fixture does
not register or activate the task. Run this together with existing early/brothers
source tests; runtime regressions use the original doctor and brothers suites.

Import only into an independent worktree legacy clone. A module/API commit does
not certify a playable quest: content still needs audited maps, original NPC and
item assets, helpers, authoritative transactions and end-to-end validation.

## Exact pet delivery and fixed fees

The strict parser now accepts `PET=level-template` with optional `*1` in
conditions. `DelPet` accepts a comma-separated list of `PET>`/`PET=` predicates,
with `*1` required on each deletion entry. Larger counts, EV pets, EVDEL and
PET< remain outside this reviewed subset. Runtime selection binds distinct
carried pet UIDs across the whole exchange, then rechecks all of them at both
confirmation stages. No missing pet can be replaced silently by an eligible
spare. All pet deletions, index repairs, item rewards, next UID and event flags
are committed in one candidate-profile save.

`DelStone` accepts a nonnegative integer source amount. Formula expressions are
not yet accepted by the exchange parser. The current balance is checked again
at commit; a failed save preserves the balance and reward together. The common
helper checks net pet capacity for multiple deliveries and updates fee eligibility
when gold changes.

Evidence: `seimu/event/event02_1:5,9,24,28` requires the two exact level-25 shark
pairs; `npc_exchangeman.c:940–960,1130–1144` implements exact level comparison.
`giiru/event/giruev2_1:9–21` specifies a 1000-stone replacement ticket;
`npc_exchangeman.c:2148–2158,2235–2248,2570–2579,2870–2882` checks and deducts
fees. No task content is activated merely by supporting these primitives.

The source-pinned `tests/fixtures/bonus-quest-transactions.json` is test-only.
Its original conditions/actions are compared to the local source by the Python
suite. The real Backend/Session suite covers missing/over-level/event pets,
UID substitution, full-roster net capacity, both pair exchanges, save failure,
source reward generation and reload. Reload comparison normalizes JSON numeric
containers because existing load migration turns elemental float arrays into
integer arrays; production save validation remains unchanged. Two real localhost
WebSocket devices exercise token replacement and replay refusal on port 0.

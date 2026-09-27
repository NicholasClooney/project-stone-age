# Progression and battle restoration

This is the historical M006 checkpoint; see the [current checklist](restoration-status.md) for later additions and limits.

The five approved slices are implemented in the single Godot project, with local authority separated from presentation.

| Slice | Playable result | Evidence |
|---|---|---|
| Progression | Three allocation points per player level; original fixed-point derived stats, pet species growth and equipment contributions; old saves preserve earned values. | [Formulas and migration](../reverse-engineering/progression-formulas.md) |
| Pet management | Original pet-change frame, switch, withdraw and return; incoming pets wait until the next round; each pet retains HP and earned XP. | [Combat source](../reverse-engineering/classic-combat-rules.md) |
| Groups | One to three enemies, independent player/pet targets, native formation coordinates and capture-one/continue behavior. | `group_battle_ui_test.gd`, `battle_settlement_test.gd` |
| Combat outcomes | Native dodge, critical, guard and counter rules; original Miss/Counter art, five critical stars, weapon-specific approach/strike/return animations and impact-timed health bars. | [Combat source](../reverse-engineering/classic-combat-rules.md) |
| Training | Original Samgir trainer, skill shop and confirmation sequence; three purchasable original melee skills, saved per pet. | [Training source](../reverse-engineering/pet-training.md) |

## Try it

- Use **立即遇敌** outside a village. Ordinary encounters cycle through one, two and three opponents; the quest finale remains one stronger opponent.
- Choose the player's target, then the pet's target or learned skill. The pet menu remains available even when an attack is remembered.
- Open the battle **宠物** button to switch or withdraw. The available 2.5 asset26040 has three rows; original arrow assets page the five-pet roster. Later reference asset126230 is absent from this client archive. No row text is painted over another slot.
- Visit Samgir pet shop1003, then approach **超级饲育员** at(18,13). Skill fees are the source prices, not free level-up unlocks.
- The main menu-bar pet window now switches between the original left-anchored list, details and skills screens; rename uses its original separate window. See [native pet-window geometry](../reverse-engineering/pet-window.md).
- Use **DEV → 全图传送** for a whole-map overview and click-to-teleport. See [map controls](dev-map-overview.md).

## Deliberate boundaries

The older physical damage branch is selected explicitly as `classic`; the reference build's newer damage branch is available as `reference`. This is a verified subset, not a claim of complete historical combat parity. Elements, riding, status ailments, remaining skills, original encounter tables, complete quest content and the historical XP curve are still outside these slices. Capture thresholds and escape escalation retain the documented MVP tuning. NPC skill-slot replacement is not implemented.

All four starting villages use original map music marker40 (`sabgm_t0`). Wilderness follows its own map markers. Tests use the silent audio driver; normal play keeps music and effects.

## Verification

Run `scripts/test.sh` and the Python importer tests from the README. The additional suites cover formula/migration integrity, per-pet settlement after switching, three-enemy targeting, capture persistence, skill costs/effects, original roster controls, and actual pointer-driven map teleportation. The full journey still exercises walking, shopping, capturing, the quest finale, saving and reloading. Rendered battle, trainer and map screenshots are generated in ignored artifacts or `/tmp` for visual inspection.

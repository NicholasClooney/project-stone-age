# NPCs, quests, inventory, and items

Start with one NPC and a short dialogue tree. Represent NPC identity, map position, appearance, interaction radius, and dialogue reference as content. When introducing authority, move the existing M001 proximity checks to that owner.

Use declarative dialogue/actions first. Lua or another scripting layer is a future candidate only after actual content needs it; imported legacy scripts are references, not automatically executable modern content.

## Additive slices

- Dialogue: open, choose a response, close; moving away cancels interaction.
- Item: one definition and one stack/instance; server checks ownership and capacity.
- Quest: one prerequisite, one progress condition, one completion state.
- Reward: completion and grant are one atomic, repeat-safe operation.
- Shop: one stock entry; validate price, funds, capacity, and transaction identity.

Definitions belong to content packs; mutable state belongs to saves. Namespace IDs so profiles cannot accidentally substitute unrelated NPCs/items. Rulesets own prices, limits, and reward calculations.

Acceptance: out-of-range interaction fails; replaying completion grants no second reward; insufficient funds or capacity leaves state unchanged. Trading, economy balancing, and generalized scripting wait for their own playable slices.

## Original mission system — deferred

Status: parked by user request. Do not begin a generalized mission implementation as part of ordinary map/encounter expansion. Special dungeons, quest-dependent gates and boss-specific mechanics belong to this later phase; keep existing gates intact. The current MVP quest is not evidence of full original quest support.

### Reference design and evidence

The checked reference combines NPC configuration, condition evaluation, actions and per-player event flags; it is not a single directly importable quest database.

- `references/chenmingbiao-stone-age/gmsv/data/npc/jaruga/event/event01_1`: `EventNo`, `TYPE:REQUEST/ACCEPT/MESSAGE`, `EVENT`, stage-specific dialogue, `GetItem`, `DelItem`, `EndSetFlg`. Event 1 accepts item 2401, removes it, gives item 2427 and sets completion flag 1.
- `.../data/npc/jaruga/event/event04_2`: checks active event 4 and absence of item 2417, then grants 15 units of that item.
- `.../npc/npc_eventaction.c`: checks `NOWEV`/`EVNOW` (active), `ENDEV`/`EVEND` (completed), items/equipment and party conditions; provides actions including item removal, gold and warping.
- `.../npc/npc_exchangeman.c` and `.../char/pet_event.c`: additional event/reward handling. Audit these paths before claiming exact execution-order or failure parity.

This is a sampled design audit, not a complete quest inventory. Decode source text with its verified encoding (current genout/data imports use GB18030); do not preserve garbled dialogue from an incorrect decoding.

### Later restoration approach

1. Catalogue original NPC bindings, event IDs, predicates, dialogue branches, item IDs, rewards and custom handlers by reference version.
2. Convert supported definitions into versioned content packs, preserving original IDs and provenance. Explicitly report unsupported conditions/actions instead of silently ignoring them.
3. Implement authoritative condition/action execution in the current Godot project. Keep dialogue presentation separate from state changes, enabling a future separate server.
4. Persist active/completed flags and any additional stage state actually required by source content. Validate proximity, prerequisites, ownership and capacity before a repeat-safe reward transaction.
5. Prove the pipeline with one simple original delivery quest and one chain across NPCs; retain the MVP quest as a separate regression.
6. Add time conditions, quest gates, special encounters/bosses and dungeon mechanisms in separate playable slices. Do not invent missing original behavior.

Acceptance: exact referenced dialogue branches and rewards; save/reload mid-quest; duplicate submissions cannot repeat a one-time reward; full inventory or unmet conditions cause no partial loss; locked gates remain locked; prerequisites from other tasks are respected. Multiplayer/party quest semantics remain deferred for the single-player phase.

### Current village NPC coverage

Verified from the generated world resident manifest and runtime on 2026-09-27:

- Samgir (1000): 10 imported ordinary outdoor residents plus the separately loaded original villager at (93,72).
- Marinas (2000): 8 imported ordinary outdoor residents.
- These residents have original positions, appearance and imported dialogue data. The ordinary-resident runtime currently displays the first dialogue entry; importing all lines does not mean full branching or cycling is restored.
- The importer selects fixed-position `npcgen_man|file:` entries on the outdoor village floor. This does not cover all interior/service/quest NPCs. Samgir's MVP shop and quest are separate implementations, not proof that village services or quests are complete.

Do not describe either village as having all original NPC behavior restored.

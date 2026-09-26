# NPCs, quests, inventory, and items

Start with one NPC and a short dialogue tree. Represent NPC identity, map position, appearance, interaction radius, and dialogue reference as content. Validate distance and current player state on the server after M001.

Use declarative dialogue/actions first. Lua or another scripting layer is a future candidate only after actual content needs it; imported legacy scripts are references, not automatically executable modern content.

## Additive slices

- Dialogue: open, choose a response, close; moving away cancels interaction.
- Item: one definition and one stack/instance; server checks ownership and capacity.
- Quest: one prerequisite, one progress condition, one completion state.
- Reward: completion and grant are one atomic, repeat-safe operation.
- Shop: one stock entry; validate price, funds, capacity, and transaction identity.

Definitions belong to content packs; mutable state belongs to saves. Namespace IDs so profiles cannot accidentally substitute unrelated NPCs/items. Rulesets own prices, limits, and reward calculations.

Acceptance: out-of-range interaction fails; replaying completion grants no second reward; insufficient funds or capacity leaves state unchanged. Trading, economy balancing, and generalized scripting wait for their own playable slices.

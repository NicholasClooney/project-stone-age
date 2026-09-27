# M001 — One village conversation

Click **Villager** in the bottom bar, or click the resident by the statue at (93, 72). The player walks to a reachable adjacent cell, faces the resident, and opens a dialogue box. Enter, Escape, or 确定 closes it. Continue walking or talk again.

## Evidence

The pinned community server revision is `0c58fb6683a49a178a8ad845a8c296c2cb83bd81` in `chenmingbiao/stone-age`.

- [poru/samugiru01.create](https://github.com/chenmingbiao/stone-age/blob/0c58fb6683a49a178a8ad845a8c296c2cb83bd81/gmsv/data/npc/poru/samugiru01.create), first block: 村民, map 1000, borncenter 93,72,1,1, direction 5, graphic 16039, dialogue file `poru/samugiru02`.
- [poru/samugiru02](https://github.com/chenmingbiao/stone-age/blob/0c58fb6683a49a178a8ad845a8c296c2cb83bd81/gmsv/data/npc/poru/samugiru02): first comma-separated entry discusses the statue and village namesake. Imported verbatim using GB18030.
- Logical graphic 16039 resolves through `ADRN.attr.bmpnumber` to archive bitmap 5885. This correction is included in M002; the first NPC commit incorrectly treated 16039 as a direct archive index. The graphic in the existing client is a fixed NPC graphic, not a SPR animation. Preserve its original pixel art and drawing offset.

`tools/import_npc.py` reads local source files and emits the NPC JSON, source URLs/SHA-256 hashes, and PNG into ignored `client/assets/legacy/`. Run after the main resource importer. No networking occurs during play.

These records verify this community server's placement and line; they do not certify every official historical release. The parchment dialogue panel is newly implemented, not extracted original window art. Click-to-approach, cardinal talk range, and the convenience button are local interaction choices. Only the first line is included; no dialogue randomization, quest, reward, or server protocol is implemented.

## Acceptance and regression checks

- NPC is visible at the recorded location and its cell blocks keyboard movement and pathfinding.
- Clicking the sprite, including during a step, approaches a reachable neighbour before opening dialogue.
- Keyboard movement, ground clicks, reset, and focus loss cancel a pending conversation.
- An unreachable resident cannot open dialogue remotely.
- Dialogue blocks movement and underlying UI clicks; closing clears held input and allows exploration.
- Repeat conversations work without restarting; original village music continues.

Run `./scripts/test.sh` for movement plus NPC checks. Input tests flush injected keys and send mouse events through the viewport so delayed input cannot cancel a later test’s route. The movement suite and 18 NPC checks pass; the dialogue has also been rendered and visually inspected. Optional visual test: `./scripts/run.sh --script res://tests/npc_smoke.gd -- --capture`; it writes `artifacts/samgir-npc.png` and exits. **Use the normal launcher for play.**

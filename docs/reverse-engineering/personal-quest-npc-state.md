# Personal NPC runtime state (project policy B)

The original server shared each NPC's position, counter and death state across
players. User decision `e5e20f7` deliberately changes that behavior: this project
keeps these values in the character's server Backend, shared by its devices and
isolated from other characters. Server restart restores the original NPCs. No
save version, profile field or world-state file is introduced.

## Source and supported contract

- `gmsv/npc/npc_npcenemy.c:255–276` checks every declared item across slots starting
  at zero, including equipment. `:445–450` invokes theft on victory only for
  `steal:1`; `:596–637` removes the first matching copy per listed item.
- `:462–486` hides the source NPC for `dieact:0`; `:533–538` restores it only when
  `NowTime.tv_sec > death_time + revival_time`. The supported original guard
  subset is `entype:2`, `dieact:0`, `time:300`, an explicit item list and either
  no `steal` or `steal:1`. Explicit `steal:0` and other unreviewed fields fail
  closed. Existing `dieact:1` victory Warp behavior remains unchanged.
- `gmsv/npc/npc_exchangeman.c:77,151–196` initializes the NPC Warp counter at one,
  selects that source destination, then advances and wraps it. Import accepts
  only dot-separated numeric triples in the original comma-separated order.
  Four-jewel source `extra/event/hougyoku:14` supplies
  `4000.53.101,2000.44.39,5105.14.3,6000.58.44`.

Task manifests retain the existing `handlers[script]={kind:"npcenemy",events:[…]}`
API. The importer derives `guard:{enemy_ids,dieact,required_items,steal,cooldown}`
from the pinned actual `.arg`, and retains `source_fields` and `combat_audit`.
Required and dropped items must be declared in `items`. There is no hand-written
battle action list or client-owned cooldown. A selected changeevent branch can
retain its original `actions.NpcWarp` directly; all destination maps must exist
before the transaction commits. This does not activate any new task registry.

## Transaction and public projection

`quest_npc_state.gd` is instantiated per `OriginalQuests`, owned by the character
Backend. Guard loot and optional theft commit through the existing atomic battle
settlement. Only after save success is the death deadline installed. Failure
restores the original profile and pending battle, including existing personal
party settlement results and claims; retry cannot roll or grant drops again.
NpcWarp similarly commits its position/counter only after the quest reward saves.

`derived.quest_npcs` is a dictionary keyed by stable NPC id. Each public value
contains only `hidden:true` and/or `{map_id,cell}`. No deadline, counter or private
state is sent. Server dialogue lookup and the helper use the same active NPC
projection; raw stale NPC ids cannot bypass hidden state or moved positions.
The helper cache adds a separate NPC-state revision while retaining route keys.
Remote clients rebuild affected residents, collision and click targets from this
projection; they never mutate the server. Existing dialogue text is allowed to
finish when an NPC moves after giving its reward.

Dialogue explains: “原版为全服共享，本项目按角色各自计算；服务器重启复位。”
Fixed enemies still use the existing AI; original special skills are audit data.

## Targeted evidence

`personal-quest-npcs.json` contains reproducible, SHA-pinned source fixtures for
three Saton guards, the miner, and the four-jewel exchange; the Python source test
rebuilds the entire module and compares it exactly. Real Backend/Session tests
cover missing entry items, exact troops, guaranteed original drops, save failure,
one-copy theft, retry/replay, strict 300/301 boundary, NpcWarp order and restart
readback. Three real sockets cover two devices on one character and a second
character, failure/retry visibility and expiry broadcasts. The UI suite uses a
real remote game with no local Backend and checks original actor nodes, click
positions and terrain collision after hide/restore/move; it is headless and does
not claim rendered-pixel verification. Existing A party settlement regression is
run separately. No full suite is run during this task batch.

## Static random encounter drops without NPCEnemy

A static module may declare `drops:[{source:"gmsv/data/enemy.txt",enemy_id:1305,
item_id:2760,probability:100,audit:"path to task source audit"}]`. `sources` must
SHA-pin that enemy table; `items` must contain every declared item. The importer
checks each pair and its original thousandth probability against `drop_slots`,
derives the source line, raw enemy row and exact source slots, and rejects
unknown fields, duplicate declarations, unreviewed items or omitted slots on an
activated enemy. Optional `source_line` must equal the actual row. It does not
trust a manifest probability or copy arbitrary drops. The output feeds the
existing `reviewed_drops` activation and battle RNG/claims transaction; it does
not itself register the task. Original group item prerequisites/exclusions remain
in the normal encounter tables and are not bypassed by this declaration.

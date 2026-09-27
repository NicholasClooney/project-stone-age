# Feature evidence and coverage limits

Reviewed 2026-09-27 against the locally archived revisions in [reference provenance](local-references.md):

- **S**, server/account source: `chenmingbiao/stone-age`, `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`.
- **C**, client source: `anson1788/stoneage`, `1997fc20456dbda36d181b9680ae10bed2e9cdf9`; paths below are relative to `石器时代8.5客户端最新源代码/石器源码`.

Method: enumerate client/server subsystem files, NPC handlers, window enums and version flags; inspect representative command dispatch, movement, trading and save flows. This is a static feature-family inventory, not an execution audit of every handler or proof of a matched playable build. Legacy executables were not run. Text encoding is inconsistent; symbol names and control flow are stronger evidence than garbled comments.

## Traced examples

| Source | Verified observation | Implication |
| --- | --- | --- |
| S `gmsv/char/char_walk.c:643` `CHAR_walkcall` | Calls movement logic; success drives party followers and pet following | Movement needs authority and group-state handling, beyond camera translation |
| S `gmsv/battle/battle_command.c:49` `BattleCommandDispach` | Validates player/battle state and dispatches escape/other commands | Battle is a state machine; original menu art alone is insufficient |
| S `gmsv/char/trade.c:658` and `:714` `TRADE_ChangeItem` | Applies item/pet/gold exchange operations | Reimplementation should make exchanges atomic and test stale confirmation |
| S `saac/recv.c:60`, `:100`, `:130`, `:149` | Account-server handlers load/save/list/delete characters | Persistence/session responsibilities exist separately from world presentation |
| S `gmsv/function.c:71–110` | Registers includes behind optional feature macros | Source presence does not establish an enabled or official feature |
| C `systeminc/login.h:11–29` | Message/input/selection, shops, storage and family window types | One villager window does not finish all dialogue/UI variants |
| C `systeminc/login.h:59–119` | Auction, profession, contract and ranking window identifiers | Evidence of client interfaces; server completeness still needs tracing |
| S `gmsv/npc/npc_petfusion.c` | Zero-byte file | Do not claim a working fusion implementation based on its filename |

## Catalogue source map

Each entry lists relevant code/data, not a claim that every symbol in that file was audited. Both-sided entries still require matching protocol/rules fixtures. Rows without source paths are new product/architecture requirements. Difficulty and points are engineering estimates, not quantities derived from line counts.

- **C01 — Local authority and command boundary:** New project requirement; no claim of legacy source equivalence.
- **C02 — Map/interior portals and spawn rules:** [S `gmsv/npc/npc_warp.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_warp.c); [S `gmsv/npc/npc_warpman.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_warpman.c); [S `gmsv/char/event.c`](../../references/chenmingbiao-stone-age/gmsv/char/event.c)
- **C03 — Character creation, stats, growth and titles:** [S `gmsv/char/char_data.c`](../../references/chenmingbiao-stone-age/gmsv/char/char_data.c); [S `gmsv/char/title.c`](../../references/chenmingbiao-stone-age/gmsv/char/title.c); [C `system/character.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/character.cpp)
- **C04 — Inventory, equipment and consumables:** [S `gmsv/char/char_item.c`](../../references/chenmingbiao-stone-age/gmsv/char/char_item.c); [S `gmsv/item/item_event.c`](../../references/chenmingbiao-stone-age/gmsv/item/item_event.c); [C `system/magicitem.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/magicitem.cpp)
- **C05 — NPC window types and dialogue choices:** [S `gmsv/npc/npc_windowman.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_windowman.c); [C `systeminc/login.h`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/systeminc/login.h); [C `system/talkwindow.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/talkwindow.cpp)
- **C06 — Quest conditions, flags and rewards:** [S `gmsv/npc/npc_eventaction.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_eventaction.c); [S `gmsv/npc/npc_action.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_action.c); [S `gmsv/char/event.c`](../../references/chenmingbiao-stone-age/gmsv/char/event.c)
- **C07 — Item/pet shops, healers and storage:** [S `gmsv/npc/npc_itemshop.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_itemshop.c); [S `gmsv/npc/npc_petshop.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_petshop.c); [S `gmsv/npc/npc_healer.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_healer.c); [S `gmsv/npc/npc_bankman.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_bankman.c); [S `gmsv/npc/npc_poolitemshop.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_poolitemshop.c); [C `system/shop.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/shop.cpp)
- **C08 — Random encounters and enemy groups:** [S `gmsv/char/encount.c`](../../references/chenmingbiao-stone-age/gmsv/char/encount.c); [S `gmsv/char/enemy.c`](../../references/chenmingbiao-stone-age/gmsv/char/enemy.c)
- **C09 — Turn battle engine and original battle UI:** [S `gmsv/battle/battle.c`](../../references/chenmingbiao-stone-age/gmsv/battle/battle.c); [S `gmsv/battle/battle_command.c`](../../references/chenmingbiao-stone-age/gmsv/battle/battle_command.c); [C `system/battleproc.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/battleproc.cpp); [C `system/battlemenu.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/battlemenu.cpp)
- **C10 — Combat formula/status/element fidelity:** [S `gmsv/battle/battle_event.c`](../../references/chenmingbiao-stone-age/gmsv/battle/battle_event.c); [S `gmsv/battle/battle_ai.c`](../../references/chenmingbiao-stone-age/gmsv/battle/battle_ai.c)
- **C11 — Magic, battle items and skill dispatch:** [S `gmsv/magic/magic.c`](../../references/chenmingbiao-stone-age/gmsv/magic/magic.c); [S `gmsv/magic/magic_field.c`](../../references/chenmingbiao-stone-age/gmsv/magic/magic_field.c); [S `gmsv/battle/battle_magic.c`](../../references/chenmingbiao-stone-age/gmsv/battle/battle_magic.c); [S `gmsv/battle/battle_item.c`](../../references/chenmingbiao-stone-age/gmsv/battle/battle_item.c)
- **C12 — Rewards, defeat and recovery:** [S `gmsv/battle/battle.c`](../../references/chenmingbiao-stone-age/gmsv/battle/battle.c); [S `gmsv/char/char_data.c`](../../references/chenmingbiao-stone-age/gmsv/char/char_data.c); [S `gmsv/npc/npc_savepoint.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_savepoint.c)
- **C13 — Pets: capture, ownership, growth and roster:** [S `gmsv/char/pet.c`](../../references/chenmingbiao-stone-age/gmsv/char/pet.c); [S `gmsv/char/pet_event.c`](../../references/chenmingbiao-stone-age/gmsv/char/pet_event.c); [S `gmsv/battle/battle_event.c`](../../references/chenmingbiao-stone-age/gmsv/battle/battle_event.c)
- **C14 — Pet battle commands and skill training:** [S `gmsv/battle/pet_skill.c`](../../references/chenmingbiao-stone-age/gmsv/battle/pet_skill.c); [S `gmsv/npc/npc_petskillshop.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_petskillshop.c)
- **C15 — Pet follow, riding and gestures:** [S `gmsv/char/char_walk.c`](../../references/chenmingbiao-stone-age/gmsv/char/char_walk.c); [S `gmsv/npc/npc_riderman.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_riderman.c); [C `system/field.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/field.cpp)
- **C16 — Party formation and following:** [S `gmsv/char/char_party.c`](../../references/chenmingbiao-stone-age/gmsv/char/char_party.c); [S `gmsv/char/char_walk.c`](../../references/chenmingbiao-stone-age/gmsv/char/char_walk.c)
- **C17 — Chat, friends/address book and mail:** [S `gmsv/char/char_talk.c`](../../references/chenmingbiao-stone-age/gmsv/char/char_talk.c); [S `gmsv/char/addressbook.c`](../../references/chenmingbiao-stone-age/gmsv/char/addressbook.c); [S `gmsv/char/petmail.c`](../../references/chenmingbiao-stone-age/gmsv/char/petmail.c); [S `saac/mail.c`](../../references/chenmingbiao-stone-age/saac/mail.c); [C `system/chat.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/chat.cpp)
- **C18 — Save/load and profile migrations:** [S `saac/char.c`](../../references/chenmingbiao-stone-age/saac/char.c); [S `saac/db.c`](../../references/chenmingbiao-stone-age/saac/db.c); [S `saac/lock.c`](../../references/chenmingbiao-stone-age/saac/lock.c)
- **C19 — Trading items, pets and currency:** [S `gmsv/char/trade.c`](../../references/chenmingbiao-stone-age/gmsv/char/trade.c); [C `other/trade.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/other/trade.cpp)
- **C20 — Remaining classic HUD functions/map/time:** [C `system/menu.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/menu.cpp); [C `system/menu2.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/menu2.cpp); [C `system/radar.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/radar.cpp); [C `system/handletime.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/handletime.cpp)
- **C21 — Bus/airplane and scheduled travel:** [S `gmsv/npc/npc_bus.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_bus.c); [S `gmsv/npc/npc_airplane.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_airplane.c); [S `gmsv/npc/npc_scheduleman.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_scheduleman.c)
- **C22 — Families/clans and shared facilities:** [S `gmsv/char/family.c`](../../references/chenmingbiao-stone-age/gmsv/char/family.c); [S `saac/acfamily.c`](../../references/chenmingbiao-stone-age/saac/acfamily.c); [S `gmsv/npc/npc_familyman.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_familyman.c); [S `gmsv/npc/npc_fmdengon.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_fmdengon.c); [S `gmsv/npc/npc_fmhealer.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_fmhealer.c)
- **C23 — Duels, spectating and rankings:** [S `gmsv/battle/battle_command.c`](../../references/chenmingbiao-stone-age/gmsv/battle/battle_command.c); [S `gmsv/npc/npc_duelranking.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_duelranking.c); [C `system/battleproc.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/battleproc.cpp)
- **X01 — Family manor wars, schedules and tax:** [S `gmsv/npc/npc_fmpkman.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_fmpkman.c); [S `gmsv/npc/npc_manorsman.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_manorsman.c); [C `systeminc/login.h`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/systeminc/login.h)
- **X02 — Player rebirth and pet transformation:** [S `gmsv/npc/npc_transmigration.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_transmigration.c); [S `gmsv/include/version.h`](../../references/chenmingbiao-stone-age/gmsv/include/version.h)
- **X03 — Pet maker/fusion variants:** [S `gmsv/npc/npc_petmaker.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_petmaker.c); [S `gmsv/npc/npc_petfusion.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_petfusion.c)
- **X04 — Quizzes, janken and NPC minigames:** [S `gmsv/npc/npc_quiz.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_quiz.c); [S `gmsv/npc/npc_janken.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_janken.c); [S `gmsv/npc/npc_luckyman.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_luckyman.c)
- **X05 — Pet races and roulette/bank games:** [S `gmsv/npc/npc_petracemaster.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_petracemaster.c); [S `gmsv/npc/npc_petracepet.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_petracepet.c); [S `gmsv/npc/npc_gambleroulette.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_gambleroulette.c); [S `gmsv/npc/npc_gamblebank.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_gamblebank.c)
- **X06 — VIP shops, auto-PK and extra exchange NPCs:** [S `gmsv/npc/npc_vipshop.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_vipshop.c); [S `gmsv/npc/npc_autopk.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_autopk.c); [S `gmsv/npc/npc_itemchange.c`](../../references/chenmingbiao-stone-age/gmsv/npc/npc_itemchange.c); [S `gmsv/function.c`](../../references/chenmingbiao-stone-age/gmsv/function.c)
- **X07 — Crafting/production and professions:** [C `system/produce.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/produce.cpp); [C `systeminc/login.h`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/systeminc/login.h); [S `gmsv/data/profession.txt`](../../references/chenmingbiao-stone-age/gmsv/data/profession.txt)
- **X08 — Auctions, black market and item mall:** [C `systeminc/login.h`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/systeminc/login.h); [C `other/ItemsMall.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/other/ItemsMall.cpp)
- **X09 — Automation, sign-in, turntable and sky-island UI:** [C `system/ai_setting.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/ai_setting.cpp); [C `system/CharSignDay.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/CharSignDay.cpp); [C `system/Turntable.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/Turntable.cpp); [C `system/skyisland.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/skyisland.cpp)
- **N01 — Headless export and two-player networking:** [C `system/netproc.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/netproc.cpp); [S `gmsv/callfromcli.c`](../../references/chenmingbiao-stone-age/gmsv/callfromcli.c)
- **N02 — Accounts, character slots and session ownership:** [S `saac/recv.c`](../../references/chenmingbiao-stone-age/saac/recv.c); [S `saac/lock.c`](../../references/chenmingbiao-stone-age/saac/lock.c); [C `system/login.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/login.cpp)
- **N03 — Administration and operational diagnostics:** [S `gmsv/char/chatmagic.c`](../../references/chenmingbiao-stone-age/gmsv/char/chatmagic.c); [S `gmsv/configfile.c`](../../references/chenmingbiao-stone-age/gmsv/configfile.c); [C `system/onlinegm.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/onlinegm.cpp)
- **N04 — Public-hosting integrity and load validation:** [S `gmsv/net.c`](../../references/chenmingbiao-stone-age/gmsv/net.c); [S `saac/main.c`](../../references/chenmingbiao-stone-age/saac/main.c)
- **N05 — Linux/Windows server packaging:** New project requirement; no claim of legacy source equivalence.
- **P01 — Version manifests, flags and two content profiles:** New project requirement; no claim of legacy source equivalence.
- **P02 — Modern seamless interior/map loading:** New project requirement; no claim of legacy source equivalence.
- **P03 — Classic/modern presentation options:** New project requirement; no claim of legacy source equivalence.
- **P04 — Resource/data conversion hardening:** [C `system/loadrealbin.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/loadrealbin.cpp); [C `system/loadsprbin.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/loadsprbin.cpp); [C `system/map.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/map.cpp)
- **L01 — Godot client to one original server build:** [C `system/lssproto_cli.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/lssproto_cli.cpp); [S `gmsv/lssproto_serv.c`](../../references/chenmingbiao-stone-age/gmsv/lssproto_serv.c)
- **L02 — One original client to Godot authority:** [C `system/lssproto_cli.cpp`](../../references/anson1788-stoneage/%E7%9F%B3%E5%99%A8%E6%97%B6%E4%BB%A38.5%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%9C%80%E6%96%B0%E6%BA%90%E4%BB%A3%E7%A0%81/%E7%9F%B3%E5%99%A8%E6%BA%90%E7%A0%81/system/lssproto_cli.cpp); [S `gmsv/callfromcli.c`](../../references/chenmingbiao-stone-age/gmsv/callfromcli.c)
- **L03 — Import one legacy save schema:** [S `saac/char.c`](../../references/chenmingbiao-stone-age/saac/char.c); [S `gmsv/char/char_data.c`](../../references/chenmingbiao-stone-age/gmsv/char/char_data.c)

## NPC handler inventory

All `npc_*.c` filenames below are recorded for discovery coverage. Many are supporting variants of a catalogue system, not separately additive features. Registration, arguments, conditional flags and client window handling must be checked when selecting a handler. `npc_petfusion.c` is empty; a filename is not an implementation.

- `npc_action.c`
- `npc_airplane.c`
- `npc_alldoman.c`
- `npc_autopk.c`
- `npc_bankman.c`
- `npc_bodylan.c`
- `npc_bus.c`
- `npc_charm.c`
- `npc_checkman.c`
- `npc_dengon.c`
- `npc_doorman.c`
- `npc_duelranking.c`
- `npc_eventaction.c`
- `npc_exchangeman.c`
- `npc_familyman.c`
- `npc_fmdengon.c`
- `npc_fmhealer.c`
- `npc_fmletter.c`
- `npc_fmpkcallman.c`
- `npc_fmpkman.c`
- `npc_fmwarpman.c`
- `npc_freepetskillshop.c`
- `npc_gamblebank.c`
- `npc_gamblemaster.c`
- `npc_gambleroulette.c`
- `npc_healer.c`
- `npc_itemchange.c`
- `npc_itemshop.c`
- `npc_janken.c`
- `npc_luckyman.c`
- `npc_makepair.c` — empty
- `npc_manorsman.c`
- `npc_mic.c`
- `npc_msg.c`
- `npc_newnpcman.c`
- `npc_npcenemy.c`
- `npc_oldman.c`
- `npc_petfusion.c` — empty
- `npc_petmaker.c`
- `npc_petracemaster.c`
- `npc_petracepet.c`
- `npc_petshop.c`
- `npc_petskillshop.c`
- `npc_poolitemshop.c`
- `npc_quiz.c`
- `npc_riderman.c`
- `npc_savepoint.c`
- `npc_scheduleman.c`
- `npc_signboard.c`
- `npc_storyteller.c`
- `npc_sysinfo.c`
- `npc_timeman.c`
- `npc_townpeople.c`
- `npc_transerman.c`
- `npc_transmigration.c`
- `npc_vippoint.c`
- `npc_vipshop.c`
- `npc_warp.c`
- `npc_warpman.c`
- `npc_windowhealer.c`
- `npc_windowman.c`

## Conditional features and unresolved parity

`gmsv/include/version.h` and client `systeminc/version.h` contain many compile-time switches, including battle/pet skill variants and later/private-server additions. A `#define` may itself be inside another conditional; this review did not reconstruct an effective build configuration. Do not mechanically turn every legacy macro into a user-facing flag. Group verified rules into profiles, then test allowed combinations.

Follow-up discovery targets: match the client/server build pair; trace profession/crafting and auction handlers end to end; establish fusion behavior; enumerate unique maps/NPC instances/quest chains; classify every imported skill effect; map later client modules to enabled features. Asset availability and historical edition assignments remain separate checks.

The full source and verified bundles remain ignored local references. The documentation records paths and revisions so research can continue offline without relying on upstream availability.

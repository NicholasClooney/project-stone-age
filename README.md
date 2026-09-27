# Project Stone Age

A playable **Godot 4.6 single-player MVP** around **萨姆吉尔村 / Samgir**, using original maps, sprites, menus, animations, music and sound effects.

## Play

On this Mac, double-click **Play Stone Age.command**, or run from the repository root:

```sh
./scripts/run.sh
```

The project-local Godot runtime is already installed under `.tools/`. You can also open `client/project.godot` in Godot 4.6 and press F6/F5 as appropriate. For another installation, set `GODOT_BIN` to the Godot executable.

| Control | Action |
| --- | --- |
| Left click | Walk to a reachable tile; click the villager to approach and talk |
| Villager button | Walk to the resident at (93, 72) and talk |
| Enter / Escape during dialogue | Close the conversation |
| WASD / arrows | Walk in screen directions; combine keys for eight directions |
| E | Original waving animation |
| X | Sit / stand |
| Tab / DEV → 角色 | Choose an original character with animated previews |
| Mouse wheel / + / − | Zoom from 40% to 200%, in shared 10% steps |
| Max out (DEV controls) | Set the same zoom to its 40% minimum; keep following the player |
| Hover bottom edge | Reveal the original seven menu tabs |
| Map tab / Ctrl+M | Toggle the original map window; drag its title to move it |
| 村外探险 / 返回村庄 | Walk to the original west exit / return portal |
| Battle icons | Choose a command, then its target; choose your pet command next |
| Right click / Esc in battle | Cancel targeting or command selection |
| 道具店 | Walk to the original shop doorway; click the merchant across the counter |
| 状态 / 宠物 / 道具 / 系统 tabs | Stats, pet naming/selection, items/equipment, save and music |
| M | Mute / unmute |
| H / Escape | Open / close help; music volume is in help |
| R | Return to the village square |

Normal play stays open until you close the window. `client/tests/capture.gd` is an automated screenshot test that exits; it is **not** the player launcher.

## What works

- Original 160 × 160 Samgir map, 482 scenery objects, original isometric projection and depth sorting.
- Original eight-direction idle/walk frames, sit and wave; the optional [character pack](docs/development/character-selection.md) adds 41 validated animated appearances and matching club battle sprites.
- Original map/ADRN collision footprints, keyboard movement, and click-to-walk with corner checks.
- Original `sabgm_t0.wav` village BGM, loop and volume controls, and a legacy UI sound.
- One original village resident at (93, 72), with the recorded sprite and first dialogue line, original stone-frame art, confirmation button, and open/close sound effects.
- Original stone top controls, wooden hover-reveal bottom menus, and a working original map window with live coordinates and player marker.
- Camera follow, consistent zoom across maps, held-key release on focus loss while click paths continue, and safe defeat recovery.
- Original 30×30 shop interior and merchant, with functional native shop, inventory, status and pet frames.
- Pure GDScript local battle/progression authority, profile-bound saves and backup recovery.

The single-player loop now includes experience, leveling, currency, source-backed wild species, a paginated 30-pet collection, one active companion, three trainable original pet skills, healing items, a club, the original shop interior, one quest and a stronger finale. The native original battle panel supports independent targets across one to ten enemies, pet switching/withdrawal, learned skills, original miss/critical/counter effects, and player→pet command selection. Progress autosaves and resumes locally. Player and pet stats use original fixed-point formulas and species growth. Existing saves retain earned stats. Player levels grant three points: spend them with UP buttons in the status window. DEV 瞬移模式 lets world clicks move you instantly; destination shortcuts are always instant; 立即遇敌 starts a normal encounter.

Visit the original 超级饲育员 in Samgir’s pet shop (1003, 18,13) to teach 破除防御, 连续攻击 or 背水之战其之１ at their source prices. All four villages share the original `sabgm_t0` theme; wilderness follows its original map music markers. See [restored slices and limits](docs/development/m006-progression-and-battle.md).

**Start your adventure:** click the villager, choose **村外的伙伴 / 休息**, and accept the quest. Explore outside, weaken an enemy and capture it. When you already have a pet, tell it to **defend while weakening a capture target**. Win three battles, then use **DEV → 挑战强敌** in the wilderness for the existing MVP finale. Return to the villager for recovery and the quest reward. Use the original bottom pet tab to rename/select your companion and the item tab to use/equip purchases.

**World restoration:** the four starting villages, both complete islands, linked village interiors and the original undersea route are now visitable. Use **DEV → 传送地点** for direct visits, or **地图导航** to browse maps, zoom/pan, and click terrain or POIs. Choose **步行** for real portal-based travel or **DEV 传送** for instant visits; disable **野外随机遇敌** there for exploration. The normal island crossing retains its original reusable pass requirement. See [world scope and remaining services](docs/development/m005-four-villages.md).

Original assets and menu layouts are retained. Fixed-point growth, supported physical combat and mounted experience now follow inspected source branches. Capture probability, this short quest, shop stock and ordinary encounter composition/timing still include explicit MVP rules; broader elemental/special skill behavior is incomplete. Multiplayer, parties, families, mail and the broader game remain deferred. See [MVP scope, fidelity and verification](docs/development/m004-single-player-mvp.md).

The rejected geometric placeholder demo is not the default or part of the tracked game. It was moved into an ignored local research folder.

## New player tools

On your next normal launch, **蓝人龙、金虎 and one 红暴龙** join once; existing pets and progress stay intact. In **DEV → 骑乘**, select the compatible gold-tiger rider (100010), then mount the tiger. You can deploy a different pet for combat. Original mounted art, separate HP, damage sharing and source-based mounted experience are implemented.

The pet window has five original rows per page, family filters, separate riding/battle states, and a growth comparison: your pet's projected level-120 stats versus its species' theoretical ceiling. These are estimates; the displayed maxima are independently optimal attributes, not a single jointly attainable perfect pet.

**GM 调试** supports level increases through 120, setting/adding base stats, extra allocation points, recovery and reward-free instant escape. **更新日志** shows readable committed changes and the `v0.x.0` version derived from feature/fix history. See [agent changelog workflow](AGENTS.md), [riding evidence](docs/reverse-engineering/original-riding.md), [pet tools](docs/development/pet-collection-growth.md), and [GM controls](docs/development/gm-controls.md).

## Original resources

The imported resources are present locally in `client/assets/legacy/` and deliberately excluded from Git. The importer and provenance documentation are tracked. A fresh clone needs a compatible local resource import before playing; the game explains this if assets are absent.

The current input is the community-distributed **SA2.5-20260823** client from [99ds.com](https://99ds.com/), with Samgir geometry from [chenmingbiao/stone-age](https://github.com/chenmingbiao/stone-age/tree/master/gmsv/data/map/sainasu/samugiru). This preserves the original village layout instead of later decorative additions in that client cache. The exact official release lineage is unverified.

```sh
python3 -m venv .tools/asset-venv
.tools/asset-venv/bin/pip install -r tools/requirements.txt
.tools/asset-venv/bin/python tools/import_legacy.py /path/to/stoneage2.5 \
  --server-map /path/to/samugiru
.tools/asset-venv/bin/python tools/import_ui.py /path/to/stoneage2.5
./scripts/run.sh --headless --editor --import --quit
./scripts/run.sh
```

The client directory must contain `data/adrn_15.bin`, `real_15.bin`, `spradrn_5.bin`, `spr_4.bin`, `pal/Palet_1.sap`, the audio files, and `map/1000.DAT`. The optional `--server-map` reads a matching `LS2MAP` Samgir file. Without it, the client DAT is used and unresolved decorations are recorded, not silently replaced with invented art.

To import the resident, obtain `poru/samugiru01.create` and `poru/samugiru02` from the [pinned legacy NPC source](https://github.com/chenmingbiao/stone-age/tree/0c58fb6683a49a178a8ad845a8c296c2cb83bd81/gmsv/data/npc) into a local directory, preserving `poru/`, then run:

```sh
.tools/asset-venv/bin/python tools/import_npc.py /path/to/stoneage2.5 /path/to/npc
```

For the full MVP, use the [local server reference](docs/reverse-engineering/local-references.md) and import the original wilderness and battle resources:

```sh
.tools/asset-venv/bin/python tools/import_wilderness.py /path/to/stoneage2.5 \
  --server-map references/chenmingbiao-stone-age/gmsv/data/map/sainasu/sainasu
.tools/asset-venv/bin/python tools/import_battle.py /path/to/stoneage2.5
.tools/asset-venv/bin/python tools/import_battle_backgrounds.py /path/to/stoneage2.5
.tools/asset-venv/bin/python tools/import_mvp.py /path/to/stoneage2.5
.tools/asset-venv/bin/python tools/import_world.py /path/to/stoneage2.5
.tools/asset-venv/bin/python tools/import_pet_training.py /path/to/stoneage2.5
.tools/asset-venv/bin/python tools/import_characters.py /path/to/stoneage2.5
.tools/asset-venv/bin/python tools/import_pets.py /path/to/stoneage2.5
.tools/asset-venv/bin/python tools/import_riding.py /path/to/stoneage2.5
.tools/asset-venv/bin/python tools/import_grid_cursor.py /path/to/stoneage2.5
.tools/asset-venv/bin/python tools/import_cursor.py \
  'references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/123.cur'
./scripts/run.sh --headless --editor --import --quit
```

The importer reads the original position, fixed graphic, name, and first comma-separated dialogue entry without rewriting the Chinese. Generated files remain ignored. Missing NPC content leaves exploration available and the Villager button explains the missing import. See [the NPC slice](docs/development/m001-village-npc.md) for evidence and limitations.

See [resource evidence](docs/reverse-engineering/samgir-import.md) for hashes, format decisions, and limitations. Do not add imported client archives or assets to a public release without resolving their distribution status. The bundled Noto Sans SC font is distributed under its included OFL license.

## Local reference sources

Full upstream checkouts and offline Git bundles are preserved in ignored `references/`. See [local reference archives](docs/reverse-engineering/local-references.md) for paths, checksums, and recovery instructions.

## Verify

Scripted and headless runs through `scripts/run.sh` use Godot’s silent audio driver, including visual test scripts. Normal game launches keep audio enabled. Use `--audio-driver Dummy` for any direct engine test launch.

```sh
./scripts/test.sh
.tools/asset-venv/bin/python -m unittest discover -s tools -p 'test_*.py'
```

The MVP suites cover the complete quest journey, shop and portals, capture/pet growth, original battle-menu input, speed-based turns, and save/reload including corrupt-save recovery. See [MVP acceptance](docs/development/m004-single-player-mvp.md).

The UI suite checks menu hover, click isolation, map toggles/live coordinates, shared zoom limits, and original open/close UI sounds. See [classic UI evidence](docs/development/m002-classic-ui.md). The NPC suite checks approach, collision, cancellation, dialogue input, closing, and resumed exploration. The Godot movement suite exercises actual movement, original direction mapping, collision, pathfinding, 200 repeated movement steps, animation, character switching, and audio looping. It needs imported assets. [Verification notes](docs/development/m000-status.md) distinguish automated checks from visual inspection.

## Layout

- `client/` — Godot scene, local simulation, renderer, and tests.
- `tools/import_legacy.py` — bounded binary decoder and deterministic conversion.
- `scripts/` — launch and test helpers.
- `docs/` — [design specification](docs/README.md) and implementation notes.
- `.tools/`, `artifacts/` — ignored local engine, source references, and verification output.

**Ordinary encounter restoration:** walking now uses original regional probabilities, mixed groups, level ranges and wild stats. Captured animals retain their actual level and growth rolls. Map coverage is 147 imported maps: the original 103, 35 training areas, and Giru’s 福尔德村 (5000), 达那村 (5100) and seven ordinary interiors. Giru now links to both villages and their interiors through original portals; reaching Giru itself still needs DEV travel; new interiors do not imply restored NPC services. Special missions, dungeons, bosses and full special skills remain deferred. One required enemy sprite (100298) has corrupt original resources: a troop needing it is skipped with a message, never replaced or rerolled.

After world import, run `python3 tools/import_encounters.py`, then `.tools/asset-venv/bin/python tools/import_encounter_art.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5`, then `./scripts/run.sh --headless --editor --import --quit`. See [source evidence and remaining limits](docs/reverse-engineering/ordinary-encounters.md).

**Travel helpers:** DEV「传送地点」lists every imported map and offers searchable NPC/entrance destinations.「瞬移模式」turns world clicks into safe instant moves.「刷怪传送」offers verified ordinary encounter spots for requested levels1–120 alongside classic-guide caveats. See [travel and training areas](docs/development/travel-and-leveling-assists.md). After updating imports, regenerate destinations with `python3 tools/build_training_spots.py`.

**Giru villages:** choose 福尔德村 or 达那村 in **地图导航 / DEV → 传送地点**, then walk through their original doors and island exits. Interior entries appear first while you are in their village. These restored interiors include scenery and doors; additional NPC services and quests remain deferred. See [travel coverage](docs/development/travel-and-leveling-assists.md).

**Navigation categories:** 地图导航 separates **地点 / 练级点 / Lv.1宠物**. Training and level-one pet lists offer current-map or all-map scope; use the existing walk / DEV teleport choice to visit. Pet locations come from eligible original encounter records, not guaranteed spawns. After imports, regenerate both `tools/build_training_spots.py` and `tools/build_level_one_spots.py`.

**怎样判断极品宠物？** See [宠物品质与成长窗口解读](docs/game-systems/pet-quality.md) for innate rolls versus actual growth, the project’s +6 filter, forecast ranges, and GM/legacy comparison limits.

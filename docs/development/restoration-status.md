# Restoration checklist

Verified against the implementation through v0.23.0 (2026-09-27). “Delivered” refers to the requested playable slice, not complete original-game parity. The earlier five progression/battle slices and later priority requests are consolidated here.

| Requested slice | Status | Scope / remaining boundary |
| --- | --- | --- |
| Playable original Samgir | Delivered | Original map, movement, character actions, music, collision and map transitions. |
| Original UI and battle presentation | Delivered subset | HUD, item/pet/status windows, dialogue, sounds, HP bars, attack/capture/escape animations and hover/selection outlines; historical-version differences remain. |
| Player progression and allocation | Delivered | Original fixed-point base/derived stats, three points per level, save migration; full historical XP curve still absent. |
| Pet switching/withdrawal and group battle | Delivered | Independent player/pet commands, switching and up to ten mixed enemies. |
| Dodge/critical/guard/counter and training | Delivered subset | Native physical combat subset and three original purchasable melee skills; all skills/status effects not complete. |
| Four villages and connecting wilderness | Delivered; expanded | 103 maps: two loaded islands, ten towns and connected interiors. Not all 694 reference map IDs. |
| Character selection | Delivered as approved DEV chooser | 41 validated original appearances; historical creation/login screen and seven damaged/missing appearances not restored. |
| Requested default pets | Delivered | Blue human dragon, gold tiger and one red rex. Gold/mechanical/other rex starter additions were superseded by the user's one-red-rex correction. |
| Riding and mounted XP | Delivered subset | All 82 classic `ridePetTable` rider composites (9 species), eligibility with reasons, a pet-window ride button, combat stat/damage sharing and mounted XP. Family-leader and certificate (`_NEW_RIDEPETS`) mounts are not restored. |
| Stone-fish cursor and yellow world selection | Delivered | Native cursor and map hover marker; UI uses this reference branch's distinct green hover/cyan item selection. |
| Global DEV map | Delivered | Zoom/pan, POIs, teleport or walking; cross-map routes follow actual portals and preserve gates. |
| Pet categories/pages and growth comparison | Delivered | 30-slot collection, original five-row frame; conditional mean, approximate marginal 90% intervals and species normal mean. Theoretical extrema are secondary, not a normal-quality benchmark. |
| GM tools and instant escape | Delivered | Player/pet levels and base stats, additional player allocation, heal and reward-free escape. |
| Backend split and remote play on the local network | Delivered | Rules, automation and saves in a backend reached by commands/events; headless `scripts/serve.sh` keeps automation running with no client; WebSocket clients reconnect with an offline summary. |
| Web client with on-demand assets | Delivered, desktop Chrome verified | 1,117 deduplicated packs; core, maps, battles, pets and music download when needed, cache across visits and retry; neighbouring maps prefetch. Vision Pro Safari is unverified; gamepad input there may need a trusted HTTPS setup. See [web client](../technical/web-client.md). |
| Game controller | Delivered | Walking, talking, menus, paging, dialogue and battle commands/targets through a highlight over the original UI; no hover needed. |
| In-game human-readable changelog | Delivered | v0.MINOR.PATCH from first-parent feat/fix history; agent update workflow enforced. |
| Accurate ordinary wild encounter data | Delivered for supported loaded areas | Original regional selection, levels, wild stats, enemy art and capture persistence; source gaps explicitly rejected. Does not imply all maps/enemies or all original combat rules. |
| All village NPCs/services | Partial | Samgir 11 outdoor residents including initial villager; Marinas 8. Ordinary residents currently show first dialogue. Interiors/services/branches not fully populated. |
| Capture-success and XP distribution parity | Partial | Original capture flags and source enemy XP included, but HP-threshold capture success, full healing on acquisition and MVP XP distribution remain simplified. |
| Original mission system | Parked | Design documented; special dungeons, quest gates and boss mechanics deferred with missions. Existing MVP quest remains playable. |
| Full special skills | Parked | No expansion until requested. |
| Multiplayer, parties, families | Out of current single-player scope | No claim of implementation. |

Battlefield selection fixed in v0.23.0: original ground-tile table and three candidate slots select among 217 available SAB backgrounds at battle entry. Same-map terrain can differ; current maps do not use the three unavailable fields. v0.22.0 used a fixed background and was not faithful here.

Detailed capture and missing-weight evidence: [source audit](../reverse-engineering/capture-and-source-gaps.md).

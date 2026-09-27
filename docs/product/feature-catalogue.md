# Feature catalogue and replication scope

Static source review, 2026-09-27. These are community client/server snapshots, not a verified matched official release. “Core” is a delivery grouping, not a claim of presence in every historical version. Conditional and client-only extensions need build-specific verification.

Calibration: completed original-resource Samgir = **1 point**; completed original villager conversation = **0.5 points**. Current original HUD/map work is also implemented within M002 scope but has no user-calibrated point value. These completed slices are excluded from all remaining estimates.

Each row estimates a working system with representative content, original presentation where assets are available, and relevant tests. It does **not** include every map, quest, pet, skill or historical release. Dependencies refer to row IDs; client-only provisional features have research uncertainty. See [estimate assumptions and totals](../development/replication-estimates.md) and [source evidence](../reverse-engineering/feature-evidence.md).

Difficulty: Medium = established pattern and modest integration; Hard = multiple interacting stateful systems; Research = missing/mismatched behavior evidence, regardless of coding complexity. Rows describe remaining scope: completed Samgir movement, one dialogue and map-window art are not recharged.

## Core

| ID | Feature | Difficulty | Points | Depends on | Deliverable / limit |
| --- | --- | --- | --- | --- | --- |
| C01 | Local authority and command boundary | Medium | 1–2 | — | Movement plus interaction use one owner; headless-compatible rules; no network yet. |
| C02 | Map/interior portals and spawn rules | Medium | 1–2 | C01 | One exterior/interior pair, spawn validation and failure recovery; bulk maps excluded. |
| C03 | Character creation, stats, growth and titles | Medium | 2–4 | C01 | One creation flow, stat allocation, experience/level progression, status UI and representative titles. |
| C04 | Inventory, equipment and consumables | Hard | 2–4 | C01,C03 | Original inventory UI, use/equip/drop/pickup, slot restrictions and atomic ownership. |
| C05 | NPC window types and dialogue choices | Medium | 1–2 | C01 | Expand existing single line to choices, text entry and selections; original sounds/assets; shop logic belongs to C07. |
| C06 | Quest conditions, flags and rewards | Hard | 2–4 | C04,C05 | One branching quest with prerequisites and once-only rewards; all story content excluded. |
| C07 | Item/pet shops, healers and storage | Hard | 2–4 | C04,C05,C13 | Representative buy/sell, heal and deposit/withdraw flows with balances/capacity checks. |
| C08 | Random encounters and enemy groups | Medium | 1–2 | C01,C02 | Area/rate/group selection, busy-state suppression and reproducible RNG fixtures. |
| C09 | Turn battle engine and original battle UI | Hard | 3–6 | C03,C08 | Turn collection, order, targets, attack/guard/escape, win/loss and world return; baseline formulas only. |
| C10 | Combat formula/status/element fidelity | Hard | 3–6 | C09 | Trace representative damage, accuracy, elements, AI and statuses into fixtures; exact full skill matrix is content work. |
| C11 | Magic, battle items and skill dispatch | Hard | 2–4 | C04,C09,C10 | Costs, legal targets, effects and original feedback for representative field and battle actions. |
| C12 | Rewards, defeat and recovery | Medium | 1–2 | C04,C09 | Battle rewards and recovery/spawn handling, no duplicate grants; verify exact penalties for chosen profile. |
| C13 | Pets: capture, ownership, growth and roster | Hard | 2–4 | C03,C09 | One capture, capacity/loyalty/growth rules and original roster UI; full species import excluded. |
| C14 | Pet battle commands and skill training | Hard | 2–4 | C10,C13 | One active pet, representative attacks/support skills, training/replacement and validity checks. |
| C15 | Pet follow, riding and gestures | Medium | 1–3 | C13 | Follow path, ride eligibility/sprites and action replication; sample rides only. |
| C16 | Party formation and following | Hard | 2–4 | C01,C09 | Join/leave/leader, formation, linked movement and battle entry; scripted actors can test before network. |
| C17 | Chat, friends/address book and mail | Hard | 2–4 | C01,C18 | Original UI and local fixtures for channels/contact/mail lifecycle; actual multi-user delivery needs N01/N02. |
| C18 | Save/load and profile migrations | Hard | 2–4 | C01 | Versioned saves, atomic writes, recovery, profile checks and duplicate reward tests; old save import excluded. |
| C19 | Trading items, pets and currency | Hard | 2–4 | C04,C13,C18 | Offer/confirm/cancel with atomic exchange, stale offer and disconnect tests; multi-user transport N01 separate. |
| C20 | Remaining classic HUD functions/map/time | Medium | 1–3 | C01,C03 | Current art/map are done; add time progression, relevant toggles and state. Inventory/pet/mail contents charged to their own rows. |
| C21 | Bus/airplane and scheduled travel | Hard | 1.5–3 | C02,C16 | One route, boarding/fare/schedule and safe arrival; all routes are content work. |
| C22 | Families/clans and shared facilities | Hard | 3–6 | C17,C18 | Creation, membership/ranks, shared notices/facilities and persistence; network N01/N02 separate. |
| C23 | Duels, spectating and rankings | Hard | 2–4 | C09,C16 | Challenge/accept/end, observer lifecycle and representative ranking updates. |

## Extensions

| ID | Feature | Difficulty | Points | Depends on | Deliverable / limit |
| --- | --- | --- | --- | --- | --- |
| X01 | Family manor wars, schedules and tax | Hard | 3–6 | C22,C23 | One scheduled conflict and ownership/tax cycle; source variants need chosen rules. |
| X02 | Player rebirth and pet transformation | Hard | 2–5 | C03,C13,C18 | Prerequisites, stat/ownership changes and persistence; _PET_TRANS is conditional evidence, not proof of every edition. |
| X03 | Pet maker/fusion variants | Research | 2–6 | C13,C18 | Pet maker code exists; npc_petfusion.c is empty. Fusion fidelity needs additional evidence before implementation. |
| X04 | Quizzes, janken and NPC minigames | Medium | 1.5–3 | C05,C06 | One example per handler family with rewards; question banks and event scripts excluded. |
| X05 | Pet races and roulette/bank games | Hard | 2–4 | C13,C18 | Representative race/betting lifecycle and atomic payouts; conditional source extensions, optional profile features. |
| X06 | VIP shops, auto-PK and extra exchange NPCs | Hard | 2–5 | C07,C23 | Representative optional handlers; do not enable private-server additions in a classic profile by default. |
| X07 | Crafting/production and professions | Research | 3–7 | C04,C11 | Client/data evidence; full matching server flow not established. Needs rules reconciliation and representative recipes. |
| X08 | Auctions, black market and item mall | Research | 3–8 | C04,C18,C19 | Client UI evidence, matching server behavior unverified. No payment integration included. |
| X09 | Automation, sign-in, turntable and sky-island UI | Research | 3–8 | C06,C09 | Later client modules; discover enabled build and matching rules before accepting parity scope. |

## Delivery

| ID | Feature | Difficulty | Points | Depends on | Deliverable / limit |
| --- | --- | --- | --- | --- | --- |
| N01 | Headless export and two-player networking | Hard | 3–6 | C01 | New Godot transport, profile handshake, visibility, authoritative updates, disconnect/reconnect; legacy wire protocol excluded. |
| N02 | Accounts, character slots and session ownership | Hard | 2–4 | C18,N01 | Modern authentication/session implementation and original login UI; no reuse of legacy password handling. |
| N03 | Administration and operational diagnostics | Medium | 1.5–3 | N01 | Minimal audited admin actions and useful logs; complete original GM command set requires separate selection. |
| N04 | Public-hosting integrity and load validation | Hard | 4–10 | N01,N02,C18 | Bounds/rates/auth transport, transactional saves, backup/restore, soak/load tests; capacity and production hosting costs not estimated. |
| N05 | Linux/Windows server packaging | Medium | 1–3 | N01 | Validate same-project headless export on both OSes; deferred, no MVP blocker. |

## Product

| ID | Feature | Difficulty | Points | Depends on | Deliverable / limit |
| --- | --- | --- | --- | --- | --- |
| P01 | Version manifests, flags and two content profiles | Hard | 2–4 | C01 | Project requirement: two verified profiles, compatibility checks and save identity; no claim that source branches map cleanly to editions. |
| P02 | Modern seamless interior/map loading | Hard | 2–4 | C02 | Project requirement: preload, cancel, retain current map on failure; logical map transfer stays authoritative. |
| P03 | Classic/modern presentation options | Medium | 1–3 | C20 | Same rules, separate UI scale/camera/transition preferences; original assets preserved. |
| P04 | Resource/data conversion hardening | Hard | 2–5 | — | Extend existing importer for representative missing formats, sound/animation fidelity and reproducible validation; bulk content excluded. |

## Optional interop

| ID | Feature | Difficulty | Points | Depends on | Deliverable / limit |
| --- | --- | --- | --- | --- | --- |
| L01 | Godot client to one original server build | Research | 4–10 | N01 | One pinned protocol pair: login/movement/dialogue baseline only; full command parity requires a later estimate. |
| L02 | One original client to Godot authority | Research | 5–12 | C01,N02 | Separate legacy codec/adapter, same baseline as L01; depends on packet fixtures, not Godot RPC. |
| L03 | Import one legacy save schema | Research | 2–5 | C18 | Read-only conversion fixtures, unknown-field report and identity mapping; never modify original saves. |

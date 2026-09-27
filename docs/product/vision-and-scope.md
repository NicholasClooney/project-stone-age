# Vision and scope

Recreate the familiar StoneAge world through a modern client, retaining historical data and behavior where evidence supports them. Enable classic presentation and modern conveniences without maintaining separate games.

## Target experience

- Start directly in Samgir during development.
- Eventually choose an installed historical or custom profile.
- Play offline using an in-process Godot authority, or connect to a private/remote server.
- Switch presentation preferences without changing combat, progression, item ownership, or access rules.

## Historical targets

| Profile family | Intent | Initial status |
| --- | --- | --- |
| 1.82 | Early-era reconstruction | Research target |
| 2.5 | Early-era rules/content profile | Research target |
| 5.x | Later-era profiles; identify an exact build first | Research target |
| 8.5 | Later-era rules/content profile | Research target |
| Custom | Explicit combinations of verified rules and selected content | Proposed |

No edition is supported merely because its label exists. Track compatibility by exact client/server build, region, data revision, and tested capability. Start with a development profile named `samgir-dev`; choose the first historically faithful profile after inspecting available material.

## Scope boundaries

M000 contains one map, one character, movement, animation, BGM, SFX, and basic collision. It requires no login, networking, battle, pet system, pack manager, database, or general streaming framework.

Later goals include NPC interaction, interiors, encounters, battles, pets, persistence, multiple profiles, and multiplayer. Public MMO operations, monetization, exhaustive historical parity, mobile packaging, and cross-platform dedicated-server validation are outside the initial delivery.

Faithfulness is measured against recorded evidence. Reconstruction and placeholders must be identifiable; visual resemblance alone does not prove compatibility.

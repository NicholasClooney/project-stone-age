# StoneAge reimplementation — working specification

Build a modern StoneAge experience with a Godot client and Godot gameplay authority in one project. Keep every iteration runnable, observable, and incrementally better. The first result is walking around 萨姆吉尔村 (Samgir) with animation, music, sound, and basic collision.

A playable Godot implementation now exists: see the [project launch guide](../README.md) and [M000 status](development/m000-status.md), and [M001 village conversation](development/m001-village-npc.md), and [M002 classic UI](development/m002-classic-ui.md), plus [M003 first battle](development/m003-first-battle.md) and the [completed single-player MVP](development/m004-single-player-mvp.md). Original assets are required following the user’s clarification; the earlier placeholder fallback is superseded.

These English Markdown documents capture the supplied design conversation. They describe intended behavior, not an existing implementation or verified historical compatibility. The specification ZIP was documentation-only; this game repository now includes implementation code, with imported legacy resources kept local.

## Start here

1. Read [vision and scope](product/vision-and-scope.md).
2. Review the [feature catalogue](product/feature-catalogue.md), [effort estimates](development/replication-estimates.md), and [source evidence](reverse-engineering/feature-evidence.md).
3. Follow [agent workflow](agent-guides/workflow.md) and [iteration rules](development/iterative-development.md).
4. Use the [architecture](technical/architecture-overview.md) when the next playable slice needs it.

## Non-negotiable decisions

- One codebase; historical editions are manifests, rules, feature modules, and content packs.
- Separate gameplay rules, wire protocols, content, and presentation.
- M000–M002 may retain temporary local state until the first Godot authority slice.
- After integration, Godot authority owns gameplay state in both local and remote sessions.
- Classic and modern presentation share gameplay semantics. Rule changes require an explicit ruleset.
- Preserve logical map identities while allowing modern seamless presentation.
- Develop one Godot app on macOS first. Linux and Windows dedicated-server exports are future constraints, not MVP gates.
- Aim for a demonstrable improvement every approximately 30 minutes of productive agent work.

## Documentation map

| Folder | Read for |
| --- | --- |
| [product](product/vision-and-scope.md) | Scope, historical targets, and [roadmap](product/roadmap.md) |
| [technical](technical/architecture-overview.md) | [Godot](technical/client.md), [Godot authority](technical/server.md), [networking](technical/networking.md), [local mode](technical/local-server.md), [saves](technical/persistence.md), [platforms](technical/platforms.md), [sprite sheets](technical/sprite-sheets.md), [fast hunt](technical/fast-hunt.md), [game scene scripts](technical/game-scripts.md), [memory baseline](technical/memory-baseline.md) |
| [game-systems](game-systems/world-and-movement.md) | World, movement, [characters and pets](game-systems/characters-and-pets.md), [宠物极品与成长解读](game-systems/pet-quality.md), [battle](game-systems/battle.md), [NPCs, quests, and items](game-systems/npcs-quests-items.md) |
| [versioning](versioning/version-system.md) | Profiles, [flags](versioning/feature-flags.md), [packs](versioning/content-packs.md), [example manifests](versioning/example-manifests.md) |
| [ui-ux](ui-ux/presentation-modes.md) | Presentation modes, [controls](ui-ux/controls-and-layout.md), [seamless transitions](ui-ux/seamless-transitions.md) |
| [content](content/asset-pipeline.md) | Import pipeline, [maps and sprites](content/maps-and-sprites.md), [audio](content/audio.md) |
| [reverse-engineering](reverse-engineering/research-plan.md) | Research priorities, [protocol archaeology](reverse-engineering/protocol.md), [resource archaeology](reverse-engineering/resources.md), [evidence log](reverse-engineering/evidence-log.md) |
| [development](development/iterative-development.md) | Iteration, [M000](development/milestone-000-samgir.md), [later slices](development/vertical-slices.md), [verification](development/verification.md) |
| [agent-guides](agent-guides/workflow.md) | Task execution, [repository conventions](agent-guides/repository-conventions.md), [task template](agent-guides/task-template.md) |

## Reading the specification

**Required** means a project decision or milestone acceptance criterion. **Proposed** means a reversible implementation default. **Research target** means unverified legacy behavior. Examples use project-defined identifiers; they do not assert historical map IDs, packet formats, feature availability, or animation timing.

The latest explicit user decisions take precedence over this specification. Record subsequent architectural changes close to the affected document. Do not let documentation become a prerequisite for showing working gameplay.

- [M005: four villages and the connecting world](development/m005-four-villages.md).
- [Character selection](development/character-selection.md) (and [character faces](reverse-engineering/character-faces.md)), [charm and pet loyalty](reverse-engineering/charm-and-loyalty.md), [精灵 and 气力](reverse-engineering/magic-and-mp.md), [map navigation](development/dev-map-overview.md), [riding](reverse-engineering/original-riding.md), [special pets](reverse-engineering/special-pets.md) (and the [pet birth and growth audit](reverse-engineering/pet-birth-audit.md)), [pet collection and growth comparison](development/pet-collection-growth.md), [GM controls](development/gm-controls.md).
- [In-game changelog and version workflow](../AGENTS.md).

- [Current restoration checklist and remaining gaps](development/restoration-status.md).

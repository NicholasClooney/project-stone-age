# Private arrival action contexts

This project supplement adds server-memory receipts for an arrival-sensitive
transaction preview. It does not persist proof in a profile, activate third-stage
content, or replace the owning service's source conditions, distance, inventory,
profile revision and atomic-save checks.

## Frozen API

- `action_context(backend, npc, branch, phase) -> Dictionary` issues a private
  receipt only for the actual catalog NPC and branch with valid current arrival.
  A new preview supersedes the previous one. Empty branches are accepted only for
  `777/ten.arg@32021:31:28`, source/service `777/ten.arg`, kind
  `original_transmigration`, handler `Transmigration`, phase `SERVICE`.
- `check_action_context(backend, context) -> String` returns an empty string only
  while the private receipt, instance, epoch, position, actual source NPC, stages
  and mark generations still match. Check the original preview receipt at confirm
  and immediately before saving; also call `check_action` with the actual NPC.
  Rechecking never refreshes or consumes it.
- `consume_action_context(context) -> void` consumes the exact private receipt
  after the owning service's atomic save succeeds. It resets arrival memory and
  does not depend on the profile's position: the successful candidate can already
  persist its return-village location. Failed saves must not call consume.

These three generic methods supersede the earlier draft's dedicated
`transmigration_context` / `check_transmigration` proposal; no compatibility
wrappers or published callers of those names exist.

Room marks now carry private generations. Leaving a final component and legally
winning again does not revive a preview from the previous visit even when the
continuous route epoch and final position are unchanged. Project movement,
scope exit and reset clear the receipt along with arrival authority. Nothing
is reconstructed from END flags, carried items, current room or profile data.

## Continuous stages

The stage hooks retain empty defaults for unrelated sources. The exact final
cave mappings added after the generic first slice are described in
transmigration-arrival-policy.md; production activation remains separate. A
reviewed policy associates a saved original action or battle Warp with a stage. `battle_committed` / `action_committed` only queue the
existing private Warp receipt; a matching actual script move consumes it and
awards the stage. Same-scope original walking and portals retain stages across
rooms. Scope exit, project movement and reset remove them. Final-room marks have
their separate component lifecycle. Stage requirements are checked by
`check_action`, including existing guard begin and final settlement hooks.

The final cave policy now has an independent real-Backend route test using the
content owner's runtime source fixture. Product world/helper and natural king
settlement integration remain separate. The static source identity fixture
alone is not an installable runtime fixture. END53 stays closed;
events48–52 are catalog tags, not extra player entry requirements.

## Verification and limits

`quest_arrival_action_context_test` follows the real adult gate, original Dream
maze, actual guardian combat and saved close/Warp. It tests modified receipts,
NPCs and branches, another authority instance, superseded previews, real reward
save failure, unchanged-receipt retries, original reward-room exit and a second
actual victory, mark generations and successful-save consumption. Exact king
identity checks are isolated policy checks; they do not create a king arrival.
This does not claim completed third-stage routes or party fixed-NPC combat.

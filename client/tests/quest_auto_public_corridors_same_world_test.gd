extends "res://tests/quest_auto_public_corridors_world_inputs_test.gd"
## DRAFT: requires its own explicit test window AFTER uncontrolled input evidence.
## Seed 1 is fixed a priori, never searched/selected for a path or a victory.
## This controls only original NPC birth placement. Field/battle RNG unchanged;
## inherited no_random_encounters is solely the disclosed mode-compat fixture.
func controlled_world()->bool:return true
func trace_label()->String:return "controlled-birth-inputs"
func configure_birth_fixture(b)->void:
 # Backend/Automation constructors only wire references. Fail if any original
 # birth attempt already occurred; never clear records or restore forged proof.
 check(b.original_quests.npc_state.version==0 and b.original_quests.npc_state.records.is_empty() and b.original_quests.npc_state.spawn_attempts.is_empty(),"Configure NPC birth RNG before ANY refresh/birth attempt")
 b.original_quests.npc_state.spawn_rng.seed=1

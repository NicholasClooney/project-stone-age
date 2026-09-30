#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 tools/build_changelog.py --check
./scripts/run.sh --headless --editor --import --quit
log_file=$(mktemp -t stone-age-tests)
trap 'rm -f "$log_file"' EXIT
for suite in hunt_resume_test hunt_window_memory_test elements_test elements_ui_test menus_in_battle_test pet_encyclopedia_test battle_sounds_test button_state_test hunt_resilience_test showcase_test pet_records_test release_log_test web_audio_test settings_menu_test perf_panel_test fast_hunt_threads_test keep_rule_test fast_hunt_test fast_hunt_flow_test stat_survey_test gm_grant_pet_test sheet_frames_test automation_settings_test radio_test remote_settings_test gamepad_test waiting_screen_test panel_refresh_test remote_resume_test map_change_ui_test remote_link_test backend_automation_test automation_minimize_test remote_minimize_test pet_healing_test pet_stat_filter_test pet_stat_workflow_test capture_rules_test classic_luck_test loyalty_test pet_capture_preflight_test training_clone_override_test pet_capture_settings_test pet_favorite_test pet_modal_layout_test pet_workflow_reload_test pet_workflow_test mirror_rules_test mirror_battle_ui_test mirror_item_ui_test battle_auto_policy_test capture_assist_squad_test battle_auto_helper_test pet_storage_test pet_release_test pet_comparison_ui_test dana_npcs_test training_max_level_test pet_hunt_speed_test training_defaults_test gm_flag_reset_test lv1_hunt_navigation_test map_navigation_tabs_test giru_villages_test clone_pet_rules_test bulk_stats_ui_test wild_currency_test battle_hover_test clone_squad_rules_test clone_battle_ui_test clone_game_integration_test travel_destinations_test travel_assists_test leveling_routes_test training_helper_test experience_multiplier_test battle_speed_test pet_hunt_rules_test pet_hunt_ui_test battle_background_test encounter_catalog_test wild_encounter_authority_test wild_encounter_integration_test changelog_test grid_cursor_test cursor_test character_selection_test travel_router_rules_test travel_router_test starter_pets_test riding_test riding_battle_test riding_settlement_test pet_growth_test pet_collection_test ui_highlight_test gm_rules_test gm_ui_test progression_test battle_settlement_test classic_combat_test pet_training_test pet_window_test dev_map_overview_test group_battle_ui_test world_expansion_destinations_test world_expansion_interiors_a_test world_expansion_interiors_b_test world_expansion_portals_a_test world_expansion_portals_b_test travel_gate_test inventory_ui_test battle_hud_test dev_navigation_test world_fidelity_test smoke npc_smoke ui_smoke battle_rules_test mvp_rules_test mvp_balance_test battle_menu_test capture_escape_test battle_smoke mvp_ui_smoke mvp_journey_test; do
if python3 - "$suite" "$log_file" <<'RUN_SUITE'
import subprocess, sys
with open(sys.argv[2], "w") as output:
    try:
        result = subprocess.run(["./scripts/run.sh", "--headless", "--script", f"res://tests/{sys.argv[1]}.gd"], stdout=output, stderr=subprocess.STDOUT, timeout=180)
    except subprocess.TimeoutExpired:
        output.write("FAIL: suite exceeded its bounded timeout\n")
        sys.exit(1)
sys.exit(result.returncode)
RUN_SUITE
then
  cat "$log_file"
else
  cat "$log_file"
  exit 1
fi
if grep -Eq 'SCRIPT ERROR|^ERROR:|FAIL:' "$log_file"; then
  echo 'Godot reported an error despite its process exit status.' >&2
  exit 1
fi
done

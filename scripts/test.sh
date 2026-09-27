#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 tools/build_changelog.py --check
./scripts/run.sh --headless --editor --import --quit
log_file=$(mktemp -t stone-age-tests)
trap 'rm -f "$log_file"' EXIT
for suite in changelog_test grid_cursor_test cursor_test character_selection_test travel_router_rules_test travel_router_test starter_pets_test riding_test riding_battle_test riding_settlement_test pet_growth_test pet_collection_test ui_highlight_test gm_rules_test gm_ui_test progression_test battle_settlement_test classic_combat_test pet_training_test pet_window_test dev_map_overview_test group_battle_ui_test world_expansion_test travel_gate_test inventory_ui_test battle_hud_test dev_navigation_test world_fidelity_test smoke npc_smoke ui_smoke battle_rules_test mvp_rules_test mvp_balance_test battle_menu_test capture_escape_test battle_smoke mvp_ui_smoke mvp_journey_test; do
if python3 - "$suite" "$log_file" <<'RUN_SUITE'
import subprocess, sys
with open(sys.argv[2], "w") as output:
    try:
        result = subprocess.run(["./scripts/run.sh", "--headless", "--script", f"res://tests/{sys.argv[1]}.gd"], stdout=output, stderr=subprocess.STDOUT, timeout=180)
    except subprocess.TimeoutExpired:
        output.write("FAIL: suite exceeded 180 seconds\n")
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

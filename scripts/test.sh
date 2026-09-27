#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/run.sh --headless --editor --import --quit
log_file=$(mktemp -t stone-age-tests)
trap 'rm -f "$log_file"' EXIT
for suite in inventory_ui_test battle_hud_test dev_navigation_test world_fidelity_test smoke npc_smoke ui_smoke battle_rules_test mvp_rules_test mvp_balance_test battle_menu_test capture_escape_test battle_smoke mvp_ui_smoke mvp_journey_test; do
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

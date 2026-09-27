# Developer whole-map teleport

Use **DEV → 全图传送** to view the entire current map, including the full800×1200 Jaruga island. Yellow markers are imported NPCs, cyan markers are original doorways/exits, and white marks the player. The right-hand list names each point of interest and its original grid coordinates.

Click the map or a listed destination to teleport to nearby walkable ground. NPC cells and automatic portal triggers are excluded from landing positions. If no safe ground exists within32cells, the map stays open with an explanation. Esc closes without moving. This is explicitly a developer bypass, including travel across gated regions; normal walking still obeys gates.

The view is a grid overview (X right, Y down), using original automap ground colors, not a new game-world illustration. It rasterizes once per loaded map into a texture capped at800×570 pixels and draws only markers afterward. It does not create a sprite per world cell.

Run `scripts/run.sh --headless --script res://tests/dev_map_overview_test.gd`. Tests cover actual pointer input, modal closure, coordinate conversion, safe NPC-adjacent landing and full-island bounds. All verification runs are muted.

# Original yellow hover frame

`system/map.cpp:2009–2026` (`drawGrid`) converts the mouse position to map coordinates, rounds it to a grid cell, and draws `CG_GRID_CURSOR` while the pointer is below menu priority. `systeminc/anim_tbl.h:1499` defines this as logical image **25001**. It follows the mouse; it is not a persistent click-destination indicator.

`tools/import_grid_cursor.py` imports bitmap **8828**, **64×47**, with native offset **−32, −24** from the local client. The Godot helper snaps to the same isometric grid, uses the original bitmap above scenery, and hides over UI, battle, and transitions. The previous hand-drawn destination diamond is removed. No generated replacement art or inferred animation is used.

```sh
.tools/asset-venv/bin/python tools/import_grid_cursor.py /path/to/stoneage2.5
scripts/run.sh --headless --editor --import --quit
scripts/run.sh --headless --script res://tests/grid_cursor_test.gd
```

The marker is world-scaled with the field camera; the stone-fish OS pointer remains native screen size. Click-to-route behavior is unchanged.

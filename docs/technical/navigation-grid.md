# Navigation grid

How the game finds walking paths on a map without keeping a whole-map `AStarGrid2D` (`client/scripts/nav_grid.gd`, used as `game.navigation`).

## Why

`AStarGrid2D` keeps a point record for every cell (position, solid flag, weight, g/f scores, previous point, open/closed pass): about 62 bytes a cell, built for the whole map on entry whether a path is ever searched there or not.

| Map | Cells | AStarGrid2D | NavGrid |
| --- | ---: | ---: | ---: |
| 萨伊那斯 100 | 800 × 800 | 41.7 MB | 0.6 MB |
| 加鲁卡 200 | 800 × 1200 | 61.9 MB | about 1 MB |
| 吉鲁岛 300 | 600 × 600 | 22.6 MB | 0.4 MB |

On the web every megabyte held raises the wasm heap for good, so this matters most there and on phones.

## How it works

1. **One byte a cell.** `_solid` is a `PackedByteArray` (0 walkable, 1 blocked). `set_point_solid` / `is_point_solid` read and write it; doors, residents and the travel overlay change single bytes.
2. **A window per search.** `get_id_path(from, to)` builds a temporary `AStarGrid2D` over the rectangle spanning both ends plus a margin (at least 48 cells, or half the trip's length), solves it with the same diagonal mode and octile heuristics, and lets it go.
3. **Shortest, provably.** A route leaving the window walks at least to the window's edge and back. If the route found inside is no longer (in steps) than `edge_steps(from) + edge_steps(to)` — counting only window edges that are not the map's own — no route outside can be shorter, and it is returned. Otherwise the margin doubles, up to the whole map, so results equal a whole-map grid's (`nav_grid_test` compares 143 random routes on maps 1000/100/300: all the same length).
4. **Kept window.** The last window (up to 320 × 320 cells, about 6 MB) is kept and reused while a search fits inside it and no cell changed in a way it did not follow; single cell changes inside it are applied to it in place.
5. **Solid runs.** Filling a window copies blocked cells in runs (`fill_solid_region` per run), from a per-row cache of `[start, end)` runs built on first use and dropped when a cell of that row changes.

## Costs

Short clicks take a few milliseconds. A first cross-island search builds a large window: about 156 ms worst case on map 100 on an M-series Mac (desktop), more on the web. Later searches nearby reuse the kept window.

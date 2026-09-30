# 开发者性能面板 (performance panel)

A developer overlay with live memory, performance and network numbers. It is not original-game UI.

## Opening it

- **F3** (rebindable on 设置 → 快捷键 as 「性能面板（开发者）」). It works over every window and battle, and even before a map loads.
- **设置 → ▶ 开发者 → 性能面板**.
- The panel sits at the top right on its own canvas layer (above battles and windows). Clicks pass through it, except on its three buttons: 「明细」 (show or hide the breakdown column), 「导出快照」, 「关闭」.

The panel is not built until first opened. While it is hidden it does no work. While it is open it samples twice a second.

## What the numbers mean

**【内存】**

| Line | Source | Meaning |
| --- | --- | --- |
| 静态（峰值） | `Performance.MEMORY_STATIC(_MAX)` | Memory Godot allocated itself (objects, dictionaries, strings, parsed JSON, audio data). Peak is the highest value since launch. It does not include GPU memory, the browser's own memory or allocator slack. |
| 显存 · 纹理 · 缓冲 | `RENDER_VIDEO/TEXTURE/BUFFER_MEM_USED` | What the renderer reports it uploaded. 显存 is the total. On the web (WebGL) these are Godot's own estimates. |
| wasm 堆 | `wasmMemory.buffer.byteLength` (web only) | The whole WebAssembly linear memory. It only grows and never shrinks, so it shows the high-water mark of the static memory plus allocator overhead. It is the number to watch on memory-limited devices (iPhone, iPad, Vision Pro). |
| JS 堆 | `performance.memory` (Chrome only) | JavaScript heap used / allocated (limit). Safari has no such API, so it shows 不可用. |
| 资源包 | `AssetPacks.stats()` (web only) | Packs mounted and their file sizes (from `packs.json`), how many this session downloaded and how many it read from the pack cache (缓存读取), and how many are still pending or failed. Mounted packs stay in the browser's filesystem memory (MEMFS) for the session; cached ones that are not mounted cost nothing. |

**【性能】**

- **FPS**: frames per second. **帧**: the average frame time between two samples (wall time ÷ frames). **逻辑 / 物理**: `TIME_PROCESS` / `TIME_PHYSICS_PROCESS`, the time spent in `_process` and `_physics_process` in the last frame.
- **绘制调用 / 绘制对象**: draw calls and objects drawn in the last frame.
- **对象 / 节点 / 资源 / 孤立节点**: live object, node and resource counts. 孤立节点 are nodes outside the tree that nobody freed. A number that keeps growing is a leak.

**【网络】**

- 本机后台 (single-player): commands and events per second through `LocalLink`. Nothing is serialized, so there are no byte counts.
- WebSocket (remote client): messages and bytes per second in each direction, totals, and **延迟** (the round trip of the last heartbeat ping, sent every 3 s).
- **后台 tick** (in-process backend only): time the last `Backend._process` took (automation tick and event flush), with a running average.

**明细 (breakdown by owner)**

Loaders report what they create to `client/scripts/perf_registry.gd`. It holds weak references, so a texture Godot frees drops out on the next sample.

- **纹理 · 估算**: width × height × bytes per pixel of the GPU format (RGBA8 = 4 for the lossless imports), grouped as 战斗图集 (battle sheets and backgrounds), 骑乘图集, 地图图块 (`images/*.png` for ground, props and residents), 人物图集, 人物面部, 宠物缩略图 (宠物大全), 界面 (classic HUD art). **未登记** is the renderer's texture memory minus these (fonts, battle UI pieces, anything not reported).
- **音频**: streams in memory by 音乐 / 电台 / 音效, with their encoded bytes (WAV/QOA data, Ogg packets) and total seconds.
- **清单 JSON**: the text size of big parsed manifests (battle, riding, characters, world, faces, the current map). The parsed Dictionary in memory is several times larger than the text.

## Snapshots

「导出快照」 writes every number (plus version, engine version, platform, renderer, time, viewport and the ten largest textures) as JSON:

- Desktop: `user://perf-snapshots/perf-YYYYMMDD-HHMMSS.json` (on macOS under `~/Library/Application Support/Godot/app_userdata/Stone Age — 萨姆吉尔村/`). The panel shows the full path.
- Web: a browser download of the same file, a copy on the clipboard, `window.stoneAgePerfSnapshot`, and a `[perf] snapshot …` line in the console.

Compare two snapshots taken at the same place (for example the village after startup, then after ten battles) to see what grows.

## Reading it from Safari Web Inspector

While the panel is open on the web, every sample is also stored in `window.stoneAgePerf`. On a Mac, enable Safari → Settings → Advanced → Show features for web developers, connect the iPhone, iPad or Vision Pro (or open the page on the Mac), then Develop → *device* → *page*. In the console:

```js
stoneAgePerf.web.wasm / 1048576      // wasm heap in MB
stoneAgePerf.engine                  // every engine monitor
stoneAgePerf.registry.textures       // the breakdown
```

Safari's Timelines → Memory view shows the page's total memory (JavaScript, layers, page) next to these numbers. The wasm heap is the part Godot owns.

## Code

- `client/scripts/perf_registry.gd`: the registry loaders report to; pure accounting.
- `client/scripts/perf_monitor.gd`: `sample()`, the panel text (`lines`, `breakdown_lines`) and `snapshot()`. It has no UI, so a probe script can reuse it.
- `client/scripts/perf_panel.gd`: the overlay.
- Counters: `WsLink.stats()`, `LocalLink.stats()`, `AssetPacks.stats()`, `Backend.tick_usec` / `tick_avg_usec`.
- Test: `client/tests/perf_panel_test.gd`.

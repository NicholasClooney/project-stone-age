# Memory baseline

Where runtime memory goes, measured before any optimization (2026-09-30, `main` at c2e6062 plus the re-import of the 8.0 album pets). A desktop Safari tab reached about 6 GB and iPhone Safari reloads the page, most likely out of memory. Re-run the same probes after each optimization and compare against the tables below.

## Headline

| | Desktop (Godot 4.6, Compatibility, M-series Mac) | Web (Chrome for Testing, headless) |
| --- | --- | --- |
| Startup, Samgir village | 360 MB Godot static, 36 MB textures, 824 MB process footprint | 412 MB wasm heap, 89 MB decoded audio, 815 MB page renderer |
| After the tour | 608 MB static (back in the village), 1.3 to 1.7 GB footprint | 805 MB wasm heap, 228 MB decoded audio, 1.52 GB page renderer plus 0.4 GB GPU process |
| Peak | 995 MB static | The wasm heap never shrinks, so the peak is what stays |

Almost all of it is parsed JSON, not pictures. Textures are only about 110 MB after the tour. The biggest consumers, in order:

1. **Parsed JSON as Variant dictionaries: 10 to 20 times the file size.** Battle manifest 141 MB (from startup), riding manifest 208 MB (from the first battle, never freed), the current map 7 to 196 MB (map 200: 196 MB).
2. **Web only: every loaded sound decoded to float32 PCM** (Godot's web "sample" playback): 89 MB at startup, 228 MB alive after the tour, 574 MB created.
3. **Web only: the wasm heap keeps its high-water mark.** Each map switch parses a new map while the old one is still held, and the pet encyclopedia's thumbnails read whole sheets back. The heap reached 805 MB within minutes and stays there.
4. **Web only: every downloaded pack lives in MEMFS** (user:// is IDBFS). At startup IDBFS copies the whole IndexedDB cache into memory, including packs this session never mounts. All packs together are 974 MB.
5. **Textures that are never freed:** every battle, pet and character sheet ever drawn (`SheetFrames`), up to 4,000 map tiles, and all pet thumbnails. That is small in a short tour (63 MB), but a sheet averages 10 MB as RGBA, so a long 后台搜宠 session across many species grows without bound.

## Method

For live numbers in a running game, including on a phone, the developer performance panel (F3, [perf panel](perf-panel.md)) shows the same monitors with a per-owner breakdown. The probes below are the repeatable scripted tour to compare before and after a change.

### Desktop probe (`client/tests/perf/memory_probe.gd`)

```sh
STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --script res://tests/perf/memory_probe.gd -- --out=../build/memory-probe.json
```

It opens a muted window for about 75 seconds. Headless runs work for everything except texture memory, which reads 0 without a real renderer. The script is not in the suite lists. Like every test it runs without persistence: no save, log or viewer setting is written. It builds its own test profile: the three default companions plus 12 扬奇洛斯 (template 92) in storage, so 同种比较 has rows.

The tour: engine only, village startup, test profile, walk in the village, maps 100, 300 (吉鲁岛), 200 (the largest map JSON) and back to 100, a battle (auto attack) and a capture battle with a sample before and after each close, the pet window and 同种比较, 宠物大全 grid (first screen, then scrolled to the end), list and 扬奇洛斯's detail page, the radio through 5 tracks, 设置, back to the village, then 3 more battles and back again.

At each step it records:

- `Performance` monitors: `MEMORY_STATIC` (every Godot allocation: Variants, nodes, images on the CPU), `MEMORY_STATIC_MAX`, `RENDER_TEXTURE_MEM_USED`, `RENDER_VIDEO_MEM_USED`, `RENDER_BUFFER_MEM_USED`, object, resource, node and orphan node counts, draw calls, FPS and process time;
- `ps` resident size and macOS `footprint` (the phys_footprint the system charges the process, GPU memory included) with its largest categories;
- textures in the resource cache by folder (`ResourceLoader.has_cached` over every imported file, width x height x 4). Map tiles and props are the `images` group;
- audio streams in the cache: stored bytes, length, and the 16-bit PCM size it would take decoded;
- the game's own caches: `SheetFrames` sheets and frames, `game.textures` (map tiles), `battle_view.textures`, portrait frames, pet thumbnails, and whether the battle, riding and faces manifests are loaded.

At the end it measures the parse cost of each big JSON (static memory before and after `JSON.parse_string`, with the text already read), the `var_to_bytes` size of the catalogs still held, and whether a loaded texture keeps a CPU copy.

### Web probe (`tools/web_memory_probe.mjs`)

Needs `node`, `playwright-core` and a Chromium (Playwright's Chrome for Testing works). Build and serve in your own checkout, on ports other than the live 8780 and 8781:

```sh
./scripts/build-web.sh
python3 tools/serve_web.py --port 8790 --bind 127.0.0.1 &
.tools/Godot.app/Contents/MacOS/Godot --headless --path client --audio-driver Dummy \
  --script res://server/server_main.gd -- --port=8791 --bind=127.0.0.1 --save=/tmp/memory-probe-save.json &
npm install --prefix /tmp/pw playwright-core
node tools/web_memory_probe.mjs --modules /tmp/pw \
  --url 'http://127.0.0.1:8790/?server=ws://127.0.0.1:8791' \
  --chrome ~/Library/Caches/ms-playwright/chromium-<rev>/chrome-mac-arm64/'Google Chrome for Testing.app'/Contents/MacOS/'Google Chrome for Testing' \
  --out build/memory-probe-web.json
```

The save path is absolute, so the backend never touches the real `user://single-player.json`. The browser runs headless with SwiftShader WebGL, so GPU memory shows up in the GPU process as ordinary memory. The tour uses `window.stoneAgeDev` (explore, encounter, escape, return, pets, village) and the keyboard (B for 宠物大全, the mouse wheel to scroll, Esc), then reloads the page. It records:

- the wasm heap: the size of every `WebAssembly.Memory` the page made. This Emscripten build exports neither `FS` nor `HEAP8`, so an init script captures the memories;
- `performance.memory` (JS heap, with `--enable-precise-memory-info`);
- Web Audio buffers: an init script counts every `AudioBuffer` created, and after a forced GC how many are still alive;
- footprint and resident size of the browser's processes by role (the page renderer is the largest renderer);
- after the reload, the contents of IndexedDB's `/userfs` store: what IDBFS copied into MEMFS at startup. `navigator.storage.estimate()` lags by minutes, so it is not used for this.

It does not measure Safari. Safari's Web Inspector (Timelines, Memory) shows the same split between JavaScript, page and layers. Use `window.stoneAgeDev` there to play the same tour.

## Desktop results

Memory in MB. "File textures" is the RGBA estimate of the imported textures in the cache. "Texture mem" is Godot's own count, which also includes fonts, thumbnails and render targets.

| Step | Map | Static | Static max | Texture mem | File textures | Footprint | Objects | Nodes | Draw calls |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 00 engine only | | 31 | 32 | 8 | 0 | 316 | 1,469 | 1 | 0 |
| 01 startup: village | 1000 | 360 | 382 | 36 | 21 | 824 | 5,602 | 1,123 | 2,369 |
| 02 test profile | 1000 | 364 | 382 | 36 | 21 | 842 | 5,602 | 1,123 | 2,369 |
| 03 walked around the village | 1000 | 364 | 382 | 38 | 22 | 846 | 5,677 | 1,125 | 2,371 |
| 04 Samgir wilderness | 100 | 563 | 600 | 42 | 25 | 1,115 | 5,657 | 1,055 | 2,358 |
| 05 吉鲁岛 + walk | 300 | 477 | 665 | 55 | 35 | 1,002 | 6,085 | 1,311 | 1,456 |
| 06 map 200 | 200 | 679 | 815 | 68 | 45 | 1,189 | 6,323 | 1,307 | 2,324 |
| 07 back to map 100 | 100 | 572 | 869 | 68 | 45 | 1,078 | 6,071 | 1,055 | 2,358 |
| 08 battle open | 100 | 785 | 869 | 75 | 49 | 1,337 | 6,151 | 1,060 | 2,425 |
| 09 after the battle | 100 | 784 | 869 | 75 | 49 | 1,337 | 6,147 | 1,060 | 2,358 |
| 10 capture battle open | 100 | 785 | 869 | 77 | 51 | 1,212 | 6,204 | 1,062 | 2,413 |
| 11 after the capture battle | 100 | 784 | 869 | 77 | 51 | 1,212 | 6,200 | 1,062 | 2,358 |
| 12 pet window | 100 | 786 | 869 | 79 | 52 | 1,216 | 6,499 | 1,160 | 2,441 |
| 13 同种比较 | 100 | 800 | 869 | 80 | 52 | 1,231 | 7,575 | 1,547 | 2,635 |
| 14 pet window closed | 100 | 801 | 869 | 80 | 52 | 1,231 | 7,575 | 1,547 | 2,358 |
| 15 宠物大全 grid | 100 | 859 | 870 | 81 | 52 | 1,389 | 19,665 | 5,854 | 2,492 |
| 16 grid scrolled to the end | 100 | 859 | 987 | 94 | 52 | 1,644 | 20,012 | 5,854 | 2,548 |
| 17 list view | 100 | 818 | 987 | 94 | 52 | 1,676 | 9,333 | 2,084 | 2,479 |
| 18 detail (扬奇洛斯) | 100 | 813 | 987 | 105 | 60 | 1,548 | 8,532 | 1,749 | 2,557 |
| 19 radio, 5 tracks | 100 | 811 | 987 | 105 | 60 | 1,545 | 7,977 | 1,547 | 2,358 |
| 20 设置 | 100 | 811 | 987 | 105 | 60 | 1,548 | 8,119 | 1,590 | 2,405 |
| 21 all closed, village | 1000 | 608 | 987 | 107 | 61 | 1,424 | 8,237 | 1,661 | 2,351 |
| 22 3 more battles, village | 1000 | 608 | 995 | 109 | 63 | 1,295 | 8,278 | 1,661 | 2,351 |

Orphan nodes stayed at 0 throughout. Closing windows frees their nodes (20,012 objects with the grid open, 8,237 after). Two runs gave the same static numbers to within 1 MB.

### Parsed JSON

| File | On disk | Parsed (static) | `var_to_bytes` | Held |
| --- | ---: | ---: | ---: | --- |
| `battle/manifest.json` | 6.8 | 141 | 16.5 | From startup (`setup_audio`), for good; grows as `BattleArt.ensure` merges 8.0 pets |
| `riding/manifest.json` | 10.3 | 208 | 24.4 | From the first battle or mount (`battle_view`, `legacy_actor`, `play_battle_sound`), for good |
| `world/200.json` | 15.2 | 196 | 36.5 | While on the map (`game.data`) |
| `world/100.json` | 9.4 | 125 | 23.2 | While on the map |
| `world/300.json` (吉鲁岛) | 5.1 | 68 | 12.4 | While on the map |
| `battle/backgrounds.json` | 6.0 | 36 | 5.7 | From startup (`battle_view.background_selector`), for good |
| `characters/catalog.json` | 0.8 | 16 | 2.1 | From startup (`game.character_catalog`), for good |
| `encounters/catalog.json` | 1.8 | 13 | 1.9 | From startup (backend), for good |
| `world/1000.json`, `samgir.json` | 0.5 each | 7 each | 1.3 | Village |

Why so large: a map's `ground` is 575,236 three-number arrays for map 100, and each is its own `Array` of `Variant`s. The manifests store every animation frame as a `Dictionary` (`{image, x, y, sound}`). Reading the file also makes a temporary `String` of 4 bytes per character (Godot strings are UTF-32), so switching maps briefly holds the old map, the new text and the new map at once. Hence the peaks: 600 MB on the first visit to map 100, 869 MB when leaving map 200.

Startup's 360 MB is mostly these: battle manifest 141, backgrounds 36, character catalog 16, encounters 13, map 1000 and samgir 14, plus the navigation grid and the scene. After the tour, 608 MB in the same village: the riding manifest (208) plus thumbnails, the encyclopedia and caches.

### Textures

- **No CPU copy.** Loading an unused 2047 x 1556 riding sheet added 16.2 MB of texture memory and 0.07 MB of static memory.
- **Sheets are RGBA.** The importer writes lossless 256-colour PNGs (1 byte a pixel on disk), but Godot imports them as RGBA8. All battle sheets together are 351 MB on disk and 6.5 GB as RGBA (average 10 MB, largest 4093 x 4072 = 64 MB). Riding sheets are 234 MB on disk and 3.9 GB as RGBA.
- **In the tour:** 1,084 map tiles (42 MB), 6 battle and character sheets (18 MB), 384 thumbnails (10.6 MB).
- **Thumbnails read whole sheets back.** Each 宠物大全 grid picture loads the species' sheet, copies it back from the GPU (`get_image`), cuts the frame and drops the sheet. Scrolling the grid once loaded 380 sheets this way: static max rose 117 MB and the process footprint about 250 MB (malloc keeps the freed large blocks). The driver's graphics memory (`IOAccelerator` in `footprint`) went from 86 to 168 MB and did not come back, although Godot's own texture count rose only 13 MB (the thumbnails): the GL driver keeps the freed sheets' memory.

### Audio (desktop)

Small. WAV imports are QOA-compressed and Ogg stays compressed; both are decoded while playing. Startup holds 53 streams in 3.5 MB (village and wilderness music, UI and 46 battle sounds). The radio keeps only the current track (and the next one it prepares). Decoded to 16-bit PCM the startup set would be 38 MB.

## Web results

| Step | wasm heap | JS heap used | Audio buffers alive (created) | Page renderer footprint | GPU process | Packs mounted |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 01 startup, first visit | 412 | 168 | 89 (126) | 815 | 350 | 271 |
| 02 map 100 | 709 | 266 | 146 (209) | 1,102 | 351 | 299 |
| 03 battle open | 709 | 260 | 140 (245) | 1,114 | 360 | 307 |
| 04 after the battle | 805 | 261 | 165 (288) | 1,237 | 369 | 307 |
| 05 after 3 more battles | 805 | 428 | 217 (521) | 1,313 | 367 | 308 |
| 06 pet window | 805 | 273 | 217 (521) | 1,318 | 371 | 308 |
| 07 宠物大全 grid scrolled | 805 | 360 | 217 (521) | 1,423 | 408 | 364 |
| 08 back in the village | 805 | 434 | 228 (574) | 1,520 | 401 | 426 |
| 09 reload, second visit | 412 | 212 | 89 (126) | 787 | 340 | 271 |

- **wasm heap = the desktop's static peak, kept.** Emscripten grows linear memory and never returns it. 412 MB at startup (battle manifest and the first map parse), 709 MB after the first map switch, 805 MB after the riding manifest loaded. On a phone, a single parse of map 200 while another large map is held can push it past what Safari allows.
- **Audio is decoded in full.** Godot 4.6 plays AudioStreamWAV and AudioStreamOggVorbis on the web as samples: the whole stream becomes an `AudioBuffer` of 32-bit floats per channel (about 350 KB per second of stereo), whatever its compression. Startup's 220 seconds of audio cost 89 MB. The buffer lives as long as the stream resource, so `battle_sounds`, `ui_sounds`, the map and battle music and the radio's current and next tracks all stay decoded. A 3-minute radio track is about 63 MB.
- **Packs in MEMFS.** `asset_packs.gd` downloads into `user://packs/`, which on the web is IDBFS: a MEMFS directory (JS typed arrays in the page) mirrored to IndexedDB. `load_resource_pack` keeps reading from that file, so a mounted pack stays in memory for the session. At startup IDBFS copies the whole store back into MEMFS: after the reload all 308 cached packs (66 MB) were in memory, although only 271 were mounted. Nothing is evicted except packs a new index no longer names, so a device that has been everywhere holds up to the full 974 MB on every start (riding 354 MB, sprites 453 MB, maps 63 MB, backgrounds 21 MB). The engine pack (`index.pck`, 14 MB) is in MEMFS too.
- **GPU process** (SwiftShader, so this is CPU memory here): 340 to 410 MB. Safari's WebGL adds its own copies in the GPU process; not measured.

This short tour reaches about 1.9 GB of browser memory. A long session adds more packs, more decoded radio tracks, more sheets and a heap sized by the worst map switch. That fits the 6 GB Safari tab, though Safari itself was not measured.

## What never gets freed

| Held | Size in the tour | Grows with |
| --- | --- | --- |
| Riding manifest (`Riding._manifest`) | 208 MB static | Loaded once on the first battle or mount |
| Battle manifest (`BattleArt._data`) | 141 MB static | Every 8.0 pet sprite `ensure()` merges in |
| `backgrounds.json`, character catalog, encounter catalog | 65 MB static | Fixed |
| `SheetFrames._sheets` / `_frames`, plus `battle_view.textures` and `AnimatedPortrait._textures` holding AtlasTextures of them | 6 sheets, 18 MB | Every distinct sprite drawn (about 10 MB each as RGBA) |
| `game.textures` (map tiles and props) | 1,084 tiles, 42 MB | Cleared on a map change only once over 4,000 |
| `PetThumbnails._made` | 384, 10.6 MB | At most about 580 species, about 16 MB |
| Web: wasm heap | 805 MB | The worst moment so far |
| Web: packs in MEMFS | 66 MB cached, 426 mounted | Every pack ever downloaded on this device |
| Web: decoded audio | 228 MB | Every stream kept loaded (battle sounds, music, radio) |

What does come back: map data when leaving a map (the same map 100 is 563 MB before and 572 MB after visiting two other maps), battle nodes (static is the same before and after closing a battle), window nodes, and radio tracks on desktop.

## Optimizations, in priority order

Estimates are from the measurements above. The web numbers matter most, since there every peak stays in the wasm heap.

1. **Store maps as packed arrays.** Convert `ground` and `blocked` to `PackedInt32Array` / `PackedByteArray` at import (or read `var_to_bytes` / a binary file instead of JSON). Map 100: 125 MB to about 5 MB; map 200: 196 MB to about 8 MB. Also removes most of the map-switch peak (currently +300 to 400 MB). **Saves about 150 to 200 MB held and 300 MB or more of peak, which on the web is the wasm heap size.**
2. **Split the battle and riding manifests per sprite and load on demand**, like the 8.0 pets already are (`battle/pets/<sprite>.json`), and keep frames as packed arrays rather than dictionaries. A battle needs a handful of sprites (about 1 MB each parsed). **Saves about 330 MB static (141 + 208 today) and the web heap with it.** Turning `backgrounds.json` into packed lookups (a battle reads one ground, one battlefield list and one background) saves about 30 MB.
3. **Web music as streams, not samples.** Set `playback_type = PLAYBACK_TYPE_STREAM` on the music and radio players (or `audio/general/default_playback_type.web`), keep samples for short effects. Music is decoded in small chunks by the audio worklet. **Saves about 200 MB after the tour and 50 to 60 MB per radio track**; startup 89 MB to about 12 MB. Drop `upcoming_stream` or keep it compressed. (Transcoding the remaining WAV music to Ogg Vorbis helps pack size and desktop memory only a little; streaming is what matters on the web.)
4. **Keep packs out of MEMFS between sessions.** Store downloaded packs in the Cache API or OPFS from JavaScript and write only the packs this session mounts into a non-persistent MEMFS folder (for example `/tmp/packs`), so startup no longer copies the whole IndexedDB store into memory. **Saves up to the whole cache (up to about 970 MB on a well-travelled device, 66 MB after this tour) at every start.** Mounted packs still cost their size for the session; Godot cannot unmount a pack, so the remaining win is mounting fewer (thumbnails below prefetch whole sprite packs).
5. **Texture budget (LRU) for sprite sheets.** Evict `SheetFrames` sheets (and the AtlasTextures in `battle_view.textures` and `AnimatedPortrait._textures` that keep them alive) beyond a byte budget, say 64 to 128 MB; clear `battle_view.textures` on `close_battle`. Budget `game.textures` by bytes rather than 4,000 entries. **Bounds a long 后台搜宠 session** (today about 10 MB per new species forever); little change in this short tour.
6. **Palette (R8) textures plus a palette shader.** Import sheets as 1 byte a pixel (`Image.FORMAT_R8` or L8) with a 256 x 1 palette texture and a `canvas_item` shader that looks up the colour. **Cuts every sheet's GPU memory by 4** (battle sheets 6.5 GB to 1.6 GB in total; 63 MB to about 16 MB in this tour) and also the web packs (the build stores RGBA today). Needs changes in `SheetFrames`, the thumbnail cutter and every node that draws sheet frames.
7. **Pre-cut thumbnails at import.** Write one small still per species (or one atlas) in `tools/import_encounter_art.py` so 宠物大全 never loads and reads back whole sheets. **Removes about 120 MB of static peak, about 250 MB of footprint churn and about 80 MB of driver memory per scroll**, and on the web avoids prefetching every sprite pack (this tour mounted 118 more packs, about 80 MB, during and after one scroll).

Items 1 to 3 are cheap. By these measurements they would take startup from 360 MB to roughly 200 MB of static memory and keep the web heap under about 400 MB instead of 805 MB (an estimate; re-measure).

## Re-running

- Desktop: the command above; compare the step table (`static_mb`, `static_max_mb`, `texture_mb`, `footprint_mb`) and the JSON costs printed at the end.
- Web: build, serve on your own ports, run the probe; compare `wasm_heap_mb`, `audio.alive_mb`, the page renderer's `largest_footprint_mb` and the reload row.
- Results go to `build/` (ignored). Footprint numbers vary by 10 to 20% between runs (allocator caching, other processes); static memory and the wasm heap are exact.

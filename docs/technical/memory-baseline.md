# Memory baseline

Where runtime memory goes, measured before any optimization (2026-09-30, `main` at c2e6062 plus the re-import of the 8.0 album pets). A desktop Safari tab reached about 6 GB and iPhone Safari reloads the page, most likely out of memory. Re-run the same probes after each optimization and compare against the tables below.

**After split manifests** (optimization 2, [runtime files](sprite-sheets.md#runtime-files)): the battle and riding manifests, `backgrounds.json` and the character catalog are read per sprite on demand. Desktop, same tour, `main` at 404fc92 before and after: startup 362 to 171 MB static, back in the village after the tour 611 to 208 MB, peak 997 to 680 MB. The columns marked "split" below are that run. Web, after only (compare with the web table): wasm heap 412 to 199 MB at startup and 805 to 495 MB after the tour; the core pack 32 to 11 MB.

## Headline

| | Desktop (Godot 4.6, Compatibility, M-series Mac) | Desktop, after split manifests | Web (Chrome for Testing, headless) |
| --- | --- | --- | --- |
| Startup, Samgir village | 360 MB Godot static, 36 MB textures, 824 MB process footprint | 171 MB static, 36 MB textures, 559 MB footprint | 412 MB wasm heap, 89 MB decoded audio, 815 MB page renderer |
| After the tour | 608 MB static (back in the village), 1.3 to 1.7 GB footprint | 208 MB static, 0.8 to 1.0 GB footprint | 805 MB wasm heap, 228 MB decoded audio, 1.52 GB page renderer plus 0.4 GB GPU process |
| Peak | 995 MB static | 680 MB static (leaving map 200) | The wasm heap never shrinks, so the peak is what stays |

Almost all of it is parsed JSON, not pictures. Textures are only about 110 MB after the tour. The biggest consumers, in order:

1. **Parsed JSON as Variant dictionaries: 10 to 20 times the file size.** Battle manifest 141 MB (from startup), riding manifest 208 MB (from the first battle, never freed), the current map 7 to 196 MB (map 200: 196 MB).
2. **Web only: every loaded sound decoded to float32 PCM** (Godot's web "sample" playback; music no longer, see [after streamed audio](#after-streamed-audio-optimization-3)): 89 MB at startup, 228 MB alive after the tour, 574 MB created.
3. **Web only: the wasm heap keeps its high-water mark.** Each map switch parses a new map while the old one is still held, and the pet encyclopedia's thumbnails read whole sheets back. The heap reached 805 MB within minutes and stays there.
4. **Web only: every downloaded pack lives in MEMFS** (user:// is IDBFS). At startup IDBFS copies the whole IndexedDB cache into memory, including packs this session never mounts. All packs together are 974 MB. **Fixed by the pack store, see [after the pack store](#after-the-pack-store-optimization-4)**: packs are cached outside IDBFS and only mounted ones are in memory.
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

The save path is absolute, so the backend never touches the real `user://single-player.json`. The browser runs headless with SwiftShader WebGL, so GPU memory shows up in the GPU process as ordinary memory. The tour uses `window.stoneAgeDev` (explore, encounter, escape, return, pets, village, and since optimization 3 `radio_next` / `radio_off` for five radio tracks and back) and the keyboard (B for 宠物大全, the mouse wheel to scroll, Esc), then reloads the page. It records:

- the wasm heap: the size of every `WebAssembly.Memory` the page made. This Emscripten build exports neither `FS` nor `HEAP8`, so an init script captures the memories;
- `performance.memory` (JS heap, with `--enable-precise-memory-info`);
- Web Audio buffers: an init script counts every `AudioBuffer` created, and after a forced GC how many are still alive;
- footprint and resident size of the browser's processes by role (the page renderer is the largest renderer);
- main-thread tasks over 50, 100 and 200 ms since the last step (`longtask`); streamed music is mixed on the main thread, so a task longer than the audio buffer is a gap. Under SwiftShader nearly every frame is over 200 ms, so these counts only mean something with a real GPU;
- after the reload, the contents of IndexedDB's `/userfs` store: what IDBFS copied into MEMFS at startup. `navigator.storage.estimate()` lags by minutes, so it is not used for this.

It does not measure Safari. Safari's Web Inspector (Timelines, Memory) shows the same split between JavaScript, page and layers. Use `window.stoneAgeDev` there to play the same tour.

## Desktop results

Memory in MB. "File textures" is the RGBA estimate of the imported textures in the cache. "Texture mem" is Godot's own count, which also includes fonts, thumbnails and render targets.

| Step | Map | Static | Static max | Texture mem | File textures | Footprint | Objects | Nodes | Draw calls | Static, split | Static max, split | Footprint, split |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 00 engine only | | 31 | 32 | 8 | 0 | 316 | 1,469 | 1 | 0 | 31 | 34 | 321 |
| 01 startup: village | 1000 | 360 | 382 | 36 | 21 | 824 | 5,602 | 1,123 | 2,369 | 171 | 173 | 559 |
| 02 test profile | 1000 | 364 | 382 | 36 | 21 | 842 | 5,602 | 1,123 | 2,369 | 174 | 191 | 575 |
| 03 walked around the village | 1000 | 364 | 382 | 38 | 22 | 846 | 5,677 | 1,125 | 2,371 | 174 | 191 | 547 |
| 04 Samgir wilderness | 100 | 563 | 600 | 42 | 25 | 1,115 | 5,657 | 1,055 | 2,358 | 374 | 414 | 837 |
| 05 吉鲁岛 + walk | 300 | 477 | 665 | 55 | 35 | 1,002 | 6,085 | 1,311 | 1,456 | 287 | 476 | 735 |
| 06 map 200 | 200 | 679 | 815 | 68 | 45 | 1,189 | 6,323 | 1,307 | 2,324 | 490 | 626 | 1,003 |
| 07 back to map 100 | 100 | 572 | 869 | 68 | 45 | 1,078 | 6,071 | 1,055 | 2,358 | 383 | 680 | 944 |
| 08 battle open | 100 | 785 | 869 | 75 | 49 | 1,337 | 6,151 | 1,060 | 2,425 | 384 | 680 | 965 |
| 09 after the battle | 100 | 784 | 869 | 75 | 49 | 1,337 | 6,147 | 1,060 | 2,358 | 383 | 680 | 895 |
| 10 capture battle open | 100 | 785 | 869 | 77 | 51 | 1,212 | 6,204 | 1,062 | 2,413 | 384 | 680 | 901 |
| 11 after the capture battle | 100 | 784 | 869 | 77 | 51 | 1,212 | 6,200 | 1,062 | 2,358 | 384 | 680 | 901 |
| 12 pet window | 100 | 786 | 869 | 79 | 52 | 1,216 | 6,499 | 1,160 | 2,441 | 386 | 680 | 906 |
| 13 同种比较 | 100 | 800 | 869 | 80 | 52 | 1,231 | 7,575 | 1,547 | 2,635 | 400 | 680 | 920 |
| 14 pet window closed | 100 | 801 | 869 | 80 | 52 | 1,231 | 7,575 | 1,547 | 2,358 | 400 | 680 | 921 |
| 15 宠物大全 grid | 100 | 859 | 870 | 81 | 52 | 1,389 | 19,665 | 5,854 | 2,492 | 458 | 680 | 1,050 |
| 16 grid scrolled to the end | 100 | 859 | 987 | 94 | 52 | 1,644 | 20,012 | 5,854 | 2,548 | 459 | 680 | 1,581 |
| 17 list view | 100 | 818 | 987 | 94 | 52 | 1,676 | 9,333 | 2,084 | 2,479 | 418 | 680 | 1,392 |
| 18 detail (扬奇洛斯) | 100 | 813 | 987 | 105 | 60 | 1,548 | 8,532 | 1,749 | 2,557 | 413 | 680 | 1,107 |
| 19 radio, 5 tracks | 100 | 811 | 987 | 105 | 60 | 1,545 | 7,977 | 1,547 | 2,358 | 411 | 680 | 1,008 |
| 20 设置 | 100 | 811 | 987 | 105 | 60 | 1,548 | 8,119 | 1,590 | 2,405 | 412 | 680 | 1,010 |
| 21 all closed, village | 1000 | 608 | 987 | 107 | 61 | 1,424 | 8,237 | 1,661 | 2,351 | 208 | 680 | 1,018 |
| 22 3 more battles, village | 1000 | 608 | 995 | 109 | 63 | 1,295 | 8,278 | 1,661 | 2,351 | 208 | 680 | 776 |

The split columns are the same tour after optimization 2, measured on `main` at 404fc92 without and with it; the run without it matched the columns on the left to within 3 MB. Texture memory, objects, nodes and draw calls did not change. Every step is about 190 MB lower from startup and 400 MB lower from the first battle on (141 MB battle manifest, 208 MB riding manifest, 36 MB backgrounds, 16 MB character catalog). What remains is mostly maps (optimization 1).

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
| After split: `battle/index.json` | 0.03 | 0.3 | 0.05 | From startup |
| After split: one battle sprite (`battle/sprites/100250.json`) | 0.02 | 0.1 | about 0.01 | The last 32 drawn |
| After split: `riding/index.json` | 0.07 | 0.9 | 0.1 | From the first battle |
| After split: one riding composite | 0.02 | 0.1 | about 0.01 | The last 8 drawn |
| After split: `battle/battlefields.json` | 0.4 | 2.4 | 0.3 | From startup (the battle view) |
| After split: `characters/index.json`, one character | 0.01 each | 0.1 each | under 0.01 | Index from startup, the last 64 characters drawn |
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

After split manifests (same probe on 404fc92 plus the change, ports 8792 and 8793; a few steps timed out waiting for a battle to end and moved on, so the later rows are rougher):

| Step | wasm heap | JS heap used | Audio buffers alive (created) | Page renderer footprint | Packs mounted |
| --- | ---: | ---: | ---: | ---: | ---: |
| 01 startup, first visit | 199 | 154 | 89 (178) | 610 | 271 |
| 02 map 100 | 495 | 262 | 146 (261) | 931 | 299 |
| 03 battle open | 495 | 234 | 140 (297) | 942 | 307 |
| 05 after 3 more battles | 495 | 301 | 182 (453) | 989 | 309 |
| 07 宠物大全 grid scrolled | 495 | 272 | 182 (495) | 1,153 | 397 |
| 08 back in the village | 495 | 320 | 193 (547) | 1,199 | 461 |
| 09 reload, second visit | 199 | 504 | 89 (126) | 1,147 | 271 |

The heap now peaks at the first map 100 parse and stays there: the manifests no longer add to it. IndexedDB held 45 MB of packs after the reload (66 MB before), since the core pack no longer carries the importer manifests.

- **wasm heap = the desktop's static peak, kept.** Emscripten grows linear memory and never returns it. 412 MB at startup (battle manifest and the first map parse), 709 MB after the first map switch, 805 MB after the riding manifest loaded. On a phone, a single parse of map 200 while another large map is held can push it past what Safari allows.
- **Audio is decoded in full.** Godot 4.6 plays AudioStreamWAV and AudioStreamOggVorbis on the web as samples: the whole stream becomes an `AudioBuffer` of 32-bit floats per channel (about 350 KB per second of stereo), whatever its compression. Startup's 220 seconds of audio cost 89 MB. The buffer lives as long as the stream resource, so `battle_sounds`, `ui_sounds`, the map and battle music and the radio's current and next tracks all stay decoded. A 3-minute radio track is about 63 MB.
- **Packs in MEMFS.** `asset_packs.gd` downloads into `user://packs/`, which on the web is IDBFS: a MEMFS directory (JS typed arrays in the page) mirrored to IndexedDB. `load_resource_pack` keeps reading from that file, so a mounted pack stays in memory for the session. At startup IDBFS copies the whole store back into MEMFS: after the reload all 308 cached packs (66 MB) were in memory, although only 271 were mounted. Nothing is evicted except packs a new index no longer names, so a device that has been everywhere holds up to the full 974 MB on every start (riding 354 MB, sprites 453 MB, maps 63 MB, backgrounds 21 MB). The engine pack (`index.pck`, 14 MB) is in MEMFS too.
- **GPU process** (SwiftShader, so this is CPU memory here): 340 to 410 MB. Safari's WebGL adds its own copies in the GPU process; not measured.

This short tour reaches about 1.9 GB of browser memory. A long session adds more packs, more decoded radio tracks, more sheets and a heap sized by the worst map switch. That fits the 6 GB Safari tab, though Safari itself was not measured.

## After streamed audio (optimization 3)

Music and radio play from one Ogg Vorbis library as streams on the web (`client/scripts/music_tracks.gd`, [web client: Music](web-client.md#music)). Measured 2026-09-30 in the same checkout: "before" is `main` at b1783aa with the probe's radio steps added, "after streamed audio" is the branch; both on the same machine and build settings, with a new character each (the "after" runs happened to start on map 100 instead of the village, so compare from step 02).

Web (MB; audio is Web Audio buffers alive after a GC, with those ever created in brackets):

| Step | wasm heap | Audio alive (created) | Page renderer footprint | After streamed audio: wasm heap | Audio alive (created) | Page renderer footprint |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 01 startup, first visit | 412 | 89 (178) | 804 | 591 (on map 100) | 0 (0) | 837 |
| 02 map 100 | 709 | 146 (261) | 1,108 | 591 | 0 (0) | 847 |
| 03 battle open | 709 | 140 (297) | 1,114 | 591 | 1 (1) | 874 |
| 04 after the battle | 805 | 140 (298) | 1,247 | 783 | 1 (2) | 1,052 |
| 05 after 3 more battles | 805 | 182 (453) | 1,282 | 783 | 1 (3) | 1,063 |
| 07 宠物大全 grid scrolled | 805 | 182 (495) | 1,418 | 783 | 1 (3) | 1,227 |
| 08 back in the village | 805 | 193 (547) | 1,527 | 783 | 1 (3) | 1,367 |
| 08a radio, 5 tracks | 805 | 304 (837) | 1,916 | 783 | 1 (3) | 1,421 |
| 08b radio off | 805 | 330 (893) | 1,931 | 783 | 1 (3) | 1,435 |
| 09 reload, second visit | 412 | 158 (262) | 1,455 | 344 | 0 (0) | 606 |

- **Decoded audio is gone:** 1 MB alive instead of 89 to 330 MB, 3 MB created in the whole tour instead of 893 MB. What is left are the sound effects actually played (samples, a few seconds each).
- **The radio no longer grows memory.** Five tracks cost 111 MB of buffers before (and 26 MB more after turning it off); now nothing. The page renderer footprint across the radio steps rose 404 MB before, 68 MB after.
- **The wasm heap is lower too:** sample playback first decodes the whole stream to PCM in the wasm heap and copies it out, which raised the heap's high-water mark. Startup on reload 412 to 344 MB; the peak after the tour 805 to 783 MB.
- **Page renderer footprint** after the tour 1,931 to 1,435 MB; after a reload 1,455 to 606 MB.

Desktop (`memory_probe.gd`, same tour): static memory is unchanged within 3 MB (the parsed JSON dominates). The audio streams held at startup are 52 streams, 1.15 MB, 105 seconds of audio (was 53 streams, 3.5 MB, about 220 seconds): the wilderness track is no longer kept loaded while the village plays. At most two music streams are held at any step (map and battle music, or the radio's current and next track); each map's music is freed when the next map's starts.

Files (the music as imported and as shipped to the web):

| | Before | After streamed audio |
| --- | ---: | ---: |
| Radio tracks, `music/` | 16.0 MB (26 Ogg Vorbis, ffmpeg's built-in encoder at q4) | 21.5 MB (26 Ogg Vorbis, libvorbis q6, cut at the loop end) |
| Map and battle music copies (`sabgm_t0/t1.wav`, `world/audio`, `mvp/audio`, `battle/audio`) | 37.9 MB (10 WAV files, 7 tracks) | none: they play from `music/` |
| Waiting screen `loading/sabgm_s1.ogg` | 0.26 MB | 0.35 MB |
| Web packs for music | 28.1 MB (5 `music-` packs of WAV, 26 `radio-` packs) plus the battle WAVs in core | 22.0 MB (24 `music-` packs) plus 0.8 MB of battle music in core |
| All web packs | 1,856 packs, 1,021.6 MB | 1,849 packs, 1,015.5 MB |

The original WAVs (89 MB) stay in the extracted client folder.

Streaming has one cost in this no-threads build: the engine mixes music on the main thread, so a stall longer than the audio buffer (raised to 150 ms, about 170 ms in practice) is a gap in the music. In headless Chrome with a real GPU (Metal), the playback position advanced exactly 3.0 s in 3 s; under SwiftShader, where every frame takes over 200 ms, it advanced only about 0.6 s in 3 s. Safari was not measured.

## What never gets freed

| Held | Size in the tour | Grows with |
| --- | --- | --- |
| Riding manifest (`Riding._manifest`) | 208 MB static | Loaded once on the first battle or mount. After split manifests: the index (under 1 MB) and the last 8 composites (about 0.1 MB each) |
| Battle manifest (`BattleArt._data`) | 141 MB static | Every 8.0 pet sprite `ensure()` merges in. After split manifests: the index and the last 32 sprites (about 0.1 MB each) |
| `backgrounds.json`, character catalog, encounter catalog | 65 MB static | Fixed. After split manifests: battlefields about 2 MB, characters under 1 MB, encounters 13 MB |
| `SheetFrames._sheets` / `_frames`, plus `battle_view.textures` and `AnimatedPortrait._textures` holding AtlasTextures of them | 6 sheets, 18 MB | Every distinct sprite drawn (about 10 MB each as RGBA) |
| `game.textures` (map tiles and props) | 1,084 tiles, 42 MB | Cleared on a map change only once over 4,000 |
| `PetThumbnails._made` | 384, 10.6 MB | At most about 580 species, about 16 MB |
| Web: wasm heap | 805 MB | The worst moment so far |
| Web: packs in MEMFS | 66 MB cached, 426 mounted | Every pack ever downloaded on this device; since optimization 4 only the packs this session mounted |
| Web: decoded audio | 228 MB (1 MB after optimization 3) | Every stream kept loaded (battle sounds, music, radio); since optimization 3 only sound effects |

What does come back: map data when leaving a map (the same map 100 is 563 MB before and 572 MB after visiting two other maps), battle nodes (static is the same before and after closing a battle), window nodes, and radio tracks on desktop.

## Optimizations, in priority order

Estimates are from the measurements above. The web numbers matter most, since there every peak stays in the wasm heap.

1. **Done, see [after packed maps](#after-packed-maps-optimization-1). Store maps as packed arrays.** Convert `ground` and `blocked` to `PackedInt32Array` / `PackedByteArray` at import (or read `var_to_bytes` / a binary file instead of JSON). Map 100: 125 MB to about 5 MB; map 200: 196 MB to about 8 MB. Also removes most of the map-switch peak (currently +300 to 400 MB). **Saves about 150 to 200 MB held and 300 MB or more of peak, which on the web is the wasm heap size.**
2. **Done (split manifests):** startup 362 to 171 MB static, after the tour 611 to 208 MB; see the split columns. **Split the battle and riding manifests per sprite and load on demand**, like the 8.0 pets already are (`battle/pets/<sprite>.json`), and keep frames as packed arrays rather than dictionaries. A battle needs a handful of sprites (about 1 MB each parsed). **Saves about 330 MB static (141 + 208 today) and the web heap with it.** Turning `backgrounds.json` into packed lookups (a battle reads one ground, one battlefield list and one background) saves about 30 MB.
3. **Done, see [after streamed audio](#after-streamed-audio-optimization-3). Web music as streams, not samples.** Set `playback_type = PLAYBACK_TYPE_STREAM` on the music and radio players (or `audio/general/default_playback_type.web`), keep samples for short effects. Music is decoded in small chunks by the audio worklet. **Saves about 200 MB after the tour and 50 to 60 MB per radio track**; startup 89 MB to about 12 MB. Drop `upcoming_stream` or keep it compressed. (Transcoding the remaining WAV music to Ogg Vorbis helps pack size and desktop memory only a little; streaming is what matters on the web.)
4. **Done, see [after the pack store](#after-the-pack-store-optimization-4). Keep packs out of MEMFS between sessions.** Store downloaded packs in the Cache API or OPFS from JavaScript and write only the packs this session mounts into a non-persistent MEMFS folder (for example `/tmp/packs`), so startup no longer copies the whole IndexedDB store into memory. **Saves up to the whole cache (up to about 970 MB on a well-travelled device, 66 MB after this tour) at every start.** Mounted packs still cost their size for the session; Godot cannot unmount a pack, so the remaining win is mounting fewer (thumbnails below prefetch whole sprite packs).
5. **Texture budget (LRU) for sprite sheets.** Evict `SheetFrames` sheets (and the AtlasTextures in `battle_view.textures` and `AnimatedPortrait._textures` that keep them alive) beyond a byte budget, say 64 to 128 MB; clear `battle_view.textures` on `close_battle`. Budget `game.textures` by bytes rather than 4,000 entries. **Bounds a long 后台搜宠 session** (today about 10 MB per new species forever); little change in this short tour.
6. **Palette (R8) textures plus a palette shader.** Import sheets as 1 byte a pixel (`Image.FORMAT_R8` or L8) with a 256 x 1 palette texture and a `canvas_item` shader that looks up the colour. **Cuts every sheet's GPU memory by 4** (battle sheets 6.5 GB to 1.6 GB in total; 63 MB to about 16 MB in this tour) and also the web packs (the build stores RGBA today). Needs changes in `SheetFrames`, the thumbnail cutter and every node that draws sheet frames.
7. **Pre-cut thumbnails at import.** Write one small still per species (or one atlas) in `tools/import_encounter_art.py` so 宠物大全 never loads and reads back whole sheets. **Removes about 120 MB of static peak, about 250 MB of footprint churn and about 80 MB of driver memory per scroll**, and on the web avoids prefetching every sprite pack (this tour mounted 118 more packs, about 80 MB, during and after one scroll).

Items 1 to 3 are cheap. By these measurements they would take startup from 360 MB to roughly 200 MB of static memory and keep the web heap under about 400 MB instead of 805 MB (an estimate; re-measure).

## After the pack store (optimization 4)

Packs are cached by the page in an IndexedDB database of its own (`web/pack_store.js`) instead of `user://`, and only the packs a session mounts are written into MEMFS (`/tmp/packs/`, not persisted). The first visit after the update deletes the old `user://packs/` from IDBFS before the engine reads it. Details in [web client](web-client.md#pack-cache).

Measured with `tools/web_pack_cache_probe.mjs` (headless Chrome for Testing with SwiftShader, 10 to 18 fps; macOS, 2026-09-30; before = the web build served from `main` just before this change). "Full cache" plants all 1,849 packs (913 MB) in IDBFS the way the old build stored them, as on a browser that has been everywhere; each visit is a new browser on the same profile. Playable = the waiting screen is gone and the village is built; prefetch = the neighbouring maps' packs are mounted too. MB.

| Visit | Game code starts | Playable | Prefetch done | JS heap | Page renderer footprint | wasm heap | Pack requests |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Before, full cache | 6.0 to 6.9 s | 6.1 to 6.9 s | 6.1 to 7.0 s | 952 to 993 | 1,347 to 1,875 | 138 | 0 |
| After, first visit after the update (full old cache) | 5.1 s | 7.5 s | 61.5 s | 57 | 451 | 166 | 271 (28 MB) |
| After, later visits | 5.4 to 5.6 s | 5.5 to 6.6 s | 9.4 to 9.6 s | 53 to 57 | 395 to 450 | 138 | 0 |
| Before, first visit ever | 5.1 s | 6.5 s | 30.5 s | 62 | 571 | 166 | 271 |
| After, first visit ever | 5.1 to 5.2 s | 6.4 to 7.4 s | 52.5 to 62.4 s | 54 to 55 | 448 to 566 | 166 | 271 |

- **Memory:** with a full cache the old build held the whole cache as JS memory (about 950 MB of JS heap, 1.3 to 1.9 GB page renderer) on every start. Now a start holds only what it mounts: about 55 MB of JS heap and 400 to 450 MB page renderer, the same as a browser with no cache at all. On the web the IndexedDB copy costs disk, not memory.
- **Startup time:** in Chrome the engine reached game code 1 to 1.5 s sooner with a full cache (the IDBFS copy is gone). Safari was not measured; the stall reported there on 正在读取素材索引 was the same IDBFS copy, which is larger there relative to its speed.
- **Warm reads:** a warm start reads 271 packs from the store in about 4 s of background time at these frame rates (the village is playable before that). Reading through an `HTTPRequest` per pack (Godot advances one only once a frame) took about twice as long, hence the direct read.
- **No network:** later visits make no request for a cached pack. The first visit after the update downloads the packs it uses again (the old cache is deleted, not moved).
- **Not explained yet:** the first-ever visit's background prefetch took 52 to 62 s instead of 30 s in these runs (the same 271 packs over the same 4 connections; the time to playable did not change). Storing each response (a `clone()` read into a Blob and an IndexedDB write) is the likely cost; a version that passed the stream on without a clone was no faster. Worth a look on a real device before tuning.

## After packed maps (optimization 1)

Maps are now `world/<id>.map` files ([original data setup](../development/original-data-setup.md)): the small fields stay JSON, and ground, walkability and objects load straight into `PackedInt32Array` / `PackedByteArray` grids (`client/scripts/map_file.gd`). The ground layer shares that grid instead of keeping a string per cell, and the map window keeps an image id per cell instead of a `Color`. Same machine, same tour, both runs on 2026-09-30 (before = `main` at b1783aa).

### Desktop

| Step | Map | Static before | Static after | Static max before | Static max after | Footprint before | Footprint after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 01 startup: village | 1000 | 361 | 355 | 382 | 374 | 827 | 813 |
| 04 Samgir wilderness | 100 | 564 | 406 | 605 | 408 | 1,117 | 850 |
| 05 吉鲁岛 + walk | 300 | 478 | 386 | 667 | 412 | 1,064 | 868 |
| 06 map 200 | 200 | 681 | 431 | 816 | 436 | 1,331 | 912 |
| 07 back to map 100 | 100 | 573 | 408 | 871 | 441 | 1,161 | 913 |
| 08 battle open | 100 | 787 | 621 | 871 | 662 | 1,422 | 1,242 |
| 16 grid scrolled to the end | 100 | 861 | 696 | 989 | 823 | 2,068 | 1,812 |
| 21 all closed, village | 1000 | 610 | 603 | 989 | 823 | 1,093 | 1,328 |
| 22 3 more battles, village | 1000 | 610 | 603 | 997 | 823 | 1,326 | 1,370 |

| Map | JSON on disk | Parsed JSON (static) | `.map` on disk | Loaded `.map` (static) |
| --- | ---: | ---: | ---: | ---: |
| `world/200` | 15.2 | 196 | 5.1 | 9.5 |
| `world/100` | 9.4 | 125 | 3.3 | 7.2 |
| `world/300` (吉鲁岛) | 5.1 | 68 | 2.0 | 4.5 |
| `world/1000` | 0.5 | 7.3 | 0.2 | 2.2 |

- On a map, static memory is now 48 MB (map 100) to 73 MB (map 200) above the village instead of 200 to 320 MB. Most of what is left is the `AStarGrid2D` navigation grid, about 62 bytes a cell: 40 MB for map 100, about 60 MB for map 200. It is the next map cost to cut (a byte grid and a hand-written A*, or a grid limited to the reachable region).
- The map-switch peak is gone: the static maximum stays within 10 MB of the current value through all map changes (441 MB after visiting 200 and returning, was 871). The remaining peaks come from the riding manifest (first battle, +210) and the 宠物大全 thumbnails (+120).
- Footprint numbers after the tour are noisy (malloc keeps freed blocks); compare static memory.
- All 147 maps load the same ground, walkability and objects as their JSON (checked by hash once at conversion; `client/tests/map_file_test.gd` keeps checking maps 1000 and 1002 against `samgir.json` and `shop.json`, including paths).
- The character catalog (16 MB) and `backgrounds.json` (36 MB) are unchanged; they belong with optimization 2.

### Web

Built with `./scripts/build-web.sh`, same probe, ports 8796/8797. Map packs are 35 MB in all instead of 63 MB.

| Step | wasm heap before | wasm heap after | Page renderer footprint before | after |
| --- | ---: | ---: | ---: | ---: |
| 01 startup, first visit | 412 | 412 | 1,522 | 985 |
| 02 map 100 | 709 | 495 | 1,634 | 1,026 |
| 04 after the battle | 805 | 591 | 1,749 | 1,087 |
| 07 宠物大全 grid scrolled | 805 | 689 | 1,433 | 1,259 |
| 08 back in the village | 805 | 689 | 1,556 | 1,445 |
| 09 reload, second visit | 412 | 412 | 1,084 | 1,248 |

The wasm heap after the first map switch drops by 214 MB; after the tour it is 689 MB instead of 805, now set by the riding manifest and the thumbnails. Startup stays at 412 MB (the battle manifest). Renderer footprints vary a lot between headless runs.

## Re-running

- Desktop: the command above; compare the step table (`static_mb`, `static_max_mb`, `texture_mb`, `footprint_mb`) and the JSON costs printed at the end.
- Web: build, serve on your own ports, run the probe; compare `wasm_heap_mb`, `audio.alive_mb`, the page renderer's `largest_footprint_mb` and the reload row. Start the backend with a new save each time, and compare from step 02: a new character does not always start in the village.
- Results go to `build/` (ignored). Footprint numbers vary by 10 to 20% between runs (allocator caching, other processes); static memory and the wasm heap are exact.

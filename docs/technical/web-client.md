# Web client

The browser build (Godot 4.6 Web export, Compatibility renderer, single-threaded) is a remote client of the backend on the MacBook: it holds no rules or saves and downloads original assets only when it needs them. See [backend interface](backend-interface.md) for the protocol.

## Build and serve

```sh
./scripts/build-web.sh      # needs imported assets and the 4.6 web export templates
./scripts/serve.sh          # backend on :8781 and the page on :8780, same save as the desktop game
```

Open `http://<MacBook address>:8780/` on any device on the same network; `serve.sh` prints the address. The page connects to `ws://<page host>:8781`. Override with `?server=ws://host:port` or `?packs=<url>`. Quit the desktop game first; both would write the same save.

Rebuilds are incremental: the export imports only changed assets, and packs whose source files (including their imported copies) are unchanged are reused from the served set, so a code-only rebuild takes about 30 s instead of about 55 s. The fingerprints live in `build/web-packs/cache.json`; delete it to rewrite every pack. The page server can keep running during a build; the new build is swapped in only when complete, and clients pick it up on reload.

Export templates live in `~/Library/Application Support/Godot/export_templates/4.6.stable/`; only the `web_*` archives are needed.

## Asset packs

`tools/plan_web_packs.py` assigns every file under `client/assets/legacy` to exactly one pack, and `client/tools/build_web_packs.gd` writes each pack from the imported resources (the `.import` remap plus the converted file), so `load()` works unchanged once a pack is mounted.

| Pack | Contents | Needed when |
| --- | --- | --- |
| `loading` | The waiting screen's image and music (about 0.3 MB) | First, before core |
| `core` | Catalogs, UI, battle manifest/UI/audio, shared effects | Startup |
| `map-<id>` | One map's data, tiles and residents used nowhere else | Entering that map |
| `tiles-<hash>` | Tiles shared by several maps, grouped by the exact set that uses them | Entering any of those maps |
| `char-<id>` | One player character's walking art (villages that draw it depend on it too) | Startup, character change, those villages |
| `sprite-<id>`, `riding-<id>`, `bg-<n>` | Battle sprite and mounted composite (one sprite sheet each, see [sprite sheets](sprite-sheets.md)), battlefield | Opening a battle that shows them; pet menus; companions |
| `music-<name>` | One track of the music library (Ogg Vorbis) | Startup (village music), entering a map with it, the radio playing it |

Riding has one `riding-<id>` pack per imported composite, holding that composite's sprite sheet (241 with the 8.0 data, about 1 MB each; `tools/import_riding.py` packs a composite's frames into one lossless 256-colour sheet, split in two only past 4096 px); mounting and mounted battles wait for the ridden composite only. The riding manifest (3.5 MB JSON, about 0.3 MB gzipped) stays in core. Re-run `tools/import_riding.py` in a checkout before its next web build after the importer changes, since imported assets are not in Git.

A measured build (before all riding pairs were imported): 1,117 packs, 302 MB in total. First load transfers roughly 30 MB compressed (engine 9 MB, base pack with the Chinese font 14 MB, core 6 MB, starting map and character); a new wilderness area about 3 MB including prefetched neighbours; a battle about 3 MB the first time.

`client/scripts/asset_packs.gd` fetches `packs.json`, fetches up to four packs at once from the network (32 at once from the cache) under content-hashed names, mounts them with `ProjectSettings.load_resource_pack`, retries each fetch three times with backoff, and removes cached packs the index no longer names without reading them. Where packs are kept is up to its store: `client/scripts/pack_store.gd` for a native build started with `--asset-packs` (downloads straight into `user://packs/`, as before) and `client/scripts/web_pack_store.gd` in a browser (see Pack cache below). After entering a map it prefetches the packs of every map linked from it. The desktop game ships all assets locally, so every `ensure()` completes immediately. On the web, troop art availability comes from the pack index rather than local files.

## Pack cache

`user://` in a browser is Emscripten's IDBFS: at every start the engine copies the whole IndexedDB store into memory (MEMFS) before any game code runs, and only then writes changes back. Packs used to be cached there, so a browser that had been everywhere loaded up to the whole pack set (1,849 packs, about 920 MB) on every start and held it for the session, and the start stalled on the IndexedDB read. Packs now stay out of `user://`:

- **Stored by the page.** `web/pack_store.js` (loaded in `<head>` before the engine, export preset `html/head_include`, copied by `scripts/build-web.sh`) keeps packs in an IndexedDB database of its own, `stone-age-packs`, one Blob per content-hashed file name. Nothing reads it at startup.
- **Read from it.** For a pack the database holds (it lists its keys once, with the index), `web_pack_store.gd` asks the script to read it (`read`), and once the Blob is loaded takes the bytes in one piece (`JavaScriptBridge.eval` of `take`, a `Uint8Array` that arrives as a `PackedByteArray`) and writes them to the mount folder. No HTTP request is made: Godot advances an `HTTPRequest` only once a frame, and routing every cached pack through one roughly doubled how long a warm start took to mount its packs (headless Chromium, about 13 fps). A stored copy with the wrong size counts as missing and is downloaded again.
- **Stored on download.** Other packs download as before, with an `X-Stone-Age-Pack: <file> <bytes>` header. The script wraps `window.fetch`, which Godot's `HTTPRequest` uses: it removes the header before the request leaves the page (so a cross-origin `?packs=` server sees no extra header) and stores a complete 200 response of that size. The game's queue, retries, backoff, progress and four parallel downloads are unchanged.
- **Mounted from MEMFS outside IDBFS.** The pack is written to `/tmp/packs/`, which is not persisted, and mounted from there. Godot 4.6 reopens a mounted pack file for every resource it loads from it and cannot unmount one, so the file stays in memory until the page closes: only packs this session mounts cost memory.
- **Pruned by name.** After `packs.json` loads, the game lists the database's keys and deletes the files the index no longer names.
- **Old cache dropped once.** A build before the pack store left its packs in IDBFS (`user://packs/`, that is `/userfs/godot/app_userdata/<project name>/packs/`). On the first visit after the update, the page script opens that store before the engine does and, in one transaction, deletes every entry under `user://packs/`, walking keys only (no pack is read). The engine's own IDBFS read waits for that transaction, so even this first start does not load them. Those packs are not moved into the new store: moving means reading them all into memory, which is what made phones reload, or rewriting them all before the engine may start. So the first visit after the update downloads the packs it uses again (about 270 packs, 28 MB, for the start in Samgir), and later visits read them from the new store. `web_pack_store.gd` also deletes `user://packs/` in case the engine did read them (then they leave IDBFS at its next sync). Only `packs/` is touched; `viewer.cfg`, remembered logins and everything else in `user://` stay.
- **Why IndexedDB and not the Cache API.** `caches` exists only in secure contexts, and the LAN page is usually plain `http://`. IndexedDB works on both.
- **Fallbacks.** Without the page script (an old cached `index.html`) or without IndexedDB, packs are downloaded every visit and still mounted from `/tmp/packs/`. A browser may refuse to store a Blob (older WebKit): the script then stores an ArrayBuffer. A full quota makes a store fail silently (`window.stoneAgePackStore.errors`, `lastError`); the pack is still mounted and simply downloaded again next time. Safari's private windows keep IndexedDB only until the window closes, and Safari may delete a site's storage after about seven days without a visit, like any site data.

`window.stoneAgePackStore` shows `hits`, `misses`, `stored`, `oldDropped` and `errors` in Web Inspector; the 开发者性能面板 shows 缓存读取 next to 本次下载. Other `user://` contents on the web are small: `viewer.cfg` (viewer settings and remembered logins) and the engine's `shader_cache/`. Tests: `client/tests/asset_packs_test.gd` (the queue with a fake store: hits, misses, prune, retries, progress, parallelism, migration) and `tools/test_pack_store.py` (the page script under Node). `tools/web_pack_cache_probe.mjs` measures a start with a warm cache in Chromium; see [memory baseline](memory-baseline.md).

## Waiting screen

`client/scripts/waiting_screen.gd` covers any download the player waits for: the startup download (index, core, startup music, starting map and character) and later labelled waits such as entering a map or opening a battle whose packs are not cached. It shows the original `CG_TITLE_NOW_LOADING` art (graphic 29019, 640x480, letterboxed on its own dark red), plays the original `sabgm_s1` on a loop (bgm_tbl entry 2, which `login.cpp` plays after the character list downloads), and has a bar with what is downloading, MB done / total and a percentage from `AssetPacks.progress`.

- A wait must last 0.3 s before the screen appears, so cached packs never flash it. Background prefetches (no label) never show it. Startup holds it (`hold()` / `release()`) across the gaps between downloads; a failed startup download stays on it with the error.
- The full screen (art and waiting music) is for startup only. While it is up the game's music is paused; it resumes when the wait ends. The waiting music follows the game's volume and mute.
- Once the game has started (`enter_game()`), later waits show only a slim progress panel at the top centre over the running game: no art or backdrop, no waiting music, the area or battle music keeps playing, and clicks pass through.
- Browsers refuse audio until a gesture. Godot's web audio driver resumes its context on the first click, tap or key, so the screen shows 点击任意处开启音乐 until `navigator.userActivation` reports one.
- Both assets must exist before core, so they come from the `loading` pack, mounted first. Import them once with `.tools/asset-venv/bin/python tools/import_loading.py /path/to/stoneage2.5`; it writes `client/assets/legacy/loading/` (ignored like every original asset) and encodes the track to Ogg Vorbis like the music library below (1.3 MB WAV to about 360 KB), or copies the WAV (QOA, about 0.5 MB) without an encoder. It plays as a stream, and the screen lets go of it once the game has started. Without the import the screen still works, with the backdrop colour and no music.
- Desktop and the in-process game ship assets locally and never create it. The remote startup notice (正在连接 MacBook 上的服务器…) sits on the same art, lightly dimmed, whenever the image is available; the disconnection notice in play is unchanged.

`tools/serve_web.py` gzips the engine, scripts, JSON and packs (the core pack shrinks from 29 MB to 6 MB), marks hashed packs immutable and revalidates the rest. Gzipped responses omit `Content-Length`: Godot's web `HTTPRequest` counts the decoded body the browser hands it against that header and would otherwise never complete.

## Game controller

`client/scripts/gamepad.gd` works in every build (desktop and web) on top of the original mouse UI, without changing it.

| Button | World | Menus, battle, dialogue |
| --- | --- | --- |
| Left stick / D-pad | Walk | Move the yellow highlight to the nearest control in that direction |
| A | Talk to the villager or resident in reach, else walk to the nearest one | Click the highlighted control |
| B | Cancel | Close / back (same as Esc) |
| X / Y | Status / pets | Switch to status / pets |
| LB / RB | Zoom out / in | Previous / next page |
| Start | 设置 | 设置 |
| Back / View | Navigate the HUD and DEV buttons (Back or B returns) | |

A minimized 自动练级 / 自动抓极品 bar is not a menu: its 展开 button is reached with Back (HUD mode), and B / Esc leave the automation running. A click is a real mouse click at the control's centre, so battle commands, targets, pet rows and dialogue choices work unchanged; disabled controls are skipped and nothing depends on hover. `tests/gamepad_test.gd` plays walking, menus, paging, dialogue and a battle turn with simulated controller events only.

## Secure context and Vision Pro

Plain `http://` on the local network works in desktop Chrome. Some browser features, gamepad input among them in some browsers, require a secure context. For HTTPS:

```sh
brew install mkcert
./scripts/make-cert.sh     # project-only CA + certificate for <name>.local, the LAN address and localhost
./scripts/serve.sh         # now https://<name>.local:8780/ and wss://…:8781 automatically
```

Everything lives in the ignored `.tools/tls/`; nothing is added to the Mac's trust store. That folder exists only in the checkout where `make-cert.sh` ran: copy it into other checkouts and worktrees (`cp -c -R <checkout>/.tools/tls .tools/tls`) rather than rerunning the script there, which would create a new CA that devices must install again. Without it `serve.sh` warns and serves plain HTTP / WS, and `https://` pages or `wss://` clients cannot connect. Install the CA on Vision Pro once: AirDrop `.tools/tls/StoneAge-Local-CA.crt`, install it under Settings > General > VPN & Device Management, then enable it under Settings > General > About > Certificate Trust Settings. Prefer the `.local` name; rerun `make-cert.sh` if you use the IP and it changes. Keep `.tools/tls/ca/rootCA-key.pem` private: anyone with it can mint certificates this device trusts. Explicit `STONE_AGE_TLS_CERT` / `STONE_AGE_TLS_KEY` override the generated pair. Vision Pro Safari has not been tested yet; check loading, WebSocket connection, audio unlock and gamepad input there first.

## Music

Every original background track is imported once, into the music library `client/assets/legacy/music/` (`tools/import_music.py`, with `manifest.json`). Map music, battle music and the 电台 all play from it through `client/scripts/music_tracks.gd`; manifests elsewhere still name the original file (`world/audio/sabgm_f0.wav`, `battle/audio/sabgm_b0.wav`), which `MusicTracks.path()` maps to the library's copy by track id. Older imports' WAV copies are not shipped to the web (`plan_web_packs.py` lists them under `skipped`).

- **Format.** Ogg Vorbis q6 via libsndfile (`tools/music_codec.py`; the `soundfile` package in `tools/requirements.txt`, with ffmpeg's built-in encoder as a fallback). The originals are 22 kHz, mostly 8-bit, so this is about 80 to 130 kbps: 21.5 MB for all 26 tracks instead of 89 MB of WAV. The original WAVs stay in the extracted client (`.tools/legacy/extracted/`) for a possible lossless option later.
- **Loops.** The original WAVs carry a `smpl` loop, and `play_bgm` (`system/t_music.cpp`, `BGM_AUTO_LOOP`) ends the buffer at the loop end and jumps back to the loop start, so a track with an intro (sabgm_t0, t1, f0, f1, d2, b1, s1) plays the intro once. The encoder cuts each file at the loop end and records `loop_start` in the manifest; `MusicTracks.prepare()` sets `AudioStreamOggVorbis.loop` and `loop_offset` (or a WAV's loop points). The radio counts its minimum play time with the shorter later loops.
- **Streamed on the web.** Godot 4.3+ plays audio on the web as "samples" by default: each stream is decoded whole into a Web Audio `AudioBuffer` of 32-bit floats (about 350 KB per second of stereo, whatever the file's compression) that lives as long as the stream. The music player and the waiting screen's player are made with `MusicTracks.music_player()`, which sets `playback_type = PLAYBACK_TYPE_STREAM`: the engine mixes the music itself in small chunks and sends them to its AudioWorklet. Sound effects stay samples (short, and they play without the worklet's latency).
- **Held.** Only what plays or is about to: the map's music (the previous map's is freed when the next starts; the village and wilderness music are kept as paths), the radio's current track and the one it fetched ahead (both let go when the radio turns off), and the scene music the radio will hand back to.
- **Trade-off.** This build has no thread support, so the stream path mixes on the main thread when the worklet asks for more. A main-thread stall longer than the worklet's buffer is a short gap in the music, where sample playback would have kept going. `client/project.godot` raises `audio/driver/output_latency.web` from Godot's 50 ms to 150 ms (Godot rounds the buffer to a power of two: 8,192 frames, about 170 ms at 48 kHz), so an ordinary hitch such as a window opening does not cut the music; a map's JSON parse still can. The only cost is that music starts and stops up to that much later. Effects are unaffected (samples do not go through the worklet).

After changing the music importer, re-import in that checkout (imported assets are not in Git):

```sh
.tools/asset-venv/bin/python -m pip install -r tools/requirements.txt
.tools/asset-venv/bin/python tools/import_music.py .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/import_loading.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/Godot.app/Contents/MacOS/Godot --headless --path client --import
```

The old copies (`client/assets/legacy/sabgm_t0.wav`, `sabgm_t1.wav`, `world/audio/sabgm_*.wav`, `mvp/audio/sabgm_f0.wav`, `battle/audio/sabgm_b0.wav` and `sabgm_s0.wav`) are no longer used or shipped once the library has the track; delete them with their `.import` files if you like. The importers no longer write them.

## Audio interruptions

Symptom (Vision Pro, reported): after stepping out of the environment, which makes visionOS pause media, the page stays silent until it is reloaded.

Likely cause (from the evidence below; not reproduced on a Vision Pro):
- WebKit moves a page's AudioContext to `suspended`, or the non-standard `interrupted`, when the system takes the audio session. It does not always come back on its own, and `resume()` only works from a user gesture and can be rejected.
- Godot 4.6's web audio (`GodotAudio.init` in the exported `index.js`) only knows `suspended`, `running` and `closed`: `interrupted` falls to `default` and is reported as suspended. `_godot_audio_resume()` calls `ctx.resume()` once, ignores a rejection, and does nothing when the context claims `running`. A rejected resume, or a context that reports running but lost its output, therefore stays silent.
- The page cannot reach Godot's context from outside the engine.

Fix: `web/audio_session.js`, copied next to `index.html` by `scripts/build-web.sh` and loaded in `<head>` before the engine (export preset `html/head_include`):
- wraps the `AudioContext` constructor to keep a reference to the engine's context, and reports every state change and page hide/show to the game;
- on every tap, click or key press while the context is not running: plays a short silent media element (reactivates the page's audio session in WebKit), calls `resume()` and plays a one-sample buffer; a failed resume is retried on the next gesture;
- after the page was hidden, the first gesture also plays the one-sample buffer, for a context that reports running but went silent;
- Media Session: system play/pause controls pause and resume the radio, and Now Playing shows the track as `石器时代 电台`.
- Audio session (Safari 16.4+ `navigator.audioSession`): `ambient` mixes with other apps' audio and video but is silenced by the iPhone's silent switch; `playback` plays through silent mode like a music app but stops other apps' sound. 游戏设定 「与其他声音同时播放」 picks it (`setMix`, kept in `localStorage` as `stoneAgeAudioMix`). The default is `playback` on iPhone and `ambient` everywhere else, so Vision Pro mixes with other media again (a fixed `playback` session, added for iPhone silent mode, had stopped that).

`client/scripts/web_audio.gd` makes the decisions: once the sound has run, any state other than `running` counts as an interruption and pauses the radio (`radio.interrupt`) with the note 系统暂停了声音，按播放继续。 播放 (a gesture) resumes the context and the radio. With the radio off, scene music simply continues once the context runs. It does nothing off the web.

Verified:
- `web_audio_test`: the decisions, with simulated states.
- `tools/test_audio_session.py`: the page script under Node with fake browser objects.
- Desktop Chrome against Godot's real engine context: the script wraps it, a script-side `suspend()` is reported, and the next tap brings it back to `running`.

Not verified: a real Vision Pro or iPhone interruption (Chrome never reports `interrupted`).

## Debugging

The web build sets `window.stoneAge` once a second (map, cell, connection, mounted and pending packs) and `window.stoneAgeDev(name)` runs DEV actions (`explore`, `encounter`, `escape`, `return`, `village`, `pets`), both usable from Safari's Web Inspector. With 开发者性能面板 open (F3), `window.stoneAgePerf` holds its latest sample (wasm heap, engine memory, asset packs); see [perf panel](perf-panel.md). Chrome pauses `requestAnimationFrame` in hidden or fully covered windows, which freezes a Godot page; an automated browser tab must be visible to run it.

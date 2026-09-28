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
| `sprite-<id>`, `riding-<id>`, `bg-<n>` | Battle sprite, mounted composite, battlefield | Opening a battle that shows them; pet menus; companions |
| `music-<name>` | One track | Startup tracks, entering a map with it |

A measured build: 1,117 packs, 302 MB in total. First load transfers roughly 30 MB compressed (engine 9 MB, base pack with the Chinese font 14 MB, core 6 MB, starting map and character); a new wilderness area about 3 MB including prefetched neighbours; a battle about 3 MB the first time.

`client/scripts/asset_packs.gd` fetches `packs.json`, downloads up to four packs at once into `user://packs/` (IndexedDB in a browser) under content-hashed names, mounts them with `ProjectSettings.load_resource_pack`, retries each download three times with backoff, and removes cached packs the index no longer names. After entering a map it prefetches the packs of every map linked from it. The desktop game ships all assets locally, so every `ensure()` completes immediately. On the web, troop art availability comes from the pack index rather than local files.

## Waiting screen

`client/scripts/waiting_screen.gd` covers any download the player waits for: the startup download (index, core, startup music, starting map and character) and later labelled waits such as entering a map or opening a battle whose packs are not cached. It shows the original `CG_TITLE_NOW_LOADING` art (graphic 29019, 640x480, letterboxed on its own dark red), plays the original `sabgm_s1` on a loop (bgm_tbl entry 2, which `login.cpp` plays after the character list downloads), and has a bar with what is downloading, MB done / total and a percentage from `AssetPacks.progress`.

- A wait must last 0.3 s before the screen appears, so cached packs never flash it. Background prefetches (no label) never show it. Startup holds it (`hold()` / `release()`) across the gaps between downloads; a failed startup download stays on it with the error.
- While it is up the game's music is paused; it resumes when the wait ends. The waiting music follows the game's volume and mute.
- Browsers refuse audio until a gesture. Godot's web audio driver resumes its context on the first click, tap or key, so the screen shows 点击任意处开启音乐 until `navigator.userActivation` reports one.
- Both assets must exist before core, so they come from the `loading` pack, mounted first. Import them once with `.tools/asset-venv/bin/python tools/import_loading.py /path/to/stoneage2.5`; it writes `client/assets/legacy/loading/` (ignored like every original asset) and transcodes the track to Ogg Vorbis with ffmpeg's built-in encoder (1.3 MB WAV to about 260 KB), or copies the WAV (QOA, about 0.5 MB) without ffmpeg. Without the import the screen still works, with the backdrop colour and no music.
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
| Start | Help | Help |
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

## Debugging

The web build sets `window.stoneAge` once a second (map, cell, connection, mounted and pending packs) and `window.stoneAgeDev(name)` runs DEV actions (`explore`, `encounter`, `escape`, `return`, `village`, `pets`), both usable from Safari's Web Inspector. Chrome pauses `requestAnimationFrame` in hidden or fully covered windows, which freezes a Godot page; an automated browser tab must be visible to run it.

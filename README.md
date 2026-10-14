# Project Stone Age

English | [简体中文](README.zh-CN.md)

A restoration of the classic MMORPG **石器时代 (StoneAge)** as a Godot 4.6 game, built around 萨姆吉尔村 / Samgir and the surrounding islands. It uses the original maps, sprites, menus, animations, music and sound effects, and follows the original server rules where the source is known.

Play it on a Mac, in a browser, on Vision Pro, or on several devices at once against one backend running on your Mac. See the [feature guide](docs/development/feature-guide.md) for what is restored.

It runs on your phone too: open the web page in your phone's browser.

<table>
  <tr>
    <td width="33%"><img src="docs/screenshots/marina-village.png" alt="玛丽娜丝渔村"><br>玛丽娜丝渔村 / Marina village</td>
    <td width="33%"><img src="docs/screenshots/pet-status.png" alt="Pet page"><br>宠物 / Pet page</td>
    <td width="33%"><img src="docs/screenshots/map-navigation.png" alt="Map navigation"><br>地图导航 / Map navigation and fast teleport</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/pet-comparison.png" alt="Pet comparison"><br>同种比较 / Pet comparison</td>
    <td><img src="docs/screenshots/game-helper.png" alt="Game helper"><br>游戏助手 / Game helper</td>
    <td><img src="docs/screenshots/auto-pet-hunt.png" alt="Auto pet hunt"><br>自动抓极品 / Auto pet hunt</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/leveling-teleport.png" alt="Leveling teleport"><br>刷怪传送 / Leveling teleport</td>
    <td><img src="docs/screenshots/pet-encyclopedia.png" alt="Pet encyclopedia"><br>宠物大全 / Pet encyclopedia</td>
    <td><img src="docs/screenshots/auto-leveling.png" alt="Auto leveling"><br>自动练级 / Auto leveling</td>
  </tr>
  <tr>
    <td colspan="2" align="center"><img src="docs/screenshots/vision-pro.png" alt="Apple Vision Pro" width="100%"><br>Apple Vision Pro</td>
    <td align="center"><img src="docs/screenshots/phone.png" alt="Phone" height="340"><br>手机 / Phone</td>
  </tr>
</table>

## Setup: one command

The original game data is not in this repository. One script downloads and imports everything a working checkout has, including the web client:

```sh
./scripts/setup-original-data.sh
```

Before downloading it lists each download with its size and the disk space needed, and asks (`--yes` skips the question, `--dry-run` only prints). Everything: 2.1 GB of downloads and about 9 GB on disk. It verifies, extracts and imports, skipping whatever is already done, so an interrupted run resumes.

| What | From |
| --- | --- |
| Godot 4.6 and its web export templates (only the 39 MB of web templates are fetched) | [godotengine/godot releases](https://github.com/godotengine/godot/releases/tag/4.6-stable) |
| The StoneAge 2.5 client (553 MB) and the 8.0 client's data (1.2 GB), checked against recorded SHA-256s | [99ds.com](https://99ds.com/) → `downloads/windows/` |
| The original server data and client source the importers read | [chenmingbiao/stone-age](https://github.com/chenmingbiao/stone-age) and [anson1788/stoneage](https://github.com/anson1788/stoneage), at the revisions pinned in [local-references.json](docs/reverse-engineering/local-references.json) |
| Python tools (Pillow, soundfile) | `tools/requirements.txt`, into `.tools/asset-venv` |

Then it builds the pet hunt's [本机极速模式](docs/technical/fast-hunt.md) helper (when a C compiler is present), runs Godot's first asset import and builds the web client.

Options:

- `--no-8.0` skips the 8.0 data: 313 pet battle sprites, the later certificate mounts and two radio tracks are then missing.
- `--no-web` skips the web export templates and the web build.
- `--import-only` re-runs the importers, for example after an importer changes (a plain rerun also re-imports when an importer changed).

The first run takes about half an hour on a recent Mac, plus the downloads. Needs `curl`, `git`, Python 3.10+ and `bsdtar` (built into macOS; `libarchive-tools` on Linux); a C compiler (`cc`, built into macOS) is optional. **Windows:** use WSL2 or Git Bash, see [Windows setup](docs/development/original-data-setup.md#windows). Downloaded executables are never extracted or run. Details, sizes, checksums and manual steps: [original data setup](docs/development/original-data-setup.md).

The client data is community-distributed proprietary game data of unverified lineage. Keep it local: imported assets are gitignored, and none of it may go into a public release without resolving its distribution status.

## Play

### On this Mac

```sh
./scripts/run.sh
```

Or double-click **Play Stone Age.command**, or open `client/project.godot` in Godot 4.6. The game keeps its own rules and save.

### With a backend: browser, Vision Pro, several devices

The game's rules, automation and save can run in a headless backend on your Mac, so auto-battles and pet hunts keep running with no window open, and any number of devices can play the same character at once.

```sh
./scripts/build-web.sh     # once, and after code changes (about 30 s)
./scripts/serve.sh         # backend on :8781, web page on :8780
```

- **Browser:** open the address `serve.sh` prints. The page downloads original assets as it needs them and caches them.
- **Desktop client:** `./scripts/run.sh -- --server=wss://127.0.0.1:8781` (or `ws://` without a certificate).
- **Vision Pro and other devices** need HTTPS: run `./scripts/make-cert.sh` once and install its certificate on the device ([steps](docs/technical/web-client.md#secure-context-and-vision-pro)).
- **Over Tailscale:** `./scripts/relaunch.sh` rebuilds, restarts the server and forwards it to `https://<your Mac>.<tailnet>.ts.net:8780/`; Ctrl-C stops it all.

Quit the standalone desktop game before starting `serve.sh`; both would write the same save. More: [web client](docs/technical/web-client.md), [backend interface](docs/technical/backend-interface.md).

### Controls

| Control | Action |
| --- | --- |
| Left click | Walk to a tile; click a villager to walk over and talk |
| WASD / arrow keys | Walk (combine for eight directions) |
| Mouse wheel, + / − | Zoom 10% to 200% (also the slider in **设置 → 画面**; remembered per device, a new device starts at 100%) |
| Hover the bottom edge | Original menu tabs: status, pets, items, map; 系统 opens **设置** |
| M | Map window, with **地图导航** and **刷怪传送** below it (Ctrl+M works too) |
| G | **游戏助手**: 自动练级, 自动抓极品, 宠物 · 同种比较, 电台, 地图导航, 刷怪传送, GM 调试 |
| Esc | Closes the top window; with none open, opens **设置** |
| Battle icons | Choose a command, then its target, then your pet's command; right click or Esc cancels |
| E / X | Wave / sit or stand |
| Tab | Choose a character |
| H | 操作说明 in **设置** |
| R | Return to the village square |
| Game controller | Supported everywhere, including menus and battles ([layout](docs/technical/web-client.md#game-controller)) |

### First steps

Walk out through the village's west exit (or use **地图导航**), weaken a wild pet and capture it, and win some battles. 蓝人龙、金虎 and 红暴龙 join you on first launch; ride one from the pet window.

The only button of this project on the game screen is **游戏助手 [G]** (top left). This project's windows open from it and from **设置** (Esc): zoom, sound and 电台, character, 瞬移, saving, 快捷键 (every shortcut can be rebound per device), changelog, 操作说明, and GM tools under 开发者. See the [feature guide](docs/development/feature-guide.md).

## Development

```sh
./scripts/test-all.sh      # every Godot suite in parallel (about a minute)
.tools/asset-venv/bin/python -m unittest discover -s tools -p 'test_*.py'
```

Tests run headless and muted and need the imported assets. Read [AGENTS.md](AGENTS.md) before contributing (commit style, changelog and versioning, landing branches). Design notes and evidence live in [docs/](docs/README.md).

| Path | Contents |
| --- | --- |
| `client/` | The Godot project: game, backend (`client/server/`), network layer and tests |
| `tools/` | Importers for the original data and their tests |
| `scripts/` | Setup, run, test, build and serve helpers |
| `docs/` | Design, reverse-engineering evidence and development notes |
| `references/`, `.tools/` | Ignored: upstream source checkouts, engine, original client data |

The bundled Noto Sans SC font is distributed under its included OFL license.

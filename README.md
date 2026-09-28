# Project Stone Age

A restoration of the classic MMORPG **石器时代 (StoneAge)** as a Godot 4.6 game, built around 萨姆吉尔村 / Samgir and the surrounding islands. It uses the original maps, sprites, menus, animations, music and sound effects, and follows the original server rules where the source is known.

Play it on a Mac, in a browser, on Vision Pro, or on several devices at once against one backend running on your Mac. See the [feature guide](docs/development/feature-guide.md) for what is restored.

## Setup: one command

The original game data is not in this repository. One script downloads and imports everything:

```sh
./scripts/setup-original-data.sh
```

It downloads, verifies and imports, skipping whatever is already done:

| What | From |
| --- | --- |
| Godot 4.6 (macOS; on Linux install it yourself as `godot`) | [godotengine/godot releases](https://github.com/godotengine/godot/releases/tag/4.6-stable) |
| The StoneAge 2.5 client (about 550 MB, checked against a recorded SHA-256) | [99ds.com](https://99ds.com/) → `downloads/windows/Stoneage2.5-Windows.rar` |
| The original server data and client source the importers read | [chenmingbiao/stone-age](https://github.com/chenmingbiao/stone-age) and [anson1788/stoneage](https://github.com/anson1788/stoneage), at the revisions pinned in [local-references.json](docs/reverse-engineering/local-references.json) |
| Python tools (Pillow) | `tools/requirements.txt`, into `.tools/asset-venv` |

Options:

- `--web` also installs the Godot web export templates, needed to build the browser version.
- `--with-8.0` also fetches the StoneAge 8.0 client data (1.2 GB) from the same site, which has graphics the 2.5 client lacks.
- `--import-only` re-runs the importers, for example after an importer changes.

The first run takes a while: roughly 15 minutes of importing on top of the downloads. Needs `curl`, `python3`, `git` and `bsdtar` (built into macOS; `libarchive-tools` on Linux). Downloaded executables are never extracted or run. Details, checksums and manual steps: [original data setup](docs/development/original-data-setup.md).

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
| Mouse wheel, + / − | Zoom |
| Hover the bottom edge | Original menu tabs: status, pets, items, map, system |
| Ctrl+M | Map window |
| Battle icons | Choose a command, then its target, then your pet's command; right click or Esc cancels |
| E / X | Wave / sit or stand |
| Tab | Choose a character |
| M | Mute |
| H / Esc | Help (music volume is there) |
| R | Return to the village square |
| Game controller | Supported everywhere, including menus and battles ([layout](docs/technical/web-client.md#game-controller)) |

### First steps

Click the villager, choose **村外的伙伴 / 休息** and accept the quest. Head out through **村外探险**, weaken a wild pet and capture it, win three battles, then use **DEV → 挑战强敌** in the wilderness for the finale and return for your reward. 蓝人龙、金虎 and 红暴龙 join you on first launch; ride one from the pet window.

The **DEV** bar has map travel, automation (**自动练级**, **自动抓极品**), GM tools and the in-game changelog. See the [feature guide](docs/development/feature-guide.md).

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

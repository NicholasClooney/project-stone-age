# Project Stone Age

[English](README.md) | 简体中文

用 Godot 4.6 复刻经典网游**石器时代 (StoneAge)**，以萨姆吉尔村和周边岛屿为中心。使用原版的地图、精灵图、菜单、动画、音乐和音效；原版服务器规则有来源可查的，都照原版做。

可以在 Mac、浏览器、Vision Pro 上玩，也可以多台设备同时连到 Mac 上跑的同一个后端。已经复原了哪些内容，见[功能指南](docs/development/feature-guide.md)。

<table>
  <tr>
    <td width="33%"><img src="docs/screenshots/marina-village.png" alt="玛丽娜丝渔村"><br>玛丽娜丝渔村</td>
    <td width="33%"><img src="docs/screenshots/pet-status.png" alt="宠物"><br>宠物</td>
    <td width="33%"><img src="docs/screenshots/map-navigation.png" alt="地图导航"><br>地图导航与快速传送</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/pet-comparison.png" alt="同种比较"><br>同种比较</td>
    <td><img src="docs/screenshots/game-helper.png" alt="游戏助手"><br>游戏助手</td>
    <td><img src="docs/screenshots/auto-pet-hunt.png" alt="自动抓极品"><br>自动抓极品</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/leveling-teleport.png" alt="刷怪传送"><br>刷怪传送</td>
    <td><img src="docs/screenshots/pet-encyclopedia.png" alt="宠物大全"><br>宠物大全</td>
    <td><img src="docs/screenshots/auto-leveling.png" alt="自动练级"><br>自动练级</td>
  </tr>
</table>

## 安装：一条命令

原版游戏数据不在这个仓库里。一个脚本就能下载并导入一份可用 checkout 需要的全部内容，包括网页客户端：

```sh
./scripts/setup-original-data.sh
```

下载前会列出每项下载的大小和所需磁盘空间，并先询问（`--yes` 跳过询问，`--dry-run` 只打印）。全部内容：下载 2.1 GB，占用磁盘约 9 GB。它会校验、解压、导入，已经做完的步骤会跳过，所以中断后重跑能接着做。

| 内容 | 来源 |
| --- | --- |
| Godot 4.6 及其网页导出模板（只下载 39 MB 的网页模板） | [godotengine/godot releases](https://github.com/godotengine/godot/releases/tag/4.6-stable) |
| 石器时代 2.5 客户端（553 MB）和 8.0 客户端的数据（1.2 GB），按记录的 SHA-256 校验 | [99ds.com](https://99ds.com/) → `downloads/windows/` |
| 导入器读取的原版服务器数据和客户端源码 | [chenmingbiao/stone-age](https://github.com/chenmingbiao/stone-age) 和 [anson1788/stoneage](https://github.com/anson1788/stoneage)，版本固定在 [local-references.json](docs/reverse-engineering/local-references.json) |
| Python 工具（Pillow、soundfile） | `tools/requirements.txt`，装进 `.tools/asset-venv` |

然后它会编译抓宠的[本机极速模式](docs/technical/fast-hunt.md)辅助程序（有 C 编译器时），运行 Godot 的首次素材导入，并构建网页客户端。

选项：

- `--no-8.0` 跳过 8.0 数据：会缺 313 个宠物战斗精灵图、后期的证书坐骑和两首电台曲目。
- `--no-web` 跳过网页导出模板和网页构建。
- `--import-only` 重新运行导入器，比如在导入器改动之后（直接重跑时，如果导入器改过也会重新导入）。

在较新的 Mac 上首次运行约半小时，另加下载时间。需要 `curl`、`git`、Python 3.10+ 和 `bsdtar`（macOS 自带；Linux 上是 `libarchive-tools`）；C 编译器（`cc`，macOS 自带）可选。**Windows：** 使用 WSL2 或 Git Bash，见 [Windows 安装](docs/development/original-data-setup.md#windows)。下载的可执行文件永远不会被解压或运行。细节、大小、校验和与手动步骤：[原版数据安装](docs/development/original-data-setup.md)。

客户端数据是社区流传的专有游戏数据，来源未经核实。请只留在本地：导入的素材都在 gitignore 里，在弄清分发权限之前，任何部分都不能放进公开发布。

## 游玩

### 在这台 Mac 上

```sh
./scripts/run.sh
```

或者双击 **Play Stone Age.command**，或者用 Godot 4.6 打开 `client/project.godot`。游戏自带规则和存档。

### 用后端：浏览器、Vision Pro、多台设备

游戏的规则、自动化和存档可以跑在 Mac 上的无界面后端里，这样不开窗口时自动战斗和抓宠也会继续，任意多台设备可以同时玩同一个角色。

```sh
./scripts/build-web.sh     # 首次运行，以及改代码之后（约 30 秒）
./scripts/serve.sh         # 后端在 :8781，网页在 :8780
```

- **浏览器：** 打开 `serve.sh` 打印的地址。页面按需下载原版素材并缓存。
- **桌面客户端：** `./scripts/run.sh -- --server=wss://127.0.0.1:8781`（没有证书就用 `ws://`）。
- **Vision Pro 和其他设备**需要 HTTPS：运行一次 `./scripts/make-cert.sh`，然后在设备上安装它生成的证书（[步骤](docs/technical/web-client.md#secure-context-and-vision-pro)）。
- **通过 Tailscale：** `./scripts/relaunch.sh` 会重新构建、重启服务器，并转发到 `https://<你的 Mac>.<tailnet>.ts.net:8780/`；Ctrl-C 全部停止。

启动 `serve.sh` 前请先退出单机桌面版游戏，否则两边会写同一个存档。更多：[网页客户端](docs/technical/web-client.md)、[后端接口](docs/technical/backend-interface.md)。

### 操作

| 操作 | 作用 |
| --- | --- |
| 左键 | 走到某格；点村民会走过去对话 |
| WASD / 方向键 | 行走（组合可走八个方向） |
| 鼠标滚轮、+ / − | 缩放 10% 到 200%（也可以用**设置 → 画面**里的滑块；按设备记住，新设备从 100% 开始） |
| 鼠标移到底边 | 原版菜单标签：状况、宠物、道具、地图；系统打开**设置** |
| M | 地图窗口，下方有**地图导航**和**刷怪传送**（Ctrl+M 也可以） |
| G | **游戏助手**：自动练级、自动抓极品、宠物 · 同种比较、电台、地图导航、刷怪传送、GM 调试 |
| Esc | 关闭最上层窗口；没有窗口时打开**设置** |
| 战斗图标 | 先选指令，再选目标，再选宠物指令；右键或 Esc 取消 |
| E / X | 挥手 / 坐下或站起 |
| Tab | 选择角色 |
| H | **设置**里的操作说明 |
| R | 回到村子广场 |
| 游戏手柄 | 全面支持，包括菜单和战斗（[按键布局](docs/technical/web-client.md#game-controller)） |

### 第一步

从村子西边出口走出去（或者用**地图导航**），把野生宠物打残后抓住，再打赢几场战斗。首次启动时蓝人龙、金虎和红暴龙会加入你；在宠物窗口里可以骑乘。

游戏画面上属于本项目的按钮只有左上角的**游戏助手 [G]**。本项目的窗口都从它和**设置**（Esc）打开：缩放、声音和电台、角色、瞬移、存档、快捷键（每个快捷键都能按设备重新绑定）、更新日志、操作说明，以及开发者下的 GM 工具。见[功能指南](docs/development/feature-guide.md)。

## 开发

```sh
./scripts/test-all.sh      # 并行跑全部 Godot 测试套件（约一分钟）
.tools/asset-venv/bin/python -m unittest discover -s tools -p 'test_*.py'
```

测试以无界面、静音方式运行，需要已导入的素材。贡献前请先读 [AGENTS.md](AGENTS.md)（提交风格、更新日志和版本、分支合入）。设计笔记和证据在 [docs/](docs/README.md)。

| 路径 | 内容 |
| --- | --- |
| `client/` | Godot 项目：游戏、后端（`client/server/`）、网络层和测试 |
| `tools/` | 原版数据的导入器及其测试 |
| `scripts/` | 安装、运行、测试、构建和服务脚本 |
| `docs/` | 设计、逆向工程证据和开发笔记 |
| `references/`、`.tools/` | 被忽略：上游源码 checkout、引擎、原版客户端数据 |

附带的 Noto Sans SC 字体按其附带的 OFL 许可证分发。

---
subject: "feat(tools): set up everything by default and support Windows"
title: "一键完整安装，支持 Windows"
---

- 开发者工具：./scripts/setup-original-data.sh 默认安装一切：8.0 资料（更多宠物战斗图、后期骑宠、电台 26 首）、网页导出模板和网页版、本机极速模式辅助程序和 Godot 资源导入。可用 --no-8.0、--no-web 跳过。
- 开发者工具：下载前列出每项下载的大小（全部约 2.1 GB）、安装后占用的硬盘（约 9 GB）和剩余空间，确认后才开始；--yes 不再询问，--dry-run 只看清单。中断后重跑会接着下载，导入程序没有变化时不重新导入。网页导出模板只下载需要的 39 MB，不再下整个 1.25 GB 的模板包。
- 开发者工具：Windows 上可以用 WSL2 或 Git Bash 安装和运行，见 docs/development/original-data-setup.md 的 Windows 一节。装有 MinGW-w64 gcc 时 Windows 版也能用本机极速模式；没有编译器时照旧用 GDScript 搜索。尚未在真正的 Windows 电脑上测试。

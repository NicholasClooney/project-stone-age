---
subject: "feat(server): play against a headless backend over WebSocket"
title: "MacBook 后台服务与远程连接"
---

- 游戏规则、自动练级、抓宠流程和存档改由后台负责；桌面版照常游玩，行为不变。
- 开发者功能：运行 scripts/serve.sh 可在 MacBook 上单独启动后台，关闭游戏窗口后自动练级仍会继续。
- 用 scripts/run.sh -- --server=ws://127.0.0.1:8781 连接后台；断线后会自动重连，并显示离线期间的战斗、等级和新伙伴。
- 尚未完成：网页版、按需下载素材和手柄操作；Vision Pro 尚未实机验证。

---
subject: "feat(web): browser client with on-demand original asset packs"
title: "网页版（按需下载素材）"
---

- 新增网页版：运行 scripts/build-web.sh 生成后，用 scripts/serve.sh 在 MacBook 上启动，同一 Wi-Fi 的浏览器打开 http://<MacBook地址>:8780 即可游玩。
- 首次只下载核心素材；进入新地图、开始战斗、查看宠物时才下载对应素材，并预先下载相邻地图。已下载的素材会缓存在浏览器，再次进入不再下载；失败会自动重试。
- 网页版由 MacBook 后台负责规则与存档，关闭网页后自动练级仍会继续。
- 尚未完成：手柄操作；Vision Pro 尚未实机验证。

---
subject: "perf(client): use shared palette atlases for pet thumbnails"
title: "宠物大全缩略图省显存"
---

- 游戏设定 → 画面 → 调色板贴图（省显存）开启时，宠物大全全部缩略图使用共享调色板和最近邻缩放，图像边缘更锐利；关闭立即恢复原来的 Lanczos 缩略图和线性过滤。
- 宠物大全的网格、列表与变色详情随开关即时切换；Web 按当前模式下载对应缩略图包。此为客户端优化，不改变原版宠物素材或数值。

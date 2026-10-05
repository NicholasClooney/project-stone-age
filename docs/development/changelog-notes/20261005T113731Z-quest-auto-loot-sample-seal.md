---
subject: "fix(quest-auto): seal internal loot attempt sampling and progress publication"
title: "完善尚未开放的刷物底座"
---

- 完善尚未开放的刷物底座，防止旧操作的回调覆盖后来开始或保存的状态。
- 内部非战斗进度快照最多每秒更新一次，不为更新进度额外保存；这不代表界面已显示实时进度。
- 刷物公开入口仍未开放；真实客户端周期更新、战斗中的进度更新及目标物品完整战斗流程尚未验收。

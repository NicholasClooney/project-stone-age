---
subject: "fix(ui): gate loot budget panel on server capability"
title: "限时刷物面板遵从服务端开关"
---

- 限时刷物预算面板仅在服务端快照明确发布严格布尔值 `quest_loot_enabled: true` 时显示；字段缺失或格式错误时保持关闭。
- 能力关闭时，实际预算恢复锁仍以只读警告显示，原有任务状态和通用停止操作保持不变。
- 这项改动只控制界面显示，不开放刷物执行器或公开启动入口；相关功能仍未开放。

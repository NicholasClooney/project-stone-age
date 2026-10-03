---
subject: "fix(quests): avoid copying discarded NPC branches"
title: "减少任务目录筛选中的重复复制"
---

- 任务目录筛选普通 NPC 时，直接复制最终启用的分支，减少加载与任务助手更新中的重复处理。
- 保留原分支顺序、个人 NPC 状态与独立返回数据；特殊服务、任务条件、随机奖励和存档格式不变。

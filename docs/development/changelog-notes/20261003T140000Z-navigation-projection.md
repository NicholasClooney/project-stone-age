---
subject: "fix(quests): avoid unrelated NPC projections in navigation keys"
title: "减少任务助手移动更新的目录复制"
---

- 任务助手更新当前位置时，仅为风任务投影当前地图的 NPC；保留个人 NPC 移动、隐藏与近处交谈资格变化。
- 金布伊任务在无关地图直接返回原导航状态，减少跨地图行走时的重复计算；原路线、到达资格、奖励与随机规则不变。

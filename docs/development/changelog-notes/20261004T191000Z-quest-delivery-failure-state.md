---
subject: "fix(quests): retain strict delivery battle failure reasons"
title: "保留连续送物任务的战斗失败原因"
---

- 连续步行送物任务在沿途战斗未成功结束、战果保存失败或地图确认超时后，保留需玩家处理的状态和原因，供后台任务浮条显示。
- 普通战斗成功结算仍继续任务；任务正常完成与玩家主动停止仍保持停止状态，既有三项自动任务的失败策略不变。

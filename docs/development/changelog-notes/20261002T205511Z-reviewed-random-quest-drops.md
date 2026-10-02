---
subject: "fix(quests): verify static encounter drops against pinned source slots"
title: "核对静态任务的原随机掉落"
---

- 静态任务模块可声明原随机敌人的审定掉落，不再要求借用固定守卫；导入时核对原敌表物品、千分比与全部掉落槽，并保留源行和原字段。
- 未审物品、错误概率与遗漏掉落槽会拒绝导入；沿用服务器原随机数和保存失败重试。本次仅补公共导入接口，不单独开放四宝玉任务。

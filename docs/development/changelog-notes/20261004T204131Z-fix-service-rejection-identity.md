---
subject: "fix(quests): validate service identity after rejection checks"
title: "原任务服务异常输入处理"
---

- 修复原任务服务处理无效动作或缺失来源资料时的脚本异常，恢复明确拒绝结果；覆盖巴那姆水壶购买与金布伊服务边界。
- 通过服务规则与来源身份检查后才绑定自动任务事务，保留保存和取消后的对白保护。

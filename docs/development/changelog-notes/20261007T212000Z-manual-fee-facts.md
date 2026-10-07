---
subject: "feat(quests): publish typed manual fee commit facts"
title: "手动必需费用的结构化提交事实"
---

- 原200石币永久通行资格与300石币赛姆收费提交后，在同角色的 quest_result 中提供严格结构化事实，包含真实提交的金额、前后余额、归属与独立交易身份；原手动文本、原价、原 writer 均不变，Backend 未修改。
- 区分磁盘提交与仅内存成功，不伪造实体票 UID；失败或无法确认的结果不发布 committed 事实。真实 Session 已落盘但返回丢失仍按原 unknown 边界处理，本片没有修复交易恢复或承诺跨重启 exactly-once。
- 新事实测试及十套原 RequiredFee 回归通过，覆盖原 handler/token、提交后停止/owner后继、重复页、真实写入失败、unknown 和 profile 范围广播；认证 WebSocket、UI消费者和自动收费尚未由本片验证。
- 只提供现有手动收费两个 tag。Start journal、自动付款、44首票及 automatic 字段未接线；不注册 suite、不开放新能力。

---
subject: "fix(quest-auto): preserve revoked loot battle ownership on reconnect"
title: "断线后保留原单战结算归属"
---

- 修复内部刷物单战断线后，新设备的位置观察报告接管原执行归属、使待结算战斗失去有效归属的问题；原战仍只结算一次，观察报告不会重新授予执行权限。
- 此修复仅为尚未开放的自动刷物能力准备，不代表公开自动刷物已上线；普通任务重连保持原规则。

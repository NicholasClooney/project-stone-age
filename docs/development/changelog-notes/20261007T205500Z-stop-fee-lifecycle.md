---
subject: "chore(quests): wire guarded fee lifecycle Stop completion"
title: "费用任务 Stop 持久收尾候选（默认关闭）"
---

- 在存在匹配费用 journal 时，Stop 先使旧运行失效，再关闭 profile 主备并退休同归属 sidecar；保留其他 hunt/battle 内容。无费用记录与 persist=false 保留兼容路径，未开放自动购票或新增玩家入口。
- 修复 W1 已写入、W2 失败后的显式 Stop 重试：只允许当前 Stop claim 的同 owner/run、完整同字节 closed profile 补齐主备，不回滚已落盘事实，不将 unknown 当成功。
- 独立 Stop 测试 headless 自然通过 369 checks / 0 failures，包含 closed-retire、部分写入与重试、旧 owner/重入和 legacy 分支。完整日志及 210 项文件/目录证据保留于 `/private/tmp/tmux-agents/codex-2nd-projects-stone-age-1/stop-retry-exact-primary/`；历史 FAIL 不覆盖。
- Hub logout/switch/party_tick 尚未消费 Stop 结果；Start 尚未建立 fee journal；typed fee fact 合同尚未冻结。此片不代表完整自动收费或恢复流程可用，不注册 suite、不启用能力。
- 不承诺 profile/sidecar 跨文件原子提交或断电 fsync 耐久性。fixture 的初始 snapshot 迁移及人为 I/O 故障仅用于测试，未改变原售票/收费规则。

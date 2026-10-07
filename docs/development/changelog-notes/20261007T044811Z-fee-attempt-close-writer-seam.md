---
subject: "chore(test): add fee attempt close writer seam"
title: "内部关闭费用记录写盘接缝（未接线）"
---

- 增加供后续生命周期集成使用的内部 profile-pair close writer 接缝及故障测试。当前没有生产调用者、Stop/Start 接线、玩家命令或 RPC；未注册 suite、未开放能力。
- 定向 headless 测试自然退出，summary 为 0 failures。`UNRUN` 是测试保留的 summary 字面标签，不代表本次未执行。完整 user 盘、primary/backup 样本、双日志、source/cache 前后锁及 SHA 记录在 `/private/tmp/tmux-agents/quest-auto-v2-core/stop-lifecycle-357a/formal-close-runtime-argv-gated-20261007T043624Z/`。
- 当前 frame claim 只覆盖本接缝已验证的单向重入边界，不代表 attempt、sidecar 与 close 之间已有完整全局互斥。此结果不证明生产 Stop/Start、恢复或购票已接线。
- profile 与 sidecar 不具备跨文件原子提交保证；测试也不证明断电后的 fsync 耐久性。历史 setup 失败和 runner 的 `SystemExit: 0` 记账瑕疵均保留并在报告中注明。

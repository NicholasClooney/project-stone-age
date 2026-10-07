---
subject: "chore(server): add private fee-resume sidecar seam"
title: "费用恢复侧栏 I/O 验证接缝（未接线）"
---

- 增加仅供内部验证的费用恢复侧栏 I/O 接缝；当前没有生产调用者、命令或 RPC，也未注册测试 suite 或开放能力。
- Godot 4.6 headless 定向测试自然通过：195 项检查、0 failures。adult 与 wood checkpoint 是测试 fixture；native envelope 只接受已覆盖的有限 allowlist，拒绝未知 typed/Object 形状。
- 本次隔离 user 目录保留 52 个文件作为证据；完整报告、日志和逐文件 SHA 记录在 `/private/tmp/tmux-agents/quest-auto-v2-core/fee-resume-sidecar-seam/formal-run-wood-area-20261007T025243Z/run/`。
- 此测试不证明生产 Stop/Start 或购票恢复已接线，不保证断电后的 fsync 耐久性，也不声称 profile 与 sidecar 跨文件原子提交。此前解析及运行失败证据保持原样。

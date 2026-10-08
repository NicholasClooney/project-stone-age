---
subject: "test(quests): migrate natural pilot cold-load expectations"
title: "自然刷物试验冷退休断言迁移"
---

- 开发测试：旧三分钟与独立三十分钟 pilot 的完整冷加载预期迁移至保留原用时下界与收益的合同，随三十分钟入口一并保留四个支持文件。
- 两 pilot 本次仅 check-only 通过，没有自然运行；旧 480 秒超时仍为 UNCOMPLETE，未修复、未重跑，自然 P3 与实际收到 2760 仍为 UNPROVEN。
- 续段远程 UI 已独立定向 PASS；提交依赖前片仅为收片顺序，生产基底为 ceb58e1b。本片不注册测试、不改生产、不开放能力。

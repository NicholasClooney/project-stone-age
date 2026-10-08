---
subject: "test(quests): align continuation recovery oracle with cold retirement"
title: "刷物续段冷加载完整断言校准"
---

- 开发测试：续段远程 UI 定向测试通过；独立完整预期保留原预算上限、已存用时下界、已结算收益、UID，以及主备代次和实际 UI 边界。
- 冷退休仅结束旧时段，不刷新同一步剩余预算；本片不修改生产逻辑或开放刷物能力。
- 两份自然 pilot 仅通过 check-only；旧 480 秒超时仍为 UNCOMPLETE，未修复、未重跑，自然 P3 与实际收到 2760 仍为 UNPROVEN。

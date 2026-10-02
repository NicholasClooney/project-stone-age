---
subject: "fix(quests): verify golden Bui exits against active map points"
title: "核实金布伊原出口的实际传送来源"
---

- 金布伊810返回809及柜台重复入口保持原首条目标；补齐当前固定源码启用MapWarpPoint的实际事件路径证据。
- 开发导入时同时核对原mapwarp表和create候选；不一致则拒绝导入，避免静默改选出口。
- 审计结论限定于固定源码、宏和表，不代表核验未知历史服务器二进制。

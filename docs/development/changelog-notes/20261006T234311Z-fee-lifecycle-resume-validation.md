---
subject: "fix(server): validate fee lifecycle on resume"
title: "恢复自动任务前校验费用记录"
---

- 恢复自动任务前，服务器会核对已保存的费用生命周期记录与恢复意图；旧存档没有该记录时继续沿用原恢复路径。
- 新费用自动购买和完整 Stop/Start 持久化生命周期尚未开放；不改变原手动售票行为。

---
subject: "fix(clock): initialise the game clock before any script reads it"
title: "游戏时钟静态初始化：测试脚本早于 autoload 读取也拿到同一时钟"
---

- 开发者修正，玩家无感：`Clock` 的模式和起点改为静态初始化。此前在 ClockDriver 节点的 `_init` 里设置，测试脚本及其先构造的对象会在那之前读到真实时间，导致虚拟时钟下出现负的计时和错位的时间戳。真实游戏仍读真实时间，行为不变。

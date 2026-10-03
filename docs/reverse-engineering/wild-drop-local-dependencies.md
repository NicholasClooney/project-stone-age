# 野外任务掉落本地依赖并集

这是运行定向验收的依赖整合，不是新增任务政策；主线按原政策序列合入时不要重复取此提交。

- `client/server/quest_arrival_policy.gd`：原样取已提交 `b02cd66` 文件完整快照。包含先前已审各链规则，不自行重写。
- `client/server/quest_legitimate_arrival.gd`：仅取 `f3026a2` 的 `action_committed` 一行增量，向 `_queue_warp` 传 `Policy.action_mark(Policy.source(npc))`。保留本槽其余原实现。
- 下一依赖 `6af90df20c57195677e6ba590514addab1ba78af`：214 条精确任务野战掉落规则与 `wild_context/check_wild`。
- 本槽基线 `c55fd28548589f2a0e40d91cff98683f99c0e5ad`：实际服务器位置抽战权威。

规则源序列由 arrival owner 提供：`2618375 → 5161a11 → 6a9343a → f3026a2 → 7c8cc27 → 3f92f72 → c0907bc → 1cc65d0 → 49ef5c9 → 883bf9b → b4df5cf → 31f2fc1 → b02cd66`；已在本槽存在的等价实现不重取。完整原门运行另依赖 `188f648/0bb3ccf`，来源 fixture `c81b017/1825a7e`，本并集不声称代替这些实际门或全部链验收。

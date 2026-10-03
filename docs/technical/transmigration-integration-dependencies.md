# 第三阶段I并集依赖

结算底座原始hash：19a8b816840a771bf20d68eeb2d9a21b38ff6e8f，基线6da4b47。

当前本槽顺序取以下**原始提交**，不复制dirty：

| owner提交 | 本槽等价提交 | 内容 |
|---|---|---|
|9142f27a0d1459491867fec2e17b66f7a90e75db|a3bc1c29|纯继承与C oracle|
|443a70da059a3b04747d1dadbd7c00eb42412671|269f1959|全部纯规则与完整oracle矩阵|
|0f62cdec663ae12325203a7a4482b54ee19d17c6|268c201a|私有到达上下文/阶段空mapping|
|5d866f324a8958ebe67bca5038ba414d7f711b79|ff9d2448|忠诚/装备纯接口|

集成方已取原始提交时不重复取本槽等价。冲突仅生成日志/版本和suite注册行；保留所有新增suite并集，R未注册的transmigration_rules_test由I追加。没有改写依赖源规则或另造arrival实现。

I外围接线仅GameSession捕获前原主人count、统一_refresh_loyalty、原UID/legacy装备命令与骑乘前刷新，OriginalQuests奖励宠刷新；不改变loyalty/equipment所属模块实现。新rebirth_session_rules_test使用真实Session/Battle捕获结算、仓库及真实保存读回验证known legacy positive（不虚构自然历史）。零转仍拒Lv1高级装，正转BODY1052保UID/磨损及legacy互斥；仓库宠与战斗配置补偿一致，原VARIABLEAI债务不重写。

并集定向3/3：rebirth_session_rules_test、transmigration_rules_test、transmigration_migration_test，日志/private/tmp/stage-three-peripheral-integration.log，5秒/单并发。零转loyalty/spirits回归另见/private/tmp/stage-three-peripheral-regression.log。服务/真实NPC/LAN全矩阵仍是后续，不能以这几套代替完整转生闭环。

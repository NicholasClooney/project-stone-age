# Public corridor execution — first launch failure

唯一获准命令：`./scripts/run.sh --headless --script res://tests/quest_auto_public_corridors_execution_test.gd`，pool-b，外层60s。未启动 encounter/其它套/import/full，未自动重试。

- UTC开始：2026-10-04T17:12:03.350206+00:00。
- UTC结束：2026-10-04T17:12:04.394947+00:00。
- 实测wall：1.045s。
- 返回码：-6。Godot crash handler报signal11，栈为RotatedFileLogger::rotate_file → RotatedFileLogger构造 → Main::setup。
- 尚未进入suite；没有Godot脚本解析结果、断言数、逻辑格、模拟时间或任务收益。本次不能称测试绿，也不能据此判定生产导航失败。

证据：public-expansion-execution-first.log；public-expansion-execution-first-meta.json。原证据保留。

只读定位：scripts/run.sh 对测试自动指定 `$HOME/Library/Application Support/$STONE_AGE_TEST_USER_DIR/logs/godot.log`；本次工具以workspace-write沙盒启动，该Library目录不在可写roots中。启动日志路径权限与crash位置吻合，判为优先待验证的启动环境原因；尚未重试证明因果，不声称Godot自身缺陷已定位。下一次获准单套应以工具 require_escalated 启动同一命令，继续正常测试隔离，不改HOME/不改生产日志或测试覆盖。

client/.godot/imported在运行前已有完整目录，run.sh不会走缺目录import分支；此次进程直接在引擎setup退出。只读ps确认无本次suite进程。系统另外可见live server及两个已存在超过一天的editor/import进程（33909、93706），不是本次启动，不操作它们，也不据它们推测本次失败。

窗口已经立即notice释放。无生产/测试代码修改用于掩盖失败。遇敌子套继续等待独立授权窗口。

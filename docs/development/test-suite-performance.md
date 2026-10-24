# 全量测试耗时与提速方向

2026-10-24 调查与改造记录。供以后继续压缩全量测试时间时参考。

## 结构

- `scripts/test-all.sh` → `tools/run_suites.py`：每个 suite 一个独立 headless Godot 进程，默认 8 并行（`STONE_AGE_TEST_JOBS`），按 `build/test-durations.json` 最慢先跑（LPT），300 s 超时、30 s 停滞检测。
- `scripts/test.sh` 串行跑同一列表，只用于「第一个失败就停」。
- 当前约 629 个 suite。Godot 启动每 suite 不到 1 s，不是瓶颈；固定 sleep 合计不到 30 s，也不是。

## 2026-10-24 之前的瓶颈：等真实墙钟

- 走路类 suite 按原版 `STEP_TIME` 0.19 s/格真实走路线，headless 下每帧仍等 60 Hz。实测 `jan_cave_walking_test` 墙钟 76 s、CPU 22 s。
- 2 路并行的全量基线：624/624，10 210 s；各 suite 耗时总和约 20 400 s（5.7 h）。8 路理想值约 43 min，再加上与其他 agent、游戏服务器争 CPU，就是约 1 h。

## 2026-10-24 改造：虚拟时钟（v0.289.x）

- `scripts/run.sh` 给测试加 `--fixed-fps 60` 和 `STONE_AGE_TEST_CLOCK=virtual`；`client/scripts/clock.gd` 按帧累加，游戏代码经 `Clock.ticks_msec()` / `Clock.unix_time()` 读时间（规则见 AGENTS.md「Testing budget」）。
- 效果：等墙钟的 suite 快 2.5 到 5 倍（jan_cave_walking 76→18 s、saton_cave_walking 132→31 s、munde_cave_ui 264→49 s、transmigration_fire_ui 181→65 s、original_herb_auto 308→130 s、transmigration_water_ui 258→112 s）。
- 改造后首次 8 路全量（机器负载约 29，有其他 agent）：612/629，2 967 s（49 min）。17 个失败中 11 个是负载下超时、单独均通过；6 个真实问题当场修掉。
- 遗留：`clean_hunt_test` 在 `--fixed-fps` 下失败（与时钟无关，暂按真实时钟运行，待用户确认）；`quest_auto_loot_2760_natural_pilot_test` 及 heartbeat_cancel 变体两种时钟下都不稳，需重写。

## 现在的瓶颈：纯 CPU 的组合 suite 与并行度

1. **大组合 suite**。几十个 case 串在一个进程里，CPU 占用 90% 以上，假时钟无效：`quest_auto_loot_unified_resume_test`（65 case，约 450 到 800 s）、`quest_auto_loot_initial_failure_test`（56 case，约 200 到 420 s）、`fee_cold_lifecycle_test`（约 80 s）以及 fee_* 系列。单个 suite 只能用一个核，最长的一条决定了尾巴。
2. **并行度**。墙钟 ≈ 总 CPU 时间 ÷ 有效并发。机器 14 核，默认 8 路，但其他 agent 和游戏服务器抢 CPU 时实际远不到 8 核专用，超时也随之出现。

## 未来可做（按预期收益排序）

| 方向 | 做法 | 预期 | 风险 / 代价 |
|---|---|---|---|
| 拆组合 suite | 把 65/56 case 的 loot/fee suite 拆成 3 到 4 个文件 | 总算力不变，缩短最长尾巴，8 路下关键路径明显变短 | 每个约 0.1 到 0.2 SP；要保证 case 间无共享状态 |
| 减少每 case 算力 | profile 这些 case 是否重复建世界、全量存档，能否共用 fixture | 未知，需先 profile | 可能触及测试基础设施 |
| 动态并发 | `run_suites.py` 按 `os.getloadavg()` 调 jobs，空闲时用到 12 | 空闲时再省约 30% | 会拖慢用户的 live hunt；AGENTS.md 要求偏少 jobs |
| 按 diff 选 suite | 文件 → suite 映射，日常只跑相关 suite | 日常开发省最多，对整合全量无效 | 0.3 到 0.5 SP，映射需维护，可能漏跑 |
| `test.sh` 并行 fail-fast | 改为调用 `run_suites.py --fail-fast` | 避免误用串行跑 5.9 h | 0.1 SP |

不值得做：合并多个 suite 到一个进程（启动开销小，且失去隔离）、调 `wait.gd` 的 deadline（成功即返回）、删固定 sleep。

## 怎么量

- 全量前后对比 `build/test-durations.json`；跑全量前先 `uptime` 确认负载回落，全机同时只跑一个全量。
- 单 suite：`time ./scripts/run.sh --headless --script res://tests/<name>.gd`，对比 user CPU 与墙钟，差值就是空等。
- `STONE_AGE_TEST_REALTIME=1` 用真实时钟跑一个 suite，区分时钟问题与逻辑问题。

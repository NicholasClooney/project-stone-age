# B-only正式边界：PASS

唯一运行 quest_auto_public_corridors_b_boundary_test，继承原execution支持，只route("B")原全断言。28 assertions / 0 failures，exit0；未运行public25、未控A/C或其它套。

- UTC 2026-10-04T18:31:52.469602 → 18:31:59.629769。
- 进程wall7.160s；suite6.114s；B route6.027s。外层60/条件50未触及。
- Godot headless/muted，独立STONE_AGE_TEST_USER_DIR=Godot/app_userdata/Stone Age tests/pool-b-public-boundary-20261004。进程PID30267已退出，结束后立即向父释放窗口。
- 生产原依赖d758291738eab876420f8a3dd42475da120e2bf9 ← b5ec513c；测试入口/支持尚待最后测试片提交。

## 实际覆盖

真实job12 REQUEST与原村出口后，原当前目标选择public-v2-yam-mati；未改A/目标来命中。B一次public_jump准确落100(621,190)，prefix_max1。该落点scope=""、marks/stages/approach均空，与移动前基线完全相等，不以公开has_arrival真假代替proof断言。

完整ACK之前额外tick0.2，位置保持门外且field调用数不增加。随后发送带run/step/revision/segment/seq完整身份的实际ACK，正常继续：

1. 门外100(621,190)。
2. 原门独立邻格100(622,190)。
3. 下一原portal独立跨图1300(24,59)。

实际field_cells仅[100,621,190]、[100,622,190]，2次；public simulated_seconds0.200，仅为代表段模拟时间，不把7.160s wall称提速。door_walk、portal、ack_hold全部true。

正常停止并save_game，再独立Session.load_game读回真实events/items、completed_battles及实际保存location相等，不强写终点。

## 边界与注册

该新入口可进入正式注册候选，正式已绿入口数从9增为10。原execution整套两个A/C序列失败仍完整保留，不改成绿；execution/world_inputs仍为诊断支持不注册。此套不证明全部29实路，不代替公开25待验或九job覆盖说明。

证据同目录：public-expansion-b-boundary.log、-meta.json、-results.json（完整位置/field/实际plan/local_path/占格观察）。未重跑，未改生产，无其他测试进程由本任务启动。

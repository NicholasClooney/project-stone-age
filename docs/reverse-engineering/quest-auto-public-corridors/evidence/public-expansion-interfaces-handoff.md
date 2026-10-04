# 29新增走廊生产接口复验通过

## 原记录/窗口

分支feat/quest-auto-public-corridors，pool-b，基main b5ec513c。未混4a/4b或2b执行历史。
仅获准同套一次：`./scripts/run.sh --headless --script res://tests/quest_auto_public_corridors_interfaces_test.gd`。
wall **25.807s**、suite内部24717ms；**555断言、0失败、exit0**。结束后立即notice释放窗口，无遗留Godot。未串其它绿套/长路/full/import/check-only。
原日志：`public-expansion-interfaces-recheck.log`。
首轮17.428s/5失败的`public-expansion-interfaces-first.log`和first-handoff保留，不覆盖，不再将其12/12当有效数据。

## 修复及边界

这次仅测试改为真实NPC `sainasu/event/event02_1` 经 `npc_state.moved()`/`refresh_npc_state()` 进入门前占格，再同API移回，并验证production blocked没有残留。没有改生产缓存或A算法，没有删29候选/放宽断言。
移入后的生产validate_audit拒绝B落点、public_cell拒占格；移回后blocked无残留及后续29候选完整audit均通过，支持首轮fixture污染归因。

当前生产草稿只改public_routes并新增public_corridors；旧7固定条目保留，新增29，总36。未提交、未集成、未上线。
此前8个map300候选仍剔除，失败原因保持为无可用原A路径，未进一步宣称地图资源根因或恢复交通。

本次实际通过：
- 旧7的生产corridor几何存在，新增29的生产corridor/audit精确原后缀匹配。
- 新29的B/C validate_audit；B最后公开外格，door不得成为落点，原portal另一步。
- 五个原portal起点在起点audit为空、next_segment先返回有效walk，再几何推进一原格后审后缀。
- 伪造route末尾source拒绝；实时原door源改变→audit/validate拒绝，next_segment为walk或空；disabled使既发C失效；全部受审start来源改变时corridor拒绝。
- 真实NPC位移后的动态占格拒绝和恢复版本消除残留。
- 生产next_segment/validate_segment受中央C≤3限制；未审村内起点返回walk，未知地图返回空，不以B遮A失败。
- 海洞10201/10202/10203、成人10204、120/121口袋、20101、20401/20406、118/119/122、300双门approach/32001均不放行。

## 逐项next_segment命中（接口样例，不是任务收益）

24项public_stride且audit_id匹配：
1. yam-mati
2. mati-yam
3. mati-marju
4. marju-mati
5. samgir-yam
6. samgir-mati
7. yam-samgir
8. mati-samgir
9. marinas-kou
10. kou-marinas
11. marinas-saton
12. marinas-doctor
13. samgir-saton
14. samgir-doctor
15. jaja-goya
16. tamutamu-goya
17. karutana-goya
18. tamutamu-sea
19. karutana-jan
20. karutana-dragon
21. karutana-wood
22. jaja-karutana
23. karutana-jaja
24. forde-blue-cave

5项合法walk：sea-goya、goya-karutana、goya-jaja、sea-tamutamu、karutana-phoenix。
它们精确端点corridor/audit测试通过，但实际next_segment重新规划的当前前缀未获得审核快段；本轮日志未区分“改选邻门”与“等长路径重规划”等具体原因，不凭audit_id为空就断言换门。保持原A，不修改出口选择凑快移。后来路线是否会命中某一精确后缀，须后续真实执行记录。

## 仍待独立验证

尚无实际九job fast/protected_walk统计；24/5不等同任务提速数。连续job25必须fast0，旧洞口job24也可0；公开接近样例单列。
尚未在新段上跑真实runner的完整A/C序列、原遭遇每格/首次截尾、B不授scope/approach proof、ACK和任务完成事务；几何/接口绿不能替代这些。
开发reference地图SHA独立复算仍未增加新证据。长路线与实际执行suite要先报计划再排窗；此次不自行启动。
后续完整切片验证后再提交独立原hash，父integrate/full收口，已有绿2a不无故重复。

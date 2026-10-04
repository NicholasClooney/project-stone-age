# 金布伊只读自动计划（4b，尚未接线）

`quest_auto_golden_bui_plan.gd` 提供 `supports(job_id)` 与 `select(backend, job_id)`。
仅支持 job 2（原事件44），返回 `done`、`manual` 或含 `step` 的 `step` 状态。
本片没有注册自动入口，不执行对话、扣券、保存、传送、生成到达证明或领取奖励。
服务执行及每次事务重验由核心独占；完整库存闭环尚未实现。

## 受审源与提案

`quest_auto_golden_bui_sources.json` 固定44份原文件 SHA、39个公开 NPC 定义、
原14号奖励完整定义以及30条原楼梯。其全文 SHA 由同名 GDScript 和只读核验脚本独立固定。
静态表不含问题答案、题序、服务私有状态、token 或 RNG。
`tools/check_quest_auto_golden_bui_sources.py` 重新核对原文件 SHA、mapwarp/create 原行、
当前导入 NPC/链接、30层原碰撞和通关两格路径；只读，不运行导入器或修改 assets。
源 revision 为 `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`。

原源每层有两个相邻的真实前进门，共60条。自动表每层只选 mapwarp 源行较早的一门，
合计30条；相邻另一门仍属手动原路线，不作为自动 fallback。
JSON中同时保留 mapwarp 行、quiz.create 行及原链接完整身份；运行时每次读取都核对静态表全文 SHA，
逐次比对当前链接完整字段与 create 行。部署不访问开发用 references；原文件 SHA 复核在离线检查进行。
来源变更必须重新审核，不能只更新表的摘要绕过拒绝。

三个提案动作按核心 `2b-source-contract.md` v1：

- `source_service`：21个问答、9个猜拳、5个受理入口。只读公开 NPC 投影，完整比对源键、service_id、kind、位置和分支。
- `walk_portal`：精确 `{from_map,from_cell,to_map,to_cell}`。不带虚构 NPC、目标 override 或 proof。
- `source_exchange`：会员证原 REQUEST/source_branch_index=3；金布伊原 ACCEPT/source_branch_index=4。
  这两个运行时 branches 数组目前都只有第0项，数组下标不构成授权。
  全部 branch_data（含原文本/源行/动作）和原 Pet14 定义必须一致。

缺入场票、缺问答2752、会员证丢失、满包或满宠均交 manual；不会购买、取消/重领或选择额外奖励。
无2751仍可按原规则提案猜拳，本模块既不选择手势，也不读随机数。
当前所在公开受理大厅与等级档必须匹配；本片不为未知/其它起点制造传送。
不调用4a答案模块；公开题页解析属于后续核心服务执行。

## 新增导航边界

`quest_auto_navigation.next_portal(backend, portal)` 只追加现有导航类，不改原方法。
每次重验受审四元组、真实当前图/格、当前合法到达、唯一原链接、原source行、非disabled、
无gate_source替代、原目标条件与当前 NPC 占格，并重算原碰撞连通路径。
返回一个普通单格 point 或原 portal point，失败返回空字典，交调用者 manual。
入口侧不能穿原 y18 墙；y<18仅是计划选步提示，从不授予资格。
读取 NPC 使用 `active_npcs()`，避免旧 `npc_by_id()` 的状态刷新；不调用 action_context 或保存。
几何缓存仅属于临时导航对象。核心仍须在执行前按原 passage/arrival 复核，楼梯始终逐格，不参与B/C。

服务实际事务链为 OriginalQuests.transact → 原save → action_committed → _queue_warp → publish_warp。
计划不调用该链，不产生 receipt。完整ACK、取消、断线、失败回滚均由后续核心实际执行验收。

## 验证与依赖

基点为 main `88b22b0a` + 4a 原片 `d8787a40`，不依赖2a本地merge或等价历史。
2a导航并集尚未验，不能从本片单独成功推断兼容或 job2 已开放。

两个定向 suite：

- `quest_auto_golden_bui_plan_test.gd`：39原身份、source_branch_index、缺券、重领拒绝、奖励/分支篡改、无proof及无profile写入。
- `quest_auto_golden_bui_portal_test.gd`：30原碰撞路径、两格与真实楼梯点、墙、缺proof、动态阻挡、disabled/gate替代、错行、邻门和异常数值。

这些是纯计划/几何测试，fixture中的 arrival 布尔替身只测拒绝分支，不是服务事务或合法到达验收。
不得用它代替真实服务、自然猜拳 RNG、WS完整ACK或进程重启测试。
获准短窗口后两套串行通过：plan 292项断言/3.570秒，portal 540项断言/2.854秒。
首跑plan测试局部变量类型推断失败（0.290秒），显式声明Dictionary后通过；未运行额外check-only、import或旧套回归。
Python原源/碰撞静态核验0.369秒通过；这些结果不覆盖2a导航并集或真实服务事务。

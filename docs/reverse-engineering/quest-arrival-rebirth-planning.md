# 漆黑洞窟与精灵王：仅审计的到达契约

阶段：仅规划审计，未给32001–32021添加生产scope、未启用NPC／descriptor、未新增转生存档字段、未开放第6转或宠物转生。`quest_arrival_case_matrix_test` 实际断言当前32011/32021没有active任务NPC／转生事务，47/48–52未启用。此断言是当前“不开放”的证据，不是后续路线或转生功能已通过的证据。

以下源均来自 `references/chenmingbiao-stone-age` revision `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`。

| 实际来源 | 原行为／潜在项目跳跃缺口 | 后续必须的处理 |
|---|---|---|
| `gmsv/data/npc/genout/wpm_300_108_225:1–6` | 原入口需Lv80和END39/40/42/46，Warp32001(29,3)，不能团队进入 | 用真实源门保存receipt开始连续scope，不能凭32001当前位置或四件核心道具授权；仍要核全部源入口／支路 |
| `gmsv/data/map/mapwarp.txt:1807`起、779–790 | 多条同层／跨层迷宫连接，32020还存在通往117的单向出口；不能按编号假设唯一楼梯 | 按真实portal图逐格验证所有可行替代路及原单向出口；脚本门和战斗分开建stage，不把测试driver选路当唯一原路 |
| `gmsv/data/npc/300/sb_skr.arg:6–11` | 守护兽5敌1399/1401/1402/1400/1403，胜Warp32011(56,36)；直接到后侧可跳战 | 可信实际guard开战proof，胜战原子保存后pending，真实close/Warp后生效；源`start msg`拼写仅依既有精确审计，不宽化parser |
| `gmsv/data/npc/300/sb_skt.arg:7–12` | 帖拉所依朵10敌1404/1406/1407/1405/1408/1410/1409/1411/1412/1413，胜Warp32021(29,57) | 只有这场真实胜战给终战阶段，不能以同图位置、捕宠移动或上一场战代替 |
| `gmsv/data/npc/genout/wpm_32021_31_51:1–6` | 最后门再查Lv80+四END，Warp32021(32,47) | 最后门需前述连续route+终战阶段；成功保存后的真实Warp给精灵王领奖组件mark；项目门口瞬移不能洗白 |
| `gmsv/data/npc/giiru/event/sikkoku/sikkoku.create:71–80` | 精灵王实际32021(31,28)，`npc_transmigration|file:777/ten.arg` | 将实际source identity绑定独立转生处理器；最后确认原子事务再核同角色epoch／最终mark／当前全部原条件 |
| `gmsv/npc/npc_transmigration.c:528–568` | Lv80、四END、按转数的宠物条件，源码受`_TRANS_6`编译条件影响 | 仅实现已获授权的转数与分支，持物／旧save的完成位不能替代本次合法到达；不得因文件有6转文本就开放6转 |
| `gmsv/data/npc/777/ten.arg:1–4,17–64` | 四出生地礼物和返村Warp，1–5转及6转文本；7–15另有PETTRANS | 原返出生村是合法最终动作，成功后清洞内资格；PETTRANS／第6转保留关闭，不能整文件无差别激活 |
| `gmsv/npc/npc_transmigration.c:699–713,1032–1046` | 增转数、重置属性／事件与等级1，存在不可逆个人进度结算 | 保存candidate里一起核条件并结算，失败不授转数／物品／旗标、不消耗当前可重试资格。成功后再发布Warp；双设备旧token不能重复 |
| `gmsv/data/npc/giiru/event/sikkoku01:14–18`, `02:14–18`, `03:15–19`, `04:14–18` | 洞内MESSAGE各发2771–2774，持有原物时只说话 | 都是实际有副作用的分支，须连续scope最终事务保护，不能因TYPE=MESSAGE而漏掉 |
| `gmsv/data/npc/giiru/event/sikkoku05:7–16` | 后期END53分支检查2701/2707/2735/2770，却删2701/2702/2703/2704并发20570–20572，源物品组不一致 | 本阶段保持关闭。将来若请求启用，需把具体经济／进度影响交主逐案裁定，不能默默修谓词或通过到达policy顺带启用 |

## 结算与恢复边界

沿用现有统一接口，不增加客户端grant。重启／load/resume无内存凭证；同角色两个设备看同一权威实例。角色离开最终领奖组件即撤mark，再回来需原流程证明。party普通行走可传递每个成员自己的连续路径；固定NPC团队战目前根本未开放，不能把普通party slice测试当未来转生团队战验收。

非法epoch的战斗仍结算普通HP、药耗、经验、金币；只取消任务sideeffect／Warp，以及已经逐物审核且真实issued固定guard身份匹配的任务掉落。现有精确过滤表没有漆黑新物，不得提前扩为普通wild禁令。后续每个新增任务掉落都需原敌人/group/area/item/条件/概率证据并按用户已裁定范围处理。冻结claim原值与Session全量合法性检查必须保持。

后续启用前必测：原双Boss与各可行路线、项目直达领奖／门口／中层portal拒绝、失败保存重试、离区再返、重启、双设备token、原出生村返程结算。真实远程GameScene像素与主统一full是另一步，不能由本只读报告替代。

## 核心原文件SHA256

| 路径 | SHA256 |
|---|---|
| `gmsv/data/npc/300/sb_skr.arg` | `0dbec971e15174a4dad37f9160ab227b7b777b1c8c2b2ce6ad262d5423042145` |
| `gmsv/data/npc/300/sb_skt.arg` | `5844223293d7cef81fdb7e2bc7d85fa73ccb70f6ebafb52ed78b2210f7458670` |
| `gmsv/data/npc/genout/wpm_32021_31_51` | `b6498e3a37c47fd7e44ce07388a78de65dce29dd14e0ddf6589fe130ca91d098` |
| `gmsv/data/npc/giiru/event/sikkoku/sikkoku.create` | `db20a0b44bebd3d6dedb1d67dec42a9dd78bd82b82ebc8107789db199a08ed13` |
| `gmsv/data/npc/777/ten.arg` | `5d09f42c64a61c3220a01a5a0e82340672fb67ead03b818c4f6457421832c852` |
| `gmsv/npc/npc_transmigration.c` | `d7e40557bc460cc5a094f7e9d143ec4e3094883890a7832393baf713d3995d24` |

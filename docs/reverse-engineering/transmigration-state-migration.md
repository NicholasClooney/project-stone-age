# 转生结算底座：v7存档与关闭入口

本片基main6da4b47。规则来源为第三阶段计划及56项原字节SHA（2026-10-03本槽重新计算，全部一致），完整公式由R独立oracle负责，本片不实现公式、不声称精灵王可玩。契约见[结算合同](../technical/transmigration-settlement-contract.md)。

## 原事实与项目持久化

原npc_transmigration.c:699–759先加转数/继承，重置等级与点池；:868–876把累计Q/L打包为单个equation；:733最终点池为新转数乘10，不能把旧自由点加回。本片只建立保存这些结果的独立结构，不把继承塞入gm_bonus_points。字节SHA：d7e40557bc460cc5a094f7e9d143ec4e3094883890a7832393baf713d3995d24。任务20项依用户裁定及anson源表，不使用该混合C快照的45/47替代44/45。

v7顶层rebirth是项目保存结构，不伪称原版字段。转数唯一在player.transmigration，packed equation只保一份。natural校验Q/L自然范围、继承基底+分配+显式开发改值差额、点池与事务号；zero保旧基础属性和兼容offset；legacy_unknown仅记录历史缺失，不推算Q/L、不夹带伪造基底，禁止继续自然转生但保留原合法正转数及资产。金币沿Session.MAX_GOLD10亿、物仓3000，未新建上限或缩仓。

先严格验证原版本，再迁移；真正v1–v6缺整个组可升级，夹带新组或不明transmigration_equation不可混用。JSON解析把数字读为float，因此逐标量检查有限整数值，不用Dictionary严格类型相等判断规范零值；否则合法v7文件会被误拒并退回旧备份。测试读回移除备份以确保不能掩盖这类错误。

## 原子候选与入口

Session.commit_transmigration_candidate是内部候选写接口，不是网络命令；重验完整profile、下一转及事务差异，直接复用既有tmp/backup/rename写入，不调用装备migrate修耐久。失败恢复原profile对象，成功整组持久。实际NPC条件、祭品选择、奖励生成、到达proof及返村位置仍由下一片Service统一构建；本片候选测试是显式持久化夹具，不宣称真实转生路线。

Backend.transmigration实例/命令与真实NPC kind派发均已接入，但服务open/command统一拒绝“尚未开放”，客户端enabled/count/token不能开启。未新增可选开发开关、未激活descriptor。END53、人物六七转与PETTRANS仍关闭。

成人战斗checkpoint.restore存在独立profile恢复入口：同样先验证真实旧schema，复用唯一TransmigrationState.migrate再升版本，保留全部pending/battle/RNG/位置/到达语义；不把迁移变成新路线授权。

## 历史测试与验证范围

完整搜索client/tests的version赋值、降级变量及硬编码v6，窄适配旧fixture：progression/pet_storage/spirits_rules/original_wood_equipment/adult_quest_resume/original_quests.migration/item_storage_legacy；helmet/adult版本断言改读Session.SAVE_VERSION。原半仓字段/混合版本/UID拒绝断言保持。普通零转fixture可删未来字段；original_quests及item_storage保合法旧零值transmigration，独立手写v1–v6正转未知历史矩阵确认不统一抹掉正转数。

新增transmigration_migration_test手写各旧版本必要shape，不把新snapshot简单降版本：v1–v6读取、属性/资产保留、正转未知Q/L、保存读回、半组/重复count/非整数/NaN/点池错误拒绝，原子写失败回滚/同轮重放拒绝、转后十点分配/GM差额账本，以及关闭的三个协议动作。adult_quest_resume保原真实路线，再覆盖v5/v6/v7checkpoint读回与未来半组拒绝。headless仅验证行为，不宣称像素。

首轮9/9定向通过（单并发），随后只复验增强后的migration/adult两套。最终hash与日志交父；主在integrate/stage-three汇总后跑唯一full，本槽不full、不导共享资源、不碰main/live/save。

最终日志：首轮`/private/tmp/stage-three-foundation-targeted.log`，9/9，149秒，详细目录`/private/var/folders/lc/kqklvgsj5fvckh6dfrrd3zdr0000gn/T/stone-age-suites-x_u7sbhy`；加强后`/private/tmp/stage-three-foundation-final.log`，2/2，115秒（adult112秒、migration4秒），详细目录`/private/var/folders/lc/kqklvgsj5fvckh6dfrrd3zdr0000gn/T/stone-age-suites-e3r67d71`。后者包含显式v6 checkpoint、半组拒绝及无备份读回，前者其余7套最终文件未变。

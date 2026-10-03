# 第三阶段结算冻结契约 v1

Owner I：bonus-last-cave-chains。基线main6da4b47，pool-d/feat/stage-three-settlement。本文是实施合同，不代表服务已开放；首片生产入口保持关闭。最新裁定覆盖原计划：END53关闭、Session.MAX_GOLD=1000000000、未知旧正转历史保护；integrate/stage-three全绿后才由主发布。

## 文件边界

I唯一写client/server/game_session.gd、backend.gd、新transmigration_state.gd/transmigration_service.gd；original_quests.gd仅精灵王dispatch；client/network/session_client.gd仅命令封装。R拥有transmigration_rules.gd/oracle；arrival owner拥有arrival/policy；水拥有loyalty/equipment；地拥有内容/importer/descriptor。I统一串外围调用，不复制dirty。tests/notes/docs独立，公共suite只追加。

## 持久格式

SAVE_VERSION=7；旧1–6先按对应原schema验证再迁移。player.transmigration唯一规范转数（零转补0）；顶层rebirth独立组，schema=1，rules="original-1to5-anson20-v1"。

- history="zero"：count=0，equation=0，inherited_base={}，developer_base_delta={}，round_points=0，consumed_gm_points=0，last_transaction=""。保旧base/allocated/legacy_stat_offset/开发点；不重构过去。
- history="natural"：player.transmigration=1..5（不持久rebirth.count），equation仅保存一份packed (Q<<16)|L，0<=Q<=20*n、80*n<=L<=130*n；inherited_base四整数fixed值；developer_base_delta四有符号fixed值（显式GM修改的独立账本，默认0）；round_points=10*n；consumed_gm_points累计旧轮已结算赠点；last_transaction为最后成功事务的非空opaque ID。不另存Q/L或duplicate count。
- history="legacy_unknown"：只有schema/rules/history；保留旧合法正转数（可>5）及全部属性资产，既不造equation也不补继承基底。可普通游玩，拒绝自然再转生。未有未知档即不操作live验证。
- v7必须完整组；v1–6只允许整组缺失迁移，不接受半组/矛盾组。JSON有限整数值允许int或表示整数的float；小数/NaN/越界拒绝。旧正转且带不明equation等未来半字段不猜测，拒绝并保原文件。
- natural base_stats[k] = inherited_base[k] + 100*allocated_stats[k] + developer_base_delta[k]；新轮自由点=round_points+3*(level-1)+gm_bonus_points-sum(allocated)。继承不进gm_bonus。实际结算消耗旧轮未分配赠点：consumed累加旧gm，当前gm置0；已分配基础值仍按原P进入公式。旧offset在真实结算才清，普通迁移不清。
- UID、物仓版本/3000容量、装备耐久、next_pet_id、next_original_uid、completed_battles原校验保持；不可通过迁移重造UID或修磨损。

## R纯规则API（接受R草案，无profile schema依赖）

全部输入只读，失败返回{ok:false,reason:String}，不抛弃原输入、不静默clamp非法新转数。stats键统一vitality/strength/toughness/dexterity；events统一{now:Array[6],ended:Array[6]}。

- quest_count(events)->int，非法-1；使用已定anson20（含14/44/45），只计END。
- inherit(base_fixed:Dictionary,old_equation:int,old_level:int,new_count:int,completed_quests:int)->Dictionary：成功{ok:true,new_count,equation,base_stats,stat_points,ans}。stat_points=10*new_count；old_equation核n-1自然范围；公式C float32/oracle由R负责。
- flags_after(events,new_count)->{ok,events}：原六字清留，END69,70,71,72,109,118,122,131,127,158,159只保旧已置；NOW69..72同理；补END48..47+n。
- sacrifice_templates(new_count)->Array[int]，1–4转693..696各一只，5转四只。
- select_sacrifices(pets,new_count,selected_ids=[])->{ok,pet_ids,indices}：pet_id为既有字符串UID，默认随身原槽首次命中；只选随身，拒重复/缺失/错template，不查宠仓，不加献宠等级条件。
- reward_for(savepoint_bits,new_count)->{ok,enemy_id,template_id,location,village_index}：低四位首置位，0无出生拒绝；真实777/ten.arg四村五奖及返村，Item/Pet仅metadata，不收费。

## Arrival调用合同

I复用现check_action(backend,npc,branch,phase)->String（空允许），在talk/preview/confirm和最终保存前均校验真实源NPC/branch；phase沿现约定，不由客户端自报。owner扩漆黑scope，跨楼第一战stage与最终room mark分开，绑定现epoch；不得凭坐标/END伪授。合法两场真实pending_guard沿既有battle_context/check_battle/battle_committed+成功保存Warp钩子；同scope跨层保阶段、项目移动/load/resume/离scope撤。

已与arrival owner冻结通用proof：action_context(backend,npc,branch,phase)->Dictionary、check_action_context(backend,context)->String、consume_action_context(context)->void。精确真实服务kind="original_transmigration"、source_script/service_id="777/ten.arg"、NPC id="777/ten.arg@32021:31:28"允许空branch，phase="SERVICE"；不能泛化为任意服务。preview保存proof，确认和最后save前重验旧proof与check_action(SERVICE)。成功save后consume，再权威返村；consume核私有身份，不依赖已变更的profile位置；失败绝不消费。I不自行写mark。

## 服务/客户端合同

实际NPC唯一来自giiru/event/sikkoku/sikkoku.create，32021(31,28)，kind="original_transmigration"、handler="Transmigration"、service_id/source_script="777/ten.arg"，源ID由内容owner给实际完整绑定，不猜ID。仅精灵王开启服务，客户端不能提交角色属性/转数/奖励/地点/RNG/proof。

命令type="transmigration"，action="preview"|"confirm"|"cancel"；preview接npc_id:String、pet_ids:Array[String]（空为原默认顺序）；confirm接token:String；cancel接token:String。SessionClient封装同字段；原NPCtalk服务dispatch走preview。首底座三个动作统一拒绝“第三阶段尚未开放”，不得加客户端可选enable或GM开关。

成功preview {ok:true,transmigration:{token,npc_id,new_count,quest_count,equation,base_stats,stat_points,sacrifices:[{pet_id,template_id,name,level}],reward:{enemy_id,template_id},location,warning}}；不发送服务私有seed/proof。确认返回{ok:true,transaction_id,new_count,location,closed:true}，由权威profile+warp更新客户端。错误走现rejected/明确reason；取消不变profile。

服务内pending绑定backend实例/同认证角色、npc、不可变profile前态与rev、原arrival proof、选定UID及本次奖励seed；任意profile变化使旧preview失效（失败save不改前态，允许同token重试），同角色第二设备新preview使旧token失效。持久snapshot是唯一真值，不用客户端revision授权。preview不重掷既有pending同选择奖励；取消/重开不可靠预览看到随机成长来刷奖（预览仅模板，随机成长不公开）。

## 原子事务/恢复

1. 确认重核Lv>=80、END39/40/42/46、0<=n<5且历史可算、非战斗/队伍/auto/stationary/questauto、真实NPC距离/到达mark/epoch、出生、祭品UID及净容量、装备合法性。
2. 复制before候选：先q/公式，再原flags清留；等级1经验0/四分配0/点池10n；扣祭品后造Lv1奖励（独立冻结seed，不碰野外/战斗RNG）；只移除祭品，剩余普通宠原始成长技能VARIABLEAI保留，按UID重映active，ride清-1。重算忠诚、有效装备/HP；不清身份/元素/魅力/MP/技能；新增不合法卸装是项目约束，净背包满则整体拒。
3. 单次保存同时写新rebirth、宠奖励/UID、出生返村location/transaction_id；不需要后续close再持久返村。先完整候选校验，走原tmp/backup/rename，不先写partial计数。保全部正常金币/仓库存量。
4. save失败恢复profile、last_saved_payload/内存引用/UID/RNG；未消费arrival、个人NPC状态或token。冻结奖励及本次前态保留，重试同一结果。不能再调用通用equipment.migrate修复磨损来完成结算。
5. save成功才清本轮pending/助手cache/个人NPC冷却与任务运行状态、重置arrival、发布一次profile与返村warp；不清completed_battles/音乐/捕宠日志/仓库。清理具体缓存按现owner接口核对，不无差别擦profile键。
6. ACK丢失/关窗/重启后以已持久事务及返村位置恢复；旧token拒绝、不再发奖。restart前未成功save无新奖励。普通存档backup语义保持，不捏造跨备份的额外历史。

2771–2774仅审核logout物品名单增量，角色load清理；单设备断线不等于登出。END53奖励始终禁用，PETTRANS/6/7转禁用，Boss特殊技能仍metadata。各owner先交实际小hash，生产启用只在完整依赖/定向闭环齐全后由集成分支统一审核。

## 内容目录激活（已冻结补充）

模块id="transmigration-final"；manifest handlers["777/ten.arg"]={"kind":"original_transmigration","events":[48,49,50,51,52]}。四门、两Boss和考古家非END53说明使用同一目录tag集合[48,49,50,51,52]（真实source EventNo/条件不改）。这些数字只表示目录属于一至五转，不要求玩家已有任何48..52；实际入口仍Lv>=80和END39/40/42/46。END53奖励branch0始终不导入执行，说明分支按原源选择。

client/data/quests/transmigration-final.json沿既有descriptor：id、manifest、enabled_events、helper；底座enabled_events=[]，不要新造布尔enabled旁路。registry仅注册configuration时仍不可激活；最终依赖齐全后独立启用片将enabled_events置[48,49,50,51,52]。runtime还要求该tag已启用+精确service身份；首片服务代码始终拒绝，无客户端开关。

王NPC branches=[]，完整常规source身份保留（create ordinal5），额外transmigration={schema:1,rules:"original-1to5-anson20-v1",rounds:[{count:1..5,texts:{startmsg,mainmsg,yesmsg1,yesmsg2,nomsg,nonemsg}}],villages:[{key,savepoint_bit,presents:[五个原enemy],location:{map_id,x,y},source_item,source_pet}],maxmsg:String}。villages按原低四bit顺序，source_item/source_pet仅metadata。禁止导入PETTRANS/6/7转为可执行服务。

E已确认Loyalty.value/capture_variable/refresh末参owner_transmigration:int=0；I全部调用传player.transmigration。OriginalEquipment.equip_error(player,item_id)->String；revalidate_after_transmigration(candidate,bag_capacity=15)->{ok:true,profile,unequipped_uids}或{ok:false,reason}，纯深拷贝不migrate/修耐久。E只需已知转数，不依赖rebirth内部历史。

## UI确认补充（v1兼容字段）

真实quest_talk成功直接返回顶层reply.transmigration；不是dialogue.kind包装。UI可直接world.link.request合同命令并等待callback，无需SessionClient重复封装。cancel必须命中当前token才清pending并返回{ok:true,closed:true}；迟到旧token拒绝且保后来窗口。confirm成功返回closed:true并发布权威profile/position，使UI正常关闭。UI文件由独立owner持有。

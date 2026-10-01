# 原版任务解释器与已知偏差

已开放 `sainasu/event/event02_1`、`event02_2` 的不可思议的贝壳任务。
公开目录 `client/data/early-quests.json` 启用事件 1、2、15、16、18、19。玩家可点击日美子
（萨姆吉尔 1000，57/124）与弥生（玛丽娜丝 2000，55/92）。
测试使用真实 QuestCatalog 和原分支，不伪造对白或奖励。
伐木扩展按地图与数据、战斗掉物、完整事件链分别提交；仅启用目录中的事件才公开 NPC。

原参考 `gmsv/npc/npc_exchangeman.c` 保留文件分支顺序，EventNo 正数且
ENDEV 已置位时跳过该分支。EVENT 逗号为 OR、`&` 为 AND。解释器只支持
本期所需 LV、SP、ITEM、NOWEV、ENDEV、严格 PET>等级-原物种，其他谓词/动作失败关闭。
SP 来自原 CHAR_SAVEPOINT 累积位集合，不能把当前地图当出生村。
新角色与旧 prototype 存档明确默认萨姆吉尔初始位 0，origin 标注
`prototype_default`，不冒充原版出生数据导入。

REQUEST YES 成功交换后才置 NOW，已 NOW 的 REQUEST 进入 StopMsg；
取消删除 GetItem 裸 ID 的所有实例，清 NOW，魅力大于零扣一。
ACCEPT 按 `_NEWEVENT` 流程先 YES 展示 ThanksMsg，再 OK 才交换并 END。
CLEAN YES 清指定 NOW/END，NO 和窗口关闭不改变存档。
服务器重验分支与活动/距离；只接受服务器 token，不接受客户端奖励或 flags。

与参考源码的有意差异：NOW 清除使用 AND NOT，修正原 XOR 非幂等缺陷；
带 `*n` 的删除按脚本意图消费 n 件，而非复制参考 C 空实现；确认保持服务器
选定分支并重验，避免原回调从头选分支造成的并发漏洞。15 格交换容量按
先删后给的净结果验证，不复制 C 循环索引复用和 REQUEST 二次预检缺陷。
旧 prototype 物品仍保留一键一格的计数堆叠，原版新物品一实例一格，装备副本
不占普通背包；旧存档超容量不截断，但拒绝继续领取超容量奖励。

任务提交同步存档；写入失败恢复完整交易前 profile，不广播成功 profile。
原服务器 NOW/END 六个 32 位字持久化到 v5 存档；事件清除与迁移可重复。
存档点原位证据见 `char/char_data.c:689-720`、`npc_savepoint.c:543-551`；
确认流程见 `npc_exchangeman.c:570-601,1744-1768`，距离见
`npcutil.c:553-567`，旗标见 `npcutil.c:1310-1422`。

## 导入格式与资源

`tools/early_quest_sources.json` 固定 NPC 参数、create、itemset、jobdaily
的来源及 SHA256。`tools/import_early_quests.py` 按 GB18030 解码并校验，
生成忽略提交的 `client/assets/legacy/quests/catalog.json`，目录 version=1。
`npcs` 保存原地图、cell、贴图及有序 branches；branch 保存 EventNo、TYPE、
EVENT、原文消息与动作。`items` 按原 ID 保存 name/memo/icon，`jobs` 保存
jobdaily 标题与 NOWEV/ENDEV 状态。新增来源需更新白名单，未知语法拒绝导入。

物品 2414（不可思议的贝壳）、2415（仙尼亚的花）与两个静态 NPC 均使用
2.5 原图。网页目录和物品归 core，NPC 图归各自地图包。导入任务后运行
`tools/plan_web_packs.py` 与 headless editor import，无需重导世界或遇敌。
Headless 测试不验证渲染像素。

## 伐木原地图与数据准备

哈恩的锻冶场 20508 使用原 `jyaruga/dungeon/dan_2-05-08`，25×25。
20501(8,53) 原入口到 20508(7,24)，两格原返回门均回原入口；
20508(20,11) 到 200(396,821) 为原单向出口，没有补造反向门。
原重复入口到 (8,24) 保留审查记录，采用先列出的 (7,24)。
全 70 图块、60 物件均可用 2.5 图形，哈恩 (12,11) 邻格从入口可达。

完整目录含贝壳 2 NPC、伐木 5 NPC 、药草 2 NPC 与博士 2 NPC、22 件原道具。NPC 与 branch 的 `events`
记录审核链关联，EventNo 原值保留，不能用正数 EventNo 筛掉科巴尔特、赛尚等
无自身事件号的分支。哈恩 1837/1838 钥匙旁支 `enabled=false`，不公开。
当前导入的原 jobdaily 有 event1、event2、event15、event16、event18 标题，event19 不捏造日志标题。

## 已开放伐木链

15级起在霍特尔村 3300(60,75) 找巴尔接委托书2466；到锻冶场20508(12,11)
找哈恩接 event19 领空壶2463；阿鲁姆洞窟20507(32,29) 科巴尔特换满壶2464；
哈恩收壶及委托书制斧2465，巴尔收斧给推荐书2467与断斧2484。
赛尚在加加村3000(114,69) 收推荐书发许可证2478，持证按原遇敌表采木，
收回许可证及木材，依0–14档给石币，14档另给杉的手环2481。
12档不删除推荐书是原文件例外，保留原条件与删除列表。

八卦年轻人3300(46,55) CLEAN18、哈恩 CLEAN19 可重新接链；断斧可交哈恩
换改造斧2485。两种斧和手环当前只显示/持有，原装备属性尚未实现。
MESSAGE 打开即按原分支交换并同步保存后显示原 NomalWindowMsg；取消请求
删全部赠物副本。木链 REQUEST 保留原交换前实际空格预检，贝壳维持既有净容量
兼容规则。所有原交易先候选验证后一次提交，失败恢复 profile。

GetStone 使用 `player.gold`；原 `_FIX_MAX_GOLD` 启用，未转生上限1000000，
达到或超过整笔拒绝，不截断奖励、不删除输入。原上限公式还含转生次数，
目前无转生系统，不假装复现该扩展。数据依据 `char_base.c:2668–2678`、
`npc_exchangeman.c:2584–2595`。采木与组队/恢复范围见
[木材掉落](original-wood-drops.md)。

## 已开放药草（event1 / job30）

原 `jaruga/event/event.create:4–25`：村庄小姑娘在塔姆塔姆村3110(16,15)，
graphic16065/dir6；咍罗山的医生在山顶20105(16,20)，graphic16024/dir6。
共享 create 的成人礼两个 NPC 明确排除于已审核白名单，不能顺便开放。
`event01_1` 的 REQUEST 仅要求 LV>0，无 SP 限制，置 NOW1；医生 NOW1
且无2401给哈罗的香草2401；小姑娘 NOW1&ITEM=2401 收药给2427并置 END1。
jobdaily 原标题为「塔姆塔姆村的药草」。无 CLEAN，完成后不重做；进行中丢药
可向医生补领。取消沿原 REQUEST 行为扣魅力一，GetItem 为空不另删药。

医生 ITEM1984 提示与1982/1983磨药分支保留完整来源但 disabled；取药分支
原条件含 NOW87/END87，保留于 `source_condition` 和 `disabled_conditions`，
有效 `condition` 只选原 NOW1 子句，不导出或激活 event87。编号 AcceptMsg1/2、
ThanksMsg1..4 按序合并成完整原对白；兼容 NomalMsg 与 NomalWindowMsg。
交易在最后 OK 才提交，满包取药拒绝，满包交药按净容量交换，保存失败回滚。

物品2401使用2.5 logical icon23030；2427使用22002。NPC图各归map3110/map20105，
目录与物品图归core。现有两图及原门已导入，无需重导世界或遇敌；测试验证
near/arrival 安全落点与真实导航网格可达，远程无 backend 客户端按原按钮交付。
香草的原 ITEM_useRecovery 体100和护身符装备属性仅保存原道具说明，功能尚未实现。
药草助手只提供三步导航；自动执行仍仅贝壳。

## 已开放恐龙博士（event15/job6、event16/job7）

`sainasu/event/event15.create` 的博士哈鲁位于11006(11,11)、graphic16024，
助手吉鲁位于(11,7)、graphic16046。保留两个脚本全部原对白和分支先后顺序。
角色LV>9领取第一阶段，NOW15且普通species74鲁尼帖斯LV>14可交；删除随身
栏首个符合宠物一只，1350/1351/1352/1354/700/1455/1102/1122等概率八选一并END15。
角色LV>15且END15领取第二阶段，NOW16且普通species191贝鲁卡LV>29可交。
无SP、ENDEV4成人门槛，也无CLEAN；原未成年提示位于更早ACCEPT之后，不可达。

`GetPet:95` 是enemy ID，enemy.txt:60映射species173布克布克Lv1。
奖励使用enemybase:173的INITNUM25、LVUPPOINT4.50、V/S/T/D=26/26/26/17、
modai270、variable_ai0、水50火50、技能槽5、graphic100321；四档[-2,+2]后保存
成长权重，初始值再随机分配10点，沿已有固定点成长规则培养。不是species95、
不是满档GM宠。目录保存enemy与enemybase原行号，来源与enemy.c/npc_exchangeman.c
原字节SHA256均锁定。现有技能学习界面仍使用已实现的技能集合，未随任务扩展。

`PET` 和 `DelPet` 精确要求CHAR_ENDEVENT==0。持久字段`original_end_event`只接受0/1，
普通捕获和新GM原表发宠明确为0（原GM便利，不是任务功能）。旧存档仅有原遇敌
`source_enemy_id`且原物种的宠默认为0，来源不明默认1；不按昵称、贴图或等级推断。
字段为兼容可选字段，版本仍5，不改变旧宠数值、UID及仓库归属。

服务器两次确认绑定首个符合宠物UID；宠物或顺序改变后拒绝旧确认，避免删错同名宠。
最后OK才抽一次奖，token消耗后重试不能重抽；原子候选profile先检查净物品/宠物
容量，交宠修复出战、骑宠和削血宠选择，存档失败恢复全部候选修改且不发布成功。
满包阻止随机物品；满宠允许第二阶段一换一，未向仓库挪奖励或自动放生。

助手列领取、原助手说明、真实已导入捕获地点与培养条件、交宠奖励步骤；普通捕获
地点只从萨伊那斯100/加鲁卡200的真实普通遇敌查找，不新增稀有遇敌。宠物UID、
原物种、等级、来源与背包格数加入缓存签名。两种瞬移和远程原NPC点击沿统一协议。
博士自动任务尚未开放；贝壳自动逻辑保持。此博士提交尚未启用成人仪式，10204
长通道和沿途遇敌依赖由后续独立切片处理；原差使直接给15颗仪的玉，不能造击杀掉落。

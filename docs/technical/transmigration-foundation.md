# 转生第一阶段底座与并行接口

本阶段只准备共用数据和原语，不开放四精灵完整链、漆黑两战、精灵王或转生结算。阶段二分别拥有地39、火40、风41→42、水46；第三阶段才处理结算。校准仍为最早可玩 Samgir=1 SP、村民对话=0.5 SP；本阶段增量估计 **1–2 SP**，共享只计一次，不含各链内容和结算。复用现有NPC战、原物品UID/保存、掉落、个人NPC状态、LAN与效果metadata；增量集中在来源/路线核对、独立注册接口和原口令选择。没有重算历史 ledger/catalogue。

## 并行文件所有权

| 链 | 独占配置（相对`client/data/quests/`） | 独占 manifest（相对`tools/`） | 独占 helper（相对`client/server/`） |
|---|---|---|---|
| 地39 | `transmigration-earth.json` | `transmigration_earth_quest_sources.json` | `transmigration_earth_helper.gd` |
| 火40 | `transmigration-fire.json` | `transmigration_fire_quest_sources.json` | `transmigration_fire_helper.gd` |
| 风41→42 | `transmigration-wind.json` | `transmigration_wind_quest_sources.json` | `transmigration_wind_helper.gd` |
| 水46 | `transmigration-water.json` | `transmigration_water_quest_sources.json` | `transmigration_water_helper.gd` |

四份配置现为`enabled_events: []`，manifest现无NPC/奖励分支、helper拒绝访问。正式实现仅改自己的配置/manifest/helper，不改`quest-modules.json`、`quest_helper.gd`或共享解释器。通过`quest_module_registry.gd`读可信本地配置；不从客户端或存档动态加载脚本。Python importer从同一descriptor读取manifest和事件，拒绝路径/身份变化与重复registry id。

helper实例API：`stage_key(helper, backend) -> Array`、`steps(helper, backend, profile, quest) -> void`、`can_visit(helper, backend, step) -> bool`。步骤仍经既有`add_step`/`resolve_step`和服务端事务。关键词分支的`add_step`/`pick`使用`spoken_keyword`进行只读选择，打开NPC后仍由玩家输入口令，不以helper代发奖励。没有增加 backend / game_session / battle_session / party_battle_session 接点。

## 共用物品与来源

`tools/transmigration_foundation_sources.json`固定本地原仓库revision `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`、逐文件SHA256、实际create序号/行号/绑定/坐标、地图ID/SHA。import时核验全部；不是按脚本文件名猜NPC，也不是官方版本认证。

仅导入29件实际所需物品：2698–2701、2706–2718、2735–2736、2758、2766–2774。没有把2698–2774整段全部开放：蜂蜜、麦克风、改名笔、娃娃/彩票等不在此阶段范围。共用物品沿用原表图标、字段与`quest_item_effects`标记；魔法和抗性不增加运行时。奖励随机池中范围外物品由各链显式审核，不能因它们在原表存在就整表启用。

## 四链依赖矩阵

| 链 | 实际绑定 / 主线路线 | 复用与本次补齐 | 阶段二仍需做 |
|---|---|---|---|
| 地39 | `jaruga/event/ruri.create`；3413拉鲁、200伊布、21015蒂亚特；21001→21014固定战→21015 | 日记/项链/羽/羁绊，NPCWarp个人状态；`200/sb_dtp.arg`、`sb_dbt.arg`十敌；等级+END4/物品OR门 | 选择原分支、助手、条件遇敌/羽毛掉落、两袋随机池；`ruri03a`没有此create绑定，不替换实际`ruri03` |
| 火40 | `giiru/event/sink/sink.create`；5106真红、20309不死鸟、300老人、30016伊拉；30502→30001…30008→30016 | 2706–2718；`sink03`精确口令 很多/一半/一点点→2709/2710/2711；NPCWarp；三组十敌；门目的地重复选择证据 | 真正绑定的是`sink044/044a/044b/044c/055/055a`，不是旧`sink04/05`；壶来源、每条换水分支/随机奖励池及链helper |
| 风41→42 | `sainasu/event/genou/genou.create`；11215威尔、100姆哈萨；梦德11107既有`event12`给2736/END41；11214→11215 | 与梦德共享**同一个实际NPC**按源分支序合并；两只11208守卫个人180秒冷却；十敌终战；回程删2758门 | 核心41→42；三档`genou_2`献宠奖励按用户决定前方案B保持关闭，见异常报告；不造替代奖励 |
| 水46 | `jaruga/event/hekisei.create`；3400使者、21215女神、31302菲伊、21308贤者；21201…21214固定战→21215 | 2766–2770；十敌两战；原免费条件门与40→31301石币300门；原 unkeyed heading 可显式声明忽略 | 完整水晶链、静态掉落完整槽审核、箱子随机池；已批准碧青OR照源保留，链UI/日志注明原版行为 |

`event12`合并只允许同一source script/create/index/名字/地图/坐标/图形/对白，源分支索引必须互不重叠并排序；任何冲突失败，不能静默覆盖梦德分支。风manifest选原分支1/2/3时可和梦德原分支0共存，事件仍按各自events筛选。

条件掉落无需新运行时：地羽敌1146的group605排除持2698；水石敌1324/group718在已导入30305区域570，为现有无条件组；水贝敌1334–1336、1347–1349同时有其他掉落槽（1249/1238），按`reviewed_static_drops`必须审核全部槽，不能只激活2766。此阶段不启用这些掉落。既有按道具筛选的`roll`/`roll_group`可复用；没有声称支持所有NOWEV/ENDEV遇敌区。

## 最小原语增量

- `parse_script`保留`KeyWord`为`spoken_keyword`。`branch_for(npc, profile, spoken="")`按原顺序跳过不匹配口令的分支；不改变普通对话。共用口令输入后仍走原ACCEPT→确认→原保存事务；每阶段重验位置/状态/原分支，token单次使用。错误口令按源码落到后面的普通说明。
- `Break`仅审核不带`*n`的`DelItem`：原C仍删除所有相同编号物品，Break改变“损坏”消息，不能误解成只删一件。本项目复用原删除数量，窗口标原版道具损坏行为。没有开启任何新袋子/箱子奖励。
- `ignored_source_lines`在单个脚本review中声明`line/text/audit`，仅允许不带`:`/`=`且非`Break/EventEnd`的原未加注释标题；换成空行保留物理行号，不吞条件和动作。水`hekisei02/06`存在这种原标题。
- NPCEnemy `onebattle:0`与缺省等价；拒绝1及未知值。`100/sb_kbu.arg`允许无物品、`time:180`的dieact0；仍按已有按角色冷却、保存成功后才隐藏、`>180`才重现。`start msg:`空拼写仅增加两份已锁定第三阶段Boss脚本，未开放它们。
- WarpMan只接受`transmigration_gate_reviews.json`逐项锁定的FREE/WARP/MONEY/DelItem组合，不把未知脚本解释为无条件门。原PartyMsg只能作为拒绝文本，不单凭文案创造组队规则；沿用现有单角色任务guard。

## 地图与门：导入不等于开放

85张共用路线地图列在`staged_world.map_sources`，原普通门540条列在导入结果`world/manifest.json.provenance.staged_portals`。门只从SHA锁定create/mapwarp抽取；脚本门不转为免费portal。此前已开放的场景保持现有状态，新图标为`dev_only`，不加入普通探索门网络，不设置新任务入口。32021有原图但无精灵王NPC、无转生操作；地图原名写“地下20楼”是原数据，ID仍为32021。

阶段二将本链需要的`map_sources/portal_sources/portal_choices`从共用证据摘入自己的`world`，声明本链`restored_scripts`以移除既有场景便利门；只有已实现、验证的链才设置`enabled_events`。不能把整份85图全部提升为普通地图，也不能因导入32021提前开放漆黑入口。

`tools/audit_transmigration_routes.py`与[路线证据](../reverse-engineering/transmigration-routes.json)检查导入碰撞、原普通门、显式列出的NPC门/胜战跳转：六条入口到目标（地、火、风、水、群青水、贤者）均有保守四向行走路线。普通门格停止继续步行扩张，抵达格除外；有冲突时只用已有审核选择，否则排除。**这是在已满足门条件/赢得固定战的前提下核查路线，不是四条任务已端到端可玩、战斗平衡或像素验收。**

深红30008(50,54)有两个原落点。固定选择`mapwarp.txt:1693`及`dungeon02.create:277`先出现的30016(28,99)；两个源列表均先28后29，原加载按顺序appendTail、事件取首个匹配。证据SHA覆盖map_warppoint/readmap/object/event/version/main；不是凭哪条路方便而选。

## 原战术 / 技能与第三阶段

[原战斗资料](../reverse-engineering/transmigration-combat-sources.json)逐项列四链及漆黑共11个守卫脚本、完整敌人顺序、enemy原战术字符串、enemybase七技能槽及petskill名称/函数/参数/行号，三张原表SHA固定。所有`original_skill_runtime_restored=false`，仍用现有AI；不能把敌人列表复刻描述为Boss特殊招式已恢复。

第三阶段仍要处理漆黑原脚本异常、精灵王事务、各转公式/累计参数/旗标迁移、忠诚与返村等。并行`body-equipment-revival`加入BODY UID槽、1052原普通属性/耐久/Lv30（magic10 inactive）。将来等级重置必须按统一slot遍历逐槽核验转生等级豁免/合法性，不能硬编码旧四槽，不能未经核源一律卸BODY；保留原UID。此阶段未改装备、消费、保存版本或战斗结算事务。

## 主工作区精确导入命令

由协调者在合入后遵循AGENTS的存档备份/干净停服及重启顺序执行；本worker不接触live。以下从仓库根目录执行，资源来自已安装原包，无新下载：

```sh
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age
./scripts/run.sh --headless --editor --import --quit
```

import_world输出450图、1605普通portal，32021 `missing=0`；quests输出242NPC/138物品，NPC数量未因本阶段增长。本阶段不需重新导入encounters或Boss美术。未将导入资产/截图提交Git。

## 定向验证

- Python `test_transmigration_foundation.py`：真实源fixture、29物品/禁用边界、十敌/180秒、12个门与变异拒绝、共享event12分支合并、Break/来源绑定校验。
- Python `test_import_world.py`：25项地图回归，包含隔离staged地图不开放普通门。
- Python `test_quest_import_common.py`：既有模块23项回归。
- `transmigration_foundation_test.gd`：三种水量的真实Backend/Session保存失败、UID保留、重放、成功存档重载；原等级+END门与300收费门；10个真实守卫实例完整十敌、失败保存与原结算重试、180秒个人冷却；两设备真实WebSocket端口0，旧token失效、原奖励不可伪造。
- `transmigration_drops_test.gd`：原group605持物排除、原概率阈值、真实战斗掉落保存失败回滚/同一roll重试/关闭重放不重复。
- `quest_helper_test.gd`：既有助手及真实远程只读投影回归。
- `audit_transmigration_conditions.py`：最小原C解析器证据，局限见[风奖励报告](../reverse-engineering/transmigration-wind-reward-condition.md)。

全部测试headless、独立测试user://；未运行full、未spawn、未启动/重启live。无头测试不验证渲染像素。

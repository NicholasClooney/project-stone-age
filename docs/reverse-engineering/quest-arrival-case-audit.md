# 任务合法到达逐案审核

阶段：全部已实现洞窟已交独立服务器政策；旧助手、自动执行及旧测试夹具由各 owner 分片适配，尚待父会并集验收。四精灵采用各链锁源 fixture 验证；本报告不把 fixture 测试称为已开放完整产品。漆黑洞窟／精灵王仍只审、不激活。普通任务专用野战掉落等待用户 A/B 决定，保持现状。

## 共同问题、修复与证据边界

此前项目 `quest_visit`、自动执行、地图/POI 和抓宠移动可以直接写服务器当前位置；旧 NPC 最终奖事务检查道具／旗标，却没有本次原路到达证明。因而原剧情需要的连续通路、口令、收费／票门、胜战位置可能被项目移动替代。现每角色服务器内存记录原 root、连续位置、epoch 和必要终战／原门 mark。任何项目移位撤销，不从存档、resume、客户端字段或另一个角色恢复。源动作仅在原子保存成功后排队 receipt，真实 Warp 后激活；最终原 NPC／service 事务仍检查实际身份与当前资格。

普通回村交付不要求已经离开的洞内 mark。公开场景本无路线、门票或必打战的 NPC，只保留原条件；没有新增从出生村步行的要求。合法获得的宠物满足公开交宠条件时，可正常交付，捕宠便利本身不赋予洞内任务资格。

`quest_arrival_case_matrix_test` 对当前全部 active NPC 有动作／REQUEST/service 分支逐项调用真实最终事务：受保护节点项目到达必须拒绝且 profile 不变；公开节点仅断言政策不添加资格条件。它另外在地／火／水锁源 catalog 下运行相同矩阵。其负例不是每条任务的自然正向流程；下表分别列真正跑过的代表原路套件。公开送斧、卡坦、四宝玉另跑其原实际事务套件。共享保存失败、旧 token、真实两设备同角色及 party 普通跟随由通用 suite／各链原 suite 覆盖，不宣称固定 NPC 团队战开放。

## 20 项与子事件

原源前缀为 `references/chenmingbiao-stone-age/gmsv/data/npc/`；旧总审计的编号裁定采用早期20项表（44而非47），萨顿按已批准项目补充同写14，清13不清14。下表 source 行号是原文件物理行，非导入数组编号。

| 加点项／子事件 | 最终源分支、此前可绕点 | 政策／无缺口原因 | 定向验证与发布边界 |
|---|---|---|---|
| 1 药草 | `jaruga/event/event01_2:27–37`取2401；`event01_1:3–12`返村2427/END1 | 200原入口→20101–05连续；3110小姑娘公开返村，无需当前洞内资格 | `quest_arrival_legacy_caves_test`原路与全动作拒绝；wind负责helper/auto并集 |
| 2 贝壳／送花 | `sainasu/event/event02_1:17–39`、`event02_2:17–39`花贝互换/END2；各8–14清位 | 2000/1000公开NPC，原出生村SP和物品谓词，无原必经迷宫，未新增资格 | 全分支矩阵公开兼容；既有贝壳事务测试由主并集 |
| 4 成人 | `jaruga/event/event04_1:3–12`收15玉→仪之兜/END4；`event04_2`供玉 | 10202原30级门→10204完整通道；不能持玉／直接置于审判前即领奖 | `quest_arrival_adult_test`真实level门/往返/重启/两设备；bonus已交产品原路 |
| 5 送斧／3 | `sainasu/event/event03_1:8–27`END3/信；`event03_2:8–17`END5/2448 | 1300/1400公开往返，原交物和旗标就是来源约束，无洞内障碍 | `yam_axe_quest_test`原交付/savefail/旧token/LAN；无新增scope |
| 8 哥亚／6、7 | `jaruga/event/event07_1:8–30`END8/1206；`event07_2`信花；`event06_1`贝换宠 | 200→20401–06连续；不凭贝壳造新入门票；原花店同洞亦受保护 | 六洞矩阵与真实深层route；wind旧流程适配 |
| 12 梦德／9、10、11 | `sainasu/event/event12`洞内石；`event10:4–13`END10/12；`event11:4–26`END11/12 | 原野外口令→11101–07→悟／唐战Warp23,35；公开村庄交石保原先后条件 | `quest_arrival_munde_wind_test`真实口令/七层/战；共享风event12同受终战mark |
| 14 萨顿／13 | `sainasu/event/event13_1:9–18`收三宝→2450/END13，项目补14；`event13_2:9–15`清13 | 100→10701–05连续；三nusu真实guard专用掉落2428/29/30按可信issued身份过滤；1112返村不锁 | 六洞route及核心invalid guard/savefail；批准重复与清13保14不变 |
| 15 博士 | `sainasu/event/event15_1:4–13`交≥15级模板74，8池奖励/END15 | 100→11001–06连续；原REQUEST Lv>9，不新增成人要求；捕宠便利不授洞内资格 | 六洞正路/事务拒绝；wind博士原route/UID适配 |
| 16 博士后段 | `event15_1:15–24,37–45`交≥30级模板191→enemy95/END16 | 同博士scope，保原END15/人物等级/宠谓词 | 同上，第二阶段全部分支入矩阵 |
| 17 龙洞 | `jaruga/event/event17_1/2/3:4–13`三玉+笛→三装备/END17 | 200→20801–07；原`wpm_20807_11_37:1–3`保存后才有dragon_gate | `quest_arrival_dragon_test`七层/门savefail/奖retry/reset；earth配旧UI；野生三玉不称已封 |
| 19 伐木／18 | `jaruga/event/20501ev1:15–24,40–50`取水造斧/END19；`20501ev3:20–40`返村END18 | 200→20501–08；洞内取水/补壶/斧/许可交换保护；公开3300/3000回报不锁 | 六洞原route矩阵；wind原流程适配；原CLEAN19保留 |
| 22 强恩／20、21 | `event20_4:5–12,16–24`END20/随机奖END22；`event20_6:5–35`女儿信/REQUEST21；村庄`event20_2:5–14`END21 | 200→20601–08三口令；jan1/2/3实际终战Warp；父女两图原往返保mark，公开交信无当前洞证要求 | `quest_arrival_jan_test`三口令/真实战/父女全往返/savefail；early owner适配 |
| 27 矿工 | `giiru/event/giruev2_1/2`实际31805交换；`300/sb_bac.arg`专用2533；`wpm_31805_22_4`矿票门 | 300→31801–06连续，原guard掉落身份过滤；捕宠51精确点可到6楼但无任务scope | 六洞route与backend捕宠/失效战果；2534普通wild待决 |
| 30 黄金／29、54 | `king/event69_1`库伊原镜/END30和金羊END54；`giiru/event/event30_6`2551/END29 | 31901–11连续，真实钥匙门和guide；`wpm_31910_8_9:1–4`消费眼的真门授golden_truth；公开库伊返程无当前洞证要求 | `quest_arrival_golden_test`真门savefail/全层路径/终奖；foundation配旧流程；2548野战待决 |
| 31 五兄弟／28 | `giiru/event/ev28_end`先五纸→晶/END28再REQUEST31；`ev28_ed1..5:9–20`宠/琴/END31 | 300→31701–06，原层门及5选guard；真实胜Warp→原同图portal→共同领奖厅；不提前要求晶的终战mark | `quest_arrival_brothers_test`全纸原路/第5真战/宠savefail；Dream离区一起回归；foundation配5选旧套件 |
| 34 梦幻／32、33、重复 | `seimu/event/event01_2:14–48`三轮固定奖，后续重复原分支 | 原昼夜入口+maze+十敌终战；实际400→41/42；仅真实保存后胜Warp授dream_final；原离领奖组件清除 | core/backend/transaction suites真maze+战/savefail/token/原出口；bonus产品适配；捕宠直达无资格 |
| 35 卡坦 | `seimu/event/event02_1`公开100随机出生NPC，恰25级四种宠和最终双宠UID | 公开野外无原任务门，位置变化仍按实际source instance与原宠谓词；不新增洞资格 | `katan_quest_test`真实出生/UID/savefail/LAN；捕宠便利可获合法原宠，不直接推进NPC |
| 38 马祖／37 | `extra/event/marju01:8–20`交信/END37及石补发；`marju:21–29`公开返村随机武器/END38 | 120原Lv50门→122/118/119；实际119→121单向出口；1300回村按原条件 | `quest_arrival_marju_test`完整maze/交付savefail/单向出口/村奖；earth配旧流程 |
| 44 金布伊 | `quiz/equiz_01`REQUEST44/券2753；`equiz_02:38–46`宠14/END44 | 5个原等级票服务门，800–810/820–829/840–850逐层；公共厅/售票不锁；批准无券猜拳不变 | `quest_arrival_dojo_test`5roots/实际问答savefail/旧token/无票拳；wind配全顶层/UI；47仍闭 |
| 45 四宝玉 | `extra/event/hougyoku:8–31`6000公开学者接结晶/四宝玉交换/END45，NpcWarp | 四个原公开野外区域本无任务门；NpcWarp个人化原条件已保留；不凭任务物名创造朝圣 | `four_jewels_quest_test`真实条件怪和事务；通用公开矩阵；掉落详细排除理由见独立表 |

## 四精灵增量

- 地：21001–16，200双原Lv65+END4门；原三层 OR 门照批准保留，dbt真实胜Warp21015(9,17)才给女神及两85槽袋的mark。dtp是否必经取真实几何，未全局强加。公开3413请求／200动态日记不加门槛。2700普通野战羽毛仍待裁定。
- 火：不死鸟200原入口→20301内部原成人+NOW40/END40门→20302→20306→20307→20309；不按编号强制全部九层。火洞30502/30503两真实入口，30016原入图为战前，hpa保存后Warp26,63才可伊拉。20309羽毛／洞内动态换水按路线保护；5106接取、300野外灌水／退款、公开30504商店不新增洞内资格。`quest_arrival_fire_test`只测试当前锁源fixture，完整自然动态换水由fire owner。
- 风：100原Lv70+END4门→11201–15；原环门及中层guard只维持路线，不给顶层mark。kgi真实胜Warp11215(9,16)授顶层，genou_1 REQUEST41/END42、genou_2三献宠、补环各按实际source检查。event12的补琴/END41琴仍需梦德原口令/七层/悟唐；公开genou_3 NOW42保持原条件。自然双登顶和选宠多设备由wind owner实测，本站没有冒用项目落点造grant。
- 水：200成人原门→21201及mzl/mzn真实战、21215↔21315逆行21308，材料门成功保存授water_material，`hekisei03`保已批准 OR。湖水31301/2同时认可5000免费原portal及40原300币门；已END46+贝的后入口合法重返，不当首次完成证明。石岛30301–07双65级+END4原门都恢复并记连续scope，2767野战仍待决。贤者／女神／箱／补湖水分支各保源条件，不靠仅在图内或持材料授资格。

## 尚未完成的统一验收

1. 所有政策与 owner 旧助手／auto／fixture 接入的完整并集，含真实远程像素证据由相应 owner／父会完成；本槽只定向，不碰live/save/full。
2. 专用普通wild掉落 A/B 待用户决定。详 `/private/tmp/tmux-agents/quest-legitimate-arrival/task-drop-audit.md` 和 `task-drop-cases.json`：19物、225精确来源行，区分4个可信固定guard物与普通wild，含敌人/group/area/概率/完整源SHA。
3. 四精灵最后生产descriptor与完整链验收，及统一所有旧token/双设备/party普通跟随回归。固定NPC组队战仍未开放。
4. 后续漆黑／精灵王仅只读规划，详同目录后续阶段审计；不能因政策覆盖而启用转生NPC、保存字段或第6转。

已修测试注册事故：前三片曾复制整条for循环，定向运行器显式suite未发现shell语法错误。独立`49ef5c9`保留314套原注册并集并去重为单条for，`bash -n`及`run_suites`枚举/文件存在性验证通过；不能以此前refresh/check代替这项检查。

实跑矩阵1343行，去重并补入wind已交efaeddb锁源后共421分支、237原脚本。逐行NPC实例／map:cell／原源物理行／原条件动作／当前scope与mark／测试层级见 `/private/tmp/tmux-agents/quest-legitimate-arrival/all-arrival-cases.md`，完整源SHA为同名JSON。风补入部分明确属于owner自然链验证，未伪称本槽矩阵跑过风全链。公开三套与矩阵4/4通过，日志 `stone-age-suites-md1nqtxq`。


## 2026-10-03 掉落 A 已批准：政策片状态

main `c298d39` 正式批准专用野战掉落 A，取代本文此前“待 A/B”状态。本片交付214条精确 source tuple 白名单与开战／最终 epoch 凭证接口；后端／automation／claims 由 bonus 单独接入，本片不冒称整套结算已实施。名单、源SHA及排除项见 `client/data/quest-wild-drop-policy.json`，契约及测试层级见 `docs/technical/quest-legitimate-arrival.md` 最后一节。

30305 双原门＋七图连续路线证据齐全，纳入 water_stone；1099 只有遇敌记录而未找到原NPC/portal入口，继续排除待核。公开200木材实际group414（不是早期摘要的407）、四宝玉均不增路线门。固定guard独立，普通装备／宠物／经验不受此名单限制。最终 backend native/queue/party/savefail 并集测试与1099入口是剩余边界。

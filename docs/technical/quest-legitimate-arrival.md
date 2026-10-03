# 冻结接入契约 v1（实现中）

新模块 `res://server/quest_legitimate_arrival.gd`，Backend成员名统一 `quest_arrival = preload(...).new()`。模块和独立测试/审计归quest-legitimate-arrival；不要给客户端增加grant或任何能选择source kind的命令。

```gdscript
func reset() -> void
func observe_move(backend, from_map: int, from_cell: Vector2i,
    to_map: int, to_cell: Vector2i, kind: String = "report", evidence: Dictionary = {}) -> void
func check_action(backend, npc: Dictionary, branch: Dictionary, phase: String) -> String
func action_committed(backend, npc: Dictionary, branch: Dictionary, phase: String) -> void
func battle_context(backend, npc: Dictionary, branch: Dictionary) -> Dictionary
func check_battle(backend, pending_guard: Dictionary) -> String
func battle_committed(backend, pending_guard: Dictionary) -> void
func has_arrival(backend, map_id: int, cell: Vector2i) -> bool
```

所有接点均同步调用，不修改profile或发送网络。`check_*`空字符串成功，非空为中文项目补充说明。`battle_context`只生成服务器证据，不能来自command；存入pending.quest_guard.arrival。其最小结构 `{epoch, scope, map_id, cell:[x,y], npc_id, warp}`；调用方不得自行拼。模块会核源身份和当前状态，不以此字典自身作为grant。

## bonus：后端/移动/战斗owner

- load_profile/reset重启路径 `quest_arrival.reset()`；不进session.snapshot/save/resume。恢复旧战斗pending无本次内存epoch不得授新资格。
- 任何权威位置变化取得old位置，调用observe_move一次；可以在position_changed之后，传真实old/new，避免同一变化重复调用。`report`用于普通report_position，`walk`仅用于服务器逐格自动步行；都核真实碰撞、相邻步或原portal精确源/目标，不能凭kind自报授权。
- `project`用于quest_visit/自动任务项目落点/抓宠/dev/automation._set_position等。相同位置不破坏合法路线；真正移位到保护区不授资格且失效当前路线。移到公开区域只清已有相关路线。组件相同本身不授资格。
- `script`只用于Brothers.publish_warp的真实原门/胜战Warp发布：必须由此前action_committed/battle_committed在模块中生成匹配源、目标、epoch的单次待发布记录。孤立调用publish_warp或普通report冒同一坐标不能授予。close_battle取原成功结算pending，不从state任意npc字段生成。
- 同角色WebSocket共用Backend实例，消息先后即epoch先后；旧token最终check_action仍重验。
- Brothers.begin在实际NPC分支已核准后，先check_action(...,"BATTLE")，再将battle_context返回值放进pending.quest_guard.arrival。
- _after_turn在任何胜战任务Warp/任务掉落应用前调用check_battle；失败返回不结算任务推进。保存成功后battle_committed；保存失败完全不调用。battle_committed只生成待发布记录，close_battle→publish_warp(script)才激活新区域。dieact0无Warp保留已合法scope，不合成胜后区域。
- 组队普通步行/portal跟随kind=`party`，evidence最小`{leader_from_map, leader_from_cell:[x,y], leader_to_map, leader_to_cell:[x,y]}`，只能ProfileHub内部从成功且经验证的leader原移动构建；模块再次核实际portal、成员原scope与同区。不得从客户端command原样读evidence；项目队长移动仅传kind=project；无资格成员不能继承leader资格。原脚本禁止组队的门照旧拒绝。
- check_battle在每个成员自己Backend调用；不能把队长arrival复制给全队。无任务guard的普通掉落暂不接额外禁止，待具体案例裁定。

## wind：original_quests独占owner

- 所有transact调用保留真实npc上下文，已有npc_id可复用：FREEWARP/KEYWORD在choose传入str(npc.id)；open_branch MESSAGE等也需传，禁止推测已经被清掉的pending。
- talk/open_branch/choose可用check_action早提示；最终transact在候选变更前必须解析当前npc_by_id(npc_id)，调用check_action；有实际保护动作却缺NPC身份默认拒绝。必须包括REQUEST的NOW、MESSAGE自动奖励、ACCEPT reward、FREEWARP/KEYWORD，不只EndSetFlg。
- 成功backend.save之后、任何Brothers.publish_warp之前调用action_committed；失败保存不调用，不提前变token/route state。
- 服务synthetic branch必须保留真实NPC身份；source_branch_index缺失用可信原branch实际内容匹配，不能按客户端提供编号。
- helper仅只读has_arrival，不可grant。公开村庄/野外分支不加朝圣要求。

## fire：service owner

- services.apply调用transact传str(npc.id)，保留服务source身份和实际actions；无需新服务内部到达容器。原购壶无门与路线障碍证据时不额外加NOW40或洞窟资格。

## 政策与实现边界

我独占新增 `quest_arrival_policy.gd`（静态审核scope、原入口/受保护NPC动作）与模块；各链给manifest/实际原门源，不改此文件。连续route从已审入口开始，允许瞬移到**公开入口前**后正式过门，不要求从出生村步行；禁止瞬移到**链内部**portal源格再过门洗白。无scope公开NPC返回通过，回村奖按原条件而非洞窟当前凭证。

新掉落资格暂不自动扩展：1146羽毛2700在21002、龙玉三层等要单列“捕宠便利是否允许顺带原任务掉落”案例交父。不会以NPC审计名义静默禁止普通战利品。

## 首片实现范围与战斗失败语义

`quest_legitimate_arrival.gd` 已提供以上接口，另有 `blocked_guard_items(pending_guard: Dictionary) -> Array`。首片仅启用梦幻41/42政策；尚未接入共享Backend/交易入口，不能宣称全任务漏洞已封闭。政策扩展与共享接入由独立提交完成。

`check_battle` 非空只否定本次任务到达授权，不能永久卡住战斗或吞掉普通战果。集成调用方仍用冻结的原slice/claim结算HP、药耗、经验与金币；跳过任务settle_profile/committed/Warp，仅在候选claim副本剔除本模块给出的专用任务物，保存失败保留原pending/原claim，成功正常关闭。先验证原claim合法，不能过滤后替伪造claim洗白。

精确专用物来源：`gmsv/data/npc/100/sb_nusu1.arg`、`sb_nusu2.arg`、`sb_nusu3.arg`的原敌513/514/515，分别掉2428/2429/2430；`gmsv/data/npc/300/sb_bac.arg`原enemy1004掉2533。源审计为 `saton-cave-quests.md`、`miner-contest-source-audit.md` 及锁SHA manifest。本接口只接受当前模块曾签发且保留的真实原NPC战上下文；仅伪造同名npc_id、改另一个守卫、普通wild或新模块均返回空列表。普通野外任务掉落不在本片限制范围。

内存proof额外含instance/serial，与私有签发记录逐字段相等才有效。项目移动增加epoch但保留未结战的真实来源记录，只用于精确去除未获授权任务物；reset/reload清掉记录，不恢复凭证。普通合法步行与保存失败不换epoch。成功battle_committed仅安排单次待发布Warp；script移动匹配真实旧坐标、目标和epoch后才授胜后mark，重复结算不能再次安排。

`quest_legitimate_arrival_test` 已运行headless：真实时间入口、独立四向地图oracle连续走完整梦幻迷宫（含原portal到达锁）、真实十敌战/真实文件系统savefail/原结果重试、胜Warp后授予、项目传入撤销、旧proof/不同角色/重启拒绝与精确守卫物品白名单。测试显式调用待集成hook，未把它说成共享入口已接通或双设备已验收。只运行此定向suite，未触live/import/full。

## 领奖区域生命周期补片

梦幻终战mark绑定领奖连通区域，而非整个scope。基于实际41/42碰撞网格、阻挡两终战守卫与仙人后，两个地图的领奖组件各227格；穷举该组件所有原portal，41只有(34,40)→41(34,43)、(33,40)→41(33,43)，源`genout/mugendungeon.create:484,493`；42对应同坐标到42，源`genout/mugendungeon2.create:43,52`。因此原出口确实留在dream scope但离开领奖组件。逐格走到出口源格仍有mark，执行原portal后立即删除；route本身可继续，不能复用终战资格。测试补真实胜战后(34,39)→(34,40)→(34,43)与旧战斗不能重授。

`Policy.mark_regions`集中声明每个mark可保留的地图/源落点；每次可信移动后重新核区域，离区清除。房间组件排除原portal与当前NPC占格，缓存随碰撞、portal或角色NPC位置/隐藏状态改变而失效；不是每格BFS后反复枚举全部NPC。缺失地图仍失败关闭。

`has_arrival`只表达当前合法路线及同组件，不能替代奖励分支的`check_action`。helper显示/导航真实奖励步骤应调用只读check_action；真正项目移位会撤资格，同区也不构成免检授权。已在可对话范围内可以返回当前格（无位移）；远处提示沿原路步行。

本轮不新增组队固定NPC战：生产Brothers.begin仍由Hub拒绝in_party。party验收限于原普通移动/portal的成员独立路线；NPC战savefail为单人真实战，不能把人工复制quest_guard的party fixture当可玩证明。

## 风与梦德政策

新增11101–11107的munde scope及11201–11215的wind scope；这是允许连续原边的区域集合，不是要求编号顺序或创造唯一路线。源入口分别为`genout/wpm_100_443_127:1–4`精确口令Warp11101(33,29)、`genout/wpm_100_278_325:1–2`LV>69且END4的Warp11201(29,79)。旧景观gate_source不能作为普通portal授予资格。

`100/sb_go.arg`/`sb_dan.arg`原胜Warp11107(23,35)后才有munde_final；共享`sainasu/event/event12:4–10`旧石分支、19–25补琴、28–36发琴/END41统一核此凭证。原回村交石/领奖仍按村庄原分支，不要求当前洞内mark。`100/sb_kgi.arg:5–7`胜Warp11215(9,16)才有wind_final，保护`genou_1:8–17`END42与32–40的REQUEST41、`genou_2:9–40`三档献宠；中层kbu个人隐藏不是山顶凭证。`genou_4:9–15`补环需要当前六楼原route；野外`genou_3`无scope不加洞窟前置。献宠分支是否激活仍由原descriptor控制，本政策不激活事件。

风原回程落100(278,325)入口NPC格在scope外：只清凭证，不拒位置或后续走离；受保护原script落点即使正逢NPC实体，只有刚提交该真实落点的下一步可离开，普通报告不能凭占格声明穿人。

共享测试support `tests/support/original_route_driver.gd`只按实际碰撞、NPC与portal计算四向路径，并用生产report_position逐格走图。脚本门与固定战必须由调用者实际完成；不会修改scope/epoch/receipt、不会把位置fixture伪装成合法入场。旧Backend下模块suite显式观察移动；已接入Backend下使用唯一b.quest_arrival、实际begin产生的proof及自动commit/Warp hook，避免双调用。两个定向suite均注册；首轮旧Backend 2/2通过，真实接入另行记录。

## 成人仪式与真实前置测试工具

`genout/wpm_10202_31_13:1–3` 原门为 `WARP:10204,2,6 / FREE:LV>29 / MONEY:-1`（源 SHA 及导入依据见 `early-original-quests.md:178`）。10204现在属于独立adult路线；公开10202入口前可项目到达，必须通过真实等级门，之后沿原通道行走。`jaruga/event/event04_1:3–11`收15仪玉、给2418并写END4，15–23请求NOW4；`event04_2:3–10`按NOW4发15仪玉，均由同一最终事务重验路线。这里不新增原等级门以外的任务条件。

此前项目助手能直接进入10204，旧`original_adult_quest_test`甚至断言“explicit helper bypasses entrance”；这是已确认的绕门证据，不能把旧fixture当合法前置。新的`OriginalRouteDriver.complete_adult`只将角色放在公开村庄门口，真实report进入、两段逐格通道、三次真实NPC交换，获取END4。测试工具不会写旗标、物品、scope或grant；初始角色等级/能力由调用方普通fixture负责。`quest_arrival_adult_test`在此基础上复用真实梦幻终战和最终奖励savefail/旧token测试；直接瞬移仪式NPC旁的请求另有拒绝断言。普通生产GameScene像素或UI自动行走未由该工具验证。

集成依赖为b2c9ad1后端、3b5790a普通NPC事务、372481b服务身份。补片交付仍不表示旧成人助手/自动任务fixture已迁移；这些旧项目瞬移会被正确拒绝，需其owner调整路线后才能称功能回归全部完成。其它洞窟政策另片审核，不随此片宣称完成。

## 地链政策小片

依赖earth纯源fixture c81b017，不开放descriptor。21001–21016为连续earth路线集合；两根`genout/wpm_200_359_671`及`wpm_200_358_671:1–3`保存成功后才进入，原LV>64/END4不变。三楼`wpm_21003_34_10:1–2`的羽毛／NOW39／END39三项OR完整保留。NPC项目到达不能自授路线，旧只持日记/项链也不能代替原路。

| 实际案例／源物理行 | 处理与此前绕过证据 | 定向验证 |
|---|---|---|
| `jaruga/event/ruri01:10–22` b0收2698/2699、给2701、Charm+1、END39 | 项目直接到21015曾可领奖；现在须真正`200/sb_dbt.arg:4–7`保存胜战并Warp21015(9,17)产生earth_final | 实际成人→公开接取/领日记→原外门→三楼OR→原多层/两实际固定战→女神，最终savefail保物品旗标，重试END39通过 |
| `ruri05/ruri06:8–16`各b0收2700、两85槽原随机池 | 同一终战后组件凭证，不能以持羽毛或NOW/END代替；未添加NOW39/END39新条件 | 真实NPC项目落点talk拒绝；合法终战组件下两b0的check_action通过；完整两池结算由earth owner并集 |
| `ruri02:8–30`b0补项链/b1REQUEST39 | 普通3413村屋，没有先过洞窟的原要求；无scope，无缺口理由是本来公开 | 真实原接取拿2699通过 |
| `ruri03:14–22`b1日记/NpcWarp | 公开200野外各原个人移动点，无洞窟前置；不锁为女神到达 | 真实公开事务给2698且个人移动通过 |
| 1146普通条件遇敌的2700羽毛 | NPC领奖已保护；捕宠便利到21002后普通战斗得羽毛是否算任务推进是独立边界，尚未新增掉落资格限制 | 明确待主裁定，未冒称这个掉落来源已由NPC终端守卫完全封堵 |

本槽真实碰撞路径从三楼原门后直找dbt邻格不可达，实际通过dtp胜Warp21009(45,48)后才走到dbt。抽象mapwarp图中21009→21010有边不证明忽略碰撞后仍能免战；政策没有新增全局dtp mark，所有可行原边仍允许，最终女神只核dbt实际胜后mark。完整真原路suite 1/1通过。Shared route driver附带兼容bonus已冻结`adult_walk_destination`只读几何接口（仅10204、has_method时调用），不将该目标作为权限或客户端传送入口。

## 水链政策小片

依赖水源片1825a7e。21201–21215及21301–21315为同一water scope，31301/31302为water_blue；路线按实际portal而不是编号。公开3400接取不加洞窟资格。正面200(73,696)原门严格LV>64/END4；后面200(316,711)原门严格LV>64/END46/2766，保留合法重返，未把它当首次完成绕过。水女神/箱不额外要求当次mzn mark，因为原END46+贝后门重返也合法；每次仍须完整已审入口及连续真实路线。

| 实际案例／源行 | 此前绕过与本片处理 | 定向验证 |
|---|---|---|
| `jaruga/event/hekisei01:10–20` b0收2769、2770、Charm1、END46 | 项目直放21215可结算；现在需water原路线到达 | 实际成人、正面原门、mzl/mzn两真实固定战、反向楼层取材料后原路返女神，实际END46通过 |
| `hekisei05/06:8–16`各b0贝换箱 | 原只持贝且LV>0，没有NOW/END门槛；新增的是原路线凭证，不修改其原条件 | 两实际NPC项目talk拒绝；完整随机奖励由水owner并集 |
| `hekisei03:18–26` b1合成2769 | 已批准原OR继续保留，但不能利用项目瞬移跳过21308(20,10)真实材料门 | 实际门前即使已持2767/2768也无mark；原门savefail不授；成功FREEWARP21308(20,7)后仅此组件water_material，实际合成通过 |
| `hekisei04:18–25` b1取/补2768 | 项目直放31302可取，改要求water_blue合法原入口及连续路线 | 5000(46,18)→31301(10,10)普通门以及40(13,1)付300→31301(10,104)两路径各自逐格到NPC真领取；前者不扣币，后者精确扣300 |

免费湖入口源`mapwarp.txt:2739–2743`及`genout/dungeon03.create:67,76,94,103`含双向入口和31301↔31302；保留所有这些原边，不创造唯一收费入口。材料房mark在成功原门事务后排队、真实Warp发布才激活，重启/离组件/项目移动同通用生命周期。

独立water suite 1/1通过（71秒），只用water owner生产命令driver，不自造凭证。隔离前置fixture明确为已有NOW46、1000金币和普通已持2767；成人END4、湖石2768、洞内两战、材料门与2769/END46均真实完成。此suite不声称复测从地/火/风完成后村庄REQUEST46的全串链，也不声称普通专用掉落来源已封闭。

### Dragon cave: original seven floors and three-jewel room

`20801–20807` now requires continuous arrival from an actual enabled `200→20801` original portal. Interior portals cannot start a new route. `npc/genout/wpm_20807_11_37:1–6` requires all three jewels and warps to `20807(13,35)`; only its successful saved action establishes `dragon_gate`. `jaruga/event/event17_1:4–12` (and the alternative `event17_2/3` branches) consumes the three jewels/flute and ends event17. These final branches require the committed gate mark as well as the original predicates. Holding the jewels or being in the room does not establish it. The mark uses the normal room-exit/epoch lifecycle.

`quest_arrival_dragon_test` uses real Backend commands through seven floors, project-to-gate denial, actual source gate and final reward save failures/retries, and reset refusal. Its inventory is explicitly preexisting test material, not a claim that wild task drops are protected. Ordinary dragon drops remain unchanged pending the dedicated-drop decision. This policy must land with the corresponding legacy helper/test flow adaptations; the isolated arrival suite does not validate the full existing UI flow.

### Marju mail: actual maze, one-way exit and public return

`genout/wpm_120_19_15:1–3` is the only reviewed original maze entry: LV>49, no fee, Warp122(6,5). Maps122/118/119 form one arrival scope. `map/mapwarp.txt:1651–1656` contains the original interior paired portals and the one-way119(103,93)→121(17,15) exit, with no reverse121 entrance. `extra/event/marju01` REQUEST38 consumes2687, gives2697 and sets END37; its MESSAGE replacement and independent ACCEPT cutting-stone branch are also protected. Being in the maze with mail/stone is no substitute for the gate and continuous route.

`extra/event/marju` on public1300 accepts the mail request and awards END38 on return using its original predicates. It intentionally requires no current cave mark after the legitimate one-way exit. `quest_arrival_marju_test` verifies real public request, project delivery refusal, original gate/large maze/portals, delivery save failure/retry, actual one-way exit, public return reward, and project replacement refusal. The independent route oracle snapshots each map's portal dictionary once per synchronous path search, avoiding repeated catalogue work without changing movement or grant semantics. Marju and Dragon route suites pass together; legacy UI/fixture adaptation is still required for release.

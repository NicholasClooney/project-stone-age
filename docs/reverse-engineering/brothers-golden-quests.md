# 五兄弟与黄金羚羊任务实现审计

依据本地 `references/chenmingbiao-stone-age` 原始服务器资料，导入白名单为 `tools/brothers_quest_sources.json`；不是用网页攻略反推旗标，也不认证其他发行版本规则。

## 实际顺序与绑定

- 五兄弟：`giiru/event/ev28_0` 等级 `LV>30` 接NOW28，五张正确答案纸2507/2509/2511/2513/2515交给 `ev28_end:9–20`，得2517并END28；随后REQUEST31，`ev28_ed1–5:9–20` 收2517并END31，分别给enemy54/57/55/56/481及2518/2519/2520/2526/2525。第五奖励按当前source481，不替换成网页版本。
- 金羊：实际 `event30.create:56–66` 的库伊30600(15,10)绑定 **`king/event69_1`**。只启用其金羊分支2–6；未绑定旧 `giiru/event/event30_5`，也不启用前后的新藏/玛蕾69/70支线。
- 采石场管理人需要END4（成人仪式）才接NOW30并给2549；原门 `genout/wpm_31903_39_4` 检查钥匙，传31904(7,3)，不消耗钥匙。`event30_2` 接NOW54。原达那/福尔德长老给线索，库伊首次借镜2547并END30。
- **没有五兄弟/金羊互锁**：五兄弟的EndSetFlg仅28/31；金羊有效分支条件和动作只涉及4/29/30/54及本链物品；`npc_exchangeman.c:1665–1678`逐项设置声明的END，`npcutil.c:1309–1332`仅OR指定bit。下面的持镜遇敌和所有本链门也不检查28/31。后做任一链的真实流程测试通过。
- **真正不可逆差异是丢镜**：`king/event69_1:28–36`需END4/29/30+NOW54+2547，收首次镜给enemy355并END54；38–46收2532只END54；58–64补发2532；67–76首次借镜2547并END30。物品说明和助手直接解释此差异。
- 原分支 `EventNo:-1` 没有清NOW54；因此END54后可再次补发2532，不能再得金羊。实现保留此行为，没有把“不能重复宠物奖励”误改成禁止全部后续对白。

## 真实之眼的完整来源

`encount.txt:345`地图31907（吉鲁采石场六楼）区域373列组521/522；`group.txt:404–405`分别要求2532/2547，成员含1055、1059、1060。`enemy.txt:699`敌人1060（模板556，原图100461，62–65级，不可抓）第一掉落为2548，概率1000/1000。沿既有权威原遇敌与击败归属结算，不由NPC凭空发眼、不手工插入怪物。

持2548回 `event30_2` 请求NOW29；`event30_7` 要END4+NOW29+END30+NOW54+2548，送31910(10,14)。真知之间原13位使者均需眼并收1个；`genout/wpm_31910_8_9`是原正确分支，送31911(6,15)，其他12位送回原矿坑坐标。`event30_6`给2551、Charm+1并END29，回库伊交首次镜领金羊。眼、镜、钥匙均不是本批登出消失物。

## 守卫、地图和物品生命周期

`300/sb_5b.create`五个原NPCEnemy位置及 `sb_5b1–5.arg` 的entype2/dieact1恢复。敌人1001/1012/1013/1014/1015使用原模板、原等级、成长与属性；胜后分别传31706(45,16)/(5,17)/(35,17)/(25,16)/(15,16)。NPC原移动没有模拟，保持原出生格。战斗使用现有AI；原战术权重、异常技能未恢复，不能称作完整原战斗AI。

导入31701–31706、31901–31911、30600及原地图中的直连门；地图原字节哈希在白名单的map_sources中。需要物品/事件的门作为原位置NPC交谈事务，不转成无条件步行门。原景观配置中的同名NPC直传门随任务恢复移除，避免绕过钥匙/真实之眼检查；这些地图不再按纯步行景观图裁剪。300(343,191)重复入口选择原dungeon02记录31701(29,49)，没有改坐标。所有新任务NPC有实际可交谈的安全落点；精灵石/精灵木占地使用现有服务器Chebyshev两格交谈范围，前端只共用纯几何offset。原NPC/道具静态图直接取2.5客户端，动态NPC取其原朝向待机第0帧，未画占位图。

itemset列78/79分别dropatlogout/vanishatdrop；`item/item.c`字段表与 `char/char.c:1445–1498`的CHAR_dropItemAtLogout交叉核实。2507–2517在权威存档重载清理，丢弃经已有物品命令删除；晶体可按原REQUEST31分支补领。后台服务器持续运行时断开查看设备不是角色登出。固定守卫战未接入中途断电checkpoint；设备断线重连继续现有权威战斗。

原数据瑕疵保留：`ev28_23`第一分支写了 `elItem`，原C不会当DelItem执行，因此不擅自修成删正确纸；记录在白名单ignored_source_fields。`event30_1`协议书及一个缺分隔符的后期条件不在本次启用分支；原source仍哈希锁定，没有修条件后悄悄扩大后期任务。

## 权威事务与可见边界

原对话继续使用服务器一次性token和再次核对分支；UI只session/snapshot/link。物品、宠物、单调UID、旗标、净容量及传送都先在候选profile修改，保存失败恢复原profile。固定战和包含1060的战斗同时恢复pending、结算奖励/捕获事件，`battle_close`重试同一结算；只有成功胜利才发布原传送。敌人掉眼沿原15格容量规则，满包则销毁掉落。

五种奖励与金羊使用原GetPet敌人定义生成1级宠物。2518/2519/2520/2525/2526/2532/2547/2551只作为原物品发放，装备属性和精灵魔法未实现，物品说明、助手和更新日志明确写出。助手瞬移绕过行走/守卫是项目便利；不扩展复杂自动任务，也不把任务NPC传送当作新增地图入口。

## 验证与导入顺序

- `tools/test_import_brothers_quests.py`：实际create绑定、排除后期支线、原EndSetFlg、原13使者/守卫动作、临时物列和限制说明。
- `brothers_golden_quests_test`：真实原任务全流程、先后顺序、五种奖励、丢镜补发差异、原敌人击败掉眼、保存失败回滚、容量与UID、一次性令牌、晶体重载、LAN同角色双设备。
- `brothers_golden_ui_test`：真实WebSocket无backend客户端，原NPC点击、确认按钮实际GUI输入、原金羊宠物图、奖励说明、960×540横屏及390×844真实竖屏点击。竖屏不使用1280画布缩成信箱；原问题、是/否选项、回答确认与奖励未实现说明均在390×844视口内。像素证明必须用真实renderer运行，headless仅验证交互逻辑。

main合入后执行（在父会话协调live停止之后）：

```sh
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/asset-venv/bin/python tools/import_encounter_art.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --sprites 100461
.tools/asset-venv/bin/python tools/pack_frame_sheets.py battle --sprites 100461
.tools/asset-venv/bin/python tools/palette_images.py
.tools/asset-venv/bin/python tools/build_exit_names.py
.tools/asset-venv/bin/python tools/plan_web_packs.py
./scripts/run.sh --headless --editor --import --quit
# 若发布网页，再生成实际资源包及客户端（build-web内部会重建plan并导入）：
./scripts/build-web.sh
```

editor命令仅资源导入，不打开窗口；build-web是构建而非发布，不操作live服务。完整初始化的encounter-art导入也已把1060纳入已审计条件遇敌图集。worktree核对主encounters/catalog后只读克隆了主catalog（补齐主已合入的稀有遇敌增量），不重导或修改那些主资料。

### 网页与像素验收

`pack_frame_sheets.py battle --sprites 100461`同时调用battle的split，故无需再全量split。100461的256帧来自本次原source导入，生成`sheets/100461.png`及`battle/sprites/100461.json`；不重打其他sprite。`plan_web_packs`的源manifest仅用于归属规划，不把battle源manifest/pets导入工作数据当运行时catalog发到网页。任务与遇敌catalog在core，任务物品图在core，NPC图在对应地图依赖或共享core；100461运行时sheet归sprite-100461。无backend远程UI通过snapshot读任务状态，原NPC/物品展示资料来自core的同版quests/catalog；本地参考数据不作为UI权威。

已实际运行planner，2584 packs、408 maps；全局归属Python13项通过，并新增本链专属catalog/NPC/item/sheet归属检查（本链Python6/6、旧任务导入Python9/9通过）。提交前Godot定向9/9通过，包含两条新suite、旧对话、sheet、split、pack与地图标签。相关地图依赖、core与sprite-100461共226个PCK已实际构建，0 failed（`/private/tmp/brothers-web-pack-build.log`）；未声称已经发布或进行了完整浏览器下载验收。`build_exit_names`移除已恢复地图30600/31701的“未开放出口”名称，生成文件随提交保留。

真实OpenGL Metal渲染，静音离屏。截图目录`/private/tmp/tmux-agents/brothers-golden-sheep-quests/proofs/`：`portrait-390x844-original-options.png`、`portrait-390x844-original-reply.png`、`portrait-390x844-reward-limit.png`均为390×844，逐张view_image验收，鼠标GUI输入实际触发按钮并核对服务器交换结果；不是headless像素。其余桌面原对白、金羊宠物与道具、横屏助手截图共7张也已检查。竖屏仅修原对话框的宽度/位置，不承诺整个旧HUD或所有菜单均完成移动端重排。

唯一全量在首次提交后执行，203/209通过（2 jobs，581秒）。六项失败不是忽略或判flaky：palette/settings/mvp_journey因world重导后遗漏既有`palette_images.py`，dana/travel_gate/travel_router因旧非任务邻格数组的GDScript类型推断不兼容。补齐资产转换与文档命令，邻格变量显式用Array，达那计数包含新恢复的原长老NPC；随后定向复验上述失败与受影响UI，不重复全量。修复后13/13定向通过（2 jobs，45秒），包含全部六个失败套件、两新suite、旧任务UI/助手、训练助手、npc_smoke与asset_packs。最终资源重新构建226 PCK零失败，真实渲染及390×844点击再次通过，十张最终截图逐张view_image。没有第二次全量。

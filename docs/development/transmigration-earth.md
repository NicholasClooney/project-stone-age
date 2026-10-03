# 琉璃洞窟（地39）第二阶段

范围是实际 `jaruga/event/ruri.create` 的六位NPC、两处原入口、三楼大地审判和九/十四楼十敌战。使用原 `ruri03` 日记分支，不替换成无此绑定的 `ruri03a`。不选 `ruri01` 的178后续绿珀石分支，不开放转生结算。

增量暂估 **1.5–2.5 SP**，以已完成 Samgir=1、村民对话=0.5 校准。复用现有服务端事务、物品UID、保存失败重试、NPC个人状态、多敌战、条件遇敌、原地图与模块注册；共享底座只计一次。主要工作是源分支/奖池字段审核、路线与助手授权、事务/LAN与390渲染验证。显式单件pile共享审核由独立owner提供，不计入本链共享开发。

## 规则与实现范围

- 拉鲁在完成成人仪式后发出39委托与2699项链；遗失可补领。伊布在NOW39且缺2698时给日记并执行原个人移动；原位置列表重复项保留。
- 两个入口均需LV>64且END4。三楼审判照源接受羽毛2700、NOW39、END39三者之一，不收费不删物。
- 九楼/十四楼分别沿用原十敌顺序与胜战Warp。原战术与七技能槽保留审计，战斗只使用现有AI，不宣称原特殊招式恢复。
- 蒂亚特需NOW39及两件材料；裸DelItem同时删除全部2698/2699，给2701、魅力+1、END39。重试与最终写盘沿用共享候选profile事务，不能重复核心奖励。
- 敌1146只有2700一个掉落槽，原概率1000/1000；group605在持日记2698时排除。完成核心消耗日记后可再次遇到。并未新增捕获奖励。
- 两袋只要求LV>0和羽毛，不额外要求NOW39或END39，不添一次性标记。每次收掉全部羽毛，按原重复槽抽一件，容量按原删除后的净背包格数检查。
- **项目修复**：依据2026-10-03用户B，修复原256字节读取截断；两袋各85槽，恢复第57槽957与尾28项。原C误产生的95不属于完整池。大袋67种、小袋57种，全部有效，重复槽是权重、不去重。详见 [逐项奖池证据](../reverse-engineering/transmigration-earth-rewards.json)。21种材料经共享显式pile审核，原C单次创建数量1、独立空格，不扩堆叠。
- 统一装备片已接入原固定攻击/防御/敏捷/魅力和耐久，真实五槽穿戴；魔法、抗性、连击/投掷特殊行为、材料合成仍未实现。2699回避+2仍仅metadata。项链/羽毛穿戴后不满足裸ITEM背包条件，须卸下交付；保留原UID。

助手两mode、raw NPC和旧step最终均重新核服务端当前步骤。洞内同时重验通用合法到达接口、当前原分支与近谈范围，两mode均返回角色当前格。连通组件仅作为附加几何条件；楼梯、其他NPC及守卫格从连通图排除。原门/守卫仍须亲自提交，助手不代执行。伊布个人位置从实时NPC投影读取。

## 导入与验证

独立 `pool-a --import` 工作树完成以下完整实际导入链。`.tools` 与 `references` 是只读共享，`client/assets/legacy` 是独立克隆；不要在素材软链接工作树执行导入。

```sh
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age
.tools/asset-venv/bin/python tools/palette_images.py
python3 tools/split_manifests.py
python3 tools/plan_web_packs.py
./scripts/run.sh --headless --editor --import --quit
```

本树在共享底座已有原基础素材的前提下，实导入450地图、1589原portal、4751图像，253任务NPC及232去重物品；地链自身11NPC、99声明物品。最终四链整合的总数由独立静态oracle审定，不能沿用这里的单链总数。共享pile依赖为 `38285f032186e8999fa7fd116924d7a6787c0f7c`，142装备及其注册依赖 `d62618d3d3d834d765a6a7602c8910d0af9e112b`、`de6fc61ec4c54483d6421055c6989074b531b611`（主分支等价提交可替代）。

通用到达依赖：`799d9cc`、`7cbcc3b`、`21acb34`、`b2c9ad1`、`3b5790a`、`372481b`。地专属policy已接 `6a9343aec515b40e825cb909df827eca76ff90df`；另接其测试所需成人真路线driver `37a768cc0d47942e072a0ea072b68cf00df78b19`。helper只调用共享接口，不创建scope或凭证。scope是21001–21016原连续区域，descriptor仍仅开放已审21001–21015；两外门保存成功才进入，dbt原胜Warp21015(9,17)才产生女神/两袋凭证。未强加全局dtp旗标；实际本槽碰撞路线需要其跨岸胜Warp。公开3413/200的拉鲁/伊布不加洞窟门槛。

定向命令：

```sh
.tools/asset-venv/bin/python tools/test_transmigration_earth.py
.tools/asset-venv/bin/python tools/test_transmigration_earth_assets.py
./scripts/run.sh --headless --script res://tests/transmigration_earth_test.gd
./scripts/run.sh --headless --script res://tests/transmigration_earth_route_test.gd
STONE_AGE_FOREGROUND_TEST=1 STONE_AGE_PROOF_DIR=/private/tmp/tmux-agents/spirit-earth/shots ./scripts/run.sh --position -2000,-2000 --script res://tests/transmigration_earth_ui_test.gd
```

到达政策接入前的已验证结果：源3项、素材2项通过；事务（UID、实际保存失败重试、重复、穿脱裸ITEM与双远端）、完整原碰撞路线和390静音离屏真实点击均0失败。路线实际走两入口之一、三楼审判、九楼/十四楼各十敌战，交双材料，沿楼梯与九楼石床回二楼后自然遇敌得羽毛。另一入口的条件/绑定由源断言覆盖，尚不能称两入口皆已自然走完。UI最终楼使用显式隔离位置fixture，不能代替自然路线或通用到达证明。

证据根目录 `/private/tmp/tmux-agents/spirit-earth/`：`runtime.log`、`route.log`、`ui.log`、`assets.log`；`shots/earth-02-original-request.png`、`earth-03-original-diary.png`、`earth-04-goddess-core.png`、`earth-05-original-core-reply.png`、`earth-06-bag5-original-choice.png`、`earth-06-bag6-original-choice.png`、`earth-07b-bond-equipped.png`。随机效果摘要呈现修复另有 `effects.log`、`summary-ui.log` 与 `shots/earth-summary-390-bag-actions.png`、`earth-summary-390-full-explanation.png`，均已逐图检查。原奖池完全不改，正常固定奖励仍保留逐项未实现限制。

只跑定向，不跑full，不修改main/live/真实save。上述政策前证据保留供审阅；政策后的最终报告另记，不能覆盖旧日志掩盖验证范围。


## 地policy接入后的验收记录

`runtime-final.log` 已通过0失败：从公开原入口、三楼OR门、实际dtp/dbt原十敌战到女神区，分别核原敌顺序/素材、两战真实保存失败重试与胜Warp；核心双材料/UID/魅力/END39的保存失败、重试、不可重复与重载；两袋完整85槽、多羽毛消耗、穿脱裸ITEM、保存失败后新令牌重试与重复领取；复用同一实际合法角色运行两真实WebSocket设备，旧令牌与奖励字段伪造、跨端重放均拒绝。两设备共用角色内存资格，没有复制scope或mark。

项目放到同一组件不能获得资格；raw NPC两mode、旧step与三楼门均拒绝。`transmigration_earth_arrival_test.gd`另核最终transact不依赖助手重验及合法近谈两mode无位移；`transmigration_earth_ui_test.gd`已移除终点位置fixture，逐原碰撞/portal报告走完整洞窟、真实两战，阶段按钮和对话/两袋/装备是真实390静音离屏指针点击。后二者本轮均0失败：`arrival-final.log`、`ui-final-labels.log`。最终17张图在 `shots-final/`，均已逐图检查；原入口、审判、两守卫、女神、两袋和装备按钮没有越出390边界，长文本可实际滚动。UI行走用测试驱动的真实服务端逐格报告，战斗用真实command/保存/close；阶段/对话/装备用实际指针点击，不声称每一个步行格和攻击都由手动点击。

仍明确的共享边界：1146普通条件遇敌掉羽毛的来源资格，由主协调另行裁定。当前 `reviewed-hunt-travel.json` 的51个捕宠白名单目标仅在41、42、31806，未授权21002直达；当前地羽毛缺口涉及通用项目移动和不可信wild位置，后者正由共享owner修复。未来若扩大捕宠白名单到地洞窟，需要另核该来源资格，不能将未来扩展说成当前入口。本片未自增掉落禁令，不能声称NPC终端凭证已经覆盖这项掉落。第三阶段、原特殊战术及已列inactive效果保持关闭/未实现。

政策后原完整往返与自然遇敌 `route-final.log` 0失败；原实现176.64秒，随后移除遇敌相邻每步重复读整图/BFS的测试冗余，仍由真实report_position/field_step与战斗完成验证。此优化不改生产代码、遇敌概率或掉落资格。

优化后的自然路线 `route-final-efficient.log` 仍0失败，`/usr/bin/time -p`实测126.62秒（user125.27/sys0.78）；没有扩大suite预算或跳过真实路线。


## 公共oracle候选状态

水链先前13NPC/55物品核对只覆盖当时的候选，不是最终冻结集合。后续已授权恢复原材料入口 `genout/wpm_300_247_222`：锁源 `genout/dungeon01.create:2326` 绑定，原脚本为 `LV>64&ENDEV=4`、Warp `30301,23,37`；water owner负责精确gate与restored_scripts。待实际水提交后须增量重核真实create身份、原条件/动作、manifest和最终物品并集，不能继续冻结旧13NPC数量或仅把计数宽化。旧已核记录保留为历史证据。

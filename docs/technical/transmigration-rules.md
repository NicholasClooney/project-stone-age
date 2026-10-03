# 第三阶段纯规则与原 C oracle

`transmigration_rules.gd` 是无 IO、无 profile mutation 的纯函数，尚未连接生产服务。I 拥有 `SAVE_VERSION=7` / `rebirth.schema=1` 保存契约；本模块不定义持久字段，不替服务验证到达、距离、忙碌状态或本次宠物所有权。

最新用户裁定：END53四信物奖励关闭；金币统一 `Session.MAX_GOLD=1000000000`，不随转数改变；未知旧正转历史保留资产、禁止捏造累计参数；物仓3000格免费不变。多代理包先进入 `integrate/stage-three`，由集成方统一 full 全绿，之后主才快进 main / 重启。worker只跑定向，不操作live。本片不需要金币函数，也没有切换原金币上限。

## API（冻结合同 v1）

`inherit(base_fixed, old_equation, old_level, new_count, completed_quests)` 返回 `{ok,new_count,equation,base_stats,stat_points,ans}`；失败 `{ok:false,reason}`。stats键为vitality/strength/toughness/dexterity，单位百分之一点。`new_count`为已加一的1..5；`completed_quests`为清旗标前本轮END计数。参数以Variant做严格有限整数校验，接受JSON整数float，拒绝bool/小数/NaN，避免GDScript类型转换先截断非法数值。

`valid_history(count,equation)` 验证旧累计值的自然范围：高16位Q满足0..20*count，低16位L满足80*count..130*count，零转只能equation=0。不推断未知历史。字段缺失由I区分 `zero` / `natural` / `legacy_unknown`；不要把未知正转传0冒充历史。

本轮贡献先累计 `q` 与 `min(level,130)`，再按原C公式分配。等级最低80，纯公式输入最高C int上限（不承诺生产允许此等级），基础单项沿现角色校验上限100000000。零总量拒绝，避免原C的0除；这项是项目输入保护。继承不进GM赠点；stat_points只为新转数×10，旧未分配点被原Main覆盖。

## 原源与数值顺序

本地社区快照 `references/chenmingbiao-stone-age` revision `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`，并非官方年代认证。逐文件原字节SHA256在 `tools/transmigration_rules_sources.json`，oracle编译前强制校验。

- `gmsv/npc/npc_transmigration.c:699–713,733`：先增转数/Status，Lv1、EXP0，自由点最终覆盖10*n。
- `:804–821`：float P=四原基础值和/100，float累计Q/L、新n；A=`int(P/12+Q/4+(L−85*n)/4)`，向零截断，不能把Q/4先整数除。
- `:826–835,844–911`：float tmp=单项/总量*A；`Rounding(tmp,1)`实际是tmp+0.5，float返回后float乘100再int；不是`round(tmp)*100`。负A不提前裁0，负的最终单项才裁0，零比例也可能获得50个fixed单位。四项和不强行归一至A*100。
- `:866–877`：本次等级最多累计130；不是改角色最高等级。

Godot float64通过 `PackedFloat32Array` 显式round-trip至binary32：int转float、float除法/乘法/加法各边界按C顺序；Rounding的0.5为double，最后才收窄float。没有用整数近似公式或Godot常规round。

## 独立原C验证

运行 `python3 tools/audit_transmigration_rules.py` 会从SHA锁定原文件**原样抽取** `NPC_TransCalculation`、`Rounding`、`NPC_TransmigrationStatus`，以最小字符字段/通知stub实际编译并运行。公式没有重写为Python参考实现。`--write`显式重建 `client/tests/fixtures/transmigration-rules.json`；默认将新编译输出与已提交fixture逐字比较。fixture不是由待测GDScript生成。

固定 `-std=c99 -fno-fast-math -ffp-contract=off`，分别编译 `-O0` / `-O2`并要求相等；oracle拒绝非32位float/int、非IEEE binary32有效精度、`FLT_EVAL_METHOD!=0`。这锁定现代严格binary32执行语义，不声称验证所有历史x87 excess precision或原服务器构建。本机：Apple clang17，851组真实C vectors与Godot一致，包括五转累计、等级130封顶、非整数比例、2^24附近、负A、旧自由点覆盖。未启动原服务器。

Godot定向：`./scripts/run.sh --headless --script res://tests/transmigration_rules_test.gd`，测试不创建Session、不读存档。sandbox首次阻止Godot测试日志目录导致启动logger崩溃；允许隔离测试目录后重跑51组0失败，非规则断言失败。无full、无导入、无live。

## 完整纯规则接口与边界

- `quest_count(events)`：now/ended各六个uint32值，非法-1；仅计END。anson `Serv.zip` 中 `gmsv/npc/npc_transmigration.c:916–917` 的20项（包括14/44/45）替换chen快照20表，属于已裁定源配置组合。ZIP/成员SHA均在辅助oracle强制核验并写入fixture，QuestCheck函数仍原样编译。
- `flags_after(events,new_count)`：原C1002–1084，启用 `_PET_TRANS` 旗标保留与 `_NEWEVENT` 六字配置，但不开放宠转生业务；END69/70/71/72/109/118/122/131/127/158/159、NOW69..72仅保旧值，再补END48..47+n。输出新对象。
- `sacrifice_templates(new_count)` / `select_sacrifices(pets,new_count,selected_ids=[])`：原C1133–1185；只接完整随身数组，容量由Session校验，默认每种模板首次命中，五转按693..696模板序返回；不加等级限制。既有`species="original_N"`为模板身份、`pet_id`为字符串UID。项目补充显式UID选择及现有30槽随身容量兼容，按整个数组原顺序首次命中；拒缺失/重复/错模板；不接宠仓、不执行删除。服务仍须验证profile/所有权/净容量。
- `reward_for(savepoint_bits,new_count)`：原C510–520只看低四位首置位，较高位忽略；无出生拒绝。777/ten.arg1–4的Present与Warp，enemy.txt1009–1013的模板映射；不处理成长随机数。Item/Pet仅metadata，函数不收费。

辅助oracle编译原 `NPC_TransmigrationQuestCheck`、`NPC_TransmigrationFlg_CLS`、`NPC_StartpointCheck`、`NPC_TransmigrationDelPet`，仅字段/位存取、宠物索引与删除记录用stub。旗标setter不模拟家族贡献/通知，纯规则不负责这些副作用。事件394组覆盖全部384个NOW/END单独位及五轮全0/全1。献宠穷举15625组（五种模板/空槽的五槽排列×五轮）；fixture保留每种转数/成败/原槽输出组合代表，Godot逐代表校验。奖励32种出生位×5轮共160组，村索引由C执行，Present/Warp/enemy期望从SHA锁定源表直接读取。

本次Godot首跑暴露JSON数组浮点值与整数数组比较类型不同，测试显式转换期望数组为整数后851属性组、394事件组、祭品代表及160奖励组全部0失败。数值与源规则实现未为绕过测试改写。输入只读断言及非法历史/零总量/小数/UID保护额外覆盖。

全模块未连接生产，不开放精灵王、转生、六七转/PETTRANS或Boss技能。原技能仅metadata的现有限制仍在，不能据纯规则通过宣称原AI已恢复。API未增加保存字段；金币无需额外函数，始终由Session.MAX_GOLD统一。

30槽兼容测试独立于原C oracle：第6/30槽、30槽混合默认/显式UID、五转四模板及非法UID均覆盖。原C `CHAR_MAXPETHAVE=5` oracle保持原样；不把项目既有30槽容量宣称为原C行为，纯规则也不硬编码新的容量上限。

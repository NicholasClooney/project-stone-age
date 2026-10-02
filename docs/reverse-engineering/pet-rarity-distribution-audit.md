# 宠物稀有度共享分布表：第 1 步只读审计

日期 2026-10-02；仓库 `/Users/nicholasclooney/Source/Projects/projects-stone-age`。本轮只读产品源码、原始参考数据与既有分布；实验均在 `/private/tmp/tmux-agents/pet-rarity-distribution-audit/`。无产品改动、无 branch/commit、无 relaunch、无 live/save 操作、无 full suite、无子代理。

## 结论与决策建议

1. **当前 `species_potential.json` 的 `max` 是百万样本最大值，绝不是自然成长上界。** 红人龙是 `original_94` 邦奇诺（满档百万样本 max 633），蓝人龙是 `original_92` 扬奇洛斯（625）；不能把 `red_rex` 当红人龙：它映射 `original_303` 巴朵兰恩，见 `client/scripts/pet_comparison.gd:6`。
2. 理想独立 RAND 模型的四项边际分布可精确写成有限多项式卷积；三围合的三项相互相关，且各自截断，不等于三个边际概率相乘或简单独立卷积。完整精确联合 DP 朴素实现不可接受。FFT 的 double 结果只是对精确模型的数值近似，不能叫逐概率位精确。
3. 真实服务器每级用同一 `growth_seed + level*104729` 重设 PCG，等级之间不是已证明独立。野生 `growth_seed` 是 **32 位输出**；GM/synthetic 的 seed 与出生直接共用，野生出生来自上游 PCG 流的先前输出。只有定义抽样空间后才可谈实际 seed 精确概率。理想 RAND 卷积不等于实际 seed 精确枚举。
4. 第一版推荐服务器共享构建期直方图/生存函数表，所有已知数值品种共同发布；至少保留五项 attack/defence/speed/max_hp/**sum=attack+defence+speed**，sum 不含 HP。建立规则、出生口径、样本量/命中量和置信区间元数据，表外不返回概率 0 或无限罕见。
5. 不应立刻承诺所有品种 10 亿样本或全联合精确 DP。先校准代表品种、评测共享 PCG seed 扫描与尾部，再决定按品种自适应采样或条件 seed 枚举。UI badge、tooltip、移动端点击解释属后续实施，不在本轮。

## 代码与原 C 的规则证据

| 规则 | 当前代码 | 原 C 与注意点 |
| --- | --- | --- |
| 四项先天偏移各 −2..+2 | `client/server/progression.gd:59-63`; 野生 `client/server/encounter_catalog.gd:124-129` | `references/chenmingbiao-stone-age/gmsv/char/enemy.c:1041-1044`，每项 `RAND(0,4)-2` |
| 偏移后的成长权重先保存，再加出生 10 点 | `progression.gd:62-64`、`encounter_catalog.gd:125-129` | `enemy.c:1046-1058`，`CHAR_ALLOCPOINT` 保存先于额外十点；十点只是出生 base，不是永久成长权重 +10 |
| 指定满档仍消耗四次偏移 RNG | `progression.gd:60-61` | 固定 offsets 只替换抽样结果，不省调用；GM seed 的出生序列位置因此不变 |
| 出生 base | `progression.gd:71` / 野生 `encounter_catalog.gd:139` | `enemy.c:1036,1061-1064`：`(initial+(L-1)*wild_growth)*(weight+birth_extra)` |
| 原 wild_growth 的 4.50 读成整数 4 | `tools/import_encounters.py:196` 与 catalog `raw_growth=4.50,wild_growth=4` | `enemy.c:295` `atoi(token)`；内置 species_actor 的默认 `wild_growth=4.5` 是另一口径，不能拿原表 4 默认替代它 |
| 成长 rank | `progression.gd:65-70`、`encounter_catalog.gd:133-138` | `enemy.c:767-797` 用**模板原始四项和**，不含偏移/十点。阈值 >=100,95,90,85,80,0 → rank 0..5 |
| 各等级十点再抽倍率，共享倍率 | `progression.gd:81-86` | `references/chenmingbiao-stone-age/gmsv/char/char_data.c:1205-1246`，倍率 450..500 +20*rank（端点都包含） |
| 每级各 base 增量的整数截断 | `progression.gd:86` | 原 C `char_data.c:1214-1216,1239-1256` 用 float32，先分别乘权重和额外点再相加；当前代码有意改为整数。不能把原 C 浮点分布说成现服完全相同 |
| 四项 derived 的截断顺序 | `progression.gd:30-40` | `references/chenmingbiao-stone-age/gmsv/char/char.c:2855-2878,2905-2910`；交叉贡献先求全表达式再截断，不是分别截断 |
| 实际 per-level seed | `progression.gd:79-85` | 项目重设 seed 策略，原 C 全局 rand 流没有这条规则 |
| 实际野生成长 seed | `encounter_catalog.gd:129` `rng.randi()` | uint32 输出；出生十点与之后 growth_seed 位于同一上游流，不可先验断言独立 |
| 原 C RAND | `references/chenmingbiao-stone-age/gmsv/include/util.h:79-80`；`char_data.c:1092` | floor(rand * interval/(RAND_MAX+1))；interval=5/51 一般不整除 RAND_MAX+1，存在微小离散映射偏差，更不是严格理想均匀 RAND |

既有 `docs/reverse-engineering/pet-birth-audit.md` 报告：枚举 215,424 个 float32 增量组合，520 个少 1；例如 weight=24, extra=1, roll=452，原 C 112，当前 113。它的脚本已删除，因此此数字是已有报告证据，本轮没有重新声称完成该枚举。当前 `progression.gd:75-77` 明确维持整数决定。

“满档/10档”必须解释清楚：本项目满档是四项 offsets=[2,2,2,2]，总偏移 +8；自然偏移组合共 5^4=625 个，理想满档概率 1/625。相对最低 −2 的四项总共提升 16，也不是 10。每次分配的 **10 点** 与满档不是同一个概念；当前代码不存在官方“10满档”的额外规则。`client/scripts/pet_hunt_rules.gd:58-65` 是理想出生偏移组合计数。不要将条件满档成长的 1/N 再解释为每次遇敌的 1/N；要乘出生条件、该物种/等级遇敌概率，且实际流相关仍需定义模型。

## 概率模型：明确什么可以精确

固定模板 w0、rank r、捕获等级 L、目标 120，先条件化全 +2，令 w=w0+2，F=initial+(L-1)*wild_growth，m=120-L。

理想模型：出生与每级额外分配 E0,E1,…,Em 独立，均为 Multinomial(10;1/4,1/4,1/4,1/4)。每级 R 独立均匀整数 low..low+50，low=450+20r，亦独立于分配。对于 e 的概率：

`p(e) = 10!/(eV!eS!eT!eD!)/4^10`, `sum(e)=10`；共 C(13,3)=286 种。

`B_i = trunc((w_i+E0_i)*F) + sum_{j=1..m} floor((w_i+Ej_i)*Rj/100)`。

原表 F 为整数、base 非负，trunc=floor；内置或特殊 definition 浮点 F 必须保持 `species_actor` 同一步骤。负权重/非法人工数据不能套 floor 与正数证明。

最终：`A=floor((2V+20S+2T+D)/2000)`；`T=floor((2V+2S+20T+D)/2000)`（此处字母 T 在右侧指 toughness base）；`Dsp=floor(D/100)`；`H=floor((4V+S+T+D)/100)`，然后按 `derived` clamp HP/attack/speed>=1、defence>=0。三围合 `Q=A+defence+Dsp`。

单项取线性 numerator c·B。出生多项式 Bc(z)，每级增量多项式 Kc(z)，则精确模型 `Pc(z)=Bc(z)*Kc(z)^m`；最后按整数 divisor 聚合到显示属性 bin。各个 K 都必须从**联合 e 和同一个 R**枚举，不能拆四项独立 binomial 后相乘。E_i 的协方差为 −10/16=−0.625，方差 30/16=1.875，共享 R 又引入额外相关。

三围合有三个 floor：令 Na=2V+20S+2T+D，Nd=2V+2S+20T+D，Ns=20D，C=Na+Nd+Ns=4V+22S+22T+22D。`sum floor(N/2000)` 不等于 `floor(C/2000)`，误差可为 0、1、2（clamp 另外处理）。保留 (Na,Nd,D) 三维联合分布足够；或保留 C 与 Na、Nd 的模 2000 余数，D 模100由可达同余关系确定。这样的压缩仍是高维状态，不是独立三边际相乘。

实际 PCG 模型：给定 seed，所有等级结果确定。`tools/fast_hunt/fast_hunt.c:124-143` 是本地 Godot PCG 镜像，`:333-337` 实现真实逐级 seed 与截断。PCG 内部 state 64 位，inc 固定；rng 的 uint32 output 与 seed 输入宽度不是一回事。野生 growth_seed 域 [0,2^32-1]；GM `randi()` 同为 32 位但出生直接由该 seed 生成；内置 next_battle*7919 等确定性种子和保存验证的更宽 seed 见 `game_session.gd:156,206,536,1553`，不能统一称 32 位世界。

三个不同的“精确”必须分别标注：

- 理想 RAND 法则上的精确分布（DP/卷积）；
- 全 2^32 **growth seed** 与固定出生 base 的精确频数（明确均匀 seed 这个测度）；
- 真实捕获条件下的上游 encounter seed / PRNG state 全枚举（物种、等级、满档、出生、growth seed 联合条件）。这通常是更大的 64 位空间/上下文，不等于前两者。

## 实验、重现与统计解释

文件均在报告目录：`audit.c` 是从 fast_hunt.c:125-143 拷贝的 PCG + 同公式；`verify-native.c` 多打印 known seeds；`server/progression.gd` 是原文件只读拷贝；`verify.gd` 用该真实 GDScript 出生、`project_pet` 和逐级 `grow_pet`，assert 两者 base 相同。`kernel_bounds.py` 枚举联合 kernel 与支持宽度。结果见 `blue-results.txt`, `red-results.txt`, `blue-100m-results.txt`, `red-100m-results.txt`, `godot-results.txt`, `verify-native-blue.txt`, `verify-native-red.txt`, `kernel-results.json`。

重现（从 repo root；输出全部 /tmp）：

```sh
cc -O3 /private/tmp/tmux-agents/pet-rarity-distribution-audit/audit.c -o /private/tmp/tmux-agents/pet-rarity-distribution-audit/audit
/private/tmp/tmux-agents/pet-rarity-distribution-audit/audit 20000000
/private/tmp/tmux-agents/pet-rarity-distribution-audit/audit 20000000 red
python3 /private/tmp/tmux-agents/pet-rarity-distribution-audit/kernel_bounds.py
.tools/Godot.app/Contents/MacOS/Godot --headless --audio-driver Dummy --path /private/tmp/tmux-agents/pet-rarity-distribution-audit --log-file /private/tmp/tmux-agents/pet-rarity-distribution-audit/godot.log --script res://verify.gd
```

Godot headless 成功退出；sandbox 阻止它为临时工程创建默认 app_userdata 目录（stderr 记录），脚本完全不读写 user://，实际 log 与结果仅 /tmp；没有访问游戏存档。临时 project 的 custom_user_dir 设置没有解决 macOS 路径拼接，Godot清理custom_user_dir_name中的路径穿越为短横线，不能用它重定向绝对目录；若后续重跑希望清洁 stderr，应在隔离宿主设置中正确配置 user-dir；不能以忽略报错掩盖存档隔离需求。

目前完成的 2,000 万连续 seed（0..19,999,999）结果：蓝 max626，seed **2755508**：attack293, defence180, speed153, HP1309；base(V,S,T,D)=19394,25327,12789,15305。真实 Godot 完全相同，且逐级与 project_pet 完全相同。已证明表 max625 不是可达值上界。seed0,1,12345 的蓝/红 Godot base/属性亦与 native 完全相同。

此实例由 species_actor 的合法满档出生生成，是当前 GM/synthetic seed 口径下的有效个体，不是把它冒称为已证明出自某次野生 EncounterCatalog.actor 的捕获回放。用户已有蓝627、红634是任务提供的观测；本轮不读取 live/save 作确认。既有 `docs/game-systems/pet-quality.md:42` 的独立 xoshiro 4 亿样本已出现蓝627，也进一步否定百万样本625为硬上限。后附 1 亿实际 seed 扫描会给出更强 knownseed 证据。

2,000 万扫描红 max633；不能因为这批没有634就推翻用户的634。蓝 >=626 共8例，对**连续种子集合的频数** 4e-7；这不是随机 iid 抽样的置信区间，也不自动覆盖全32位域，不能拿它直接替代生产全域概率。rate 约 0.728M pets/core-second（两程序同时运行；20M 各 CPU 27.46s）。

## 精确计算复杂度、边界与构建预算

蓝满档 L1 的联合单级事件 286*51=14,586，可合并相同增量。`kernel-results.json`：

| metric | 单级非零 bins | 单级整数 numerator 宽 | Lv120 numerator 支持宽 |
| --- | ---: | ---: | ---: |
| HP | 235 | 257 | 31,335 |
| attack | 1,037 | 1,431 | 175,681 |
| defence | 1,014 | 1,251 | 154,261 |
| speed | 64 | 64 | 7,788 |

单项直接 DP 大致 `O(m * final_width * kernel_nonzero)`，蓝 attack约1.1e10 multiply-add（考虑宽度线性增长的1/2），其他另计；每种几十秒到多分钟/小时取决语言和算术，未经性能实现不作确定承诺。double 内存仅数 MB/metric；数学精确整数分母 `4^(10*(m+1))*51^m`，L1约1,875 bits，整数 count 每格约235 B起，不含 bigint开销，attack一份约41 MB；逐层、工作缓冲另计。FFT 提速需要明确浮点误差；NTT/CRT 若要 exact integer counts，约63个30bit模数与多次大变换，开发、计算成本显著高于普通 FFT。

四 base 朴素联合 DP 的末层范围宽 (8145,8740,7550,7788)，乘积 **4.186e15** 格；单double约33.5 PB，支持并非全满但没有已证明足够稀疏的保证。换 (Na,Nd,D) dense 约175681*154261*7788≈2.1e14格，double约1.7 PB。C+余数同余压缩可减少，但仍可能 billions 状态，不应承诺 1-day 实现。探索 gcd/对称性、舍入 residue 有价值，不过必须实测状态数后才下结论。当前每级 e 总和固定不代表 base 总和固定，roll 与各项 floor 会改变总 base，因此不能把4D随意降成3D base。

**安全上界** 可无需概率求出：正权重下各项单步上界取最大倍率并枚举286分配，最后执行 derived。现有 `client/scripts/pet_growth.gd:7-48` 已对每个单项计算这种理想可达上界（各项不一定同一宠达到，不能相加叫精确三围上界）。三围的保守联合界可用 C=4V+22S+22T+22D 的出生最大 +m倍单步最大，然后 floor(C/2000)：蓝663、红671。这是安全上界，非实际 seed 可达最大，也非非常稀有的概率；和 sampled max625/633 相距很远。

真实32位 seed 全枚举：以0.728M/core-s算，单模板约5,900 core-s=1.64 core-hour；431 distinct definitions（459 species、其中19个wild basis）无复用约706 core-hours，14核理想50小时，计负载/IO/更多basis约2–5天 wall-time。以上CPU时间推算不是实测全域。固定出生可做32位全域精确频数；GM/synthetic 出生也由同seed决定，一并枚举容易，但必须名称标明GM/synthetic测度。真实野生的出生额外点+growth seed不能自动按独立联合枚举。

**共享 seed kernel 的优化**：对所有species的同一个 seed/lv，四维 e 可重用，rank的 roll范围虽不同但 bound51相同，可共享 bounded(51) offset（各rank只加不同low）；每维增量是 floor((w+e)*roll/100)，可按 rank,dimension,weight 预累加一次，再为模板加上119层累计。相同 definition去重（当前431）与相同权重复用可显著减少重复PCG。只需分块处理 seed，不能保存全域每seed每weight数组（数TB）。此法仍须明确定义出生模型/level L，并对完整与最低wild两套使用不同step起点。它优化实际seed枚举成本，不证明出生与seed独立。

条件 DP/枚举备选：

- 给定真实出生 base 与weights，枚举全32位growthseed是明确定义的条件seed分布；真实生产seed与该出生条件的测度仍未必均匀。
- 给定成长seed枚举出生286种，再以multinomial权重加总，可构建“独立出生 + uniform32 growthseed”的**混合模型精确分布**；代价2^32*286末端派生/模板≈1.23e12计算，需要差分/分段优化。不应叫真实捕获联合概率。
- 全上游64位 seed 2^64 比32位再多2^32倍，一般不可做；只有定义特定有限 runseed/index区间，才可能精确那个区间频数。原C全局rand的 seed/state空间与当前PCG也不同。

采样备选：原生1e9/species，5项uint64 histogram，sample max仅事实；需增加defence/speed/HP bins，sum保持联合直接测量。当前 `tools/species_potential.c:39` histogram是uint32，1e9仍能容纳，未来>2^32累计会溢出，推荐全uint64；`:86-87` 将超bin上限折到末bin会造成假尾部，必须动态/support bounds、assert或显式overflow，不能静默夹断。

现有全459×1e6+19wild约4分钟/14核（`docs/technical/species-potential.md`），简单×1000约**67小时/14核**，与上面的实际PCG估算相近量级；单品种尾工具旧报告400M/80s/14核不能直接套到所有品种流水线。1e9尾模拟一次约几分钟多核，但全物种约2–5天。先做1–10M全覆盖（分钟级），主要品质档阈值几乎均可稳定，再给极稀有品种升100M/1e9或对实际32位域扫全。

存储：共享最终5个显示属性的dense uint64 survival arrays，即使约1000 bins/metric，459species×5×1000×8≈18.4MB/basis；当前大多数更窄，稀疏/变长offset压缩通常数MB。添加19 wild远小于两倍。加载后按metric,value-min直接索引O(1)，无需每人模拟；内存中用PackedInt64Array/Float64Array，JSON数字Array/Dictionary的运行时膨胀要测。构建工件可压缩，存完整counts,N和方法元数据，probability只在服务器按count/N算。

## 尾部、置信区间、tie 与边界产品规则

定义上尾 **inclusive** `S(x)=P(X>=x)`；每只宠的“前x%”=100*S(observed)，同一整数同百分位、同badge。N等于1/S只是该口径下的条件期望等待数（独立同分布重复试验时），不是地图遇敌成本。极端尾部显示“约1/N”加“估计/未充分采样”；用科学记数法避免四舍五入成0。

档位建议 conservative：普通 >10%，优秀 <=10%，稀有 <=1%，极稀有 <=0.1%，传说 <=0.01%；如要百万分之一档，默认不启用，需至少足量命中与CI支持。这些是开发便利评级，不冒称原版官方档位。<=门槛比较inclusive tail，整点tie不强迫精确占满1%；例如蓝>=621理想采样约2.11%，尽管当前 `top1`=621，不能说621本身是前1%。当前 `species_potential.c:91-94` 从大到小累计直到 c>n*top，返回的是分位切点，不是 cutpoint 的inclusive tail恰好<=top；如果做badge应直接查S(x)，不能复用top字段。

在 iid uniform样本模型明确成立时，k/n点估计，普通尾部用Wilson或Clopper–Pearson；稀少命中可使用精确二项CI或小p Poisson近似。相对标准误≈1/sqrt(k)，95%相对半宽≈1.96/sqrt(k)：k=100仅±20%，k=400±10%，k=1000±6.2%；n=1e9、p=1e-6约1000命中可用，p=1e-8约10命中误差~62%，p=1e-9约1命中不可靠。连续seed扫描和确定性xoshiro单流没有自动iid保证，CI只适用于明确抽样测度/随机采样方案，需多独立seed/批次检验与实际PCG校准。

零命中：95%单侧上界 `1-0.05^(1/n)`≈2.996/n；1e9样本未见仅说明 p<约3e-9（在抽样假设下），不说明p=0，更不能肯定“比十亿之一更稀有”。表外高值应显示“超出样本范围；未估准”，给CI界/“样本中0例”，N未知。位于已证明不可能的安全上界之外应显示“口径不匹配/人工或异常数据”，不是无限极品。可采用 (k+1)/(n+1) 作有说明的平滑显示，但这不是精确p，仍需CI。低于表min自然tail=1若全support已覆盖；采样min之外则要保留未观察低尾信息。

## 共享权威与适用范围

- 模型 key至少包含 template/definition-hash、rules revision、capture level、target level120、offset condition、method (ideal / empirical PCG / seed-exhaustive)、n或seed-space。名称/sprite不够，同名模板initial可能不同。
- 满档表标注“同种Lv1满档自然培养群体”。对非满档可以仍与满档参考群体比，但必须明确“满档基准”；若要它自己档位条件的百分位，要625 offsets 的混合/独立表（全自然population表是各偏移tuple混合，不能把全+2尾p统一除625当任意自然属性尾p）。
- wild表只适用于记录的最低wild等级；其他实际捕获等级不能套最低表。需要记录capture level/birth provenance，旧保存若没有而已升过级，不能从当前level猜捕获level。
- 正常GM发放是 `game_session.gd:1810-1827` 的同公式自然参数生成，未标gm_modified，但其出生/成长seed相关方式不同：可用理想参考分布比较，不能说野生实际精确测度同一张表。
- gm_modified、非零legacy_stat_offset（`pet_comparison.gd:17-18`）、未知stats、非法growth weights、特殊definition、转生/特殊成长、任何所谓mutated/synthetic参数，应显示无匹配基准或独立规则表。当前没有实现完整转生/变异成长体系；不要为未实现机制捏造自然概率。
- 内置species alias只有definition与birth规则吻合才共享原表；特别是捕获L>1时4.5默认与原表4不同。`species_key`仅名字映射不能证明概率表适用。
- 服务器启动读一份构建工件，投影现有个体时继续调用既有Progression（自身预测是确定的，概率表衡量参考群体稀有度）；在snapshot/query发送五项查表结果与schema/model version给客户端。LAN/remote客户端读world.state/session响应，不依赖不存在的backend，更不能每台重新采样。遵循`docs/technical/backend-interface.md`的权威边界。
- 五项排名各自独立展示意义；不能取多个指标中最小tail叫整宠精确排名（多重比较），也不能乘边际tail。要组合评分必须另定义联合统计量并直接构建它的表。

## 工作量估算（agent-days，不含用户审批与慢机排队）

| 工作 | 实现/核对时间 | 构建 wall time | 风险 |
| --- | --- | --- | --- |
| PCG native parity、5项hist、元数据/CI、代表种子fixture | 1–2 agent-days | 全1–10M分钟到约1h | seed定义/出生口径、overflow、整数断点 |
| 459共享构建与server O1服务、snapshot/LAN适用口径 | 1–2 agent-days | 初版无需1e9 | provenance旧存档、protocol/schema、fallback |
| badge/tooltip/mobile与头less逻辑验证 | 1–2 agent-days | 无重模拟需求 | 文案误称原版、ties、多人权威；像素验证另需显式图形请求 |
| 1e9全物种或实际32位共享kernel exhaustive | 优化/验证额外2–4 agent-days | 暂估2–5天/14核；共享kernel可能缩短，须benchmark | 全域并非真实野生出生联合概率 |
| 理想四边际精确law的高精度/NTT工程 | 3–5 agent-days | 单品种先benchmark；全431可能hours–days | 浮点误差与exact命名 |
| 三围合全精确联合DP研究 | 至少5–10 agent-days探索，不保证成功 | 未知，不建议承诺 | billions+状态、内存、尾部认证 |

推荐先做3–6 agent-days的可靠共享采样表与诚实尾部展示；先确认参考群体口径，再决定实际seed枚举。原游戏概率规则不改；精确自身成长预测保留。产品实施仍需父session先向用户回报本调查。


## 最终追加：1 亿 seed 扫描与真实 Godot 极端值确认

蓝/红各枚举seed0..99,999,999，单程序CPU137.28/137.30s，约0.728M/core-s。蓝最高627共3例，红最高634共3例。这是所枚举连续区间的准确频数，不是全2^32域p=3e-8的证明，也不是iid抽样CI。

| 品种 | seed | attack | defence | speed | HP | sum | base(V,S,T,D) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| original_92 蓝人龙 | 69252848 | 293 | 181 | 153 | 1319 | **627** | 19616,25304,12853,15324 |
| original_94 红人龙 | 84176317 | 303 | 180 | 151 | 1249 | **634** | 17605,26498,12887,15130 |

上述两例均为species_actor全+2、Lv1出生，project_pet与真实逐级grow_pet完全一致；已复现任务所述627/634，且不是估计或理想xoshiro模拟。仍应明确为synthetic/GM同seed出生口径，未声称找到对应野生遇敌上游runseed/index。

额外验证：`verify-known.c` 一次仅跑6个knownseed，分别两种模板；`verify-known-blue.txt` / `verify-known-red.txt` / `godot-results.txt` 中12只actor的base与攻防敏血、sum逐个自动assert相同，记录`parity-results.txt`。verify.gd每只还assert project_pet==119次grow_pet；headless无窗口，无full suite。

一个值得进一步调查的相关性证据：seed84176317蓝也为627（293/182/152，HP1318），而红为634。两模板rank相同，其每级抽样共享完全相同的PCG pattern，极端值同时发生符合共享rank/seed kernel可复用的事实，不可拿此共享枚举样本跨物种当作独立样本。

工作树状态与调查开始一致：既存未跟踪`client/tests/capture_then_leave_test.gd.uid`和`client/tests/fast_hunt_reap_test.gd.uid`，本轮未处理。临时源码、脚本、结果仅报告目录，不提交。

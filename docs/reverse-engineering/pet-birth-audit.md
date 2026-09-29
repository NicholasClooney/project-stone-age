# 宠物出生与成长核对报告（特殊宠物分支）

2026-09-29。核对 `feat/special-pets` 分支是否改变原有宠物属性的计算，并把项目的出生、成长公式与参考服务器 C 源码（`references/chenmingbiao-stone-age/gmsv/`）逐条对照。

## 结论

- 分支没有改变任何原有宠物的属性计算。对 main 与分支用同一批种子生成的 38,320 只宠物，出生资质、Lv1 属性、成长档、练到 Lv120 的属性和野生 Lv90 公式逐字节相同。
- 项目的出生、成长档、升级顺序与公式与参考 C 源码一致。
- 有一处 main 上原本就存在的细微差异（不是本分支引入）：原版升级用 32 位浮点数，项目用整数，约 5% 的满档蓝人龙 Lv120 三围合比原版多 1 点，极少数多 2 点。见下文。

## 分支改动分类

| 文件 | 改动 | 是否影响原有属性计算 |
| --- | --- | --- |
| `client/server/progression.gd` `species_actor` | 资质写成整数；新增可选参数 `offsets` 指定四项档位 | 否，见下两节 |
| `client/server/game_session.gd` | 新增 `gm_grant_pet`，其余不变 | 否，只是新入口 |
| `client/server/backend.gd`、`client/network/session_client.gd` | 新增 `gm_grant_pet` 命令 | 否 |
| `client/server/encounter_catalog.gd`（野生遇敌） | 未改动 | 否 |
| `grow_pet`、`derived`、`project_pet` | 未改动 | 否 |
| `tools/import_encounter_art.py` | 多导入特殊宠物的战斗图；只写战斗图和 `art-coverage.json`，不写图鉴模板数值 | 否 |
| `tools/pack_frame_sheets.py` | 修复 Python 3.9 下无参数运行失败 | 否 |

### `species_actor` 的改动为什么不改变结果

原写法：

```gdscript
for i in range(4):weights[i] += rng.randi_range(-2,2)
```

分支写法：

```gdscript
for i in range(4):
	var roll := rng.randi_range(-2,2)
	weights[i] = int(weights[i])+(int(offsets[i]) if offsets.size()==4 else roll)
```

1. **随机数顺序不变。** 每项仍然各抽一次 `-2..2`。指定 `offsets` 时也照抽不用，所以后面 10 个出生点和成长种子的随机序列位置不变。
2. **整数与小数数值相同。** 原版模板从 JSON 图鉴读入，是 `37.0` 这样的小数，现在是 `37`。之后的运算里：
   - `int(initial*(...))`：两边值相同。
   - `int((w+e)*roll/100)`：小数时是精确的浮点除法（分子是 2^53 以内的整数，IEEE 除法正确舍入，而真实商与整数至少相差 0.01），整数时是整数除法，两者截断结果相同。
   - 野生遇敌（`encounter_catalog.gd`）一直是整数，这次只是让两条路径格式一致。
   - 存档本来就是 JSON，读档时会统一数字，所以对已有宠物也没有影响。

### 实测

临时脚本调用 `Progression.species_actor(name, 1, seed)`、`project_pet(pet, 120)` 和 `species_actor(name, 90, seed)`，覆盖 6 个内置物种和 958 个原版模板，每个 40 个种子，共 38,320 只，分别在 main（`ab4f06d`）和分支上运行。两份输出逐字节相同（`cmp` 无差异）。输出包含资质、Lv1 base 属性、成长档、Lv120 base 属性、攻防敏血，以及 Lv90 野生公式的 base 属性。

## 与参考 C 源码逐条对照

| 规则 | 参考 C 源码 | 项目 | 一致 |
| --- | --- | --- | --- |
| 模板整数字段读取 | `gmsv/char/enemy.c:295` `atoi(token)`，所以成长率「4.50」读成 4 | 图鉴 `wild_growth` 为 4，原文保留在 `raw_growth` | 是 |
| 资质偏移 | `enemy.c:1041-1044`，体、力、强、敏各 `RAND(0,4)-2` | `progression.gd:53` 起，同顺序各 `randi_range(-2,2)` | 是 |
| 成长资质保存 | `enemy.c:1046-1050` `CHAR_ALLOCPOINT` 在加出生点之前保存 | `growth_weights` 为偏移后、加出生点前的值 | 是 |
| 出生 10 点 | `enemy.c:1052-1058`，10 次 `RAND(0,3)` | `progression.gd:63`、`encounter_catalog.gd:111` | 是 |
| 出生属性 | `enemy.c:1036` `PARAM_CAL`：`((level-1)*成长率 + 初始值) * 点数` | `encounter_catalog.gd:120`，内置物种见 `progression.gd` | 是 |
| 成长档 | `enemy.c:767` `ENEMY_getRank`：按模板原始四项和（不含偏移）对照 100/95/90/85/80/0 | `total` 用 `data.weights` 原值 | 是 |
| 升级 10 点与倍率顺序 | `gmsv/char/char_data.c:1200` `CHAR_PetLevelUp`：先 10 次 `RAND(0,3)`，再 `RAND(min,max)` | `progression.gd:80-82` 同顺序 | 是 |
| 倍率区间 | `RankRandTbl` {450,500},{470,520},…,{550,600} | `low = 450 + rank*20`，`low..low+50` | 是 |
| 每级增加 | `(int)(资质*fRand + 点数*fRand)`，32 位浮点 | `int((资质+点数)*roll/100)`，整数 | 见下节 |

## 已知差异：32 位浮点（main 原有，非本分支）

原版中 `fRand = (float)(RAND * 0.01)`，再分别计算 `资质*fRand` 与 `点数*fRand`，都是 32 位浮点，最后相加截断。项目用精确整数，而 4.52 这类倍率在 32 位浮点里略小于真实值，所以原版有时少 1。

- 枚举全部成长档、倍率、资质 0 到 63、点数 0 到 10，共 215,424 种组合：520 种（0.241%）结果不同，全部是原版比项目少 1。例如成长档 0、倍率 452、资质 24、点数 1：原版 112，项目 113。
- 对满档蓝人龙用同一组随机数模拟 2 万只 Lv1 练到 120，按原版算法与项目算法各算一次三围合：
  - 95.4% 相同。
  - 4.5% 原版少 1。
  - 0.08% 原版少 2。
- 影响：项目的 Lv120 三围合平均偏高约 0.05，`pet-quality.md` 的分布与 624 门槛基本不受影响。这是 `grow_pet` 的既有建模选择。要完全贴合原版，可在 `grow_pet` 中按 32 位浮点复现，但会改变所有已有宠物的未来成长预测。
- **决定（2026-09-29）：不复现。** `grow_pet` 继续用精确整数运算。差异很小（约 5% 满档蓝人龙 Lv120 多 1 点），而复现会让每只已有宠物的 Lv120 预测、同种比较和找宠门槛一起变动。以后若要逐点贴合原版，需要同时迁移已有宠物的预测并重新测 `pet-quality.md` 的分布。

验证脚本未入库：浮点枚举与模拟是一个一次性 Python 脚本；main 与分支对比是一个临时 Godot 脚本，运行后已删除。

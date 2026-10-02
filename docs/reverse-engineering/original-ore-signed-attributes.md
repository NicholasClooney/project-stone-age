# 矿石敌1043的原始负属性

## 源证据

当前原表enemy.txt:682：1043→模板545，Lv1，pet_flag0，不可捕捉，原策略只等待，掉2534概率1000/1000。enemybase.txt:366：模板545权重100/0/5/0，初值250，wild_growth1。原零权重经±2可为负，不应挑一个刚好非负的seed掩盖生成范围。

`gmsv/char/enemy.c:1041–1044` 四次±2扰动无下限；`:1046–1050` 直接打包CHAR_ALLOCPOINT；`:1052–1057` 再分配十点；`:1061–1064` 以 `(initial+(level-1)*growth)*weight` 设置原属性。`char_data.c:124–171` 默认角色清零后仅复制data/flg，未装后置init钩子；`char_base.c:1627–1635` 复制角色后仅调用存在的回调，`:971–984` setInt无下限。`char.c:2855–2908` 用原有符号基础值计算派生。未发现可据以声称“原C会把负权重归零”的分支。

固定group508、地图31801(24,24)、seed27产生1043权重98/1/3/-1、敏捷基础值-250。本项目既有派生速度最低1，和“原始值非负”是两件事。保留原生成分布，现有AI/派生下限保持，不恢复原特殊技能或负ALLOCPOINT捕捉后的历史行为。

## 最小适配

新增 `OriginalOreActor.validation_shape` 仅由真实Session野战入口调用。独立读取服务器导入catalog，确认1043/545、源pet_flag0及wait_only；验证原等级范围、四权重逐项在原权重±2、基础值为原乘数整数倍、相对扰动权重每项追加0–10且总共十点、派生字段与当前规则一致。不会只相信传入enemy_id，也不接收客户端目录或种子。

校验辅助副本仅让原通用校验继续验证其余字段；该副本不会用作战斗角色，实际实例保持负原始值。玩家、普通宠物、存档 `_actor_valid` 未改。物品、金币、保存失败重试及个人party_settlement机制未改，不增加捕捉矿石入口。超出源负界、伪装身份、可捕捉标记、11点追加、伪造派生字段均拒绝。

同时修复 `FastHunt._input` 对掉落抽样次数的描述：使用与EncounterCatalog.actor相同的 `drop_enemy_allowed`（包含已审核任务掉落），不再仅用旧静态木头/眼睛ID数组。旧遗漏会在1043掉落抽样后使下一敌人的等级/权重/growth_seed全部错位。C与GDScript的实际actor抽取顺序和算法没有改变，只补齐给native的可信抽样计数。

## 验证

原seed27整队真实Session→战斗胜利→保存失败回滚→重试只发一份2534→重复close无重复；最小负界进入真实Session；玩家/宠物保存负值仍拒绝，胜后真实存档正常读回。矿石区域1000次抽组比较全部敌人的等级、权重、基础值、growth_seed、Lv120投影及捕捉选择，与native一致。另定向回归fast_hunt_test、wild_encounter_authority_test及personal_quest_npcs_test；未跑full。

## 审计文件SHA-256

- `gmsv/char/enemy.c`：`fecfedd35d6323c1112fd164a4f4636618c943debb0917781abc2f58b806ed1a`
- `gmsv/char/char_data.c`：`ec7d3f51982ba9bba9dc3c922c89263c6d3a9733b3188355d3a1280bf9afe990`
- `gmsv/char/char_base.c`：`0fb9501a891989799a4e6d6b407f14bdf2dfbe903df8169ff64d57a67826b287`
- `gmsv/char/char.c`：`0f5074d47f0b12ee92b9d5f537b7bf099fc16dd969d33e5e38632b2dddbc3f9d`
- `gmsv/data/enemy.txt`：`69fc9f603cc9ee24bbc30511e6a0407254b62ba68651b71cb68f50a58f9f6629`
- `gmsv/data/enemybase.txt`：`3868f26a02d60aa810a21f0abba76fe1334619862c7ba9fe21ad4417de39dc17`

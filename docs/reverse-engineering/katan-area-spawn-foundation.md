# 卡坦原区域出生底座

只支持实际 `seimu/event/event02_n.create:8–18` → `changeevent|file:seimu/event/event02_1`；不把区域出生普遍放开。任务模块继续声明 `scripts["seimu/event/event02_1"].spawn_policy = {"mode":"source-area"}`。不填写固定坐标。模块 `world.map_sources["100"]` 锁原 `gmsv/data/map/sainasu/sainasu` SHA。

`sources` 须同时锁定：原create/script、`gmsv/data/npc/jaruga/event/event.template`、`gmsv/npc/npcgen.c`、`npccreate.c`、`npctemplate.c`、`gmsv/map/map_deal.c`、`readmap.c`、`gmsv/setup.cf`、`gmsv/data/map/mapset.txt`。setup.cf 注释混合旧编码，导入只按字节保留并读取ASCII配置键，不替换源或忽略SHA。

## 原规则与项目差异

- `event02_n.create:10–14`：地图100，含两端矩形230,180–525,200，time0、createnum1、ignoreinvincible1。
- `event.template:4–8`：ExChangeMan、makeatnobody1、makeatnosee1；`npctemplate.c:611` 默认fly0。故不要求玩家在区域内，也不排除玩家视野。
- `npcgen.c:25,54–95` 每次只抽一个 RAND(0,6215) 偏移，x取余296，y整除296；不能固化角点，也不能遇阻后立刻无限抽样。
- `map_deal.c:24–57`：物件层walkable2可通行；物件层1时还要求地表层1；其他拒绝。不是其他NPC/玩家占格检测。`readmap.c:162–170` 从mapset第四列读取整数（不会把2压成bool）；`:317–323` 缺图编号为0。`setup.cf:328` 实际指向mapset.txt。
- `main.c:76` 启动生成；`npcgen.c:344–375` 后续循环至少一秒、一次失败留待重试；`npccreate.c:535–554` time0仍受生成数量限制。原全局队列每轮最多一个符合生成条件的create，本切片仅复现已审核的卡坦单create，不恢复完整全服NPC调度器。
- 原区域6216候选，其中6125可通行。此源快照的6125格与当前导出100.map阻挡全部一致；保留原候选分布，不另挑方便点。

项目沿已批准个人NPC状态政策B：原版全服共享，本项目按角色各自计算。初始化由可信服务器RNG进行，失败满一秒再抽；成功位置稳定，同角色多设备一致。源动态位置放既有个人内存投影，重启清空重抽，不增加存档字段。出生自身不是玩家交易；后续交易仍遵守成功保存后才提交的原事务规则。

稳定ID为 `seimu/event/event02_1@100:230:180:area:525:200`，角点仅作区域身份组成部分，**不是可交互出生坐标**。导入NPC附 `source_spawn`（矩形、原通行mask及来源）；未生成时客户端/服务器active_npcs均不暴露占位NPC；成功后沿既有 `derived.quest_npcs[id]={map_id,cell}` 投影、地图碰撞与helper版本更新。客户端不能指定随机点、种子或重试时钟。

测试用可信clock/RNG注入验证阻挡候选、同秒及0.999秒拒绝重试、1秒重试、实际地形所有合法格、位置持久于进程且不进save、重启、原对话可达与占位坐标拒绝。三socket验证同角色一致/另一角色隔离、服务器tick发布，不宣称headless测试验证像素。完整卡坦交宠路线由任务模块验收。

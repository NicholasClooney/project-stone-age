# 矿工验票与缺表条件公共接口

本切片提供接口，不自行注册矿工任务；实际路线、地图恢复和助手由矿工模块负责。

`handlers["genout/wpm_31805_22_4"] = {"kind":"warpman","events":[27]}`，同时将 `genout/giruev2.create` 加入 `creates` 并锁定原脚本/create SHA。仅受审的 `FREE:ITEM=2527`、`DelItem:2527*1`、`MONEY:-1`、`WARP:31806,34,6` 字段组合被接纳。生成 FREEWARP 分支带 `item_deletion_scope:"bag"`，确认时重新检查物品与组队状态；候选 profile 消费第一张背包许可证，成功保存后才传送，失败完整回滚。

原证据：`npc_eventaction.c:1243–1280,1423–1424,1524–1538` 的免费物品检查从 CHAR_STARTITEMARRAY 开始；`:856–906` 的量词删除同样从背包消费一份。`npc_warpman.c:228–231,393–400,560–566` 开窗及确认均拒绝队伍；`:580–584` 缺 PartyMsg 时采用原默认文本（展示去除排版空白）。MONEY=-1 不产生负扣款或付费旁路。其他交换脚本已确定的 DelItem 修正保持不变。

2391 在此快照 itemset 的 ID 列缺失；只给 `giiru/event/giruev2_1` 原分支0 `ENDEV=27&ITEM!=2391` 以下显式注记：

```json
"missing_condition_items": [{
  "id": 2391,
  "script": "giiru/event/giruev2_1",
  "branch": 0,
  "reason": "Pinned itemset has no 2391; retain original negative condition."
}]
```

`items` 不列2391。不创建其定义，不修改谓词，不允许该例外被用于其他分支、授予/删除/随机奖励、守卫所需物品、掉落或物品展示注记。loader 确认锁定源表确实缺项、原分支被选择、条件完全相符，并记录源脚本与分支行号。其他来源异常必须单独审核。

验证：源生成夹具逐值比较与负例；真实 Backend 取消、失票后重查、精确一张 UID 消费、保存失败回滚、真实存档读回、两 WebSocket 设备重放拒绝、真实 ProfileHub 开窗后组队拒绝。旧免费等级门、ITEM 穿戴语义及交易回归定向运行；未运行全套。地图夹具来自真实31805/31806 LS2MAP 文件，不修改存档验证规则。

# 生产接口首跑：失败证据及最小fixture修正（未复跑）

唯一获准suite quest_auto_public_corridors_interfaces_test，仅一次，wall17.428s、内部16328ms、431断言5失败、exit1。完成即通知释放窗口，无遗留Godot。
原日志：public-expansion-interfaces-first.log。没有串联其它套/import/full/长路。

## 首次逐项结果

5失败：
- public-v2-mati-yam：production audit为空。
- public-v2-mati-marju：production audit为空。
- public-v2-mati-samgir：production corridor为空。
- public-v2-kou-marinas：production audit为空。
- public-v2-karutana-jaja：production audit为空。

另外24条跑到末尾，日志有12条public_stride与12条walk；但这轮受测试状态污染，**这些计数不能作为清洁29项最终命中率或任务收益**。

## 从实际代码定位到的因果链

测试使用伪service_npcs.append + 直接写catalog.npc_overrides模拟占格，清理时pop/erase。
生产original_quests.gd的refresh_npc_state每次都执行 `catalog.npc_overrides=npc_state.snapshot()`；npc_by_id调用它。
导航blocked的cache key来自npc_state.version、npc_overrides、enabled_events，不包括测试直接改动的service_npcs内容。
因此临时blocker存在时，查询可把占格缓存到“overrides已经恢复为空”的key下；测试pop/erase没有正式NPC版本变化，此后仍读到残留blocker。
首项yam-mati的blocker位置100(621,190)恰为后续mati-yam/mati-marju/mati-samgir的start；marinas-kou的门前100(470,630)恰为kou-marinas的start；goya-karutana/jaja-karutana的200(304,599)恰为karutana-jaja的start。五失败位置全部符合这条污染链。

这是当前静态因果定位，尚未复跑完成排除；不据此放宽断言或改生产A/缓存策略。也不把不走正式version的fixture当作真实NPC移动产品路径。

## 已做最小修正（仅测试文本）

改用真实已启用原NPC sainasu/event/event02_1，并通过既有 `original_quests.npc_state.moved()` + `refresh_npc_state()` 移到门前，验证production validate_audit拒绝，再同API移回原图/格。
正式moved同时维护records并推进version；新断言要求移回后production blocked已无门前占格，防止跨候选残留。
没有改生产模块/核心/navigation/旧7，保留原完整5失败日志，没有剔除29项来让测试绿。

## 边界结果的口径

已运行到的保护、门前格、伪source、disabled、原起点来源失效、未知村内fallback断言没有独立报错，但整个套为失败，**不交绿结论**。五portal起点先walk的接口断言也未报错，仍须在干净修正版重验。
实际A选择别门而walk仍是合法结果；清理fixture污染后才判断其精确命中数量。A/C执行/遇敌/proof/九job收益尚未验。

## 下一窗口请求

仅重跑同一修正版interfaces短套一次，依据首跑17.428s，暂估20–30s、外层60s；不添加其它suite。等母代理明确分配再跑。

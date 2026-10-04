extends RefCounted
## Draft pure proposal only. No registration or execution hook.
## Frozen callback: QuestAutoLootSources.matches_backend(b, expected_source) -> bool.
## Core owns res://server/quest_auto_loot_sources.gd; callers supply its callable.
## Missing dependency fails closed; only core verifies the complete current source.
## Execution independently rechecks source/admission; this result is no capability.
const Motion = preload("res://server/quest_auto_motion.gd")
const SIGNATURE := "sha256:97c680e16befd2de159349c7b75ac7a9f0dc387f94c9b35c13141cd846d0dc0e"

static func source() -> Dictionary:
 return {"policy":"jewels_2760_area56_v1","map_id":100,"area_id":56,
  "group_id":711,"enemy_id":1305,"drop_slot":0,"requires_item":2764,
  "excludes_item":2760,"signature":SIGNATURE}

static func manual(reason:String) -> Dictionary:
 return {"status":"manual","reason":reason}

static func select(b, source_matches:Callable = Callable()) -> Dictionary:
 var items:Variant = b.session._profile.get("original_items",[])
 if not items is Array:return manual("原道具数据无效。")
 for item in items:
  if Motion.integer(item)==null:return manual("原道具编号无效。")
 for item in items:
  if Motion.same_integer(item,2760):return {"status":"done"}
 var has_requirement := false
 for item in items:
  if Motion.same_integer(item,2764):has_requirement=true
 if not has_requirement:return manual("缺少原地宝珠前置道具2764，请手动取得。")
 if not Motion.same_integer(b.automation.position_map,100):
  return manual("请先沿合法原路到原地宝珠区域；计划不移动角色。")
 var area:Dictionary = b.encounter_catalog.area_at(100,b.automation.position_cell)
 if not Motion.same_integer(area.get("id"),56):
  return manual("当前实际遇敌区域不是受审区域56。")
 if not source_matches.is_valid():return manual("原掉落源校验尚未接入。")
 var expected := source()
 var matches:Variant = source_matches.call(b,expected.duplicate(true))
 if not matches is bool or not matches:return manual("当前原掉落源未匹配冻结签名，请重新审计。")
 return {"status":"step","step":{"id":"jewels:hunt:2760","action":"loot",
  "target":{"item_id":2760,"count":1},"source":expected}}

extends RefCounted
## Pure inspection only. No step, receipt, payment, battle or route execution.
const Compare=preload("res://server/quest_auto_spirit_fire_plan.gd")
const SOURCE_PATH="res://server/quest_auto_spirit_fire_route_sources.json"
const SOURCE_SHA="46d203d0e0ad38d6aaef89fb5d96c4d9fac2aafa063309e515225e66b0dea976"
static func source_table()->Dictionary:
 var raw:String=FileAccess.get_file_as_string(SOURCE_PATH)
 if raw.sha256_text()!=SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func hold(stage:String,reason:String)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason}
static func fee_contract(fee_id:String,gold:Variant)->Dictionary:
 var table:Dictionary=source_table()
 if table.is_empty():return hold("source_changed","火费用完整源锁改变。")
 if not table.fees.has(fee_id):return hold("manual_unapproved_fee","额外票、1150壶、支线和必要性未定费用保持人工。")
 if (not gold is int and not gold is float) or not is_finite(float(gold)) or float(gold)!=floor(float(gold)) or float(gold)<0:
  return hold("invalid_gold","余额必须是有效非负整数；不能作为付款凭据。")
 var contract:Dictionary=table.fees[fee_id].duplicate(true)
 if float(gold)<float(contract.amount):
  var result:Dictionary=hold("insufficient_gold","金币不足，停止交玩家。")
  result.amount=contract.amount
  result.shortfall=int(contract.amount)-int(gold)
  return result
 var result:Dictionary=hold("manual_core_contract","必需费用已授权；原售证兼容和核心原子执行合同尚未接线。")
 result.fee_contract=contract
 result.advisory_only=true
 return result

extends RefCounted
## Core-owned registry. Modules propose read-only plans; the runner owns actions.
const Delivery=preload("res://server/quest_delivery_plan.gd")
const SourcePlan=preload("res://server/quest_auto_golden_bui_plan.gd")
static func supports(job_id:int)->bool:
 return Delivery.supports(job_id) or SourcePlan.supports(job_id)
static func select(b,job_id:int)->Dictionary:
 if SourcePlan.supports(job_id):return SourcePlan.select(b,job_id)
 if Delivery.supports(job_id):return Delivery.select(b,job_id)
 return {"status":"manual","reason":"此任务尚未注册审核计划。"}

const Doctor=preload("res://server/quest_auto_doctor_plan.gd")
static func doctor_request(b,job_id:int)->Dictionary:
 if job_id!=6 or not b._doctor_request_enabled():return {"status":"manual","reason":"博士首请求尚未开放。"}
 return Doctor.request_proposal(b,job_id)

const Saton=preload("res://server/quest_auto_saton_plan.gd")
static func saton_request(b,job_id:int)->Dictionary:
 if job_id!=10 or not b._saton_request_enabled():return {"status":"manual","reason":"萨顿首请求尚未开放。"}
 var p:Dictionary=b.session._profile
 if not RulesForSaton.flag(p,"now",13) and (2431 in p.original_items or p.get("original_instances",[]).any(func(item):return item is Dictionary and item.get("item_id")==2431)):
  return {"status":"manual","stage":"unexpected_footprint","reason":"足迹与委托状态不一致，请手动核实。"}
 return Saton.request_proposal(b)
const RulesForSaton=preload("res://server/original_quests.gd")

const Munde=preload("res://server/quest_auto_munde_plan.gd")
static func munde_request(b,job_id:int)->Dictionary:
 if job_id!=8 or not b._munde_request_enabled():return {"status":"manual","reason":"梦德首请求尚未开放。"}
 if preload("res://server/original_quests.gd").flag(b.session._profile,"now",9) or preload("res://server/original_quests.gd").flag(b.session._profile,"ended",9):
  return {"status":"manual","stage":"request9_complete","reason":"梦德首委托已处理；后续任务请手动进行。"}
 return Munde.request_proposal(b,job_id)

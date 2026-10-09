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

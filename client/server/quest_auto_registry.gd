extends RefCounted
## Core-owned registry. Modules propose read-only plans; the runner owns actions.
const Delivery=preload("res://server/quest_delivery_plan.gd")
static func supports(job_id:int)->bool:
 return Delivery.supports(job_id)
static func select(b,job_id:int)->Dictionary:
 if Delivery.supports(job_id):return Delivery.select(b,job_id)
 return {"status":"manual","reason":"此任务尚未注册审核计划。"}

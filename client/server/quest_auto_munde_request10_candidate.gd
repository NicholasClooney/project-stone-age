extends RefCounted
## UNRUN runner-side candidate for the native REQUEST9 -> REQUEST11 -> REQUEST10 prefix.
## This module only selects the existing exact source-locked plan steps.
## It never changes profile, position, arrival, dialogue, or save state and is
## intentionally absent from Policy/Registry until the core opens job 8.
const Plan=preload("res://server/quest_auto_munde_plan.gd")
const REQUEST10_ID="sainasu/event/event10@1300:65:65"

static func supports(job_id:int)->bool:
 return job_id==8

static func select(b,job_id:int=8)->Dictionary:
 if job_id!=8:return Plan.hold("unsupported_job","仅梦德job8。")
 var stage:Dictionary=Plan.select(b,job_id)
 if stage.get("status")=="done":return stage
 match str(stage.get("stage","")):
  "request9":return Plan.request_proposal(b,job_id)
  "request11":return Plan.request11_proposal(b,job_id)
  "request10":return Plan.request10_proposal(b,job_id)
  _:return stage

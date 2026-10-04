extends RefCounted
## UNRUN. Parent explicitly orchestrates 28 -> 29 -> 28; never starts another job.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if not job_id in [27,28,29]:return hold("unsupported_job","强恩保27/28/29原映射。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 var end_event:={27:20,28:21,29:22}
 if Rules.flag(p,"ended",end_event[job_id]):return {"status":"done"}
 if job_id==27:
  if not Rules.flag(p,"now",20):
   if not 2486 in held:return hold("flower","原吉德领花分支待核，不反复探测ACCEPT。","jaruga/event/event20_1",23)
   return hold("request20","原妻子REQUEST消花。","jaruga/event/event20_2",17)
  if not 2487 in held:return hold("claim_token","原领2487 ACCEPT。","jaruga/event/event20_3",6)
  return hold("keyword_boss_return","三个精确口令门需d878及新hook，山贼人工；原胜后区域通过才交强恩END20，持2487不授proof。","jaruga/event/event20_4",5)
 if not Rules.flag(p,"ended",20):return hold("prerequisite","须END20，不自动启动job27。")
 if job_id==29:
  if not Rules.flag(p,"now",21):return hold("parent_request28","父链须先明确启动28并完成沙拉原REQUEST。")
  return hold("random_equipment","原随机2490..2494一件，非人选五选，GetRandItem事务待核。","jaruga/event/event20_4",16)
 if not Rules.flag(p,"now",21):
  if not 2487 in held:return hold("missing_token","缺沙拉REQUEST所需2487；不注物或重开27。")
  return hold("request21","妻子说明无持久flag；沙拉原REQUEST消2487。","jaruga/event/event20_6",26)
 if not Rules.flag(p,"ended",22):
  var result:=hold("parent_job29","父链显式切29取得装备后再回28；纯计划不会start。")
  result["required_parent_job"]=29
  return result
 if not 2488 in held:return hold("claim_letter","沙拉原ACCEPT领家书。","jaruga/event/event20_6",5)
 return hold("deliver_letter","原event20_2交信END21；event20_1前页/转交效果须核完整分支，不发明额外消费。","jaruga/event/event20_2",5)

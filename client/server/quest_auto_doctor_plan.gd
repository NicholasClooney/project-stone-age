extends RefCounted
## UNRUN: never selects, consumes or captures a pet UID.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":"sainasu/event/event15_1","line":line}}
static func select(b,job_id:int)->Dictionary:
 if not job_id in [6,7]:return hold("unsupported_job","仅博士job6/7。")
 var p:Dictionary=b.session._profile
 var event:=15 if job_id==6 else 16
 if Rules.flag(p,"ended",event):return {"status":"done"}
 if job_id==7 and not Rules.flag(p,"ended",15):return hold("prerequisite","第二委托须END15；不自动启动job6。")
 if not Rules.flag(p,"now",event):
  if int(p.player.level)<=(9 if job_id==6 else 15):return hold("level","未满足原REQUEST等级。")
  return hold("request","待原REQUEST及六层合法路径绑定。",26 if job_id==6 else 37)
 return hold("manual_uid","请玩家确认原合格宠UID及消耗；即使仅一只也不代选。第一委托是原随机单奖，第二GetPet95未获自动权限。",4 if job_id==6 else 15)

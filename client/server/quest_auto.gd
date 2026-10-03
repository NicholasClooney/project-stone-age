extends RefCounted
## Source-derived delivery runner: shell/herb visits and adult channel walking. Every exchange stays in OriginalQuests/save().
const Policy=preload("res://scripts/quest_auto_policy.gd")
const Rules=preload("res://server/original_quests.gd")
var running:=false
var quest_id:=-1
var client:=""
var connection:=-1
var phase:=""
var message:=""
var target:Dictionary={}
var step:Dictionary={}
var clean_authorized:=false
var elapsed:=0.0
var waited:=0.0
var internal:=false
## Only a restart-restored intent may continue without the initiating socket.
var restored:=false
var shutdown_intent:Dictionary={}
var path:Array[Vector2i]=[]
var issued:Array=[]
var position_serial:=0
var owns_battle:=false
func event(b) -> int:
 return int(row(b,quest_id).get("event",-1))
func title(b) -> String:
 return str(row(b,quest_id).get("title","原任务"))
func emit_position(b,point:Dictionary) -> void:
 position_serial+=1
 issued.append({"seq":position_serial,"map_id":int(point.map_id),"cell":point.cell.duplicate()})
 while issued.size()>16:issued.pop_front()
 b._emit({"type":"position","map_id":point.map_id,"cell":point.cell,"quest_position_seq":position_serial,"client":"quest_auto"})
func accept_report(b,command:Dictionary) -> bool:
 if running and str(command.get("client",""))==client and int(command.get("_quest_connection",-1))==connection:
  for receipt in issued:
   if int(command.get("quest_position_seq",-1))==int(receipt.seq) and int(command.get("map_id",-1))==int(receipt.map_id) and command.get("cell",[])==receipt.cell:
    if phase=="landing" and int(receipt.seq)==position_serial:report(b,command)
    return true
 report(b,command)
 return false
func walk_path(b,goal:Vector2i) -> Array[Vector2i]:
 var map_id:int=b.automation.position_map
 var data:Dictionary=b.quest_helper.maps.get(map_id,{})
 if data.is_empty():return []
 var nav=AStarGrid2D.new()
 nav.region=Rect2i(0,0,int(data.width),int(data.height))
 nav.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
 nav.update()
 var occupied:Dictionary={}
 for npc in b.quest_catalog.active_npcs():
  if int(npc.map_id)==map_id:occupied[Vector2i(npc.cell[0],npc.cell[1])]=true
 for npc in b.quest_helper.places.residents:
  if int(npc.map_id)==map_id:occupied[Vector2i(npc.cell[0],npc.cell[1])]=true
 var links:Dictionary=b.quest_helper.places.links(map_id)
 for y in range(int(data.height)):
  for x in range(int(data.width)):
   var cell:=Vector2i(x,y)
   nav.set_point_solid(cell,not b.quest_helper.safe(data,cell,occupied,links))
 var result:Array[Vector2i]=[]
 var origin:Vector2i=b.automation.position_cell
 if nav.is_point_solid(origin) or nav.is_point_solid(goal):return result
 for cell in nav.get_id_path(origin,goal):result.append(cell)
 if not result.is_empty():result.pop_front()
 return result
func start_battle(b) -> void:
 owns_battle=true
 phase="battle"
 b.automation.start({"kind":"battle","settings":{"preset":"attack","compact":true}})
 b.automation.compact_active=true
 message="沿途遇敌：原自动战斗中，结算后继续。"
 b.publish()

func snapshot() -> Dictionary:
 return {"running":running,"quest_id":quest_id,"phase":phase,"message":message,"target":target.duplicate(true),"client":client}
func stop(b, reason:String="已停止自动任务。", persist:bool=true) -> void:
 var had_shutdown_intent:=not shutdown_intent.is_empty()
 if persist:shutdown_intent={}
 if not running:
  if persist and had_shutdown_intent:b.keep_resume_file()
  return
 if not persist:shutdown_intent=resume_state()
 if owns_battle and b.automation.running:b.automation.stop(reason)
 owns_battle=false
 path.clear()
 issued.clear()
 running=false
 phase="stopped"
 message=reason
 b.original_quests.pending={}
 if persist:b.keep_resume_file()
 b.publish()
func resume_state() -> Dictionary:
 if not running:return shutdown_intent.duplicate(true)
 return {"version":1,"quest_id":quest_id,"clean_authorized":clean_authorized}
func suspend(b) -> void:
 # Transport shutdown must checkpoint before clearing the running intent.
 if running:
  shutdown_intent=resume_state()
  b.keep_resume_file()
 stop(b,"服务器已停止。",false)
func load_resume(b,state:Dictionary) -> void:
 if int(state.get("version",0))!=1 or not Policy.JOB_EVENTS.has(int(state.get("quest_id",-1))):return
 if int(Policy.JOB_EVENTS[int(state.quest_id)]) not in b.quest_catalog.enabled_events:return
 quest_id=int(state.quest_id)
 clean_authorized=bool(state.get("clean_authorized",false))
 b.original_quests.pending={}
 step=select(b)
 if step.is_empty():return
 client=""
 connection=-1
 restored=true
 running=true
 phase="travel"
 elapsed=0.0
 waited=0.0
 message="服务器重启后已恢复"+title(b)+"自动任务。"
 if b.battle_open and quest_id==1:start_battle(b)
 b.publish()
func row(b,id:int) -> Dictionary:
 for quest in b.quest_helper.snapshot(b).quests:
  if int(quest.id)==id:return quest
 return {}
func select(b) -> Dictionary:
 var quest:=row(b,quest_id)
 if Rules.flag(b.session._profile,"ended",event(b)):
  if clean_authorized and quest.get("can_restart",false):
   for candidate in quest.steps:
    if str(candidate.source.type)=="CLEAN":return candidate
  return {}
 for candidate in quest.get("steps",[]):
  if candidate.current and candidate.actionable and str(candidate.source.type) in ["REQUEST","ACCEPT"]:return candidate
 return {}
func start(b,command:Dictionary) -> Dictionary:
 if running:return b._reject("自动任务已在运行。")
 var id=command.get("quest_id",-1)
 if not (id is int or id is float) or float(id)!=floor(float(id)):return b._reject("无效任务编号。")
 var quest:=row(b,int(id))
 if quest.is_empty() or not Policy.supports(id,int(quest.event)) or not int(quest.event) in b.quest_catalog.enabled_events:return b._reject("仅开放贝壳、药草与成人仪式自动任务。")
 if b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active() or not b.original_quests.pending.is_empty():return b._reject("当前正忙。")
 if b.quest_visit_guard.is_valid():
  var reason:=str(b.quest_visit_guard.call())
  if not reason.is_empty():return b._reject(reason)
 if str(command.get("client","")).is_empty():return b._reject("缺少发起设备。")
 quest_id=int(id)
 clean_authorized=bool(quest.get("can_restart",false))
 step=select(b)
 if step.is_empty():return b._reject(str(quest.get("blocked_reason",""))+" 当前没有可自动执行的原任务步骤。")
 shutdown_intent={}
 restored=false
 client=str(command.client)
 connection=int(command.get("_quest_connection",-1))
 running=true
 phase="travel"
 message=title(b)+"自动任务：准备前往原 NPC。"
 path.clear()
 issued.clear()
 owns_battle=false
 elapsed=0.0
 waited=0.0
 b.publish()
 return {"ok":true}
func report(b,command:Dictionary) -> void:
 if not running:return
 var same:bool=int(command.get("map_id",-1))==b.automation.position_map and b._cell(command)==b.automation.position_cell
 if not same:stop(b,"移动停止了自动任务。");return
 if phase=="landing" and str(command.get("client",""))==client and int(command.get("_quest_connection",-1))==connection:
  phase="travel" if event(b)==4 else "talk"
  waited=0.0
  message="已确认抵达，准备原任务对话。"
  b.publish()
func tick(b,delta:float) -> void:
 if not running:return
 if b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():stop(b,"组队变化停止了自动任务。");return
 if phase=="battle":
  if b.automation.running:return
  if b.battle_open or not b.session._pending.is_empty():stop(b,"沿途自动战斗已停止，请手动处理。");return
  owns_battle=false
  if str(b.battle_state.get("outcome","")) not in ["win","captured"]:stop(b,"沿途战斗未获胜。");return
  if not b.save():stop(b,"沿途战斗保存失败，停止自动任务。");return
  path.clear()
  phase="travel"
 if b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active():stop(b,"其他活动停止了自动任务。");return
 if Rules.flag(b.session._profile,"ended",event(b)) and not clean_authorized:
  stop(b,title(b)+"已完成。")
  return
 if phase=="landing":
  waited+=delta
  if waited>=30.0:stop(b,"等待地图位置确认超时。")
  return
 elapsed+=delta
 if elapsed<0.2:return
 elapsed=0.0
 internal=true
 advance(b)
 internal=false
func advance(b) -> void:
 if phase=="travel":
  step=select(b)
  if step.is_empty():stop(b,title(b)+"已完成。" if Rules.flag(b.session._profile,"ended",event(b)) else "原任务条件已变化。");return
  var npc:Dictionary=b.original_quests.npc_by_id(str(step.npc_id))
  if npc.is_empty() or b.original_quests.branch_for(npc,b.session._profile)!=step.source.branch_data:stop(b,"原任务分支已变化。");return
  target=b.quest_helper.destination(b,npc,"near")
  if target.is_empty():stop(b,"找不到安全 NPC 落点。");return
  if event(b)==4 and b.automation.position_map==int(target.map_id):
   var goal:=Vector2i(target.cell[0],target.cell[1])
   if b.automation.position_cell==goal:phase="talk"
   else:
    path=walk_path(b,goal)
    if path.is_empty():stop(b,"原通道没有可步行路线。");return
    phase="walking"
   b.publish()
   return
  if event(b)==4:
   var arrival:Dictionary=b.quest_helper.destination(b,npc,"arrival")
   if arrival.is_empty():stop(b,"找不到原地图入口落点。");return
   target=arrival
  phase="travel" if restored and event(b)==4 else ("talk" if restored else "landing")
  waited=0.0
  message="准备原任务对话。" if restored else "等待发起设备加载任务地图。"
  b.automation.position_changed(int(target.map_id),Vector2i(int(target.cell[0]),int(target.cell[1])),int(target.map_id)!=b.automation.position_map)
  emit_position(b,target)
  b.publish()
  return
 if phase=="walking":
  if path.is_empty():phase="travel";return
  var cell:Vector2i=path.pop_front()
  if absi(cell.x-b.automation.position_cell.x)+absi(cell.y-b.automation.position_cell.y)!=1:stop(b,"原通道路线已变化。");return
  b.automation.position_changed(10204,cell,false,"walk")
  emit_position(b,{"map_id":10204,"cell":[cell.x,cell.y]})
  var reply:Dictionary=b._cmd_field_step({"map_id":10204,"cell":[cell.x,cell.y],"encounter":true})
  if reply.get("battle",false):start_battle(b)
  else:
   message="沿原仪式通道步行前往"+str(step.label)
   b.publish()
  return
 if phase=="talk":
  var reply:Dictionary=b.original_quests.talk(b,str(step.npc_id))
  if not reply.get("ok",false):stop(b,str(reply.get("reason","原对话失败。")));return
  var pending:Dictionary=b.original_quests.pending
  if str(pending.get("phase",""))!=str(step.source.type) or pending.get("branch",{})!=step.source.branch_data:stop(b,"原任务分支已变化，停止自动确认。");return
  phase="yes"
  message="准备确认原任务步骤。"
  b.publish()
  return
 var pending:Dictionary=b.original_quests.pending
 var original_phase:=str(pending.get("phase",""))
 if (phase=="yes" and original_phase not in ["REQUEST","ACCEPT","CLEAN"]) or (phase=="ok" and original_phase not in ["end","reward"]):stop(b,"原对话已变化。");return
 var reply:Dictionary=b.original_quests.choose(b,str(pending.get("token","")),"yes" if phase=="yes" else "ok")
 if not reply.get("ok",false):stop(b,str(reply.get("reason","原交易失败。")));return
 if reply.has("dialogue"):
  phase="ok"
  message="准备确认原任务结果。"
 else:
  if str(step.source.type)=="CLEAN":clean_authorized=false
  phase="travel"
  message="原任务步骤已完成。"
 b.publish()

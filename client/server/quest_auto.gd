extends RefCounted
## Source-derived delivery runner: shell/herb visits and adult channel walking. Every exchange stays in OriginalQuests/save().
const Policy=preload("res://scripts/quest_auto_policy.gd")
const Settings=preload("res://server/quest_auto_settings_rules.gd")
const PermitGate=preload("res://server/quest_auto_permit_gate.gd")
const Motion=preload("res://server/quest_auto_motion.gd")
const Source=preload("res://server/quest_auto_source_actions.gd")
const SourcePlan=preload("res://server/quest_auto_golden_bui_plan.gd")
var source_after_landing:="travel"
const SourceFrame=preload("res://server/quest_auto_source_frame.gd")
var source_frame:RefCounted
var source_answers:RefCounted
var motion:Dictionary={}
# Geometry proposes; core alone advances and publishes committed cells.
var segment=preload("res://server/quest_auto_segment.gd").new()
const Registry=preload("res://server/quest_auto_registry.gd")
var identity=preload("res://server/quest_auto_state.gd").new()
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
var defer_tick:=false
var execution_mode:="A"
var waited:=0.0
var internal:=false
## Only a restart-restored intent may continue without the initiating socket.
var restored:=false
## Transport loss pauses this live intent; it is not restart restoration.
var detached:=false
var shutdown_intent:Dictionary={}
var path:Array[Vector2i]=[]
var herb_path:Array=[]
var issued:Array=[]
var position_serial:=0
var owns_battle:=false
var strict_walk:=false
var pause_reason:=""
var navigation=preload("res://server/quest_auto_navigation.gd").new()
var dialogue_choices:Array=[]
var waiting_saved:=false
var boss_id:=""
var boss_ready:=false
func delivery_supports(id:int)->bool:
 return Registry.supports(id)
func handoff(b,reason:String)->void:
 stop(b,reason)
 phase="manual"
 pause_reason=reason
 b.publish()
func fail(b,reason:String)->void:
 if strict_walk:handoff(b,reason)
 else:stop(b,reason)
func strict_select(b,selected_id:int=-1,allow_clean:Variant=null)->Dictionary:
 var id:int=quest_id if selected_id<0 else selected_id
 if delivery_supports(id):return Registry.select(b,id)
 var selected:=select(b,id,allow_clean)
 if not selected.is_empty():return {"status":"step","step":selected}
 if Rules.flag(b.session._profile,"ended",int(row(b,id).get("event",-1))):return {"status":"done"}
 return {"status":"manual","reason":"当前原任务条件不满足，请手动处理后重新启动。"}
func safe_shell_clean(value:Dictionary,id:int,authorized:bool)->bool:
 if id!=11 or not authorized:return false
 var recipes:Dictionary={
  "sainasu/event/event02_1":[2000,[55,92],"ENDEV=2&ITEM!=2414&SP=0,ENDEV=2&ITEM!=2414&SP=3"],
  "sainasu/event/event02_2":[1000,[57,124],"ENDEV=2&ITEM!=2415&SP=1,ENDEV=2&ITEM!=2415&SP=2"]
 }
 var npc_id:=str(value.get("npc_id",""))
 if not recipes.has(npc_id):return false
 var recipe:Array=recipes[npc_id]
 var source:Dictionary=value.get("source",{})
 var branch:Dictionary=source.get("branch_data",{})
 if not Motion.same_integer(value.get("map_id"),recipe[0]) or Motion.cell(value.get("cell"))!=recipe[1] or str(source.get("npc_id",""))!=npc_id:return false
 for field in branch:
  if field not in ["event","type","condition","texts","actions","enabled","events"]:return false
 return branch.get("event",0)==-1 and branch.get("type","")=="CLEAN" and branch.get("condition","")==recipe[2] and branch.get("actions",{})=={"CleanFlg":"2"} and branch.get("events",[]).size()==1 and Motion.same_integer(branch.events[0],2) and branch.get("enabled",false)==true
func safe_step(value:Dictionary,selected_id:int=-1,allow_clean:Variant=null)->bool:
 var source:Dictionary=value.get("source",{})
 var branch:Dictionary=source.get("branch_data",{})
 if str(source.get("type",""))=="CLEAN":return safe_shell_clean(value,quest_id if selected_id<0 else selected_id,clean_authorized if allow_clean==null else bool(allow_clean))
 if str(source.get("type","")) not in ["REQUEST","ACCEPT","MESSAGE","FREEWARP"]:return false
 if str(source.get("type",""))=="FREEWARP" and (str(value.get("npc_id",""))!="genout/wpm_120_19_15@120:19:15" or str(branch.get("actions",{}).get("Warp",""))!="122,6,5"):return false
 if branch.has("spoken_keyword") or branch.has("keyword") or branch.get("project_pet_selection",false):return false
 for action in branch.get("actions",{}):
  if action not in ["GetItem","DelItem","GetStone","EndSetFlg","GetRandItem","Warp"]:return false
 return not branch.is_empty()
func event(b) -> int:
 return int(row(b,quest_id).get("event",-1))
func title(b) -> String:
 return str(row(b,quest_id).get("title","原任务"))
func selected_mode(b)->String:
 return "A" if restored else str(Settings.effective(b.session.automation_settings()).mode)
func settings_changed(b,previous:Dictionary)->void:
 if Settings.effective(previous).mode==Settings.effective(b.session.automation_settings()).mode:return
 if not running or phase not in ["travel","landing","segment_landing"]:return
 var awaiting:bool=phase in ["landing","segment_landing"]
 identity.invalidate()
 clear_motion()
 navigation.clear()
 elapsed=0.0
 if awaiting:
  emit_position(b,{"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y]}, {},true)
func emit_position(b,point:Dictionary,origin:Dictionary={},ack_required:bool=false) -> void:
 position_serial+=1
 var packet:Dictionary=Motion.packet(identity,position_serial,point,origin,ack_required or phase=="landing")
 if packet.is_empty():handoff(b,"原任务位置资料不是有效整数坐标。");return
 if quest_id==2:packet.quest_source_landing=true
 issue_position(b,packet)
func issue_position(b,packet:Dictionary)->void:
 remember_position(packet)
 b._emit(packet)
func remember_position(packet:Dictionary)->void:
 var receipt:Dictionary=packet.duplicate(true)
 receipt.seq=position_serial
 receipt.require_full_identity=phase=="segment_landing" or packet.get("quest_source_landing",false)
 issued.append(receipt)
 while issued.size()>16:issued.pop_front()
 motion={"segment_id":packet.quest_segment_id,"position_seq":position_serial,"map_id":packet.map_id,"cell":packet.cell.duplicate(),"awaiting_ack":packet.quest_ack_required,"mode":packet.quest_segment.mode}
func clear_motion()->void:
 segment.clear()
 issued.clear()
 motion={}
func detach(b, peer:int) -> void:
 if not running or connection!=peer:return
 detached=true
 if source_frame!=null:source_frame.detach()
 connection=-1
 client=""
 clear_motion()
 b.publish()
func accept_report(b,command:Dictionary) -> bool:
 # A tagged report only acknowledges a server-issued move. Even a malformed,
 # old-run or cancelled receipt must never fall through to report_position.
 if Motion.tagged(command):
  if running and not detached and str(command.get("client",""))==client and int(command.get("_quest_connection",-1))==connection:
   for receipt in issued:
    if Motion.matches(command,receipt,identity):
     if int(receipt.seq)==position_serial:
      motion.awaiting_ack=false
      if phase=="segment_landing":
       segment.clear()
       phase="travel"
       waited=0.0
       b.publish()
      elif phase=="landing":report(b,command)
     break
  return true
 # Backend profile routing and transport own identity. Reconnection requires
 # an untagged handshake at the current authoritative cell, not an old ack.
 if running and detached and int(command.get("_quest_connection",-1))!=-1 and not str(command.get("client","")).is_empty():
  if quest_id==2:return reconnect_source(b,command)
  if int(command.get("map_id",-1))==b.automation.position_map and b._cell(command)==b.automation.position_cell:
   connection=int(command._quest_connection)
   client=str(command.client)
   detached=false
   waited=0.0
   report(b,command)
   emit_position(b,{"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y]}, {},phase=="segment_landing")
   b.publish()
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
 if map_id==10204 and origin==Vector2i(2,6) and b.quest_arrival.has_arrival(b,map_id,origin) and int(data.blocked[origin.y*int(data.width)+origin.x])==0 and not occupied.has(origin):nav.set_point_solid(origin,false)
 if nav.is_point_solid(origin) or nav.is_point_solid(goal):return result
 for cell in nav.get_id_path(origin,goal):result.append(cell)
 if not result.is_empty():result.pop_front()
 return result
func start_battle(b) -> void:
 clear_motion()
 if strict_walk and b.session._pending.has("quest_guard"):
  wait_boss(b)
  return
 owns_battle=true
 phase="battle"
 b.automation.start({"kind":"battle","settings":{"preset":"attack","compact":true}})
 b.automation.compact_active=true
 message="沿途遇敌：原自动战斗中，结算后继续。"
 b.publish()

func snapshot(b=null) -> Dictionary:
 var result:Dictionary={"running":running,"quest_id":quest_id,"phase":phase,"message":message,"target":target.duplicate(true),"client":client,"detached":detached,"strict_walk":strict_walk,"pause_reason":pause_reason}
 result.merge(identity.snapshot())
 result.settings=Settings.effective(b.session.automation_settings() if b!=null else {})
 result.effective_mode=execution_mode if running else result.settings.mode
 result.available_modes=["A","B","C"]
 result.mode_notice="B/C只用于已审核的七条公开走廊；保护段和未知公开段仍沿A逐格。" if result.settings.mode!="A" else ""
 if running and restored and result.settings.mode!="A":result.mode_notice="重启恢复先沿A原路推进；重新启动任务后应用所选模式。"
 result.can_continue=running and phase=="waiting_boss" and boss_ready
 result.budget={}
 result.motion=motion.duplicate(true)
 return result
func stop(b, reason:String="已停止自动任务。", persist:bool=true) -> void:
 var old_source=source_frame
 if old_source!=null:old_source.cancel()
 source_frame=null
 identity.invalidate()
 waiting_saved=false
 boss_ready=false
 var had_shutdown_intent:=not shutdown_intent.is_empty()
 if persist:shutdown_intent={}
 if not running:
  if persist and had_shutdown_intent:b.keep_resume_file()
  return
 if not persist:shutdown_intent=resume_state()
 if owns_battle and b.automation.running:b.automation.stop(reason)
 owns_battle=false
 path.clear();herb_path.clear()
 navigation.clear()
 clear_motion()
 running=false
 phase="stopped"
 message=reason
 if old_source==null or old_source.owns_pending(str(b.original_quests.pending.get("token",""))):b.original_quests.pending={}
 if persist:b.keep_resume_file()
 b.publish()
func resume_state() -> Dictionary:
 if not running:return shutdown_intent.duplicate(true)
 return {"version":3,"quest_id":quest_id,"clean_authorized":clean_authorized,"strict_walk":true,"identity":identity.checkpoint(),"phase":phase}
func suspend(b) -> void:
 # Transport shutdown must checkpoint before clearing the running intent.
 if running:
  shutdown_intent=resume_state()
  b.keep_resume_file()
 stop(b,"服务器已停止。",false)
func load_resume(b,state:Dictionary) -> void:
 if int(state.get("version",0)) not in [1,2,3] or not Policy.JOB_EVENTS.has(int(state.get("quest_id",-1))):return
 if int(Policy.JOB_EVENTS[int(state.quest_id)]) not in b.quest_catalog.enabled_events:return
 quest_id=int(state.quest_id)
 strict_walk=true
 clear_motion()
 identity.begin()
 if int(state.get("version",0))==3 and not identity.restore(state.get("identity",{})):return
 pause_reason=""
 navigation.clear()
 clean_authorized=bool(state.get("clean_authorized",false))
 b.original_quests.pending={}
 step={} if strict_walk else select(b)
 if not strict_walk and step.is_empty():return
 client=""
 connection=-1
 restored=true
 detached=false
 running=true
 execution_mode=selected_mode(b)
 phase="travel"
 elapsed=0.0
 waited=0.0
 message="服务器重启后已恢复"+title(b)+"自动任务。"
 if str(state.get("phase","")) in ["waiting_reward","waiting_boss"]:
  handoff(b,"重启后人工交接需重新核对，请手动操作后再启动。")
  return
 if b.battle_open and (strict_walk or quest_id in [1,30]):start_battle(b)
 b.publish()
func row(b,id:int) -> Dictionary:
 for quest in b.quest_helper.snapshot(b).quests:
  if int(quest.id)==id:return quest
 return {}
func select(b,selected_id:int=-1,allow_clean:Variant=null) -> Dictionary:
 var quest:=row(b,quest_id if selected_id<0 else selected_id)
 if Rules.flag(b.session._profile,"ended",int(quest.get("event",-1))):
  if (clean_authorized if allow_clean==null else bool(allow_clean)) and quest.get("can_restart",false):
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
 if quest.is_empty() or not Policy.supports(id,int(quest.event)) or not int(quest.event) in b.quest_catalog.enabled_events:return b._reject("此任务尚未开放自动推进。")
 if b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active() or not b.original_quests.pending.is_empty():return b._reject("当前正忙。")
 if b.quest_visit_guard.is_valid():
  var reason:=str(b.quest_visit_guard.call())
  if not reason.is_empty():return b._reject(reason)
 if str(command.get("client","")).is_empty():return b._reject("缺少发起设备。")
 if int(quest.event)==4 and int(b.session._profile.player.level)<30:return b._reject("原成人仪式入口需要等级30；自动任务不能绕过等级门。")
 var first:Dictionary=strict_select(b,int(id),bool(quest.get("can_restart",false)))
 if first.get("status","")!="step" or not safe_step(first.get("step",{}),int(id),bool(quest.get("can_restart",false))):return b._reject(str(first.get("reason",quest.get("blocked_reason","")))+" 当前没有可自动执行的已审核原任务步骤。")
 quest_id=int(id)
 strict_walk=true
 clear_motion()
 identity.begin()
 pause_reason=""
 navigation.clear()
 clean_authorized=bool(quest.get("can_restart",false))
 step=first.step.duplicate(true)
 shutdown_intent={}
 restored=false
 detached=false
 client=str(command.client)
 connection=int(command.get("_quest_connection",-1))
 running=true
 execution_mode=selected_mode(b)
 phase="travel"
 message=title(b)+"自动任务：准备前往原 NPC。"
 path.clear();herb_path.clear()
 clear_motion()
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
  motion.awaiting_ack=false
  phase=source_after_landing if quest_id==2 else ("travel" if strict_walk or event(b)==4 or (event(b)==1 and int(target.get("map_id",-1)) in [200,20101,20102,20103,20104,20105]) else "talk")
  source_after_landing="travel"
  waited=0.0
  message="已确认抵达，准备原任务对话。"
  b.publish()
func tick(b,delta:float) -> void:
 if not running:return
 if b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():stop(b,"组队变化停止了自动任务。");return
 if phase=="waiting_reward":
  if b.original_quests.pending.is_empty():handoff(b,"奖励窗口已失效，请重新操作。")
  return
 if phase=="waiting_boss":
  poll_boss(b)
  return
 if phase=="battle":
  if b.automation.running:return
  if b.battle_open or not b.session._pending.is_empty():fail(b,"沿途自动战斗已停止，请手动处理。");return
  owns_battle=false
  if str(b.battle_state.get("outcome","")) not in ["win","captured"]:fail(b,"沿途战斗未获胜。");return
  var saved_identity:Dictionary=identity.checkpoint()
  if not b.save():fail(b,"沿途战斗保存失败，停止自动任务。");return
  if not running or identity.checkpoint()!=saved_identity:return
  path.clear();herb_path.clear()
  navigation.clear()
  phase="travel"
 if b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active():stop(b,"其他活动停止了自动任务。");return
 if not strict_walk and Rules.flag(b.session._profile,"ended",event(b)) and not clean_authorized:
  stop(b,title(b)+"已完成。")
  return
 if detached:return
 if phase in ["landing","segment_landing"]:
  waited+=delta
  if waited>=30.0:fail(b,"等待地图位置确认超时。")
  return
 elapsed+=maxf(0.0,delta)
 var desired:String="A" if quest_id==2 else selected_mode(b)
 var cadence:float=0.2/Settings.C_SPEED_MULTIPLIER if phase=="travel" and desired=="C" else 0.2
 if elapsed<cadence:return
 defer_tick=false
 internal=true
 advance(b)
 internal=false
 if not defer_tick:elapsed=0.0
func herb_travel(b,npc:Dictionary)->void:
 var geometry=preload("res://server/legacy_cave_helper.gd")
 var map_id:int=b.automation.position_map
 var cell:Vector2i=b.automation.position_cell
 var portal:Dictionary=geometry.entrance(b.quest_helper,npc)
 if portal.is_empty():stop(b,"哈罗山原入口资料缺失。");return
 if map_id not in range(20101,20106) or not b.quest_arrival.has_arrival(b,map_id,cell):
  herb_path.clear()
  var source:=Vector2i(int(portal.cell[0]),int(portal.cell[1]))
  if map_id!=int(portal.from_map) or absi(cell.x-source.x)+absi(cell.y-source.y)>1:
   target=geometry.destination(b.quest_helper,b,npc,"near")
   if target.is_empty():stop(b,"哈罗山公开入口没有安全落点。");return
   b.automation.position_changed(int(target.map_id),Vector2i(int(target.cell[0]),int(target.cell[1])),map_id!=int(target.map_id))
  elif cell!=source:
   target={"map_id":map_id,"cell":portal.cell.duplicate()}
   b.automation.position_changed(map_id,source,false,"walk")
  else:
   var passage:Dictionary=b._cmd_check_passage({"from_map":map_id,"to_map":int(portal.to_map)})
   if not passage.ok:stop(b,str(passage.get("reason","原入口拒绝通行。")));return
   target={"map_id":int(portal.to_map),"cell":portal.target.duplicate()}
   b.automation.position_changed(int(target.map_id),Vector2i(int(target.cell[0]),int(target.cell[1])),true,"walk")
   if not b.quest_arrival.has_arrival(b,int(target.map_id),b.automation.position_cell):stop(b,"原入口未授予山洞路线。");return
  phase="travel" if restored else "landing"
  waited=0.0;emit_position(b,target);b.publish();return
 var close:Vector2i=cell-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if map_id==int(npc.map_id) and maxi(absi(close.x),absi(close.y))<=2 and b.quest_arrival.check_action(b,npc,step.source.branch_data,str(step.source.type)).is_empty():
  phase="talk";herb_path.clear();b.publish();return
 if herb_path.is_empty():herb_path=geometry.path_to_npc(b.quest_helper,b,npc)
 if herb_path.is_empty():stop(b,"哈罗山原路线不可步行抵达医生。");return
 target=herb_path.pop_front()
 var next:=Vector2i(int(target.cell[0]),int(target.cell[1]))
 var changed:bool=int(target.map_id)!=map_id
 if changed:
  var passage:Dictionary=b._cmd_check_passage({"from_map":map_id,"to_map":int(target.map_id)})
  if not passage.ok:stop(b,str(passage.get("reason","原楼梯拒绝通行。")));return
 b.automation.position_changed(int(target.map_id),next,changed,"walk")
 if not b.quest_arrival.has_arrival(b,int(target.map_id),next):stop(b,"原路步行资格已变化。");return
 emit_position(b,target)
 if changed:
  phase="travel" if restored else "landing";waited=0.0
 else:
  var reply:Dictionary=b._cmd_field_step({"map_id":map_id,"cell":[next.x,next.y],"encounter":true})
  if reply.get("battle",false):start_battle(b);return
 message="沿哈罗山原楼梯与通道步行前往医生。"
 b.publish()

func adult_enter(b)->void:
 var portal:Dictionary=b.quest_helper.places.links(10202).get(Vector2i(31,13),{})
 if portal.is_empty() or int(portal.get("to_map",-1))!=10204 or (portal.get("target",[]).size()!=2 or Vector2i(int(portal.target[0]),int(portal.target[1]))!=Vector2i(2,6)) or int(portal.get("requires_level",-1))!=30:
  stop(b,"原成人仪式入口资料缺失，停止自动任务。");return
 if int(b.session._profile.player.level)<int(portal.requires_level):stop(b,"原成人仪式入口需要等级30，不能绕门。");return
 var cell:Vector2i=b.automation.position_cell
 if b.automation.position_map!=10202 or cell not in [Vector2i(30,13),Vector2i(31,13)]:
  target={"map_id":10202,"cell":[30,13]}
  b.automation.position_changed(10202,Vector2i(30,13),b.automation.position_map!=10202)
  phase="travel" if restored else "landing"
  waited=0.0;emit_position(b,target);b.publish();return
 if cell==Vector2i(30,13):
  b.automation.position_changed(10202,Vector2i(31,13),false,"walk")
  emit_position(b,{"map_id":10202,"cell":[31,13]});b.publish();return
 var allowed:Dictionary=b._cmd_check_passage({"from_map":10202,"to_map":10204})
 if not allowed.ok:stop(b,str(allowed.get("reason","原入口拒绝通行。")));return
 b.automation.position_changed(10204,Vector2i(2,6),true,"walk")
 if not b.quest_arrival.has_arrival(b,10204,Vector2i(2,6)):stop(b,"原入口未授予通道资格。");return
 target={"map_id":10204,"cell":[2,6]}
 phase="travel" if restored else "landing"
 waited=0.0;emit_position(b,target);b.publish()

func advance(b) -> void:
 if quest_id==2 and strict_walk:
  advance_source(b)
  return
 if strict_walk:
  strict_advance(b)
  return
 if phase=="travel":
  step=select(b)
  if step.is_empty():stop(b,title(b)+"已完成。" if Rules.flag(b.session._profile,"ended",event(b)) else "原任务条件已变化。");return
  var npc:Dictionary=b.original_quests.npc_by_id(str(step.npc_id))
  if npc.is_empty() or b.original_quests.branch_for(npc,b.session._profile)!=step.source.branch_data:stop(b,"原任务分支已变化。");return
  if event(b)==1 and int(npc.map_id)==20105:
   herb_travel(b,npc)
   return
  if event(b)==4:
   if b.automation.position_map!=10204 or not b.quest_arrival.has_arrival(b,10204,b.automation.position_cell):
    adult_enter(b)
    return
   target=b.quest_helper.adult_walk_destination(b,npc)
  else:target=b.quest_helper.destination(b,npc,"near")
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

func strict_advance(b)->void:
 if phase=="travel":
  var selection:=strict_select(b)
  if str(selection.get("status","manual"))=="done":stop(b,title(b)+"已完成。");return
  if str(selection.get("status","manual"))!="step":handoff(b,str(selection.get("reason","请手动处理当前任务步骤。")));return
  step=selection.get("step",{})
  if identity.step_id!=str(step.get("id","")):clear_motion()
  identity.select_step(str(step.get("id","")))
  if not safe_step(step):handoff(b,"此步骤包含选择、消费、战斗或未审核动作，请手动处理后重新启动。");return
  var npc:Dictionary=b.original_quests.npc_by_id(str(step.get("npc_id","")))
  if npc.is_empty():handoff(b,"原任务人物当前不可用。");return
  var map_id:int=b.automation.position_map
  var origin:Vector2i=b.automation.position_cell
  if not b.quest_arrival.has_arrival(b,map_id,origin):handoff(b,"当前原路到达资格已失效，请手动沿原入口重新进入后启动。");return
  var offset:=origin-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
  if map_id==int(npc.map_id) and maxi(absi(offset.x),absi(offset.y))<=2:
   if b.original_quests.branch_for(npc,b.session._profile)!=step.source.branch_data:handoff(b,"原任务分支已经变化，请手动处理。");return
   var denied:String=b.quest_arrival.check_action(b,npc,step.source.branch_data,str(step.source.type))
   if not denied.is_empty():handoff(b,denied);return
   navigation.clear()
   var reply:Dictionary=b.original_quests.talk(b,str(npc.id))
   if not reply.get("ok",false):handoff(b,str(reply.get("reason","原对话失败。")));return
   dialogue_choices=step.get("auto_choices",["ok"] if str(step.source.type)=="MESSAGE" else ["yes","ok"]).duplicate()
   phase="strict_dialogue"
   strict_dialogue_reply(b,reply)
   return
  execution_mode=selected_mode(b)
  var point:Dictionary={}
  if execution_mode=="A":point=navigation.next(b,npc)
  else:
   point=segment_point(b,npc)
   if point.is_empty():handoff(b,"当前审核路线不可用，请沿原路手动处理。");return
   if segment.proposal.get("kind")!="walk":
    advance_public_segment(b,point)
    return
   if elapsed<0.2:defer_tick=true;return
   segment.clear()
  if point.has("gate"):
   advance_permit_gate(b,point)
   return
  if point.is_empty() or not navigation.validate(b,point):handoff(b,"没有可连续步行的原路线；请手动处理原门或当前位置后重新启动。");return
  var changed:bool=int(point.map_id)!=map_id
  if point.has("portal"):
   var passage:Dictionary=b._cmd_check_passage({"from_map":map_id,"to_map":int(point.map_id)})
   if not passage.get("ok",false):handoff(b,str(passage.get("reason","原入口拒绝通行。")));return
  b.automation.position_changed(int(point.map_id),Vector2i(int(point.cell[0]),int(point.cell[1])),changed,"walk")
  if not b.quest_arrival.has_arrival(b,int(point.map_id),b.automation.position_cell):handoff(b,"原路线资格已变化，停止推进。");return
  target={"map_id":int(point.map_id),"cell":point.cell.duplicate()}
  if changed:
   navigation.clear()
   phase="travel" if restored else "landing"
   waited=0.0
  var move_identity:Dictionary=identity.checkpoint()
  emit_position(b,target,{"map_id":map_id,"cell":[origin.x,origin.y]},changed and not restored)
  if not running or identity.checkpoint()!=move_identity:return
  if not changed:
   var encounter:Dictionary=b._cmd_field_step({"map_id":map_id,"cell":point.cell.duplicate(),"encounter":true})
   if encounter.get("battle",false):start_battle(b);return
  message="沿原路线步行前往"+str(npc.get("name","任务人物"))+"；沿途普通遇敌自动战斗后继续。"
  b.publish()
  return
 if phase=="strict_dialogue":
  var pending:Dictionary=b.original_quests.pending
  if pending.get("branch",{})!=step.source.branch_data or dialogue_choices.is_empty():handoff(b,"原对话已变化，请手动处理。");return
  var before_map:int=b.automation.position_map
  var before_cell:Vector2i=b.automation.position_cell
  var reply:Dictionary=b.original_quests.choose(b,str(pending.get("token","")),str(dialogue_choices.pop_front()))
  if not reply.get("ok",false):handoff(b,str(reply.get("reason","原交易失败。")));return
  strict_dialogue_reply(b,reply)
  if running and (before_map!=b.automation.position_map or before_cell!=b.automation.position_cell):
   target={"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y]}
   navigation.clear()
   phase="travel" if restored else "landing"
   waited=0.0
   emit_position(b,target,{"map_id":before_map,"cell":[before_cell.x,before_cell.y]},not restored)
  b.publish()

## Replan once after any geometry/eligibility invalidation, always from authority.
func segment_point(b,npc:Dictionary)->Dictionary:
 var attempts:=2
 if segment.active(identity) and not segment.complete():
  var retained:Dictionary=segment.next_point(b,npc,navigation,identity)
  if not retained.is_empty():return retained
  navigation.clear()
  attempts=1
 for attempt in range(attempts):
  var proposal:Dictionary=navigation.next_segment(b,npc,execution_mode,Settings.C_MAX_CELLS)
  var origin:Dictionary={"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y]}
  if not segment.begin(proposal,execution_mode,origin,identity,position_serial+1):return {}
  var point:Dictionary=segment.next_point(b,npc,navigation,identity)
  if not point.is_empty():return point
  navigation.clear()
 return {}
func advance_public_segment(b,point:Dictionary)->void:
 if elapsed<segment.interval():defer_tick=true;return
 var checkpoint:Dictionary=identity.checkpoint()
 var map_id:int=b.automation.position_map
 # Every point was just checked by real geometry, including protected cells.
 b.automation.position_changed(map_id,Vector2i(int(point.cell[0]),int(point.cell[1])),false,"project")
 if not segment.commit(point,identity):handoff(b,"移动段身份已失效。");return
 target={"map_id":map_id,"cell":Motion.cell(point.cell)}
 var done:bool=segment.complete()
 if done and not restored:phase="segment_landing";waited=0.0
 position_serial+=1
 var packet:Dictionary=segment.packet(identity,position_serial,done and not restored)
 issue_position(b,packet)
 # Position publication can synchronously cancel/detach or change settings.
 if not running or detached or identity.checkpoint()!=checkpoint:return
 var encounter:Dictionary=b._cmd_field_step({"map_id":map_id,"cell":target.cell.duplicate(),"encounter":true})
 if not running or detached or identity.checkpoint()!=checkpoint:return
 if encounter.get("battle",false):start_battle(b);return
 if not encounter.get("ok",false) or encounter.get("hit",false):handoff(b,str(encounter.get("reason","原遇敌已命中但战斗未能开启，请手动处理。")));return
 if done and restored:segment.clear()
 message="沿已审核公开走廊推进；原门和保护段仍逐格。"
 b.publish()

func strict_dialogue_reply(b,reply:Dictionary)->void:
 if not reply.has("dialogue"):
  if str(step.get("source",{}).get("type",""))=="CLEAN":clean_authorized=false
  phase="travel"
  navigation.clear()
  b.publish()
  return
 var dialogue:Dictionary=reply.dialogue
 if dialogue.has("kind") or dialogue_choices.is_empty():handoff(b,"此对话需要玩家选择，请手动处理后重新启动。");return
 var choices:Array=dialogue.get("choices",[])
 var next:=str(dialogue_choices[0])
 # yes/no is the reviewed ordinary transaction confirmation; any reward
 # choice, input field or extra alternative is never auto-accepted.
 var ids:Array=choices.map(func(choice):return str(choice.get("id","")))
 if not ((next=="yes" and ids==["yes","no"]) or (next=="ok" and ids==["ok"])):handoff(b,"此对话需要玩家选择，请手动处理后重新启动。");return
 message="准备确认已审核的原送物步骤。"
 b.publish()


## Only a reviewed server-side plan may open this handoff. No client command
## accepts a dialogue or action kind. Services and UID/king confirmations must
## be reviewed by their owning plan before calling this entry point.
func wait_reward(b,reply:Dictionary)->void:
 if not running or not reply.get("ok",false) or not reply.get("dialogue") is Dictionary or b.original_quests.pending.is_empty():
  handoff(b,"奖励对话不可用。")
  return
 var pending:Dictionary=b.original_quests.pending
 var branch:Dictionary=pending.get("branch",{})
 if bool(branch.get("project_pet_selection",false)) or branch.get("actions",{}).has("DelPet") or str(pending.get("npc",{}).get("handler",""))=="Transmigration":
  handoff(b,"交宠与精灵王确认需独立人工操作。")
  return
 var dialogue:Dictionary=reply.dialogue
 if str(dialogue.get("token",""))!=str(b.original_quests.pending.get("token","")):
  handoff(b,"奖励对话已经改变。")
  return
 clear_motion()
 phase="waiting_reward"
 waiting_saved=false
 _reward_window(b,dialogue)
 message="请选择原任务奖励；成功保存后自动继续。"
 b.publish()
func _reward_window(b,dialogue:Dictionary)->void:
 identity.wait_for("reward",str(dialogue.get("token","")),str(dialogue.get("npc_id","")),str(b.session._profile.get("character_id","")))
 identity.waiting.dialogue=dialogue.duplicate(true)
func accepts_waiting_command(b,command:Dictionary)->bool:
 if not running or phase!="waiting_reward" or not identity.matches(command,str(b.session._profile.get("character_id",""))):return false
 var pending:Dictionary=b.original_quests.pending
 return not pending.is_empty() and str(pending.get("token",""))==str(identity.waiting.get("token","")) and str(pending.get("npc",{}).get("id",""))==str(identity.waiting.get("npc_id",""))
func choose_waiting(b,command:Dictionary)->Dictionary:
 if not accepts_waiting_command(b,command):return b._reject("自动任务等待已过期。")
 var expected_run:String=identity.run_id
 var expected_step:String=identity.step_id
 var expected_revision:int=identity.revision
 var saved_before:int=b.quest_save_serial
 var choice:=str(command.get("choice",""))
 internal=true
 var reply:Dictionary=b.original_quests.choose(b,str(command.get("token","")),choice,str(command.get("text","")),command.get("pet_ids",[]))
 internal=false
 # Synchronous publish observers may cancel while the transaction saves.
 # The successful transaction remains committed, but its old run cannot revive.
 if not running or phase!="waiting_reward" or identity.run_id!=expected_run or identity.step_id!=expected_step or identity.revision!=expected_revision:
  if not running:b.original_quests.pending={}
  reply.erase("dialogue")
  reply.closed=true
  return reply
 if not reply.get("ok",false) or choice in ["no","cancel"]:
  handoff(b,str(reply.get("reason","已取消奖励选择，停止自动任务。")))
  return reply
 waiting_saved=waiting_saved or b.quest_save_serial>saved_before
 # An already-saved plain end acknowledgement contains no further choice.
 # Close it through the original handler so saved rewards need no extra click.
 if waiting_saved and reply.get("dialogue") is Dictionary and str(b.original_quests.pending.get("phase",""))=="end":
  var choices:Array=reply.dialogue.get("choices",[])
  if choices.map(func(item):return str(item.get("id","")))==["ok"]:
   internal=true
   reply=b.original_quests.choose(b,str(reply.dialogue.get("token","")),"ok")
   internal=false
   if not reply.get("ok",false):handoff(b,"奖励已保存但结果确认已失效。 ");return reply
 if reply.get("dialogue") is Dictionary:
  _reward_window(b,reply.dialogue)
  b.publish()
  return reply
 if not waiting_saved:
  handoff(b,"本次选择未保存任务进展，请手动处理。")
  return reply
 identity.invalidate()
 waiting_saved=false
 navigation.clear()
 path.clear()
 var next:Dictionary=strict_select(b)
 if str(next.get("status","manual"))=="done":stop(b,title(b)+"已完成。")
 elif str(next.get("status","manual"))=="step":
  phase="travel"
  clear_motion()
  identity.select_step(str(next.get("step",{}).get("id","")))
  message="奖励已保存，继续原任务。"
  b.publish()
 else:handoff(b,str(next.get("reason","奖励已保存；下一步需手动处理。")))
 return reply

## Called only after an audited plan starts the actual original guard battle.
func wait_boss(b)->void:
 var id:=str(b.session._pending.get("battle_id",""))
 if not running or id.is_empty() or not b.session._pending.has("quest_guard"):
  handoff(b,"守卫战斗身份不可用，请手动处理。")
  return
 clear_motion()
 boss_id=id
 boss_ready=false
 owns_battle=false
 identity.invalidate()
 phase="waiting_boss"
 message="请手动完成守卫战；胜利保存后按继续。"
 b.publish()
func poll_boss(b)->void:
 if b.battle_open or not b.session._pending.is_empty():return
 if boss_ready:return
 if str(b.battle_state.get("battle_id",""))!=boss_id or str(b.battle_state.get("outcome",""))!="win" or not bool(b.battle_state.get("settled",false)) or not str(b.battle_state.get("quest_arrival_denied","")).is_empty() or boss_id not in b.session._profile.completed_battles:
  handoff(b,"守卫战未成功完成，请手动处理。")
  return
 if not b.save():handoff(b,"守卫战保存失败，停止自动任务。");return
 boss_ready=true
 identity.invalidate()
 message="守卫战已胜利保存，请按继续。"
 b.publish()
func continue_boss(b,command:Dictionary)->Dictionary:
 if not running or phase!="waiting_boss" or not boss_ready or str(command.get("quest_run_id",""))!=identity.run_id or str(command.get("quest_step_id",""))!=identity.step_id or command.get("quest_revision",-1)!=identity.revision:return b._reject("守卫战继续请求已过期或尚未完成。")
 if b.battle_open or not b.session._pending.is_empty() or boss_id not in b.session._profile.completed_battles:return b._reject("守卫战状态已改变。")
 boss_ready=false
 identity.invalidate()
 phase="travel"
 navigation.clear()
 path.clear()
 message="继续原任务。"
 b.publish()
 return {"ok":true}


## The navigation proposal names a reviewed resident; it never supplies authority.
func advance_permit_gate(b,point:Dictionary)->Dictionary:
 var denied:String=PermitGate.point_error(point)
 if not denied.is_empty():
  handoff(b,denied)
  return {"ok":false,"reason":denied}
 var expected:Dictionary=identity.checkpoint()
 var origin:Dictionary={"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y]}
 var reply:Dictionary=b.commit_undersea_permit_gate(str(point.gate.source_id),identity.run_id,identity.step_id,identity.revision)
 if not reply.get("ok",false):
  if running and identity.checkpoint()==expected:handoff(b,str(reply.get("reason","原守卫拒绝通行。")))
  return reply
 # A committed move survives cancellation; its automation capability does not.
 if not running or identity.checkpoint()!=expected:
  reply.continued=false
  b._emit({"type":"position","map_id":int(reply.target.map_id),"cell":reply.target.cell.duplicate(),"client":"server"})
  b.publish()
  return reply
 reply.continued=true
 identity.invalidate()
 clear_motion()
 navigation.clear()
 path.clear()
 target=reply.target.duplicate(true)
 phase="travel" if restored else "landing"
 waited=0.0
 message="已出示原通行证，等待确认原守卫目的位置。"
 emit_position(b,target,origin,not restored)
 b.publish()
 return reply

## Dormant 4c internal hooks. Registry/start/tick do not dispatch job2 yet.
func source_live(frame)->bool:
 return frame!=null and frame==source_frame and running and quest_id==2 and not detached and connection!=-1 and frame.matches(identity.checkpoint(),connection)
func source_open(b,proposal:Dictionary)->Dictionary:
 if proposal.get("action") not in ["source_service","source_exchange"]:return b._reject("此接点不执行原楼梯或其他动作。")
 if not internal or not running or quest_id!=2 or detached or connection==-1 or identity.step_id!=str(proposal.get("id","")) or step!=proposal:return b._reject("原服务执行身份无效。")
 var checked:Dictionary=Source.validate_open(b,2,proposal)
 if not checked.ok:return checked
 if source_frame!=null:source_frame.cancel()
 source_frame=SourceFrame.new()
 source_frame.owner_profile={"profile_id":str(b.session._profile.get("profile_id","")),"character_id":str(b.session._profile.get("character_id",""))}
 if not source_frame.configure(identity.checkpoint(),connection,str(proposal.npc_id),str(proposal.source.source_id)):return b._reject("原服务身份不完整。")
 return b.call_quest_source(source_frame,proposal)
func source_next(b)->Dictionary:
 if not internal or not source_live(source_frame):return b._reject("原服务执行身份已失效。")
 var checked:Dictionary=Source.validate_step(b,2,step)
 if not checked.ok or b.battle_open or not b.session._pending.is_empty():return b._reject("原服务资格已变化。")
 if b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():return b._reject("请先退出团队。")
 if not b.original_quests.allowed(b,checked.npc) or not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):return b._reject("原路近距资格已失效。")
 var page:Dictionary=source_frame.page
 if page.is_empty() or str(b.original_quests.pending.get("token",""))!=str(page.token) or str(b.original_quests.pending.get("npc",{}).get("id",""))!=str(step.npc_id):return b._reject("原对话已失效。")
 var ids:Array=page.choices.map(func(option):return option.id)
 var answer:Dictionary={}
 if ids==["yes","no"]:answer={"choice":"yes"}
 elif ids==["ok"]:answer={"choice":"ok"}
 elif step.source.get("kind")=="golden_bui_janken" and ids==["rock","scissors","paper"]:answer={"choice":"rock"}
 elif step.source.get("kind")=="golden_bui_quiz":
  if source_answers==null:source_answers=preload("res://server/quest_auto_source_answers.gd").new()
  answer=source_answers.resolve_quiz(str(step.source.source_id),page)
  if answer.get("status")!="answer":return b._reject(str(answer.get("reason","原公开题目未能匹配。")))
 else:return b._reject("原公开选项未审核。")
 var choice:Dictionary=source_frame.take_choice(identity.checkpoint(),connection,str(page.token),str(answer.choice),str(answer.get("text","")))
 if choice.is_empty():return b._reject("原对话回复已经消费。")
 return b.call_quest_source(source_frame,step,choice)

## Prepare before subsequent snapshots; delivery revalidates after observers.
## The original transaction has already moved/saved/granted its own proof.
func source_position_packet(b,source:Dictionary,original:Dictionary)->Dictionary:
 if not b.quest_source_call_live(source):return original
 if b.automation.position_map!=int(original.map_id) or b.automation.position_cell!=Vector2i(int(original.cell[0]),int(original.cell[1])):return original
 identity.invalidate()
 source.frame.identity=identity.checkpoint()
 source.identity=identity.checkpoint()
 clear_motion()
 navigation.clear()
 target={"map_id":original.map_id,"cell":original.cell.duplicate()}
 phase="landing"
 waited=0.0
 position_serial+=1
 var packet:Dictionary=Motion.packet(identity,position_serial,target,source.origin,true)
 packet.quest_source_landing=true
 packet.v=b.PROTOCOL
 remember_position(packet)
 return packet

## Never mint another capability at dispatch, or rewrite queued snapshots.
func source_position_current(b,source:Dictionary,packet:Dictionary)->bool:
 if not b.quest_source_call_live(source) or not packet.get("quest_source_landing",false):return false
 if not Motion.same_integer(packet.get("map_id"),b.automation.position_map) or Motion.cell(packet.get("cell"))!=[b.automation.position_cell.x,b.automation.position_cell.y]:return false
 if issued.is_empty():return false
 var command:Dictionary=packet.duplicate()
 return Motion.matches(command,issued[-1],identity)

## Server-only admission for the still-unregistered dispatcher. Not an RPC or
## a test bypass: pure source selection and normal authority guards apply.
func begin_source_run(b,device:String,peer:int)->Dictionary:
 if running or device.is_empty() or peer==-1 or b.battle_open or not b.session._pending.is_empty() or not b.original_quests.pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active():return b._reject("当前无法开始原源任务。")
 if b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():return b._reject("请先退出团队。")
 var selected:Dictionary=SourcePlan.select(b,2)
 if selected.get("status")!="step":return b._reject(str(selected.get("reason","原任务不需要继续。")))
 var checked:Dictionary=Source.validate_step(b,2,selected.step)
 if not checked.ok:return checked
 quest_id=2;client=device;connection=peer;running=true;strict_walk=true
 restored=false;detached=false;owns_battle=false;shutdown_intent={}
 source_frame=null;source_after_landing="travel"
 identity.begin();step={};target={};path.clear();herb_path.clear();navigation.clear();clear_motion()
 phase="travel";elapsed=0.0;waited=0.0;execution_mode="A";pause_reason=""
 message="沿审核原路前往原道场人物。"
 b.publish()
 return {"ok":true}
func advance_source(b)->void:
 if phase=="source_dialogue":
  source_reply(b,source_next(b))
  return
 if phase!="travel":return
 var selected:Dictionary=SourcePlan.select(b,2)
 if selected.get("status")=="done":stop(b,"原金布伊任务已完成。");return
 if selected.get("status")!="step":handoff(b,str(selected.get("reason","原源路线不可用。")));return
 var proposal:Dictionary=selected.step
 var checked:Dictionary=Source.validate_step(b,2,proposal)
 if not checked.ok:handoff(b,str(checked.reason));return
 if source_frame!=null:
  source_frame.cancel();source_frame=null
 if identity.step_id!=str(proposal.id):clear_motion();navigation.clear()
 step=proposal.duplicate(true);identity.select_step(str(step.id))
 execution_mode="A"
 if step.action=="walk_portal":
  if not b.original_quests.pending.is_empty():handoff(b,"原对话尚未结束。");return
  source_walk(b,navigation.next_portal(b,step.portal))
  return
 var npc:Dictionary=checked.npc
 var offset:Vector2i=b.automation.position_cell-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if b.automation.position_map==int(npc.map_id) and maxi(absi(offset.x),absi(offset.y))<=2:
  source_reply(b,source_open(b,step))
 else:source_walk(b,navigation.next(b,npc))
func source_reply(b,reply:Dictionary)->void:
 if not running:return
 if not reply.get("ok",false):handoff(b,str(reply.get("reason","原服务失败。")));return
 if detached:return
 if not reply.get("source_commit",{}).get("continued",false):handoff(b,"原服务调用身份已失效。");return
 if reply.get("dialogue") is Dictionary:
  if source_frame==null or source_frame.page.is_empty():handoff(b,"原公开对白已变化。");return
  phase="source_dialogue"
 elif reply.get("closed",false):
  phase="landing" if reply.get("source_commit",{}).get("warp",false) else "travel"
  source_after_landing="travel";waited=0.0
 else:handoff(b,"原服务未返回可审核的后续。");return
 b.publish()
func source_walk(b,point:Dictionary)->void:
 if point.is_empty() or point.has("gate") or not navigation.validate(b,point):handoff(b,"原源路线不能连续逐格通过。");return
 var from_map:int=b.automation.position_map
 var from_cell:Vector2i=b.automation.position_cell
 if not b.quest_arrival.has_arrival(b,from_map,from_cell):handoff(b,"原路资格已失效。");return
 var changed:bool=int(point.map_id)!=from_map
 if point.has("portal"):
  if step.action!="walk_portal" or not Source.validate_portal(b,step).ok:handoff(b,"原楼梯来源已变化。");return
  var passage:Dictionary=b._cmd_check_passage({"from_map":from_map,"to_map":int(point.map_id)})
  if not passage.get("ok",false):handoff(b,str(passage.get("reason","原楼梯拒绝通行。")));return
 b.automation.position_changed(int(point.map_id),Vector2i(int(point.cell[0]),int(point.cell[1])),changed,"walk")
 if not b.quest_arrival.has_arrival(b,int(point.map_id),b.automation.position_cell):handoff(b,"原路移动未保有到达资格。");return
 target={"map_id":int(point.map_id),"cell":point.cell.duplicate()}
 if changed:phase="landing";source_after_landing="travel";waited=0.0;navigation.clear()
 var current:Dictionary=identity.checkpoint()
 emit_position(b,target,{"map_id":from_map,"cell":[from_cell.x,from_cell.y]},changed)
 if not running or detached or identity.checkpoint()!=current:return
 if not changed:
  var encounter:Dictionary=b._cmd_field_step({"map_id":from_map,"cell":point.cell.duplicate(),"encounter":true})
  if encounter.get("battle",false):start_battle(b);return
 b.publish()
func reconnect_source(b,command:Dictionary)->bool:
 # The generic legacy handshake may truncate numbers; source runs may not.
 if not Motion.same_integer(command.get("map_id"),b.automation.position_map) or Motion.cell(command.get("cell"))!=[b.automation.position_cell.x,b.automation.position_cell.y]:return true
 var next_phase:String=source_after_landing if phase=="landing" else phase
 connection=int(command._quest_connection);client=str(command.client);detached=false
 identity.invalidate();clear_motion();waited=0.0
 if next_phase=="source_dialogue":
  if source_frame==null or not source_frame.rebind(identity.checkpoint(),connection,str(b.original_quests.pending.get("token",""))):handoff(b,"原服务页在断线期间失效，请手动核对已保存进度。");return true
 else:
  if source_frame!=null:source_frame.cancel();source_frame=null
 if phase!="battle":
  source_after_landing=next_phase
  phase="landing"
 emit_position(b,{"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y]}, {},phase=="landing")
 b.publish()
 return true

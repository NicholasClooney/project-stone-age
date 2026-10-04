extends RefCounted
## Source-derived delivery runner: shell/herb visits and adult channel walking. Every exchange stays in OriginalQuests/save().
const Policy=preload("res://scripts/quest_auto_policy.gd")
const Settings=preload("res://server/quest_auto_settings_rules.gd")
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
func strict_select(b)->Dictionary:
 if delivery_supports(quest_id):return Registry.select(b,quest_id)
 var selected:=select(b)
 if not selected.is_empty():return {"status":"step","step":selected}
 if Rules.flag(b.session._profile,"ended",event(b)):return {"status":"done"}
 return {"status":"manual","reason":"当前原任务条件不满足，请手动处理后重新启动。"}
func safe_step(value:Dictionary)->bool:
 var source:Dictionary=value.get("source",{})
 var branch:Dictionary=source.get("branch_data",{})
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
func emit_position(b,point:Dictionary) -> void:
 position_serial+=1
 issued.append({"seq":position_serial,"map_id":int(point.map_id),"cell":point.cell.duplicate()})
 while issued.size()>16:issued.pop_front()
 b._emit({"type":"position","map_id":point.map_id,"cell":point.cell,"quest_position_seq":position_serial,"client":"quest_auto"})
func detach(b, peer:int) -> void:
 if not running or connection!=peer:return
 detached=true
 connection=-1
 client=""
 b.publish()
func accept_report(b,command:Dictionary) -> bool:
 # Backend routing has already authenticated the profile; transport overwrites
 # the connection tag. Only an actual report at the authoritative cell rebinds.
 if running and detached and int(command.get("_quest_connection",-1))!=-1 and not str(command.get("client","")).is_empty():
  if int(command.get("map_id",-1))==b.automation.position_map and b._cell(command)==b.automation.position_cell:
   connection=int(command._quest_connection)
   client=str(command.client)
   detached=false
   waited=0.0
   b.publish()
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
 if map_id==10204 and origin==Vector2i(2,6) and b.quest_arrival.has_arrival(b,map_id,origin) and int(data.blocked[origin.y*int(data.width)+origin.x])==0 and not occupied.has(origin):nav.set_point_solid(origin,false)
 if nav.is_point_solid(origin) or nav.is_point_solid(goal):return result
 for cell in nav.get_id_path(origin,goal):result.append(cell)
 if not result.is_empty():result.pop_front()
 return result
func start_battle(b) -> void:
 if strict_walk and b.session._pending.has("quest_guard"):
  handoff(b,"守卫战斗不在本批自动推进范围，请手动处理。")
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
 result.effective_mode="A"
 result.available_modes=["A"]
 result.mode_notice="B/C执行器尚未接入，当前沿A原路推进。" if result.settings.mode!="A" else ""
 result.can_continue=false
 result.budget={}
 return result
func stop(b, reason:String="已停止自动任务。", persist:bool=true) -> void:
 identity.invalidate()
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
 issued.clear()
 running=false
 phase="stopped"
 message=reason
 b.original_quests.pending={}
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
 phase="travel"
 elapsed=0.0
 waited=0.0
 message="服务器重启后已恢复"+title(b)+"自动任务。"
 if b.battle_open and (strict_walk or quest_id in [1,30]):start_battle(b)
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
 if quest.is_empty() or not Policy.supports(id,int(quest.event)) or not int(quest.event) in b.quest_catalog.enabled_events:return b._reject("此任务尚未开放自动推进。")
 if b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active() or not b.original_quests.pending.is_empty():return b._reject("当前正忙。")
 if b.quest_visit_guard.is_valid():
  var reason:=str(b.quest_visit_guard.call())
  if not reason.is_empty():return b._reject(reason)
 if str(command.get("client","")).is_empty():return b._reject("缺少发起设备。")
 if int(quest.event)==4 and int(b.session._profile.player.level)<30:return b._reject("原成人仪式入口需要等级30；自动任务不能绕过等级门。")
 quest_id=int(id)
 strict_walk=true
 identity.begin()
 pause_reason=""
 navigation.clear()
 clean_authorized=bool(quest.get("can_restart",false))
 step={} if strict_walk else select(b)
 if not strict_walk and step.is_empty():return b._reject(str(quest.get("blocked_reason",""))+" 当前没有可自动执行的原任务步骤。")
 shutdown_intent={}
 restored=false
 detached=false
 client=str(command.client)
 connection=int(command.get("_quest_connection",-1))
 running=true
 phase="travel"
 message=title(b)+"自动任务：准备前往原 NPC。"
 path.clear();herb_path.clear()
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
  phase="travel" if strict_walk or event(b)==4 or (event(b)==1 and int(target.get("map_id",-1)) in [200,20101,20102,20103,20104,20105]) else "talk"
  waited=0.0
  message="已确认抵达，准备原任务对话。"
  b.publish()
func tick(b,delta:float) -> void:
 if not running:return
 if b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():stop(b,"组队变化停止了自动任务。");return
 if phase=="battle":
  if b.automation.running:return
  if b.battle_open or not b.session._pending.is_empty():fail(b,"沿途自动战斗已停止，请手动处理。");return
  owns_battle=false
  if str(b.battle_state.get("outcome","")) not in ["win","captured"]:fail(b,"沿途战斗未获胜。");return
  if not b.save():fail(b,"沿途战斗保存失败，停止自动任务。");return
  path.clear();herb_path.clear()
  navigation.clear()
  phase="travel"
 if b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active():stop(b,"其他活动停止了自动任务。");return
 if not strict_walk and Rules.flag(b.session._profile,"ended",event(b)) and not clean_authorized:
  stop(b,title(b)+"已完成。")
  return
 if detached:return
 if phase=="landing":
  waited+=delta
  if waited>=30.0:fail(b,"等待地图位置确认超时。")
  return
 elapsed+=delta
 if elapsed<0.2:return
 elapsed=0.0
 internal=true
 advance(b)
 internal=false
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
  var point:Dictionary=navigation.next(b,npc)
  if point.is_empty() or not navigation.validate(b,point):handoff(b,"没有可连续步行的原路线；请手动处理原门或当前位置后重新启动。");return
  var changed:bool=int(point.map_id)!=map_id
  if point.has("portal"):
   var passage:Dictionary=b._cmd_check_passage({"from_map":map_id,"to_map":int(point.map_id)})
   if not passage.get("ok",false):handoff(b,str(passage.get("reason","原入口拒绝通行。")));return
  b.automation.position_changed(int(point.map_id),Vector2i(int(point.cell[0]),int(point.cell[1])),changed,"walk")
  if not b.quest_arrival.has_arrival(b,int(point.map_id),b.automation.position_cell):handoff(b,"原路线资格已变化，停止推进。");return
  target={"map_id":int(point.map_id),"cell":point.cell.duplicate()}
  emit_position(b,target)
  if changed:
   navigation.clear()
   phase="travel" if restored else "landing"
   waited=0.0
  else:
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
   emit_position(b,target)
   phase="travel" if restored else "landing"
   waited=0.0
  b.publish()
func strict_dialogue_reply(b,reply:Dictionary)->void:
 if not reply.has("dialogue"):
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

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
# Private lifetime for the dormant ordinary Doctor route; never a fee capability.
var _doctor_scope:Dictionary={}
func _doctor_start_frame(b,command:Dictionary)->Dictionary:
 var peer:Variant=command.get("_quest_connection")
 if not peer is int or peer==-1 or not b._fee_bindings.get(peer) is RefCounted:return {}
 return {"transition":transition_frame(b),"peer":peer,"binding":b._fee_bindings.get(peer),"account":b.account_name,"profile":b.session._profile.get("profile_id"),"character":b.session._profile.get("character_id")}
func _doctor_start_current(b,f:Dictionary)->bool:
 return not f.is_empty() and b._doctor_request_enabled() and transition_current(b,f.transition) and b.account_name==f.account and b.session._profile.get("profile_id")==f.profile and b.session._profile.get("character_id")==f.character and is_same(b._fee_bindings.get(f.peer),f.binding)
func _doctor_live(b)->bool:
 if _doctor_scope.is_empty() or b.session==null:return false
 var f:Dictionary=_doctor_scope
 return b._doctor_request_enabled() and is_same(b.quest_auto,self) and is_same(b.session,f.session.get_ref()) and is_same(identity,f.identity.get_ref()) and identity.run_id==f.run and b.save_path==f.path and b.account_name==f.account and b.session._profile.get("profile_id")==f.profile and b.session._profile.get("character_id")==f.character and connection==f.connection and is_same(b._fee_bindings.get(connection),f.binding)
func _doctor_capture(b)->Dictionary:
 if _doctor_scope.is_empty():return {}
 return {"scope":_doctor_scope,"transition":transition_frame(b)}
func _doctor_return(b,f:Dictionary)->bool:
 return f.is_empty() or (is_same(_doctor_scope,f.scope) and _doctor_live(b) and transition_current(b,f.transition))

# Private lifetime for the dormant ordinary Saton route; never a fee capability.
var _saton_scope:Dictionary={}
func _saton_start_frame(b,command:Dictionary)->Dictionary:
 var peer:Variant=command.get("_quest_connection")
 if not peer is int or peer==-1 or not b._fee_bindings.get(peer) is RefCounted:return {}
 return {"transition":transition_frame(b),"peer":peer,"binding":b._fee_bindings.get(peer),"account":b.account_name,"profile":b.session._profile.get("profile_id"),"character":b.session._profile.get("character_id")}
func _saton_start_current(b,f:Dictionary)->bool:
 return not f.is_empty() and b._saton_request_enabled() and transition_current(b,f.transition) and b.account_name==f.account and b.session._profile.get("profile_id")==f.profile and b.session._profile.get("character_id")==f.character and is_same(b._fee_bindings.get(f.peer),f.binding)
func _saton_live(b)->bool:
 if _saton_scope.is_empty() or b.session==null:return false
 var f:Dictionary=_saton_scope
 return b._saton_request_enabled() and is_same(b.quest_auto,self) and is_same(b.session,f.session.get_ref()) and is_same(identity,f.identity.get_ref()) and identity.run_id==f.run and b.save_path==f.path and b.account_name==f.account and b.session._profile.get("profile_id")==f.profile and b.session._profile.get("character_id")==f.character and connection==f.connection and is_same(b._fee_bindings.get(connection),f.binding)
func _saton_capture(b)->Dictionary:
 if _saton_scope.is_empty():return {}
 return {"scope":_saton_scope,"transition":transition_frame(b)}
func _saton_return(b,f:Dictionary)->bool:
 return f.is_empty() or (is_same(_saton_scope,f.scope) and _saton_live(b) and transition_current(b,f.transition))


# Private lifetime for the dormant ordinary Munde route; never a fee capability.
var _munde_scope:Dictionary={}
func _munde_start_frame(b,command:Dictionary)->Dictionary:
 var peer:Variant=command.get("_quest_connection")
 if not peer is int or peer==-1 or not b._fee_bindings.get(peer) is RefCounted:return {}
 return {"transition":transition_frame(b),"peer":peer,"binding":b._fee_bindings.get(peer),"account":b.account_name,"profile":b.session._profile.get("profile_id"),"character":b.session._profile.get("character_id")}
func _munde_start_current(b,f:Dictionary)->bool:
 return not f.is_empty() and b._munde_request_enabled() and transition_current(b,f.transition) and b.account_name==f.account and b.session._profile.get("profile_id")==f.profile and b.session._profile.get("character_id")==f.character and is_same(b._fee_bindings.get(f.peer),f.binding)
func _munde_live(b)->bool:
 if _munde_scope.is_empty() or b.session==null:return false
 var f:Dictionary=_munde_scope
 return b._munde_request_enabled() and is_same(b.quest_auto,self) and is_same(b.session,f.session.get_ref()) and is_same(identity,f.identity.get_ref()) and identity.run_id==f.run and b.save_path==f.path and b.account_name==f.account and b.session._profile.get("profile_id")==f.profile and b.session._profile.get("character_id")==f.character and connection==f.connection and is_same(b._fee_bindings.get(connection),f.binding)
func _munde_capture(b)->Dictionary:
 if _munde_scope.is_empty():return {}
 return {"scope":_munde_scope,"transition":transition_frame(b)}
func _munde_return(b,f:Dictionary)->bool:
 return f.is_empty() or (is_same(_munde_scope,f.scope) and _munde_live(b) and transition_current(b,f.transition))



func delivery_supports(id:int)->bool:
 return Registry.supports(id)
func transition_frame(b)->Dictionary:
 return {"session":b.session,"path":b.save_path,"automation":b.automation,"auto_token":b.automation.start_lifetime,"identity_object":identity,"identity":identity.checkpoint(),"connection":connection,"client":client}
func transition_current(b,frame:Dictionary)->bool:
 return is_same(b.quest_auto,self) and is_same(b.session,frame.session) and b.save_path==frame.path and is_same(b.automation,frame.automation) and is_same(b.automation.start_lifetime,frame.auto_token) and is_same(identity,frame.identity_object) and identity.checkpoint()==frame.identity and connection==frame.connection and client==frame.client
func handoff(b,reason:String)->void:
 var call:Dictionary=transition_frame(b)
 call.identity.revision+=1
 stop(b,reason)
 if not transition_current(b,call):return
 phase="manual"
 pause_reason=reason
 b.publish()
func fail(b,reason:String)->void:
 if strict_walk:handoff(b,reason)
 else:stop(b,reason)
func strict_select(b,selected_id:int=-1,allow_clean:Variant=null)->Dictionary:
 var id:int=quest_id if selected_id<0 else selected_id
 if id==6 and b._doctor_request_enabled():return Registry.doctor_request(b,id)
 if id==10 and b._saton_request_enabled():return Registry.saton_request(b,id)
 if id==8 and b._munde_request_enabled():return Registry.munde_request(b,id)
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
 # Source routes always use A; stored global preferences do not revoke pages.
 if quest_id==2:return
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
 var loot_battle:Dictionary=b.quest_loot.capture_battle_cancel(b)
 var loot_close:Dictionary=b.quest_loot.capture_idle_close(b)
 if not loot_close.is_empty() and not b.quest_loot.prepare_idle_revocation(b,loot_close,"detach"):return
 if not loot_battle.is_empty() and not b.quest_loot.prepare_battle_revocation(b,loot_battle,"detach"):return
 detached=true
 if source_frame!=null:source_frame.detach()
 connection=-1
 client=""
 clear_motion()
 if not loot_close.is_empty():
  # This exact idle obligation is revoked before the close can publish/reenter.
  # Keep its identity/token intact for a failed save's frozen repair path.
  if not b.quest_loot.idle_close_owner(b,loot_close):return
  running=false
  owns_battle=false
  phase="stopped"
  b.quest_loot.finish_idle_close(b,loot_close)
  if not b.quest_loot.idle_close_context(b,loot_close):return
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
 # A revoked loot receipt owns only its existing battle, never a reconnect.
 # Consume observations without rebinding or falling through to map_changed.
 if b.quest_loot.cancelled_battle_owner(b,b.quest_loot.cancelled_battle):return true
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
 var transition_identity:Dictionary=identity.checkpoint()
 var transition_connection:int=connection
 var fee_battle_scope:Dictionary=b._fee_execution_scope()
 # Receipt-clearing battle profiles must follow the current authority cell.
 b.emit_event({"type":"auto_status","status":b.automation.status()})
 if not running or detached or connection!=transition_connection or identity.checkpoint()!=transition_identity:return
 if not b._fee_execution_current(fee_battle_scope):return
 b.automation.start({"kind":"battle","settings":{"preset":"attack","compact":true}})
 if not fee_battle_scope.is_empty():
  if not b.automation.take_fee_battle_start(fee_battle_scope):return
  # start_training owns the legitimate token replacement; all other refs stay exact.
  if not running or detached or identity.checkpoint()!=transition_identity or connection!=transition_connection:return
  if not is_same(b.session,fee_battle_scope.session) or not is_same(b.automation,fee_battle_scope.automation) or not is_same(b.battle,fee_battle_scope.battle) or not is_same(b._fee_bindings.get(connection),fee_battle_scope.binding):return
 b.automation.compact_active=true
 message="沿途遇敌：原自动战斗中，结算后继续。"
 b.publish()

func snapshot(b=null) -> Dictionary:
 var result:Dictionary={"running":running,"quest_id":quest_id,"phase":phase,"message":message,"target":target.duplicate(true),"client":client,"detached":detached,"strict_walk":strict_walk,"pause_reason":pause_reason}
 result.merge(identity.snapshot())
 result.settings=Settings.effective(b.session.automation_settings() if b!=null else {})
 result.effective_mode=execution_mode if running else result.settings.mode
 result.available_modes=["A","B","C"]
 result.mode_notice="B/C只用于已审核的公开走廊；保护段和未知公开段仍沿A逐格。" if result.settings.mode!="A" else ""
 if running and restored and result.settings.mode!="A":result.mode_notice="重启恢复先沿A原路推进；重新启动任务后应用所选模式。"
 if running and quest_id==2:
  result.available_modes=["A"]
  result.effective_mode="A"
  result.mode_notice="金布伊自动任务全程按A原路；B/C偏好保留供其他已开放任务使用。"
 result.source_entry=source_entry(b) if b!=null else {"job_id":2,"enabled":false,"can_start":false,"reason":"服务未连接。","effective_mode":"A"}
 result.can_continue=running and phase=="waiting_boss" and boss_ready
 result.budget=b.quest_loot.projection(b) if b!=null else {}
 result.motion=motion.duplicate(true)
 if b!=null:
  var departure:Dictionary=b._fee_departure_projection()
  if not departure.is_empty():result.fee_departure=departure
 return result
func stop(b, reason:String="已停止自动任务。", persist:bool=true, captured_idle_close:Dictionary={}, retry_fee_lifecycle:bool=false) -> Dictionary:
 if b==null or not is_same(b.quest_auto,self):return {"ok":false,"stage":"stop_owner_stale","stopped_in_memory":false,"lifecycle":"unknown"}
 if b.session==null:return {"ok":false,"stage":"session_missing","stopped_in_memory":false,"lifecycle":"unknown"}
 # Only a persistent stop with a present fee lifecycle needs the cross-callback
 # operation claim. Legacy runs and persist=false shutdown/suspend keep their
 # prior cancellation path and cannot be blocked by fee-seam claims.
 var has_fee_record:bool=b.session._profile.has("quest_auto_fee_lifecycle")
 var needs_fee_claim:bool=persist and has_fee_record and (running or retry_fee_lifecycle or b._quest_auto_stop_operation_call!=null)
 var departure_entry:Dictionary=b._fee_departure_call
 var operation:Dictionary={}
 var fee_lifecycle_requested:bool=needs_fee_claim
 if needs_fee_claim:
  operation=b._begin_quest_auto_stop_operation(self)
  if operation.is_empty():return {"ok":false,"stage":"stop_operation_busy","stopped_in_memory":false,"lifecycle":"unknown"}
 if not departure_entry.is_empty() and not b._fee_departure_current(departure_entry):
  if not operation.is_empty():b._end_quest_auto_stop_operation(operation)
  return {"ok":false,"stage":"departure_superseded","stopped_in_memory":false,"lifecycle":"unknown"}
 var was_running:bool=running
 var stopped_identity:Dictionary=identity.checkpoint()
 var result_holder:Dictionary={"result":{"ok":false,"stage":"stop_aborted_before_state_change","stopped_in_memory":false,"lifecycle":"unknown"}}
 _stop_body(b,reason,persist,captured_idle_close,operation,stopped_identity,was_running,retry_fee_lifecycle,fee_lifecycle_requested,result_holder)
 var result_value:Variant=result_holder.get("result",null)
 var result:Dictionary=result_value.duplicate(true) if result_value is Dictionary else {"ok":false,"stage":"stop_result_missing","stopped_in_memory":false,"lifecycle":"unknown"}
 if not operation.is_empty():b._end_quest_auto_stop_operation(operation)
 return result

func _stop_body(b, reason:String="已停止自动任务。", persist:bool=true, captured_idle_close:Dictionary={}, operation:Dictionary={}, stopped_identity:Dictionary={}, was_running:bool=false, retry_fee_lifecycle:bool=false, fee_lifecycle_requested:bool=false, result_holder:Dictionary={}) -> void:
 if not is_same(b.quest_auto,self) or b.session==null or (not operation.is_empty() and not b._quest_auto_stop_operation_current(operation)):
  result_holder["result"]={"ok":false,"stage":"stop_owner_stale_before_mutation","stopped_in_memory":false,"lifecycle":"unknown"}
  return
 if persist and b.session._profile.has("quest_auto_fee_lifecycle") and (running or retry_fee_lifecycle or b._quest_auto_stop_operation_call!=null) and operation.is_empty():
  result_holder["result"]={"ok":false,"stage":"fee_stop_claim_missing","stopped_in_memory":false,"lifecycle":"unknown"}
  return
 var call:Dictionary=transition_frame(b)
 call.identity.revision+=1
 var loot_battle:Dictionary=b.quest_loot.capture_battle_cancel(b)
 var loot_close:Dictionary=captured_idle_close if not captured_idle_close.is_empty() else b.quest_loot.capture_idle_close(b)
 if not loot_close.is_empty() and not b.quest_loot.idle_close_owner(b,loot_close):return
 # Repeated stop while repair is pending must not rotate its retry identity.
 if not running and (not loot_close.is_empty() or not loot_battle.is_empty()):return
 if not persist and not loot_battle.is_empty():shutdown_intent=resume_state()
 if not loot_close.is_empty():
  # Preserve intent before invalidation; close must precede resume location I/O.
  if not persist:shutdown_intent=resume_state()
  loot_close.keep_resume_after_close=persist or bool(loot_close.get("keep_resume_after_close",false))
 var old_source=source_frame
 if old_source!=null:old_source.cancel()
 if fee_lifecycle_requested and b.session==null:
  result_holder["result"]={"ok":false,"applicable":true,"stage":"session_missing_after_claim_callback","lifecycle":"unknown","stopped_in_memory":false}
  return
 if not loot_close.is_empty() and not b.quest_loot.prepare_idle_revocation(b,loot_close,"stop"):return
 if not loot_battle.is_empty() and not b.quest_loot.prepare_battle_revocation(b,loot_battle,"stop"):return
 source_frame=null
 var fee_before_invalidation:Dictionary=identity.checkpoint()
 identity.invalidate()
 b._fee_departure_after_invalidate(self,fee_before_invalidation)
 result_holder["result"]={"ok":false,"stage":"memory_stop_in_progress","stopped_in_memory":false,"identity_invalidated":true,"lifecycle":"unknown"}
 waiting_saved=false
 boss_ready=false
 var had_shutdown_intent:=not shutdown_intent.is_empty()
 if persist:shutdown_intent={}
 if not running:
  var idle_fee_lifecycle:Dictionary={"ok":true,"applicable":false,"lifecycle":"legacy","stage":"legacy_noop","stopped_in_memory":false}
  if fee_lifecycle_requested:
   idle_fee_lifecycle=b._close_and_retire_stopped_fee_run(stopped_identity,operation)
  if not idle_fee_lifecycle.get("applicable",false):idle_fee_lifecycle["stopped_in_memory"]=false
  var idle_ok_value:Variant=idle_fee_lifecycle.get("ok",null)
  var idle_ok:bool=false
  if idle_ok_value is bool:idle_ok=idle_ok_value
  if fee_lifecycle_requested and not idle_ok:
   message=reason+"（已停止；持久收尾仍未完成："+str(idle_fee_lifecycle.get("stage","unknown"))+"）"
   result_holder["result"]=idle_fee_lifecycle.duplicate(true)
   if b.session!=null and transition_current(b,call):b.publish()
   return
  if persist and had_shutdown_intent:b.keep_resume_file()
  result_holder["result"]=idle_fee_lifecycle.duplicate(true)
  return
 if not persist and loot_close.is_empty() and loot_battle.is_empty():shutdown_intent=resume_state()
 # A captured idle obligation proves no battle/pending/receipt is owned.
 # Do not enter automation.stop (which can publish midway) for this idle run.
 if loot_close.is_empty() and loot_battle.is_empty() and owns_battle and b.automation.running:b.automation.stop(reason)
 if not transition_current(b,call):return
 if not loot_close.is_empty() and not b.quest_loot.idle_close_owner(b,loot_close):return
 owns_battle=false
 path.clear();herb_path.clear()
 navigation.clear()
 clear_motion()
 running=false
 var in_progress_value:Variant=result_holder.get("result",{})
 if in_progress_value is Dictionary:
  var progress_result:Dictionary=in_progress_value.duplicate(true)
  progress_result["stopped_in_memory"]=true
  result_holder["result"]=progress_result
 phase="stopped"
 message=reason
 if old_source==null or old_source.owns_pending(str(b.original_quests.pending.get("token",""))):b.original_quests.pending={}
 if not loot_close.is_empty():
  b.quest_loot.finish_idle_close(b,loot_close)
  if not b.quest_loot.idle_close_context(b,loot_close):return
 var fee_lifecycle:Dictionary={"ok":true,"applicable":false,"lifecycle":"legacy","stage":"legacy_stop","stopped_in_memory":true}
 if fee_lifecycle_requested and was_running:
  fee_lifecycle=b._close_and_retire_stopped_fee_run(stopped_identity,operation)
 var run_ok_value:Variant=fee_lifecycle.get("ok",null)
 var run_ok:bool=false
 if run_ok_value is bool:run_ok=run_ok_value
 if fee_lifecycle_requested and not run_ok:
  # Do not overwrite a sidecar when a matched journal could not be closed or
  # an unattributed hunt/battle file was deliberately preserved.
  message=reason+"（任务已停止；持久收尾未完成："+str(fee_lifecycle.get("stage","unknown"))+"）"
  result_holder["result"]=fee_lifecycle.duplicate(true)
  if b.session==null or not transition_current(b,call):return
  if not loot_close.is_empty() and not b.quest_loot.idle_close_context(b,loot_close):return
  b.publish()
  return
 if persist and loot_close.is_empty():b.keep_resume_file()
 if not transition_current(b,call):return
 if not loot_close.is_empty() and not b.quest_loot.idle_close_context(b,loot_close):return
 b.publish()
 fee_lifecycle["stopped_in_memory"]=true
 result_holder["result"]=fee_lifecycle.duplicate(true)
func resume_state() -> Dictionary:
 if not running:return shutdown_intent.duplicate(true)
 return {"version":3,"quest_id":quest_id,"clean_authorized":clean_authorized,"strict_walk":true,"identity":identity.checkpoint(),"phase":phase}
func suspend(b) -> void:
 var loot_battle:Dictionary=b.quest_loot.capture_battle_cancel(b)
 if not loot_battle.is_empty():
  stop(b,"服务器已停止。",false)
  if not b.quest_loot.cancelled_battle_owner(b,loot_battle):return
  b.keep_resume_file()
  return
 # Capture before resume-clock/publication callbacks, as well as identity loss.
 var loot_close:Dictionary=b.quest_loot.capture_idle_close(b)
 if not loot_close.is_empty() and not b.quest_loot.idle_close_owner(b,loot_close):return
 if not loot_close.is_empty():
  loot_close.keep_resume_after_close=true
  stop(b,"服务器已停止。",false,loot_close)
  return
 # Non-loot behavior is unchanged; idle loot commits before resume location I/O.
 # Transport shutdown must checkpoint before clearing the running intent.
 if running:
  shutdown_intent=resume_state()
  b.keep_resume_file()
 if not loot_close.is_empty() and not b.quest_loot.idle_close_owner(b,loot_close):return
 stop(b,"服务器已停止。",false,loot_close)
func load_resume(b,state:Dictionary) -> void:
 if b.quest_loot.State.resume_is_loot(state):return
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
func _supports_automatic_start(job_id:int,event_id:int)->bool:
 return Policy.supports(job_id,event_id)
func prepare_start(b,command:Dictionary) -> Dictionary:
 if b._quest_auto_stop_operation_call!=null:return b._reject("自动任务正在停止，请稍后重试。")
 if running:return b._reject("自动任务已在运行。")
 var id=command.get("quest_id",-1)
 if not (id is int or id is float) or float(id)!=floor(float(id)):return b._reject("无效任务编号。")
 var quest:=row(b,int(id))
 if quest.is_empty() or not (_supports_automatic_start(int(id),int(quest.event)) or (b._doctor_request_enabled() and int(id)==6 and int(quest.event)==15) or (b._saton_request_enabled() and int(id)==10 and int(quest.event)==13) or (b._munde_request_enabled() and int(id)==8 and int(quest.event)==9)) or not int(quest.event) in b.quest_catalog.enabled_events:return b._reject("此任务尚未开放自动推进。")
 if b._doctor_request_enabled() and int(id)==6:
  var peer:Variant=command.get("_quest_connection")
  if not peer is int or peer==-1 or not b._fee_bindings.get(peer) is RefCounted:return b._reject("博士首请求需要当前可信连接。")
 if b._saton_request_enabled() and int(id)==10:
  var peer:Variant=command.get("_quest_connection")
  if not peer is int or peer==-1 or not b._fee_bindings.get(peer) is RefCounted:return b._reject("萨顿首请求需要当前可信连接。")
 if b._munde_request_enabled() and int(id)==8:
  var peer:Variant=command.get("_quest_connection")
  if not peer is int or peer==-1 or not b._fee_bindings.get(peer) is RefCounted:return b._reject("梦德首请求需要当前可信连接。")
 if b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active() or not b.original_quests.pending.is_empty():return b._reject("当前正忙。")
 if b.quest_visit_guard.is_valid():
  var reason:=str(b.quest_visit_guard.call())
  if not reason.is_empty():return b._reject(reason)
 if str(command.get("client","")).is_empty():return b._reject("缺少发起设备。")
 if int(id)==2:
  if not command.get("_quest_connection") is int or int(command._quest_connection)==-1:return b._reject("缺少可信发起连接。")
  var admitted:Dictionary=source_admission(b)
  if not admitted.ok and not b._fee_lobby_ticket.propose(b):return b._reject(str(admitted.reason))
  return {"ok":true,"source":true,"quest_id":2,"client":str(command.client),"connection":int(command._quest_connection)}
 if int(quest.event)==4 and int(b.session._profile.player.level)<30:return b._reject("原成人仪式入口需要等级30；自动任务不能绕过等级门。")
 var first:Dictionary=strict_select(b,int(id),bool(quest.get("can_restart",false)))
 if first.get("status","")!="step" or not safe_step(first.get("step",{}),int(id),bool(quest.get("can_restart",false))):return b._reject(str(first.get("reason",quest.get("blocked_reason","")))+" 当前没有可自动执行的已审核原任务步骤。")
 return {"ok":true,"source":false,"quest_id":int(id),"client":str(command.client),"connection":int(command.get("_quest_connection",-1)),"clean":bool(quest.get("can_restart",false)),"first":first.step.duplicate(true)}
func start(b,command:Dictionary) -> Dictionary:
 if b._fee_start_intent_enabled() and b._fee_start_intent.classified(command):return b._reject("收费启动必须经过可信后端入口。")
 var doctor_admission:Dictionary={}
 var saton_admission:Dictionary={}
 var munde_admission:Dictionary={}
 var doctor_id:Variant=command.get("quest_id")
 var saton_id:Variant=command.get("quest_id")
 var munde_id:Variant=command.get("quest_id")
 var doctor_start:bool=b._doctor_request_enabled() and (doctor_id is int or doctor_id is float) and doctor_id==6
 var saton_start:bool=b._saton_request_enabled() and (saton_id is int or saton_id is float) and saton_id==10
 var munde_start:bool=b._munde_request_enabled() and (munde_id is int or munde_id is float) and munde_id==8
 if doctor_start:
  doctor_admission=_doctor_start_frame(b,command)
  if doctor_admission.is_empty():return b._reject("博士首请求需要当前可信连接。")
 if saton_start:
  saton_admission=_saton_start_frame(b,command)
  if saton_admission.is_empty():return b._reject("萨顿首请求需要当前可信连接。")
 if munde_start:
  munde_admission=_munde_start_frame(b,command)
  if munde_admission.is_empty():return b._reject("梦德首请求需要当前可信连接。")
 var prepared:Dictionary=prepare_start(b,command)
 if not prepared.get("ok",false):return prepared
 if doctor_start and not _doctor_start_current(b,doctor_admission):return b._reject("博士首请求发起身份已改变。")
 if saton_start and not _saton_start_current(b,saton_admission):return b._reject("萨顿首请求发起身份已改变。")
 if munde_start and not _munde_start_current(b,munde_admission):return b._reject("梦德首请求发起身份已改变。")
 _doctor_scope={}
 _saton_scope={}
 _munde_scope={}
 if prepared.source:
  _install_source_start(prepared.client,prepared.connection)
  b.publish()
  return {"ok":true}
 quest_id=prepared.quest_id
 strict_walk=true
 clear_motion()
 identity.begin()
 pause_reason=""
 navigation.clear()
 clean_authorized=prepared.clean
 step=prepared.first.duplicate(true)
 shutdown_intent={}
 restored=false
 detached=false
 client=prepared.client
 connection=prepared.connection
 running=true
 if quest_id==6 and b._doctor_request_enabled():
  _doctor_scope={"session":weakref(b.session),"identity":weakref(identity),"run":identity.run_id,"path":b.save_path,"account":b.account_name,"profile":b.session._profile.get("profile_id"),"character":b.session._profile.get("character_id"),"connection":connection,"binding":b._fee_bindings.get(connection)}
 if quest_id==10 and b._saton_request_enabled():
  _saton_scope={"session":weakref(b.session),"identity":weakref(identity),"run":identity.run_id,"path":b.save_path,"account":b.account_name,"profile":b.session._profile.get("profile_id"),"character":b.session._profile.get("character_id"),"connection":connection,"binding":b._fee_bindings.get(connection)}
 if quest_id==8 and b._munde_request_enabled():
  _munde_scope={"session":weakref(b.session),"identity":weakref(identity),"run":identity.run_id,"path":b.save_path,"account":b.account_name,"profile":b.session._profile.get("profile_id"),"character":b.session._profile.get("character_id"),"connection":connection,"binding":b._fee_bindings.get(connection)}
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
 if not _doctor_scope.is_empty() and not b._doctor_request_call.is_empty():return
 if not _saton_scope.is_empty() and not b._saton_request_call.is_empty():return
 if not _munde_scope.is_empty() and not b._munde_request_call.is_empty():return
 if not _doctor_scope.is_empty() and not _doctor_live(b):
  # Abandon only this captured run, with no save/publish or pending mutation.
  if is_same(identity,_doctor_scope.identity.get_ref()) and identity.run_id==_doctor_scope.run:running=false;internal=false
  return
 if not _saton_scope.is_empty() and not _saton_live(b):
  # Abandon only this captured run, with no save/publish or pending mutation.
  if is_same(identity,_saton_scope.identity.get_ref()) and identity.run_id==_saton_scope.run:running=false;internal=false
  return
 if not _munde_scope.is_empty() and not _munde_live(b):
  # Abandon only this captured run, with no save/publish or pending mutation.
  if is_same(identity,_munde_scope.identity.get_ref()) and identity.run_id==_munde_scope.run:running=false;internal=false
  return
 # A cancelled receipt may finish only its already-running original battle.
 if b.quest_loot.cancelled_battle_owner(b,b.quest_loot.cancelled_battle):return
 if internal and step.get("id")==b.quest_loot.State.STEP:
  b.quest_loot.tick_internal(b)
  return
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
  # A client must leave its battle gate before the first post-win receipt.
  var transition_connection:int=connection
  b.publish()
  if not running or detached or connection!=transition_connection or identity.checkpoint()!=saved_identity:return
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
 var doctor_tick:Dictionary=_doctor_scope
 var saton_tick:Dictionary=_saton_scope
 var munde_tick:Dictionary=_munde_scope
 internal=true
 advance(b)
 if not doctor_tick.is_empty() and (not is_same(_doctor_scope,doctor_tick) or not _doctor_live(b) or not b._doctor_request_call.is_empty()):return
 if not saton_tick.is_empty() and (not is_same(_saton_scope,saton_tick) or not _saton_live(b) or not b._saton_request_call.is_empty()):return
 if not munde_tick.is_empty() and (not is_same(_munde_scope,munde_tick) or not _munde_live(b) or not b._munde_request_call.is_empty()):return
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
 if not _doctor_scope.is_empty() and not _doctor_live(b):return
 if not _saton_scope.is_empty() and not _saton_live(b):return
 if not _munde_scope.is_empty() and not _munde_live(b):return
 if phase=="travel":
  var doctor_selection:Dictionary=_doctor_capture(b)
  var saton_selection:Dictionary=_saton_capture(b)
  var munde_selection:Dictionary=_munde_capture(b)
  var selection:=strict_select(b)
  if not _doctor_return(b,doctor_selection):return
  if not _saton_return(b,saton_selection):return
  if not _munde_return(b,munde_selection):return
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
   var doctor_call:Dictionary=_doctor_capture(b)
   var saton_call:Dictionary=_saton_capture(b)
   var munde_call:Dictionary=_munde_capture(b)
   var doctor_private:Dictionary=b._begin_doctor_request_call(self) if not _doctor_scope.is_empty() else {}
   var saton_private:Dictionary=b._begin_saton_request_call(self) if not _saton_scope.is_empty() else {}
   var munde_private:Dictionary=b._begin_munde_request_call(self) if not _munde_scope.is_empty() else {}
   if not _doctor_scope.is_empty() and doctor_private.is_empty():return
   if not _saton_scope.is_empty() and saton_private.is_empty():return
   if not _munde_scope.is_empty() and munde_private.is_empty():return
   var reply:Dictionary=b.original_quests.talk(b,str(npc.id))
   var doctor_private_live:bool=b._doctor_request_call_live(doctor_private)
   var saton_private_live:bool=b._saton_request_call_live(saton_private)
   var munde_private_live:bool=b._munde_request_call_live(munde_private)
   b._end_doctor_request_call(doctor_private)
   b._end_saton_request_call(saton_private)
   b._end_munde_request_call(munde_private)
   if not doctor_private_live:return
   if not saton_private_live:return
   if not munde_private_live:return
   if not _doctor_return(b,doctor_call):return
   if not _saton_return(b,saton_call):return
   if not _munde_return(b,munde_call):return
   if not reply.get("ok",false):handoff(b,str(reply.get("reason","原对话失败。")));return
   dialogue_choices=step.get("auto_choices",["ok"] if str(step.source.type)=="MESSAGE" else ["yes","ok"]).duplicate()
   phase="strict_dialogue"
   strict_dialogue_reply(b,reply)
   return
  execution_mode="A" if not _saton_scope.is_empty() or not _munde_scope.is_empty() else selected_mode(b)
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
  if not _doctor_scope.is_empty() and (point.has("gate") or (point.has("portal") and (point.portal.get("requires_travel_pass",false) or preload("res://scripts/passage_rules.gd").requires_permit(map_id,int(point.get("map_id",-1)))))):
   handoff(b,"博士首请求仅允许审核的无收费原路线。");return
  if not _saton_scope.is_empty() and (point.has("gate") or (point.has("portal") and (point.portal.get("disabled",false) or not str(point.portal.get("gate_source","")).is_empty() or point.portal.get("requires_travel_pass",false) or preload("res://scripts/passage_rules.gd").requires_permit(map_id,int(point.get("map_id",-1)))))):
   handoff(b,"萨顿首请求仅允许审核的无收费原路线。");return
  if not _munde_scope.is_empty() and (point.has("gate") or (point.has("portal") and (point.portal.get("disabled",false) or not str(point.portal.get("gate_source","")).is_empty() or point.portal.get("requires_travel_pass",false) or preload("res://scripts/passage_rules.gd").requires_permit(map_id,int(point.get("map_id",-1)))))):
   handoff(b,"梦德首请求仅允许审核的无收费原路线。");return
  if point.has("gate"):
   advance_permit_gate(b,point)
   return
  if point.is_empty() or not navigation.validate(b,point):handoff(b,"没有可连续步行的原路线；请手动处理原门或当前位置后重新启动。");return
  var changed:bool=int(point.map_id)!=map_id
  if point.has("portal"):
   var doctor_passage:Dictionary=_doctor_capture(b)
   var saton_passage:Dictionary=_saton_capture(b)
   var munde_passage:Dictionary=_munde_capture(b)
   var passage:Dictionary=b._cmd_check_passage({"from_map":map_id,"to_map":int(point.map_id)})
   if not _doctor_return(b,doctor_passage):return
   if not _saton_return(b,saton_passage):return
   if not _munde_return(b,munde_passage):return
   if not passage.get("ok",false):handoff(b,str(passage.get("reason","原入口拒绝通行。")));return
  var doctor_move:Dictionary=_doctor_capture(b)
  var saton_move:Dictionary=_saton_capture(b)
  var munde_move:Dictionary=_munde_capture(b)
  b.automation.position_changed(int(point.map_id),Vector2i(int(point.cell[0]),int(point.cell[1])),changed,"walk")
  if not _doctor_return(b,doctor_move):return
  if not _saton_return(b,saton_move):return
  if not _munde_return(b,munde_move):return
  if not b.quest_arrival.has_arrival(b,int(point.map_id),b.automation.position_cell):handoff(b,"原路线资格已变化，停止推进。");return
  target={"map_id":int(point.map_id),"cell":point.cell.duplicate()}
  if changed:
   navigation.clear()
   phase="travel" if restored else "landing"
   waited=0.0
  var move_identity:Dictionary=identity.checkpoint()
  emit_position(b,target,{"map_id":map_id,"cell":[origin.x,origin.y]},changed and not restored)
  if not _doctor_return(b,doctor_move):return
  if not _saton_return(b,saton_move):return
  if not _munde_return(b,munde_move):return
  if not running or identity.checkpoint()!=move_identity:return
  if not changed:
   var encounter:Dictionary=b._cmd_field_step({"map_id":map_id,"cell":point.cell.duplicate(),"encounter":true})
   if not _doctor_return(b,doctor_move):return
   if not _saton_return(b,saton_move):return
   if not _munde_return(b,munde_move):return
   if encounter.get("battle",false):start_battle(b);return
  message="沿原路线步行前往"+str(npc.get("name","任务人物"))+"；沿途普通遇敌自动战斗后继续。"
  b.publish()
  return
 if phase=="strict_dialogue":
  var pending:Dictionary=b.original_quests.pending
  if pending.get("branch",{})!=step.source.branch_data or dialogue_choices.is_empty():handoff(b,"原对话已变化，请手动处理。");return
  var before_map:int=b.automation.position_map
  var before_cell:Vector2i=b.automation.position_cell
  var doctor_call:Dictionary=_doctor_capture(b)
  var saton_call:Dictionary=_saton_capture(b)
  var munde_call:Dictionary=_munde_capture(b)
  var doctor_private:Dictionary=b._begin_doctor_request_call(self) if not _doctor_scope.is_empty() else {}
  var saton_private:Dictionary=b._begin_saton_request_call(self) if not _saton_scope.is_empty() else {}
  var munde_private:Dictionary=b._begin_munde_request_call(self) if not _munde_scope.is_empty() else {}
  if not _doctor_scope.is_empty() and doctor_private.is_empty():return
  if not _saton_scope.is_empty() and saton_private.is_empty():return
  if not _munde_scope.is_empty() and munde_private.is_empty():return
  var reply:Dictionary=b.original_quests.choose(b,str(pending.get("token","")),str(dialogue_choices.pop_front()))
  var doctor_private_live:bool=b._doctor_request_call_live(doctor_private)
  var saton_private_live:bool=b._saton_request_call_live(saton_private)
  var munde_private_live:bool=b._munde_request_call_live(munde_private)
  b._end_doctor_request_call(doctor_private)
  b._end_saton_request_call(saton_private)
  b._end_munde_request_call(munde_private)
  if not doctor_private_live:return
  if not saton_private_live:return
  if not munde_private_live:return
  if not _doctor_return(b,doctor_call):return
  if not _saton_return(b,saton_call):return
  if not _munde_return(b,munde_call):return
  if not reply.get("ok",false):handoff(b,str(reply.get("reason","原交易失败。")));return
  strict_dialogue_reply(b,reply)
  if not _doctor_return(b,doctor_call):return
  if not _saton_return(b,saton_call):return
  if not _munde_return(b,munde_call):return
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

## Read-only eligibility, never a reusable permission or a source-page export.
func source_admission(b)->Dictionary:
 if not Source.job_enabled(b,2):return {"ok":false,"reason":"此任务尚未开放自动推进。"}
 if running or b.battle_open or not b.session._pending.is_empty() or not b.original_quests.pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active():return {"ok":false,"reason":"当前无法开始原源任务。"}
 if b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():return {"ok":false,"reason":"请先退出团队。"}
 if Rules.flag(b.session._profile,"ended",44):return {"ok":false,"reason":"已领取金布伊，任务已完成。"}
 var selected:Dictionary=SourcePlan.select(b,2)
 if selected.get("status")!="step":return {"ok":false,"reason":str(selected.get("reason","原任务不需要继续。"))}
 var checked:Dictionary=Source.validate_step(b,2,selected.step)
 return {"ok":bool(checked.ok),"reason":str(checked.get("reason",""))}
func source_entry(b)->Dictionary:
 var admission:Dictionary=source_admission(b)
 return {"job_id":2,"enabled":Source.job_enabled(b,2),"can_start":bool(admission.ok),"reason":str(admission.reason),"effective_mode":"A"}
## Public start dispatch and internal callers share the same original guards.
func begin_source_run(b,device:String,peer:int)->Dictionary:
 if b._fee_start_intent_enabled():return b._reject("收费启动必须经过可信后端入口。")
 if device.is_empty() or peer==-1:return b._reject("缺少可信发起连接。")
 var checked:Dictionary=source_admission(b)
 if not checked.ok:return b._reject(str(checked.reason))
 _install_source_start(device,peer)
 b.publish()
 return {"ok":true}
func _install_source_start(device:String,peer:int,staged:RefCounted=null)->void:
 _doctor_scope={}
 _saton_scope={}
 _munde_scope={}
 quest_id=2;client=device;connection=peer;running=true;strict_walk=true
 restored=false;detached=false;owns_battle=false;shutdown_intent={}
 source_frame=null;source_after_landing="travel"
 if staged==null:identity.begin()
 else:identity=staged
 step={};target={};path.clear();herb_path.clear();navigation.clear();clear_motion()
 phase="travel";elapsed=0.0;waited=0.0;execution_mode="A";pause_reason=""
 message="沿审核原路前往原道场人物。"
func install_fee_start(b,prepared:Dictionary,staged:RefCounted)->void:
 if not b._fee_start_intent.install_permitted(b,self,prepared,staged):return
 _install_source_start(prepared.client,prepared.connection,staged)
 b._fee_start_intent.mark_installed(b,self,staged)
func advance_source(b)->void:
 if b._fee_lobby_ticket.advance(b):return
 if phase=="source_dialogue":
  var entry_reply:Dictionary=b._fee_lobby_ticket_entry.begin_reply(b,self)
  var response:Dictionary=source_next(b)
  if b._fee_lobby_ticket_entry.finish_reply(b,self,entry_reply):source_reply(b,response)
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
 if identity.step_id!=str(proposal.id):
  var previous_identity:Dictionary=identity.checkpoint()
  var previous_connection:int=connection
  # Clearing an old receipt must not follow a stale automation position.
  b.emit_event({"type":"auto_status","status":b.automation.status()})
  if not running or detached or connection!=previous_connection or identity.checkpoint()!=previous_identity:return
  clear_motion();navigation.clear()
 step=proposal.duplicate(true);identity.select_step(str(step.id))
 execution_mode="A"
 if step.action=="walk_portal":
  if not b.original_quests.pending.is_empty():handoff(b,"原对话尚未结束。");return
  source_walk(b,navigation.next_portal(b,step.portal))
  return
 var npc:Dictionary=checked.npc
 var offset:Vector2i=b.automation.position_cell-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if b.automation.position_map==int(npc.map_id) and maxi(absi(offset.x),absi(offset.y))<=2:
  var entry_reply:Dictionary=b._fee_lobby_ticket_entry.begin_reply(b,self)
  var response:Dictionary=source_open(b,step)
  if b._fee_lobby_ticket_entry.finish_reply(b,self,entry_reply):source_reply(b,response)
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

## Exact, silent revocation only; does not close/settle or steal a writer claim.
func revoke_fee_execution(b,f:Dictionary,reason:String,require_guard:bool=true)->void:
 if not b._fee_departure_owner(f) or not is_same(self,f.runner) or identity.checkpoint()!=f.checkpoint:return
 if require_guard and not b._fee_departure_current(f):return
 if not is_same(b.automation,f.automation) or not is_same(b.automation.start_lifetime,f.auto_token) or not is_same(b.battle,f.battle):return
 if owns_battle:b.automation.revoke_fee_execution(f,reason)
 var old_source=source_frame
 if old_source!=null:old_source.cancel()
 if old_source!=null and old_source.owns_pending(str(b.original_quests.pending.get("token",""))):b.original_quests.pending={}
 source_frame=null
 identity.invalidate()
 f.checkpoint=identity.checkpoint()
 running=false;detached=true;restored=false;owns_battle=false
 connection=-1;client="";f.runner_connection=-1;f.client=""
 waiting_saved=false;boss_ready=false;shutdown_intent={}
 path.clear();herb_path.clear();navigation.clear();clear_motion()
 phase="stopped";message=reason+"（持久收尾需重新核验。）"

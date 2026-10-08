extends RefCounted
## Internal timer/candidate preparation with dormant battle settlement hooks.
## No public registration; only the sealed internal continuation driver is wired.
## Authoritative commit hooks must accept a candidate before accept_commit;
## Internal drivers use original transactions only; no proof or reward is invented.
const State=preload("res://server/quest_auto_loot_state.gd")
const Sources=preload("res://server/quest_auto_loot_sources.gd")
const Settings=preload("res://server/quest_auto_settings_rules.gd")
var clock:Callable=Time.get_ticks_msec
var key:=""
var binding:Dictionary={}
var span:Dictionary={}
var anchor_ms:=-1
var base_used_ms:=0
var last_ms:=-1
var blocked:=false
var frozen:=false
var frozen_ms:=-1
var storage_paused:=false
var lifetime:RefCounted=RefCounted.new()
var cached_sample:Dictionary={}
# P3 is a passive, per-span heartbeat. The wall clock below is only a
# once-per-second scheduler; budget time still comes exclusively from `clock`.
const HEARTBEAT_INTERVAL_MS:=1000
var heartbeat_wall_ms:=-1
var heartbeat_generation:=-1
var heartbeat_call:RefCounted=null
func now()->int:
 var value=clock.call()
 if not State.integer(value,0,State.MAX_MSEC):blocked=true;return -1
 var current:=int(value)
 if last_ms>=0 and current<last_ms:blocked=true;return -1
 last_ms=current
 return current
func start_after_commit(step_id:String,entry:Dictionary,run_identity:Dictionary)->bool:
 if anchor_ms>=0 or step_id!=State.STEP or not State.valid_entry(entry) or not entry.open_span or entry.recovery_blocked:return false
 if not State.exact(run_identity,["run_id","step_id","revision"]) or not State.opaque(run_identity.run_id) or run_identity.step_id!=step_id or not State.integer(run_identity.revision):return false
 var current:=now()
 if current<0:return false
 lifetime=RefCounted.new()
 key=step_id;binding=run_identity.duplicate(true)
 span={"budget_id":entry.budget_id,"generation":entry.generation,"issued_seq":entry.issued_seq}
 anchor_ms=current;base_used_ms=int(entry.used_ms);frozen=false;blocked=false;storage_paused=false
 heartbeat_wall_ms=-1;heartbeat_call=null
 cached_sample={"lifetime":lifetime,"span":span.duplicate(true),"used_ms":base_used_ms}
 progress_stamp={"lifetime":lifetime,"span":span.duplicate(true),"ms":current,"used_ms":base_used_ms}
 return true
func used_ms()->int:
 if anchor_ms<0 or blocked:return -1
 var current:int=frozen_ms if frozen else now()
 if current<anchor_ms or base_used_ms>State.MAX_MSEC-(current-anchor_ms):blocked=true;return -1
 return base_used_ms+current-anchor_ms
func sample_active()->bool:
 # Explicit scheduling/sample hook; NEVER called by snapshot/projection.
 var total:=used_ms()
 if total<0:return false
 cached_sample={"lifetime":lifetime,"span":span.duplicate(true),"used_ms":total}
 return true
func pause_idle()->bool:
 # Never call with a live step battle: disconnected battle time still accrues.
 if anchor_ms<0 or blocked:return false
 if frozen:return true
 frozen_ms=now();frozen=frozen_ms>=0
 return frozen
func pause_storage()->bool:
 # Final settlement sample. Synchronous disk I/O and repair wait are excluded.
 # Retrying the same original battle keeps this exact sample, never +=delta.
 if storage_paused:return frozen and not blocked
 if anchor_ms<0 or blocked:return false
 if not frozen:
  frozen_ms=now()
  if frozen_ms<0:return false
  frozen=true
 storage_paused=true
 return sample_active()
func pause_storage_for(expected_lifetime:RefCounted)->bool:
 # A returning old frame must not freeze a reused timer's new lifetime.
 if not is_same(lifetime,expected_lifetime):return false
 return pause_storage()
func same_span(ledger:Dictionary)->bool:
 if not State.valid(ledger) or not ledger.entries.has(key):return false
 var entry:Dictionary=ledger.entries[key]
 return span.get("budget_id")==entry.budget_id and span.get("generation")==entry.generation and span.get("issued_seq")==entry.issued_seq
func checkpoint(ledger:Dictionary,close:bool=false)->Dictionary:
 var used:=used_ms()
 if used<0 or not same_span(ledger):return State.denied("计时状态不可核实，停止刷物。")
 if close and not frozen:return State.denied("关闭前须冻结无战活跃段。")
 return State.progress(ledger,key,State.identity(ledger.entries[key]),used,close)
func accept_commit(ledger:Dictionary)->bool:
 if not same_span(ledger):return false
 var entry:Dictionary=ledger.entries[key]
 if entry.recovery_blocked:return false
 if not entry.open_span:
  key="";binding={};span={};anchor_ms=-1;base_used_ms=0;frozen=false;storage_paused=false;cached_sample={};heartbeat_wall_ms=-1;heartbeat_call=null
  return true
 # Keep the original time anchor across checkpoint writes/retries. It is the
 # accumulated total, never +=delta per attempted save, so failures cannot double.
 return entry.used_ms>=base_used_ms
func may_attempt(ledger:Dictionary,run_identity:Dictionary)->bool:
 if blocked or frozen or binding!=run_identity or not same_span(ledger) or ledger.recovery_blocked:return false
 var entry:Dictionary=ledger.entries[key]
 var used:=used_ms()
 return used>=0 and entry.open_span and not entry.recovery_blocked and used<entry.limit_ms

# Dormant original-battle adapter. No public caller or step scheduler is wired.
# The clock survives run cancellation solely to settle its already-issued battle.
var battle_receipt:Dictionary={}
var owner_session_id:=0
func bind_battle(b)->void:
 # An admission guard may start an unrelated battle while E2 is CHECKING.
 # A call lock alone is never permission to charge that battle to this span.
 if attempt_call!=null and attempt_frame.is_empty():return
 if anchor_ms<0 or key.is_empty() or not battle_receipt.is_empty():return
 var q=b.quest_auto
 if not q.running or not q.internal or q.detached or q.identity.checkpoint()!=binding or q.step.get("action")!="loot" or q.identity.step_id!=State.STEP:return
 if not attempt_frame.is_empty():
  # E2 already checked both host guards BEFORE consuming the original RNG.
  # Do not call arbitrary guards a second time after pending has been created.
  if not attempt_owned(b,attempt_frame):return
 else:
  if b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():return
  if b.party_guard.is_valid() and not str(b.party_guard.call()).is_empty():return
 if b.stationary.running or not Sources.same(q.step,Sources.step()) or not Sources.matches_backend(b,q.step.source):return
 var ledger:Dictionary=b.session._profile.get("quest_loot",{})
 if b.save_path.is_empty():return
 if not attempt_frame.is_empty():
  # The attempt crossed the budget gate before the original roll. Its current
  # battle must still be counted if loading crosses the time limit meanwhile.
  if not same_span(ledger) or blocked or frozen or ledger.recovery_blocked or not ledger.entries[key].open_span or ledger.entries[key].recovery_blocked:return
 elif not may_attempt(ledger,binding):return
 var saved=JSON.parse_string(b.last_saved_payload)
 if not saved is Dictionary or not same_span(saved.get("quest_loot",{})) or not saved.quest_loot.entries[key].open_span:return
 var pending:Dictionary=b.session._pending
 if not pending.get("source_encounter",false) or pending.get("party",false) or pending.get("capture_only",false) or pending.has("training_borrow") or pending.has("quest_guard"):return
 var source:Dictionary=pending.get("wild_drop_source",{})
 var area:Dictionary=b.encounter_catalog.area_at(b.automation.position_map,b.automation.position_cell)
 # All groups in the actual same area are covered, not just target group711.
 if source.get("map")!=100 or source.get("area")!=56 or source.get("borrowed",true) or b.automation.position_map!=100 or area.get("id")!=56:return
 if source.get("cell")!=[b.automation.position_cell.x,b.automation.position_cell.y] or source.get("group")!=pending.get("group_id") or pending.get("area_id")!=56 or str(pending.get("battle_id","")).is_empty():return
 owner_session_id=b.session.get_instance_id()
 battle_receipt={"owner_session_id":owner_session_id,"identity":binding.duplicate(true),"source":source.duplicate(true),"ledger":{"budget_id":span.budget_id,"generation":span.generation,"issued_seq":span.issued_seq,"battle_id":str(pending.battle_id)}}
 pending.quest_loot_receipt=battle_receipt.duplicate(true)
func settlement_candidate(b,pending:Dictionary,result:Dictionary)->Dictionary:
 if b.save_path.is_empty():return State.denied("刷物预算需要真实存档，不能改为仅内存结算。")
 if battle_receipt.is_empty() or pending.get("quest_loot_receipt",{})!=battle_receipt or b.session.get_instance_id()!=owner_session_id:return State.denied("刷物战斗凭据已失效。")
 if pending.get("wild_drop_source",{})!=battle_receipt.source or str(result.get("battle_id",""))!=str(pending.get("battle_id","")) or str(pending.battle_id)!=str(battle_receipt.ledger.battle_id):return State.denied("刷物原战斗来源已改变。")
 if pending.get("party",false) or pending.get("capture_only",false) or pending.has("training_borrow") or pending.has("quest_guard"):return State.denied("刷物预算不能结算其他战斗。")
 var ledger:Dictionary=b.session._profile.get("quest_loot",{})
 if not same_span(ledger):return State.denied("刷物预算代或活跃段已改变。")
 var received:=0
 for drop in result.get("drop_summary",[]):
  if drop.get("item_id")==2760 and drop.get("received",false)==true:received+=1
 # All original reward computation and target counting precede the cutoff.
 if not pause_storage():return State.denied("刷物活跃时长无法核实。")
 var total:=used_ms()
 if total<0:return State.denied("刷物活跃时长无法核实。")
 return State.settle(ledger,key,battle_receipt.ledger,str(pending.battle_id),total,received)
func settlement_committed(expected_lifetime:RefCounted,receipt:Dictionary,ledger:Dictionary)->bool:
 # Retire only this captured timer generation, never an observer's replacement.
 if not is_same(lifetime,expected_lifetime) or battle_receipt!=receipt:return false
 if not accept_commit(ledger):return false
 battle_receipt={};owner_session_id=0
 return true

## Frozen display-v1 only. No clock calls, normalization, source validation,
## saving, allocation or mutation. Feature/commands remain unavailable.
func projection(b)->Dictionary:
 var available:bool=b._quest_loot_public_enabled()
 var view:Dictionary={"enabled":available,"reason":"限时刷物尚未开放。" if not available else "尚未启动本次刷物预算。","default_limit_minutes":30,"activity":"unavailable","finish_current_battle":false,"recovery_blocked":false,"can_start":false,"can_stop":false,"can_adjust_limit":false,"can_reset":false,"entry":null}
 # Snapshot projection must stay cheap and source-agnostic. This is advisory
 # from already loaded authority only; the command performs the full source,
 # terrain and save/CAS admission again.
 if available:
  var start_reason:String=public_start_projection_reason(b)
  view.can_start=start_reason.is_empty()
  if not start_reason.is_empty() and view.entry==null:view.reason=start_reason
 if b.save_path.is_empty() or b.last_saved_payload.is_empty():return view
 var baseline=JSON.parse_string(b.last_saved_payload)
 if not baseline is Dictionary or not State.valid(baseline.get("quest_loot")):return view
 view.default_limit_minutes=Settings.effective(baseline.get("automation_settings",{})).loot_minutes
 var ledger:Dictionary=baseline.quest_loot
 var entry:Dictionary=ledger.entries.get(State.STEP,{})
 view.recovery_blocked=ledger.recovery_blocked or (not entry.is_empty() and entry.recovery_blocked)
 var cold:Dictionary=b.session.last_loot_cold_retirement
 if not cold.is_empty():
  view.cold_retirement=cold.duplicate(true)
  view.reason=str(cold.reason)
 if entry.is_empty():
  if view.recovery_blocked:view.activity="recovery_locked";view.reason="备份预算历史不确定，尚未开放恢复操作。"
  return view
 var used:int=int(entry.used_ms)
 var live_ledger:Dictionary=b.session._profile.get("quest_loot",{})
 var span_current:bool=is_same(b.quest_loot,self) and anchor_ms>=0 and same_span(ledger) and same_span(live_ledger) and entry.open_span
 var pending:Dictionary=b.session._pending
 var battle_current:bool=span_current and not battle_receipt.is_empty() and owner_session_id==b.session.get_instance_id() and pending.get("quest_loot_receipt",{})==battle_receipt and str(pending.get("battle_id",""))==str(battle_receipt.ledger.battle_id)
 var q=b.quest_auto
 var run_current:bool=span_current and q.running and q.identity.checkpoint()==binding and q.step.get("id")==State.STEP
 var closing_current:bool=idle_close_owner(b,close_pending)
 var sample_current:bool=(run_current or battle_current or closing_current) and is_same(cached_sample.get("lifetime"),lifetime) and cached_sample.get("span")==span and State.integer(cached_sample.get("used_ms"),0,State.MAX_MSEC)
 if sample_current:used=maxi(used,int(cached_sample.used_ms))
 view.entry={"step_id":State.STEP,"budget_id":entry.budget_id,"generation":int(entry.generation),"revision":int(entry.revision),"target_item_id":2760,"target_count":1,"limit_ms":int(entry.limit_ms),"saved_used_ms":int(entry.used_ms),"used_ms":used,"limit_reached":used>=int(entry.limit_ms),"existing_items":int(entry.existing_items),"new_items":int(entry.new_items),"saved_battles":int(entry.saved_battles)}
 view.finish_current_battle=battle_current and (view.entry.limit_reached or not run_current or q.detached)
 if failure_pending_for_profile(b):
  view.activity="storage_paused";view.reason="刷物记录待确认。"
 elif view.recovery_blocked:
  view.activity="recovery_locked";view.reason="中断时段用时不确定，显示已存下界。"
 elif closing_current or (sample_current and storage_paused):
  view.activity="storage_paused"
  view.reason=str(b.battle_state.get("settlement_error","")) if battle_current else ""
  if view.reason.is_empty():view.reason="保存处理中或等待修复，预算暂停计时。"
 elif battle_current:
  # BattleSession.snapshot() refreshes capture_player. Projection is a pure
  # read: use the already-authoritative state dictionary and never sample time.
  view.activity="battle" if b.battle._state.get("active",false) else "settling"
 elif baseline.get("original_items",[]).any(func(item):return State.integer(item,2760,2760)):
  view.activity="completed"
 elif view.entry.limit_reached:
  view.activity="limit_reached"
 elif run_current and not q.detached and not frozen and not blocked:
  view.activity="running"
 else:view.activity="stopped"
 return view

## Cheap display-only eligibility from already resident server state. It does
## not parse the save cache, scan source data, load terrain, or sample time.
## The server command never treats this advisory as authorization.
func public_start_projection_reason(b)->String:
 if failure_pending_for_profile(b):return "刷物记录待确认。"
 if not b._quest_loot_public_enabled():return "限时刷物尚未开放。"
 if b.save_path.is_empty() or b.last_saved_payload.is_empty():return "刷物需要可信真实存档。"
 var q=b.quest_auto
 if q.running or b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or not b.original_quests.pending.is_empty():return "当前事务尚未完成。"
 if b.automation.running or b.automation.hunt_running or b.automation.flow_active() or b.stationary.running:return "当前有其他自动活动。"
 if not close_pending.is_empty() or not cancelled_battle.is_empty() or not open_obligation.is_empty() and anchor_ms>=0:return "已有刷物事务尚未完成。"
 if anchor_ms>=0 or not battle_receipt.is_empty() or not ready_frame.is_empty() or attempt_call!=null:return "旧刷物时段尚未退休。"
 var profile:Dictionary=b.session._profile
 if not profile is Dictionary:return "当前角色资料无效。"
 if int(profile.get("player",{}).get("hp",0))<=0:return "角色已倒下。"
 if profile.get("no_random_encounters",false):return "随机遇敌已关闭，请手动调整；不会自动开启。"
 if b.session.bag_slots(profile)>=15:return "道具栏已满。"
 var ledger_value:Variant=profile.get("quest_loot",{})
 if not State.valid(ledger_value):return "刷物预算资料无效。"
 var ledger:Dictionary=ledger_value
 if ledger.recovery_blocked:return "预算历史需要人工恢复。"
 if ledger.entries.has(State.STEP):
  var entry:Dictionary=ledger.entries[State.STEP]
  if entry.recovery_blocked or entry.open_span or entry.used_ms>=entry.limit_ms:return "既有预算不能隐式重开或重置。"
 return ""

## Authoritative command preflight. This is deliberately outside projection:
## it rechecks the persisted full profile and every original source predicate.
func public_start_reason(b)->String:
 var advisory:String=public_start_projection_reason(b)
 if not advisory.is_empty():return advisory
 var baseline=JSON.parse_string(b.last_saved_payload)
 if not baseline is Dictionary or not b.session._valid_profile(baseline):return "当前存档资料无效。"
 var live:Dictionary=b.session._normalize_numbers(b.session._profile.duplicate(true))
 if b.session._normalize_numbers(baseline)!=live:return "当前角色未匹配已存基线。"
 var planned:Dictionary=JewelPlan.select(b,Sources.matches_backend)
 if planned.get("status")!="step" or not Sources.same(planned.get("step",{}),Sources.step()):return str(planned.get("reason","原刷物来源当前不可用。"))
 # Safe-cell and map data are deliberately rechecked by E1 admission.
 return ""

## The external wire contains only type+seq. The server injects the signed
## connection and resolves its exact attached transport binding.
var public_start_call:RefCounted=null
var initial_e2:Dictionary={}
func public_start(b,connection:int,transport:RefCounted,seq:int)->Dictionary:
 if seq<=0:return {"ok":false,"persisted":false,"reason":"无效刷物启动序号。","seq":seq,"type":"rejected"}
 if public_start_call!=null:return {"ok":false,"persisted":false,"reason":"刷物启动调用正在进行。","seq":seq,"type":"rejected"}
 var call:=RefCounted.new()
 public_start_call=call
 var reply:Dictionary=_public_start_locked(b,connection,transport,seq,call)
 if is_same(public_start_call,call):public_start_call=null
 if not reply.has("persisted"):reply.persisted=false
 reply.seq=seq
 reply.type="ack" if reply.get("ok",false) else "rejected"
 return reply
func _public_start_locked(b,connection:int,transport:RefCounted,seq:int,call:RefCounted)->Dictionary:
 if not b._quest_loot_public_enabled():return State.denied("限时刷物尚未开放。")
 if not is_instance_valid(transport) or connection==-1 or b._fee_bindings.get(connection)!=transport:return State.denied("刷物启动需要当前已连接的可信设备。")
 # Only this loot entry requests one source-proven retry or read-only
 # confirmation. No generic Stop/resume gate, RPC or successor permission.
 if failure_pending_for_profile(b):
  retry_failed_initial_once(b)
  confirm_failed_initial_readonly(b)
  if failure_pending_for_profile(b):return State.denied("刷物记录待确认。")
  if not is_same(public_start_call,call) or b._fee_bindings.get(connection)!=transport:return State.denied("刷物确认期间连接已变化。")
 var reason:String=public_start_reason(b)
 if not reason.is_empty():return State.denied(reason)
 var planned:Dictionary=JewelPlan.select(b,Sources.matches_backend)
 if planned.get("status")!="step" or not Sources.same(planned.get("step",{}),Sources.step()):return State.denied(str(planned.get("reason","原刷物步骤不可用。")))
 var q=b.quest_auto
 # The internal runner identity is server-created; no client route, source,
 # position, budget, proof, client-id or identity field is accepted.
 q.identity.begin();q.identity.select_step(State.STEP)
 q.quest_id=-1;q.clean_authorized=false;q.elapsed=0.0;q.waited=0.0
 q.strict_walk=false;q.internal=true;q.restored=false;q.detached=false;q.owns_battle=false
 q.client="quest-loot:%d"%connection;q.connection=connection
 q.shutdown_intent={};q.source_frame=null;q.waiting_saved=false;q.boss_ready=false
 q.navigation.clear();q.path.clear();q.herb_path.clear();q.clear_motion()
 q.step=planned.step.duplicate(true);q.target={};q.dialogue_choices=[]
 q.running=true;q.phase="loot_admission";q.execution_mode="A"
 q.pause_reason="";q.message="原区域56刷物：正在校验原来源与预算。"
 var start_frame:Dictionary={"call":call,"transport":transport,"connection":connection,"runner":weakref(q),"identity_object":weakref(q.identity),"identity":q.identity.checkpoint(),"session":weakref(b.session),"path":b.save_path,"client":q.client,"step":q.step.duplicate(true),"position_map":b.automation.position_map,"position_cell":b.automation.position_cell,"loot":weakref(self),"lifetime":lifetime}
 var admitted:Dictionary=admit_prepared_run(b)
 if not _public_start_owner(b,start_frame,true):return {"ok":false,"persisted":bool(admitted.get("persisted",false)),"reason":"准入期间启动归属已变化。"}
 if not admitted.get("ok",false):
  var failure_reason:String=str(admitted.get("reason","原刷物准入失败。"))
  if admitted.get("persisted",false):
   # The E1 open is already durable. Use the existing identity-bound Stop;
   # it closes only its captured open obligation, otherwise it stays locked.
   q.stop(b,failure_reason)
  else:
   if is_same(b.quest_auto,q) and q.identity.checkpoint()==start_frame.identity and is_same(b.quest_loot,self):
    q.running=false;q.internal=false;q.phase="stopped";q.message=failure_reason;q.pause_reason=failure_reason
    q.identity.invalidate()
  return {"ok":false,"persisted":bool(admitted.get("persisted",false)),"reason":failure_reason}
 var entry:Dictionary=b.session._profile.quest_loot.entries.get(State.STEP,{})
 start_frame.ready_token=admitted.get("ready_token")
 if not _arm_initial_e2(b,start_frame,admitted,entry):
  var handoff_reason:String="预算已保存，但初始尝试交接未能封口。"
  if _public_start_owner(b,start_frame,true) and entry.get("open_span",false):q.stop(b,handoff_reason)
  return {"ok":false,"persisted":true,"reason":handoff_reason}
 # Publish only after the original writer and E1 clock seal both succeeded.
 # Observers flush after _handle returns; subsequent E2 revalidates this frame.
 b.publish()
 if not _initial_e2_owner(b,initial_e2,false):
  if is_same(b.quest_auto,q) and q.identity.checkpoint()==start_frame.identity and q.running and q.internal and q.phase=="loot_admission" and is_same(initial_e2.get("runner",null).get_ref() if initial_e2.get("runner") is WeakRef else null,q):
   q.stop(b,"E1已保存，但发布后初始尝试状态未能保持。")
  return {"ok":false,"persisted":true,"reason":"E1已保存，但发布后初始尝试归属已变化。"}
 return {"ok":true,"persisted":true,"run_identity":q.identity.checkpoint(),"budget_identity":State.identity(entry)}

func _public_start_owner(b,frame:Dictionary,inside_call:bool)->bool:
 var q=frame.get("runner",null).get_ref() if frame.get("runner") is WeakRef else null
 var owner=frame.get("session",null).get_ref() if frame.get("session") is WeakRef else null
 var timer=frame.get("loot",null).get_ref() if frame.get("loot") is WeakRef else null
 if not is_instance_valid(q) or not is_instance_valid(owner) or not is_instance_valid(timer):return false
 if not is_same(b.quest_loot,timer) or not is_same(b.quest_auto,q) or not is_same(b.session,owner) or b.save_path!=frame.path:return false
 if not is_same(q.identity,frame.identity_object.get_ref()) or q.identity.checkpoint()!=frame.identity or q.connection!=frame.connection or q.client!=frame.client or q.step!=frame.step:return false
 if not q.running or not q.internal or q.detached or q.restored or q.phase!="loot_admission":return false
 if b._fee_bindings.get(frame.connection)!=frame.transport:return false
 if b.automation.position_map!=frame.position_map or b.automation.position_cell!=frame.position_cell:return false
 if inside_call and (not is_same(public_start_call,frame.call) or not b._quest_loot_public_enabled()):return false
 return true

func _arm_initial_e2(b,start_frame:Dictionary,admitted:Dictionary,entry:Dictionary)->bool:
 if not admitted.get("ok",false) or not admitted.get("persisted",false) or not State.valid_entry(entry) or not entry.open_span:return false
 var ready:Dictionary=ready_frame
 if ready.is_empty() or ready.get("identity",{})!=start_frame.identity or ready.get("connection",-1)!=start_frame.connection or ready.get("client","")!=start_frame.client or ready.get("step",{})!=start_frame.step:return false
 if not is_same(ready.get("capability"),admitted.get("capability")) or not is_same(ready.get("lifetime"),admitted.get("lifetime")) or not is_same(ready.get("ready_token"),admitted.get("ready_token")) or not is_same(ready.get("ready_token"),start_frame.ready_token):return false
 if admitted.get("identity",{})!=start_frame.identity or admitted.get("candidate_serial",-1)!=b.quest_save_serial or admitted.get("candidate_payload","")!=b.last_saved_payload:return false
 var installed=JSON.parse_string(str(admitted.get("candidate_payload","")))
 if not installed is Dictionary or not b.session._valid_profile(installed):return false
 var installed_profile:Dictionary=b.session._normalize_numbers(installed.duplicate(true))
 var live_profile:Dictionary=b.session._normalize_numbers(b.session._profile.duplicate(true))
 if not _public_start_owner(b,start_frame,true) or live_profile!=installed_profile:return false
 initial_e2={"token":RefCounted.new(),"transport":start_frame.transport,"connection":start_frame.connection,"client":start_frame.client,"runner":start_frame.runner,"identity_object":start_frame.identity_object,"identity":start_frame.identity.duplicate(true),"session":start_frame.session,"path":start_frame.path,"step":start_frame.step.duplicate(true),"position_map":start_frame.position_map,"position_cell":start_frame.position_cell,"loot":weakref(self),"lifetime":admitted.lifetime,"capability":admitted.capability,"ready_token":admitted.ready_token,"entry":State.identity(entry),"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"payload":b.last_saved_payload,"serial":b.quest_save_serial,"dispatch":b.continuation_dispatch_checkpoint(),"generation_floor":b._normal_process_generation,"last_generation":b._normal_process_generation}
 return true

func _initial_e2_owner(b,frame:Dictionary,check_writer:bool)->bool:
 if frame.is_empty() or not is_same(initial_e2,frame):return false
 var q=frame.runner.get_ref() if frame.get("runner") is WeakRef else null
 var owner=frame.session.get_ref() if frame.get("session") is WeakRef else null
 var timer=frame.loot.get_ref() if frame.get("loot") is WeakRef else null
 if not is_instance_valid(q) or not is_instance_valid(owner) or not is_instance_valid(timer):return false
 if not is_same(b.quest_loot,timer) or not is_same(b.quest_auto,q) or not is_same(b.session,owner) or b.save_path!=frame.path:return false
 if not is_same(q.identity,frame.identity_object.get_ref()) or q.identity.checkpoint()!=frame.identity or q.connection!=frame.connection or q.client!=frame.client or q.step!=frame.step or not q.running or not q.internal or q.detached or q.restored or q.phase!="loot_admission":return false
 if not is_same(lifetime,frame.lifetime) or not is_same(admission,frame.capability) or not is_same(ready_frame.get("ready_token"),frame.ready_token) or ready_frame.get("identity",{})!=frame.identity or ready_frame.get("connection",-1)!=frame.connection or ready_frame.get("client","")!=frame.client or ready_frame.get("step",{})!=frame.step or ready_frame.has("continuation_gate"):return false
 if b._fee_bindings.get(frame.connection)!=frame.transport or b.automation.position_map!=frame.position_map or b.automation.position_cell!=frame.position_cell:return false
 if check_writer and (not is_same(b.session._profile,frame.profile_ref) or b.session._profile!=frame.profile or b.last_saved_payload!=frame.payload or b.quest_save_serial!=frame.serial):return false
 return true

# Only the original outer-process resume writer may advance an unchanged
# initial E2 serial seal. Generic save/checkpoint calls retain the strict fence.
# Depth 2 is outer _process (1) plus keep_resume_file wrapper (1).
func capture_initial_resume_save(b)->Dictionary:
 if not b.keep_resume_current or b._process_depth!=1 or b._dispatch_boundary_depth!=2 or b._depth!=0 or b._observer_depth!=0 or b._flush_depth!=0 or not b._queue.is_empty():return {}
 var frame:Dictionary=initial_e2
 if not _initial_e2_owner(b,frame,true) or b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or attempt_call!=null or not attempt_frame.is_empty():return {}
 return {"frame":frame,"ready":ready_frame,"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"payload":b.last_saved_payload,"serial":b.quest_save_serial,"generation":b._normal_process_generation}
func finish_initial_resume_save(b,ticket:Dictionary,saved:bool)->void:
 if ticket.is_empty() or not saved:return
 var fact:Dictionary=ticket.get("writer_fact",{})
 if not fact.get("eligible",false) or not fact.get("written") is bool or not fact.written or not is_same(fact.get("saved_call"),fact.get("call")) or not fact.get("saved_serial") is int or fact.saved_serial!=int(ticket.serial)+1:return
 if not b.keep_resume_current or b._process_depth!=1 or b._dispatch_boundary_depth!=2 or b._depth!=0 or b._observer_depth!=0 or b._flush_depth!=0 or not b._queue.is_empty() or b._normal_process_generation!=ticket.generation:return
 var frame:Dictionary=ticket.frame
 if not is_same(initial_e2,frame) or not is_same(ready_frame,ticket.ready) or not _initial_e2_owner(b,frame,false):return
 if b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or attempt_call!=null or not attempt_frame.is_empty():return
 if frame.serial!=ticket.serial or b.quest_save_serial!=ticket.serial+1 or b.last_saved_payload!=ticket.payload or frame.payload!=ticket.payload:return
 if not is_same(b.session._profile,ticket.profile_ref) or b.session._profile!=ticket.profile or frame.profile!=ticket.profile:return
 # No callback, writer, publication, re-admission or new budget here.
 frame.serial=b.quest_save_serial

func _initial_e2_battle_current(b,frame:Dictionary,battle_id:String)->bool:
 if frame.is_empty() or not is_same(initial_e2,frame):return false
 var q=frame.runner.get_ref() if frame.get("runner") is WeakRef else null
 var owner=frame.session.get_ref() if frame.get("session") is WeakRef else null
 var timer=frame.loot.get_ref() if frame.get("loot") is WeakRef else null
 if not is_instance_valid(q) or not is_instance_valid(owner) or not is_instance_valid(timer):return false
 if not is_same(b.quest_loot,timer) or not is_same(b.quest_auto,q) or not is_same(b.session,owner) or b.save_path!=frame.path:return false
 if not is_same(q.identity,frame.identity_object.get_ref()) or q.identity.checkpoint()!=frame.identity or q.connection!=frame.connection or q.client!=frame.client or q.step!=frame.step or not q.running or not q.internal or q.detached or q.restored or q.phase!="loot_battle":return false
 if not is_same(lifetime,frame.lifetime) or not is_same(admission,frame.capability) or not is_same(ready_frame.get("ready_token"),frame.ready_token):return false
 if b._fee_bindings.get(frame.connection)!=frame.transport or not b.battle_open or str(b.session._pending.get("battle_id",""))!=battle_id:return false
 return not battle_receipt.is_empty() and b.session._pending.get("quest_loot_receipt",{})==battle_receipt and str(battle_receipt.get("ledger",{}).get("battle_id",""))==battle_id

# UNRUN candidate: execution revocation is separate from durable-close authority.
var initial_failure:Dictionary={}
func _initial_failure_execution(b,frame:Dictionary)->bool:
 if frame.is_empty() or not is_same(initial_e2,frame) or not is_same(b.quest_loot,self):return false
 for pair in [["session",b.session],["runner",b.quest_auto],["loot",self],["identity_object",b.quest_auto.identity]]:
  var ref:Variant=frame.get(pair[0])
  if not ref is WeakRef or not is_same(ref.get_ref(),pair[1]):return false
 var q=b.quest_auto
 return b.save_path==frame.path and is_same(lifetime,frame.lifetime) and q.identity.checkpoint()==frame.identity and q.step==frame.step and q.running and q.internal and q.phase=="loot_admission" and q.connection==frame.connection and q.client==frame.client and not q.detached and not q.restored and not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty() and battle_receipt.is_empty() and attempt_call==null and attempt_frame.is_empty()
func _initial_failure_current(b,record:Dictionary)->bool:
 if record.is_empty() or not is_same(initial_failure,record) or not is_same(b.quest_loot,self) or not initial_e2.is_empty() or not ready_frame.is_empty() or not is_same(admission,record.revoked_cap):return false
 var frame:Dictionary=record.frame
 for pair in [["session",b.session],["runner",b.quest_auto],["loot",self],["identity_object",b.quest_auto.identity]]:
  var ref:Variant=frame.get(pair[0])
  if not ref is WeakRef or not is_same(ref.get_ref(),pair[1]):return false
 var q=b.quest_auto
 return b.save_path==frame.path and is_same(lifetime,frame.lifetime) and q.identity.checkpoint()==frame.identity and q.step==frame.step and q.connection==frame.connection and q.client==frame.client and not q.running and q.phase=="stopped" and not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty()
# In-memory failure ownership survives runner identity changes. Cold loading
# retires the selected persisted ledger without recreating the old run.
func failure_pending_for_profile(b)->bool:
 if initial_failure.is_empty() or initial_failure.result.budget_close=="persisted":return false
 if not is_same(b.quest_loot,self) or b.session==null or b.save_path!=initial_failure.path:return false
 var profile_id:Variant=b.session._profile.get("profile_id")
 # character_id is a changeable appearance, not the persistent save owner.
 if not profile_id is String:return true
 return profile_id==initial_failure.profile_id
func _failure_confirm_current(b,record:Dictionary,scope:Dictionary)->bool:
 if not is_same(initial_failure,record) or not failure_pending_for_profile(b):return false
 var owner:Variant=record.frame.get("session")
 if not owner is WeakRef or not is_same(owner.get_ref(),b.session):return false
 if not record.installed_proven or record.expected.is_empty() or not is_same(b.session._profile,record.installed_ref):return false
 if not is_same(lifetime,record.frame.lifetime) or not is_same(open_obligation,record.obligation):return false
 if b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty():return false
 return _failure_observation_current(b,scope) and b.quest_save_serial==record.serial+1 and b.session._profile==record.expected and b.last_saved_payload==record.expected_payload and State.valid(b.session._profile.get("quest_loot",{})) and b.session._profile.quest_loot==record.expected.quest_loot
func confirm_failed_initial_readonly(b)->bool:
 if not failure_pending_for_profile(b):return false
 var record:Dictionary=initial_failure
 var scope:Dictionary=_failure_observation(b)
 if not _failure_confirm_current(b,record,scope):return false
 var facts:Array[Dictionary]=[]
 # Bounded latest read-only observation; original writer facts remain immutable.
 record.confirm_facts=[]
 for path in [record.path,record.path+".bak",record.path+".tmp"]:
  if not _failure_confirm_current(b,record,scope):return false
  var raw:Variant=_failure_disk(path)
  if not _failure_confirm_current(b,record,scope):return false
  # Append facts to this exact obligation, never adopt a successor profile.
  record.confirm_facts.append(raw.duplicate(true))
  facts.append(_failure_fact(raw))
 if _failure_matches(facts[0],record.expected_payload.to_utf8_buffer())!="matches" or _failure_matches(facts[1],str(record.payload).to_utf8_buffer())!="matches" or facts[2].state!="missing":return false
 # Retire only the proven original timer span. No q.message/profile/save/publish.
 if not same_span(record.expected.quest_loot):return false
 if not accept_commit(record.expected.quest_loot):return false
 if is_same(open_obligation,record.obligation):open_obligation={}
 record.result={"ok":true,"stopped_in_memory":true,"budget_close":"persisted","stage":"readonly_confirmed","reason":"原刷物关闭记录已只读确认。"}
 return true
func _failure_disk(path:String)->Dictionary:
 var file:=FileAccess.open(path,FileAccess.READ)
 var open_error:int=FileAccess.get_open_error()
 if file==null:return {"state":"missing" if open_error==ERR_FILE_NOT_FOUND else "unknown","open_error":open_error}
 var length:int=file.get_length()
 var length_error:int=file.get_error()
 # No new profile-size limit; exact original length or unknown I/O facts.
 if length_error!=OK or length<0:file.close();return {"state":"unknown"}
 var bytes:PackedByteArray=file.get_buffer(length)
 var error:int=file.get_error()
 file.close()
 if error!=OK or bytes.size()!=length:return {"state":"unknown","declared":length,"error":error,"bytes":bytes}
 return {"state":"read","bytes":bytes}
# Only canonical, typed observations reach comparisons. Extra/contradictory shape
# is unknown, never evidence of absence. This is not a profile-size contract.
func _failure_fact(raw:Variant)->Dictionary:
 if not raw is Dictionary:return {"state":"unknown"}
 var state_value:Variant=raw.get("state")
 if not state_value is String:return {"state":"unknown"}
 var state:String=state_value
 if state=="read":
  var bytes_value:Variant=raw.get("bytes")
  if raw.size()!=2 or not bytes_value is PackedByteArray:return {"state":"unknown"}
  return {"state":"read","bytes":bytes_value}
 if state=="missing":
  var error_value:Variant=raw.get("open_error")
  if raw.size()!=2 or not error_value is int:return {"state":"unknown"}
  if error_value==ERR_FILE_NOT_FOUND:return {"state":"missing","open_error":ERR_FILE_NOT_FOUND}
 return {"state":"unknown"}
func _failure_matches(raw:Variant,expected:PackedByteArray)->String:
 var fact:Dictionary=_failure_fact(raw)
 var state:String=fact.state
 if state!="read":return state
 var bytes:PackedByteArray=fact.bytes
 return "matches" if bytes==expected else "different"
func _failure_observation(b)->Dictionary:
 return {"serial":b.quest_save_serial,"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"payload":b.last_saved_payload,"obligation":open_obligation,"obligation_value":open_obligation.duplicate(true),"clock":clock,"anchor":anchor_ms,"base":base_used_ms,"last":last_ms,"frozen":frozen,"blocked":blocked,"paused":storage_paused,"map":b.automation.position_map,"cell":b.automation.position_cell,"transport":b._fee_bindings.get(b.quest_auto.connection)}
func _failure_observation_current(b,scope:Dictionary)->bool:
 return b.quest_save_serial==scope.serial and is_same(b.session._profile,scope.profile_ref) and b.session._profile==scope.profile and b.last_saved_payload==scope.payload and is_same(open_obligation,scope.obligation) and open_obligation==scope.obligation_value and clock==scope.clock and anchor_ms==scope.anchor and base_used_ms==scope.base and last_ms==scope.last and frozen==scope.frozen and blocked==scope.blocked and storage_paused==scope.paused and b.automation.position_map==scope.map and b.automation.position_cell==scope.cell and b._fee_bindings.get(b.quest_auto.connection)==scope.transport
func _failure_close_baseline(b,frame:Dictionary,evidence:Dictionary)->bool:
 # This slice does not acquire or close a separate fee lifecycle obligation.
 if b.session._profile.has("quest_auto_fee_lifecycle") or not _initial_e2_owner(b,frame,false):return false
 if not is_same(b.session._profile,frame.profile_ref) or b.session._profile!=frame.profile or b.last_saved_payload!=frame.payload:return false
 if not b.session._valid_profile(frame.profile) or not State.valid(frame.profile.get("quest_loot",{})):return false
 var entry:Dictionary=frame.profile.quest_loot.entries.get(State.STEP,{})
 if not State.valid_entry(entry) or not entry.open_span or entry.recovery_blocked or frame.profile.quest_loot.recovery_blocked or State.identity(entry)!=frame.entry:return false
 if open_obligation.is_empty() or not is_same(open_obligation.owner,b.session) or not is_same(open_obligation.runner,b.quest_auto) or open_obligation.path!=frame.path or open_obligation.identity!=frame.identity or not is_same(open_obligation.lifetime,lifetime) or open_obligation.entry!=frame.entry:return false
 var scope:Dictionary=_failure_observation(b)
 var facts:Array[Dictionary]=[]
 for path in [frame.path,frame.path+".bak",frame.path+".tmp"]:
  if not _initial_failure_execution(b,frame) or not _failure_observation_current(b,scope):return false
  var raw:Variant=_failure_disk(path)
  if not _initial_failure_execution(b,frame) or not _failure_observation_current(b,scope):return false
  evidence.facts.append(raw.duplicate(true))
  facts.append(_failure_fact(raw))
 if _failure_matches(facts[0],str(frame.payload).to_utf8_buffer())!="matches" or facts[1].state!="read" or facts[2].state!="missing":return false
 var backup_bytes:PackedByteArray=facts[1].bytes
 var old_backup:Variant=JSON.parse_string(backup_bytes.get_string_from_utf8())
 return old_backup is Dictionary and b.session._valid_profile(old_backup)
func _failure_close_current(b,record:Dictionary)->bool:
 return _initial_failure_current(b,record) and b.quest_save_serial==record.serial and is_same(b.session._profile,record.profile_ref) and b.session._profile==record.profile and b.last_saved_payload==record.payload and is_same(open_obligation,record.obligation) and clock==record.clock and anchor_ms==record.anchor and base_used_ms==record.base and last_ms==record.last and not frozen and not blocked and not storage_paused and b._fee_bindings.get(record.frame.connection)==record.frame.transport and b.automation.position_map==record.frame.position_map and b.automation.position_cell==record.frame.position_cell
func _retire_initial_failure(b,frame:Dictionary)->Dictionary:
 if not _initial_failure_execution(b,frame):
  # No Stop/capture/close/message/publication on behalf of an old call.
  if is_same(initial_e2,frame):initial_e2={}
  return {"ok":false,"stopped_in_memory":false,"budget_close":"unknown","stage":"stale_or_nonidle"}
 var observation_serial:int=b.quest_save_serial
 var evidence:Dictionary={"facts":[]}
 var close_allowed:bool=_failure_close_baseline(b,frame,evidence)
 # Disk reads above are observation only; never learn a successor authority.
 if not _initial_failure_execution(b,frame):return {"ok":false,"stopped_in_memory":false,"budget_close":"unknown","stage":"stale_after_observation"}
 close_allowed=close_allowed and b.quest_save_serial==observation_serial and is_same(b.session._profile,frame.profile_ref) and b.session._profile==frame.profile and b.last_saved_payload==frame.payload
 var record:Dictionary={"frame":frame,"revoked_cap":RefCounted.new(),"serial":b.quest_save_serial,"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"payload":b.last_saved_payload,"obligation":open_obligation,"clock":clock,"anchor":anchor_ms,"base":base_used_ms,"last":last_ms,"result":{"ok":false,"stopped_in_memory":true,"budget_close":"not_attempted","stage":"execution_revoked","reason":"刷物校验失效，已停止新尝试；预算关闭未确认，未新增刷物尝试。"}}
 # Ledger owner is captured from the actual sealed profile, not a new runner.
 record.path=frame.path;record.profile_id=str(frame.profile.get("profile_id",""));record.character_id=str(frame.profile.get("character_id",""))
 record.ledger_owner={"step_id":State.STEP,"entry":frame.entry.duplicate(true),"issued_seq":frame.profile.quest_loot.entries[State.STEP].issued_seq}
 record.expected={};record.expected_payload="";record.cutoff=-1
 record.write_token=null;record.write_receipts=[];record.writer_attempts=0;record.retry_count=0;record.prewrite_proven=false;record.installed_proven=false;record.installed_ref={}
 record.baseline_facts=evidence.facts;record.writer_result={};record.readback_facts=[];record.confirm_facts=[]
 initial_failure=record
 # No callback, snapshot, Stop, capture_idle_close or resume write in this revocation.
 initial_e2={};ready_frame={};admission=record.revoked_cap
 var q=b.quest_auto
 q.running=false;q.owns_battle=false;q.phase="stopped";q.message=record.result.reason
 q.clear_motion()
 if close_allowed and _failure_close_current(b,record) and record.anchor>=0 and record.clock.is_valid():
  # Clock output is local until the entire captured scope is rechecked.
  var sample:Variant=record.clock.call()
  if _failure_close_current(b,record) and State.integer(sample,0,State.MAX_MSEC) and sample>=record.last and sample>=record.anchor and record.base<=State.MAX_MSEC-(sample-record.anchor):
   var used:int=record.base+int(sample)-record.anchor
   var planned:Dictionary=State.progress(record.profile.quest_loot,State.STEP,frame.entry,used,true)
   if planned.get("ok",false):
    var expected:Dictionary=record.profile.duplicate(true)
    expected.quest_loot=planned.ledger
    # Freeze once before the real writer; false never earns retry authority.
    record.expected=expected.duplicate(true);record.expected_payload=JSON.stringify(expected);record.cutoff=int(sample)
    record.writer_attempts=1
    record.result={"ok":false,"stopped_in_memory":true,"budget_close":"unknown","stage":"writer_in_flight","reason":"刷物记录待确认；已停止本次刷物。"}
    var envelope:Dictionary=b.session.begin_loot_failure_close(record.profile,{"step_id":State.STEP,"expected_entry":frame.entry,"total_used_ms":used},frame.path,b,self,record.revoked_cap)
    _finish_failure_write(b,record,envelope)
 if _initial_failure_current(b,record):
  q.message=record.result.reason
  b.publish() # Last action: no returning old-call mutation after publication.
 return record.result.duplicate(true)

func _finish_failure_write(b,record:Dictionary,envelope:Dictionary)->bool:
 # No old-call side effect after the original writer can replace its owner.
 if not _initial_failure_current(b,record):return false
 var token:Variant=envelope.get("token")
 if token is RefCounted:record.write_token=token
 var result_value:Variant=envelope.get("result",{})
 var result:Dictionary=result_value if result_value is Dictionary else {}
 record.write_receipts.append(envelope.duplicate(true))
 record.writer_result=result.duplicate(true)
 record.prewrite_proven=b.session.loot_failure_retryable(record.write_token)
 record.installed_proven=result.get("ok") is bool and result.ok and result.get("installed") is bool and result.installed and b.quest_save_serial==record.serial+1 and b.session._profile==record.expected and b.last_saved_payload==record.expected_payload
 if record.installed_proven:record.installed_ref=b.session._profile
 var read_scope:Dictionary=_failure_observation(b)
 var facts:Array[Dictionary]=[]
 for path in [record.path,record.path+".bak",record.path+".tmp"]:
  if not _initial_failure_current(b,record) or not _failure_observation_current(b,read_scope):return false
  var raw:Variant=_failure_disk(path)
  if not _initial_failure_current(b,record) or not _failure_observation_current(b,read_scope):return false
  record.readback_facts.append(raw.duplicate(true))
  facts.append(_failure_fact(raw))
 record.result={"ok":false,"stopped_in_memory":true,"budget_close":"unknown","stage":"close_partial_or_unknown","reason":"刷物记录待确认；已停止本次刷物。","writer_ok":result.get("ok","unknown"),"primary_candidate":_failure_matches(facts[0],record.expected_payload.to_utf8_buffer()),"backup_previous":_failure_matches(facts[1],str(record.payload).to_utf8_buffer()),"temporary_state":facts[2].state}
 if record.installed_proven and record.result.primary_candidate=="matches" and record.result.backup_previous=="matches" and facts[2].state=="missing":
  record.result.ok=true;record.result.budget_close="persisted";record.result.stage="close_verified"
  record.result.reason="刷物校验失效，已停止；原预算时段已保存关闭。"
  accept_commit(record.expected.quest_loot)
  if is_same(open_obligation,record.obligation):open_obligation={}
 return record.result.ok
func retry_failed_initial_once(b)->bool:
 if not failure_pending_for_profile(b):return false
 var record:Dictionary=initial_failure
 if record.retry_count!=0 or record.expected.is_empty() or not _failure_close_current(b,record):return false
 if not b.session.loot_failure_retryable(record.write_token):return false
 record.retry_count=1 # Consume locally BEFORE any read or callback/reentry.
 var facts:Array[Dictionary]=[]
 for path in [record.path,record.path+".bak",record.path+".tmp"]:
  if not _failure_close_current(b,record):return false
  var raw:Variant=_failure_disk(path)
  if not _failure_close_current(b,record):return false
  facts.append(_failure_fact(raw))
 if record.baseline_facts.size()!=3:return false
 var original_backup:Dictionary=_failure_fact(record.baseline_facts[1])
 if original_backup.state!="read" or _failure_matches(facts[0],str(record.payload).to_utf8_buffer())!="matches" or _failure_matches(facts[1],original_backup.bytes)!="matches" or facts[2].state!="missing":return false
 if not _failure_close_current(b,record):return false
 record.writer_attempts=2
 record.result={"ok":false,"stopped_in_memory":true,"budget_close":"unknown","stage":"retry_in_flight","reason":"刷物记录待确认；已停止本次刷物。"}
 var envelope:Dictionary=b.session.retry_loot_failure_close(record.write_token)
 return _finish_failure_write(b,record,envelope)

func _tick_initial_e2(b)->void:
 var frame:Dictionary=initial_e2
 if not failed_initial_resume.is_empty():
  var rejected:Dictionary=failed_initial_resume
  failed_initial_resume={}
  if is_same(rejected,frame):
   _retire_initial_failure(b,frame)
   return
 if not _initial_e2_owner(b,frame,true):
  _retire_initial_failure(b,frame)
  return
 if not b.continuation_dispatch_ready(frame.dispatch):return
 var generation:int=b._normal_process_generation
 if generation<=int(frame.get("generation_floor",0)) or generation<=int(frame.get("last_generation",0)):return
 if b._process_depth!=1 or b._dispatch_boundary_depth!=1 or b._observer_depth!=0 or b._flush_depth!=0 or b._depth!=1:return
 if b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or attempt_call!=null:return
 frame.last_generation=generation
 var reply:Dictionary=attempt_once(b)
 if reply.get("_sample_stale",false):
  _retire_initial_failure(b,frame)
  return
 var battle_id:String=str(reply.get("battle_id",""))
 if reply.get("battle",false):
  if _initial_e2_battle_current(b,frame,battle_id):initial_e2={}
  elif is_same(initial_e2,frame):initial_e2={}
  return
 if not _initial_e2_owner(b,frame,false):
  _retire_initial_failure(b,frame)
  return
 if reply.get("ok",false):
  var sample:Variant=reply.get("_progress_sample",{})
  if sample is Dictionary and not sample.is_empty():publish_attempt_progress(b,sample)
  return
 # Same owner only: normal stop performs the existing durable E1 close.
 # Stale/new-run returns above retire only this captured frame object.
 if is_same(initial_e2,frame) and _initial_e2_owner(b,frame,false) and not b.battle_open and b.session._pending.is_empty():
  b.quest_auto.stop(b,str(reply.get("reason","刷物尝试停止。")))

# E1 internal prepared-run admission. No public caller or new acquisition via C2.
const MapFile=preload("res://scripts/map_file.gd")
const JewelPlan=preload("res://server/quest_auto_jewel_loot_plan.gd")
var admission:RefCounted
static func admission_terrain_valid(data:Dictionary)->bool:
 # MapFile normalizes JSON/packed maps to these packed grids; safe reads both.
 if not State.integer(data.get("width"),1,2147483647) or not State.integer(data.get("height"),1,2147483647):return false
 var width:int=int(data.width)
 var height:int=int(data.height)
 if width>2147483647/height:return false
 return data.get("blocked") is PackedByteArray and data.blocked.size()==width*height and data.get("ground") is PackedInt32Array and data.ground.size()==width*height
func admission_error(b,frame:Dictionary)->String:
 if not admission_owner(b,frame):return "准入调用归属已失效。"
 var q=frame.runner
 if not is_same(b.quest_loot,self) or not q.running or not q.internal or q.detached or q.restored or q.connection==-1 or q.client.is_empty() or q.phase!="loot_admission" or q.identity.step_id!=State.STEP:return "刷物内部执行身份无效。"
 if not Sources.same(q.step,Sources.step()):return "刷物步骤来源无效。"
 if b.save_path.is_empty() or b.last_saved_payload.is_empty():return "刷物需要可信真实存档。"
 if b.battle_open or b.battle.snapshot().get("active",false) or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or not b.original_quests.pending.is_empty():return "当前事务尚未完成。"
 if b.automation.running or b.automation.hunt_running or b.automation.flow_active() or b.stationary.running:return "当前有其他自动活动。"
 # Guards are host Callables and may synchronously cancel or replace a run.
 # Check each boundary before invoking the next guard or selecting a candidate.
 for guard in [b.quest_visit_guard,b.party_guard]:
  if not admission_owner(b,frame):return "准入回调前归属已改变。"
  if not guard.is_valid():continue
  var profile_ref:Dictionary=frame.owner._profile
  var before:Dictionary=frame.owner.snapshot()
  var saved:String=b.last_saved_payload
  var denied:String=str(guard.call())
  if not admission_owner(b,frame):return "准入回调改变了执行归属。"
  if not is_same(frame.owner._profile,profile_ref) or frame.owner.snapshot()!=before or b.last_saved_payload!=saved:return "准入回调改变了角色或存档。"
  if not denied.is_empty():return "当前连接或组队状态不允许刷物。"
 var profile:Dictionary=b.session.snapshot()
 if not b.session._valid_profile(profile) or int(profile.player.hp)<=0:return "角色状态无效或已倒下。"
 if profile.get("no_random_encounters",false):return "随机遇敌已关闭，请手动调整；不会自动开启。"
 if b.session.bag_slots(profile)>=15:return "道具栏已满。"
 if b.automation.position_map!=100 or b.encounter_catalog.area_at(100,b.automation.position_cell).get("id")!=56:return "当前实际区域不是原区域56。"
 if b.quest_helper.places.file(100)!=frame.terrain_path:return "准入期间原地图路径已改变。"
 # One independent load per invocation, reused across guards/acquire/open.
 # Never populate or trust quest_helper.maps; dynamic occupancy stays live.
 if not frame.has("terrain"):frame.terrain=MapFile.load_map(frame.terrain_path)
 var data:Dictionary=frame.terrain
 if not admission_terrain_valid(data):return "原地图缺失或结构无效。"
 var occupied:Dictionary={}
 for npc in b.quest_catalog.active_npcs():
  if int(npc.map_id)==100:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 for npc in b.quest_helper.places.residents:
  if int(npc.map_id)==100:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 if not b.quest_helper.safe(data,b.automation.position_cell,occupied,b.quest_helper.places.links(100)):return "当前格不是可用原普通格。"
 if not Sources.matches_backend(b,q.step.source):return "完整原来源校验失败。"
 if not admission_owner(b,frame):return "准入结束时归属已改变。"
 return ""
func admission_owner(b,frame:Dictionary)->bool:
 if not frame.get("continuation",{}).is_empty() and not continuation_current(b,frame.continuation):return false
 var q=b.quest_auto
 return b.quest_visit_guard==frame.visit_guard and b.party_guard==frame.party_guard and is_same(b.session,frame.owner) and b.save_path==frame.path and is_same(b.quest_loot,self) and is_same(lifetime,frame.lifetime) and is_same(admission,frame.capability) and is_same(q,frame.runner) and q.identity.checkpoint()==frame.identity and q.connection==frame.connection and q.client==frame.client and q.running and q.internal and not q.detached and not q.restored and q.phase==str(frame.get("phase","loot_admission")) and q.step==frame.step and b.automation.position_map==frame.map_id and b.automation.position_cell==frame.cell
func admit_prepared_run(b,continuation:Dictionary={})->Dictionary:
 if not continuation.is_empty() and not continuation_current(b,continuation):return State.denied("续行调用归属已失效。")
 # Capture this invocation BEFORE any reentrant guard, never adopt its successor.
 admission=RefCounted.new()
 if not continuation.is_empty():continuation.e1_admission=admission
 var q=b.quest_auto
 var frame:Dictionary={"owner":b.session,"path":b.save_path,"runner":q,"identity":q.identity.checkpoint(),"connection":q.connection,"client":q.client,"step":q.step.duplicate(true),"map_id":b.automation.position_map,"cell":b.automation.position_cell,"lifetime":lifetime,"capability":admission,"visit_guard":b.quest_visit_guard,"party_guard":b.party_guard,"terrain_path":b.quest_helper.places.file(100),"clock":clock,"continuation":continuation}
 var reason:=admission_error(b,frame)
 if not reason.is_empty():return State.denied(reason)
 if anchor_ms>=0 or not battle_receipt.is_empty():return State.denied("旧刷物时段尚未退休。")
 var planned:Dictionary=JewelPlan.select(b,Sources.matches_backend)
 if planned.get("status")!="step" or not Sources.same(planned.get("step"),b.quest_auto.step):return State.denied(str(planned.get("reason","目标已满足或原步骤无效。")))
 var baseline=JSON.parse_string(b.last_saved_payload)
 if not baseline is Dictionary or not b.session._valid_profile(baseline) or b.session._normalize_numbers(baseline)!=b.session.snapshot():return State.denied("当前角色未匹配已存基线。")
 var ledger:Dictionary=b.session._profile.quest_loot
 if ledger.recovery_blocked:return State.denied("预算历史需要人工恢复。")
 if ledger.entries.has(State.STEP):
  var entry:Dictionary=ledger.entries[State.STEP]
  if entry.recovery_blocked or entry.open_span or entry.used_ms>=entry.limit_ms:return State.denied("既有预算不能隐式重开或重置。")
 if not continuation.is_empty() and not ledger.entries.has(State.STEP):return State.denied("续行不能创建新预算。")
 var operations:Array=["open"] if ledger.entries.has(State.STEP) else ["acquire","open"]
 var persisted:=false
 var opened:Dictionary={}
 for operation in operations:
  if not admission_owner(b,frame):return {"ok":false,"persisted":persisted,"reason":"写前执行归属已变化。"}
  reason=admission_error(b,frame)
  if not reason.is_empty():return {"ok":false,"persisted":persisted,"reason":reason}
  var expected:Dictionary=frame.owner.snapshot()
  var args:Dictionary={"step_id":State.STEP}
  if operation=="acquire":
   args.merge({"budget_id":Crypto.new().generate_random_bytes(16).hex_encode(),"run_id":frame.identity.run_id,"minutes":Settings.effective(frame.owner.automation_settings()).loot_minutes,"existing_items":0})
  else:args.expected_entry=State.identity(expected.quest_loot.entries[State.STEP])
  if not continuation.is_empty():
   if operation!="open" or not continuation_current(b,continuation):return {"ok":false,"persisted":persisted,"reason":"续行写前归属失效。"}
   var transition:Dictionary=State.open(expected.quest_loot,State.STEP,args.expected_entry)
   if not transition.get("ok",false):return transition
   continuation.expected_open=expected.duplicate(true)
   continuation.expected_open.quest_loot=transition.ledger
   continuation.open_payload=JSON.stringify(continuation.expected_open)
  var result:Dictionary=frame.owner.commit_loot_idle_transition(expected,expected.quest_loot.duplicate(true),operation,args,frame.path,_admission_written.bind(b,frame,operation))
  if not result.get("ok",false):return {"ok":false,"persisted":persisted,"reason":"预算保存失败，未启动尝试。"}
  persisted=true
  if operation=="open":opened=result
  # A later observer may replace any owner/profile/cache. Never undo that save.
  if not result.get("installed",false) or not admission_owner(b,frame):return {"ok":false,"persisted":true,"reason":"已存事务后执行归属改变，停止旧调用。"}
  if frame.owner.snapshot()!=result.profile or b.last_saved_payload!=result.payload:return {"ok":false,"persisted":true,"reason":"已存事务后角色或保存基线改变。"}
  reason=admission_error(b,frame)
  if not reason.is_empty():return {"ok":false,"persisted":true,"reason":reason}
  planned=JewelPlan.select(b,Sources.matches_backend)
  if planned.get("status")!="step" or not Sources.same(planned.get("step"),frame.step):return {"ok":false,"persisted":true,"reason":"写后原计划条件改变。"}
 return start_admission_after_commit(b,frame,opened)

# E1-only clock boundary. Public timer APIs remain unchanged.
func admission_timer_snapshot()->Dictionary:
 return {"key":key,"binding":binding.duplicate(true),"span":span.duplicate(true),"anchor_ms":anchor_ms,"base_used_ms":base_used_ms,"last_ms":last_ms,"blocked":blocked,"frozen":frozen,"frozen_ms":frozen_ms,"storage_paused":storage_paused,"cached_sample":cached_sample.duplicate(true),"ready_frame":ready_frame.duplicate(true),"initial_e2":initial_e2.duplicate(true),"next_attempt_ms":next_attempt_ms,"last_attempt_ms":last_attempt_ms,"attempt_frame":attempt_frame.duplicate(true),"attempt_call":attempt_call,"battle_receipt":battle_receipt.duplicate(true),"open_obligation":open_obligation.duplicate(true),"close_pending":close_pending.duplicate(true)}
func start_admission_after_commit(b,frame:Dictionary,opened:Dictionary)->Dictionary:
 var denied:Dictionary={"ok":false,"persisted":true,"reason":"已存时段无法启动计时，停止等待恢复。"}
 if not admission_owner(b,frame) or clock!=frame.clock or not opened.get("ok",false) or not opened.get("installed",false):return denied
 if frame.owner.snapshot()!=opened.profile or b.last_saved_payload!=opened.payload:return denied
 var entry:Dictionary=opened.profile.quest_loot.entries[State.STEP]
 if anchor_ms>=0 or not State.valid_entry(entry) or not entry.open_span or entry.recovery_blocked:return denied
 if not State.exact(frame.identity,["run_id","step_id","revision"]) or not State.opaque(frame.identity.run_id) or frame.identity.step_id!=State.STEP or not State.integer(frame.identity.revision):return denied
 var profile_ref:Dictionary=frame.owner._profile
 var entry_ref:Dictionary=profile_ref.quest_loot.entries[State.STEP]
 var serial:int=b.quest_save_serial
 var timer_before:Dictionary=admission_timer_snapshot()
 # Local only: do not call now(), which writes last_ms after its callback.
 var sampled=frame.clock.call()
 if not admission_owner(b,frame) or clock!=frame.clock or not is_same(frame.owner._profile,profile_ref) or not is_same(frame.owner._profile.quest_loot.entries.get(State.STEP),entry_ref):return denied
 if frame.owner.snapshot()!=opened.profile or b.last_saved_payload!=opened.payload or b.quest_save_serial!=serial or entry_ref!=entry or admission_timer_snapshot()!=timer_before:return denied
 # Still the same owner: retain original invalid/backward-clock rejection.
 if not State.integer(sampled,0,State.MAX_MSEC):blocked=true;return denied
 var current:int=int(sampled)
 if last_ms>=0 and current<last_ms:blocked=true;return denied
 # No Callable/save/emit from this point through ready installation/return.
 last_ms=current
 lifetime=RefCounted.new()
 heartbeat_wall_ms=-1;heartbeat_call=null
 key=State.STEP;binding=frame.identity.duplicate(true)
 span={"budget_id":entry.budget_id,"generation":entry.generation,"issued_seq":entry.issued_seq}
 anchor_ms=current;base_used_ms=int(entry.used_ms);frozen=false;blocked=false;storage_paused=false
 cached_sample={"lifetime":lifetime,"span":span.duplicate(true),"used_ms":base_used_ms}
 progress_stamp={"lifetime":lifetime,"span":span.duplicate(true),"ms":current,"used_ms":base_used_ms}
 frame.lifetime=lifetime
 if not frame.continuation.is_empty():
  frame.continuation.expected_lifetime=lifetime
  frame.continuation.expected_deadline=current
 frame.ready_token=RefCounted.new()
 if not open_obligation.is_empty() and is_same(open_obligation.capability,frame.capability):open_obligation.lifetime=lifetime
 ready_frame=frame.duplicate()
 ready_frame.erase("terrain")
 ready_frame.erase("continuation") # Never retain a consumed call envelope.
 next_attempt_ms=last_ms
 return {"ok":true,"persisted":true,"capability":admission,"lifetime":lifetime,"identity":frame.identity.duplicate(true),"ready_token":frame.ready_token,"open_anchor_ms":current,"continuation_call":frame.continuation.get("call"),"candidate_payload":opened.payload,"candidate_serial":serial}

# P3: one passive sample after the original automation tick, inside one real
# outer Backend._process generation. The invocation frame is local and holds
# strong owners only until the injected clock returns; no owner backlink is
# retained by the timer, receipt, progress stamp or automation scope.
func heartbeat_normal_process(b,generation:int,entry_epoch:int)->void:
 # Cheap process/timer gates run every frame; no map scan, JSON parse or
 # profile validation is performed until this exact generation is due.
 if not is_same(b.quest_loot,self) or generation<=0:return
 if b._process_depth!=1 or b._dispatch_boundary_depth!=1 or b._observer_depth!=0 or b._flush_depth!=0 or b._depth!=1:return
 if b._normal_process_generation!=generation or b._normal_process_entry_epoch!=entry_epoch or b._dispatch_epoch!=entry_epoch:return
 if heartbeat_call!=null or heartbeat_generation==generation:return
 if anchor_ms<0 or key!=State.STEP or frozen or blocked or storage_paused or battle_receipt.is_empty():return
 var wall:int=Time.get_ticks_msec()
 if wall<0 or wall>State.MAX_MSEC:return
 if heartbeat_wall_ms>=0 and (wall<heartbeat_wall_ms or wall-heartbeat_wall_ms<HEARTBEAT_INTERVAL_MS):return
 if not clock.is_valid():return
 # Full authority/profile/ledger checks are expensive, so do them only after
 # cheap gates pass. They are read-only and contain no Callable or publication.
 if not heartbeat_owner_current(b,generation,entry_epoch):return
 var call:RefCounted=RefCounted.new()
 var expected_lifetime:RefCounted=lifetime
 heartbeat_call=call
 heartbeat_wall_ms=wall
 heartbeat_generation=generation
 var frame:Dictionary=capture_heartbeat_frame(b,generation,entry_epoch,call,expected_lifetime,wall)
 var sampled=clock.call()
 if not heartbeat_frame_current(b,frame):
  retire_heartbeat_call(call)
  return
 # A bad/rewound sample rejects this observation only. It never poisons the
 # settlement clock, freezes/stops the runner, or substitutes a cached cutoff.
 if not State.integer(sampled,0,State.MAX_MSEC):
  retire_heartbeat_call(call)
  return
 var current:int=int(sampled)
 if current<last_ms or current<anchor_ms or base_used_ms>State.MAX_MSEC-(current-anchor_ms):
  retire_heartbeat_call(call)
  return
 var total:int=base_used_ms+current-anchor_ms
 # The full post-clock frame check above is the final owner gate. Only pure
 # type/range arithmetic follows it; no Callable or publish can interleave.
 last_ms=current
 cached_sample={"lifetime":expected_lifetime,"span":span.duplicate(true),"used_ms":total}
 var stamp:Dictionary=progress_stamp
 var publish_progress:bool=is_same(stamp.get("lifetime"),expected_lifetime) and stamp.get("span",{})==span and State.integer(stamp.get("ms"),0,State.MAX_MSEC) and State.integer(stamp.get("used_ms"),0,State.MAX_MSEC) and current>=int(stamp.ms) and current-int(stamp.ms)>=PROGRESS_INTERVAL_MS and total>int(stamp.used_ms)
 if publish_progress:
  progress_stamp={"lifetime":expected_lifetime,"span":span.duplicate(true),"ms":current,"used_ms":total}
  # _publish snapshots/publishes only; no Session save or storage write.
  # Install the stamp first, and queue the event under the existing process
  # depth so observers cannot reenter a half-installed sample.
  b.publish()
 retire_heartbeat_call(call)

func heartbeat_owner_current(b,generation:int,entry_epoch:int)->bool:
 if not is_same(b.quest_loot,self) or generation<=0:return false
 if b._process_depth!=1 or b._dispatch_boundary_depth!=1 or b._observer_depth!=0 or b._flush_depth!=0 or b._depth!=1:return false
 if b._normal_process_generation!=generation or b._normal_process_entry_epoch!=entry_epoch or b._dispatch_epoch!=entry_epoch:return false
 if b.save_path.is_empty() or b.stationary.running or not b.original_quests.pending.is_empty():return false
 if anchor_ms<0 or key!=State.STEP or frozen or blocked or storage_paused or battle_receipt.is_empty():return false
 var q=b.quest_auto
 var auto=b.automation
 if not q.running or not q.internal or q.detached or q.restored or not q.owns_battle or q.phase!="loot_battle" or q.step.get("action")!="loot" or not Sources.same(q.step,Sources.step()) or q.identity.checkpoint()!=binding:return false
 if not auto.running or not auto.single_battle or auto.settings.get("preset")!="attack" or not auto.settings.get("compact",false) or not auto.compact_active:return false
 if auto.clone_override_active or auto.hunt_running or auto.flow_active() or not auto.training_borrow_pending.is_empty():return false
 if auto.loot_scope.is_empty():return false
 var scope:Dictionary=auto.loot_scope
 var capability=scope.get("capability")
 if not capability is RefCounted or not is_instance_valid(capability) or not is_same(auto.start_lifetime,scope.get("token")) or not is_same(scope.get("lifetime"),lifetime):return false
 if scope.get("path")!=b.save_path or scope.get("receipt",{})!=battle_receipt:return false
 if not scope_owner_matches(scope,"session",b.session) or not scope_owner_matches(scope,"battle",b.battle) or not scope_owner_matches(scope,"automation",auto) or not scope_owner_matches(scope,"runner",q) or not scope_owner_matches(scope,"timer",self):return false
 var authority:Dictionary=scope.get("authority",{})
 if authority.get("identity",{})!=binding or authority.get("connection")!=q.connection or authority.get("client")!=q.client:return false
 if owner_session_id!=b.session.get_instance_id() or not b.battle_open:return false
 var pending:Dictionary=b.session._pending
 var battle_state:Dictionary=b.battle._state
 var battle_id:=str(battle_receipt.get("ledger",{}).get("battle_id",""))
 if battle_id.is_empty() or str(scope.get("battle_id",""))!=battle_id or not battle_state.get("active",false) or str(battle_state.get("battle_id",""))!=battle_id or str(b.battle_state.get("battle_id",""))!=battle_id:return false
 var source:Dictionary=battle_receipt.get("source",{})
 if auto.position_map!=100 or b.encounter_catalog.area_at(auto.position_map,auto.position_cell).get("id")!=56 or source.get("map")!=100 or source.get("area")!=56 or source.get("cell")!=[auto.position_cell.x,auto.position_cell.y]:return false
 if pending.get("party",false) or pending.get("capture_only",false) or pending.has("training_borrow") or pending.has("quest_guard") or not pending.get("source_encounter",false):return false
 if pending.get("quest_loot_receipt",{})!=battle_receipt or str(pending.get("battle_id",""))!=battle_id or pending.get("wild_drop_source",{})!=battle_receipt.get("source",{}):return false
 if not b.session._loot_settlement.is_empty():return false
 var ledger_value=b.session._profile.get("quest_loot",{})
 if not ledger_value is Dictionary:return false
 var ledger:Dictionary=ledger_value
 if not State.valid(ledger) or not same_span(ledger) or not ledger.entries[key].open_span or ledger.entries[key].recovery_blocked:return false
 var saved=JSON.parse_string(b.last_saved_payload)
 if not saved is Dictionary or not b.session._valid_profile(saved):return false
 var saved_ledger_value=saved.get("quest_loot",{})
 if not saved_ledger_value is Dictionary:return false
 var saved_ledger:Dictionary=saved_ledger_value
 return State.valid(saved_ledger) and same_span(saved_ledger) and saved_ledger.entries[key].open_span and not saved_ledger.entries[key].recovery_blocked

func capture_heartbeat_frame(b,generation:int,entry_epoch:int,call:RefCounted,expected_lifetime:RefCounted,wall:int)->Dictionary:
 var q=b.quest_auto
 var auto=b.automation
 return {"generation":generation,"entry_epoch":entry_epoch,"dispatch_epoch":b._dispatch_epoch,"call":call,"lifetime":expected_lifetime,"clock":clock,"timer":heartbeat_timer_snapshot(),"span":span.duplicate(true),"binding":binding.duplicate(true),"receipt":battle_receipt.duplicate(true),"owner_session_id":owner_session_id,"session":b.session,"path":b.save_path,"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"pending_ref":b.session._pending,"pending":b.session._pending.duplicate(true),"settlement":b.session._loot_settlement.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"backend_rev":b.rev,"queue":b._queue.duplicate(true),"dispatch_dirty":b._dispatch_dirty,"battle":b.battle,"battle_state":b.battle._state.duplicate(true),"backend_battle_state":b.battle_state.duplicate(true),"battle_open":b.battle_open,"runner":q,"identity_object":q.identity,"identity":q.identity.checkpoint(),"connection":q.connection,"client":q.client,"phase":q.phase,"step":q.step.duplicate(true),"visit_guard":b.quest_visit_guard,"party_guard":b.party_guard,"stationary_running":b.stationary.running,"original_pending":b.original_quests.pending.duplicate(true),"position_map":auto.position_map,"position_cell":auto.position_cell,"automation":auto,"auto_scope":auto.loot_scope.duplicate(true),"auto_token":auto.start_lifetime,"auto_running":auto.running,"compact_active":auto.compact_active,"wall":wall}

func heartbeat_timer_snapshot()->Dictionary:
 # open_obligation may retain the one map grid used for E1 validation. The
 # heartbeat checks its authority fields without copying that large grid.
 var open:Dictionary={}
 for field in open_obligation:
  if field=="terrain":continue
  var value=open_obligation[field]
  open[field]=value.duplicate(true) if value is Dictionary or value is Array else value
 return {"key":key,"binding":binding.duplicate(true),"span":span.duplicate(true),"anchor_ms":anchor_ms,"base_used_ms":base_used_ms,"last_ms":last_ms,"blocked":blocked,"frozen":frozen,"frozen_ms":frozen_ms,"storage_paused":storage_paused,"lifetime":lifetime,"cached_sample":cached_sample.duplicate(true),"progress_stamp":progress_stamp.duplicate(true),"heartbeat_wall_ms":heartbeat_wall_ms,"heartbeat_generation":heartbeat_generation,"heartbeat_call":heartbeat_call,"admission":admission,"ready_frame":ready_frame.duplicate(true),"next_attempt_ms":next_attempt_ms,"last_attempt_ms":last_attempt_ms,"attempt_frame":attempt_frame.duplicate(true),"attempt_call":attempt_call,"battle_receipt":battle_receipt.duplicate(true),"open_obligation":open,"close_pending":close_pending.duplicate(true),"cancelled_battle":cancelled_battle.duplicate(true),"followup":followup.duplicate(true),"consume_call":consume_call}

func heartbeat_frame_current(b,frame:Dictionary)->bool:
 if frame.is_empty() or not is_same(heartbeat_call,frame.call) or not is_same(lifetime,frame.lifetime) or clock!=frame.clock:return false
 if not heartbeat_owner_current(b,int(frame.generation),int(frame.entry_epoch)):return false
 var q=b.quest_auto
 var auto=b.automation
 if not is_same(b.session,frame.session) or b.save_path!=frame.path or not is_same(b.session._profile,frame.profile_ref) or b.session._profile!=frame.profile:return false
 if not is_same(b.session._pending,frame.pending_ref) or b.session._pending!=frame.pending or b.session._loot_settlement!=frame.settlement:return false
 if b.last_saved_payload!=frame.cache or b.quest_save_serial!=frame.serial or b.rev!=frame.backend_rev or b._queue!=frame.queue or b._dispatch_dirty!=frame.dispatch_dirty:return false
 if not is_same(b.battle,frame.battle) or b.battle._state!=frame.battle_state or b.battle_state!=frame.backend_battle_state or b.battle_open!=frame.battle_open:return false
 if not is_same(q,frame.runner) or not is_same(q.identity,frame.identity_object) or q.identity.checkpoint()!=frame.identity or q.connection!=frame.connection or q.client!=frame.client or q.phase!=frame.phase or q.step!=frame.step:return false
 if not is_same(auto,frame.automation) or auto.loot_scope!=frame.auto_scope or not is_same(auto.start_lifetime,frame.auto_token) or auto.running!=frame.auto_running or auto.compact_active!=frame.compact_active:return false
 if b.quest_visit_guard!=frame.visit_guard or b.party_guard!=frame.party_guard or b.stationary.running!=frame.stationary_running or b.original_quests.pending!=frame.original_pending:return false
 if auto.position_map!=frame.position_map or auto.position_cell!=frame.position_cell:return false
 if span!=frame.span or binding!=frame.binding or battle_receipt!=frame.receipt or owner_session_id!=frame.owner_session_id:return false
 var timer:Dictionary=heartbeat_timer_snapshot()
 return timer==frame.timer

func retire_heartbeat_call(call:RefCounted)->void:
 if is_same(heartbeat_call,call):heartbeat_call=null

# E2: one explicit internal drive call, never a loop or a public RPC.
const ATTEMPT_INTERVAL_MS=500
var ready_frame:Dictionary={}
var attempt_frame:Dictionary={}
var attempt_call:RefCounted
var next_attempt_ms:=-1
var last_attempt_ms:=-1
func attempt_owned(b,frame:Dictionary)->bool:
 return is_same(attempt_call,frame.get("attempt_call")) and admission_owner(b,frame)
func retire_attempt_frame(frame:Dictionary,call:RefCounted)->void:
 if is_same(attempt_frame,frame) and is_same(attempt_frame.get("attempt_call"),call):attempt_frame={}
func attempt_once(b)->Dictionary:
 if ready_frame.has("continuation_gate") and not b.continuation_dispatch_ready(ready_frame.continuation_gate):return {"ok":true,"attempted":false,"reason":"等待后续正常处理代。"}
 # Acquire BEFORE host guards or clock Callables. Every inner early return
 # unwinds through this one identity-checked retirement boundary.
 if attempt_call!=null or not attempt_frame.is_empty():return {"ok":false,"attempted":false,"_sample_stale":true,"reason":"刷物尝试已有调用。"}
 if ready_frame.is_empty():return {"ok":false,"attempted":false,"reason":"刷物尝试未就绪。"}
 var call:=RefCounted.new()
 attempt_call=call
 var frame:Dictionary=ready_frame.duplicate()
 frame.attempt_call=call
 var fence:Dictionary=capture_attempt_sample(b,frame)
 var result:Dictionary=attempt_locked(b,frame,fence)
 if not result.get("ok",false) and not sample_attempt_current(b,fence,true):result._sample_stale=true
 retire_attempt_frame(frame,call)
 if is_same(attempt_call,call):attempt_call=null
 return result
func attempt_locked(b,frame:Dictionary,fence:Dictionary)->Dictionary:
 if not attempt_owned(b,frame) or binding!=frame.identity or blocked or frozen or anchor_ms<0:return State.denied("刷物尝试归属已失效。")
 var reason:=admission_error(b,frame)
 if not sample_attempt_current(b,fence,true):return {"ok":false,"_sample_stale":true,"reason":"准入回调改变原尝试。"}
 if not reason.is_empty():return State.denied(reason)
 var planned:Dictionary=JewelPlan.select(b,Sources.matches_backend)
 if planned.get("status")!="step" or not Sources.same(planned.get("step"),frame.step):return State.denied("目标或来源条件已变化。")
 var ledger:Dictionary=frame.owner._profile.quest_loot
 var saved=JSON.parse_string(b.last_saved_payload)
 if not saved is Dictionary or not frame.owner._valid_profile(saved) or frame.owner._normalize_numbers(saved)!=frame.owner.snapshot():return State.denied("刷物尝试前真实保存基线不匹配。")
 if not same_span(ledger) or ledger.recovery_blocked or not ledger.entries[State.STEP].open_span or ledger.entries[State.STEP].recovery_blocked:return State.denied("当前持久时段不能尝试。")
 # This explicit scheduler sample is outside snapshot. Sample failures never roll.
 var sampled:Dictionary=sample_attempt_sealed(b,frame,fence)
 if not sampled.get("ok",false):return {"ok":false,"reason":"刷物活跃采样或执行归属无效。","_sample_stale":sampled.get("stale",false)}
 var sample:Dictionary=sampled.seal
 if cached_sample.used_ms>=ledger.entries[State.STEP].limit_ms:return State.denied("本步预算已到限，停止新尝试。")
 if last_ms<next_attempt_ms:return {"ok":true,"attempted":false,"reason":"等待下一逻辑步。","_progress_sample":sample}
 # No callback occurs between this final complete guard and field_step entry.
 reason=admission_error(b,frame)
 if not sample_attempt_current(b,sample,true):return {"ok":false,"reason":"采样后原归属已变化。","_sample_stale":true}
 if not reason.is_empty():return State.denied(reason)
 if last_ms>State.MAX_MSEC-ATTEMPT_INTERVAL_MS:return State.denied("尝试时钟截止超出合法范围。")
 last_attempt_ms=last_ms
 next_attempt_ms=last_attempt_ms+ATTEMPT_INTERVAL_MS
 if ready_frame.has("continuation_gate"):
  ready_frame.continuation_gate.generation=b.continuation_dispatch_checkpoint().generation
 sample.timer=progress_timer_snapshot() # exact local cadence writes, before any callback
 fence.timer=sample.timer
 attempt_frame=frame
 var reply:Dictionary=b._cmd_field_step({"map_id":frame.map_id,"cell":[frame.cell.x,frame.cell.y],"encounter":true})
 retire_attempt_frame(frame,frame.attempt_call)
 # field_step may already have rolled and published a battle. Never undo it.
 var battle_happened:bool=bool(reply.get("battle",false))
 if not attempt_owned(b,frame):return {"ok":false,"attempted":true,"battle":battle_happened,"reason":"原尝试已发生，旧执行归属不再继续。"}
 if not battle_happened:return {"ok":bool(reply.get("ok",false)),"attempted":true,"battle":false,"hit":bool(reply.get("hit",false)),"_progress_sample":sample}
 var pending:Dictionary=frame.owner._pending
 var battle_id:String=str(pending.get("battle_id",""))
 if battle_id.is_empty() or battle_receipt.is_empty() or pending.get("quest_loot_receipt",{})!=battle_receipt or str(b.battle_state.get("battle_id",""))!=battle_id or not b.battle_open:return {"ok":false,"attempted":true,"battle":true,"reason":"原战斗已发生，凭据变化后需手动处理。"}
 var q=frame.runner
 q.owns_battle=true
 q.phase="loot_battle"
 frame.phase="loot_battle"
 b.emit_event({"type":"auto_status","status":b.automation.status()})
 if not attempt_owned(b,frame) or str(frame.owner._pending.get("battle_id",""))!=battle_id:return {"ok":false,"attempted":true,"battle":true,"reason":"战斗发布后旧执行已取消。"}
 # Compact flag must be set BEFORE automation.start's synchronous publication.
 # Its existing single_battle runner stops after this original battle only.
 b.automation.compact_active=true
 var execution:Dictionary=make_auto_context(b,frame)
 var started:Dictionary=b.automation.start({"kind":"battle","settings":{"preset":"attack","compact":true}},execution)
 if not attempt_owned(b,frame):return {"ok":false,"attempted":true,"battle":true,"reason":"战斗启动发布后旧执行已取消。"}
 return {"ok":bool(started.get("ok",false)),"attempted":true,"battle":true,"battle_id":battle_id}

# E3a: only idle spans. Pending/actual battle cancellation is a separate slice.
var open_obligation:Dictionary={}
var close_pending:Dictionary={}
func _admission_written(payload:String,b,frame:Dictionary,operation:String)->void:
 var continuation:Dictionary=frame.get("continuation",{})
 # Bind the installed candidate object before Backend's first observer callback.
 if operation=="open" and not continuation.is_empty() and continuation_current(b,continuation) and payload==continuation.get("open_payload","") and frame.owner.snapshot()==continuation.get("expected_open",{}):
  continuation.open_profile_ref=frame.owner._profile
 # Session installed the immutable candidate before this callback. Capture its
 # exact open obligation BEFORE the backend observer can synchronously cancel.
 if operation=="open" and admission_owner(b,frame):
  var parsed=JSON.parse_string(payload)
  if parsed is Dictionary and frame.owner._valid_profile(parsed):
   var committed:Dictionary=frame.owner._normalize_numbers(parsed)
   if committed==frame.owner.snapshot() and committed.quest_loot.entries[State.STEP].open_span:
    open_obligation=frame.duplicate()
    open_obligation.erase("continuation")
    open_obligation.entry=State.identity(committed.quest_loot.entries[State.STEP])
 b._loot_settlement_written(payload,frame.owner,frame.path)
func idle_close_context(b,ticket:Dictionary)->bool:
 if ticket.is_empty():return false
 var q=b.quest_auto
 return is_same(b.quest_loot,self) and is_same(b.session,ticket.owner) and b.save_path==ticket.path and is_same(q,ticket.runner) and is_same(lifetime,ticket.lifetime) and q.identity.checkpoint()==ticket.expected_identity and q.connection==ticket.expected_connection and q.client==ticket.expected_client and not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty()
func idle_close_owner(b,ticket:Dictionary)->bool:
 return is_same(close_pending,ticket) and idle_close_context(b,ticket)
func capture_idle_close(b)->Dictionary:
 revoke_followup(b)
 var q=b.quest_auto
 if not close_pending.is_empty():return close_pending if idle_close_owner(b,close_pending) else {}
 if not q.running or q.step.get("id")!=State.STEP or open_obligation.is_empty():return {}
 if b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or not battle_receipt.is_empty():return {}
 var obligation:Dictionary=open_obligation
 if not is_same(obligation.owner,b.session) or obligation.path!=b.save_path or not is_same(obligation.runner,q) or obligation.identity!=q.identity.checkpoint() or not is_same(obligation.lifetime,lifetime):return {}
 if not State.valid(b.session._profile.get("quest_loot",{})):return {}
 var entry:Dictionary=b.session._profile.quest_loot.entries.get(State.STEP,{})
 if not State.valid_entry(entry) or not entry.open_span or State.identity(entry)!=obligation.entry:return {}
 var ticket:Dictionary={"owner":b.session,"path":b.save_path,"runner":q,"lifetime":lifetime,"token":RefCounted.new(),"expected_identity":q.identity.checkpoint(),"expected_connection":q.connection,"expected_client":q.client,"entry":State.identity(entry),"used_ms":int(entry.used_ms),"profile":b.session.snapshot(),"sample_ok":false}
 close_pending=ticket
 # Revoke new attempts BEFORE any clock/sample/save callback.
 ready_frame={}
 initial_e2={}
 admission=RefCounted.new()
 if anchor_ms>=0:
  ticket.sample_ok=pause_storage_for(ticket.lifetime)
  if ticket.sample_ok and idle_close_owner(b,ticket):ticket.used_ms=int(cached_sample.used_ms)
 else:
  # E1 open committed, but its observer cancelled before timer startup.
  ticket.sample_ok=true
 return ticket
func prepare_idle_revocation(b,ticket:Dictionary,operation:String)->bool:
 # Freeze the ONLY allowed successor before the runner's pure local mutation.
 # Never learn a successor identity from a later callback's current runner.
 if not idle_close_owner(b,ticket) or operation not in ["stop","detach"]:return false
 var expected:Dictionary=ticket.expected_identity.duplicate(true)
 if operation=="stop":expected.revision+=1
 ticket.expected_identity=expected
 if operation=="detach":ticket.expected_connection=-1;ticket.expected_client=""
 return true
func finish_idle_close(b,ticket:Dictionary)->Dictionary:
 if ticket.is_empty():return {"ok":true,"idle":false}
 if not idle_close_owner(b,ticket):return State.denied("旧关闭调用归属已改变。")
 return retry_idle_close(b,ticket.token)
func retry_idle_close(b,token:RefCounted)->Dictionary:
 # Internal repair entry only. No settings-only writer, RPC or timer resample.
 var ticket:Dictionary=close_pending
 if ticket.is_empty() or not is_same(ticket.token,token) or not idle_close_owner(b,ticket) or not ticket.sample_ok:return State.denied("关闭预算义务已失效。")
 if b.session.snapshot()!=ticket.profile:return State.denied("关闭前完整角色状态已变化。")
 var result:Dictionary=ticket.owner.commit_loot_idle_transition(ticket.profile,ticket.profile.quest_loot,"close",{"step_id":State.STEP,"expected_entry":ticket.entry,"total_used_ms":ticket.used_ms},ticket.path,b._loot_settlement_written.bind(ticket.owner,ticket.path))
 if not result.get("ok",false):return {"ok":false,"persisted":false,"reason":"预算关闭保存失败，暂停等待修复。"}
 # Never reinstall the return candidate/cache over a reentrant later save.
 var same:bool=idle_close_owner(b,ticket)
 var retired:bool=false
 if same and b.session._profile.quest_loot==result.profile.quest_loot:
  retired=true
  if anchor_ms>=0:accept_commit(result.profile.quest_loot)
  if is_same(close_pending,ticket):close_pending={}
  if not open_obligation.is_empty() and is_same(open_obligation.lifetime,ticket.lifetime):open_obligation={}
 # The close is already durable. Resume location/side-file I/O is a second
 # original transaction, only on the exact returned candidate, never on an
 # observer's newer profile/run. Failure leaves a safely CLOSED durable span.
 var resume_attempted:bool=false
 if retired and ticket.get("keep_resume_after_close",false) and idle_close_context(b,ticket) and b.session.snapshot()==result.profile:
  resume_attempted=true
  b.keep_resume_file()
 return {"ok":true,"persisted":true,"retired":retired,"resume_attempted":resume_attempted,"profile":result.profile}

# E3b draft: cancellation owns only an already-issued original battle receipt.
var cancelled_battle:Dictionary={}
func cancelled_battle_owner(b,ticket:Dictionary)->bool:
 if ticket.is_empty():return false
 var q=b.quest_auto
 if not ticket.auto_scope.is_empty() and not is_same(ticket.automation.start_lifetime,ticket.auto_token):return false
 return is_same(b.quest_loot,self) and is_same(b.session,ticket.session) and b.save_path==ticket.path and is_same(b.battle,ticket.battle) and is_same(b.automation,ticket.automation) and is_same(q,ticket.runner) and is_same(lifetime,ticket.lifetime) and q.identity.checkpoint()==ticket.identity and q.connection==ticket.connection and q.client==ticket.client
func capture_battle_cancel(b)->Dictionary:
 revoke_followup(b)
 var q=b.quest_auto
 if not cancelled_battle.is_empty():
  return cancelled_battle if cancelled_battle_owner(b,cancelled_battle) and b.session._pending.get("quest_loot_receipt",{})==cancelled_battle.receipt else {}
 if not q.running or q.identity.checkpoint()!=binding or q.step.get("id")!=State.STEP or owner_session_id!=b.session.get_instance_id() or battle_receipt.is_empty():return {}
 var pending:Dictionary=b.session._pending
 if not b.battle_open or pending.get("quest_loot_receipt",{})!=battle_receipt or pending.get("wild_drop_source",{})!=battle_receipt.source or str(pending.get("battle_id",""))!=str(battle_receipt.ledger.battle_id) or str(b.battle.snapshot().get("battle_id",""))!=str(pending.get("battle_id","")):return {}
 if pending.get("party",false) or pending.get("capture_only",false) or pending.has("training_borrow") or pending.has("quest_guard") or not same_span(b.session._profile.get("quest_loot",{})):return {}
 var auto=b.automation
 # Never keep a foreign multi-battle runner alive under this receipt.
 if auto.running and (not auto.single_battle or auto.settings.get("preset")!="attack" or not auto.settings.get("compact",false) or auto.clone_override_active or auto.hunt_running or auto.flow_active() or not auto.training_borrow_pending.is_empty()):return {}
 cancelled_battle={"session":b.session,"path":b.save_path,"battle":b.battle,"automation":auto,"runner":q,"lifetime":lifetime,"identity":q.identity.checkpoint(),"connection":q.connection,"client":q.client,"receipt":battle_receipt.duplicate(true),"auto_token":auto.start_lifetime,"auto_scope":auto._loot_frame()}
 ready_frame={};admission=RefCounted.new()
 # Do not pause/sample: current battle remains active through final settlement.
 return cancelled_battle
func prepare_battle_revocation(b,ticket:Dictionary,operation:String)->bool:
 if not cancelled_battle_owner(b,ticket) or operation not in ["stop","detach"]:return false
 if operation=="stop":ticket.identity.revision+=1
 else:ticket.connection=-1;ticket.client=""
 var scope:Dictionary=ticket.auto_scope
 if not scope.is_empty() and is_same(ticket.automation.start_lifetime,ticket.auto_token):
  scope.authority.identity=ticket.identity.duplicate(true)
  scope.authority.connection=ticket.connection;scope.authority.client=ticket.client
 return true
func retire_cancelled_battle(b,expected_lifetime:RefCounted,receipt:Dictionary)->void:
 var ticket:Dictionary=cancelled_battle
 if ticket.is_empty() or not is_same(ticket.lifetime,expected_lifetime) or ticket.receipt!=receipt or not cancelled_battle_owner(b,ticket):return
 # The immutable original battle candidate is already committed. No replan or
 # new span is opened; a detached runner also becomes stopped at this boundary.
 ticket.runner.running=false;ticket.runner.owns_battle=false
 ticket.runner.phase="stopped"
 if is_same(cancelled_battle,ticket):cancelled_battle={}

func make_auto_context(b,frame:Dictionary)->Dictionary:
 # Stored by automation and copied into cancellation tickets. Owner backlinks
 # must stay weak in ALL copies; a strong self/timer link creates persistent cycles.
 return {"capability":RefCounted.new(),"session":weakref(b.session),"path":b.save_path,"battle":weakref(b.battle),"battle_id":str(b.session._pending.get("battle_id","")),"automation":weakref(b.automation),"runner":weakref(b.quest_auto),"timer":weakref(self),"lifetime":lifetime,"receipt":battle_receipt.duplicate(true),"authority":{"identity":frame.identity.duplicate(true),"connection":frame.connection,"client":frame.client}}
static func scope_owner_matches(frame:Dictionary,key:String,expected:Object)->bool:
 if not is_instance_valid(expected):return false
 var reference=frame.get(key)
 if not reference is WeakRef:return false
 # Local resolution holds the exact live object for this comparison only.
 # An expired weak reference cannot resolve a replacement or an ObjectID reuse.
 var owner=reference.get_ref()
 return is_instance_valid(owner) and is_same(owner,expected)
func auto_context_current(b,frame:Dictionary)->bool:
 if frame.is_empty():return false
 var q=b.quest_auto;var expected:Dictionary=frame.authority
 return is_same(b.quest_loot,self) and scope_owner_matches(frame,"timer",self) and is_same(lifetime,frame.lifetime) and scope_owner_matches(frame,"session",b.session) and b.save_path==frame.path and scope_owner_matches(frame,"battle",b.battle) and str(b.battle.snapshot().get("battle_id",""))==frame.battle_id and scope_owner_matches(frame,"automation",b.automation) and scope_owner_matches(frame,"runner",q) and q.identity.checkpoint()==expected.identity and q.connection==expected.connection and q.client==expected.client
func freeze_failed_auto(b,frame:Dictionary)->void:
 if not is_same(b.quest_loot,self) or not is_same(lifetime,frame.lifetime) or not is_same(b.automation,frame.automation) or not is_same(b.automation.start_lifetime,frame.auto_token):return
 var auto=b.automation;var scope:Dictionary=frame.auto_scope
 if scope.is_empty() or not auto._loot_current(scope) or scope.receipt!=frame.receipt or b.session._pending.get("quest_loot_receipt",{})!=frame.receipt:return
 # Disarm compact FIRST: original stop must never close an uncommitted battle.
 # This exact E2 runner has no clone/flow obligation capable of early publish.
 if auto.clone_override_active or auto.hunt_running or auto.flow_active() or not auto.training_borrow_pending.is_empty():return
 ready_frame={};admission=RefCounted.new()
 auto.compact_active=false
 auto.stop("刷物战结算未保存，停止自动战斗等待修复。")

# C1 only: evidence for a later scheduler, never a command to open/roll a span.
# Stored owners are weak; local backend settlement frames own their lifetimes.
var followup:Dictionary={}
func capture_followup(b,receipt:Dictionary)->Dictionary:
 var q=b.quest_auto;var auto=b.automation
 var scope:Dictionary=auto._loot_frame()
 if not q.running or not q.internal or q.detached or q.restored or q.phase!="loot_battle" or not auto._loot_current(scope) or scope.is_empty() or scope.receipt!=receipt:return {}
 if not Sources.same(q.step,Sources.step()) or str(b.battle.snapshot().get("outcome",""))!="win":return {}
 return {"token":RefCounted.new(),"session":weakref(b.session),"path":b.save_path,"battle":weakref(b.battle),"battle_id":str(receipt.ledger.battle_id),"automation":weakref(auto),"runner":weakref(q),"identity_object":weakref(q.identity),"timer":weakref(self),"lifetime":lifetime,"auto_token":auto.start_lifetime,"scope_capability":scope.capability,"identity":q.identity.checkpoint(),"connection":q.connection,"client":q.client,"step":q.step.duplicate(true),"map_id":auto.position_map,"cell":auto.position_cell,"serial":b.quest_save_serial,"receipt":receipt.duplicate(true),"closed":false,"scope_retired":false,"clock":clock,"last_attempt_ms":last_attempt_ms,"deadline_ms":next_attempt_ms}
func followup_owner(b,ticket:Dictionary)->bool:
 if ticket.is_empty() or not is_same(b.quest_loot,self):return false
 var q=b.quest_auto;var auto=b.automation
 for pair in [["session",b.session],["battle",b.battle],["automation",auto],["runner",q],["identity_object",q.identity],["timer",self]]:
  if not scope_owner_matches(ticket,pair[0],pair[1]):return false
 return b.save_path==ticket.path and is_same(lifetime,ticket.lifetime) and is_same(auto.start_lifetime,ticket.auto_token) and str(b.battle.snapshot().get("battle_id",""))==ticket.battle_id and q.running and q.internal and not q.detached and not q.restored and q.phase=="loot_battle" and q.identity.checkpoint()==ticket.identity and q.connection==ticket.connection and q.client==ticket.client and q.step==ticket.step and auto.position_map==ticket.map_id and auto.position_cell==ticket.cell
func record_followup(b,ticket:Dictionary,saved:Dictionary,receipt:Dictionary)->void:
 # The actual immutable successful candidate/receipt is the fact. Serial only
 # rejects additional intervening saves, including same-payload save calls.
 if not saved.get("ok",false) or not followup_owner(b,ticket) or receipt!=ticket.receipt:return
 if b.quest_save_serial!=ticket.serial+1 or b.session.snapshot()!=saved.profile or b.last_saved_payload!=saved.payload or not b.session._pending.is_empty():return
 var entry:Dictionary=saved.profile.quest_loot.entries.get(State.STEP,{})
 if not State.valid_entry(entry) or entry.open_span or entry.budget_id!=receipt.ledger.budget_id or entry.generation!=receipt.ledger.generation or not ticket.battle_id in saved.profile.completed_battles:return
 ticket.profile=saved.profile.duplicate(true);ticket.payload=saved.payload;ticket.serial=b.quest_save_serial
 followup=ticket
func followup_current(b,ticket:Dictionary)->bool:
 return is_same(followup,ticket) and followup_owner(b,ticket) and ticket.has("profile") and b.quest_save_serial==ticket.serial and b.session.snapshot()==ticket.profile and b.last_saved_payload==ticket.payload and b.session._pending.is_empty()
func revoke_followup(b)->void:
 var ticket:Dictionary=followup
 # Called before cancellation's local mutations; stale old tickets are also
 # discarded, never used to stop/clear/save a newer runner.
 if not ticket.is_empty() and is_same(b.quest_loot,self) and is_same(followup,ticket):followup={}
func capture_followup_close(b)->Dictionary:
 var ticket:Dictionary=followup
 if ticket.is_empty():return {}
 if not followup_current(b,ticket) or ticket.closed or not b.battle_open or b.battle.snapshot().active or not b.battle_state.get("settled",false):
  reject_followup_execution(b,ticket)
  return {}
 return ticket
func record_followup_close(b,ticket:Dictionary,saved:bool)->void:
 if ticket.is_empty() or not is_same(followup,ticket):return
 # This is the return of close_battle's one existing save, before any publish.
 if not saved or not followup_owner(b,ticket) or b.battle_open or not b.session._pending.is_empty() or b.quest_save_serial!=ticket.serial+1 or b.session.snapshot()!=ticket.profile or b.last_saved_payload!=ticket.payload:
  reject_followup_execution(b,ticket)
  return
 ticket.serial=b.quest_save_serial;ticket.closed=true
 ticket.dispatch_barrier=b.continuation_dispatch_checkpoint()
func followup_status(b)->Dictionary:
 var ticket:Dictionary=followup
 if ticket.is_empty():return {}
 if not followup_current(b,ticket):
  reject_followup_execution(b,ticket)
  return {}
 # Does NOT mean callbacks were flushed. C2 must supply a real dispatch barrier.
 return {"token":ticket.token,"closed":ticket.closed,"auto_stopped":not b.automation.running,"battle_id":ticket.battle_id}
func retire_followup_scope(b,token:RefCounted)->bool:
 var ticket:Dictionary=followup
 if ticket.is_empty() or not is_same(ticket.token,token) or not followup_current(b,ticket) or not ticket.closed or b.battle_open or b.automation.running:return false
 var auto=b.automation;var scope:Dictionary=auto.loot_scope
 if ticket.scope_retired:return scope.is_empty()
 if scope.is_empty() or not is_same(scope.get("capability"),ticket.scope_capability) or not is_same(scope.get("token"),ticket.auto_token) or not auto._loot_current(scope):return false
 # No Callable/emit/save between owner check and exact stopped-scope retirement.
 auto.loot_scope={};ticket.scope_retired=true
 return true

# Internal continuous followup. No public job/RPC; original E1/E2 own all writes/rolls.
var consume_call:RefCounted
func continuation_owner(b,c:Dictionary)->bool:
 if c.is_empty() or not is_same(consume_call,c.call) or not is_same(b.quest_loot,self) or not is_same(lifetime,c.expected_lifetime) or clock!=c.clock:return false
 var q=b.quest_auto;var auto=b.automation
 for pair in [["session",b.session],["battle",b.battle],["automation",auto],["runner",q],["identity_object",q.identity],["timer",self]]:
  if not scope_owner_matches(c,pair[0],pair[1]):return false
 if c.get("retired",false):
  if not auto.loot_scope.is_empty():return false
 elif not is_same(auto.loot_scope.get("capability"),c.scope_capability) or not is_same(auto.loot_scope.get("token"),c.auto_token):return false
 return b.save_path==c.path and is_same(auto.start_lifetime,c.auto_token) and str(b.battle.snapshot().get("battle_id",""))==c.battle_id and q.running and q.internal and not q.detached and not q.restored and q.phase==c.phase and q.identity.checkpoint()==c.identity and q.connection==c.connection and q.client==c.client and q.step==c.step and auto.position_map==c.map_id and auto.position_cell==c.cell and not b.battle_open and not auto.running and b.session._pending.is_empty() and b.session._loot_settlement.is_empty() and last_attempt_ms==c.last_attempt_ms and next_attempt_ms==c.expected_deadline and b.quest_visit_guard==c.visit_guard and b.party_guard==c.party_guard
func continuation_current(b,c:Dictionary)->bool:
 if not continuation_owner(b,c):return false
 # Exactly old closed state or this call's precomputed open candidate. The
 # installed-before-cache bridge exists only inside the original writer callback.
 if b.session.snapshot()==c.profile and is_same(b.session._profile,c.profile_ref):
  return b.last_saved_payload==c.payload and b.quest_save_serial==c.serial
 if c.get("expected_open",{}).is_empty() or b.session.snapshot()!=c.expected_open:return false
 if c.has("open_profile_ref") and not is_same(b.session._profile,c.open_profile_ref):return false
 return (b.last_saved_payload==c.payload and b.quest_save_serial==c.serial) or (b.last_saved_payload==c.open_payload and b.quest_save_serial==c.serial+1)
static func followup_decision(planned:Dictionary,entry:Dictionary)->String:
 if planned.get("status")=="done":return "completed"
 if entry.used_ms>=entry.limit_ms:return "limit_reached"
 return "open" if planned.get("status")=="step" else "manual"
func consume_followup(b)->Dictionary:
 if consume_call!=null:return State.denied("续行调用正在进行。")
 var call:=RefCounted.new()
 consume_call=call
 var result:Dictionary=consume_followup_locked(b,call)
 if is_same(consume_call,call):consume_call=null
 return result
func consume_followup_locked(b,call:RefCounted)->Dictionary:
 var ticket:Dictionary=followup
 if not failed_followup_resume.is_empty():
  finish_followup_execution_failure(b)
  return State.denied("刷物续行保存校验失败，停止新尝试。")
 if ticket.is_empty():return State.denied("没有当前已关闭战果凭据。")
 if not followup_current(b,ticket):
  reject_followup_execution(b,ticket)
  finish_followup_execution_failure(b)
  return State.denied("原战果凭据已失效，停止新尝试。")
 if not ticket.closed or b.automation.running or b.battle_open:return {"ok":true,"waiting":true}
 if not b.continuation_dispatch_ready(ticket.get("dispatch_barrier",{})):return {"ok":true,"waiting":true}
 if ticket.clock!=clock or not State.integer(ticket.last_attempt_ms,0,State.MAX_MSEC-ATTEMPT_INTERVAL_MS) or ticket.deadline_ms!=ticket.last_attempt_ms+ATTEMPT_INTERVAL_MS or last_attempt_ms!=ticket.last_attempt_ms or next_attempt_ms!=ticket.deadline_ms:return State.denied("原尝试节拍身份已变化。")
 var c:Dictionary=ticket.duplicate(true)
 c.call=call;c.phase="loot_battle";c.expected_lifetime=lifetime;c.expected_deadline=ticket.deadline_ms
 c.profile_ref=b.session._profile;c.visit_guard=b.quest_visit_guard;c.party_guard=b.party_guard
 if not continuation_current(b,c):return State.denied("续行归属已变化。")
 var planned:Dictionary=JewelPlan.select(b,Sources.matches_backend)
 if not continuation_current(b,c):return State.denied("重规划回调改变了旧归属。")
 var decision:String=followup_decision(planned,c.profile.quest_loot.entries[State.STEP])
 if decision=="open" and not Sources.same(planned.get("step"),c.step):decision="manual"
 if not retire_followup_scope(b,ticket.token):return State.denied("原自动战斗身份不可退休。")
 c.retired=true
 if not continuation_current(b,c):return State.denied("原自动战斗退休归属已变化。")
 # Exact stopped scope retirement above is callback-free; never clear a successor.
 if is_same(followup,ticket):followup={}
 if decision!="open":
  b.quest_auto.running=false;b.quest_auto.owns_battle=false
  b.quest_auto.phase="completed" if decision=="completed" else "manual"
  b.quest_auto.message="目标已满足，刷物结束。" if decision=="completed" else "本步预算已到限。" if decision=="limit_reached" else str(planned.get("reason","原刷物步骤需要手动处理。"))
  b.quest_auto.pause_reason="" if decision=="completed" else b.quest_auto.message
  b.publish()
  return {"ok":true,"status":decision,"persisted":false}
 c.phase="loot_admission";b.quest_auto.phase=c.phase
 c.before_open_timer=admission_timer_snapshot()
 var reply:Dictionary=admit_prepared_run(b,c)
 if not reply.get("ok",false):
  # Only a proved non-commit on the unchanged old closed owner may announce
  # failure. Persisted opens and superseding callbacks keep their own facts.
  return announce_failed_open(b,c,reply)
 if not continuation_current(b,c) or not is_same(reply.get("continuation_call"),call):return {"ok":false,"persisted":true,"reason":"已存续开返回归属已改变。"}
 var ready:Dictionary=ready_frame
 if not is_same(reply.capability,admission) or not is_same(reply.capability,ready.get("capability")) or not is_same(reply.lifetime,lifetime) or not is_same(reply.lifetime,ready.get("lifetime")) or not is_same(reply.ready_token,ready.get("ready_token")) or reply.identity!=c.identity or not admission_owner(b,ready):return {"ok":false,"persisted":true,"reason":"已存续开安装凭据不匹配。"}
 if reply.candidate_payload!=c.open_payload or b.last_saved_payload!=reply.candidate_payload or reply.candidate_serial!=c.serial+1 or b.quest_save_serial!=reply.candidate_serial:return {"ok":false,"persisted":true,"reason":"已存续开候选已被替换。"}
 # No callback from seal validation through deadline installation. Never roll
 # in the consumer; the next normal process must also satisfy the real clock.
 next_attempt_ms=maxi(int(c.deadline_ms),int(reply.open_anchor_ms))
 ready.continuation_gate={"epoch":c.dispatch_barrier.epoch,"generation":b.continuation_dispatch_checkpoint().generation}
 var committed:Dictionary={"ok":true,"status":"reopened","persisted":true,"identity":reply.identity.duplicate(true),"entry":State.identity(b.session._profile.quest_loot.entries[State.STEP])}
 # Publish only AFTER seal/gate. No live-object reads or writes after observers.
 b.publish()
 return committed
func announce_failed_open(b,c:Dictionary,reply:Dictionary)->Dictionary:
 if not reply.get("persisted") is bool or reply.persisted or reply.get("ok",true):return reply
 if not continuation_current(b,c) or not is_same(admission,c.get("e1_admission")):return reply
 if c.has("open_profile_ref") or anchor_ms>=0 or not battle_receipt.is_empty() or not close_pending.is_empty():return reply
 if not is_same(b.session._profile,c.profile_ref) or b.session.snapshot()!=c.profile or b.last_saved_payload!=c.payload or b.quest_save_serial!=c.serial:return reply
 if b.session._profile.quest_loot.entries[State.STEP].open_span or admission_timer_snapshot()!=c.before_open_timer:return reply
 # All checks above are read-only and callback-free. Do not generic-stop/save,
 # create storage debt, or clear any later ready/timer/nav here.
 var result:Dictionary=reply.duplicate(true)
 result.status="manual"
 var q=b.quest_auto
 q.running=false;q.owns_battle=false;q.phase="manual"
 q.message=str(reply.get("reason","预算续开失败，已停止。"))
 q.pause_reason=q.message
 b.publish()
 return result
func tick_internal(b)->void:
 if not cancelled_battle.is_empty() or not close_pending.is_empty():return
 if b.quest_auto.phase=="loot_battle":
  consume_followup(b)
  return
 if b.quest_auto.phase=="loot_admission" and not initial_e2.is_empty():
  _tick_initial_e2(b)
  return
 if b.quest_auto.phase=="loot_admission" and ready_frame.has("continuation_gate"):
  var ready:Dictionary=ready_frame
  var reply:Dictionary=attempt_once(b)
  if reply.get("_sample_stale",false):return
  if reply.get("ok",false):
   publish_attempt_progress(b,reply.get("_progress_sample",{}))
   return
  # Stop only the same idle execution. A published battle or a successor is
  # an independent fact; never route it through this old idle-close tail.
  if is_same(ready_frame,ready) and admission_owner(b,ready) and not b.battle_open and b.session._pending.is_empty():
   b.quest_auto.stop(b,str(reply.get("reason","刷物尝试停止。")))

# P2 candidate: sealed idle samples only; no public timer API or battle heartbeat.
const PROGRESS_INTERVAL_MS=1000
var progress_stamp:Dictionary={}
func progress_timer_snapshot()->Dictionary:
 var value:Dictionary=admission_timer_snapshot()
 # CHECKING/ROLLING transient lock retirement does not change sample authority.
 # The captured call itself is separately checked while inside attempt_locked.
 value.erase("attempt_frame");value.erase("attempt_call")
 value.progress_stamp=progress_stamp.duplicate(true)
 return value
func sample_attempt_current(b,s:Dictionary,inside_call:bool)->bool:
 if s.is_empty() or not is_same(ready_frame,s.ready) or not is_same(ready_frame.get("ready_token"),s.ready_token):return false
 if not admission_owner(b,s.frame) or clock!=s.clock or not is_same(lifetime,s.lifetime):return false
 if not is_same(b.quest_auto.identity,s.identity_object) or not is_same(b.automation,s.automation):return false
 if [b.automation.running,b.automation.hunt_running,b.automation.flow_active(),b.stationary.running,b.original_quests.pending]!=s.activity:return false
 if inside_call and not is_same(attempt_call,s.call):return false
 if not is_same(b.session,s.session) or b.save_path!=s.path or not is_same(b.session._profile,s.profile_ref) or b.session.snapshot()!=s.profile:return false
 if not is_same(b.session._pending,s.pending_ref) or b.session._pending!=s.pending or b.session._loot_settlement!=s.settlement:return false
 if b.last_saved_payload!=s.payload or b.quest_save_serial!=s.serial:return false
 if not is_same(b.battle,s.battle) or b.battle.snapshot()!=s.battle_state or b.battle_open!=s.battle_open:return false
 return progress_timer_snapshot()==s.timer
func sample_attempt_sealed(b,frame:Dictionary,fence:Dictionary)->Dictionary:
 if not attempt_owned(b,frame) or frozen or blocked or storage_paused or anchor_ms<0 or not battle_receipt.is_empty() or b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty():return {"ok":false}
 var s:Dictionary=fence.duplicate()
 var value=s.clock.call()
 # Invalid owner is not an invalid-clock policy: never poison its successor.
 if not sample_attempt_current(b,s,true):return {"ok":false,"stale":true}
 if not State.integer(value,0,State.MAX_MSEC):blocked=true;fence.timer=progress_timer_snapshot();return {"ok":false}
 var current:int=int(value)
 if last_ms>=0 and current<last_ms:blocked=true;fence.timer=progress_timer_snapshot();return {"ok":false}
 # Preserve same-owner original now()->used_ms overflow ordering, not its
 # stale-owner mutation. Public now/sample_active remain byte-identical.
 if current<anchor_ms or base_used_ms>State.MAX_MSEC-(current-anchor_ms):
  last_ms=current;blocked=true;fence.timer=progress_timer_snapshot();return {"ok":false}
 last_ms=current
 cached_sample={"lifetime":lifetime,"span":span.duplicate(true),"used_ms":base_used_ms+current-anchor_ms}
 s.timer=progress_timer_snapshot()
 fence.timer=s.timer
 s.ms=current;s.used_ms=cached_sample.used_ms
 return {"ok":true,"seal":s}
func publish_attempt_progress(b,s:Dictionary)->void:
 if s.is_empty() or attempt_call!=null or not attempt_frame.is_empty() or not sample_attempt_current(b,s,false):return
 if frozen or blocked or storage_paused or b.battle_open or not battle_receipt.is_empty() or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty():return
 if not is_same(progress_stamp.get("lifetime"),lifetime) or progress_stamp.get("span",{})!=span:return
 if s.ms<int(progress_stamp.ms) or s.ms-int(progress_stamp.ms)<PROGRESS_INTERVAL_MS or s.used_ms==progress_stamp.used_ms:return
 # No add-to-deadline overflow. Store only primitive time/span and lifetime,
 # never the temporary seal/owner/frame, and never write after observers.
 progress_stamp={"lifetime":lifetime,"span":span.duplicate(true),"ms":s.ms,"used_ms":s.used_ms}
 b.publish()

func capture_attempt_sample(b,frame:Dictionary)->Dictionary:
 return {"identity_object":b.quest_auto.identity,"automation":b.automation,"activity":[b.automation.running,b.automation.hunt_running,b.automation.flow_active(),b.stationary.running,b.original_quests.pending.duplicate(true)],"frame":frame,"call":frame.attempt_call,"ready":ready_frame,"ready_token":ready_frame.ready_token,"clock":clock,"lifetime":lifetime,"session":b.session,"path":b.save_path,"profile_ref":b.session._profile,"profile":b.session.snapshot(),"pending_ref":b.session._pending,"pending":b.session._pending.duplicate(true),"settlement":b.session._loot_settlement.duplicate(true),"payload":b.last_saved_payload,"serial":b.quest_save_serial,"battle":b.battle,"battle_state":b.battle.snapshot(),"battle_open":b.battle_open,"timer":progress_timer_snapshot()}

# Exact checkpoint-origin same-payload continuation. No global save exemption.
func capture_followup_checkpoint(b,command:Dictionary)->Dictionary:
 var ticket:Dictionary=followup
 if ticket.is_empty() or not followup_current(b,ticket) or b.save_path.is_empty():return {}
 if b.battle.snapshot().active or not b.battle_state.get("settled",false):return {}
 for field in ["map_id","x","y"]:
  if not State.integer(command.get(field),0,2147483647):return {}
 var location:Dictionary={"map_id":int(command.map_id),"x":int(command.x),"y":int(command.y)}
 if location!={"map_id":b.automation.position_map,"x":b.automation.position_cell.x,"y":b.automation.position_cell.y}:return {}
 if b.session._profile.get("location",{})!=location or JSON.stringify(b.session.snapshot())!=ticket.payload:return {}
 return {"call":RefCounted.new(),"timer":self,"session":b.session,"profile_ref":b.session._profile,"path":b.save_path,"ticket":ticket,"ticket_before":ticket.duplicate(true),"serial":b.quest_save_serial,"payload":ticket.payload,"location":location,"written":false}
func followup_checkpoint_owner(b,c:Dictionary,expected_serial:int)->bool:
 if c.is_empty() or not is_same(c.timer,self) or not is_same(b.quest_loot,self) or not is_same(b.session,c.session) or b.save_path!=c.path:return false
 if not is_same(followup,c.ticket) or c.ticket!=c.ticket_before or not followup_owner(b,c.ticket):return false
 if not is_same(b.session._profile,c.profile_ref) or b.session.snapshot()!=c.ticket_before.profile or b.last_saved_payload!=c.payload or b.quest_save_serial!=expected_serial:return false
 if not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or b.battle.snapshot().active or not b.battle_state.get("settled",false):return false
 return b.session._profile.get("location",{})==c.location and c.location=={"map_id":b.automation.position_map,"x":b.automation.position_cell.x,"y":b.automation.position_cell.y}
func mark_followup_checkpoint_saved(b,c:Dictionary,payload:String)->void:
 # Only the actual original same-payload branch receives this exact argument.
 # No callback between the branch's serial increment and this mark.
 if c.get("written",true) or payload!=c.get("payload") or not followup_checkpoint_owner(b,c,int(c.serial)+1):return
 c.written=true;c.saved_call=c.call;c.saved_serial=b.quest_save_serial
func finish_followup_checkpoint(b,c:Dictionary,saved:bool)->void:
 if not saved or not c.get("written",false) or not is_same(c.get("saved_call"),c.call) or c.get("saved_serial")!=int(c.serial)+1:return
 if not followup_checkpoint_owner(b,c,c.saved_serial):return
 # Preserve original immutable candidate/profile/payload/closed/barrier and
 # owner identity. Only this exact successful no-op checkpoint advances serial.
 c.ticket.serial=c.saved_serial

# Only two long-lived objects may bridge an original no-op resume writer.
# Rejection is separate from resealing; it never creates a disk/close permission.
var failed_initial_resume:Dictionary={}
var failed_followup_resume:Dictionary={}
func outer_resume_persistent_claims_idle(b)->bool:
 return b._fee_attempt_writer_call==null and b._fee_attempt_writer_snapshot.is_empty() and not b._fee_attempt_writer_executing and b._fee_attempt_close_call==null and b._fee_attempt_close_frame.is_empty() and not b._fee_attempt_close_executing and b._fee_resume_sidecar_call==null and b._fee_resume_sidecar_frame.is_empty() and not b._fee_resume_sidecar_executing and b._quest_auto_stop_operation_call==null and b._quest_auto_stop_operation_owner==null and b._fee_start_journal_writer._frame.is_empty() and not b._fee_start_journal_writer._executing
func outer_resume_context(b)->bool:
 return outer_resume_persistent_claims_idle(b) and b._loot_outer_resume_call!=null and b.keep_resume_current and b._process_depth==1 and b._dispatch_boundary_depth==2 and b._depth==0 and b._observer_depth==0 and b._flush_depth==0 and b._queue.is_empty() and consume_call==null and attempt_call==null and attempt_frame.is_empty() and heartbeat_call==null
func resume_followup_identity(b,ticket:Dictionary)->bool:
 # Same fields as followup_owner, using already-resident battle state. No
 # snapshot/migration/capture-player hook may run inside mark/finish/revocation.
 if ticket.is_empty() or not is_same(b.quest_loot,self):return false
 var q=b.quest_auto;var auto=b.automation
 for pair in [["session",b.session],["battle",b.battle],["automation",auto],["runner",q],["identity_object",q.identity],["timer",self]]:
  if not scope_owner_matches(ticket,pair[0],pair[1]):return false
 return b.save_path==ticket.path and is_same(lifetime,ticket.lifetime) and is_same(auto.start_lifetime,ticket.auto_token) and str(b.battle._state.get("battle_id",""))==ticket.battle_id and q.running and q.internal and not q.detached and not q.restored and q.phase=="loot_battle" and q.identity.checkpoint()==ticket.identity and q.connection==ticket.connection and q.client==ticket.client and q.step==ticket.step and auto.position_map==ticket.map_id and auto.position_cell==ticket.cell
func followup_execution_owner(b,ticket:Dictionary)->bool:
 if not resume_followup_identity(b,ticket):return false
 var scope:Dictionary=b.automation.loot_scope
 if not scope.is_empty() and (not is_same(scope.get("capability"),ticket.scope_capability) or not is_same(scope.get("token"),ticket.auto_token) or scope.get("receipt",{})!=ticket.receipt):return false
 var prior:Variant=ticket.get("profile")
 if not prior is Dictionary:return false
 var expected:Variant=prior.get("profile_id")
 var current:Variant=b.session._profile.get("profile_id")
 return expected is String and current is String and expected==current
func reject_followup_execution(b,ticket:Dictionary)->void:
 if ticket.is_empty() or not is_same(followup,ticket):return
 # Execution authority deliberately does not depend on a writer/profile seal.
 # It still requires the original runner/identity/session/timer/battle owners.
 if not followup_execution_owner(b,ticket):
  if is_same(followup,ticket):followup={}
  return
 if failed_followup_resume.is_empty():failed_followup_resume=ticket
func finish_followup_execution_failure(b)->void:
 var ticket:Dictionary=failed_followup_resume
 if ticket.is_empty():return
 if not is_same(followup,ticket) or not followup_execution_owner(b,ticket):
  if is_same(failed_followup_resume,ticket):failed_followup_resume={}
  return
 # Do not interfere with the original settled battle's close/automatic exit.
 # In particular this is not generic Stop and never calls save/close_battle.
 if b.battle_open or b.automation.running:return
 if not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or b.battle._state.get("active",true):return
 var q=b.quest_auto
 # Only the stopped original scope checked above is retired. A replacement
 # capability/token/receipt fails execution ownership before reaching this point.
 if not b.automation.loot_scope.is_empty():b.automation.loot_scope={}
 followup={};failed_followup_resume={}
 # Retire only old execution-owned readiness, not a different lifetime/frame.
 if is_same(ready_frame.get("runner"),q) and is_same(ready_frame.get("lifetime"),ticket.lifetime) and ready_frame.get("identity")==ticket.identity:
  ready_frame={};admission=RefCounted.new()
 if not initial_e2.is_empty() and is_same(initial_e2.get("lifetime"),ticket.lifetime) and initial_e2.get("identity")==ticket.identity:initial_e2={}
 q.running=false;q.owns_battle=false;q.phase="stopped"
 q.message="刷物续行保存校验失败；原战果保留，已停止新尝试。"
 q.pause_reason=q.message
 # All mutations above precede the last callback. Never touch a successor after it.
 b.publish()
func capture_outer_resume_save(b)->Dictionary:
 if not outer_resume_context(b) or not b._loot_resume_envelope.is_empty():return {}
 if not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or b.save_path.is_empty():return {}
 if not failed_initial_resume.is_empty() and not is_same(failed_initial_resume,initial_e2):failed_initial_resume={}
 if not failed_followup_resume.is_empty() and (not is_same(failed_followup_resume,followup) or not followup_execution_owner(b,failed_followup_resume)):failed_followup_resume={}
 if not failed_followup_resume.is_empty() or not failed_initial_resume.is_empty():return {}
 var scope_ref:Dictionary=b.automation.loot_scope
 var scope_value:Dictionary=scope_ref.duplicate(true)
 var initial:Dictionary=capture_initial_resume_save(b) # Keep the existing observer seam.
 var ticket:Dictionary=followup
 var c1:bool=not ticket.is_empty() and followup_current(b,ticket) and not b.battle._state.get("active",true) and b.battle_state.get("settled",false)
 if c1 and (not followup_execution_owner(b,ticket) or not is_same(b.automation.loot_scope,scope_ref) or b.automation.loot_scope!=scope_value or not is_same(followup,ticket) or b.quest_save_serial!=ticket.serial or b.session._profile!=ticket.profile or b.last_saved_payload!=ticket.payload):c1=false
 if not initial.is_empty() and c1:
  failed_initial_resume=initial.frame
  reject_followup_execution(b,ticket)
  return {} # Never choose one of two conflicting capabilities.
 if not ticket.is_empty() and not c1:reject_followup_execution(b,ticket)
 if initial.is_empty() and not c1:return {}
 var kind:String="initial" if not initial.is_empty() else "followup"
 var target:Dictionary=initial.frame if kind=="initial" else ticket
 var fact:Dictionary={"call":RefCounted.new(),"written":false}
 if kind=="initial":initial.writer_fact=fact
 var envelope:Dictionary={"timer":self,"origin":b._loot_outer_resume_call,"kind":kind,"scope_ref":scope_ref,"scope_value":scope_value,"target":target,"value":target.duplicate(true),"initial":initial,"ready":ready_frame,"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"payload":b.last_saved_payload,"serial":b.quest_save_serial,"generation":b._normal_process_generation,"battle_open":b.battle_open,"auto_running":b.automation.running,"fact":fact}
 b._loot_resume_envelope=envelope
 return envelope
func outer_resume_current(b,e:Dictionary,expected_serial:int)->bool:
 if e.is_empty() or not is_same(b._loot_resume_envelope,e) or not is_same(b.quest_loot,self) or not is_same(e.timer,self):return false
 if not outer_resume_context(b) or not is_same(b._loot_outer_resume_call,e.origin) or b._normal_process_generation!=e.generation:return false
 if not is_same(b.session._profile,e.profile_ref) or b.session._profile!=e.profile or b.last_saved_payload!=e.payload or b.quest_save_serial!=expected_serial:return false
 if e.target.serial!=e.serial or e.target!=e.value or b.battle_open!=e.battle_open or b.automation.running!=e.auto_running or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty():return false
 if e.kind=="initial":
  return is_same(initial_e2,e.target) and is_same(ready_frame,e.ready) and _initial_e2_owner(b,e.target,false)
 if e.kind!="followup" or not is_same(followup,e.target) or not followup_execution_owner(b,e.target):return false
 if not is_same(b.automation.loot_scope,e.scope_ref) or b.automation.loot_scope!=e.scope_value:return false
 return not b.battle._state.get("active",true) and b.battle_state.get("settled",false) and b.session._profile==e.target.profile and e.payload==e.target.payload
func mark_outer_resume_saved(b,e:Dictionary,payload:String)->void:
 # Called only by Backend's actual equal-payload branch after its +1.
 if not outer_resume_current(b,e,int(e.serial)+1) or payload!=e.payload or e.fact.written:return
 e.fact.written=true;e.fact.saved_call=e.fact.call;e.fact.saved_serial=b.quest_save_serial
func finish_outer_resume_save(b,e:Dictionary,result:Variant)->void:
 if e.is_empty():return
 var owns:bool=is_same(b._loot_resume_envelope,e)
 var success:bool=result is bool and result==true
 var fact:Dictionary=e.fact
 var eligible:bool=owns and success and fact.get("written") is bool and fact.written and is_same(fact.get("saved_call"),fact.call) and fact.get("saved_serial") is int and fact.saved_serial==int(e.serial)+1 and outer_resume_current(b,e,fact.saved_serial)
 if e.kind=="initial":
  # Keep actual bool return visible to the legacy observer, independently
  # from writer provenance and final eligibility. Unknown is never true.
  fact.eligible=eligible
  finish_initial_resume_save(b,e.initial,success)
  if not eligible and is_same(initial_e2,e.target) and _initial_failure_execution(b,e.target):failed_initial_resume=e.target
 elif e.kind=="followup":
  if eligible:e.target.serial=fact.saved_serial
  else:reject_followup_execution(b,e.target)
 if owns and is_same(b._loot_resume_envelope,e):b._loot_resume_envelope={}

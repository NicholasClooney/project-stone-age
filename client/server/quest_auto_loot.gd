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
 cached_sample={"lifetime":lifetime,"span":span.duplicate(true),"used_ms":base_used_ms}
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
  key="";binding={};span={};anchor_ms=-1;base_used_ms=0;frozen=false;storage_paused=false;cached_sample={}
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
 var view:Dictionary={"enabled":false,"reason":"限时刷物尚未开放。","default_limit_minutes":30,"activity":"unavailable","finish_current_battle":false,"recovery_blocked":false,"can_start":false,"can_stop":false,"can_adjust_limit":false,"can_reset":false,"entry":null}
 if b.save_path.is_empty() or b.last_saved_payload.is_empty():return view
 var baseline=JSON.parse_string(b.last_saved_payload)
 if not baseline is Dictionary or not State.valid(baseline.get("quest_loot")):return view
 view.default_limit_minutes=Settings.effective(baseline.get("automation_settings",{})).loot_minutes
 var ledger:Dictionary=baseline.quest_loot
 var entry:Dictionary=ledger.entries.get(State.STEP,{})
 view.recovery_blocked=ledger.recovery_blocked or (not entry.is_empty() and entry.recovery_blocked)
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
 if view.recovery_blocked:
  view.activity="recovery_locked";view.reason="中断时段用时不确定，显示已存下界。"
 elif closing_current or (sample_current and storage_paused):
  view.activity="storage_paused"
  view.reason=str(b.battle_state.get("settlement_error","")) if battle_current else ""
  if view.reason.is_empty():view.reason="保存处理中或等待修复，预算暂停计时。"
 elif battle_current:
  view.activity="battle" if b.battle.snapshot().get("active",false) else "settling"
 elif baseline.get("original_items",[]).any(func(item):return State.integer(item,2760,2760)):
  view.activity="completed"
 elif view.entry.limit_reached:
  view.activity="limit_reached"
 elif run_current and not q.detached and not frozen and not blocked:
  view.activity="running"
 else:view.activity="stopped"
 return view

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
 return {"key":key,"binding":binding.duplicate(true),"span":span.duplicate(true),"anchor_ms":anchor_ms,"base_used_ms":base_used_ms,"last_ms":last_ms,"blocked":blocked,"frozen":frozen,"frozen_ms":frozen_ms,"storage_paused":storage_paused,"cached_sample":cached_sample.duplicate(true),"ready_frame":ready_frame.duplicate(true),"next_attempt_ms":next_attempt_ms,"last_attempt_ms":last_attempt_ms,"attempt_frame":attempt_frame.duplicate(true),"attempt_call":attempt_call,"battle_receipt":battle_receipt.duplicate(true),"open_obligation":open_obligation.duplicate(true),"close_pending":close_pending.duplicate(true)}
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
  if is_same(followup,ticket):followup={}
  return {}
 return ticket
func record_followup_close(b,ticket:Dictionary,saved:bool)->void:
 if ticket.is_empty() or not is_same(followup,ticket):return
 # This is the return of close_battle's one existing save, before any publish.
 if not saved or not followup_owner(b,ticket) or b.battle_open or not b.session._pending.is_empty() or b.quest_save_serial!=ticket.serial+1 or b.session.snapshot()!=ticket.profile or b.last_saved_payload!=ticket.payload:
  if is_same(followup,ticket):followup={}
  return
 ticket.serial=b.quest_save_serial;ticket.closed=true
 ticket.dispatch_barrier=b.continuation_dispatch_checkpoint()
func followup_status(b)->Dictionary:
 var ticket:Dictionary=followup
 if ticket.is_empty():return {}
 if not followup_current(b,ticket):
  if is_same(followup,ticket):followup={}
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
 if ticket.is_empty() or not followup_current(b,ticket) or not ticket.closed or b.automation.running or b.battle_open:return {"ok":false,"persisted":false,"reason":"没有当前已关闭战果凭据。"}
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

extends RefCounted
## Internal timer/candidate preparation with dormant battle settlement hooks.
## No public registration or attempt scheduler is connected.
## Authoritative commit hooks must accept a candidate before accept_commit;
## this object never saves, creates a battle, grants proof or counts a reward.
const State=preload("res://server/quest_auto_loot_state.gd")
const Sources=preload("res://server/quest_auto_loot_sources.gd")
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
 if anchor_ms<0 or key.is_empty() or not battle_receipt.is_empty():return
 var q=b.quest_auto
 if not q.running or not q.internal or q.detached or q.identity.checkpoint()!=binding or q.step.get("action")!="loot" or q.identity.step_id!=State.STEP:return
 if b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():return
 if b.party_guard.is_valid() and not str(b.party_guard.call()).is_empty():return
 if b.stationary.running or not Sources.same(q.step,Sources.step()) or not Sources.matches_backend(b,q.step.source):return
 var ledger:Dictionary=b.session._profile.get("quest_loot",{})
 if not may_attempt(ledger,binding) or b.save_path.is_empty():return
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

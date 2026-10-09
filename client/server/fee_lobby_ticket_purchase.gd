extends RefCounted
## Default-closed, one fresh Start purchase. No entry, retry, WAL or schema change.
## Night decision pending user confirmation: unknown real IO alone can hold
## profile writes, including manual saves, until a proven real reload.
const Exact=preload("res://server/fee_start_journal_writer.gd")
const Journal=preload("res://server/fee_attempt_lifecycle.gd")
const Adapter=preload("res://server/fee_lobby_ticket_adapter.gd")
const Fact=preload("res://server/fee_lobby_ticket_fact.gd")
const Equipment=preload("res://server/original_equipment.gd")
var _proposal:Dictionary={}
var _op:Dictionary={}
var _hold:Dictionary={}
var _fact:Dictionary={}
var rejected_saves:int=0 # Process diagnostic; not a durable fact.
const PURCHASE_HOLD_TEXT="购票结果未确认，请重新进入存档"
var HOLD_TEXT:String:
 get:return hold_text()
func hold_text()->String:return "入场结果未确认，请重新进入存档" if _hold.get("kind")=="entry" else PURCHASE_HOLD_TEXT
func propose(b)->bool:
 _proposal={}
 if not b._fee_lobby_ticket_enabled() or held(b):return false
 var call:RefCounted=b._fee_start_intent.current_call()
 if call==null or not b._fee_start_intent.writer_current(b,call):return false
 var plan:Dictionary=Adapter.offer(b)
 if plan.is_empty() or not b._fee_start_intent.writer_current(b,call):return false
 _proposal={"call":call,"plan":plan}
 return true
func take_proposal(b,call:RefCounted)->Dictionary:
 if _proposal.is_empty() or not is_same(_proposal.call,call):return {}
 var proposal:Dictionary=_proposal;_proposal={}
 if not b._fee_start_intent.writer_current(b,call) or held(b):return {}
 return proposal.plan if Exact.same_value(Adapter.offer(b),proposal.plan) else {}
func held(b)->bool:
 if _hold.is_empty() or not b._fee_lobby_ticket_enabled():return false
 # Run is immutable provenance, NOT a revocation predicate: Stop/load may retire
 # the run before a failed load. That must not expose the same stale memory/path.
 return is_same(_hold.session.get_ref(),b.session) and b.save_path==_hold.path and b.account_name==_hold.account and Exact.same_value(Exact.owner(b.session._profile),_hold.owner)
func refuse_save(b)->bool:
 if not _op.is_empty() and is_same(b.session,_op.session) and b.save_path==_op.path and Exact.same_value(Exact.owner(b.session._profile),_op.owner):return true
 if not held(b):return false
 note_refused_save()
 b.session.last_error=hold_text()
 return true
func note_refused_save()->void:
 rejected_saves+=1
 print("FEE_PURCHASE_SAVE_HOLD count=",rejected_saves)
func before_load(b,path:String)->Dictionary:
 _proposal={}
 if not held(b) or path!=_hold.path:return {}
 return {"hold":_hold,"session":b.session,"path":path,"previous_receipt":b.session._fee_loaded_receipt}
func stopped_for_load(b,h:Dictionary)->bool:
 return not h.is_empty() and is_same(_hold,h.hold) and held(b) and is_same(b.session,h.session) and not b.quest_auto.running and not b.automation.running and not b.automation.hunt_running and not b.automation.flow_active() and not b.battle_open and b.session._pending.is_empty()
func after_load(b,h:Dictionary)->void:
 if h.is_empty() or not is_same(_hold,h.hold) or not held(b) or not is_same(b.session,h.session):return
 var r:Dictionary=b.session._fee_loaded_receipt
 if is_same(r,h.previous_receipt) or not b.session._fee_loaded_receipt_current(r) or r.path!=h.path:return
 # Primary provenance only. A backup fallback is not proof that the unknown
 # primary can be overwritten. No warm reload, disk repair or merging here.
 if r.source!="primary" or not Journal.valid(r.get("journal")) or r.journal.current.run_id!=_hold.run_id or not Exact.same_value(r.journal.owner,_hold.owner):return
 var bytes:PackedByteArray=r.loader_profile_bytes if r.loader_wrote else r.source_bytes
 var row:Dictionary=b.session._read_fee_attempt_file(h.path,bytes)
 if not is_same(_hold,h.hold) or not held(b) or not b.session._fee_loaded_receipt_current(r):return
 if Exact.row_state(row,true,bytes)=="matches":
  if is_same(b.session._fee_purchase_hold,_hold):b.session._fee_purchase_hold={}
  _hold={}
func _idle(b)->bool:
 return b._quest_auto_stop_operation_call==null and b._fee_attempt_writer_call==null and b._fee_attempt_close_call==null and b._fee_resume_sidecar_call==null and b._fee_start_intent._loot_idle(b)
func _current(b,f:Dictionary)->bool:
 if not is_same(_op,f) or not is_same(b._fee_attempt_writer_call,f.claim):return false
 if not is_same(b.session,f.session) or b.save_path!=f.path or b.account_name!=f.account:return false
 if not is_same(b.quest_auto,f.runner) or not is_same(b.quest_auto.identity,f.identity) or b.quest_auto.identity.checkpoint()!=f.checkpoint:return false
 if not b.quest_auto.running or b.quest_auto.detached or not b.quest_auto.internal or b.quest_auto.connection!=f.connection or not is_same(b._fee_bindings.get(f.connection),f.binding):return false
 if not is_same(b.automation,f.automation) or not is_same(b.automation.start_lifetime,f.auto_token) or b.battle_open:return false
 if b.automation.running or b.automation.hunt_running or b.automation.flow_active() or b.stationary.running:return false
 if not is_same(b.quest_auto.source_frame,f.source) or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty() or not b.original_quests.pending.is_empty():return false
 if not b._fee_start_intent._loot_idle(b) or b._quest_auto_stop_operation_call!=null or b._fee_attempt_close_call!=null or b._fee_resume_sidecar_call!=null:return false
 if b._depth!=f.depth or b._dispatch_epoch!=f.epoch or b._dispatch_boundary_depth!=f.boundary or b._observer_depth!=f.observer or b._flush_depth!=f.flush:return false
 if not is_same(b.session._profile,f.profile_ref) or not Exact.same_value(b.session._profile,f.profile) or not Exact.same_value(Exact.owner(b.session._profile),f.owner):return false
 return b.last_saved_payload==f.cache and b.quest_save_serial==f.serial and b.automation.position_map==f.plan.map_id and b.automation.position_cell==f.plan.cell
func _rows(b,f:Dictionary)->Array:
 var rows:Array=[]
 for suffix in ["",".bak",".tmp"]:
  if not _current(b,f):return rows
  rows.append(f.session._read_fee_attempt_file(f.path+suffix,PackedByteArray()))
  if not _current(b,f):return []
 return rows
func _known(rows:Array)->bool:
 return rows.size()==3 and rows.all(func(row):return Exact.row_complete(row))
func _same_rows(a:Array,z:Array)->bool:
 if not _known(a) or not _known(z):return false
 for i in range(3):
  if Exact.row_state(a[i],z[i].exists,z[i].get("bytes",PackedByteArray()))!="matches":return false
 return true
func _quarantine(f:Dictionary)->void:
 if not f.io_entered:return
 # Keep no backend/runner/Callable: a weak Session is sufficient to prevent an
 # obsolete frame from retaining the owner. This is protection, not authority.
 _hold={"session":weakref(f.session),"path":f.path,"account":f.account,"owner":f.owner.duplicate(true),"run_id":f.run_id,"attempt_id":f.attempt_id,"host":f.host}
 f.session._fee_purchase_hold=_hold
func _write(b,f:Dictionary,candidate:Dictionary,twice:bool)->bool:
 if not _current(b,f) or not f.session._valid_profile(candidate):return false
 var previous:Array=_rows(b,f)
 if not _known(previous) or Exact.row_state(previous[0],true,f.cache.to_utf8_buffer())!="matches" or Exact.row_state(previous[2],false,PackedByteArray())!="matches":return false
 var payload:String=JSON.stringify(candidate)
 var bytes:PackedByteArray=payload.to_utf8_buffer()
 for index in range(2 if twice else 1):
  if not _current(b,f):return false
  var pre:Array=_rows(b,f)
  if not _same_rows(pre,previous):return false
  f.io_entered=false;f.physical_ran=false
  f.next_candidate=candidate;f.next_value=candidate.duplicate(true)
  var wrote:bool=b._write_lobby_ticket_candidate(f.call,candidate)
  wrote=wrote and f.physical_ran
  var after:Array=_rows(b,f)
  if not _known(after):_quarantine(f);return false
  var landed:bool=Exact.row_state(after[0],true,bytes)=="matches"
  if landed:
   if not _current(b,f):_quarantine(f);return false
   if index==0:
    b.session._profile=candidate.duplicate(true);b.last_saved_payload=payload;b.quest_save_serial+=1
    f.profile_ref=b.session._profile;f.profile=b.session._profile.duplicate(true);f.cache=payload;f.serial=b.quest_save_serial
  if not landed:
   # Known unchanged disk is a failed attempt. Any unrecognized combination is
   # unresolved even if the raw wrapper returned false.
   if Exact.row_state(after[0],previous[0].exists,previous[0].get("bytes",PackedByteArray()))!="matches":_quarantine(f)
   return false
  if not wrote:return false
  if Exact.row_state(after[1],true,previous[0].bytes)!="matches" or Exact.row_state(after[2],false,PackedByteArray())!="matches":return false
  previous=after
 return _current(b,f)
## Exact dedicated physical seam. The private flag is set at the real file
## operation, not before invoking a possibly false/forged wrapper. No arbitrary
## fee input; the Session seam only protects unresolved C writes.
func write_physical(b,call:RefCounted,candidate:Dictionary)->bool:
 if _op.is_empty() or not is_same(_op.call,call):return false
 var f:Dictionary=_op
 if not f.executing or not _current(b,f) or f.physical_ran or not is_same(candidate,f.next_candidate) or not Exact.same_value(candidate,f.next_value):return false
 f.physical_ran=true
 f.io_entered=true
 var file=FileAccess.open(f.path+".tmp",FileAccess.WRITE)
 if file==null:return false
 file.store_string(JSON.stringify(candidate));file.flush()
 var error:Error=file.get_error();file.close()
 if error!=OK or not _current(b,f):return false
 var absolute:String=ProjectSettings.globalize_path(f.path)
 if FileAccess.file_exists(f.path):
  var prior:Variant=f.session._parse_save(FileAccess.get_file_as_string(f.path))
  if not _current(b,f) or not f.session._valid_profile(prior):return false
  if DirAccess.copy_absolute(absolute,absolute+".bak")!=OK:return false
 if not _current(b,f):return false
 return DirAccess.rename_absolute(absolute+".tmp",absolute)==OK
func persist(b,call:RefCounted)->Dictionary:
 if _op.is_empty() or not is_same(_op.call,call) or _op.executing:return {"ok":false}
 var f:Dictionary=_op
 f.executing=true
 if not _current(b,f):return {"ok":false}
 var attempt:Dictionary=Journal.begin_attempt(f.profile.quest_auto_fee_lifecycle,f.run_id,f.attempt_id,f.plan.source_id,f.plan.offer_id,f.plan.item_id,f.plan.amount,f.profile.player.gold)
 if not Exact.strict_true(attempt.get("ok")):return {"ok":false}
 var fence:Dictionary=f.profile.duplicate(true);fence.quest_auto_fee_lifecycle=attempt.candidate
 if not _write(b,f,fence,true):return {"ok":false,"stage":"attempt_incomplete"}
 # Real double-write success is local control flow. A public diagnostic cannot
 # manufacture this handoff. The old generic attempt writer is unchanged.
 f.fenced=true
 if not Exact.same_value(Adapter.offer(b),f.plan) or not _current(b,f):return {"ok":false,"stage":"offer_changed"}
 var before:Dictionary=f.profile.duplicate(true)
 var candidate:Dictionary=before.duplicate(true)
 candidate.player.gold-=f.plan.amount
 Equipment.add(candidate,f.plan.item_id)
 if candidate.original_instances.size()!=before.original_instances.size()+1:return {"ok":false}
 var uid:Variant=candidate.original_instances[-1].get("uid")
 if not Journal.strict_int(uid,1):return {"ok":false}
 var ticket:Dictionary=Journal.commit_ticket(before.quest_auto_fee_lifecycle,f.run_id,f.attempt_id,uid,candidate.player.gold)
 if not Exact.strict_true(ticket.get("ok")):return {"ok":false}
 candidate.quest_auto_fee_lifecycle=ticket.candidate
 # Reject migration/normalization side effects: the exact ticket is the only
 # inventory delta. Existing item order, equipment, reward, map and all else stay.
 var exact:Dictionary=before.duplicate(true)
 exact.player.gold-=f.plan.amount
 exact.original_items.append(f.plan.item_id)
 exact.original_instances.append({"uid":uid,"item_id":f.plan.item_id,"durability":0})
 exact.next_original_uid+=1;exact.quest_auto_fee_lifecycle=ticket.candidate
 if uid!=before.next_original_uid or not Exact.same_value(candidate,exact):return {"ok":false}
 if not _write(b,f,candidate,false):return {"ok":false,"stage":"purchase_incomplete"}
 f.committed=true
 b._fee_lobby_ticket_entry.accept_purchase(b,self,f.call)
 _fact={"schema":1,"scope":"profile","origin":"explicit_start","owner":f.owner.duplicate(true),"transaction_id":f.transaction_id,"fee_kind":"golden44_lobby_ticket","phase":"ticket_purchase","run_id":f.run_id,"step_id":"golden44:lobby_purchase","attempt_id":f.attempt_id,"source_id":f.plan.source_id,"offer_id":f.plan.offer_id,"currency":"stone","amount":f.plan.amount,"balance_before":before.player.gold,"balance_after":candidate.player.gold,"item_id":f.plan.item_id,"ticket_uid":uid,"status":"committed","durability":"disk","save_serial":f.serial,"candidate_sha256":f.cache.sha256_text()}
 if not Fact.valid(_fact):_fact={}
 return {"ok":true,"stage":"purchase_committed"}
func advance(b)->bool:
 if not b._fee_lobby_ticket_enabled() or not _op.is_empty():return false
 var cap:Dictionary=b._fee_start_intent.take_purchase(b,self)
 if cap.is_empty():return false
 # Consume before every adapter, writer and callback. No run/recovery retry.
 if held(b) or not _idle(b) or b._depth<=0 or not b.quest_auto.internal:return true
 var plan:Dictionary=Adapter.offer(b)
 if plan.is_empty() or not Exact.same_value(plan,cap.plan):b.quest_auto.stop(b,"首票条件已改变，请手动处理。",false);return true
 var attempt_id:String=Crypto.new().generate_random_bytes(16).hex_encode()
 var transaction_id:String=Crypto.new().generate_random_bytes(16).hex_encode()
 if attempt_id==cap.run_id or transaction_id==attempt_id or transaction_id==cap.run_id:return true
 var f:Dictionary={"host":weakref(b),"call":RefCounted.new(),"claim":RefCounted.new(),"session":b.session,"path":b.save_path,"account":b.account_name,"owner":Exact.owner(b.session._profile),"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"runner":b.quest_auto,"identity":b.quest_auto.identity,"checkpoint":b.quest_auto.identity.checkpoint(),"source":b.quest_auto.source_frame,"connection":b.quest_auto.connection,"binding":b._fee_bindings.get(b.quest_auto.connection),"automation":b.automation,"auto_token":b.automation.start_lifetime,"depth":b._depth,"boundary":b._dispatch_boundary_depth,"observer":b._observer_depth,"flush":b._flush_depth,"epoch":b._dispatch_epoch,"plan":plan,"run_id":cap.run_id,"attempt_id":attempt_id,"transaction_id":transaction_id,"executing":false,"io_entered":false,"fenced":false,"committed":false}
 _op=f;b._fee_attempt_writer_call=f.claim
 b._persist_lobby_ticket_purchase(f.call) # Return value intentionally not authority.
 if is_same(b._fee_attempt_writer_call,f.claim):b._fee_attempt_writer_call=null
 if is_same(_op,f):_op={}
 var fact:Dictionary=_fact;_fact={}
 if not fact.is_empty():b._emit({"type":"quest_result","fee_fact":fact})
 if not f.committed and is_same(b.session,f.session) and is_same(b.quest_auto,f.runner) and is_same(b.quest_auto.identity,f.identity) and b.quest_auto.identity.checkpoint()==f.checkpoint and b.save_path==f.path and b.account_name==f.account and Exact.same_value(Exact.owner(b.session._profile),f.owner) and is_same(b.automation,f.automation) and is_same(b.automation.start_lifetime,f.auto_token):
  b.quest_auto.stop(b,hold_text() if held(b) else "首票未完成，本次不再自动购买。",false)
 return true

## Only the actual still-current purchase writer success can mint an entry
## continuation. Neither the fact nor a public result is accepted here.
func take_entry_handoff(b,consumer,call:RefCounted)->Dictionary:
 if not is_same(consumer,b._fee_lobby_ticket_entry) or _op.is_empty() or not is_same(_op.call,call):return {}
 var f:Dictionary=_op
 if not f.committed or f.get("entry_handed",false) or not _current(b,f):return {}
 f.entry_handed=true
 return {"session":f.session,"runner":f.runner,"identity":f.identity,"automation":f.automation,"auto_token":f.auto_token,"owner":f.owner,"path":f.path,"account":f.account,"run_id":f.run_id,"connection":f.connection,"binding":f.binding,"purchase":f.profile.quest_auto_fee_lifecycle.current.purchase.duplicate(true),"purchase_tx":f.transaction_id}
func hold_entry(b,producer,call:RefCounted)->void:
 if not is_same(producer,b._fee_lobby_ticket_entry):return
 var f:Dictionary=producer.hold_proof(b,self,call)
 if f.is_empty():return
 # Same provisional night decision, extended only to actual C entry IO.
 _hold={"kind":"entry","session":weakref(f.session),"path":f.path,"account":f.account,"owner":f.owner.duplicate(true),"run_id":f.run_id,"attempt_id":f.attempt_id,"host":f.host}
 f.session._fee_purchase_hold=_hold

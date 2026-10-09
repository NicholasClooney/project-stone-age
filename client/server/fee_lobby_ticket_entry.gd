extends RefCounted
## Default-closed continuation of this process's actual C purchase, not recovery.
## Night decision pending user confirmation: unknown actual entry IO shares the
## exact C profile-write protection. No public diagnostic mints authority.
const Exact=preload("res://server/fee_start_journal_writer.gd")
const Journal=preload("res://server/fee_attempt_lifecycle.gd")
const Source=preload("res://server/quest_auto_source_actions.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Fact=preload("res://server/fee_lobby_ticket_entry_fact.gd")
const HOLD_TEXT="入场结果未确认，请重新进入存档"
var _live:Dictionary={}
var _op:Dictionary={}
var _reply:Dictionary={}
func revoke()->void:_live={};_reply={}
func detach(connection:int,binding:Variant)->void:
 if not _live.is_empty() and _live.connection==connection and is_same(_live.binding,binding):_live={}
func accept_purchase(b,producer,call:RefCounted)->void:
 if not is_same(producer,b._fee_lobby_ticket) or not b._fee_lobby_ticket_enabled():return
 var h:Dictionary=producer.take_entry_handoff(b,self,call)
 if h.is_empty():return
 # All owning game objects are weak: the backend owns this module.
 _live={"token":RefCounted.new(),"router":weakref(b.original_quests),"session":weakref(h.session),"runner":weakref(h.runner),"identity":weakref(h.identity),"automation":weakref(h.automation),"auto_token":h.auto_token,"owner":h.owner.duplicate(true),"path":h.path,"account":h.account,"run_id":h.run_id,"connection":h.connection,"binding":h.binding,"purchase":h.purchase.duplicate(true),"purchase_tx":h.purchase_tx}
func _owner(b,h:Dictionary)->bool:
 if h.is_empty() or not is_same(h.router.get_ref(),b.original_quests) or not is_same(h.session.get_ref(),b.session) or not is_same(h.runner.get_ref(),b.quest_auto) or not is_same(h.identity.get_ref(),b.quest_auto.identity):return false
 if not is_same(h.automation.get_ref(),b.automation) or not is_same(h.auto_token,b.automation.start_lifetime):return false
 if b.save_path!=h.path or b.account_name!=h.account or not Exact.same_value(Exact.owner(b.session._profile),h.owner):return false
 return b.quest_auto.running and b.quest_auto.quest_id==2 and not b.quest_auto.detached and b.quest_auto.identity.run_id==h.run_id and b.quest_auto.connection==h.connection and is_same(b._fee_bindings.get(h.connection),h.binding)
func handles(b,npc_id:String,branch:Dictionary,phase:String)->bool:
 if not b._fee_lobby_ticket_enabled() or b._quest_source_call.is_empty() or not b.quest_auto.internal:return false
 var source:Dictionary=b.capture_quest_source_call(npc_id)
 if source.is_empty() or not Source.GATES.has(source.step.get("source",{}).get("source_id")):return false
 var record:Variant=b.session._profile.get("quest_auto_fee_lifecycle")
 # manual_only/no record remain the original path, with no invented receipt.
 if not record is Dictionary or not record.get("current") is Dictionary:return false
 var p:Variant=record.current.get("purchase")
 return p is Dictionary and p.get("state") is String and p.state in ["ticket_committed","entry_committed"]
func refuses_save(b)->bool:
 return not _op.is_empty() and is_same(b.session,_op.session) and b.save_path==_op.path and Exact.same_value(Exact.owner(b.session._profile),_op.owner)
func _current(b,f:Dictionary)->bool:
 if not is_same(_op,f) or not is_same(b._fee_attempt_writer_call,f.claim) or not _owner(b,f.cap):return false
 if not is_same(b.session,f.session) or not is_same(b.quest_auto,f.runner) or not is_same(b.quest_auto.identity,f.identity) or b.quest_auto.identity.checkpoint()!=f.checkpoint:return false
 if not is_same(b._quest_source_call,f.source) or not is_same(b.quest_auto.source_frame,f.source.frame) or not b.quest_source_call_live(f.source):return false
 if not is_same(b.original_quests,f.router) or not b.original_quests.pending.is_empty():return false
 if not b.quest_auto.internal or b.battle_open or not b.session._pending.is_empty() or not b.session._loot_settlement.is_empty():return false
 if b.automation.running or b.automation.hunt_running or b.automation.flow_active() or b.stationary.running:return false
 if not b._fee_start_intent._loot_idle(b) or b._quest_auto_stop_operation_call!=null or b._fee_attempt_close_call!=null or b._fee_resume_sidecar_call!=null:return false
 if b._depth!=f.depth or b._dispatch_epoch!=f.epoch or b._dispatch_boundary_depth!=f.boundary or b._observer_depth!=f.observer or b._flush_depth!=f.flush:return false
 if not is_same(b.session._profile,f.profile_ref) or not Exact.same_value(b.session._profile,f.profile):return false
 return b.last_saved_payload==f.cache and b.quest_save_serial==f.serial and b.automation.position_map==f.map and b.automation.position_cell==f.cell
func _rows(b,f:Dictionary)->Array:
 var rows:Array=[]
 for suffix in ["",".bak",".tmp"]:
  if not _current(b,f):return []
  rows.append(f.session._read_fee_attempt_file(f.path+suffix,PackedByteArray()))
  if not _current(b,f):return []
 return rows
func _known(rows:Array)->bool:return rows.size()==3 and rows.all(func(row):return Exact.row_complete(row))
func _quarantine(b,f:Dictionary)->void:
 if not f.io_entered:return
 b._fee_lobby_ticket.hold_entry(b,self,f.call)
func hold_proof(b,consumer,call:RefCounted)->Dictionary:
 if not is_same(consumer,b._fee_lobby_ticket) or _op.is_empty() or not is_same(_op.call,call) or not _op.io_entered:return {}
 # Captured provenance protects the actual old file even after a callback has
 # superseded the active owner. It never authorizes an operation on a successor.
 return {"session":_op.session,"path":_op.path,"account":_op.account,"owner":_op.owner.duplicate(true),"run_id":_op.cap.run_id,"attempt_id":_op.cap.purchase.attempt_id,"host":weakref(b)}
func _selected(before:Dictionary,item:int)->int:
 if not before.get("original_items") is Array or not before.get("original_instances") is Array or not before.get("original_equipment") is Dictionary:return -1
 if before.original_items.size()!=before.original_instances.size():return -1
 var first:int=-1
 var worn_index:int=-1
 var seen:Dictionary={}
 for i in range(before.original_instances.size()):
  var row:Variant=before.original_instances[i]
  if not row is Dictionary or not Journal.strict_int(row.get("uid"),1) or not Journal.strict_int(row.get("item_id"),1) or not Journal.strict_int(row.get("durability")):return -1
  if not Journal.strict_int(before.original_items[i],1) or before.original_items[i]!=row.item_id or seen.has(row.uid):return -1
  seen[row.uid]=true
  if row.item_id==item:
   if first<0:first=i
   if worn_index<0 and Equipment.worn(before,row.uid):worn_index=i
 return worn_index if worn_index>=0 else first
func f_valid_profile(b,before:Dictionary)->bool:return b.session._valid_profile(before)
func transact(b,before:Dictionary,candidate:Dictionary,npc_id:String,branch:Dictionary,phase:String)->Dictionary:
 var denied:Dictionary={"ok":false,"reason":"入场提交资格已失效，请手动核对存档。"}
 if not handles(b,npc_id,branch,phase) or not _op.is_empty():return denied
 if _live.is_empty() or not _owner(b,_live):_live={};return denied
 var cap:Dictionary=_live;_live={} # Genuine invocation consumes once before callbacks/IO.
 if _reply.is_empty() or not is_same(_reply.cap,cap) or not _reply_valid(b,_reply):return denied
 if b._fee_lobby_ticket.held(b) or not b._fee_lobby_ticket._idle(b) or b._depth<=0:return denied
 if not f_valid_profile(b,before) or not Exact.same_value(before,b.session._profile) or not Journal.valid(before.get("quest_auto_fee_lifecycle")):return denied
 var record:Dictionary=before.quest_auto_fee_lifecycle
 if record.current.run_status!="active" or record.current.run_id!=cap.run_id or not Exact.same_value(record.owner,cap.owner) or not Exact.same_value(record.current.purchase,cap.purchase):return denied
 var source:Dictionary=b.capture_quest_source_call(npc_id)
 if source.is_empty() or source.saved or not source.frame.can_save(source.call) or not b.quest_source_call_live(source) or not Source.transaction(source.step,branch,phase):return denied
 var source_id:String=source.step.source.source_id
 var gate:Array=Source.GATES[source_id]
 if gate[3]!=cap.purchase.item_id or b.automation.position_map!=gate[0]:return denied
 if not Journal.strict_int(before.player.get("gold"),0,1000000000):return denied
 var index:int=_selected(before,gate[3])
 if index<0:return denied
 var uid:int=before.original_instances[index].uid
 var expected:Dictionary=before.duplicate(true)
 for slot in expected.original_equipment:
  if expected.original_equipment[slot]==uid:expected.original_equipment[slot]=0
 expected.original_items.remove_at(index);expected.original_instances.remove_at(index)
 expected.location={"map_id":gate[2],"x":14,"y":26}
 if not Exact.same_value(candidate,expected):return denied # Reject every unrelated migration/delta.
 var next:Dictionary=Journal.commit_entry(record,cap.run_id,cap.purchase.attempt_id,cap.purchase.ticket_uid,gate[3],uid)
 if not Exact.strict_true(next.get("ok")):return denied
 candidate.quest_auto_fee_lifecycle=next.candidate
 var tx:String=Crypto.new().generate_random_bytes(16).hex_encode()
 if tx in [cap.run_id,cap.purchase.attempt_id,cap.purchase_tx]:return denied
 var f:Dictionary={"call":RefCounted.new(),"claim":RefCounted.new(),"cap":cap,"session":b.session,"router":b.original_quests,"runner":b.quest_auto,"identity":b.quest_auto.identity,"checkpoint":b.quest_auto.identity.checkpoint(),"source":source,"path":b.save_path,"account":b.account_name,"owner":cap.owner,"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"map":b.automation.position_map,"cell":b.automation.position_cell,"depth":b._depth,"epoch":b._dispatch_epoch,"boundary":b._dispatch_boundary_depth,"observer":b._observer_depth,"flush":b._flush_depth,"candidate":candidate,"value":candidate.duplicate(true),"source_id":source_id,"uid":uid,"transaction_id":tx,"executing":false,"physical_ran":false,"io_entered":false,"committed":false,"fact":{},"reply":_reply}
 _op=f;b._fee_attempt_writer_call=f.claim
 b._persist_lobby_ticket_entry(f.call,candidate) # Wrapper diagnostics are never authority.
 var committed:bool=f.committed
 if committed and _current(b,f):_publish(b,f,npc_id,branch,phase)
 if not committed and _current(b,f):
  # No persistence/settlement; hold prevents subsequent old-memory writes.
  b.quest_auto.stop(b,HOLD_TEXT if b._fee_lobby_ticket.held(b) else "入场未完成，本次不再自动提交。",false)
 if is_same(b._fee_attempt_writer_call,f.claim):b._fee_attempt_writer_call=null
 if is_same(_op,f):_op={}
 if not f.fact.is_empty():b._emit({"type":"quest_result","fee_fact":f.fact.duplicate(true)})
 return {"ok":true} if committed else {"ok":false,"reason":"save_failed"}
func persist(b,call:RefCounted,candidate:Dictionary)->Dictionary:
 if _op.is_empty() or not is_same(_op.call,call) or _op.executing:return {"ok":false}
 var f:Dictionary=_op;f.executing=true
 if not _current(b,f) or not is_same(candidate,f.candidate) or not Exact.same_value(candidate,f.value) or not f.session._valid_profile(candidate):return {"ok":false}
 var checked:Dictionary=Source.validate_step(b,2,f.source.step)
 if not _current(b,f) or not Exact.strict_true(checked.get("ok")):return {"ok":false}
 var pre:Array=_rows(b,f)
 if not _known(pre) or Exact.row_state(pre[0],true,f.cache.to_utf8_buffer())!="matches" or Exact.row_state(pre[2],false,PackedByteArray())!="matches":return {"ok":false}
 var payload:String=JSON.stringify(candidate);var bytes:PackedByteArray=payload.to_utf8_buffer()
 f.pre_rows=pre
 var wrote:bool=b._write_lobby_ticket_entry_candidate(call,candidate)
 wrote=wrote and f.physical_ran
 var after:Array=_rows(b,f)
 if not _known(after):_quarantine(b,f);return {"ok":false}
 var landed:bool=Exact.row_state(after[0],true,bytes)=="matches"
 if not landed:
  if Exact.row_state(after[0],true,pre[0].bytes)!="matches":_quarantine(b,f)
  return {"ok":false}
 # Readback of an actual candidate is memory reconciliation, not committed fact.
 if not f.physical_ran:return {"ok":false}
 b.session._profile=candidate.duplicate(true);b.last_saved_payload=payload;b.quest_save_serial+=1
 f.profile_ref=b.session._profile;f.profile=b.session._profile.duplicate(true);f.cache=payload;f.serial=b.quest_save_serial
 if is_same(_reply,f.reply):
  _reply.profile_ref=f.profile_ref;_reply.profile=f.profile.duplicate(true);_reply.cache=f.cache;_reply.serial=f.serial
 if not wrote or Exact.row_state(after[1],true,pre[0].bytes)!="matches" or Exact.row_state(after[2],false,PackedByteArray())!="matches":return {"ok":false}
 f.committed=true
 var p:Dictionary=f.cap.purchase
 f.fact={"schema":1,"scope":"profile","origin":"explicit_start","owner":f.owner.duplicate(true),"transaction_id":f.transaction_id,"fee_kind":"golden44_ticket_entry","phase":"ticket_entry","run_id":f.cap.run_id,"step_id":"golden44:entry:"+f.source_id,"attempt_id":p.attempt_id,"source_id":f.source_id,"currency":"stone","amount":0,"balance_before":candidate.player.gold,"balance_after":candidate.player.gold,"item_id":p.item_id,"ticket_uid":p.ticket_uid,"consumed_ticket_uid":f.uid,"destination":candidate.location.duplicate(true),"status":"committed","durability":"disk","save_serial":f.serial,"candidate_sha256":payload.sha256_text()}
 if not Fact.valid(f.fact):f.fact={}
 # Exact original SourceFrame save window, before any publication.
 f.source.saved=true;f.source.durable=true;f.source.candidate_sha=payload.sha256_text()
 f.source.frame.record_saved(f.source.call,f.serial)
 var target:Dictionary=candidate.location
 f.source.warp=[target.map_id,target.x,target.y]
 return {"ok":true}
func write_physical(b,call:RefCounted,candidate:Dictionary)->bool:
 if _op.is_empty() or not is_same(_op.call,call):return false
 var f:Dictionary=_op
 if not f.executing or f.physical_ran or not _current(b,f) or not is_same(candidate,f.candidate) or not Exact.same_value(candidate,f.value):return false
 var last:Array=_rows(b,f)
 if not _known(last):return false
 for i in range(3):
  if Exact.row_state(last[i],f.pre_rows[i].exists,f.pre_rows[i].get("bytes",PackedByteArray()))!="matches":return false
 f.physical_ran=true;f.io_entered=true
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
func _publish(b,f:Dictionary,npc_id:String,branch:Dictionary,phase:String)->void:
 if not _current(b,f):return
 var npc:Dictionary=b.original_quests.npc_by_id(npc_id)
 if not _current(b,f):return
 b.quest_arrival.action_committed(b,npc,branch,phase)
 if not _current(b,f):return
 var target:Dictionary=f.value.location
 var changed:bool=target.map_id!=f.map
 f.map=target.map_id;f.cell=Vector2i(target.x,target.y)
 b.automation.position_changed(f.map,f.cell,changed,"script")
 if not _current(b,f):return
 b._emit({"type":"position","map_id":f.map,"cell":[f.cell.x,f.cell.y],"client":""})
 if not _current(b,f):return
 b.publish()
 if not _current(b,f):return
 b.publish() # Preserve Brothers.publish_warp then OriginalQuests publication.

## Cancellation-only caller scope: it cannot mint/refresh a purchase or entry.
## Empty is the exact old caller path; a real scope is never built from reply.ok.
func begin_reply(b,runner)->Dictionary:
 if not b._fee_lobby_ticket_enabled() or _live.is_empty() or not is_same(runner,b.quest_auto):return {}
 if not _reply.is_empty():return {"reentrant":true}
 var record:Variant=b.session._profile.get("quest_auto_fee_lifecycle")
 if not Journal.valid(record) or record.current.purchase.state!="ticket_committed":return {}
 var g:Dictionary={"cap":_live,"session":b.session,"runner":runner,"identity":runner.identity,"checkpoint":runner.identity.checkpoint(),"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"source":{}}
 _reply=g
 return g
func _reply_valid(b,g:Dictionary)->bool:
 return is_same(_reply,g) and _owner(b,g.cap) and is_same(g.session,b.session) and is_same(g.runner,b.quest_auto) and is_same(g.identity,b.quest_auto.identity) and b.quest_auto.identity.checkpoint()==g.checkpoint and is_same(b.session._profile,g.profile_ref) and Exact.same_value(b.session._profile,g.profile) and b.last_saved_payload==g.cache and b.quest_save_serial==g.serial
func capture_source(b,source:Dictionary)->void:
 if _reply.is_empty() or not _reply_valid(b,_reply) or not is_same(b._quest_source_call,source):return
 if not _reply.source.is_empty():return
 _reply.source=source
func finish_reply(b,runner,g:Dictionary)->bool:
 if g.is_empty():return true
 if not is_same(_reply,g):return false
 var valid:bool=is_same(runner,g.runner) and _reply_valid(b,g) and b._quest_source_call.is_empty()
 if valid and not g.source.is_empty():
  valid=is_same(b.quest_auto.source_frame,g.source.frame)
  if valid and not b.original_quests.pending.is_empty():valid=g.source.frame.owns_pending(str(b.original_quests.pending.get("token","")))
 _reply={}
 return valid
func position_prepared(b,source:Dictionary,packet:Dictionary)->void:
 if _op.is_empty() or _reply.is_empty():return
 var f:Dictionary=_op
 if not f.committed or not is_same(f.reply,_reply) or not is_same(f.source,source) or not is_same(_reply.source,source) or not is_same(b._quest_source_call,source):return
 var expected:Dictionary=f.checkpoint.duplicate(true);expected.revision+=1
 if not _owner(b,f.cap) or not is_same(b.quest_auto.identity,f.identity) or b.quest_auto.identity.checkpoint()!=expected or source.identity!=expected:return
 if not source.get("position_claimed",false) or not packet.get("quest_source_landing",false) or not b.quest_auto.source_position_current(b,source,packet):return
 if b._dispatch_boundary_depth!=f.boundary+1 or b._depth!=f.depth or b._observer_depth!=f.observer or b._flush_depth!=f.flush or b._dispatch_epoch!=f.epoch:return
 if not is_same(b.session._profile,f.profile_ref) or not Exact.same_value(b.session._profile,f.profile) or b.last_saved_payload!=f.cache or b.quest_save_serial!=f.serial:return
 f.checkpoint=expected;_reply.checkpoint=expected

func source_guard(source:Dictionary)->Dictionary:
 return _reply if not _reply.is_empty() and is_same(_reply.source,source) else {}
func finalize_source_allowed(b,source:Dictionary,g:Dictionary)->bool:
 if g.is_empty():return true
 return is_same(_reply,g) and is_same(g.source,source) and is_same(b._quest_source_call,source) and _owner(b,g.cap) and is_same(b.session,g.session) and is_same(b.quest_auto,g.runner) and is_same(b.quest_auto.identity,g.identity)

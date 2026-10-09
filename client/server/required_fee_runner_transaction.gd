extends RefCounted
## D0 dormant primitive: no production issuer or route caller is installed.
## Night decision pending user confirmation: independent unknown-IO save hold.
const Exact=preload("res://server/fee_start_journal_writer.gd")
const Manual=preload("res://server/required_fee_transaction.gd")
const Fact=preload("res://server/required_fee_runner_fact.gd")
const HOLD_TEXT="必需费用结果未确认，请重新进入存档"
var _cap:Dictionary={}
var _issued:RefCounted
var _op:Dictionary={}
var _hold:Dictionary={}
var rejected_saves:int=0
func revoke()->void:_cap={}
func detach(connection:int,binding:Variant)->void:
 if not _cap.is_empty() and _cap.connection==connection and is_same(_cap.binding,binding):_cap={}
func _idle(b)->bool:
 return b.session!=null and not b._fee_lobby_ticket.held(b) and not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty() and not b.automation.running and not b.automation.hunt_running and not b.automation.flow_active() and not b.stationary.running and b._fee_start_intent._loot_idle(b) and b._fee_attempt_writer_call==null and b._fee_attempt_close_call==null and b._quest_auto_stop_operation_call==null and b._fee_resume_sidecar_call==null and b._quest_source_call.is_empty()
func _source(kind:String,source:String)->bool:
 return (kind=="permit" and source in ["genout/ss_1100_86_107","genout/ss_4000_99_85"]) or (kind=="seimu" and source==Manual.GATE)
func prepare(b,issuer:RefCounted,kind:String,source:String)->RefCounted:
 # Only a future trusted producer may install this issuer. Default is null.
 # Neither a public result nor a client command can set it; D0 has no caller.
 if issuer==null or not b._required_fee_runner_enabled() or not is_same(issuer,b._required_fee_runner_authority) or is_same(issuer,_issued):return null
 if not _source(kind,source) or not _cap.is_empty() or not _op.is_empty() or held(b) or not _idle(b):return null
 var q=b.quest_auto
 if not q.running or not q.internal or q.detached or q.identity.run_id.is_empty() or q.identity.step_id.is_empty() or b._depth<=0 or b.save_path.is_empty():return null
 var binding:Variant=b._fee_bindings.get(q.connection)
 var owner:Dictionary=Exact.owner(b.session._profile)
 if not binding is RefCounted or owner.is_empty() or not b.original_quests.pending.is_empty():return null
 _issued=issuer
 _cap={"call":RefCounted.new(),"issuer":issuer,"session":weakref(b.session),"runner":weakref(q),"identity":weakref(q.identity),"router":weakref(b.original_quests),"automation":weakref(b.automation),"arrival_owner":weakref(b.quest_arrival),"auto_token":b.automation.start_lifetime,"checkpoint":q.identity.checkpoint(),"phase":q.phase,"client":q.client,"source_frame":weakref(q.source_frame) if q.source_frame!=null else null,"owner":owner,"path":b.save_path,"account":b.account_name,"binding":binding,"connection":q.connection,"kind":kind,"source":source}
 return _cap.call
func _owner(b,h:Dictionary)->bool:
 if h.is_empty() or not b._required_fee_runner_enabled() or not is_same(b._required_fee_runner_authority,h.issuer):return false
 if not is_same(b.session,h.session.get_ref()) or not is_same(b.quest_auto,h.runner.get_ref()) or not is_same(b.quest_auto.identity,h.identity.get_ref()) or not is_same(b.original_quests,h.router.get_ref()) or not is_same(b.automation,h.automation.get_ref()):return false
 if not is_same(b.quest_arrival,h.arrival_owner.get_ref()):return false
 if b.quest_auto.phase!=h.phase or b.quest_auto.client!=h.client or not is_same(b.quest_auto.source_frame,h.source_frame.get_ref() if h.source_frame!=null else null):return false
 if not is_same(b.automation.start_lifetime,h.auto_token) or b.quest_auto.identity.checkpoint()!=h.checkpoint or not b.quest_auto.running or not b.quest_auto.internal or b.quest_auto.detached:return false
 return b.save_path==h.path and b.account_name==h.account and Exact.same_value(Exact.owner(b.session._profile),h.owner) and b.quest_auto.connection==h.connection and is_same(b._fee_bindings.get(h.connection),h.binding)
func held(b)->bool:
 return not _hold.is_empty() and b._required_fee_runner_enabled() and is_same(_hold.session.get_ref(),b.session) and b.save_path==_hold.path and b.account_name==_hold.account and Exact.same_value(Exact.owner(b.session._profile),_hold.owner)
func refuse_save(b)->bool:
 if not _op.is_empty() and is_same(b.session,_op.session) and b.save_path==_op.path and Exact.same_value(Exact.owner(b.session._profile),_op.cap.owner):return true
 if not held(b):return false
 rejected_saves+=1;b.session.last_error=HOLD_TEXT
 print("REQUIRED_FEE_SAVE_HOLD count=",rejected_saves)
 return true
func before_load(b,path:String)->Dictionary:
 revoke()
 if not held(b) or path!=_hold.path:return {}
 return {"hold":_hold,"session":b.session,"path":path,"previous":b.session._required_fee_loaded_receipt}
func stopped_for_load(b,h:Dictionary)->bool:
 return not h.is_empty() and is_same(_hold,h.hold) and held(b) and is_same(h.session,b.session) and not b.quest_auto.running and not b.automation.running and not b.automation.hunt_running and not b.automation.flow_active() and not b.battle_open and b.session._pending.is_empty()
func after_load(b,h:Dictionary)->void:
 if h.is_empty() or not is_same(_hold,h.hold) or not held(b) or not is_same(b.session,h.session):return
 var r:Dictionary=b.session._required_fee_loaded_receipt
 if r.is_empty() or is_same(r,h.previous) or not is_same(r.hold,_hold) or r.path!=h.path or r.source!="primary" or not is_same(b.session._profile,r.profile_ref) or not Exact.same_value(b.session._profile,r.profile):return
 var row:Dictionary=b.session._read_fee_attempt_file(h.path,r.bytes)
 if not is_same(_hold,h.hold) or not held(b) or not is_same(b.session._required_fee_loaded_receipt,r) or not is_same(b.session._profile,r.profile_ref) or not Exact.same_value(b.session._profile,r.profile):return
 if Exact.row_state(row,true,r.bytes)!="matches":return
 if is_same(b.session._required_fee_hold,_hold):b.session._required_fee_hold={}
 _hold={};b.session._required_fee_loaded_receipt={}
func _current(b,f:Dictionary)->bool:
 if not is_same(_op,f) or not is_same(b._fee_attempt_writer_call,f.claim) or not _owner(b,f.cap):return false
 if b._fee_lobby_ticket.held(b) or not is_same(b.stationary,f.stationary) or b.automation.compact_active!=f.compact:return false
 if not is_same(b.session._pending,f.pending_ref) or not is_same(b.session._loot_settlement,f.loot_ref) or not is_same(b.original_quests.pending,f.page_ref):return false
 if not is_same(b.battle,f.battle) or b.quest_visit_guard!=f.visit_guard:return false
 if not f.marked and Manual.arrival(b)!=f.arrival:return false
 if not is_same(b.session,f.session) or not is_same(b.session._profile,f.profile_ref) or not Exact.same_value(b.session._profile,f.profile) or b.last_saved_payload!=f.cache or b.quest_save_serial!=f.serial:return false
 if b._depth!=f.depth or b._dispatch_epoch!=f.epoch or b._dispatch_boundary_depth!=f.boundary or b._observer_depth!=f.observer or b._flush_depth!=f.flush:return false
 return b.automation.position_map==f.map and b.automation.position_cell==f.cell and b.original_quests.pending.is_empty() and not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty() and not b.automation.running and not b.automation.hunt_running and not b.automation.flow_active() and not b.stationary.running and b._fee_start_intent._loot_idle(b) and b._fee_attempt_close_call==null and b._quest_auto_stop_operation_call==null and b._fee_resume_sidecar_call==null and b._quest_source_call.is_empty()
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
 _hold={"session":weakref(f.session),"path":f.path,"account":f.cap.account,"owner":f.cap.owner.duplicate(true),"run":f.cap.checkpoint.run_id,"transaction_id":f.transaction_id,"host":weakref(b)}
 f.session._required_fee_hold=_hold
func execute(b,call:RefCounted)->Dictionary:
 if _cap.is_empty() or not is_same(_cap.call,call) or not _op.is_empty():return {"ok":false,"stage":"capability_rejected"}
 var h:Dictionary=_cap;_cap={}
 if not _owner(b,h) or not _idle(b) or held(b):return {"ok":false,"stage":"scope_rejected"}
 var source:Dictionary=Manual.capture(b,h.kind,h.source)
 if not _owner(b,h) or not Manual.current(b,source):return {"ok":false,"stage":"capture_changed"}
 if h.kind=="permit":
  if not Manual.near(b,Manual.vendor(b,h.source)):return {"ok":false,"stage":"source_rejected"}
  if b.session.has_travel_pass():return {"ok":true,"stage":"already_owned","charged":false}
 else:
  var data:Dictionary=Manual.lock_data()
  if not data.has("seimu") or not Manual.gate_matches(b,h.source,data.seimu.branches[0]):return {"ok":false,"stage":"source_rejected"}
  source.branch=data.seimu.branches[0].duplicate(true)
  var arrival_reason:String=b.quest_arrival.check_action(b,data.seimu,source.branch,"FREEWARP")
  if not _owner(b,h) or not Manual.current(b,source) or not arrival_reason.is_empty():return {"ok":false,"stage":"arrival_rejected"}
 var error:String=Manual.guard_error(b,source)
 if not _owner(b,h) or not Manual.current(b,source) or not error.is_empty():return {"ok":false,"stage":"guard_rejected"}
 var c:Dictionary=Manual.candidate(b,source)
 if c.is_empty() or not _owner(b,h) or not Manual.current(b,source):return {"ok":false,"stage":"candidate_rejected"}
 var expected:Dictionary=source.before.duplicate(true)
 if not Fact.integer(expected.player.get("gold"),200 if h.kind=="permit" else 300,Fact.MAX_GOLD):return {"ok":false,"stage":"gold_rejected"}
 expected.player.gold-=200 if h.kind=="permit" else 300
 if h.kind=="permit":expected.travel_pass=true
 else:expected.location={"map_id":31301,"x":10,"y":104}
 if not Exact.same_value(c,expected):return {"ok":false,"stage":"delta_rejected"}
 var f:Dictionary={"call":RefCounted.new(),"claim":RefCounted.new(),"cap":h,"session":b.session,"path":b.save_path,"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"before":source.before.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"map":b.automation.position_map,"cell":b.automation.position_cell,"depth":b._depth,"epoch":b._dispatch_epoch,"boundary":b._dispatch_boundary_depth,"observer":b._observer_depth,"flush":b._flush_depth,"candidate":c,"expected":expected,"payload":JSON.stringify(expected),"transaction_id":Crypto.new().generate_random_bytes(16).hex_encode(),"kind":h.kind,"source":h.source,"pending_ref":b.session._pending,"loot_ref":b.session._loot_settlement,"page_ref":b.original_quests.pending,"stationary":b.stationary,"compact":b.automation.compact_active,"battle":b.battle,"visit_guard":b.quest_visit_guard,"arrival":Manual.arrival(b),"executing":false,"physical_ran":false,"io_entered":false,"marked":false,"durable":true,"fact":{}}
 _op=f;b._fee_attempt_writer_call=f.claim
 b._persist_required_fee_runner(f.call,c)
 if f.marked and _current(b,f):_publish(b,f)
 if not f.marked and _current(b,f):b.quest_auto.stop(b,HOLD_TEXT if held(b) else "必需费用未完成，本次不再自动提交。",false)
 if is_same(b._fee_attempt_writer_call,f.claim):b._fee_attempt_writer_call=null
 if is_same(_op,f):_op={}
 # Immutable profile fact survives late wrapper/owner changes. Legacy UI treats
 # automatic_required as unrecognized and only displays optional original text.
 if not f.fact.is_empty():b._emit({"type":"quest_result","fee_fact":f.fact.duplicate(true)})
 return {"ok":f.marked,"stage":"committed" if f.marked else "unconfirmed","charged":f.marked}
func persist(b,call:RefCounted,candidate:Dictionary)->bool:
 if _op.is_empty() or not is_same(_op.call,call) or _op.executing:return false
 var f:Dictionary=_op;f.executing=true
 if not _current(b,f) or not is_same(candidate,f.candidate) or not Exact.same_value(candidate,f.expected) or not f.session._valid_profile(candidate):return false
 f.pre=_rows(b,f)
 if not _known(f.pre) or Exact.row_state(f.pre[0],true,f.cache.to_utf8_buffer())!="matches" or Exact.row_state(f.pre[2],false,PackedByteArray())!="matches":return false
 var written:bool=b._write_required_fee_runner(f.call,candidate)
 var after:Array=_rows(b,f)
 if not _known(after):_quarantine(b,f);return false
 var landed:bool=Exact.row_state(after[0],true,f.payload.to_utf8_buffer())=="matches"
 if not landed:
  if Exact.row_state(after[0],true,f.pre[0].bytes)!="matches":_quarantine(b,f)
  return false
 if not f.physical_ran:return false
 b.session._profile=candidate.duplicate(true);b.last_saved_payload=f.payload;b.quest_save_serial+=1
 f.profile_ref=b.session._profile;f.profile=b.session._profile.duplicate(true);f.cache=b.last_saved_payload;f.serial=b.quest_save_serial
 if not written or Exact.row_state(after[1],true,f.pre[0].bytes)!="matches" or Exact.row_state(after[2],false,PackedByteArray())!="matches":return false
 f.marked=true;f.committed=f.expected.duplicate(true);f.committed_serial=f.serial
 f.fact=Fact.from_committed(f)
 return true
func write_physical(b,call:RefCounted,candidate:Dictionary)->bool:
 if _op.is_empty() or not is_same(_op.call,call):return false
 var f:Dictionary=_op
 if not f.executing or f.physical_ran or not _current(b,f) or not is_same(candidate,f.candidate) or not Exact.same_value(candidate,f.expected):return false
 var last:Array=_rows(b,f)
 if not _known(last):return false
 for i in range(3):
  if Exact.row_state(last[i],f.pre[i].exists,f.pre[i].get("bytes",PackedByteArray()))!="matches":return false
 f.physical_ran=true;f.io_entered=true
 var file=FileAccess.open(f.path+".tmp",FileAccess.WRITE)
 if file==null:return false
 file.store_string(f.payload);file.flush()
 var error:Error=file.get_error();file.close()
 if error!=OK or not _current(b,f):return false
 var absolute:String=ProjectSettings.globalize_path(f.path)
 if DirAccess.copy_absolute(absolute,absolute+".bak")!=OK or not _current(b,f):return false
 return DirAccess.rename_absolute(absolute+".tmp",absolute)==OK
func _publish(b,f:Dictionary)->void:
 if not _current(b,f):return
 if f.kind=="seimu":
  var data:Dictionary=Manual.lock_data()
  if not data.has("seimu") or not _current(b,f):return
  b.quest_arrival.action_committed(b,data.seimu,data.seimu.branches[0],"FREEWARP")
  if not _current(b,f):return
  f.map=31301;f.cell=Vector2i(10,104)
  b.automation.position_changed(f.map,f.cell,true,"script")
  if not _current(b,f):return
  b._emit({"type":"position","map_id":31301,"cell":[10,104],"client":""})
  if not _current(b,f):return
 b.publish()

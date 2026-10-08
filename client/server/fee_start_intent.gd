extends RefCounted
## Default-closed job2/event44 explicit intent only. No purchase adapter.
const Exact=preload("res://server/fee_start_journal_writer.gd")
const Journal=preload("res://server/fee_attempt_lifecycle.gd")
const Identity=preload("res://server/quest_auto_state.gd")
var _frame:Dictionary={}
var _live:Dictionary={}
var _seen:Dictionary={} # One high-water diagnostic per attached real binding; no durable history.
var _delivery:Dictionary={}
func classified(command:Dictionary)->bool:
 var id:Variant=command.get("quest_id")
 return (id is int or id is float) and id==2
func has_call()->bool:return not _frame.is_empty()
func current_call()->RefCounted:return _frame.get("call")
func owns_call(call:RefCounted)->bool:return has_call() and is_same(call,_frame.call)
func revoke()->void:
 _frame={};_live={};_delivery={} # Same-binding diagnostics survive load but are not authorities.
func detach(b,connection:int,binding:Variant)->void:
 if binding!=null:_seen.erase(binding)
 if not _live.is_empty() and _live.connection==connection and is_same(_live.binding,binding):_live={}
 if has_call() and _frame.connection==connection and is_same(_frame.binding,binding):
  b._fee_start_journal_writer.revoke_start(_frame.call)
  _frame={}
func _failure(reason:String,seq:int=0)->Dictionary:
 return {"ok":false,"type":"rejected","seq":seq,"reason":reason,"persisted_intent":false}
func _scope(b)->bool:
 return b._depth==1 and b._dispatch_boundary_depth==1 and b._observer_depth==0 and b._flush_depth==0 and b._quest_source_call.is_empty() and not b.quest_auto.internal and _loot_idle(b)
func _loot_idle(b)->bool:
 if not b.automation.loot_scope.is_empty() or not b.session._loot_failure_active.is_empty() or not b.session._loot_failure_write.is_empty() or b._loot_outer_resume_call!=null or not b._loot_resume_envelope.is_empty():return false
 var t=b.quest_loot
 return t.consume_call==null and t.attempt_call==null and t.attempt_frame.is_empty() and t.heartbeat_call==null and t.anchor_ms<0 and t.initial_failure.is_empty() and t.followup.is_empty() and t.public_start_call==null and t.initial_e2.is_empty() and t.ready_frame.is_empty() and t.open_obligation.is_empty() and t.close_pending.is_empty() and t.failed_initial_resume.is_empty() and t.failed_followup_resume.is_empty()
func _capture(b,connection:int,binding:RefCounted)->Dictionary:
 return {"session":b.session,"owner":Exact.owner(b.session._profile),"path":b.save_path,"account":b.account_name,
  "connection":connection,"binding":binding,"runner":b.quest_auto,"identity":b.quest_auto.identity,"checkpoint":b.quest_auto.identity.checkpoint(),
  "timer":b.quest_loot,"timer_token":b.quest_loot.lifetime,"automation":b.automation,"auto_token":b.automation.start_lifetime,"epoch":b._dispatch_epoch,
  "catalog":b.quest_catalog,"events":b.quest_catalog.enabled_events.duplicate(true),"jobs":b.quest_catalog.jobs.duplicate(true),"map":b.automation.position_map,"cell":b.automation.position_cell,
  "source":b.quest_auto.source_frame,"client_before":b.quest_auto.client,"connection_before":b.quest_auto.connection,
  "profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial}
func _owner(b,f:Dictionary)->bool:
 return not f.is_empty() and is_same(b.session,f.session) and b.save_path==f.path and b.account_name==f.account \
  and Exact.same_value(Exact.owner(b.session._profile),f.owner) and is_same(b._fee_bindings.get(f.connection),f.binding) \
  and is_same(b.quest_auto,f.runner) and is_same(b.quest_loot,f.timer) and is_same(b.quest_loot.lifetime,f.timer_token) and is_same(b.automation,f.automation) and is_same(b.automation.start_lifetime,f.auto_token)
func writer_current(b,call:RefCounted)->bool:
 if not owns_call(call) or not _owner(b,_frame) or not _scope(b) or b._dispatch_epoch!=_frame.epoch:return false
 if not is_same(b.quest_catalog,_frame.catalog) or not Exact.same_value(b.quest_catalog.enabled_events,_frame.events) or not Exact.same_value(b.quest_catalog.jobs,_frame.jobs) or b.automation.position_map!=_frame.map or b.automation.position_cell!=_frame.cell:return false
 return not b.quest_auto.running and is_same(b.quest_auto.identity,_frame.identity) and b.quest_auto.identity.checkpoint()==_frame.checkpoint \
  and is_same(b.quest_auto.source_frame,_frame.source) and b.quest_auto.client==_frame.client_before and b.quest_auto.connection==_frame.connection_before
func _finish(b,call:RefCounted,reply:Dictionary)->Dictionary:
 if owns_call(call):
  var entry:Dictionary=_frame.entry
  if is_same(_seen.get(_frame.binding),entry):entry.reply=reply.duplicate(true)
  _frame={}
  b._fee_start_journal_writer.revoke_start()
 return reply
func start(b,command:Dictionary)->Dictionary:
 if not b._fee_start_intent_enabled() or not classified(command):return _failure("收费启动尚未开放。")
 var seq_value:Variant=command.get("seq")
 var connection_value:Variant=command.get("_quest_connection")
 if not seq_value is int or seq_value<=0 or not connection_value is int or connection_value==-1:return _failure("收费启动缺少可信连接和序号。")
 var seq:int=seq_value
 var connection:int=connection_value
 for key in command:
  if key not in ["type","seq","quest_id","client","_quest_connection"]:return _failure("收费启动不接受客户端资格字段。",seq)
 if not command.get("type") is String or command.type!="quest_auto_start" or not command.get("client") is String or command.client.is_empty():return _failure("收费启动设备字段无效。",seq)
 var binding:Variant=b._fee_bindings.get(connection)
 if not binding is RefCounted or not _scope(b) or b.save_path.is_empty() or Exact.owner(b.session._profile).is_empty():return _failure("收费启动归属无法确认。",seq)
 if has_call():return _failure("收费启动正在处理。",seq)
 var previous_command:Dictionary=_seen.get(binding,{})
 if not previous_command.is_empty():
  if seq==previous_command.seq and Exact.same_value(command,previous_command.command):
   var duplicate:Dictionary=previous_command.reply.duplicate(true);duplicate["duplicate"]=true
   if _live.is_empty() or not is_same(_live.binding,binding) or not live_current(b):duplicate["ok"]=false;duplicate["stale"]=true
   return duplicate
  if seq<=previous_command.seq:return _failure("收费启动序号已使用。",seq)
 var f:Dictionary=_capture(b,connection,binding)
 var call:=RefCounted.new();f.call=call;_frame=f
 f.entry={"seq":seq,"command":command.duplicate(true),"reply":_failure("收费启动尚未完成。",seq)}
 _seen[binding]=f.entry
 var prepared:Dictionary=b.quest_auto.prepare_start(b,command)
 if not writer_current(b,call):return _finish(b,call,_failure("启动校验期间归属已变化。",seq))
 if not Exact.strict_true(prepared.get("ok")):return _finish(b,call,prepared)
 if not Exact.strict_true(prepared.get("source")) or not prepared.get("quest_id") is int or prepared.quest_id!=2:return _finish(b,call,_failure("未审核的收费任务。",seq))
 if not is_same(b.session._profile,f.profile_ref) or not Exact.same_value(b.session._profile,f.profile) or b.last_saved_payload!=f.cache or b.quest_save_serial!=f.serial:return _finish(b,call,_failure("启动校验改变了存档。",seq))
 _live={}
 var staged=Identity.new();staged.begin()
 var candidate:Dictionary=f.profile.duplicate(true)
 var record:Dictionary
 if candidate.has("quest_auto_fee_lifecycle"):
  var previous:Variant=candidate.quest_auto_fee_lifecycle
  if not Journal.valid(previous):return _finish(b,call,_failure("原收费记录无法确认。",seq))
  var replaced:Dictionary=Journal.replace_closed_for_start(previous,f.owner.profile_id,f.owner.character_id,staged.run_id,false)
  if not Exact.strict_true(replaced.get("ok")):return _finish(b,call,_failure("上次收费意图尚未安全关闭。",seq))
  record=replaced.candidate
 else:record=Journal.empty_record(f.owner.profile_id,f.owner.character_id,staged.run_id,false)
 candidate.quest_auto_fee_lifecycle=record
 f.staged=staged;f.prepared=prepared;f.record=record.duplicate(true)
 var handle:Dictionary=b._begin_fee_start_journal_frame(candidate)
 if handle.is_empty():return _finish(b,call,_failure("收费启动存档前置未核实。",seq))
 var diagnostic:Dictionary=b._persist_fee_start_journal_pair(handle)
 b._end_fee_start_journal_frame(handle)
 var permission:Dictionary=b._fee_start_journal_writer.take_start(b,self,call)
 if permission.is_empty():
  var refused:Dictionary=_failure("收费启动双份意图尚未核实。",seq)
  refused.writer=diagnostic;refused.run_id=staged.run_id
  return _finish(b,call,refused)
 f.permission=permission;f.installing=true;f.installed=false
 b.quest_auto.install_fee_start(b,prepared,staged)
 if not owns_call(call) or not f.installed:
  var lost:Dictionary=_failure("收费意图已写入，运行归属已变化。",seq)
  lost.persisted_intent=true;lost.run_id=staged.run_id;lost.stale=true
  return _finish(b,call,lost)
 _live={"token":RefCounted.new(),"session":f.session,"owner":f.owner,"path":f.path,"account":f.account,"connection":connection,"binding":binding,
  "runner":f.runner,"timer":f.timer,"timer_token":f.timer_token,"automation":f.automation,"auto_token":f.auto_token,"identity":staged,"checkpoint":staged.checkpoint(),"source":b.quest_auto.source_frame,
  "record":record.duplicate(true),"profile_ref":b.session._profile,"profile":b.session._profile.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"purchase_allowed":false}
 b.publish()
 var accepted:bool=owns_call(call) and live_current(b)
 var result:Dictionary={"ok":accepted,"seq":seq,"persisted_intent":true,"run_id":staged.run_id}
 if not accepted:result.merge({"stale":true,"reason":"收费意图已保存；当前运行归属已变化。"})
 if accepted:_delivery={"reply":result,"live":_live,"binding":binding,"entry":f.entry}
 return _finish(b,call,result)
func install_permitted(b,runner,prepared:Dictionary,staged:RefCounted)->bool:
 if not has_call() or not _frame.get("installing",false) or _frame.get("installed",false):return false
 var f:Dictionary=_frame
 if not writer_current(b,f.call) or not is_same(runner,f.runner) or not is_same(prepared,f.prepared) or not is_same(staged,f.staged):return false
 var p:Dictionary=f.permission
 return is_same(b.session._profile,p.profile_ref) and Exact.same_value(b.session._profile,p.profile) and b.last_saved_payload==p.cache and b.quest_save_serial==p.serial
func mark_installed(b,runner,staged:RefCounted)->void:
 if not has_call() or not _frame.get("installing",false):return
 if not _owner(b,_frame) or not is_same(runner,_frame.runner) or not is_same(staged,_frame.staged) or not is_same(runner.identity,staged) or not runner.running:return
 _frame.installed=true;_frame.installing=false
func _live_owner(b,f:Dictionary)->bool:
 return _owner(b,f) and b.quest_auto.running and not b.quest_auto.detached and is_same(b.quest_auto.identity,f.identity) and b.quest_auto.identity.checkpoint()==f.checkpoint \
  and is_same(b.quest_auto.source_frame,f.source) and b.quest_auto.connection==f.connection and is_same(b.session._profile,f.profile_ref) \
  and Exact.same_value(b.session._profile.get("quest_auto_fee_lifecycle"),f.record)
func live_current(b)->bool:
 if _live.is_empty():return false
 var valid:bool=_live_owner(b,_live) and b.last_saved_payload==_live.cache and b.quest_save_serial==_live.serial and Exact.same_value(b.session._profile,_live.profile)
 if not valid:_live={}
 return valid
## Controlled actual Backend save only. It advances an existing token, never mints.
func begin_save(b)->Dictionary:
 if _live.is_empty():return {}
 if not _live_owner(b,_live) or b.last_saved_payload!=_live.cache or b.quest_save_serial!=_live.serial:
  _live={};return {}
 return {"live":_live,"token":_live.token,"serial":_live.serial}
func finish_save(b,handle:Dictionary,saved:bool)->void:
 if handle.is_empty() or _live.is_empty() or not is_same(handle.live,_live) or not is_same(handle.token,_live.token):return
 if not saved or not _live_owner(b,_live) or b.quest_save_serial!=handle.serial+1 or b.last_saved_payload!=JSON.stringify(b.session._profile):
  _live={};return
 _live.profile=b.session._profile.duplicate(true);_live.cache=b.last_saved_payload;_live.serial=b.quest_save_serial

## The real dispatch return consumes this ref-bound observation after event flush.
## It can downgrade an ACK, never install a run or mint a permission.
func take_delivery(reply:Dictionary)->Dictionary:
 if _delivery.is_empty() or not is_same(reply,_delivery.reply):return {}
 var guard:Dictionary=_delivery;_delivery={}
 return guard
func finish_delivery(b,guard:Dictionary,reply:Dictionary)->void:
 if guard.is_empty() or not is_same(reply,guard.reply):return
 if not is_same(_live,guard.live) or not live_current(b):
  reply.ok=false;reply.type="rejected";reply.stale=true;reply.reason="收费意图已保存；发布期间运行归属已变化。"
 if is_same(_seen.get(guard.binding),guard.entry):guard.entry.reply=reply.duplicate(true)

extends "res://tests/quest_auto_loot_state_test.gd"
## Public production start with explicit closed negative fixture and post-writer
## reentry observation; the command still uses Backend,
## GameSession, E1 and the original field-step path.
const Backend=preload("res://server/backend.gd")
const MapFile=preload("res://scripts/map_file.gd")
const Wait=preload("res://tests/support/wait.gd")
class ClosedBackend:
 extends "res://server/backend.gd"
 func _quest_loot_public_enabled()->bool:return false
class EnabledBackend:
 extends "res://server/backend.gd"
 var replace_identity_after_open:=false
 var replaced_identity:=false
 var field_calls:=0
 var field_generation:=-1
 var field_process_depth:=-1
 var field_had_initial_frame:=false
 var replaced_identity_value:Dictionary={}
 func _loot_settlement_written(payload:String,owner,path:String)->void:
  super._loot_settlement_written(payload,owner,path)
  if not replace_identity_after_open or owner!=session or path!=save_path:return
  var saved=JSON.parse_string(payload)
  if saved is Dictionary and saved.get("quest_loot",{}).get("entries",{}).get("jewels:hunt:2760",{}).get("open_span",false):
   replace_identity_after_open=false
   quest_auto.identity.begin();quest_auto.identity.select_step("jewels:hunt:2760")
   replaced_identity_value=quest_auto.identity.checkpoint()
   replaced_identity=true
 func _cmd_field_step(command:Dictionary)->Dictionary:
  field_calls+=1
  field_generation=_normal_process_generation
  field_process_depth=_process_depth
  field_had_initial_frame=not quest_loot.initial_e2.is_empty()
  var reply:Dictionary=super._cmd_field_step(command)
  set_process(false)
  return reply
func fresh_path(path:String)->bool:
 for candidate in [path,path+".tmp",path+".bak",path.get_basename()+".stop-log.jsonl",path+".resume.json"]:
  if FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(candidate):
   check(false,"Independent start fixture path is new: "+candidate)
   return false
 return true
func read_disk(path:String)->Dictionary:
 if not FileAccess.file_exists(path):return {"ok":false,"path":path,"exists":false,"error":ERR_FILE_NOT_FOUND}
 var file:=FileAccess.open(path,FileAccess.READ)
 var open_error:int=FileAccess.get_open_error()
 if file==null:return {"ok":false,"path":path,"exists":true,"open_error":open_error}
 var declared:int=file.get_length()
 file.seek(0)
 var bytes:PackedByteArray=file.get_buffer(declared)
 var read_error:int=file.get_error()
 file.close()
 var actual:int=bytes.size()
 var hasher:=HashingContext.new()
 var hash_error:int=hasher.start(HashingContext.HASH_SHA256)
 if hash_error==OK:hash_error=hasher.update(bytes)
 var digest:String=hasher.finish().hex_encode() if hash_error==OK else ""
 return {"ok":open_error==OK and read_error==OK and declared==actual and hash_error==OK,"path":path,"exists":true,"declared":declared,"actual":actual,"open_error":open_error,"read_error":read_error,"hash_error":hash_error,"bytes":bytes,"sha256":digest}
func same_rejected_state(b,command:Dictionary,label:String)->bool:
 var before:Dictionary=b.session.snapshot()
 var cache:String=b.last_saved_payload
 var serial:int=b.quest_save_serial
 var disk:Dictionary=read_disk(b.save_path)
 if failures or not disk.get("ok",false):return false
 var reply:Dictionary=b.handle(command)
 check(not reply.get("ok",true) and reply.get("persisted") is bool and not reply.persisted and reply.get("type","")=="rejected","Pre-write rejection has explicit persisted=false: "+label)
 if failures:return false
 var after:Dictionary=read_disk(b.save_path)
 check(after.get("ok",false) and after.bytes==disk.bytes and after.sha256==disk.sha256 and b.session.snapshot()==before and b.last_saved_payload==cache and b.quest_save_serial==serial,"Rejected request preserves full profile/cache/serial/primary bytes: "+label)
 return failures==0
func prepare_source(b,path:String,closed_budget:bool=false)->bool:
 b.set_process(false);b.save_path=path
 b.session.OriginalEquipment.add(b.session._profile,2764)
 var map:Dictionary=MapFile.load_map(b.quest_helper.places.file(100))
 if not b.quest_loot.admission_terrain_valid(map):return false
 var links:Dictionary=b.quest_helper.places.links(100)
 var found:=false
 for y in range(341,413):
  for x in range(621,646):
   var cell:=Vector2i(x,y)
   if b.encounter_catalog.area_at(100,cell).get("id")!=56:continue
   if not b.quest_helper.safe(map,cell,{},links):continue
   b.automation.position_changed(100,cell,true,"project")
   found=true;break
  if found:break
 if not found:return false
 if closed_budget:
  var acquired:Dictionary=State.acquire(State.empty(),KEY,ID,RUN,30,0)
  if not acquired.get("ok",false):return false
  var opened:Dictionary=State.open(acquired.ledger,KEY,State.identity(acquired.ledger.entries[KEY]))
  if not opened.get("ok",false):return false
  var closed:Dictionary=State.progress(opened.ledger,KEY,State.identity(opened.ledger.entries[KEY]),1000,true)
  if not closed.get("ok",false):return false
  b.session._profile.quest_loot=closed.ledger
 return b.save()
func start_command(seq:int,connection:int)->Dictionary:
 return {"type":"quest_loot_start","seq":seq,"_quest_connection":connection}
func run()->void:
 # Production is open; unauthenticated input still cannot create an E1.
 var production:=Backend.new();production.set_process(false)
 check(Backend.QUEST_LOOT_PUBLIC_ENABLED and production._quest_loot_public_enabled() and production._capabilities().get("quest_loot_enabled")==true,"Actual production constant/getter/projection enable public loot")
 var production_before:Dictionary=production.session.snapshot()
 var unbound:Dictionary=production.handle({"type":"quest_loot_start","seq":1,"_quest_connection":404})
 check(not unbound.get("ok",true) and unbound.get("persisted")==false and production.session.snapshot()==production_before and production.last_saved_payload.is_empty(),"Open production still rejects an unattached transport without mutation")
 production.free()
 if failures:quit(1);return
 # Explicit closed fixture retains every capability-revocation negative case.
 var closed:=ClosedBackend.new();closed.set_process(false)
 var caps:Dictionary=closed._capabilities()
 var before:Dictionary=closed.session.snapshot()
 var disabled:Dictionary=closed.handle({"type":"quest_loot_start","seq":1,"_quest_connection":404})
 check(caps.get("quest_loot_enabled") is bool and not caps.quest_loot_enabled and not closed._quest_loot_public_enabled(),"Explicit ClosedBackend projects the immutable closed server getter")
 check(not disabled.get("ok",true) and disabled.get("persisted") is bool and not disabled.persisted and closed.session.snapshot()==before and closed.last_saved_payload.is_empty(),"Explicitly disabled handler rejects with persisted=false and no session mutation")
 var forged:Dictionary=closed.handle({"type":"quest_loot_start","seq":1,"_quest_connection":404,"quest_loot_enabled":true})
 check(not forged.get("ok",true) and forged.get("persisted") is bool and not forged.persisted and not closed._quest_loot_public_enabled(),"Client payload cannot alter the server-owned immutable capability")
 closed.free()
 if failures:quit(1);return

 var invalid:=EnabledBackend.new()
 var invalid_path:String="user://quest-loot-public-invalid.json"
 if not fresh_path(invalid_path) or not prepare_source(invalid,invalid_path):check(false,"Prepare original source-bound invalid-sequence fixture");invalid.free();quit(1);return
 # Connection IDs are signed peer instance IDs; only the exact -1 sentinel is invalid.
 var connection:=-741
 invalid.fee_attach(connection)
 var commands:Array=[{"type":"quest_loot_start","_quest_connection":connection},{"type":"quest_loot_start","seq":0,"_quest_connection":connection},{"type":"quest_loot_start","seq":true,"_quest_connection":connection},{"type":"quest_loot_start","seq":1.5,"_quest_connection":connection},{"type":"quest_loot_start","seq":1,"_quest_connection":connection,"route":"client"},{"type":"quest_loot_start","seq":1,"_quest_connection":connection,"_fee_binding":RefCounted.new()}]
 for index in range(commands.size()):
  if not same_rejected_state(invalid,commands[index],"invalid/forged start %d"%index):invalid.free();quit(1);return
 var busy_call:=RefCounted.new()
 invalid.quest_loot.public_start_call=busy_call
 if not same_rejected_state(invalid,start_command(2,connection),"reentrant public-start call lock"):invalid.free();quit(1);return
 check(is_same(invalid.quest_loot.public_start_call,busy_call),"Busy rejection leaves the captured current start call untouched")
 invalid.quest_loot.public_start_call=null
 invalid.fee_attach(-1)
 if not same_rejected_state(invalid,start_command(3,-1),"exact invalid connection sentinel"):invalid.free();quit(1);return
 invalid.fee_detach(-1)
 var old_binding=invalid._fee_bindings[connection]
 invalid.fee_detach(connection)
 if not same_rejected_state(invalid,start_command(1,connection),"detached old connection epoch"):invalid.free();quit(1);return
 check(old_binding is RefCounted and invalid._fee_bindings.get(connection)==null,"Detached transport epoch is no longer current")
 invalid.free()
 if failures:quit(1);return

 var blocked:=EnabledBackend.new()
 var blocked_path:String="user://quest-loot-public-tmp-blocked.json"
 if not fresh_path(blocked_path) or not prepare_source(blocked,blocked_path):check(false,"Prepare real E1 tmp-failure fixture");blocked.free();quit(1);return
 blocked.fee_attach(connection)
 var before_blocked:Dictionary=blocked.session.snapshot()
 var before_payload:String=blocked.last_saved_payload
 var before_serial:int=blocked.quest_save_serial
 var before_disk:Dictionary=read_disk(blocked_path)
 var before_backup:Dictionary=read_disk(blocked_path+".bak")
 var marker:String=ProjectSettings.globalize_path(blocked_path+".tmp")
 check(DirAccess.make_dir_absolute(marker)==OK,"Create only the owned E1 temporary-path blocker")
 if failures:blocked.free();quit(1);return
 var blocked_reply:Dictionary=blocked.handle(start_command(1,connection))
 check(not blocked_reply.get("ok",true) and blocked_reply.get("persisted") is bool and not blocked_reply.persisted and blocked_reply.get("type","")=="rejected","Actual E1 temporary writer failure is explicitly unpersisted")
 if failures:blocked.free();quit(1);return
 var after_blocked:Dictionary=read_disk(blocked_path)
 var after_backup:Dictionary=read_disk(blocked_path+".bak")
 check(before_disk.get("ok",false) and after_blocked.get("ok",false) and after_blocked.bytes==before_disk.bytes and before_backup.get("exists",false)==after_backup.get("exists",false) and (not before_backup.get("exists",false) or before_backup.get("ok",false) and after_backup.get("ok",false) and before_backup.bytes==after_backup.bytes) and blocked.session.snapshot()==before_blocked and blocked.last_saved_payload==before_payload and blocked.quest_save_serial==before_serial and blocked.quest_loot.anchor_ms<0 and blocked.quest_loot.ready_frame.is_empty() and not blocked.quest_auto.running,"Failed E1 preserves full profile/cache/serial/primary+backup and installs no timer or ready frame")
 if failures:blocked.free();quit(1);return
 check(DirAccess.remove_absolute(marker)==OK,"Remove only the owned E1 temporary blocker after assertions")
 if failures:blocked.free();quit(1);return
 blocked.free()

 var postwrite:=EnabledBackend.new()
 var postwrite_path:String="user://quest-loot-public-postwrite.json"
 if not fresh_path(postwrite_path) or not prepare_source(postwrite,postwrite_path):check(false,"Prepare real E1 post-write reentry fixture");postwrite.free();quit(1);return
 postwrite.fee_attach(connection);postwrite.replace_identity_after_open=true
 var persisted_reply:Dictionary=postwrite.handle(start_command(1,connection))
 check(postwrite.replaced_identity and not persisted_reply.get("ok",true) and persisted_reply.get("persisted") is bool and persisted_reply.persisted and persisted_reply.get("type","")=="rejected","Post-writer identity replacement reports durable E1 with persisted=true")
 if failures:postwrite.free();quit(1);return
 var durable:Dictionary=read_disk(postwrite_path)
 var durable_profile=JSON.parse_string(durable.bytes.get_string_from_utf8()) if durable.get("ok",false) else null
 check(durable.get("ok",false) and durable_profile is Dictionary and State.valid(durable_profile.get("quest_loot")) and durable_profile.quest_loot.entries.get(KEY,{}).get("open_span",false) and postwrite.session._profile.quest_loot.entries.get(KEY,{}).get("open_span",false) and postwrite.last_saved_payload==durable.bytes.get_string_from_utf8() and postwrite.quest_loot.anchor_ms<0 and postwrite.quest_loot.ready_frame.is_empty() and postwrite.quest_loot.initial_e2.is_empty(),"Original E1 writer remains durable after its post-write callback replaces the runner identity, without arming the old E2 tail")
 if failures:postwrite.free();quit(1);return
 check(postwrite.quest_auto.identity.checkpoint()==postwrite.replaced_identity_value,"Old start tail does not invalidate or rewrite the replacement identity")
 postwrite.free()
 if failures:quit(1);return

 var enabled:=EnabledBackend.new()
 var enabled_path:String="user://quest-loot-public-success.json"
 if not fresh_path(enabled_path) or not prepare_source(enabled,enabled_path):check(false,"Prepare successful real-handler source fixture");enabled.free();quit(1);return
 var binding=enabled.fee_attach(connection)
 var enable_caps:Dictionary=enabled._capabilities()
 var first:Dictionary=enabled.handle(start_command(1,connection))
 check(enable_caps.get("quest_loot_enabled")==true and enabled._quest_loot_public_enabled() and is_same(enabled._fee_bindings.get(connection),binding),"Production immutable getter and current attached transport authorize this callback fixture")
 check(first.get("ok",false) and first.get("persisted") is bool and first.persisted and first.get("type","")=="ack" and first.get("seq")==1,"Real public handler returns ACK only after durable E1 and E2 frame installation")
 if failures:enabled.free();quit(1);return
 check(first.get("run_identity",{}).keys().size()==3 and first.run_identity.has_all(["run_id","step_id","revision"]) and first.get("budget_identity",{}).keys().size()==3 and first.budget_identity.has_all(["budget_id","generation","revision"]),"ACK exposes only the frozen three-key run and budget identities")
 check(enabled.quest_loot.initial_e2.get("ready_token",null)!=null and not enabled.quest_loot.initial_e2.has("continuation_gate") and enabled.session._profile.quest_loot.entries[KEY].open_span,"First E2 is armed by the actual successful E1 open, without a fabricated continuation gate")
 if failures:enabled.free();quit(1);return
 var duplicate:Dictionary=enabled.handle(start_command(2,connection))
 check(not duplicate.get("ok",true) and duplicate.get("persisted") is bool and not duplicate.persisted and duplicate.get("seq")==2,"Duplicate start while the same runner is active is a pre-write rejection")
 if failures:enabled.free();quit(1);return
 var started_entry:Dictionary=enabled.session._profile.quest_loot.entries[KEY].duplicate(true)
 var stopped:Dictionary=enabled.handle({"type":"quest_auto_stop","client":"ignored-client"})
 check(stopped.get("ok",false) and not enabled.quest_auto.running and not enabled.session._profile.quest_loot.entries[KEY].open_span and enabled.session._profile.quest_loot.entries[KEY].settled_seq==started_entry.issued_seq,"Existing generic quest_auto_stop closes the started E1 span through its original writer")
 if failures:enabled.free();quit(1);return
 var stopped_disk:Dictionary=read_disk(enabled_path)
 var stopped_profile=JSON.parse_string(stopped_disk.bytes.get_string_from_utf8()) if stopped_disk.get("ok",false) else null
 check(stopped_profile is Dictionary and enabled.session._normalize_numbers(stopped_profile)==enabled.session._normalize_numbers(enabled.session._profile.duplicate(true)),"Generic Stop's durable close matches the complete persisted profile")
 if failures:enabled.free();quit(1);return
 enabled.free()

 var reopened:=EnabledBackend.new()
 var reopened_path:String="user://quest-loot-public-reopen.json"
 if not fresh_path(reopened_path) or not prepare_source(reopened,reopened_path,true):check(false,"Prepare a valid closed under-limit budget via pure State candidates and the real profile writer");reopened.free();quit(1);return
 reopened.fee_attach(connection)
 var prior:Dictionary=reopened.session._profile.quest_loot.entries[KEY].duplicate(true)
 var reopened_reply:Dictionary=reopened.handle(start_command(1,connection))
 check(reopened_reply.get("ok",false) and reopened_reply.get("persisted",false),"Explicit new public start reopens a closed under-limit budget")
 if failures:reopened.free();quit(1);return
 var next:Dictionary=reopened.session._profile.quest_loot.entries[KEY]
 check(next.budget_id==prior.budget_id and next.generation==prior.generation and next.limit_ms==prior.limit_ms and next.used_ms==prior.used_ms and next.saved_battles==prior.saved_battles and next.new_items==prior.new_items and next.issued_seq==prior.issued_seq+1 and next.revision==prior.revision+1 and next.open_span,"Reopen preserves the existing budget/history and advances only its serial span")
 var stop_again:Dictionary=reopened.handle({"type":"quest_auto_stop"})
 check(stop_again.get("ok",false) and not reopened.session._profile.quest_loot.entries[KEY].open_span,"Reopened budget closes through the same ordinary Stop transaction")
 if failures:reopened.free();quit(1);return
 reopened.fee_detach(connection)
 if not same_rejected_state(reopened,start_command(2,connection),"transport detached after a closed span"):reopened.free();quit(1);return
 reopened.free()
 if failures:quit(1);return

 var e2:=EnabledBackend.new()
 var e2_path:String="user://quest-loot-public-e2.json"
 if not fresh_path(e2_path) or not prepare_source(e2,e2_path):check(false,"Prepare first-E2 real process fixture");e2.free();quit(1);return
 e2.fee_attach(connection)
 var e2_ack:Dictionary=e2.handle(start_command(1,connection))
 check(e2_ack.get("ok",false) and e2_ack.get("persisted",false),"E2 barrier starts from real durable E1 ACK")
 if failures:e2.free();quit(1);return
 var generation_floor:int=int(e2.quest_loot.initial_e2.get("generation_floor",-1))
 e2.set_process(true);root.add_child(e2)
 var reached:bool=await Wait.until(self,func():return e2.field_calls>0,60.0)
 e2.set_process(false)
 check(reached and e2.field_calls==1 and e2.field_had_initial_frame and e2.field_process_depth==1 and e2.field_generation>generation_floor,"Original one-shot initial E2 reaches the real field handler only on a later normal Backend process generation")
 if failures:e2.free();quit(1);return
 print("QUEST AUTO LOOT PUBLIC START: %d failures; real Backend handler/E1 writer/first E2, production open capability, explicit closed negative fixture and callback injection; no live WS authentication claim"%failures)
 e2.free()
 quit(1 if failures else 0)

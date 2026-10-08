extends SceneTree
## Static candidate, UNRUN. Full independent profile and three-file oracles.
## Synthetic transport binding uses the real fee_attach; no account auth claim.
const Backend=preload("res://tests/support/fee_start_intent_backend.gd")
const Fault=preload("res://tests/support/fee_start_intent_fault_session.gd")
const Equipment=preload("res://server/original_equipment.gd")
const OLD="11111111111111111111111111111111"
const ORIGIN="33333333333333333333333333333333"
const ATTEMPT="44444444444444444444444444444444"
var checks:=0
var failures:=0
var fixtures:=0
var load_calls:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;push_error(label)
func yes(value:Variant)->bool:
 if not value is bool:return false
 return value
func raw(path:String)->Dictionary:
 if not FileAccess.file_exists(path):return {"exists":false,"bytes":PackedByteArray()}
 var f:=FileAccess.open(path,FileAccess.READ)
 if f==null:return {"exists":true,"bytes":PackedByteArray(),"unknown":true}
 var bytes:PackedByteArray=f.get_buffer(f.get_length());f.close()
 return {"exists":true,"bytes":bytes}
func journal(profile:Dictionary,run_id:String,closed:bool=false,unknown:bool=false)->Dictionary:
 # Independent literal; does not call Writer/Journal/Intent expected builders.
 return {"schema":1,"owner":{"profile_id":profile.profile_id,"character_id":profile.character_id},
  "current":{"run_id":run_id,"run_status":"closed" if closed else "active","purchase":{"state":"manual_only"}},
  "unresolved_attempt":{"origin_run_id":ORIGIN,"attempt_id":ATTEMPT,"source_id":"test-source","offer_id":"test-offer","item_id":799001,"amount":37,"balance_before":100} if unknown else {}}
func setup(tag:String,kind:String="absent",ticket:bool=true)->Dictionary:
 fixtures+=1
 print("START INTENT FIXTURE ",fixtures," ",tag," begin")
 var b=Backend.new();b.set_process(false)
 var s=Fault.new();b.session=s;s.host=weakref(b)
 s.battle_pets_hook=b._live_battle_pets;s.capture_entry_hook=b._capture_entry
 s._profile.player.level=35;s._profile.no_random_encounters=true
 for key in s._profile.inventory:s._profile.inventory[key]=0
 if ticket:Equipment.add(s._profile,2755)
 b.automation.position_changed(811,Vector2i(30,22),true)
 b.save_path="user://start-intent-%d-%03d-%s.json"%[Time.get_ticks_usec(),fixtures,tag]
 if kind!="absent":s._profile.quest_auto_fee_lifecycle=journal(s._profile,OLD,kind!="active",kind=="unknown")
 check(s._valid_profile(s.snapshot()) and b.save(),tag+": original full save")
 b.fee_attach(71);b.entry_identity=b.quest_auto.identity
 s.writer_calls=0;s.read_calls=0
 return {"b":b,"s":s,"path":b.save_path,"before":s._profile.duplicate(true),"serial":b.quest_save_serial,"cache":b.last_saved_payload,"tag":tag,"kind":kind}
func command(seq:int=91)->Dictionary:return {"type":"quest_auto_start","seq":seq,"quest_id":2,"client":"explicit-menu","_quest_connection":71}
func expected(c:Dictionary)->Dictionary:
 var value:Dictionary=c.before.duplicate(true)
 var run_id:String=c.b.candidates[0].quest_auto_fee_lifecycle.current.run_id
 value.quest_auto_fee_lifecycle=journal(c.before,run_id,false,c.kind=="unknown")
 return value
func disk(c:Dictionary,primary:Dictionary,backup:Dictionary={},backup_exists:bool=false)->void:
 check(raw(c.path)=={"exists":true,"bytes":JSON.stringify(primary).to_utf8_buffer()},c.tag+": complete primary")
 check(raw(c.path+".bak")=={"exists":backup_exists,"bytes":JSON.stringify(backup).to_utf8_buffer() if backup_exists else PackedByteArray()},c.tag+": complete backup")
 check(raw(c.path+".tmp")=={"exists":false,"bytes":PackedByteArray()},c.tag+": absent tmp")
func finish(c:Dictionary)->void:
 check(c.b._fee_start_journal_writer._start.is_empty() and not c.b._fee_start_intent.has_call(),c.tag+": private writer/call retired")
 print("START INTENT FIXTURE ",fixtures," ",c.tag," end")
 c.b.free() # Preserve success and failure disk fixtures.
func good(kind:String,mode:String="")->void:
 var c:Dictionary=setup("good-"+kind+mode,kind);c.b.mode=mode
 var r:Dictionary=c.b.handle(command())
 var value:Dictionary=expected(c)
 check(yes(r.get("ok")) and yes(r.get("persisted_intent")),c.tag+": actual installation ACK")
 check(c.s.writer_calls==2 and c.s.read_calls==15,c.tag+": exact B1 IO")
 check(c.s._profile==value and c.b.quest_save_serial==c.serial+1 and c.b.last_saved_payload==JSON.stringify(value),c.tag+": full profile/cache/serial, rewards gold UID unchanged")
 disk(c,value,value,true)
 check(c.b.quest_auto.running and c.b.quest_auto.identity.run_id==value.quest_auto_fee_lifecycle.current.run_id and not is_same(c.b.entry_identity,c.b.quest_auto.identity),c.tag+": staged same run installed")
 check(c.b._fee_start_intent.live_current(c.b) and not c.b._fee_start_intent._live.purchase_allowed,c.tag+": private intent only, never replacement ticket permission")
 var token:RefCounted=c.b._fee_start_intent._live.token
 var again:Dictionary=c.b.handle(command())
 check(yes(again.get("duplicate")) and yes(again.get("ok")) and is_same(c.b._fee_start_intent._live.token,token),c.tag+": dropped ACK replay same token")
 check(c.s.writer_calls==2 and c.b.installs==1,c.tag+": no duplicate write/install")
 if mode=="nested":check(not yes(c.b.nested_result.get("ok")),"nested real handle refused")
 if mode=="wrong_take":check(c.b.forged_take.is_empty(),"wrong consumer/call did not consume real writer permission")
 finish(c)
func write_fault(mode:String,wrapper:String="")->void:
 var c:Dictionary=setup(mode+wrapper);c.s.mode=mode;c.b.mode=wrapper
 if mode.begins_with("read_"):c.s.read_fault_at=7
 var r:Dictionary=c.b.handle(command())
 var value:Dictionary=expected(c)
 var two:bool=mode in ["w2_fail","w2_false"]
 check(c.s.writer_calls==(2 if two else 1) and c.s.read_calls==(15 if two else 9),c.tag+": precise IO phase reached")
 check(not yes(r.get("ok")) and not c.b.quest_auto.running and not c.b._fee_start_intent.live_current(c.b),c.tag+": diagnostic/raw result does not mint")
 var installed:bool=mode in ["w1_false","w2_fail","w2_false","bad_return"]
 if mode=="owner_after":
  var owner:Dictionary=c.before.duplicate(true);owner.profile_id="successor-profile"
  check(c.s._profile==owner and is_same(c.s._profile,c.s.successor),c.tag+": owner successor not erased")
 else:check(c.s._profile==(value if installed else c.before),c.tag+": exact memory, not fake rollback")
 check(c.b.quest_save_serial==(c.serial+10 if mode=="serial_after" else c.serial+(1 if installed else 0)),c.tag+": serial oracle")
 check(c.b.last_saved_payload==(JSON.stringify(value) if installed else c.cache),c.tag+": cache oracle")
 if mode=="w1_fail":disk(c,c.before)
 elif mode=="w2_false":disk(c,value,value,true)
 else:disk(c,value,c.before,true)
 if mode=="claim_after":check(is_same(c.b._fee_attempt_writer_call,c.s.injected_claim),"successor claim preserved")
 else:check(c.b._fee_attempt_writer_call==null,c.tag+": own claim retired")
 finish(c)
func preflight()->void:
 for kind:String in ["missing_ticket","active","bad_seq","missing_binding","client_cap","busy","guard","candidate_drift","public_ok_only","loot_envelope","loot_proof","loot_failure"]:
  var c:Dictionary=setup(kind,"active" if kind=="active" else "absent",kind!="missing_ticket")
  var cmd:Dictionary=command()
  match kind:
   "bad_seq":cmd.seq=true
   "missing_binding":c.b.fee_detach(71)
   "client_cap":cmd.start_cap={"ok":true}
   "busy":c.b.battle_open=true
   "guard":c.b.quest_visit_guard=func():return "fixture party guard"
   "candidate_drift","public_ok_only":c.b.mode=kind
   "loot_envelope":c.b._loot_resume_envelope={"fixture":true}
   "loot_proof":c.b.quest_loot.ready_frame={"fixture":true}
   "loot_failure":c.s._loot_failure_active={"fixture":true}
  var r:Dictionary=c.b.handle(cmd)
  check(not yes(r.get("ok")) and c.s.writer_calls==0 and c.s._profile==c.before,c.tag+": rejected no writer/full memory unchanged")
  check(not c.b.quest_auto.running and c.b._fee_start_intent._live.is_empty(),c.tag+": no forged install/permission")
  check(c.b.quest_save_serial==c.serial and c.b.last_saved_payload==c.cache,c.tag+": cache serial unchanged")
  disk(c,c.before);finish(c)
func successors()->void:
 for mode:String in ["binding_after","timer_after","position_after","catalog_after"]:
  var c:Dictionary=setup(mode);c.s.start_mode=mode
  var r:Dictionary=c.b.handle(command());var value:Dictionary=expected(c)
  check(not yes(r.get("ok")) and not c.b.quest_auto.running and c.b._fee_start_intent._live.is_empty(),mode+": W1 successor rejects Start")
  check(c.s.writer_calls==1 and c.s.read_calls==9 and c.s._profile==c.before,mode+": reached W1 physical but no memory install")
  check(c.b.quest_save_serial==c.serial and c.b.last_saved_payload==c.cache,mode+": no predecessor cache tail")
  disk(c,value,c.before,true);finish(c)
 for mode:String in ["publish_binding","observer_binding"]:
  var c:Dictionary=setup(mode);c.b.mode=mode
  var fired:Array=[false]
  var weak:WeakRef=weakref(c.b)
  if mode=="observer_binding":c.b.event.connect(func(_event):
   if fired[0]:return
   fired[0]=true;weak.get_ref().fee_attach(71))
  var old_binding:RefCounted=c.b._fee_bindings[71]
  var r:Dictionary=c.b.handle(command());var value:Dictionary=expected(c)
  check(not yes(r.get("ok")) and yes(r.get("persisted_intent")) and yes(r.get("stale")),mode+": ACK downgraded, intent fact survives")
  check(not is_same(old_binding,c.b._fee_bindings[71]) and not c.b._fee_start_intent.live_current(c.b),mode+": binding successor survives")
  if mode=="observer_binding":check(fired[0],"real queued event callback reached")
  check(c.s._profile==value and c.b.quest_save_serial==c.serial+1 and c.b.last_saved_payload==JSON.stringify(value),mode+": committed full profile unchanged")
  disk(c,value,value,true);finish(c)
func save_lifetime()->void:
 for mode:String in ["success","fail","false_after","load","detach","revision","source","owner","profile_ref","continue","load_fail","stop","path","serial","lifetime","binding","save_spoof","timer_lifetime"]:
  var c:Dictionary=setup("lifetime-"+mode)
  check(yes(c.b.handle(command()).get("ok")),mode+": real Start")
  var value:Dictionary=expected(c)
  var token:RefCounted=c.b._fee_start_intent._live.token
  var target:Dictionary=value.duplicate(true)
  match mode:
   "success","fail","false_after":
    target.player.gold+=1;c.s._profile.player.gold+=1;c.s.save_mode="" if mode=="success" else mode
    var saved:bool=c.b.save()
    check(saved==(mode=="success"),mode+": actual wrapper return")
    check(c.s._profile==target,mode+": full memory including deliberate manual gold change")
    disk(c,target if mode!="fail" else value,value,true)
    check(c.b.quest_save_serial==c.serial+(2 if mode=="success" else 1) and c.b.last_saved_payload==JSON.stringify(target if mode=="success" else value),mode+": save serial/cache exact")
   "load","load_fail":
    # Real load calls old persistent Stop first: independent closed target.
    target.quest_auto_fee_lifecycle.current.run_status="closed"
    load_calls+=1
    check(c.b.load_profile(c.path if mode=="load" else c.path+".missing")== (mode=="load"),"actual success/failure load keeps its return")
    check(c.s._profile==target,"load after real Stop retains full closed journal profile")
    disk(c,target,target,true)
   "detach":c.b.fee_detach(71);c.b.quest_auto.detach(c.b,71)
   "revision":c.b.quest_auto.identity.invalidate()
   "source":c.b.quest_auto.source_frame=RefCounted.new()
   "owner":c.s._profile.profile_id="successor-profile";target.profile_id="successor-profile"
   "profile_ref":c.s._profile=c.s._profile.duplicate(true)
   "stop":
    check(yes(c.b.handle({"type":"quest_auto_stop","seq":92,"client":"explicit-menu","_quest_connection":71}).get("ok")),"actual Stop")
    target.quest_auto_fee_lifecycle.current.run_status="closed"
    check(c.s._profile==target,"Stop complete closed profile")
    disk(c,target,target,true)
   "path":c.b.save_path+=".successor"
   "serial":c.b.quest_save_serial+=1
   "lifetime":c.b.automation.start_lifetime=RefCounted.new()
   "binding":c.b.fee_attach(71)
   "timer_lifetime":c.b.quest_loot.lifetime=RefCounted.new()
   "save_spoof":
    c.s._profile.player.gold+=1;target.player.gold+=1
    c.b.quest_save_serial+=1;c.b.last_saved_payload=JSON.stringify(c.s._profile)
   "continue":c.b.handle({"type":"quest_auto_continue","seq":92,"client":"explicit-menu","_quest_connection":71})
  check(c.s._profile==target,mode+": complete independent lifetime profile, all unrelated rewards and UIDs fixed")
  var serial_delta:int=2 if mode in ["success","load","load_fail","stop","serial","save_spoof"] else 1
  var saved_target:Dictionary=target if mode in ["success","load","load_fail","stop","save_spoof"] else value
  check(c.b.quest_save_serial==c.serial+serial_delta and c.b.last_saved_payload==JSON.stringify(saved_target),mode+": complete lifetime serial/cache")
  var valid:bool=c.b._fee_start_intent.live_current(c.b)
  if mode in ["success","continue"]:
   check(valid and is_same(c.b._fee_start_intent._live.token,token),mode+": only original token, no new mint")
  else:check(not valid,mode+": authority revoked")
  if mode not in ["success","fail","false_after","load","load_fail","stop"]:disk(c,value,value,true)
  var n:int=c.s.writer_calls
  var repeated:Dictionary=c.b.handle(command())
  check((yes(repeated.get("duplicate")) or mode in ["detach","binding"]) and c.s.writer_calls==n,mode+": old command never rewrites; detached binding denied")
  if mode not in ["success","continue"]:check(not yes(repeated.get("ok")) and c.b._fee_start_intent._live.is_empty(),mode+": old ACK cannot restore authority")
  finish(c)
func install_boundaries()->void:
 for mode:String in ["no_install","copied_prepared","wrong_identity","post_install_binding"]:
  var c:Dictionary=setup(mode)
  var runner=preload("res://tests/support/fee_start_intent_runner.gd").new()
  runner.mode=mode;c.b.quest_auto=runner
  var r:Dictionary=c.b.handle(command());var value:Dictionary=expected(c)
  check(runner.attempted and not yes(r.get("ok")) and yes(r.get("persisted_intent")),mode+": actual install boundary reached, no success ACK")
  check(runner.running==(mode=="post_install_binding") and not c.b._fee_start_intent.live_current(c.b),mode+": bad handle cannot install, post callback cannot authorize")
  check(c.s._profile==value and c.b.quest_save_serial==c.serial+1 and c.b.last_saved_payload==JSON.stringify(value),mode+": committed fact is preserved")
  disk(c,value,value,true);finish(c)
func strict_commands()->void:
 var c:Dictionary=setup("strict-fields")
 for field:String in ["seq","_quest_connection","client"]:
  for bad:Variant in [null,true,[],{},0.5]:
   var cmd:Dictionary=command();cmd[field]=bad
   check(not yes(c.b.handle(cmd).get("ok")),field+": strict bad type rejection")
  var missing:Dictionary=command();missing.erase(field)
  check(not yes(c.b.handle(missing).get("ok")),field+": missing rejection")
 check(c.s.writer_calls==0 and c.s._profile==c.before and c.b.quest_save_serial==c.serial,"all malformed commands zero B1 writes")
 disk(c,c.before);finish(c)
func competing_binding()->void:
 var c:Dictionary=setup("competing-binding")
 check(yes(c.b.handle(command()).get("ok")),"first real binding intent")
 var value:Dictionary=expected(c)
 var token:RefCounted=c.b._fee_start_intent._live.token
 c.b.fee_attach(72)
 var rival:Dictionary=command();rival._quest_connection=72;rival.client="rival"
 check(not yes(c.b.handle(rival).get("ok")),"second real binding cannot replace active run")
 check(c.b._fee_start_intent.live_current(c.b) and is_same(c.b._fee_start_intent._live.token,token),"failed rival leaves live predecessor permission intact")
 check(yes(c.b.handle(command()).get("duplicate")) and c.b.candidates.size()==1,"rival cannot erase first binding seq high-water")
 check(c.s._profile==value and c.b.quest_save_serial==c.serial+1,"rival leaves full profile/serial")
 disk(c,value,value,true);finish(c)
func direct_forgery()->void:
 var c:Dictionary=setup("direct-forgery")
 var fake=preload("res://server/quest_auto_state.gd").new();fake.begin()
 c.b.quest_auto.install_fee_start(c.b,{"ok":true,"quest_id":2,"source":true,"client":"fake","connection":71},fake)
 check(not c.b.quest_auto.running and c.s._profile==c.before and c.s.writer_calls==0,"public prepared diagnostic and staged identity cannot authorize install")
 check(not yes(c.b.quest_auto.start(c.b,command()).get("ok")) and not yes(c.b.quest_auto.begin_source_run(c.b,"fake",71).get("ok")),"gate true internal old install bypass refused")
 check(c.b._fee_start_intent.take_delivery({"ok":true,"persisted_intent":true}).is_empty(),"fake ACK does not obtain private delivery record")
 disk(c,c.before);finish(c)
func gatefalse_original()->void:
 var c:Dictionary=setup("gatefalse-original")
 c.b.enabled=false
 var r:Dictionary=c.b.handle(command())
 check(yes(r.get("ok")) and c.b.quest_auto.running,"gatefalse real original job2 Start")
 check(c.s._profile==c.before and c.s.writer_calls==0 and c.b.candidates.is_empty() and c.b.quest_save_serial==c.serial,"gatefalse no B1, original full profile/serial")
 check(c.b._fee_start_intent._live.is_empty() and not r.has("persisted_intent"),"gatefalse original ACK no fee permission")
 disk(c,c.before);finish(c)
func post_writer()->void:
 for mode:String in ["after_persist_binding","after_persist_profile_ref"]:
  var c:Dictionary=setup(mode);c.b.mode=mode
  var r:Dictionary=c.b.handle(command());var value:Dictionary=expected(c)
  check(yes(c.b.inner_result.get("ok")) and not yes(r.get("ok")) and not c.b.quest_auto.running,"real pair succeeded but post-writer successor denies install")
  check(c.s.writer_calls==2 and c.s.read_calls==15 and c.s._profile==value and c.b.quest_save_serial==c.serial+1,"actual W1/W2 disk/memory facts survive successor")
  check(c.b._fee_start_intent._live.is_empty(),"no old cap after writer callback")
  disk(c,value,value,true);finish(c)
func default_closed()->void:
 var b=preload("res://server/backend.gd").new();b.set_process(false)
 check(not b._fee_start_intent_enabled(),"production constant false")
 check(b._fee_start_intent.start(b,command()).get("ok")==false and b._fee_start_intent._live.is_empty(),"direct private module obeys closed gate")
 b.free()
func run()->void:
 for kind:String in ["absent","closed","unknown"]:good(kind)
 for mode:String in ["wrapper_false","wrong_take","nested"]:good("absent",mode)
 for mode:String in ["w1_fail","w2_fail","w1_false","w2_false","read_unknown","read_bad_ok","read_bad_exists","read_bad_bytes","bad_return","bad_row","owner_after","serial_after","path_after","identity_after","claim_after"]:write_fault(mode)
 write_fault("w2_false","wrapper_true")
 preflight();successors();save_lifetime();install_boundaries();strict_commands();competing_binding();direct_forgery();gatefalse_original();post_writer();default_closed()
 print("START INTENT SUMMARY: ",checks," checks, ",failures," failures, ",fixtures," fixtures, ",load_calls," real loads")
 quit(1 if failures else 0)

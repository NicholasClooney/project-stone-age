extends SceneTree
## STATIC C candidate, UNRUN. No test cleans product private authority fields.
const Backend=preload("res://tests/support/fee_lobby_ticket_backend.gd")
const Fault=preload("res://tests/support/fee_lobby_ticket_fault_session.gd")
const Fact=preload("res://server/fee_lobby_ticket_fact.gd")
var checks:int=0
var failures:int=0
var fixtures:int=0
var load_calls:int=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;push_error(label)
func raw(path:String)->Dictionary:
 if not FileAccess.file_exists(path):return {"exists":false,"bytes":PackedByteArray()}
 var file=FileAccess.open(path,FileAccess.READ)
 if file==null:return {"exists":true,"unknown":true}
 var bytes:PackedByteArray=file.get_buffer(file.get_length());file.close()
 return {"exists":true,"bytes":bytes}
func rows(c:Dictionary)->Array:return [raw(c.path),raw(c.path+".bak"),raw(c.path+".tmp")]
func disk(c:Dictionary,p:Dictionary,z:Dictionary={},exists:bool=true)->void:
 check(rows(c)==[{"exists":true,"bytes":JSON.stringify(p).to_utf8_buffer()},{"exists":exists,"bytes":JSON.stringify(z).to_utf8_buffer() if exists else PackedByteArray()},{"exists":false,"bytes":PackedByteArray()}],c.tag+": complete main/bak/tmp")
func command(seq:int=41)->Dictionary:return {"type":"quest_auto_start","quest_id":2,"client":"fixture-explicit","seq":seq,"_quest_connection":71}
func setup(tag:String,level:int=35,ticket:bool=false)->Dictionary:
 fixtures+=1;print("LOBBY FIXTURE ",fixtures," ",tag," begin")
 var b=Backend.new();b.set_process(false)
 var luck=RandomNumberGenerator.new();luck.seed=7319
 var s=Fault.new(func():return 1791504000,luck);s.host=weakref(b);b.session=s
 s.battle_pets_hook=b._live_battle_pets;s.capture_entry_hook=b._capture_entry
 s._profile.player.level=level;s._profile.player.gold=1000000;s._profile.no_random_encounters=true
 for key in s._profile.inventory:s._profile.inventory[key]=0
 if ticket:
  var id:int=2757 if level>=70 else (2756 if level>=50 else 2755)
  preload("res://server/original_equipment.gd").add(s._profile,id)
 b.automation.position_changed(851 if level>=70 else 811,Vector2i(29 if level>=70 else (28 if level>=50 else 30),22),true)
 b.save_path="user://lobby-shutdown.json" if tag=="shutdown" else "user://lobby-%d-%03d-%s.json"%[Time.get_ticks_usec(),fixtures,tag]
 s.set_location(b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y)
 check(s._valid_profile(s.snapshot()) and b.save(),tag+": original setup saved")
 load_calls+=1
 check(b.load_profile(b.save_path),tag+": real fixture normalization load")
 b.automation.position_changed(851 if level>=70 else 811,Vector2i(29 if level>=70 else (28 if level>=50 else 30),22),true)
 check(b.save(),tag+": canonical fixture resave")
 b.fee_attach(71)
 return {"b":b,"s":s,"tag":tag,"path":b.save_path,"before":s._profile.duplicate(true),"serial":b.quest_save_serial,"ticket":ticket,"level":level}
func start(c:Dictionary)->Dictionary:
 var result:Dictionary=c.b.handle(command())
 check(result.get("ok")==true and result.get("persisted_intent")==true,c.tag+": actual Start ACK intent")
 if not result.get("ok",false):return {}
 var value:Dictionary=c.before.duplicate(true)
 value["quest_auto_fee_lifecycle"]={"schema":1,"owner":{"profile_id":c.before.profile_id,"character_id":c.before.character_id},"current":{"run_id":result.run_id,"run_status":"active","purchase":{"state":"manual_only" if c.ticket else "none"}},"unresolved_attempt":{}}
 check(c.s._profile==value and c.b.quest_save_serial==c.serial+1,c.tag+": independent whole Start profile and serial")
 disk(c,value,value)
 c.s.writes=0;c.s.reads=0;c.s.calls=[]
 c.started=value;c.start_serial=c.b.quest_save_serial
 return value
func attempt(c:Dictionary)->Dictionary:
 var value:Dictionary=c.started.duplicate(true)
 var observed:Dictionary=c.s.calls[0].quest_auto_fee_lifecycle.current.purchase
 var high:bool=c.level>=70
 var id:int=2757 if high else (2756 if c.level>=50 else 2755)
 value.quest_auto_fee_lifecycle.current.purchase={"state":"attempting","attempt_id":observed.attempt_id,"source_id":"quiz/uketuke2" if high else "quiz/uketuke","offer_id":"quiz/uketuke2@4020:18:13:0" if high else ("quiz/uketuke@2020:18:13:1" if c.level>=50 else "quiz/uketuke@2020:18:13:2"),"item_id":id,"amount":c.level*(20 if c.level<50 else 40),"balance_before":c.started.player.gold}
 check(observed.attempt_id is String and observed.attempt_id.length()==32 and observed.attempt_id!=value.quest_auto_fee_lifecycle.current.run_id,c.tag+": server attempt independent")
 return value
func paid(c:Dictionary,a:Dictionary)->Dictionary:
 var value:Dictionary=a.duplicate(true)
 var p:Dictionary=value.quest_auto_fee_lifecycle.current.purchase
 var uid:int=c.started.next_original_uid
 value.player.gold-=p.amount
 value.original_items.append(p.item_id)
 value.original_instances.append({"uid":uid,"item_id":p.item_id,"durability":0})
 value.next_original_uid+=1
 p["state"]="ticket_committed";p["balance_after"]=value.player.gold;p["ticket_uid"]=uid
 return value
func finish(c:Dictionary)->void:
 check(c.b._fee_lobby_ticket._op.is_empty() and c.b._fee_attempt_writer_call==null,c.tag+": operation claim released")
 print("LOBBY FIXTURE ",fixtures," ",c.tag," end")
 c.b.free() # Disks are intentionally preserved on PASS and FAIL.
func good(level:int,wrapper:String="")->void:
 var c:Dictionary=setup("good-%d-%s"%[level,wrapper],level)
 if start(c).is_empty():finish(c);return
 check(c.b._fee_start_intent.take_purchase(c.b,RefCounted.new()).is_empty(),c.tag+": wrong consumer does not consume true Start capability")
 if wrapper=="save_noop":
  check(c.b.save() and c.b._fee_start_intent.live_current(c.b),c.tag+": controlled real save retains capability")
  c.start_serial+=1
 c.b.wrapper=wrapper;c.b.purchase_turn()
 check(c.s.writes==3,c.tag+": attempt twice then ticket once")
 if c.s.calls.size()!=3:finish(c);return
 var a:Dictionary=attempt(c);var p:Dictionary=paid(c,a)
 check(c.s.calls==[a,a,p],c.tag+": all writer full candidates independently expected")
 disk(c,p,a)
 var live:Dictionary=p.duplicate(true)
 if wrapper=="owner_after_mark":live.character_id="100005"
 check(c.s._profile==live and c.b.quest_save_serial==c.start_serial+2 and c.b.last_saved_payload==JSON.stringify(p),c.tag+": full live gold/items/UID/cache/serial")
 check(c.b.facts.size()==1,c.tag+": one profile fact even wrapper false/owner successor")
 if c.b.facts.size()==1:
  var tx:Variant=c.b.facts[0].transaction_id
  var expected:Dictionary={"schema":1,"scope":"profile","origin":"explicit_start","owner":{"profile_id":p.profile_id,"character_id":p.character_id},"transaction_id":tx,"fee_kind":"golden44_lobby_ticket","phase":"ticket_purchase","run_id":p.quest_auto_fee_lifecycle.current.run_id,"step_id":"golden44:lobby_purchase","attempt_id":a.quest_auto_fee_lifecycle.current.purchase.attempt_id,"source_id":a.quest_auto_fee_lifecycle.current.purchase.source_id,"offer_id":a.quest_auto_fee_lifecycle.current.purchase.offer_id,"currency":"stone","amount":a.quest_auto_fee_lifecycle.current.purchase.amount,"balance_before":a.player.gold,"balance_after":p.player.gold,"item_id":p.original_items[-1],"ticket_uid":c.started.next_original_uid,"status":"committed","durability":"disk","save_serial":c.start_serial+2,"candidate_sha256":JSON.stringify(p).sha256_text()}
  check(c.b.facts[0]==expected and Fact.valid(expected),c.tag+": independent complete tagged fact")
  for key in expected:
   for bad in [null,false,[],{},1.0]:
    var invalid:Dictionary=expected.duplicate(true);invalid[key]=bad
    check(not Fact.valid(invalid),c.tag+": strict malformed "+key)
  for field in ["profile_id","character_id"]:
   for bad_owner in [null,false,1,[],{}]:
    var bad_fact:Dictionary=expected.duplicate(true);bad_fact.owner[field]=bad_owner
    check(not Fact.valid(bad_fact),c.tag+": strict nested owner "+field)
  for extra in ["consumed_ticket_uid","destination","entry_committed"]:
   var invalid:Dictionary=expected.duplicate(true);invalid[extra]=1
   check(not Fact.valid(invalid),c.tag+": purchase never entry shape")
 var old_rows:Array=rows(c)
 var duplicate:Dictionary=c.b.handle(command())
 check(duplicate.get("duplicate")==true and c.s.writes==3 and rows(c)==old_rows and c.b.facts.size()==1,c.tag+": dropped ACK replay cannot buy again")
 check(c.b._fee_start_intent.take_purchase(c.b,c.b._fee_lobby_ticket).is_empty(),c.tag+": genuine capability spent")
 finish(c)
func failed(at:int,mode:String)->void:
 var c:Dictionary=setup("fault-%d-%s"%[at,mode])
 if start(c).is_empty():finish(c);return
 c.s.at=at;c.s.mode=mode;c.b.purchase_turn()
 check(c.s.writes==at and c.b.facts.is_empty(),c.tag+": no later write or committed event")
 if c.s.calls.is_empty():finish(c);return
 var a:Dictionary=attempt(c);var p:Dictionary=paid(c,a)
 var expected_disk:Dictionary=c.started if at==1 and mode=="false_before" else (p if at==3 and mode!="false_before" else a)
 var backup:Dictionary=c.started if at==1 or (at==2 and mode in ["false_before","raw_forged"]) else a
 disk(c,expected_disk,backup)
 var live:Dictionary=c.started if at==1 and mode in ["false_before","unknown"] else (p if at==3 and mode=="false_after" else a)
 check(c.s._profile==live,c.tag+": exact memory independent of disk landing")
 check(not c.b.quest_auto.running and c.b._fee_start_intent.take_purchase(c.b,c.b._fee_lobby_ticket).is_empty(),c.tag+": no fee execution or replacement entitlement")
 if mode=="unknown":
  check(c.b._fee_lobby_ticket.held(c.b),c.tag+": unknown holds after run retired")
  var frozen:Array=rows(c);var serial:int=c.b.quest_save_serial;var snapshots:int=c.s.snapshot_calls
  c.s._profile.player.gold+=3
  var manual:Dictionary=c.s._profile.duplicate(true)
  check(not c.b.save(),c.tag+": manual save explicit exception")
  check(c.s.snapshot_calls==snapshots and c.s._profile==manual and rows(c)==frozen and c.b.quest_save_serial==serial,c.tag+": refuse before snapshot and disk, preserve full live input")
  check(c.b._fee_lobby_ticket.rejected_saves==1,c.tag+": volatile rejection count only")
  c.b.quest_auto.identity.begin()
  check(not c.b.save() and rows(c)==frozen,c.tag+": changed run cannot wash same-memory old path")
  c.b.fee_detach(71);c.b.fee_attach(71)
  check(c.b._fee_lobby_ticket.held(c.b),c.tag+": binding/warm does not release hold")
 finish(c)
func existing_and_gate()->void:
 for enabled in [true,false]:
  var c:Dictionary=setup("existing-"+str(enabled),35,true);c.b.purchase_enabled=enabled
  if start(c).is_empty():finish(c);continue
  check(not c.b._fee_lobby_ticket.advance(c.b) and c.s.writes==0 and c.b.facts.is_empty(),c.tag+": existing ticket manual_only zero payment")
  disk(c,c.started,c.started);finish(c)
 var no:Dictionary=setup("gatefalse-missing");no.b.purchase_enabled=false
 var frozen:Array=rows(no);var result:Dictionary=no.b.handle(command())
 check(not result.get("ok",false) and no.s._profile==no.before and rows(no)==frozen and no.b.quest_save_serial==no.serial,"gatefalse no-ticket old rejection no B1")
 finish(no)
func load_case(success:bool)->void:
 var c:Dictionary=setup("load-"+str(success))
 if start(c).is_empty():finish(c);return
 c.s.at=3;c.s.mode="unknown";c.b.purchase_turn()
 var frozen:Array=rows(c);var before:Dictionary=c.s._profile.duplicate(true)
 c.s.mode="";c.s.at=0
 var actual_path:String=c.path if success else c.path+".missing"
 load_calls+=1
 var loaded:bool=c.b.load_profile(actual_path)
 check(loaded==success,c.tag+": true loader return")
 check(rows(c)==frozen,c.tag+": loader did not repair/overwrite fee-only disk")
 check(c.b._fee_start_intent.take_purchase(c.b,c.b._fee_lobby_ticket).is_empty(),c.tag+": real load success/failure never mints another ticket")
 if success:
  var actual:Dictionary=paid(c,attempt(c))
  check(c.s._profile==actual and not c.b._fee_lobby_ticket.held(c.b),c.tag+": real primary receipt releases hold and independently loads paid profile")
 else:check(c.s._profile==before and c.b._fee_lobby_ticket.held(c.b),c.tag+": failed load preserves full profile and protection")
 finish(c)
func successor(mode:String)->void:
 var c:Dictionary=setup("successor-"+mode)
 if start(c).is_empty():finish(c);return
 c.s.at=1;c.s.mode=mode
 var serial:int=c.b.quest_save_serial
 c.b.purchase_turn()
 check(c.s.writes==1 and c.b.facts.is_empty(),c.tag+": first write only, no public fact")
 if c.s.calls.is_empty():finish(c);return
 var a:Dictionary=attempt(c)
 disk(c,a,c.started)
 var expected:Dictionary=c.started.duplicate(true)
 if mode=="owner":expected.character_id="100005"
 check(c.s._profile==expected,c.tag+": whole successor not replaced by old writer")
 check(c.b.quest_save_serial==serial+(9 if mode=="serial" else 0),c.tag+": successor serial intact")
 if mode=="session":check(c.b.session._profile==expected and not is_same(c.b.session,c.s),c.tag+": independent new Session retained")
 if mode in ["owner","path","session"]:
  check(not c.b._fee_lobby_ticket.held(c.b),c.tag+": different owner/path not held")
 else:check(c.b._fee_lobby_ticket.held(c.b),c.tag+": same stale memory/path remains held")
 finish(c)
func untrusted()->void:
 var c:Dictionary=setup("forged-diagnostic")
 check(c.b._fee_lobby_ticket.persist(c.b,RefCounted.new())=={"ok":false},"wrong private handle rejected")
 if start(c).is_empty():finish(c);return
 var old:Array=rows(c);c.b.wrapper="forged_ok";c.b.purchase_turn()
 check(c.s.writes==0 and c.s._profile==c.started and rows(c)==old and c.b.facts.is_empty(),"forged public success cannot fence/pay/mint")
 check(c.b._fee_start_intent.take_purchase(c.b,c.b._fee_lobby_ticket).is_empty(),"forged return does not refund fresh opportunity")
 finish(c)
func preflight_rejections()->void:
 for mode in ["money","bag","level","map","ended","party","source","unknown_journal"]:
  var c:Dictionary=setup("reject-"+mode)
  match mode:
   "money":c.s._profile.player.gold=0
   "bag":
    for index in range(15):preload("res://server/original_equipment.gd").add(c.s._profile,2752)
   "level":c.s._profile.player.level=29
   "map":c.b.automation.position_changed(1000,Vector2i(80,90),true)
   "ended":c.s._profile.original_events.ended[1]=1<<12
   "party":c.b.quest_visit_guard=func():return "team"
   "source":c.b.quest_catalog.enabled_events.erase(44)
   "unknown_journal":
    c.s._profile.quest_auto_fee_lifecycle={"schema":1,"owner":{"profile_id":c.s._profile.profile_id,"character_id":c.s._profile.character_id},"current":{"run_id":"11111111111111111111111111111111","run_status":"closed","purchase":{"state":"manual_only"}},"unresolved_attempt":{"origin_run_id":"22222222222222222222222222222222","attempt_id":"33333333333333333333333333333333","source_id":"old","offer_id":"old","item_id":2755,"amount":700,"balance_before":1000}}
  check(c.b.save(),c.tag+": preparation saved before counters")
  var before:Dictionary=c.s._profile.duplicate(true);var old:Array=rows(c);var count:int=c.s.writes;var serial:int=c.b.quest_save_serial
  var result:Dictionary=c.b.handle(command())
  check(not result.get("ok",false) and c.s._profile==before and rows(c)==old and c.s.writes==count and c.b.quest_save_serial==serial,c.tag+": entire rejected Start unchanged no B1")
  finish(c)
func gatefalse_save()->void:
 var c:Dictionary=setup("gatefalse-save");c.b.purchase_enabled=false
 var p:Dictionary=c.s._profile.duplicate(true);var n:int=c.b.quest_save_serial
 check(c.b.save() and c.b.quest_save_serial==n+1 and c.s._profile==p,"gatefalse same-payload serial remains parent behavior")
 c.s._profile.player.gold+=2
 var next:Dictionary=p.duplicate(true);next.player.gold+=2
 check(c.b.save() and c.b.quest_save_serial==n+2 and c.s._profile==next,"gatefalse changed full profile/serial")
 disk(c,next,p)
 check(c.b._fee_lobby_ticket.rejected_saves==0 and c.b._fee_lobby_ticket._hold.is_empty(),"gatefalse never creates or counts hold")
 finish(c)
func failed_save_cap()->void:
 var c:Dictionary=setup("failed-controlled-save")
 if start(c).is_empty():finish(c);return
 var old:Array=rows(c);var serial:int=c.b.quest_save_serial
 c.s._profile.player.gold+=1;c.s.save_mode="false_before"
 var expected:Dictionary=c.started.duplicate(true);expected.player.gold+=1
 check(not c.b.save() and c.b.quest_save_serial==serial and rows(c)==old and c.s._profile==expected,"failed save independent whole live/disk/serial")
 check(not c.b._fee_lobby_ticket.advance(c.b) and c.b.facts.is_empty() and c.s.writes==0,"failed controlled save revokes cap, no fee IO")
 finish(c)
func candidate_drift()->void:
 var c:Dictionary=setup("unrelated-candidate")
 if start(c).is_empty():finish(c);return
 var old:Array=rows(c);var n:int=c.b.quest_save_serial
 c.s.at=1;c.s.mode="candidate_unrelated";c.b.purchase_turn()
 check(c.s.writes==1 and c.s._profile==c.started and rows(c)==old and c.b.quest_save_serial==n and c.b.facts.is_empty(),"unrelated candidate rejected before physical IO, full profile/three disks unchanged")
 check(not c.b._fee_lobby_ticket.held(c.b),"no actual IO means no unknown hold")
 finish(c)
func shutdown_hold()->void:
 var c:Dictionary=setup("shutdown")
 if start(c).is_empty():finish(c);return
 c.s.at=3;c.s.mode="unknown";c.b.purchase_turn()
 var frozen:Array=rows(c);var before:Dictionary=c.s._profile.duplicate(true);var serial:int=c.b.quest_save_serial
 c.b.shut_down()
 check(rows(c)==frozen and c.s._profile==before and c.b.quest_save_serial==serial,"shutdown does not wash unresolved ticket profile")
 check(c.b._fee_lobby_ticket.held(c.b) and c.b._fee_lobby_ticket.rejected_saves==1,"shutdown keeps hold and records exactly its rejected generic save")
 finish(c)
func run()->void:
 for level in [30,49,50,69,70]:good(level)
 good(35,"false_after_mark");good(35,"owner_after_mark");good(35,"save_noop");good(35,"stop_after_mark")
 failed(2,"raw_forged")
 for at in [1,2,3]:
  for mode in ["false_before","false_after","unknown"]:failed(at,mode)
 for mode in ["binding","serial","path","owner","profile_ref","run","session"]:successor(mode)
 untrusted();preflight_rejections();gatefalse_save();failed_save_cap();candidate_drift();shutdown_hold()
 existing_and_gate()
 load_case(true);load_case(false)
 print("LOBBY PURCHASE SUMMARY checks=",checks," failures=",failures," fixtures=",fixtures," real_loads=",load_calls)
 quit(1 if failures else 0)

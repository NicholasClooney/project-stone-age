extends SceneTree
## UNRUN. Public300 door is a disclosed fixture; upstream route remains unproven.
## Real portal establishes arrival; only then real prepare/Start/A steps run.
const B=preload("res://tests/support/brothers_request_fault_backend.gd")
const Runner=preload("res://tests/support/brothers_request_observed_runner.gd")
const Fixture=preload("res://tests/support/brothers_request_fixture.gd")
const Diff=preload("res://tests/support/brothers_request_compare.gd")
const Plan=preload("res://server/quest_auto_brothers_plan.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Policy=preload("res://scripts/quest_auto_policy.gd")
const Registry=preload("res://server/quest_auto_registry.gd")
const Wait=preload("res://tests/support/wait.gd")
const PEER:int=182828
const CLIENT:String="brothers6d"
const WAIT_SECONDS:float=60.0
const MAX_POINTS:int=500
const SOURCE_SHA:String="c7717f4e5ce1144854b179615b8edd2cddf16fd6e2bc19d20ededfbf945bbeae"
var b
var checks:int=0
var failures:int=0
var walks:int=0
var ticks:int=0
var transaction_before:Dictionary={}
var transaction_disks:Array=[]
var transaction_serial:int=0
var transaction_seen:bool=false
var committed:bool=false
var deadline:int=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->bool:
 checks+=1
 if not value:failures+=1;push_error(label)
 return value
func equal(actual:Variant,expected:Variant,label:String)->bool:
 var difference:Dictionary=Diff.first(actual,expected,label)
 if not difference.is_empty():Diff.print_first(difference)
 return check(difference.is_empty(),label)
func admission_state()->Dictionary:
 var state:Dictionary=b.whole_state()
 state["scope"]=b.quest_auto._brothers_scope.duplicate(true)
 state["call"]=b._brothers_request_call.duplicate(true)
 state["step"]=b.quest_auto.step.duplicate(true)
 return state
func prepare_oracle()->bool:
 var table:Dictionary=Plan.source_table()
 if not check(not table.is_empty() and table.sources["npc/giiru/event/ev28_0"].sha256==SOURCE_SHA,"complete original source identity"):return false
 # Independent literal, never Registry/selector result as expected.
 # branch_data JSON on both sides; proposal cell is an int literal, no coercion.
 var first:Dictionary={"id":"brothers:request:28","npc_id":"giiru/event/ev28_0","map_id":31701,"cell":[29,44],"current":true,"done":false,"actionable":true,"auto_choices":["yes","ok"],"source":{"npc_id":"giiru/event/ev28_0","type":"REQUEST","condition":"LV>30","actions":{},"branch_index":0,"branch_data":table.npc.branches[0].duplicate(true),"source_line":11,"source_sha":SOURCE_SHA,"audit_policy":"brothers_request28_v1"}}
 var expected:Dictionary={"ok":true,"source":false,"quest_id":18,"client":CLIENT,"connection":PEER,"clean":false,"first":first}
 var before:Dictionary=admission_state()
 var session_ref=b.session
 var profile_ref:Dictionary=b.session._profile
 var runner_ref=b.quest_auto
 var scope_ref:Dictionary=b.quest_auto._brothers_scope
 var call_ref:Dictionary=b._brothers_request_call
 var binding_ref=b._fee_bindings.get(PEER)
 var actual:Dictionary=b.quest_auto.prepare_start(b,{"type":"quest_auto_start","quest_id":18,"client":CLIENT,"_quest_connection":PEER})
 if not equal(actual,expected,"prepare"):return false
 if not equal(admission_state(),before,"prepare entire unchanged state"):return false
 return check(is_same(session_ref,b.session) and is_same(profile_ref,b.session._profile) and is_same(runner_ref,b.quest_auto) and is_same(scope_ref,b.quest_auto._brothers_scope) and is_same(call_ref,b._brothers_request_call) and is_same(binding_ref,b._fee_bindings.get(PEER)),"prepare identity refs unchanged")
func drive()->bool:
 if failures:return true
 if not b.quest_auto.running:return true
 if Time.get_ticks_msec()>=deadline:return not check(false,"one global Wait60 exhausted before next synchronous step")
 ticks+=1
 if ticks>MAX_POINTS+10:return not check(false,"bounded 510 runner ticks")
 var origin:Vector2i=b.automation.position_cell
 var phase:String=b.quest_auto.phase
 var pending:Dictionary=b.original_quests.pending.duplicate(true)
 var before:Dictionary=b.session.snapshot()
 var disks:Array=b.disk_rows()
 var serial:int=b.quest_save_serial
 var epoch:int=b.quest_arrival._epoch
 if not check(b.automation.position_map==31701 and b.quest_arrival.has_arrival(b,31701,origin),"actual current arrival before every runner tick"):return true
 b.quest_auto.tick(b,0.21)
 if not check(b.automation.position_map==31701 and b.quest_arrival._epoch==epoch and b.quest_arrival.has_arrival(b,31701,b.automation.position_cell),"same genuine arrival retained after tick; no exit or remint"):return true
 var destination:Vector2i=b.automation.position_cell
 if destination!=origin:
  walks+=1
  var point:Dictionary=b.quest_auto.navigation.last_point
  if not check(walks<=MAX_POINTS and abs(destination.x-origin.x)+abs(destination.y-origin.y)==1 and point.get("map_id")==31701 and not point.has("portal") and not point.has("gate"),"real A one-cell step never crosses portal or fee gate"):return true
 if phase=="travel" and pending.is_empty() and b.quest_auto.phase=="strict_dialogue":
  if not check(not transaction_seen and b.original_quests.pending.get("phase")=="REQUEST" and b.original_quests.pending.branch==b.quest_auto.step.source.branch_data,"only exact original REQUEST opened"):return true
  transaction_seen=true;transaction_before=before;transaction_disks=disks;transaction_serial=serial
 if transaction_seen and not committed and b.original_quests.pending.is_empty() and b.quest_auto.phase=="travel" and b.quest_save_serial>transaction_serial:
  if not record_transaction():return true
 return not b.quest_auto.running
func record_transaction()->bool:
 var expected:Dictionary=transaction_before.duplicate(true)
 expected.original_events.now[0]=int(expected.original_events.now[0]) | (1 << 28)
 if not equal(b.session.snapshot(),expected,"full profile only NOW28; money/items/pets/UIDs unchanged"):return false
 var disks:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},transaction_disks[0],{"exists":false,"bytes":PackedByteArray()}]
 if not equal(b.disk_rows(),disks,"independent three exact disks"):return false
 if not check(b.last_saved_payload==JSON.stringify(expected) and b.quest_save_serial==transaction_serial+1,"one genuine writer cache/serial"):return false
 var loaded=Session.new()
 if not check(loaded.load_game(b.save_path) and JSON.stringify(loaded.snapshot())==JSON.stringify(expected),"one actual JSON load of complete independently expected profile"):return false
 committed=true
 return true
func run()->void:
 b=B.new();b.set_process(false)
 b.quest_auto=Runner.new()
 b.fee_attach(PEER)
 b.save_path="user://brothers6d-route.json"
 b.session._profile.player.level=31
 b.session._profile.player.gold=1234
 b.session._profile.no_random_encounters=true
 if not check(b.session.gm_grant_pet(74),"fixture real pet birth UID, not consumed"):finish();return
 if not check(Fixture.enter(b),"disclosed300 entrance setup then real portal establishes current arrival"):finish();return
 if not check(b.save(),"normal baseline save after genuine entrance"):finish();return
 if not check(not Policy.supports(18,28) and not Registry.supports(18),"public opening remains closed"):finish();return
 if not prepare_oracle():finish();return
 var before:Dictionary=admission_state()
 var reply:Dictionary=b.handle({"type":"quest_auto_start","quest_id":18,"client":CLIENT,"_quest_connection":PEER})
 if not check(reply.get("ok",false) and b.quest_auto.running and b.quest_auto.strict_walk and b.quest_auto.phase=="travel" and not b.quest_auto._brothers_scope.is_empty(),"real handle Start creates independent run"):finish();return
 if not equal(b.session._profile,before.profile,"Start full profile unchanged") or not equal(b.disk_rows(),before.disks,"Start disks unchanged"):finish();return
 if not check(b.last_saved_payload==before.cache and b.quest_save_serial==before.serial and b.quest_auto._doctor_scope.is_empty() and b.quest_auto._saton_scope.is_empty() and b.quest_auto._munde_scope.is_empty() and b._required_fee_runner_authority==null,"Start cache/serial and other authority unchanged"):finish();return
 deadline=Time.get_ticks_msec()+int(WAIT_SECONDS*1000)
 var reached:bool=await Wait.until(self,drive,WAIT_SECONDS)
 if not check(reached and failures==0 and committed and walks>0 and b.quest_auto.phase=="manual" and not b.quest_auto.running,"one real first-floor route and REQUEST, then manual boundary"):finish();return
 if not equal(Registry.brothers_request(b,18),{"status":"manual","stage":"request28_complete","reason":"五兄弟首委托已处理；后续任务请手动进行。"},"exact post-NOW28 manual boundary"):finish();return
 if not check(not Rules.flag(b.session._profile,"ended",28) and not Rules.flag(b.session._profile,"now",31),"no answers/crystal/job19/boss follow-up"):finish();return
 var final_state:Dictionary=b.whole_state()
 var denied:Dictionary=b.handle({"type":"quest_auto_start","quest_id":18,"client":CLIENT,"_quest_connection":PEER})
 if not check(not denied.get("ok",false),"repeat Start rejected"):finish();return
 if not equal(b.whole_state(),final_state,"repeat Start leaves full state and disks unchanged"):finish();return
 finish()
func finish()->void:
 if b!=null:b.free()
 print("BROTHERS 6D ROUTE: %d checks; %d failures; 1 backend; at most 1 load; 1 Wait60; %d walks; %d ticks"%[checks,failures,walks,ticks])
 quit(1 if failures else 0)

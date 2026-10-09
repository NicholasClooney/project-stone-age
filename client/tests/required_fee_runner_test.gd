extends "res://tests/support/required_fee_runner_harness.gd"
## UNRUN. Synchronous real D writer, no issuer/route production caller.
func good(kind:String,mode:String,owned:bool=false)->void:
 var c:Dictionary=setup("good-"+kind+"-"+mode+"-"+str(owned),kind,owned)
 if failures:finish(c);return
 if mode=="second":
  c.source="genout/ss_4000_99_85"
  c.s.set_location(4000,98,85);c.b.automation.position_changed(4000,Vector2i(98,85),true)
  check(c.b.save(),"second exact original vendor placement")
 c.b._depth+=1
 check(c.b._prepare_required_fee_runner(RefCounted.new(),kind,c.source)==null,"unregistered issuer cannot be rebuilt from public values")
 c.b._required_fee_runner_authority=RefCounted.new()
 check(c.b._prepare_required_fee_runner(c.b._required_fee_runner_authority,kind,"unlocked-source")==null,"no generic input fee or guessed source")
 c.b._depth-=1
 var cap:RefCounted=arm(c)
 var initial:Dictionary=before(c)
 check(not c.b.turn(RefCounted.new()).get("ok",false),c.tag+": wrong handle leaves real capability")
 if failures:finish(c);return
 if mode=="saved":check(c.b.save(),c.tag+": legitimate same-owner save before take");initial=before(c)
 c.b.mode=mode
 var r:Dictionary=c.b.turn(cap)
 if kind=="permit" and owned:
  check(r=={"ok":true,"stage":"already_owned","charged":false} and before(c)==initial and c.b.physical_calls==0 and c.b.facts.is_empty(),c.tag+": bool entitlement means zero IO/gold/fact/UID")
 else:
  var expected:Dictionary=paid(initial.profile,kind)
  check(r=={"ok":true,"stage":"committed","charged":true},c.tag+": only base mark authorizes success")
  check(c.b.actual_return and c.b.writer_observation.marked and c.b.writer_observation.io_entered,c.tag+": real physical return and actual marked fact")
  check(c.s._profile==expected and c.b.last_saved_payload==JSON.stringify(expected) and c.b.quest_save_serial==initial.serial+1,c.tag+": complete profile/cache/serial including untouched inventory, UID, rewards")
  check(rows(c)==[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},initial.rows[0],{"exists":false,"bytes":PackedByteArray()}],c.tag+": full primary/backup/tmp")
  var fact:Dictionary=expected_fact(c,expected,tx(c),initial.serial+1)
  check(c.b.facts==[{"type":"quest_result","fee_fact":fact}],c.tag+": exact standalone profile event, no manual label/no duplicate amount")
  check(Fact.valid(fact) and not ManualFact.valid(fact),c.tag+": independent automatic origin, A rejects unchanged")
  if mode=="nested":check(c.b.nested_rejected,c.tag+": active operation rejects recursive persist and forged call")
  if kind=="seimu":check(c.b.automation.position_map==31301 and c.b.automation.position_cell==Vector2i(10,104),c.tag+": actual Warp handoff only after mark")
 var frozen:Dictionary=before(c);var events:Array=c.b.facts.duplicate(true)
 check(not c.b.turn(cap).get("ok",false),c.tag+": replay consumed identity")
 c.b._depth+=1
 check(c.b._prepare_required_fee_runner(c.b._required_fee_runner_authority,kind,c.source)==null,c.tag+": same issuer cannot mint again")
 c.b._depth-=1
 check(before(c)==frozen and c.b.facts==events,c.tag+": whole replay inert")
 finish(c)
func failure(kind:String,mode:String)->void:
 var c:Dictionary=setup("failure-"+kind+"-"+mode,kind)
 if failures:finish(c);return
 if mode=="insufficient":c.s._profile.player.gold=199 if kind=="permit" else 299;check(c.b.save(),"fixture reduced gold saved")
 var cap:RefCounted=arm(c);var initial:Dictionary=before(c)
 c.b.mode=mode;c.s.mode=mode
 var r:Dictionary=c.b.turn(cap)
 check(not r.get("ok",false) and c.b.facts.is_empty(),c.tag+": false/unknown cannot be committed")
 var landed:bool=mode in ["false_after","post_unknown"]
 var expected:Dictionary=paid(initial.profile,kind)
 var expected_rows:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},initial.rows[0],{"exists":false,"bytes":PackedByteArray()}] if landed else initial.rows
 check(rows(c)==expected_rows,c.tag+": actual full disk even false after real write; no rollback fiction")
 var live:Dictionary=expected if mode=="false_after" else initial.profile
 check(c.s._profile==live and c.b.last_saved_payload==(JSON.stringify(expected) if mode=="false_after" else initial.cache) and c.b.quest_save_serial==initial.serial+(1 if mode=="false_after" else 0),c.tag+": exact confirmed-cache distinction")
 check(c.b.automation.position_map==initial.map and c.b.automation.position_cell==initial.cell,c.tag+": failed/unknown never publishes Warp")
 check(c.b._required_fee_runner.held(c.b)==(mode=="post_unknown"),c.tag+": hold only actual IO then unknown")
 if mode in ["pre_unknown","writer_pre_unknown","post_unknown"]:
  var expected_reads:int=3 if mode=="pre_unknown" else 9
  check(c.s.reads==expected_reads and c.b.writer_observation.io_entered==(mode=="post_unknown"),c.tag+": exact pre R1-3 / writer R4-6 / post R7-9 injection")
  for observed in c.s.trace:
   check(observed.io_entered==(mode=="post_unknown" and observed.read>=7),c.tag+": independently observed actual IO flag at read")
 if mode!="insufficient":tx(c)
 var frozen:Array=rows(c)
 check(not c.b.turn(cap).get("ok",false) and rows(c)==frozen,c.tag+": failed slot consumed, no retry")
 finish(c)
func admission(mode:String)->void:
 var c:Dictionary=setup("admission-"+mode)
 if failures:finish(c);return
 var cap:RefCounted=arm(c)
 var initial:Dictionary=before(c)
 match mode:
  "gatefalse":c.b.enabled=false
  "binding":c.b.fee_attach(71)
  "run":c.b.quest_auto.identity.begin()
  "step":c.b.quest_auto.identity.select_step("different")
  "issuer":c.b._required_fee_runner_authority=RefCounted.new()
  "detach":c.b.fee_detach(71)
  "revoke":c.b._required_fee_runner.revoke()
  "phase":c.b.quest_auto.phase="different"
  "client":c.b.quest_auto.client="different"
 check(not c.b.turn(cap).get("ok",false) and c.b.physical_calls==0 and c.b.facts.is_empty(),c.tag+": invalidated authority cannot reach writer")
 check(c.s._profile==initial.profile and rows(c)==initial.rows and c.b.last_saved_payload==initial.cache and c.b.quest_save_serial==initial.serial,c.tag+": full financial state unchanged")
 finish(c)
func successor(mode:String)->void:
 var c:Dictionary=setup("successor-"+mode)
 if failures:finish(c);return
 var cap:RefCounted=arm(c);var initial:Dictionary=before(c)
 var successor_state:Dictionary={}
 c.b.after=func(host):
  match mode:
   "binding":host.fee_attach(71)
   "serial":host.quest_save_serial+=9
   "path":host.save_path+=".next"
   "run":host.quest_auto.identity.begin()
   "arrival":host.quest_arrival.reset()
   "pending_ref":host.session._pending={}
   "page_ref":host.original_quests.pending={}
   "phase":host.quest_auto.phase="successor"
   "owner":host.session._profile=host.session._profile.duplicate(true);host.session._profile.character_id="100005"
  successor_state.merge({"profile":host.session._profile.duplicate(true),"cache":host.last_saved_payload,"serial":host.quest_save_serial,"path":host.save_path,"checkpoint":host.quest_auto.identity.checkpoint(),"binding":host._fee_bindings.get(71)},true)
 var r:Dictionary=c.b.turn(cap)
 check(not r.ok and c.b.actual_return and c.b.facts.is_empty(),c.tag+": stale post-write caller cannot mark/publish")
 var expected:Dictionary=paid(initial.profile,"permit")
 check(rows(c)==[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},initial.rows[0],{"exists":false,"bytes":PackedByteArray()}],c.tag+": actual old IO preserved")
 check({"profile":c.s._profile,"cache":c.b.last_saved_payload,"serial":c.b.quest_save_serial,"path":c.b.save_path,"checkpoint":c.b.quest_auto.identity.checkpoint(),"binding":c.b._fee_bindings.get(71)}==successor_state,c.tag+": exact successor authority and memory untouched")
 finish(c)
func run()->void:
 good("permit","second")
 if failures:summary("D0 TRANSACTION");return
 good("permit","wrapper_successor")
 if failures:summary("D0 TRANSACTION");return
 for kind in ["permit","seimu"]:
  for mode in ["success","wrapper_false","nested","saved"]:
   good(kind,mode)
   if failures:summary("D0 TRANSACTION");return
  good(kind,"owned",true)
  if failures:summary("D0 TRANSACTION");return
  for mode in ["insufficient","false_before","forged_true","tamper","false_after","pre_unknown","writer_pre_unknown","post_unknown"]:
   failure(kind,mode)
   if failures:summary("D0 TRANSACTION");return
 for mode in ["gatefalse","binding","run","step","issuer","detach","revoke","phase","client"]:
  admission(mode)
  if failures:summary("D0 TRANSACTION");return
 for mode in ["binding","serial","path","run","owner","arrival","pending_ref","page_ref","phase"]:
  successor(mode)
  if failures:summary("D0 TRANSACTION");return
 summary("D0 TRANSACTION")

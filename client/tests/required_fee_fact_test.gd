extends "res://tests/required_fee_test.gd"
## STATIC CANDIDATE: not yet run. Same synchronous real-handler fixture chain
## as required_fee_test; explicit return doubles are labeled below. No sockets
## or frame sleeps; disk success fixtures always run the actual base writer.
const Fact=preload("res://server/required_fee_fact.gd")
const Hub=preload("res://server/profile_hub.gd")

class ObservedBackend:
 extends Backend
 var mode:=""
 var armed:=false
 var transaction_at_entry:=""
 var base_return:=false
 var after_write:Callable
 var saved_frame:Dictionary={}
 func _save_required_fee(frame:Dictionary)->bool:
  transaction_at_entry=frame.transaction_id
  if armed and mode in ["unmarked_true","unmarked_false"]:
   armed=false
   # Deliberate private return double: no base writer, candidate or mark.
   return mode=="unmarked_true"
  base_return=super._save_required_fee(frame)
  saved_frame=frame
  if armed:
   armed=false
   if after_write.is_valid():after_write.call(self)
   if mode=="wrapper_false":return false
  return base_return

class LostReturnSession:
 extends Session
 var lose_return:=false
 var actually_written:=false
 func save_game(path:String)->bool:
  var result:bool=super.save_game(path)
  if lose_return:
   lose_return=false
   actually_written=result
   # Actual original writer ran; only its virtual return is lost. The fee
   # boundary cannot confirm it, so it must not publish committed.
   return false
  return result

var seen_transactions:Dictionary={}

func watch(b)->Array:
 var messages:Array=[]
 b.event.connect(func(message:Dictionary):messages.append(message.duplicate(true)))
 return messages

func financial(messages:Array)->Array:
 return messages.filter(func(message):return message.get("type")=="quest_result")

func expected_profile(before:Dictionary,kind:String)->Dictionary:
 # Independent full-profile oracle. Never calls the production candidate,
 # fact projection, warp helper or a helper-generated expected dictionary.
 var expected:Dictionary=before.duplicate(true)
 expected.player.gold-=200 if kind=="permit" else 300
 if kind=="permit":expected.travel_pass=true
 else:expected.location={"map_id":31301,"x":10,"y":104}
 return expected

func expected_message(kind:String,before:Dictionary,after:Dictionary,tx:String,serial:int,durability:String)->Dictionary:
 var fact:Dictionary={
  "schema":1,"scope":"profile","origin":"manual",
  "owner":{"profile_id":before.profile_id,"character_id":before.character_id},
  "transaction_id":tx,"fee_kind":"undersea_permit200" if kind=="permit" else "seimu300",
  "phase":"permit_purchase" if kind=="permit" else "gate_crossing",
  "source_id":"genout/ss_1100_86_107" if kind=="permit" else "genout/wpm_40_13_1@40:13:1",
  "currency":"stone","amount":200 if kind=="permit" else 300,
  "balance_before":1000,"balance_after":800 if kind=="permit" else 700,
  "status":"committed","durability":durability,"save_serial":serial,
  "candidate_sha256":JSON.stringify(after).sha256_text()
 }
 if kind=="permit":fact.entitlement="travel_pass"
 else:fact.destination={"map_id":31301,"cell":[10,104]}
 return {"type":"quest_result","v":1,"text":"原售证：永久海底通行资格已生效，扣除200石币，提交后余额800。" if kind=="permit" else "赛姆原通行费，扣除300石币，提交后余额700。","fee_fact":fact}

func check_transaction(tx:String)->void:
 check(tx.length()==32 and tx.is_valid_hex_number() and tx==tx.to_lower(),"Server transaction identity is a 128-bit lowercase hex ID")
 check(not seen_transactions.has(tx),"Each original candidate submission has an independent transaction ID")
 seen_transactions[tx]=true

func check_saved(b,path:String,expected:Dictionary)->void:
 var bytes:PackedByteArray=disk(path)
 if failures:return
 var parsed:Dictionary=Compare.validated_copy(b.session,bytes.get_string_from_utf8())
 check(parsed.get("ok",false) and parsed.profile==expected,"Whole actual persisted profile equals independent oracle")
 check(bytes==JSON.stringify(expected).to_utf8_buffer(),"Original writer bytes equal exact candidate including unrelated profile fields")

func case_success(kind:String,mode:String)->void:
 var b=ObservedBackend.new()
 if not setup(b,kind,"fact-"+kind+"-"+mode,1000):b.free();return
 var saved_path:String=b.save_path
 var original_disk:PackedByteArray=disk(saved_path)
 if failures:b.free();return
 if mode=="memory":b.save_path=""
 var events:Array=watch(b)
 var opened:Dictionary=open_fee(b,kind)
 check(opened.get("ok",false) and opened.has("dialogue") and financial(events).is_empty(),"Real original token page has no committed fee fact")
 if failures:b.free();return
 var before:Dictionary=b.session.snapshot()
 var cache_before:String=b.last_saved_payload
 var serial_before:int=b.quest_save_serial
 var expected:Dictionary=expected_profile(before,kind)
 var old_session=b.session
 var successor:Dictionary={}
 var callback:Array=[false]
 b.mode=mode;b.armed=true
 b.after_write=func(host):
  callback[0]=true
  if mode=="stop":
   var stopped:Dictionary=host.handle({"type":"quest_auto_stop"})
   check(stopped.get("ok",false),"Real explicit Stop after committed writer returns")
  elif mode=="owner_successor":
   # Disclosed private owner-replacement fixture at the virtual return edge.
   # New full session and path are really saved; no fake fee writer result.
   host.session=Session.new()
   host.session._profile.character_id="100005"
   host.save_path=saved_path+".successor.json"
   check(not FileAccess.file_exists(host.save_path),"Fresh successor profile path")
   check(host.save(),"Actual full successor save after old candidate committed")
   if failures:return
   successor.merge(record(host),true)
  # Duplicate publication attempt against the same marked frame is a no-op.
  Fee.publish_committed(host,host.saved_frame)
 var reply:Dictionary=choose_fee(b,kind,opened)
 if failures:b.free();return
 check(reply.get("ok",false) and reply.get("committed",false) and b.base_return and callback[0],"Base commit survives outer false/Stop/successor return")
 check_transaction(b.transaction_at_entry)
 var expected_event:Dictionary=expected_message(kind,before,expected,b.transaction_at_entry,serial_before+1,"memory" if mode=="memory" else "disk")
 check(financial(events)==[expected_event],"One exact complete profile-scoped fee event, unchanged text and actual candidate facts")
 if failures:b.free();return
 check(Fact.valid(expected_event.fee_fact),"Independent exact event satisfies strict tagged contract")
 check(old_session.snapshot()==expected,"Complete original owner profile retains exactly the original fee candidate")
 if mode=="owner_successor":
  check(record(b)==successor,"Old return and duplicate publish cannot overwrite complete successor state")
  check(b.session._profile.character_id!=expected_event.fee_fact.owner.character_id,"Fact owner stays with committed old owner")
 elif mode=="memory":
  check(b.last_saved_payload==cache_before and disk(saved_path)==original_disk,"Memory success is explicitly nondurable and leaves disk/cache unchanged")
  check(b.quest_save_serial==serial_before+1,"Memory base mark advances original serial once")
 else:
  check(b.session.snapshot()==expected and b.last_saved_payload==JSON.stringify(expected),"Whole live candidate and cache remain exact")
  check(b.quest_save_serial==serial_before+1,"Disk fee transaction advances serial once")
 if mode!="memory":
  check_saved(b,saved_path,expected)
  check(disk(saved_path+".bak")==original_disk,"Successful original writer retains entire previous primary as backup")
 if failures:b.free();return
 var state_before_replay:Dictionary={"profile":b.session.snapshot(),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"map":b.automation.position_map,"cell":b.automation.position_cell,"page":b.original_quests.pending.duplicate(true)}
 check(not choose_fee(b,kind,opened).get("ok",true),"Actual consumed token cannot charge or publish again")
 check({"profile":b.session.snapshot(),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"map":b.automation.position_map,"cell":b.automation.position_cell,"page":b.original_quests.pending.duplicate(true)}==state_before_replay,"Token replay preserves complete profile/cache/position/page")
 check(financial(events)==[expected_event],"Replay does not duplicate (owner, transaction_id, phase)")
 b.free()

func case_failure(kind:String,mode:String)->void:
 var b=ObservedBackend.new()
 if mode=="unknown_landed":b.session=LostReturnSession.new()
 var cost:int=200 if kind=="permit" else 300
 if not setup(b,kind,"fact-failure-"+kind+"-"+mode,cost-1 if mode=="insufficient" else 1000):b.free();return
 var events:Array=watch(b)
 var opened:Dictionary=open_fee(b,kind)
 check(opened.get("ok",false) and opened.has("dialogue"),"Failure case uses real source token")
 if failures:b.free();return
 var before:Dictionary=record(b)
 if failures:b.free();return
 before.page={}
 if mode=="savefail":check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Genuine isolated writer-open failure")
 if failures:b.free();return
 if mode=="unknown_landed":b.session.lose_return=true
 b.mode=mode;b.armed=true
 var reply:Dictionary=choose_fee(b,kind,opened)
 check(not reply.get("ok",true) and not reply.get("committed",false),"Failed or unconfirmed return does not claim committed")
 check(financial(events).is_empty(),"Failure/unknown never publishes committed text or typed fee fact")
 if failures:b.free();return
 var after:Dictionary=record(b)
 if failures:b.free();return
 if mode=="unknown_landed":
  check(b.session.actually_written,"Unknown case actually wrote through original Session writer before false return")
  var expected:Dictionary=expected_profile(before.profile,kind)
  check_saved(b,b.save_path,expected)
  check(after.disk==JSON.stringify(expected).to_utf8_buffer() and after.bak=={"exists":true,"bytes":before.disk},"Unknown disk outcome is retained, never fabricated as a financial success")
  # Existing base-writer false-return rollback is unchanged in slice A.
  after.disk=before.disk;after.bak=before.bak
 check(after==before,"Full non-disk authority/cache/profile remains exact on failed/unconfirmed mark")
 check(not choose_fee(b,kind,opened).get("ok",true) and financial(events).is_empty(),"Failed consumed token cannot replay a fee")
 b.free()

func case_profile_scope()->void:
 var b=ObservedBackend.new()
 if not setup(b,"permit","fact-profile-scope",1000):b.free();return
 var hub=Hub.new()
 hub.tick=false;hub.share_dir=""
 # Connection routing fixture only, not authentication or real WebSockets.
 hub._connections={71:{"id":"a"},72:{"id":"a"},73:{"id":"other"}}
 b.event.connect(hub._on_backend_event.bind("a"))
 var delivered:Array=[]
 hub.outgoing.connect(func(connection:int,message:Dictionary):
  if message.get("type")=="quest_result":delivered.append({"connection":connection,"message":message.duplicate(true)})
 )
 var before:Dictionary=b.session.snapshot()
 var serial:int=b.quest_save_serial
 var opened:Dictionary=open_fee(b,"permit")
 check(opened.get("ok",false) and opened.has("dialogue"),"Profile routing uses actual permit page")
 if failures:hub.free();b.free();return
 var reply:Dictionary=choose_fee(b,"permit",opened)
 check(reply.get("committed",false),"Profile routing uses actual committed writer")
 check_transaction(b.transaction_at_entry)
 var expected:Dictionary=expected_message("permit",before,expected_profile(before,"permit"),b.transaction_at_entry,serial+1,"disk")
 check(delivered.size()==2 and delivered.has({"connection":71,"message":expected}) and delivered.has({"connection":72,"message":expected}),"Both profile devices receive same owner/tx/phase; unrelated profile receives none")
 hub.free();b.free()

func pure_example(permit:bool=true)->Dictionary:
 # Literal independent oracle, not generated by Fact.from_committed.
 var value:Dictionary={"schema":1,"scope":"profile","origin":"manual","owner":{"profile_id":"samgir-singleplayer-v1","character_id":"100000"},"transaction_id":"0123456789abcdef0123456789abcdef","fee_kind":"undersea_permit200" if permit else "seimu300","phase":"permit_purchase" if permit else "gate_crossing","source_id":"genout/ss_1100_86_107" if permit else "genout/wpm_40_13_1@40:13:1","currency":"stone","amount":200 if permit else 300,"balance_before":1000,"balance_after":800 if permit else 700,"status":"committed","durability":"disk","save_serial":7,"candidate_sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}
 if permit:value.entitlement="travel_pass"
 else:value.destination={"map_id":31301,"cell":[10,104]}
 return value

func case_strict_shapes()->void:
 for permit in [true,false]:
  var valid:Dictionary=pure_example(permit)
  check(Fact.valid(valid),"Independent literal tagged shape accepted")
  for field in valid:
   var missing:Dictionary=valid.duplicate(true);missing.erase(field)
   check(not Fact.valid(missing),"Every exact tag field required: "+field)
   var wrong:Dictionary=valid.duplicate(true);wrong[field]=null
   check(not Fact.valid(wrong),"Null field rejected: "+field)
  for field in ["run_id","step_id","revision","attempt_id","ticket_uid","consumed_ticket_uid","item_id","connection","open_id","token","purchase_amount"]:
   var extra:Dictionary=valid.duplicate(true);extra[field]=1
   check(not Fact.valid(extra),"Manual fee never fabricates run/UID/transport/purchase fields: "+field)
  for field in ["schema","amount","balance_before","balance_after","save_serial"]:
   for value in [true,false,-1,0.5,float(valid[field]),NAN,INF,"200",null]:
    var wrong:Dictionary=valid.duplicate(true);wrong[field]=value
    check(not Fact.valid(wrong),"Strict numeric field rejects bad type/range: "+field)
  for field in ["status","phase","fee_kind","source_id","durability","scope","origin","currency"]:
   for value in [true,1,{},[],"", "unknown", "failed", "ticket_purchase", "ticket_entry"]:
    var wrong:Dictionary=valid.duplicate(true);wrong[field]=value
    check(not Fact.valid(wrong),"Exact discriminator rejects unsupported value: "+field)
  for field in ["transaction_id","candidate_sha256"]:
   for value in [true,1,"", "x".repeat(64),"a".repeat(31),"A".repeat(32),"0x"+"a".repeat(30)]:
    var wrong:Dictionary=valid.duplicate(true);wrong[field]=value
    check(not Fact.valid(wrong),"Strict hex identity: "+field)
  for owner in [{},{"profile_id":"p"},{"profile_id":"p","character_id":"c","run_id":"r"},{"profile_id":1,"character_id":"c"},{"profile_id":"p","character_id":true},{"profile_id":"","character_id":"c"},{"profile_id":"p","character_id":"c".repeat(129)}]:
   var wrong:Dictionary=valid.duplicate(true);wrong.owner=owner
   check(not Fact.valid(wrong),"Strict owner attribution")
  var mismatch:Dictionary=valid.duplicate(true);mismatch.balance_after+=1
  check(not Fact.valid(mismatch),"Exact amount/balance equation required")
  mismatch=valid.duplicate(true);mismatch.balance_before=1000000001;mismatch.balance_after=1000000001-mismatch.amount
  check(not Fact.valid(mismatch),"Balance cannot exceed actual game gold limit")
  if permit:
   for value in [2422,true,"2422",{},"ticket"]:
    var wrong:Dictionary=valid.duplicate(true);wrong.entitlement=value
    check(not Fact.valid(wrong),"200 is permanent entitlement, never entity ticket")
   var second_shop:Dictionary=valid.duplicate(true);second_shop.source_id="genout/ss_4000_99_85"
   check(Fact.valid(second_shop),"Only the second exact original shop is also accepted")
  else:
   for value in [{"map_id":31301.0,"cell":[10,104]},{"map_id":31301,"cell":[10.0,104]},{"map_id":31301,"cell":[10,true]},{"map_id":31301,"cell":[10,104,0]},{"map_id":31302,"cell":[10,104]},{"map_id":31301,"cell":[10,104],"other":0}]:
    var wrong:Dictionary=valid.duplicate(true);wrong.destination=value
    check(not Fact.valid(wrong),"Only exact typed original Warp destination accepted")
 for value in [null,true,[],1,"committed"]:check(not Fact.valid(value),"Non-dictionary fact rejected")

func case_projection_boundary()->void:
 # Tiny disclosed pure inputs check projection rejection/isolation only. Real
 # full profiles and writes are independently asserted in handler cases above.
 var before:Dictionary={"profile_id":"samgir-singleplayer-v1","character_id":"100000","player":{"gold":1000},"travel_pass":false,"location":{"map_id":1100,"x":85,"y":107},"unrelated":{"sentinel":[1,2,3]}}
 var committed:Dictionary=before.duplicate(true)
 committed.player.gold=800;committed.travel_pass=true
 var frame:Dictionary={"marked":true,"durable":true,"path":"user://pure-unused.json","before":before,"committed":committed,"kind":"permit","source":"genout/ss_1100_86_107","transaction_id":"0123456789abcdef0123456789abcdef","committed_serial":7,"payload":JSON.stringify(committed)}
 var original:Dictionary=frame.duplicate(true)
 var expected:Dictionary=pure_example()
 expected.candidate_sha256=JSON.stringify(committed).sha256_text()
 var projected:Dictionary=Fact.from_committed(frame)
 check(projected==expected and frame==original,"Pure projection copies exact independently specified committed fact without input mutation")
 if failures:return
 frame.committed.player.gold=1;frame.before.character_id="100005"
 check(projected==expected,"Already projected fact does not alias later owner/balance mutations")
 for field in ["marked","durable","path","before","committed","kind","source","transaction_id","committed_serial","payload"]:
  var missing:Dictionary=original.duplicate(true);missing.erase(field)
  check(Fact.from_committed(missing).is_empty(),"Projection requires explicit writer observation: "+field)
 for value in [false,1,"true",null]:
  var unmarked:Dictionary=original.duplicate(true);unmarked.marked=value
  check(Fact.from_committed(unmarked).is_empty(),"No actual strict writer mark, no committed fact")
 for value in [1,"disk",null]:
  var untyped:Dictionary=original.duplicate(true);untyped.durable=value
  check(Fact.from_committed(untyped).is_empty(),"No truthy durability coercion")
 var unknown:Dictionary=original.duplicate(true);unknown.path=""
 check(Fact.from_committed(unknown).is_empty(),"Disk claim cannot accompany memory-only writer path")
 unknown=original.duplicate(true);unknown.payload="different candidate"
 check(Fact.from_committed(unknown).is_empty(),"Candidate digest cannot describe another payload")
 unknown=original.duplicate(true);unknown.committed.unrelated.sentinel.append(4);unknown.payload=JSON.stringify(unknown.committed)
 check(Fact.from_committed(unknown).is_empty(),"Coincidental balances do not hide unrelated full-profile mutation")
 unknown=original.duplicate(true);unknown.committed.character_id="100005";unknown.payload=JSON.stringify(unknown.committed)
 check(Fact.from_committed(unknown).is_empty(),"Cross-owner candidate cannot mint an old-owner fact")
 var owner_checks:int=0
 for side in ["before","committed"]:
  for field in ["profile_id","character_id"]:
   for bad_owner in [null,true,false,1,1.0,[],["100000"],{},"","x".repeat(129)]:
    var malformed:Dictionary=original.duplicate(true)
    malformed[side][field]=bad_owner
    var rejected:Dictionary=Fact.from_committed(malformed)
    check(rejected=={},"Malformed "+side+" owner returns empty without mixed-type comparison: "+field)
    owner_checks+=1
   var missing:Dictionary=original.duplicate(true)
   missing[side].erase(field)
   var rejected_missing:Dictionary=Fact.from_committed(missing)
   check(rejected_missing=={},"Missing "+side+" owner key returns empty without exception: "+field)
   owner_checks+=1
 check(owner_checks==44,"Both owner sides complete all 44 malformed/missing cases without aborting")
 check(Fact.MAX_GOLD==Session.MAX_GOLD and Fact.MAX_GOLD==1000000000,"Fee fact range equals actual Session gold limit")
 print("FEE FACT OWNER REJECTION: %d / 44 cases completed"%owner_checks)

func run()->void:
 case_strict_shapes()
 case_projection_boundary()
 if failures:quit(1);return
 for kind in ["permit","seimu"]:
  for mode in ["success","wrapper_false","stop","owner_successor","memory"]:
   case_success(kind,mode)
   if failures:quit(1);return
  for mode in ["insufficient","savefail","unmarked_true","unmarked_false","unknown_landed"]:
   case_failure(kind,mode)
   if failures:quit(1);return
 case_profile_scope()
 print("REQUIRED FEE FACT: %d failures; real handlers/base writer, explicit return and owner fixtures; no automatic payment or crash replay claim"%failures)
 quit(1 if failures else 0)

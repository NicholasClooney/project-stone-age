extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## UNRUN tmp. Real adult job1 only; no Fire travel/request, no completion injection.
const Rules=preload("res://server/original_quests.gd")
const Wait=preload("res://tests/support/wait.gd")
const Progression=preload("res://server/progression.gd")
const SAVE="user://fire-real-adult-prerequisite.json"
const TRACE="user://fire-real-adult-prerequisite-trace.json"
const CLIENT="fire-adult-prerequisite"
const MAX_POINTS=6000
class ObservedBackend extends "res://server/backend.gd":
 var transactions:Array=[]
 var fields:Array=[]
 var diagnostic_errors:Array=[]
 static func bytes_sha(raw:PackedByteArray)->Dictionary:
  var evidence:Dictionary={"ok":false,"start_error":FAILED,"update_error":FAILED,"digest_length":0,"sha256":""}
  var context:HashingContext=HashingContext.new()
  evidence.start_error=context.start(HashingContext.HASH_SHA256)
  if evidence.start_error!=OK:return evidence
  evidence.update_error=context.update(raw)
  if evidence.update_error!=OK:return evidence
  var digest:PackedByteArray=context.finish()
  evidence.digest_length=digest.size()
  if digest.size()!=32:return evidence
  evidence.sha256=digest.hex_encode();evidence.ok=true
  return evidence
 static func read_evidence(path:String)->Dictionary:
  var record:Dictionary={"path":path,"ok":false,"open_error":OK,"length_error":OK,"read_error":OK,"length":-1,"bytes_read":0,"raw_base64":"","sha256":"","parse_error":ERR_PARSE_ERROR,"parsed":null}
  var file:FileAccess=FileAccess.open(path,FileAccess.READ)
  record.open_error=FileAccess.get_open_error()
  if file==null:return record
  var length:int=file.get_length()
  record.length=length;record.length_error=file.get_error()
  if record.length_error!=OK or length<=0:
   file.close();return record
  var raw:PackedByteArray=file.get_buffer(length)
  record.read_error=file.get_error()
  file.close()
  record.length=length;record.bytes_read=raw.size()
  record.raw_base64=Marshalls.raw_to_base64(raw)
  var hash_evidence:Dictionary=bytes_sha(raw)
  record.hash_evidence=hash_evidence;record.sha256=hash_evidence.sha256
  if record.open_error!=OK or record.length_error!=OK or record.read_error!=OK or raw.size()!=length or not hash_evidence.ok:return record
  var parser:JSON=JSON.new()
  record.parse_error=parser.parse(raw.get_string_from_utf8())
  record.parse_line=parser.get_error_line();record.parse_message=parser.get_error_message()
  record.parsed=parser.data if record.parse_error==OK else null
  record.ok=record.parse_error==OK and record.parsed is Dictionary
  return record
 func save_quest_source_transaction(npc_id:String,branch:Dictionary,phase:String)->bool:
  var candidate:Dictionary=session.snapshot()
  var result:bool=super.save_quest_source_transaction(npc_id,branch,phase)
  if npc_id in ["jaruga/event/event04_1","jaruga/event/event04_2"]:
   var evidence:Dictionary=read_evidence(save_path)
   if not evidence.ok:diagnostic_errors.append({"kind":"transaction_read","index":transactions.size(),"evidence":evidence})
   var disk:Variant=evidence.parsed
   transactions.append({"npc_id":npc_id,"branch":branch.duplicate(true),"phase":phase,"ok":result,"candidate":candidate,"disk":disk,"disk_evidence":evidence,"authority":[automation.position_map,[automation.position_cell.x,automation.position_cell.y]],"save_serial":quest_save_serial})
  return result
 func _cmd_field_step(command:Dictionary)->Dictionary:
  var result:Dictionary=super._cmd_field_step(command)
  fields.append({"command":command.duplicate(true),"result":result.duplicate(true)})
  return result
var b
var assertions:int=0
var failures:int=0
var packets:Array=[]
var moves:Array=[]
var saved_seen:int=0
var points:int=0
var saw_completed:bool=false
var final_authority:Array=[]
var final_evidence:Dictionary={}
var trace_reuse_refused:bool=false
var began:int=Clock.ticks_msec()
func _initialize()->void:call_deferred("run")
static func same(a:Variant,c:Variant)->bool:
 if a is bool or c is bool:return a is bool and c is bool and a==c
 if a is int or a is float:return (c is int or c is float) and is_finite(float(a)) and is_finite(float(c)) and float(a)==floor(float(a)) and float(c)==floor(float(c)) and a==c
 if a is Array and c is Array:
  if a.size()!=c.size():return false
  for i in range(a.size()):
   if not same(a[i],c[i]):return false
  return true
 if a is Dictionary and c is Dictionary:
  if a.size()!=c.size():return false
  for key in a:
   if not c.has(key) or not same(a[key],c[key]):return false
  return true
 return typeof(a)==typeof(c) and a==c
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func saved_transactions()->bool:
 while saved_seen<b.transactions.size():
  var index:int=saved_seen
  var row:Dictionary=b.transactions[index]
  saved_seen+=1
  if not check(index<3 and row.ok and row.disk is Dictionary and same(row.candidate,row.disk),"Original transaction normal save full-profile readback "+str(index)):return false
  var expected_id:String="jaruga/event/event04_2" if index==1 else "jaruga/event/event04_1"
  if not check(row.npc_id==expected_id and int(row.branch.event)==4,"Exact original three-exchange NPC/event order"):return false
  var profile:Dictionary=row.candidate
  if index==0:
   if not check(row.phase=="REQUEST" and Rules.flag(profile,"now",4) and not Rules.flag(profile,"ended",4) and profile.original_items.is_empty(),"Real adult request grants only NOW4"):return false
  elif index==1:
   if not check(row.phase=="reward" and profile.original_items.size()==15 and profile.original_items.count(2417)==15 and not Rules.flag(profile,"ended",4),"Original messenger actually grants fifteen jade"):return false
  else:
   if not check(row.phase=="reward" and profile.original_items==[2418] and Rules.flag(profile,"ended",4) and not Rules.flag(profile,"now",4),"Judge consumes real fifteen jade and grants helmet END4"):return false
 return true
func advance()->bool:
 if failures:return true
 if not b.diagnostic_errors.is_empty():
  check(false,"Existing transaction I/O diagnostic; do not tick again");return true
 for iteration in range(16):
  var old_map:int=b.automation.position_map
  var old:Vector2i=b.automation.position_cell
  b.quest_auto.tick(b,0.21)
  if not b.diagnostic_errors.is_empty():
   check(false,"Transaction evidence I/O failed; stop immediately after original tick");return true
  if not saved_transactions():return true
  var map_id:int=b.automation.position_map
  var cell:Vector2i=b.automation.position_cell
  if old_map!=map_id or old!=cell:
   points+=1
   var link:Dictionary=b.quest_helper.places.links(old_map).get(old,{})
   var move:Dictionary={"from_map":old_map,"from":[old.x,old.y],"map_id":map_id,"cell":[cell.x,cell.y],"link":link.duplicate(true),"phase":b.quest_auto.phase}
   moves.append(move)
   if not check(points<=MAX_POINTS and not saw_completed,"Original path bound; no movement after actual END4"):return true
   if old_map==map_id:
    if not check(absi(old.x-cell.x)+absi(old.y-cell.y)==1,"Mode A remains a single original adjacent logical cell"):return true
   else:
    if not check(not link.is_empty() and not link.get("disabled",false) and int(link.to_map)==map_id and same(link.target,[cell.x,cell.y]),"Every actual cross-map move is its original independent portal"):return true
  while not packets.is_empty():
   var packet:Dictionary=packets.pop_front()
   var command:Dictionary={"type":"report_position","map_id":packet.map_id,"cell":packet.cell.duplicate(),"client":CLIENT,"_quest_connection":71}
   for field in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq"]:
    if packet.has(field):command[field]=packet[field]
   if not check(b.handle(command).get("ok",false),"Acknowledge actual issued receipt without inventing coordinate"):return true
  if not check(not b.battle_open,"Explicit no_random compatibility, no forced enemy or victory"):return true
  if Rules.flag(b.session._profile,"ended",4) and b.session._profile.original_items==[2418]:
   saw_completed=true
   final_authority=[map_id,[cell.x,cell.y]]
   # Stop driving immediately at actual completed reward. No Fire or tail-loop work.
   return true
  if not b.quest_auto.running:
   check(false,"Adult runner stopped before END4: "+str(b.quest_auto.message));return true
 return false
static func path_exists(path:String)->bool:
 return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))
func run()->void:
 trace_reuse_refused=path_exists(TRACE)
 assertions+=1
 if trace_reuse_refused:
  failures+=1;finish();return
 b=ObservedBackend.new();b.set_process(false);b.save_path=SAVE
 for path in [SAVE,SAVE+".bak",SAVE+".tmp",SAVE.get_basename()+".resume.json",SAVE.get_basename()+".resume.json.tmp",SAVE.get_basename()+".resume.json.bak"]:
  if not check(not path_exists(path),"Reject existing save or sidecar: "+path):finish();return
 if not check(not Rules.flag(b.session._profile,"now",4) and not Rules.flag(b.session._profile,"ended",4) and not 2417 in b.session._profile.original_items and not 2418 in b.session._profile.original_items,"Actual fresh profile has no adult completion items or flags"):finish();return
 b.session.gm_raise_level(-1,30)
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 Progression.refresh(b.session._profile.player);b.session._profile.player.hp=b.session._profile.player.max_hp
 # Explicit empty-bag fixture; no original item/flag/proof is manufactured.
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 if not check(b.handle({"type":"no_random_encounters","enabled":true}).get("ok",false),"Disclosed encounter-off compatibility"):finish();return
 var spawn:Array=b.quest_helper.places.info(1000).spawn
 b.automation.position_changed(1000,Vector2i(int(spawn[0]),int(spawn[1])),true,"project")
 if not check(b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"Public initial authority grants no protected proof"):finish();return
 if not check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"A"}}}).get("ok",false),"Original A preference saves through production command"):finish();return
 if not check(b.save(),"Durable initial fixture only, never an extra endpoint save"):finish();return
 b.event.connect(func(event:Dictionary):
  if event.get("type")=="position" and event.has("quest_position_seq"):packets.append(event.duplicate(true)))
 if not check(b.handle({"type":"quest_auto_start","quest_id":1,"client":CLIENT,"_quest_connection":71}).get("ok",false),"Actual adult job1 begins from public village"):finish();return
 var completed:bool=await Wait.until(self,advance)
 if failures:finish();return
 if not check(completed and saw_completed and b.transactions.size()==3,"Single shared Wait reaches only real adult three-transaction completion"):finish();return
 if not check(points>300 and final_authority[0]==10204,"Full original public approach and ritual walks, not direct gate placement"):finish();return
 if not check(b.fields.size()>0 and b.session._profile.original_items==[2418] and Rules.flag(b.session._profile,"ended",4),"Actual field calls and final earned prerequisite preserved"):finish();return
 var final_read:Dictionary=ObservedBackend.read_evidence(SAVE)
 final_evidence=final_read
 if not final_read.ok:
  b.diagnostic_errors.append({"kind":"final_read","evidence":final_read})
  check(false,"Final original save evidence read failed");finish();return
 var disk:Variant=final_read.parsed
 if not check(disk is Dictionary and same(disk,b.transactions[-1].candidate),"Final disk remains last original transaction, no supplemental save"):finish();return
 finish()
func finish()->void:
 # A rejected existing TRACE is never opened, even during failure cleanup.
 if trace_reuse_refused or path_exists(TRACE):
  if failures==0:failures+=1
  print("ADULT_TRACE_IO ",JSON.stringify({"path":TRACE,"error":"existing_trace_file_or_directory","write_attempted":false}))
  if b!=null:b.free()
  print("quest_auto_fire_adult_prerequisite_test: %d assertions, %d failures"%[assertions,failures])
  quit(1);return
 var result:Dictionary={"assertions":assertions,"failures":failures,"elapsed_msec":Clock.ticks_msec()-began,"points":points,"moves":moves,"completed":saw_completed,"final_authority":final_authority,"final_evidence":final_evidence}
 if b!=null:
  result.transactions=b.transactions;result.fields=b.fields;result.diagnostic_errors=b.diagnostic_errors
  # Captured transaction candidate only, never a new snapshot/projection during failure handling.
  result.last_saved_candidate=b.transactions[-1].candidate if not b.transactions.is_empty() else {}
  result.runner={"running":b.quest_auto.running,"phase":b.quest_auto.phase,"message":b.quest_auto.message}
 var bytes:PackedByteArray=JSON.stringify(result).to_utf8_buffer()
 var expected_hash:Dictionary=ObservedBackend.bytes_sha(bytes)
 if not expected_hash.ok:
  failures+=1
  push_error("TRACE hashing start/update/finish failed; no write attempted")
  print("ADULT_TRACE_IO ",JSON.stringify({"path":TRACE,"hash_evidence":expected_hash,"write_attempted":false}))
  if b!=null:b.free()
  print("quest_auto_fire_adult_prerequisite_test: %d assertions, %d failures"%[assertions,failures])
  quit(1);return
 var expected_sha:String=expected_hash.sha256
 var trace_evidence:Dictionary={"path":TRACE,"expected_length":bytes.size(),"expected_sha256":expected_sha,"expected_hash_evidence":expected_hash}
 var file:FileAccess=FileAccess.open(TRACE,FileAccess.WRITE)
 trace_evidence.open_error=FileAccess.get_open_error()
 var written:bool=file!=null and trace_evidence.open_error==OK
 if file!=null:
  file.store_buffer(bytes);file.flush()
  trace_evidence.write_error=file.get_error();trace_evidence.write_position=file.get_position()
  written=written and trace_evidence.write_error==OK and trace_evidence.write_position==bytes.size()
  file.close()
 var readback:Dictionary=ObservedBackend.read_evidence(TRACE) if written else {}
 trace_evidence.readback={}
 for key in ["path","ok","open_error","length_error","read_error","length","bytes_read","sha256","hash_evidence","parse_error","parse_line","parse_message"]:
  if readback.has(key):trace_evidence.readback[key]=readback[key]
 var verified:bool=expected_hash.ok and written and readback.get("ok",false) and readback.get("hash_evidence",{}).get("ok",false) and int(readback.get("length",-1))==bytes.size() and str(readback.get("sha256",""))==expected_sha
 # This stdout record authenticates the closed TRACE; cannot place its own hash inside itself.
 print("ADULT_TRACE_IO ",JSON.stringify(trace_evidence))
 if not verified:
  failures+=1
  push_error("TRACE open/write/closed-read length or SHA verification failed")
 if b!=null:b.free()
 print("quest_auto_fire_adult_prerequisite_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)

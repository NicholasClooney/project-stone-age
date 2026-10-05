extends "res://tests/quest_auto_loot_continuation_test.gd"
# TMP UNPARSED/UNRUN. Internal source/clock; original complete pool, no group injection.
var tail_seen:=false
func tail(b)->void:
 b.set_process(false)
 if failures:return
 tail_seen=true
func normal_once(b)->bool:
 tail_seen=false;b.set_process(true)
 var arrived:bool=await Wait.until(self,func():return failures>0 or tail_seen)
 if failures:return false
 check(arrived and tail_seen,"One actual normal process returned through runner")
 return failures==0
func run_mode(mode:String)->void:
 for selected_mode in [mode]:
  var b=CountedBackend.new();var time:Array=[1000]
  var path:String="user://loot-two-battle-"+mode+".json"
  if not fresh_paths(path):b.free();quit(1);return
  if not closed_fixture(b,path,time):b.free();quit(1);return
  if not archive_pair(b,"first_closed"):b.free();quit(1);return
  var first:Dictionary=b.session._profile.quest_loot.entries[KEY].duplicate(true)
  b.quest_auto.after_tick=tail;root.add_child(b)
  for index in range(100):
   if not await normal_once(b):b.free();quit(1);return
   if b.quest_loot.ready_frame.has("continuation_gate"):break
  check(b.quest_loot.ready_frame.has("continuation_gate"),"Actual C1 and flush barrier open second span via original C2")
  if failures:b.free();quit(1);return
  # Same disclosed deterministic input as the accepted progress fixture.
  b.encounter_rng.seed=4101;b.encounter_catalog.pressure=50
  var reached:=false
  for index in range(200):
   time[0]=maxi(time[0],b.quest_loot.next_attempt_ms)
   if not await normal_once(b):b.free();quit(1);return
   if b.battle_open:reached=true;break
   time[0]+=500
  check(reached and b.session._pending.get("group_id")==169 and b.session._pending.has("quest_loot_receipt"),"Original full-pool second group169 actually starts")
  if failures:b.free();quit(1);return
  var receipt:Dictionary=b.session._pending.quest_loot_receipt.duplicate(true)
  var pending:Dictionary=b.session._pending.duplicate(true)
  var before:Dictionary=b.session.snapshot();var old_disk:PackedByteArray=checked_bytes(b.save_path)
  if failures:b.free();quit(1);return
  if not archive_pair(b,"second_open"):b.free();quit(1);return
  var fields:int=b.field_calls
  if mode=="second_savefail":
   check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own second-result writer blocker")
   if failures:b.free();quit(1);return
  var terminal:=false
  for index in range(100):
   time[0]+=500
   if not await normal_once(b):b.free();quit(1);return
   if not b.automation.running:terminal=true;break
  check(terminal,"Original second single battle finishes/stops within100 normal ticks")
  if failures:b.free();quit(1);return
  if mode=="second_savefail":
   check(b.battle_open and not b.battle.snapshot().active and str(b.battle.snapshot().battle_id)==str(pending.battle_id) and not b.battle_state.get("settled",true),"Real second result failed; original battle remains")
   if failures:b.free();quit(1);return
   var expected:Dictionary=pending.duplicate(true)
   expected.loot_claims=b.battle.drop_claims_for()
   var failed_bytes:PackedByteArray=checked_bytes(b.save_path)
   if failures:b.free();quit(1);return
   check(b.session._pending==expected and b.session.snapshot()==before and failed_bytes==old_disk and b.quest_loot.storage_paused,"Complete failed second candidate retains original pending/profile/disk")
   if failures:b.free();quit(1);return
   if not archive_pair(b,"second_failed"):b.free();quit(1);return
   var frozen:Dictionary=b.quest_loot.cached_sample.duplicate(true)
   time[0]+=999999
   if not await normal_once(b):b.free();quit(1);return
   var waiting_bytes:PackedByteArray=checked_bytes(b.save_path)
   if failures:b.free();quit(1);return
   check(b.quest_loot.cached_sample==frozen and b.session._pending==expected and waiting_bytes==old_disk,"Storage wait never resamples or repeats result")
   if failures:b.free();quit(1);return
   check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Repair only own blocker after complete failure checks")
   if failures:b.free();quit(1);return
   var repaired:Dictionary=b.handle({"type":"battle_close","battle_id":pending.battle_id})
   if failures:b.free();quit(1);return
   check(repaired.get("ok",false),"Original battle_close commits second real result")
   if failures:b.free();quit(1);return
  var entry:Dictionary=b.session._profile.quest_loot.entries[KEY]
  check(entry.budget_id==first.budget_id and entry.generation==first.generation and entry.saved_battles==2 and entry.issued_seq==first.issued_seq+1 and entry.settled_seq==entry.issued_seq and not entry.open_span and not b.battle_open and b.session._pending.is_empty() and b.field_calls==fields,"Two actual results same cumulative budget; no third open or attempt")
  if failures:b.free();quit(1);return
  if not archive_pair(b,"second_closed"):b.free();quit(1);return
  if not checked_complete_disk(b):b.free();quit(1);return
  var saved:Dictionary=b.session.snapshot();var saved_bytes:PackedByteArray=checked_bytes(b.save_path)
  if failures:b.free();quit(1);return
  var repeated:Dictionary=b.handle({"type":"battle_close","battle_id":receipt.ledger.battle_id})
  if failures:b.free();quit(1);return
  var repeated_bytes:PackedByteArray=checked_bytes(b.save_path)
  if failures:b.free();quit(1);return
  check(not repeated.get("ok",true) and b.session.snapshot()==saved and repeated_bytes==saved_bytes,"Repeated original second battle ID cannot count/reward twice")
  if failures:b.free();quit(1);return
  if not archive_pair(b,"repeated_close"):b.free();quit(1);return
  print("TWO BATTLE COMPLETE ",mode," saved_battles=2")
  b.free()
 print("TWO BATTLE DRIVER: 0 failures; one internal two-result169 fixture; no target-drop claim")
 quit(0)

func fresh_paths(path:String)->bool:
 for suffix in ["", ".bak", ".tmp", ".resume.json", ".resume.json.tmp", ".resume.json.bak", ".evidence"]:
  check(not FileAccess.file_exists(path+suffix) and not DirAccess.dir_exists_absolute(path+suffix),"New isolated user fixture refuses reused path: "+suffix)
  if failures:return false
 var error:int=DirAccess.make_dir_absolute(path+".evidence")
 check(error==OK,"Create own evidence directory")
 return failures==0
func read_disk(path:String)->Dictionary:
 var file=FileAccess.open(path,FileAccess.READ)
 var opened:int=FileAccess.get_open_error()
 if file==null:
  print("DISK_READ ",path," open_error=",opened)
  check(false,"Actual evidence file open failed");return {"ok":false}
 var declared:int=file.get_length()
 var length_error:int=file.get_error()
 if length_error!=OK:
  file.close();print("DISK_LENGTH ",path," error=",length_error," declared=",declared)
  check(false,"Actual evidence length query failed");return {"ok":false}
 var bytes:PackedByteArray=file.get_buffer(declared)
 var error:int=file.get_error();file.close()
 var context=HashingContext.new();var begun:int=context.start(HashingContext.HASH_SHA256)
 if begun!=OK:check(false,"SHA begin");return {"ok":false}
 var updated:int=context.update(bytes)
 if updated!=OK:check(false,"SHA update");return {"ok":false}
 var digest_bytes:PackedByteArray=context.finish()
 check(digest_bytes.size()==32,"SHA256 finish returns exactly32 bytes")
 if failures:return {"ok":false}
 var digest:String=digest_bytes.hex_encode()
 print("DISK_READ ",path," open=",opened," read=",error," declared=",declared," actual=",bytes.size()," sha256=",digest)
 check(opened==OK and error==OK and declared>0 and bytes.size()==declared,"Whole disk read has explicit valid length and no I/O error")
 if failures:return {"ok":false}
 return {"ok":true,"bytes":bytes,"sha256":digest,"declared":declared,"actual":bytes.size()}
func checked_bytes(path:String)->PackedByteArray:
 var result:Dictionary=read_disk(path)
 return result.bytes if result.get("ok",false) else PackedByteArray()
func archive_pair(b,stage:String)->bool:
 if failures:return false
 for suffix in ["", ".bak"]:
  var result:Dictionary=read_disk(b.save_path+suffix)
  if failures or not result.get("ok",false):return false
  var destination:String=b.save_path+".evidence/"+stage+(".primary" if suffix.is_empty() else ".backup")
  check(not FileAccess.file_exists(destination) and not DirAccess.dir_exists_absolute(destination),"Evidence phase cannot overwrite previous bytes")
  if failures:return false
  var output=FileAccess.open(destination,FileAccess.WRITE)
  if output==null:check(false,"Evidence write open error "+str(FileAccess.get_open_error()));return false
  output.store_buffer(result.bytes);output.flush()
  var error:int=output.get_error();output.close()
  check(error==OK,"Evidence flush status")
  if failures:return false
  var copied:Dictionary=read_disk(destination)
  if failures:return false
  check(copied.get("ok",false) and copied.bytes==result.bytes and copied.sha256==result.sha256,"Evidence copy exact bytes/SHA")
  if failures:return false
 print("ARCHIVED ",stage," blocker=",DirAccess.dir_exists_absolute(b.save_path+".tmp"))
 return true
func checked_complete_disk(b)->bool:
 var raw:Dictionary=read_disk(b.save_path)
 if failures:return false
 var copied:Dictionary=ProfileCompare.validated_copy(b.session,raw.bytes.get_string_from_utf8())
 check(copied.get("ok",false),"Whole stored profile validates before copy normalization")
 if failures:return false
 check(copied.profile==b.session.snapshot(),"Complete native/UID/ledger equals validated stored copy")
 return failures==0

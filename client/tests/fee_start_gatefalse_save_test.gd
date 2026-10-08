extends SceneTree
## UNRUN test-only proposal. Actual default-closed Backend.save; independent
## c9939efe contract oracle, no copied production implementation or fee token.
const Backend=preload("res://server/backend.gd")
class FaultSession extends "res://server/game_session.gd":
 var mode:=""
 var writes:=0
 func _write_profile_candidate(candidate:Dictionary,path:String)->bool:
  writes+=1
  if mode=="false_before":return false
  var actual:bool=super._write_profile_candidate(candidate,path)
  return false if mode=="false_after" else actual
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;push_error(label)
func raw(path:String)->Dictionary:
 if not FileAccess.file_exists(path):return {"exists":false,"bytes":PackedByteArray()}
 return {"exists":true,"bytes":FileAccess.get_file_as_bytes(path)}
func run()->void:
 for mode:String in ["empty_path","first_write","same_cache","changed","false_before","false_after"]:
  var b=Backend.new();b.set_process(false)
  var s=FaultSession.new();b.session=s
  s.battle_pets_hook=b._live_battle_pets;s.capture_entry_hook=b._capture_entry
  check(s._valid_profile(s.snapshot()),"normalized actual valid fixture")
  var before:Dictionary=s._profile.duplicate(true)
  var path:String="user://fee-gatefalse-save-%d-%s.json"%[Time.get_ticks_usec(),mode]
  b.save_path="" if mode=="empty_path" else path
  if mode not in ["empty_path","first_write"]:check(b.save(),"initial real save")
  if mode=="empty_path":b.last_saved_payload="sentinel-empty-path"
  var previous_cache:String=b.last_saved_payload
  b.quest_save_serial=41;s.writes=0
  var expected:Dictionary=before.duplicate(true)
  if mode in ["changed","false_before","false_after"]:
   expected.player.gold+=1;s._profile.player.gold+=1
  s.mode=mode
  var result:bool=b.save()
  var success:bool=mode not in ["false_before","false_after"]
  check(not b._fee_start_intent_enabled(),"real production gate false")
  check(result==success and b.quest_save_serial==(42 if success else 41),mode+": original bool and exact serial")
  var cache:String=previous_cache if mode=="empty_path" or not success else JSON.stringify(expected)
  check(b.last_saved_payload==cache and s._profile==expected,mode+": complete profile and cache, gold/UID only declared delta")
  check(s.writes==(0 if mode in ["empty_path","same_cache"] else 1),mode+": exact actual candidate writer count")
  var primary_exists:bool=mode!="empty_path"
  var primary:Dictionary=before if mode=="false_before" else expected
  check(raw(path)=={"exists":primary_exists,"bytes":JSON.stringify(primary).to_utf8_buffer() if primary_exists else PackedByteArray()},mode+": complete primary bytes")
  var backup_exists:bool=mode in ["changed","false_after"]
  check(raw(path+".bak")=={"exists":backup_exists,"bytes":JSON.stringify(before).to_utf8_buffer() if backup_exists else PackedByteArray()},mode+": complete backup bytes")
  check(raw(path+".tmp")=={"exists":false,"bytes":PackedByteArray()},mode+": tmp absent")
  check(b._fee_start_intent._frame.is_empty() and b._fee_start_intent._live.is_empty() and b._fee_start_intent._seen.is_empty(),mode+": save cannot create Start authority")
  b.free() # Deliberately retain all five physical fixtures; no disk for empty_path.
 print("FEE GATEFALSE SAVE SUMMARY: ",checks," checks, ",failures," failures; 6 backends, 0 loads, 0 Wait")
 quit(1 if failures else 0)

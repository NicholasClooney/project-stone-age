extends "res://tests/quest_auto_loot_admission_test.gd"
## Signed-ID contract only. WebSocketPeer is real but not connected/authenticated;
## production UI separately verifies OPEN server peer/scene/session ownership.
func run()->void:
 var peer:=WebSocketPeer.new()
 var signed_id:int=peer.get_instance_id()
 check(signed_id<0 and signed_id!=-1,"Actual RefCounted WebSocketPeer supplies a negative non-sentinel ID")
 if failures:quit(1);return
 for mode in ["negative_peer","disconnected","positive_internal"]:
  var b=ObservedBackend.new()
  if not setup(b,"user://loot-peer-"+mode+".json"):b.free();quit(1);return
  b.quest_auto.connection=signed_id if mode=="negative_peer" else -1 if mode=="disconnected" else 71
  var profile:Dictionary=b.session.snapshot();var disk:String=FileAccess.get_file_as_string(b.save_path);var cache:String=b.last_saved_payload
  var identity:Dictionary=b.quest_auto.identity.checkpoint();var commits:int=b.commits
  var result:Dictionary=b.quest_loot.admit_prepared_run(b)
  print("LOOT PEER CONTRACT ",mode," id=",b.quest_auto.connection," result=",result)
  if mode=="disconnected":
   check(not result.get("ok",true) and b.session.snapshot()==profile and FileAccess.get_file_as_string(b.save_path)==disk and b.last_saved_payload==cache and b.commits==commits and b.quest_auto.identity.checkpoint()==identity,"Exact -1 sentinel rejects before acquire/open or profile/cache/identity changes")
  else:
   check(result.get("ok",false) and b.session._profile.quest_loot.entries[KEY].open_span and b.commits==commits+2 and b.quest_auto.identity.checkpoint()==identity,"Non-sentinel internal binding follows unchanged source/CAS acquire plus open rules")
  if failures:b.free();quit(1);return
  b.free()
 print("QUEST AUTO LOOT PEER: 0 failures; 3 internal signed-ID fixtures")
 quit(0)

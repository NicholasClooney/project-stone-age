extends SceneTree
const Session=preload("res://server/game_session.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
func _initialize()->void:
 var s=Session.new();var path:="user://transmigration-history-logout.json"
 for id in [2771,2771,2772,2773,2774,2138]:Session.OriginalEquipment.add(s._profile,id)
 var before:Dictionary=s.snapshot();var kept:Dictionary=before.original_instances[-1].duplicate(true)
 check(s.save_game(path),"save all four original history proofs and duplicate")
 check(s.snapshot()==before,"saving and ordinary snapshots never simulate logout")
 var restored=Session.new()
 check(restored.load_game(path),"real character load applies reviewed logout list")
 var after:Dictionary=restored.snapshot()
 check(after.original_items==[2138] and after.original_instances==[kept],"all proof instances removed; ordinary meat UID preserved")
 check(after.next_original_uid==before.next_original_uid and after.player==before.player and after.rebirth==before.rebirth and after.original_events==before.original_events,"logout consumes no UID or character/history/flags")
 check(restored.save_game(path),"save cleaned profile")
 var again=Session.new()
 check(again.load_game(path) and again.snapshot()==after,"cleanup is idempotent on second real load")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 print("TRANSMIGRATION LOGOUT: %d failures"%failures);quit(1 if failures else 0)

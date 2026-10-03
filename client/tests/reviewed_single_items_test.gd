extends SceneTree
const Backend=preload("res://server/backend.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Session=preload("res://server/game_session.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func reward(b,id:int) -> Dictionary:
 # Exercise the real transaction/UID/save boundary; original source rows are
 # independently locked and imported by test_quest_single_items.py.
 return b.original_quests.transact(b,b.session._profile,{"event":-1,"actions":{"GetRandItem":str(id)},"texts":{}},"ACCEPT")
func run() -> void:
 var b=Backend.new()
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 var before:Dictionary=b.session.snapshot()
 check(reward(b,11814).ok and reward(b,11814).ok,"two single-instance material rewards succeed")
 var state:Dictionary=b.session.snapshot()
 check(Session.bag_slots(state)==Session.bag_slots(before)+2,"same source item consumes two independent bag slots")
 check(state.original_items.count(11814)==2 and int(state.original_instances[-1].uid)!=int(state.original_instances[-2].uid),"duplicate materials have separate stable UIDs")
 while Session.bag_slots(b.session._profile)<14:Equipment.add(b.session._profile,1238)
 check(reward(b,1238).ok and Session.bag_slots(b.session.snapshot())==15,"food reward occupies last available slot")
 before=b.session.snapshot()
 check(not reward(b,1238).ok and b.session.snapshot()==before,"full bag rejects without merging or advancing UID")
 Equipment.remove(b.session._profile,1238)
 before=b.session.snapshot();b.save_path="user://missing-single-item-review/save.json"
 check(not reward(b,11814).ok and b.session.snapshot()==before,"failed durable save rolls back material and UID")
 b.save_path="user://reviewed-single-items.json"
 check(reward(b,11814).ok,"same transaction can retry after save path recovery")
 state=b.session.snapshot()
 var copy=Backend.new()
 check(copy.load_profile(b.save_path),"saved profile accepted by Backend")
 check(copy.session.snapshot().original_instances==state.original_instances,"saved single-instance UIDs survive actual Backend reload")
 copy.free();b.free()
 print("REVIEWED SINGLE ITEMS: %d failures"%failures)
 quit(1 if failures else 0)

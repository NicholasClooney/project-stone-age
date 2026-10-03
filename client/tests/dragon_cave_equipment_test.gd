extends SceneTree
const Session=preload("res://server/game_session.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Effects=preload("res://scripts/original_item_effects.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func run()->void:
 var session=Session.new()
 for id in [2460,2505,2461,2462]:Equipment.add(session._profile,id)
 var spear:=int(session.snapshot().original_instances[0].uid)
 var flute:=int(session.snapshot().original_instances[1].uid)
 check(not session.equip_item("original:%d"%spear),"source spear level40 gate")
 session.gm_raise_level(-1,40)
 check(session.equip_item("original:%d"%spear) and session.equip_item("original:%d"%flute),"spear ARM and flute amulet coexist")
 check(session.equipment_mods()=={"attack":36,"defence":-14,"speed":-14,"charm":5},"exact ordinary source stat sum")
 check(not session.equip_item("original:%d"%int(session.snapshot().original_instances[2].uid)) and not session.equip_item("original:%d"%int(session.snapshot().original_instances[3].uid)),"dragon armor/clothes remain original dragon body item definitions remain unimplemented")
 check(session.snapshot().original_instances[0].durability==2500000 and session.snapshot().original_instances[1].durability==200000,"source durability values")
 var path:="user://dragon-cave-equipment.json"
 check(session.save_game(path),"source equipment persists")
 var restored=Session.new()
 check(restored.load_game(path) and restored.snapshot().original_equipment==session.snapshot().original_equipment and restored.equipment_mods()==session.equipment_mods(),"real save preserves UID slots and ordinary modifiers")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 print("DRAGON CAVE EQUIPMENT: %d failures"%failures);quit(1 if failures else 0)

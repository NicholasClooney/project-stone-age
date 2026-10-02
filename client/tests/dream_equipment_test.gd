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
 for id in [2605,2606,2604]:Equipment.add(session._profile,id)
 var hat:=int(session.snapshot().original_instances[0].uid)
 var harp:=int(session.snapshot().original_instances[1].uid)
 check(not session.equip_item("original:%d"%hat),"source hat level35 gate")
 session.gm_raise_level(-1,35)
 check(session.equip_item("original:%d"%hat) and session.equip_item("original:%d"%harp),"hat HEAD and harp amulet coexist")
 check(session.equipment_mods()=={"attack":2,"defence":4,"speed":3,"charm":5},"exact ordinary source stat sum")
 check(not session.equip_item("original:%d"%int(session.snapshot().original_instances[2].uid)),"dream armor/clothes remain metadata without BODY")
 check(session.snapshot().original_instances[0].durability==2500000 and session.snapshot().original_instances[1].durability==2500000,"source durability values")
 var path:="user://dream-cave-equipment.json"
 check(session.save_game(path),"source equipment persists")
 var restored=Session.new()
 check(restored.load_game(path) and restored.snapshot().original_equipment==session.snapshot().original_equipment and restored.equipment_mods()==session.equipment_mods(),"real save preserves UID slots and ordinary modifiers")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 print("DREAM EQUIPMENT: %d failures"%failures);quit(1 if failures else 0)

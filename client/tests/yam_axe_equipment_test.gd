extends SceneTree
## The two identically named source axes have different levels and durability.
const Session=preload("res://server/game_session.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Backend=preload("res://server/backend.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(value: bool, note: String) -> void:
	print(("PASS: " if value else "FAIL: ")+note)
	if not value:failures+=1
func run() -> void:
	var session=Session.new()
	session.gm_raise_level(-1,19)
	Equipment.add(session._profile,2416)
	Equipment.add(session._profile,2448)
	var first:=int(session.snapshot().original_instances[0].uid)
	var final_axe:=int(session.snapshot().original_instances[1].uid)
	check(not session.equip_item("original:%d" % first),"2416 requires original Lv20")
	check(session.gm_raise_level(-1,20) and session.equip_item("original:%d" % first),"temporary 2416 really equips at Lv20")
	check(session.equipment_mods()=={"attack":9,"defence":-3,"speed":-3,"charm":0},"2416 uses source numeric fields")
	check(int(session.snapshot().original_instances[0].durability)==0,"temporary axe has no durability wear")
	check(not session.equip_item("original:%d" % final_axe),"2448 requires Lv25 independently")
	check(session.gm_raise_level(-1,25) and session.equip_item("original:%d" % final_axe),"2448 replaces temporary axe in ARM")
	check(session.equipment_mods()=={"attack":35,"defence":-10,"speed":-10,"charm":0},"2448 exact reward mods")
	check(int(session.snapshot().original_instances[1].durability)==2500000,"2448 source durability")
	var path:="user://yam-axe-equipment.json"
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	check(session.save_game(path),"both original axes save")
	var restored=Session.new()
	check(restored.load_game(path) and restored.snapshot().original_instances==session.snapshot().original_instances and restored.snapshot().original_equipment==session.snapshot().original_equipment,"UID and worn reward survive save/load")
	var backend=Backend.new();root.add_child(backend)
	backend.session=restored
	restored.equip_item("original:%d" % first)
	var before: Dictionary=restored.snapshot()
	backend.save_path="user://missing-yam-parent/save.json"
	var result: Dictionary=backend.handle({"type":"quest_discard","item_id":2416,"instance_uid":first})
	check(not result.ok and restored.snapshot()==before,"failed save rolls back discarded worn temporary axe")
	backend.save_path=path
	result=backend.handle({"type":"quest_discard","item_id":2416,"instance_uid":first})
	check(result.ok and not restored.snapshot().original_items.has(2416) and int(restored.snapshot().original_equipment.arm)==0,"discard removes worn temporary axe and clears ARM")
	check(restored.snapshot().original_items==[2448],"discard keeps the distinct final reward")
	backend.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("YAM AXE EQUIPMENT: %d failures" % failures)
	quit(1 if failures else 0)

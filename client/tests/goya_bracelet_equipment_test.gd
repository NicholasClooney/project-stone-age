extends SceneTree
const Session=preload("res://server/game_session.gd")
const Equipment=preload("res://server/original_equipment.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(value: bool, note: String) -> void:
	print(("PASS: " if value else "FAIL: ")+note)
	if not value:failures+=1
func run() -> void:
	var s=Session.new()
	Equipment.add(s._profile,1206);Equipment.add(s._profile,1206)
	var uid:=int(s.snapshot().original_instances[0].uid)
	var spare:=int(s.snapshot().original_instances[1].uid)
	check(s.equip_item("original:%d" % uid),"red bracelet equips at starting level")
	check(s.equipment_mods()=={"attack":3,"defence":3,"speed":-3,"charm":2},"1206 numeric source wins over stale description")
	check(int(s.effective_player_stats().charm)==int(s.snapshot().player.charm)+2,"bracelet charm is derived without modifying base")
	check(not s.equip_item("original:%d" % spare),"second bracelet cannot occupy another decoration slot")
	check(int(s.snapshot().original_instances[0].durability)==2500000,"red bracelet source durability")
	var path:="user://goya-bracelet-equipment.json"
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	check(s.save_game(path),"bracelet equipped state saves")
	var restored=Session.new()
	check(restored.load_game(path) and restored.snapshot().original_equipment==s.snapshot().original_equipment and restored.snapshot().original_instances==s.snapshot().original_instances,"duplicate bracelet UIDs and wear survive roundtrip")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("GOYA BRACELET EQUIPMENT: %d failures" % failures)
	quit(1 if failures else 0)

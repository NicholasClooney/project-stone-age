extends "res://tests/original_wood_equipment_test.gd"
func run() -> void:
 var b=Backend.new();root.add_child(b)
 b.session._profile.inventory.club=1
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://equipment-save-missing/save.json"
 var result:Dictionary=b.handle({"type":"equip_item","item":"club"})
 check(not result.ok and result.reason=="save_failed" and b.session.snapshot()==before,"failed equipment save restores complete profile")
 b.save_path="user://equipment-save-atomic.json"
 result=b.handle({"type":"equip_item","item":"club"})
 var loaded=Session.new()
 check(result.ok and loaded.load_game(b.save_path) and loaded.snapshot().equipped,"successful equipment transaction persists worn state")
 b.queue_free();await process_frame
 remove_files("user://equipment-save-atomic.json")
 print("EQUIPMENT SAVE ATOMIC: %d failures"%failures)
 quit(1 if failures else 0)

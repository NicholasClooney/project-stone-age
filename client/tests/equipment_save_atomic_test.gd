extends "res://tests/original_wood_equipment_test.gd"
func run() -> void:
 var path:="user://equipment-save-atomic-%d.json"%OS.get_process_id()
 var b=Backend.new();root.add_child(b)
 b.session._profile.inventory.club=1
 b.save_path=path
 check(b.save(),"baseline unequipped profile persisted")
 var before:Dictionary=b.session.snapshot()
 # A directory at the exact .tmp file path deterministically blocks writing;
 # the previously committed save stays in place at the real test save path.
 DirAccess.make_dir_absolute(path+".tmp")
 var result:Dictionary=b.handle({"type":"equip_item","item":"club"})
 var loaded=Session.new()
 check(not result.ok and result.reason=="save_failed" and b.session.snapshot()==before,"failed equip restores complete profile")
 check(loaded.load_game(path) and not loaded.snapshot().equipped,"failed equip leaves prior disk save unequipped")
 DirAccess.remove_absolute(path+".tmp")
 result=b.handle({"type":"equip_item","item":"club"})
 check(result.ok and loaded.load_game(path) and loaded.snapshot().equipped,"successful equip persists worn state")
 before=b.session.snapshot()
 DirAccess.make_dir_absolute(path+".tmp")
 result=b.handle({"type":"equip_item","item":"club"})
 check(not result.ok and result.reason=="save_failed" and b.session.snapshot()==before,"failed unequip restores complete worn profile")
 check(loaded.load_game(path) and loaded.snapshot().equipped,"failed unequip leaves prior disk save worn")
 DirAccess.remove_absolute(path+".tmp")
 result=b.handle({"type":"equip_item","item":"club"})
 check(result.ok and loaded.load_game(path) and not loaded.snapshot().equipped,"successful unequip retry persists final state")
 b.queue_free();await process_frame
 remove_files(path)
 print("EQUIPMENT SAVE ATOMIC: %d failures"%failures)
 quit(1 if failures else 0)

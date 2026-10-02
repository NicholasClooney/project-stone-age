extends "res://tests/bonus_quest_transactions_test.gd"
const REWARD="sainasu/event/event13_1@1112:16:15"
const CLEAN="sainasu/event/event13_2@1100:86:99"
func setup():
 var b=Backend.new()
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-quest-supplements.json"))
 b.quest_catalog.npcs.append_array(fixture.npcs);b.quest_catalog.items.merge(fixture.items)
 b.quest_catalog.enabled_events.append_array([13,14])
 b.session.gm_raise_level(-1,30)
 return b
func prepare(b)->void:
 Rules.set_flag(b.session._profile,"now",13,true)
 for id in [2428,2429,2430,2431]:Session.OriginalEquipment.add(b.session._profile,id)
func run()->void:
 var b=setup();prepare(b)
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-supplement-parent/no-save.json"
 check(not trade(b,REWARD).ok and b.session.snapshot()==before,"reward save failure rolls back source items and both flags")
 b.save_path="user://saton-supplement.json"
 check(trade(b,REWARD).ok,"source reward plus authorized14 committed")
 check(Rules.flag(b.session.snapshot(),"ended",13) and Rules.flag(b.session.snapshot(),"ended",14),"13 and14 complete together")
 check(b.session.snapshot().original_items.count(2450)==1,"exact source reward once")
 var r:=talk(b,CLEAN)
 check(str(r.get("dialogue",{}).get("text","")).contains("14保留"),"explicit project confirmation preserves14 wording")
 before=b.session.snapshot()
 check(choose(b,r,"no").ok and b.session.snapshot()==before,"CLEAN cancel changes nothing")
 r=talk(b,CLEAN);b.save_path="user://missing-supplement-parent/no-save.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"CLEAN save failure rolls back13 and preserves14")
 b.save_path="user://saton-supplement.json"
 check(choose(b,talk(b,CLEAN),"yes").ok,"explicit confirmation clears source13")
 check(not Rules.flag(b.session.snapshot(),"ended",13) and Rules.flag(b.session.snapshot(),"ended",14),"only13 cleared, bonus14 retained")
 prepare(b)
 check(trade(b,REWARD).ok and b.session.snapshot().original_items.count(2450)==2,"user-approved repeat reward after source CLEAN")
 var loaded=Backend.new();loaded.save_path=b.save_path
 check(loaded.load_profile(b.save_path) and Rules.flag(loaded.session.snapshot(),"ended",14) and loaded.session.snapshot().original_items.count(2450)==2,"real save validation and reload retains supplemented progress")
 loaded.free();b.free()
 DirAccess.remove_absolute(ProjectSettings.globalize_path("user://saton-supplement.json"))
 print("ORIGINAL QUEST SUPPLEMENTS: %d failures"%failures)
 quit(1 if failures else 0)

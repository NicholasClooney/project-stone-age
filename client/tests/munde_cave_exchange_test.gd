extends "res://tests/yam_axe_quest_test.gd"
## Original exchanges only: gate/battle acquisition is a separate route test.
const KOLK="sainasu/event/event09@1200:97:75"
const HOTOR="sainasu/event/event10@1300:65:65"
const KATAN="sainasu/event/event11@1400:71:76"
const CHIEF="sainasu/event/event12@11107:24:6"
func setup():
 var b=Backend.new()
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/munde-cave-exchanges.json"))
 b.quest_catalog.npcs.append_array(fixture.npcs);b.quest_catalog.items.merge(fixture.items)
 b.quest_catalog.enabled_events.append_array([9,10,11,12])
 b.session.gm_raise_level(-1,30)
 return b
func talk(b,id:String)->Dictionary:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 var npc:Dictionary=b.original_quests.npc_by_id(id)
 # This exchange-only fixture places the player; route/navigation suites cover original access.
 b.automation.position_changed(int(npc.map_id),Vector2i(int(npc.cell[0]),int(npc.cell[1])))
 return b.handle({"type":"quest_talk","npc_id":id})
func run() -> void:
 var b=setup()
 check(b.original_quests.branch_for(b.original_quests.npc_by_id(KOLK),b.session.snapshot()).is_empty(),"LV30 without adult completion cannot request9")
 Rules.set_flag(b.session._profile,"ended",4,true) # Existing adult completion prerequisite.
 var r:=talk(b,KOLK)
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-munde-parent/save.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"request9 failed save changes no profile")
 b.save_path=""
 check(trade(b,KOLK).ok and Rules.flag(b.session.snapshot(),"now",9),"original Kolk request9")
 check(trade(b,KATAN).ok and trade(b,HOTOR).ok,"original two-village requests")
 check(Rules.flag(b.session.snapshot(),"now",10) and Rules.flag(b.session.snapshot(),"now",11),"both source subquests started")
 r=choose(b,talk(b,CHIEF),"yes");before=b.session.snapshot();b.save_path="user://missing-munde-parent/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"two-stone grant rolls back together")
 b.save_path=""
 check(trade(b,CHIEF).ok and b.session.snapshot().original_items==[2419,2420],"chief source gives both stones, not a fake battle drop")
 before=b.session.snapshot()
 talk(b,HOTOR)
 check(b.session.snapshot().original_items==before.original_items and not Rules.flag(b.session.snapshot(),"ended",10),"first completion cannot deliver Hotor stone before Katan")
 var charm:=int(b.session.snapshot().player.charm)
 r=choose(b,talk(b,KATAN),"yes");before=b.session.snapshot();b.save_path="user://missing-munde-parent/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"first stone and charm rollback on failed save")
 b.save_path=""
 check(trade(b,KATAN).ok and Rules.flag(b.session.snapshot(),"ended",11) and not Rules.flag(b.session.snapshot(),"ended",12),"Katan first grants1052 and END11 only")
 check(1052 in b.session.snapshot().original_items and int(b.session.snapshot().player.charm)==charm+1,"original Katan armour and one charm")
 r=choose(b,talk(b,HOTOR),"yes");before=b.session.snapshot();b.save_path="user://missing-munde-parent/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"second stone and completion12 rollback together")
 b.save_path=""
 check(trade(b,HOTOR).ok and Rules.flag(b.session.snapshot(),"ended",10) and Rules.flag(b.session.snapshot(),"ended",12),"Hotor second writes10 and12")
 check(2421 in b.session.snapshot().original_items and not Rules.flag(b.session.snapshot(),"ended",9),"magatama is not final Kolk completion")
 r=choose(b,talk(b,KOLK),"yes");before=b.session.snapshot();b.save_path="user://missing-munde-parent/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"final reward1357 rolls back with END9")
 b.save_path=""
 r=choose(b,talk(b,KOLK),"yes")
 check(choose(b,r,"ok").ok and Rules.flag(b.session.snapshot(),"ended",9) and b.session.snapshot().original_items.count(1357)==1,"only final Kolk return completes9 with1357")
 check(not choose(b,r,"ok").ok,"final reward token is single use")
 before=b.session.snapshot();talk(b,KOLK);talk(b,KATAN);talk(b,HOTOR);talk(b,CHIEF)
 check(b.session.snapshot().original_items==before.original_items and b.session.snapshot().original_events==before.original_events,"completed source exchanges neither reissue stones nor repeat rewards")
 b.free()
 print("MUNDE CAVE EXCHANGES: %d failures"%failures)
 quit(1 if failures else 0)

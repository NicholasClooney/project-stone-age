extends "res://tests/brothers_golden_quests_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Travel=preload("res://tests/support/water_route_driver.gd")
const Equipment=preload("res://server/original_equipment.gd")
func npc(b,script:String)->Dictionary:
 for n in b.quest_catalog.active_npcs():
  if str(n.get("source_script",str(n.id).split("@")[0]))==script:return n
 return {}
func run()->void:
 var b=fresh()
 check(Route.complete_adult(b).get("ok",false),"actual adult ritual prerequisite")
 # Public earlier requests and ordinary eye drop are explicit preexisting
 # fixtures; neither inventory nor these flags can establish cave arrival.
 for pair in [["now",29],["ended",30],["now",54]]:Rules.set_flag(b.session._profile,pair[0],pair[1],true)
 for item in [2549,2548]:Equipment.add(b.session._profile,item)
 var truth:Dictionary=npc(b,"genout/wpm_31910_8_9")
 var final:Dictionary=npc(b,"giiru/event/event30_6")
 b.automation.position_changed(31910,Vector2i(8,10))
 check(not Travel.commit(b,truth),"project arrival with real eye cannot launder truth gate")
 var entry:Dictionary={}
 for link in b.quest_helper.places.links(300).values():
  if int(link.to_map)==31901 and not link.get("disabled",false):entry=link;break
 check(not entry.is_empty(),"original golden cave public entrance")
 if entry.is_empty():b.free();quit(1);return
 b.automation.position_changed(300,Vector2i(int(entry.cell[0]),int(entry.cell[1])))
 check(b.handle({"type":"report_position","map_id":31901,"cell":entry.target}).ok,"real original quarry entrance")
 var key_gate:Dictionary=npc(b,"genout/wpm_31903_39_4")
 check(Travel.walk_near(b,key_gate,range(31901,31904)) and Travel.commit(b,key_gate),"real three-floor route and original key gate")
 var guide:Dictionary=npc(b,"giiru/event/event30_7")
 check(Travel.walk_near(b,guide,range(31904,31910)) and Travel.commit(b,guide),"original middle floors and source guide to truth room")
 check(not b.quest_arrival.check_action(b,final,final.branches[1],"reward").is_empty(),"guide Warp is not final truth-door proof")
 check(Travel.walk_near(b,truth,[31910]),"walk to actual correct eye door")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-golden-arrival/save.json"
 check(not Travel.commit(b,truth) and b.session.snapshot()==before,"failed truth gate preserves eye and no final qualification")
 b.save_path=""
 check(Travel.commit(b,truth) and 2548 not in b.session.snapshot().original_items,"saved original truth door consumes actual eye")
 check(Travel.walk_near(b,final,[31911]),"actual final chamber approach")
 check(Travel.commit(b,final) and Rules.flag(b.session.snapshot(),"ended",29) and 2551 in b.session.snapshot().original_items,"original spirit gift and END29 after truthful original route")
 b.quest_arrival.reset()
 check(not b.quest_arrival.check_action(b,final,final.branches[1],"reward").is_empty(),"restart cannot reuse truth chamber proof")
 b.free();print("QUEST ARRIVAL GOLDEN: %d failures"%failures);quit(1 if failures else 0)

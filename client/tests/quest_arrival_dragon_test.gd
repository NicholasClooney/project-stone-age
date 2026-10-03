extends "res://tests/brothers_golden_quests_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Travel=preload("res://tests/support/water_route_driver.gd")
const Equipment=preload("res://server/original_equipment.gd")
func run()->void:
 var b=fresh()
 var gate:Dictionary=Travel.npc(b,"genout/wpm_20807_11_37")
 var reward:Dictionary=Travel.npc(b,"jaruga/event/event17_1")
 # Inventory is an explicit preexisting fixture; it cannot establish arrival.
 for item in [2457,2458,2459,2505]:Equipment.add(b.session._profile,item)
 Rules.set_flag(b.session._profile,"now",17,true)
 b.automation.position_changed(20807,Vector2i(11,38))
 check(not Travel.commit(b,gate),"project placement with all three jewels cannot launder original gate")
 var entry:Dictionary={}
 for link in b.quest_helper.places.links(200).values():
  if int(link.to_map)==20801 and not link.get("disabled",false):entry=link;break
 check(not entry.is_empty(),"original public dragon entrance exists")
 if entry.is_empty():b.free();quit(1);return
 b.automation.position_changed(200,Vector2i(int(entry.cell[0]),int(entry.cell[1])))
 check(b.handle({"type":"report_position","map_id":20801,"cell":entry.target}).ok,"actual original portal starts dragon route")
 check(Travel.walk_near(b,gate,range(20801,20808)),"actual collision and portals cross seven original floors")
 check(not b.quest_arrival.check_action(b,reward,reward.branches[0],"reward").is_empty(),"before three-jewel gate reward has no room mark")
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-arrival-dragon/save.json"
 check(not Travel.commit(b,gate) and b.session.snapshot()==before,"failed gate save preserves profile and gives no arrival")
 check(not b.quest_arrival.check_action(b,reward,reward.branches[0],"reward").is_empty(),"failed save cannot authorize dragon reward")
 b.save_path=""
 check(Travel.commit(b,gate),"saved source three-jewel Warp establishes room mark")
 check(Travel.walk_near(b,reward,[20807]),"walk from actual gate Warp to original reward NPC")
 b.save_path="user://missing-arrival-dragon/save.json";before=b.session.snapshot()
 check(not Travel.commit(b,reward) and b.session.snapshot()==before,"failed final reward preserves jewels and flags")
 b.save_path=""
 check(Travel.commit(b,reward) and Rules.flag(b.session.snapshot(),"ended",17),"actual final transaction retries after save failure")
 b.quest_arrival.reset()
 check(not b.quest_arrival.check_action(b,reward,reward.branches[0],"reward").is_empty(),"restart loses arrival despite unchanged room and END17")
 b.free();print("QUEST ARRIVAL DRAGON: %d failures"%failures);quit(1 if failures else 0)

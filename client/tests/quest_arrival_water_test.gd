extends "res://tests/brothers_golden_quests_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Water=preload("res://tests/support/water_route_driver.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Policy=preload("res://server/quest_arrival_policy.gd")
func water_profile():
 var b=fresh();Water.install_fixture(b)
 # Isolated preexisting in-progress quest state, not arrival evidence.
 # Source request prerequisites are owned by water's complete-chain suite.
 Rules.set_flag(b.session._profile,"now",46,true)
 b.session._profile.player.gold=1000
 return b
func run()->void:
 var b=water_profile()
 for script in ["jaruga/event/hekisei01","jaruga/event/hekisei03","jaruga/event/hekisei04","jaruga/event/hekisei05","jaruga/event/hekisei06"]:
  var n: Dictionary=Water.npc(b,script)
  b.automation.position_changed(int(n.map_id),Vector2i(int(n.cell[0])+1,int(n.cell[1])))
  check(not b.handle({"type":"quest_talk","npc_id":n.id}).ok,"project placement cannot advance water terminal "+script)
 check(Policy.scope(3400).is_empty(),"public water request gets no invented cave arrival prerequisite")
 check(Route.complete_adult(b).get("ok",false),"actual adult entrance prerequisite before carrying lake materials")
 var before_gold: int=int(b.session.snapshot().player.gold)
 check(Water.lake(b,true),"actual free Folde portal and lake tunnel reach blue-water NPC")
 check(Water.commit(b,Water.npc(b,"jaruga/event/hekisei04")) and 2768 in b.session.snapshot().original_items and int(b.session.snapshot().player.gold)==before_gold,"free source entrance gives blue material without charging alternative door fee")
 # The wild green material is ordinary preexisting inventory here. It never
 # grants route; the actual material door and two guards are still required.
 Equipment.add(b.session._profile,2767)
 check(Water.cave(b,"genout/wpm_21308_20_10"),"real entrance, both fixed guards and reverse floors reach material door")
 var sage: Dictionary=Water.npc(b,"jaruga/event/hekisei03")
 check(not b.quest_arrival.check_action(b,sage,sage.branches[1],"reward").is_empty(),"standing before material door with both items is not sage qualification")
 var gate: Dictionary=Water.npc(b,"genout/wpm_21308_20_10")
 var before: Dictionary=b.session.snapshot()
 b.save_path="user://missing-water-arrival/save.json"
 check(not Water.commit(b,gate) and b.session.snapshot()==before,"material gate save failure does not commit profile")
 check(not b.quest_arrival.check_action(b,sage,sage.branches[1],"reward").is_empty(),"failed gate persistence grants no material-room mark")
 b.save_path=""
 check(Water.commit(b,gate) and Water.walk_near(b,sage,[21308]),"saved original material gate and real walking reach sage")
 check(Water.commit(b,sage) and 2769 in b.session.snapshot().original_items,"original approved OR synthesis runs only after actual material gate")
 var goddess: Dictionary=Water.npc(b,"jaruga/event/hekisei01")
 check(Water.walk_near(b,goddess,[21215]+range(21308,21316)),"original reverse floors return to goddess")
 check(Water.commit(b,goddess) and Rules.flag(b.session.snapshot(),"ended",46) and 2770 in b.session.snapshot().original_items,"actual original final exchange completes END46")
 b.free()
 b=water_profile();before_gold=int(b.session.snapshot().player.gold)
 check(Water.lake(b,false) and int(b.session.snapshot().player.gold)==before_gold-300,"alternative original 40 door charges300 and preserves lake route")
 check(Water.commit(b,Water.npc(b,"jaruga/event/hekisei04")) and 2768 in b.session.snapshot().original_items,"paid original entry also reaches real blue material reward")
 b.free();print("QUEST ARRIVAL WATER: %d failures"%failures);quit(1 if failures else 0)

extends "res://tests/brothers_golden_quests_test.gd"
const Travel=preload("res://tests/support/water_route_driver.gd")
const Equipment=preload("res://server/original_equipment.gd")
func run()->void:
 var b=fresh()
 Equipment.add(b.session._profile,2487);Rules.set_flag(b.session._profile,"now",20,true)
 var leader:Dictionary=Travel.npc(b,"jaruga/event/event20_4")
 b.automation.position_changed(20607,Vector2i(68,6))
 check(not Travel.commit(b,leader),"project placement cannot set END20")
 var entry:Dictionary={}
 for link in b.quest_helper.places.links(200).values():
  if int(link.to_map)==20601 and not link.get("disabled",false):entry=link;break
 check(not entry.is_empty(),"Jan original public entrance")
 if entry.is_empty():b.free();quit(1);return
 b.automation.position_changed(200,Vector2i(int(entry.cell[0]),int(entry.cell[1])))
 check(b.handle({"type":"report_position","map_id":20601,"cell":entry.target}).ok,"Jan actual root portal")
 for script in ["genout/wpm_20604_11_53","genout/wpm_20605_51_4","genout/wpm_20606_9_23"]:
  var gate:Dictionary=Travel.npc(b,script)
  check(Travel.walk_near(b,gate,range(20601,20608)),"real original route to keyword gate "+script)
  var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":gate.id})
  var answer:String=str(gate.branches[0].get("keyword",""))
  check(not answer.is_empty(),"actual pinned source keyword exists")
  check(b.handle({"type":"quest_choose","token":opened.get("dialogue",{}).get("token",""),"choice":"submit","text":answer}).ok,"real keyword Warp "+script)
 check(not b.quest_arrival.check_action(b,leader,leader.branches[0],"reward").is_empty(),"three passwords alone do not authorize final leader")
 check(Travel.guard(b,"200/sb_jan1.arg",[20607]),"real mandatory final battle and saved Warp")
 check(Travel.walk_near(b,leader,[20607]),"walk from actual victory Warp to leader")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-jan-arrival/save.json"
 check(not Travel.commit(b,leader) and b.session.snapshot()==before,"leader save failure grants no END20 and preserves preexisting item")
 b.save_path=""
 check(Travel.commit(b,leader) and Rules.flag(b.session.snapshot(),"ended",20),"actual leader transaction retries END20 after save failure")
 var daughter:Dictionary=Travel.npc(b,"jaruga/event/event20_6")
 check(Travel.walk_near(b,daughter,[20607,20608]) and Travel.commit(b,daughter) and Rules.flag(b.session.snapshot(),"now",21),"original interior portal retains final region for daughter REQUEST21")
 check(Travel.walk_near(b,leader,[20607,20608]) and Travel.commit(b,leader) and Rules.flag(b.session.snapshot(),"ended",22),"original return to leader earns END22")
 check(Travel.walk_near(b,daughter,[20607,20608]) and Travel.commit(b,daughter) and 2488 in b.session.snapshot().original_items,"original daughter letter branch")
 b.free();print("QUEST ARRIVAL JAN: %d failures"%failures);quit(1 if failures else 0)

extends "res://tests/brothers_golden_quests_test.gd"
const Travel=preload("res://tests/support/water_route_driver.gd")
func source_npc(b,script:String)->Dictionary:
 for n in b.quest_catalog.active_npcs():
  if str(n.get("source_script",str(n.id).split("@")[0]))==script:return n
 return {}
func run()->void:
 var b=fresh()
 # Empty pet slots are fixture capacity, not task flags or arrival evidence.
 b.session._profile.pets=[]
 var maps:Array=range(31701,31707)
 var reward:Dictionary=source_npc(b,"giiru/event/ev28_ed5")
 b.automation.position_changed(int(reward.map_id),Vector2i(int(reward.cell[0]),int(reward.cell[1])+1))
 check(not Travel.commit(b,reward),"project placement cannot choose original brother pet reward")
 var entry:Dictionary={}
 for link in b.quest_helper.places.links(300).values():
  if int(link.to_map)==31701 and not link.get("disabled",false):entry=link;break
 check(not entry.is_empty(),"original brothers public root exists")
 if entry.is_empty():b.free();quit(1);return
 b.automation.position_changed(300,Vector2i(int(entry.cell[0]),int(entry.cell[1])))
 check(b.handle({"type":"report_position","map_id":31701,"cell":entry.target}).ok,"real original cave entrance")
 var first:Dictionary=source_npc(b,"giiru/event/ev28_0")
 check(Travel.walk_near(b,first,maps) and Travel.commit(b,first) and Rules.flag(b.session.snapshot(),"now",28),"actual first-floor REQUEST28")
 for item in [2507,2509,2511,2513,2515]:
  var options:Array=b.quest_helper.candidates(b,28,"GetItem",item)
  check(not options.is_empty(),"original correct answer source exists")
  if options.is_empty():continue
  check(Travel.walk_near(b,options[0].npc,maps) and Travel.commit(b,options[0].npc) and item in b.session.snapshot().original_items,"actual floor path and answer paper "+str(item))
 var crystal:Dictionary=source_npc(b,"giiru/event/ev28_end")
 check(Travel.walk_near(b,crystal,maps) and Travel.commit(b,crystal) and Rules.flag(b.session.snapshot(),"ended",28),"source five-paper exchange before final guards")
 check(Travel.commit(b,crystal) and Rules.flag(b.session.snapshot(),"now",31),"source REQUEST31 remains before battle mark")
 var gate:Dictionary=source_npc(b,"genout/wpm_31705_25_8")
 check(Travel.walk_near(b,gate,maps) and Travel.commit(b,gate),"original crystal floor gate")
 check(not b.quest_arrival.check_action(b,reward,reward.branches[0],"reward").is_empty(),"floor gate alone cannot authorize pet reward")
 var guard:Dictionary=source_npc(b,"300/sb_5b5.arg")
 check(Travel.walk_near(b,guard,[31706]) and Travel.commit(b,guard) and b.battle_open,"actual chosen brother guard starts")
 fight(b)
 check(b.handle({"type":"battle_close"}).get("ok",false),"saved original victory Warp")
 check(Travel.walk_near(b,reward,[31706]),"original post-victory corridor and same-map portal reach reward hall")
 check(b.quest_arrival.check_action(b,reward,reward.branches[0],"reward").is_empty(),"original hall portal retains victory proof")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-brother-arrival/save.json"
 check(not Travel.commit(b,reward) and b.session.snapshot()==before,"pet save failure preserves crystal flags and UIDs")
 b.save_path=""
 check(Travel.commit(b,reward) and Rules.flag(b.session.snapshot(),"ended",31),"real pet reward commits after retry")
 b.free();print("QUEST ARRIVAL BROTHERS: %d failures"%failures);quit(1 if failures else 0)

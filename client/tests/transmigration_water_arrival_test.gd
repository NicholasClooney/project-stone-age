extends "res://tests/transmigration_water_test.gd"
const Policy=preload("res://server/quest_arrival_policy.gd")
func run()->void:
 for map_id in range(30301,30308):check(Policy.scope(map_id)=="water_stone","all seven stone floors share installed policy")
 check(Policy.script_root("genout/wpm_300_247_222",30301) and Policy.script_root("genout/wpm_300_182_162",30307),"both original stone gates remain legitimate")
 check(not Policy.portal_root(300,30301) and not Policy.portal_root(300,30307),"stone convenience portals cannot grant arrival")
 check(not Policy.scope(21201).is_empty() and Policy.scope(21201)==Policy.scope(21315),"water forward/backward caves use installed continuous arrival policy")
 check(Policy.portal_root(5000,31301) and Policy.script_root("genout/wpm_40_13_1",31301),"both original lake roots are legitimate")
 for free_entry in [true,false]:
  var b=setup();Rules.set_flag(b.session._profile,"now",46,true);b.session._profile.player.gold=300
  check(WaterRoute.lake(b,free_entry),"actual lake route from "+("Ford ordinary portal" if free_entry else "paid original gate"))
  var water:=source(b,"jaruga/event/hekisei04")
  var before_gold:int=b.session.snapshot().player.gold
  check(before_gold==(300 if free_entry else 0),"only chosen paid entrance consumes300")
  check(WaterRoute.commit(b,water) and Rules.item_count(b.session.snapshot(),2768)==1,"actual lake arrival authorizes original water item")
  b.save_path="user://water-arrival-reload.json"
  check(b.save(),"legitimate lake reward saves")
  var loaded=Backend.new()
  check(loaded.load_profile(b.save_path) and loaded.session.snapshot().original_instances==b.session.snapshot().original_instances,"lake reward reload preserves exact UIDs")
  check(not loaded.quest_arrival.has_arrival(loaded,int(water.map_id),b.automation.position_cell),"reload restores no lake arrival authority")
  loaded.free()

  b.free()
 for script in ["jaruga/event/hekisei01","jaruga/event/hekisei03","jaruga/event/hekisei04","jaruga/event/hekisei05","jaruga/event/hekisei06"]:
  var b=setup();Rules.set_flag(b.session._profile,"ended",4,true);Rules.set_flag(b.session._profile,"now",46,true)
  for id in [2766,2767,2768,2769]:grant(b,id)
  if script=="jaruga/event/hekisei03":b.handle({"type":"quest_discard","item_id":2769})
  if script=="jaruga/event/hekisei04":b.handle({"type":"quest_discard","item_id":2768})
  var npc:=source(b,script)
  check(b.handle({"type":"reviewed_hunt_travel","map_id":41,"area_id":416,"template_id":72}).ok,"actual authorized catch teleport remains available")
  b.automation.position_changed(int(npc.map_id),Vector2i(int(npc.cell[0])+1,int(npc.cell[1])))
  var before:Dictionary=b.session.snapshot()
  check(not b.handle({"type":"quest_talk","npc_id":npc.id}).ok,"catch/project position grants no original NPC transaction "+script)
  var branch:Dictionary=b.original_quests.branch_for(npc,before)
  check(not b.original_quests.transact(b,before,branch,"reward","",str(npc.id)).ok and b.session.snapshot()==before,"final transaction independently preserves flags and UIDs "+script)
  for mode in ["near","arrival"]:
   check(not b.handle({"type":"quest_visit","npc_id":npc.id,"mode":mode}).ok,"raw NPC helper cannot convert capture into arrival "+mode)
  b.free()
 var stone_backend=setup();Rules.set_flag(stone_backend.session._profile,"now",46,true)
 stone_backend.automation.position_changed(30305,Vector2i(50,52))
 for mode in ["near","arrival"]:
  check(not stone_backend.handle({"type":"quest_visit","step_id":"water46:stone","mode":mode}).ok,"project placement cannot authorize stone hunt helper "+mode)
 stone_backend.free()
 print("TRANSMIGRATION WATER ARRIVAL: %d failures"%failures);quit(1 if failures else 0)

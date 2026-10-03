extends "res://tests/brothers_golden_quests_test.gd"
var GATE:String
func run()->void:
 for route in [["genout/wpm_300_247_222@300:247:222",Vector2i(248,222),30301,Vector2i(23,37)],["genout/wpm_300_182_162@300:182:162",Vector2i(183,162),30307,Vector2i(10,6)]]:
  test_gate(route)
 print("ORIGINAL STONE ISLAND GATE: %d failures"%failures);quit(1 if failures else 0)
func test_gate(route:Array)->void:
 GATE=str(route[0])
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-water-source.json"))
 var gates:Array=fixture.npcs.filter(func(n):return str(n.id)==GATE)
 check(gates.size()==1,"one actual stone-island source create")
 for row in [[64,true,false],[65,false,false],[65,true,true]]:
  var b=fresh();b.session._profile.player.level=int(row[0]);Rules.set_flag(b.session._profile,"ended",4,bool(row[1]))
  b.quest_catalog.npcs=b.quest_catalog.npcs.filter(func(n):return str(n.id)!=GATE);b.quest_catalog.npcs.append_array(gates)
  b.quest_catalog.enabled_events.erase(46)
  check(not b.original_quests.npc_by_id(GATE).is_empty(),"original adult gate stays visible before water46 activation")
  b.automation.position_changed(300,route[1])
  var before:Dictionary=b.session.snapshot();var r:Dictionary=b.handle({"type":"quest_talk","npc_id":GATE})
  if not bool(row[2]):
   check(r.get("ok",false) and str(b.original_quests.pending.get("phase",""))=="end" and b.automation.position_map==300 and b.session.snapshot()==before,"exact original65+END4 condition refuses "+str(row))
  else:
   b.save_path="user://missing-stone-gate-parent/save.json"
   check(not choose(b,r,"yes").ok and b.automation.position_map==300 and b.session.snapshot()==before,"failed gate save cannot publish original Warp")
   b.save_path="";r=b.handle({"type":"quest_talk","npc_id":GATE})
   check(choose(b,r,"yes").ok and b.automation.position_map==int(route[2]) and b.automation.position_cell==route[3],"65 and adult enters exact original landing")
   check(b.session.snapshot().player.gold==before.player.gold and b.session.snapshot().original_events==before.original_events and b.session.snapshot().original_instances==before.original_instances,"original free gate adds no fee, item or task condition")
   check(not choose(b,r,"yes").ok,"stone gate token cannot replay")
  b.free()

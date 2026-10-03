extends "res://tests/original_fixed_guards_test.gd"
func run()->void:
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-fire-gate.json"))
 var npc:Dictionary=fixture.module.npcs[0]
 var b=fresh();b.quest_catalog.npcs=b.quest_catalog.npcs.filter(func(n):return str(n.id)!=str(npc.id));b.quest_catalog.npcs.append(npc)
 if not 40 in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(40)
 for flags in [[false,false,false],[true,false,false],[false,true,false],[false,false,true]]:
  Rules.set_flag(b.session._profile,"ended",4,flags[0]);Rules.set_flag(b.session._profile,"now",40,flags[1]);Rules.set_flag(b.session._profile,"ended",40,flags[2])
  var r:=source_talk(b,npc)
  check(b.original_quests.pending.get("phase","")=="end","original gate rejects missing adult or fire state "+str(flags))
 for ended in [false,true]:
  Rules.set_flag(b.session._profile,"ended",4,true);Rules.set_flag(b.session._profile,"now",40,not ended);Rules.set_flag(b.session._profile,"ended",40,ended)
  var r:=source_talk(b,npc);var before:Dictionary=b.session.snapshot();b.save_path="user://missing-fire-gate/fail.json"
  check(b.original_quests.pending.get("phase","")=="FREEWARP","both original OR branches permit gate")
  check(not choose(b,r,"yes").ok and b.session.snapshot()==before and b.automation.position_cell==Vector2i(200,39),"gate savefail cannot cross")
  b.save_path="";r=source_talk(b,npc)
  check(choose(b,r,"yes").ok and b.automation.position_cell==Vector2i(200,41),"source successful gate warp exact200,41")
  check(not choose(b,r,"yes").ok,"gate token replay denied")
 b.free()
 print("TRANSMIGRATION FIRE GATE: %d failures"%failures);quit(1 if failures else 0)

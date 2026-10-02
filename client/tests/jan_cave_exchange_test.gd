extends "res://tests/yam_axe_quest_test.gd"
## Source exchanges only; original guard/keyword/map acquisition has separate route coverage.
const FRIEND="jaruga/event/event20_1@3400:59:66"
const JIDE="jaruga/event/event20_2@3406:27:14"
const SON="jaruga/event/event20_3@3406:28:17"
const JAN="jaruga/event/event20_4@20607:68:5"
const WIFE="jaruga/event/event20_5@20607:71:7"
const SARAH="jaruga/event/event20_6@20608:9:3"
func setup():
 var b=Backend.new()
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/jan-cave-exchanges.json"))
 b.quest_catalog.npcs.append_array(fixture.npcs);b.quest_catalog.items.merge(fixture.items)
 b.quest_catalog.enabled_events.append_array([20,21,22])
 return b
func talk(b,id:String)->Dictionary:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 var npc:Dictionary=b.original_quests.npc_by_id(id)
 # Exchange fixture isolates original transactions; never claim this placement is a route.
 b.automation.position_changed(int(npc.map_id),Vector2i(int(npc.cell[0]),int(npc.cell[1])))
 return b.handle({"type":"quest_talk","npc_id":id})
func rollback_reward(b,id:String)->void:
 var r:=choose(b,talk(b,id),"yes")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-jan-parent/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"source ACCEPT reward rollback "+id)
 check(not choose(b,r,"ok").ok,"failed transaction token cannot replay")
 b.save_path=""
func run()->void:
 var b=setup()
 check(b.original_quests.branch_for(b.original_quests.npc_by_id(JIDE),b.session.snapshot()).is_empty(),"Jide requires original flower")
 rollback_reward(b,FRIEND)
 check(trade(b,FRIEND).ok and b.session.snapshot().original_items==[2486],"friend grants original flower")
 var r:=talk(b,JIDE);var before:Dictionary=b.session.snapshot();b.save_path="user://missing-jan-parent/save.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"request20 failed save preserves flower and flags")
 b.save_path=""
 check(trade(b,JIDE).ok and Rules.flag(b.session.snapshot(),"now",20) and not 2486 in b.session.snapshot().original_items,"source request consumes flower and writes NOW20")
 rollback_reward(b,SON)
 check(trade(b,SON).ok and b.session.snapshot().original_items==[2487],"son gives mother's ornament")
 rollback_reward(b,JAN)
 check(trade(b,JAN).ok and Rules.flag(b.session.snapshot(),"ended",20) and 2487 in b.session.snapshot().original_items,"Jan records20 without consuming ornament")
 before=b.session.snapshot();check(trade(b,WIFE).ok and b.session.snapshot().original_items==before.original_items,"wife's original story has no invented item reward")
 r=talk(b,SARAH);before=b.session.snapshot();b.save_path="user://missing-jan-parent/save.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"request21 failed save retains ornament")
 b.save_path=""
 check(trade(b,SARAH).ok and Rules.flag(b.session.snapshot(),"now",21) and not 2487 in b.session.snapshot().original_items,"Sarah consumes ornament and requests21")
 talk(b,SARAH)
 check(not 2488 in b.session.snapshot().original_items,"cannot receive letter before22")
 var before22:Dictionary=b.session.snapshot()
 var seen:Array=[]
 for value in range(32):
  b.session._profile=before22.duplicate(true)
  seed(value)
  check(trade(b,JAN).ok,"fixed seed executes original five-choice reward")
  var item:int=b.session.snapshot().original_items[0]
  if not item in seen:seen.append(item)
 seen.sort();check(seen==[2490,2491,2492,2493,2494],"all five source reward alternatives reachable")
 b.session._profile=before22.duplicate(true)
 while Session.bag_slots(b.session.snapshot())<15:Session.OriginalEquipment.add(b.session._profile,2486)
 before=b.session.snapshot()
 check(not trade(b,JAN).ok and b.session.snapshot()==before,"full bag cannot consume completion22 or create random reward")
 b.session._profile=before22.duplicate(true)
 rollback_reward(b,JAN)
 r=choose(b,talk(b,JAN),"yes")
 check(choose(b,r,"ok").ok and Rules.flag(b.session.snapshot(),"ended",22) and not Rules.flag(b.session.snapshot(),"ended",21),"equipment reward records22 before letter21")
 check(b.session.snapshot().original_items.size()==1 and b.session.snapshot().original_items[0] in [2490,2491,2492,2493,2494],"exactly one of the five original random rewards")
 check(not choose(b,r,"ok").ok,"random reward cannot replay")
 before=b.session.snapshot();talk(b,JAN)
 check(b.session.snapshot().original_items==before.original_items,"completed22 cannot issue a second random reward")
 rollback_reward(b,SARAH)
 check(trade(b,SARAH).ok and 2488 in b.session.snapshot().original_items,"original letter only after22")
 rollback_reward(b,JIDE)
 check(trade(b,JIDE).ok and Rules.flag(b.session.snapshot(),"ended",21) and 2489 in b.session.snapshot().original_items and not 2488 in b.session.snapshot().original_items,"Jide consumes letter and gives flute with21")
 before=b.session.snapshot();talk(b,JAN);talk(b,SARAH);talk(b,JIDE)
 check(b.session.snapshot().original_items==before.original_items and b.session.snapshot().original_events==before.original_events,"completed20/21/22 exchanges neither repeat nor enable161")
 check(not Rules.flag(b.session.snapshot(),"now",161) and not Rules.flag(b.session.snapshot(),"ended",47),"later chain161 and quiz47 excluded")
 check(b.session.save_game("user://jan-exchanges.json"),"exchange result persists")
 var loaded=Session.new();check(loaded.load_game("user://jan-exchanges.json") and loaded.snapshot().original_items==b.session.snapshot().original_items and loaded.snapshot().original_events==b.session.snapshot().original_events,"exchange save reload retains all three completion flags")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://jan-exchanges.json"+suffix))
 b.free()
 print("JAN CAVE EXCHANGES: %d failures"%failures)
 quit(1 if failures else 0)

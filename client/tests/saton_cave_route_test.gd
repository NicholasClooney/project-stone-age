extends "res://tests/original_fixed_guards_test.gd"
const ELDER="sainasu/event/event13_1@1112:16:15"
const YOUTH="sainasu/event/event13_2@1100:86:99"
var now:=1000
func source_talk(b,npc:Dictionary)->Dictionary:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 check(preload("res://tests/support/legacy_cave_route.gd").approach(b,npc).ok,"Saton fixture follows actual original portals and continuous path")
 return b.handle({"type":"quest_talk","npc_id":str(npc.id)})
func setup():
 var b=fresh();b.quest_catalog.enabled_events=[13,14];guards=[]
 b.original_quests.npc_state.clock=func():return now
 for npc in b.quest_catalog.active_npcs():
  if str(npc.get("source_script","")) in ["100/sb_nusu1.arg","100/sb_nusu2.arg","100/sb_nusu3.arg"]:guards.append(npc)
 return b
func run()->void:
 var b=setup()
 check(guards.size()==3,"three original bound Saton guards")
 var events:Array=b.quest_catalog.enabled_events.filter(func(e):return e in [13,14,47]);events.sort()
 check(events==[13,14],"exact original13 and authorized supplemental14, no47")
 check(trade(b,ELDER).ok and 2431 in b.session.snapshot().original_items,"actual request grants footprint")
 for i in range(guards.size()):
  var npc:Dictionary=guards[i]
  # Actual original route precedes every protected source dialogue.
  var r:=source_talk(b,npc)
  seed(100+i)
  check(choose(b,r,"yes").ok,"original guard starts with footprint")
  check(b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))==npc.branches[0].guard.enemy_ids.map(func(e):return int(e)),"exact original two-enemy troop")
  check(preload("res://server/troop_art.gd").can_render(b.session._pending.enemies),"every original guard/pet sprite available")
  var before:Dictionary=b.session.snapshot();b.save_path="user://missing-saton-route/save.json"
  fight(b)
  check(b.session.snapshot()==before and not b.original_quests.npc_by_id(npc.id).is_empty(),"failed settlement neither grants treasure nor hides guard")
  b.save_path=""
  check(b.handle({"type":"battle_close"}).ok,"pending same-result settlement retries")
  check(b.session.snapshot().original_items.count(2428+i)==1 and 2431 in b.session.snapshot().original_items,"source1000/1000 treasure once, no invented footprint theft")
  check(b.original_quests.npc_by_id(npc.id).is_empty(),"successful personal save hides guard")
  check(not choose(b,r,"yes").ok,"old source token cannot replay")
  var other=Backend.new()
  check(not other.original_quests.npc_by_id(npc.id).is_empty(),"other character guard remains available")
  other.free()
  now+=300;b.original_quests.refresh_npc_state()
  check(b.original_quests.npc_by_id(npc.id).is_empty(),"exact300 remains hidden")
  now+=1;b.original_quests.refresh_npc_state()
  check(not b.original_quests.npc_by_id(npc.id).is_empty(),"strict301 restores this character guard")
 check(trade(b,ELDER).ok,"real three treasures delivery")
 var done:Dictionary=b.session.snapshot()
 check(Rules.flag(done,"ended",13) and Rules.flag(done,"ended",14) and done.original_items.count(2450)==1,"original13 reward and authorized supplemental14")
 check([2428,2429,2430,2431].all(func(id):return not id in done.original_items),"all original required items consumed")
 check(b.session.save_game("user://saton-route.json"),"completed route saves")
 var loaded=Session.new();check(loaded.load_game("user://saton-route.json") and loaded.snapshot().original_events==done.original_events,"13 and14 survive reload")
 b.free()
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://saton-route.json"+suffix))
 print("SATON CAVE ROUTE: %d failures"%failures)
 quit(1 if failures else 0)

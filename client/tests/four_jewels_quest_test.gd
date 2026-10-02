extends "res://tests/marju_quest_test.gd"
const SCHOLAR="extra/event/hougyoku@6000:58:44"
const JewelHelper=preload("res://server/four_jewels_helper.gd")
func fight(b) -> void:
 for i in range(100):
  var state:Dictionary=b.battle.snapshot()
  if not state.active:return
  var target:=0
  for index in range(state.enemies.size()):
   if int(state.enemies[index].hp)>0:target=index;break
  b.handle({"type":"battle_command","action":"attack","target":target})
 check(not b.battle.snapshot().active,"actual source multi-enemy battle completes")
func prepare():
 var b=Backend.new()
 b.session.gm_raise_level(-1,60);clean_bag(b)
 for stat in ["vitality","strength","toughness","dexterity"]:check(b.session.gm_set_base_stat(-1,stat,500),"real GM combat setup for deterministic acceptance")
 check(b.session.gm_heal(-1),"real GM heal fills test combatant HP")
 return b
func collect(b,part:Dictionary,retry:bool=false) -> void:
 var target:=JewelHelper.hunting(b.quest_helper,b,part)
 check(not target.is_empty(),"original conditional area has navigable real cell")
 if target.is_empty():return
 var rng:=RandomNumberGenerator.new()
 var found:=false
 for seed_value in range(10000):
  rng.seed=seed_value
  var roll:Dictionary=b.encounter_catalog.roll(int(target.map_id),Vector2i(target.cell[0],target.cell[1]),rng,b.session.snapshot().original_items)
  if int(roll.get("group_id",-1))!=int(part.group):continue
  if not roll.enemies.any(func(e):return int(e.source_enemy_id)==int(part.enemy) and int(part.item) in e.generated_drops):continue
  b.encounter_rng.seed=seed_value;found=true;break
 check(found,"real weighted RNG seed gives audited source drop")
 if not found:return
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 var visit:Dictionary=b.handle({"type":"quest_visit","quest_id":31,"step_id":"jewels:hunt:%d"%int(part.item),"mode":"near"})
 check(visit.ok,"real helper command navigates to source area")
 var issued:Dictionary=b.wild_encounter(int(target.map_id),Vector2i(target.cell[0],target.cell[1]))
 check(issued.ok,"production Backend opens original conditional encounter")
 if not issued.ok:return
 check(b.session._pending.enemies.any(func(e):return int(e.source_enemy_id)==int(part.enemy)),"source quest enemy appears alongside source companions")
 check(b.session._pending.enemies.any(func(e):return int(e.source_enemy_id)==int(part.enemy) and int(part.item) in e.generated_drops),"authority retains exact pre-rolled source drop")
 var before:Dictionary=b.session.snapshot()
 if retry:b.save_path="user://missing-jewel-dir/save.json"
 fight(b)
 check(b.battle.snapshot().get("outcome")=="win","real battle victory required before claiming jewel")
 if retry:
  check(b.session.snapshot()==before and not b.session._pending.is_empty(),"failed settlement preserves all state and retains exact rolled loot")
  b.save_path=""
 check(b.handle({"type":"battle_close"}).ok,"source battle closes with saved drop")
 check(b.session.snapshot().original_items.count(int(part.item))==1,"exactly one earned source jewel")
 before=b.session.snapshot();b.handle({"type":"battle_close"})
 check(b.session.snapshot()==before,"repeated battle close cannot duplicate jewel")
 for i in range(80):
  var roll:Dictionary=b.encounter_catalog.roll(int(target.map_id),Vector2i(target.cell[0],target.cell[1]),rng,b.session.snapshot().original_items)
  if int(roll.get("group_id",-1))==int(part.group):check(false,"held jewel excludes its own source group");return
 check(true,"held jewel excludes original group")
func run() -> void:
 var b=prepare()
 var reward_step:Dictionary=b.quest_helper.resolve_step(b,31,"jewels:return")
 check(reward_step.get("reward_effects",[]).size()==1 and str(reward_step.get("effects_notice","")).contains("未生效"),"actual helper exposes source bracelet magic limitation")
 for reward in reward_step.get("reward_effects",[]):
  check(reward.effects.filter(func(e):return e.type=="stat").all(func(e):return bool(e.active)),"helper bracelet ordinary stats remain active")
 check(45 in b.quest_catalog.enabled_events and not b.original_quests.npc_by_id(SCHOLAR).is_empty(),"actual bound scholar active")
 var base=Backend.new();base.session.gm_raise_level(-1,59);clean_bag(base)
 trade(base,SCHOLAR)
 check(not 2764 in base.session.snapshot().original_items,"59 cannot receive source crystal")
 base.free()
 check(trade(b,SCHOLAR).ok and 2764 in b.session.snapshot().original_items and not Rules.flag(b.session.snapshot(),"ended",45),"60 receives crystal but no completion")
 for part in JewelHelper.PARTS:
  var target:=JewelHelper.hunting(b.quest_helper,b,part)
  var rng:=RandomNumberGenerator.new()
  var excluded:=true
  for i in range(50):
   var r:Dictionary=b.encounter_catalog.roll(int(target.map_id),Vector2i(target.cell[0],target.cell[1]),rng,[])
   excluded=excluded and int(r.get("group_id",-1))!=int(part.group)
  check(excluded,"without crystal conditional group is excluded")
  collect(b,part,int(part.item)==2760)
 # Exercise coexistence with a real independent area birth, never an injected record.
 if 35 in b.quest_catalog.enabled_events:
  check(await Wait.until(self,func():return not b.original_quests.npc_by_id("seimu/event/event02_1@100:230:180:area:525:200").is_empty()),"registered Katan actually births before scholar rollback")
 var r:=choose(b,talk(b,SCHOLAR),"yes")
 var scholar_before:Dictionary=b.original_quests.npc_by_id(SCHOLAR).duplicate(true)
 var record_existed:bool=b.original_quests.npc_state.records.has(SCHOLAR)
 var record_before:Dictionary=b.original_quests.npc_state.records.get(SCHOLAR,{}).duplicate(true)
 print("NPC records before failed scholar reward: ",b.original_quests.npc_state.records.keys())
 check(not record_existed and int(scholar_before.map_id)==6000 and scholar_before.cell.map(func(value):return int(value))==[58,44],"first scholar reward starts at original location with no move counter")
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-jewel-dir/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"five source items and reward rollback together")
 var scholar_after:Dictionary=b.original_quests.npc_by_id(SCHOLAR)
 var record_after:Dictionary=b.original_quests.npc_state.records.get(SCHOLAR,{})
 print("NPC records after failed scholar reward: ",b.original_quests.npc_state.records.keys())
 check(b.original_quests.npc_state.records.has(SCHOLAR)==record_existed and record_after==record_before,"failed reward preserves scholar record existence and every runtime field")
 check(int(scholar_after.map_id)==int(scholar_before.map_id) and scholar_after.cell==scholar_before.cell and int(record_after.get("counter",-1))==int(record_before.get("counter",-1)),"failed reward leaves exact scholar position and counter unchanged")
 b.save_path="user://four-jewels.json"
 r=choose(b,talk(b,SCHOLAR),"yes")
 check(choose(b,r,"ok").ok,"five genuinely earned items exchange")
 check(b.session.snapshot().original_items==[2765] and Rules.flag(b.session.snapshot(),"ended",45),"one source bracelet and END45")
 var moved:Dictionary=b.original_quests.npc_by_id(SCHOLAR)
 check(int(moved.map_id)==4000 and moved.cell==[53,101],"successful reward selects first original personal move")
 var committed_record:Dictionary=b.original_quests.npc_state.records[SCHOLAR].duplicate(true)
 check(committed_record=={"map_id":4000,"cell":[53,101],"counter":1},"successful original move advances scholar counter exactly once")
 check(not choose(b,r,"ok").ok,"final token cannot replay")
 check(b.original_quests.npc_state.records[SCHOLAR]==committed_record,"replayed token cannot move scholar or advance counter")
 before=b.session.snapshot();trade(b,SCHOLAR)
 check(b.session.snapshot().original_items==before.original_items,"completed source branch cannot reward again")
 check(b.original_quests.npc_state.records[SCHOLAR]==committed_record,"completed conversation preserves committed scholar location and counter")
 var reload=Backend.new()
 check(reload.load_profile(b.save_path) and Rules.flag(reload.session.snapshot(),"ended",45),"source completion reloads")
 check(int(reload.original_quests.npc_by_id(SCHOLAR).map_id)==6000,"restart resets NPC memory position only")
 reload.free()
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(b.save_path+suffix))
 b.free()
 await lan_jewels()
 print("FOUR JEWELS QUEST: %d failures"%failures)
 quit(1 if failures else 0)

func lan_jewels() -> void:
 var b=prepare();root.add_child(b)
 check(trade(b,SCHOLAR).ok,"LAN crystal accepted through real source")
 for part in JewelHelper.PARTS:collect(b,part)
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"LAN ephemeral server")
 var links:Array=[];var states:Array=[];var pollers:Array=[]
 for i in range(2):
  var link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
  var state=preload("res://network/client_state.gd").new()
  link.message.connect(state.apply)
  var poller:Callable=func():link.poll(0.016)
  process_frame.connect(poller);links.append(link);states.append(state);pollers.append(poller);link.connect_now()
  check(await Wait.until(self,func():return link.online and not state.profile.is_empty()),"remote profile connects")
  await rpc(link,{"type":"ping"})
 check(links.all(func(l):return l.backend==null),"two remote clients have no backend")
 await rpc(links[0],{"type":"quest_visit","npc_id":SCHOLAR,"mode":"near"})
 var a:Dictionary=await rpc(links[0],{"type":"quest_talk","npc_id":SCHOLAR})
 a=await rpc(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes"})
 await rpc(links[0],{"type":"ping"})
 var other:Dictionary=await rpc(links[1],{"type":"quest_talk","npc_id":SCHOLAR})
 var stale:Dictionary=await rpc(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"ok"})
 check(not stale.ok and not Rules.flag(b.session.snapshot(),"ended",45),"second socket invalidates first reward token")
 other=await rpc(links[1],{"type":"quest_choose","token":other.dialogue.token,"choice":"yes"})
 var done:Dictionary=await rpc(links[1],{"type":"quest_choose","token":other.dialogue.token,"choice":"ok"})
 check(done.ok,"second socket commits one source bracelet")
 for link in links:await rpc(link,{"type":"ping"})
 check(states.all(func(s):return Rules.flag(s.profile,"ended",45) and s.profile.original_items==[2765]),"both devices see same completed chain and one bracelet")
 check(states[0].profile.original_items==states[1].profile.original_items,"both devices see identical original bracelet")
 check(states.all(func(s):return int(s.derived.quest_npcs[SCHOLAR].map_id)==4000),"both sockets receive source personal scholar move")
 var other_character=Backend.new()
 check(int(other_character.original_quests.npc_by_id(SCHOLAR).map_id)==6000,"another character retains original scholar location")
 other_character.free()
 for i in range(2):links[i].close();process_frame.disconnect(pollers[i])
 server.stop();server.queue_free();b.queue_free();await process_frame

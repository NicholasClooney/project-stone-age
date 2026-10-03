extends "res://tests/original_fixed_guards_test.gd"
const LEADER="giiru/event/giruev2_1@31805:19:21"
const RIVAL="giiru/event/giruev2_2@31805:33:23"
const GUARD="300/sb_bac.arg@31805:26:23"
const GATE="genout/wpm_31805_22_4@31805:22:4"
func fresh():
 var b=super.fresh();b.quest_catalog.enabled_events=[27]
 return b
func talk(b,id:String)->Dictionary:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 var npc:Dictionary=b.original_quests.npc_by_id(id)
 if npc.is_empty():return {"ok":false}
 check(preload("res://tests/support/legacy_cave_route.gd").approach(b,npc).ok,"miner fixture follows actual original cave route")
 return b.handle({"type":"quest_talk","npc_id":id})
func save_failure(b,id:String,note:String)->void:
 var opened:=talk(b,id)
 var accept:bool=str(b.original_quests.pending.get("phase",""))=="ACCEPT"
 var thanks:=choose(b,opened,"yes") if accept else opened
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://miner-no-parent/save.json"
 check(not choose(b,thanks,"ok" if accept else "yes").ok and b.session.snapshot()==before,note)
 b.save_path=""
func mine(b)->void:
 var rng:=RandomNumberGenerator.new();rng.seed=27
 var area:Dictionary=b.encounter_catalog.area_at(31801,Vector2i(37,48))
 check(not area.is_empty(),"original first-floor encounter area exists")
 check(b.encounter_catalog.roll_group(area,508,rng,[]).is_empty(),"without source permit no ore group")
 var troop:Dictionary=b.encounter_catalog.roll_group(area,508,rng,b.session.snapshot().original_items)
 check(troop.get("enemies",[]).any(func(e):return int(e.source_enemy_id)==1043 and e.generated_drops==[2534]),"original group508 contains real guaranteed ore drop")

 # Seed27 includes the original ore's negative growth component; retain it
 # to exercise the source-bounded noncapturable NPC compatibility.
 check(preload("res://server/troop_art.gd").can_render(troop.enemies),"source seed27 troop has complete imported battle art")
 var config:Dictionary=b.session.start_wild_battle_config(troop)
 check(not config.is_empty(),"real Session accepts source mining troop")
 if config.is_empty():return
 b.open_battle(config)
 var before:Dictionary=b.session.snapshot();b.save_path="user://miner-no-parent/save.json"
 fight(b)
 check(b.session.snapshot()==before,"mining settlement save failure is atomic")
 b.save_path=""
 check(b.handle({"type":"battle_close"}).ok and b.session.snapshot().original_items.count(2534)==1,"same mining result retries exactly one ore")
 before=b.session.snapshot();b.handle({"type":"battle_close"})
 check(b.session.snapshot()==before,"mining close replay cannot duplicate ore")
func run()->void:
 var b=fresh()
 check(27 in b.quest_catalog.enabled_events,"registered END27")
 if b.original_quests.npc_by_id(LEADER).is_empty():check(false,"real imported miner content missing");b.free();quit(1);return
 var now:=[1000];b.original_quests.npc_state.clock=func():return now[0]
 var low=Backend.new();low.quest_catalog.enabled_events=[27]
 check(not trade(low,LEADER).get("dialogue",{}).has("actions") and not Rules.flag(low.session.snapshot(),"now",27),"below30 cannot acquire NOW27")
 low.free()
 save_failure(b,LEADER,"failed request does not write NOW27")
 check(trade(b,LEADER).ok and Rules.flag(b.session.snapshot(),"now",27),"real leader request starts27")
 save_failure(b,RIVAL,"failed permit save gives no item")
 check(trade(b,RIVAL).ok and 2536 in b.session.snapshot().original_items,"real rival gives mining permit")
 check(not choose(b,talk(b,GUARD),"yes").ok and not b.battle_open,"mining permit is not competition qualification")
 mine(b)
 natural_mining()
 save_failure(b,RIVAL,"failed qualification retains ore and mining permit")
 check(trade(b,RIVAL).ok and 2535 in b.session.snapshot().original_items and not 2534 in b.session.snapshot().original_items and not 2536 in b.session.snapshot().original_items,"original qualification consumes both source objects")
 check(choose(b,talk(b,GUARD),"yes").ok and b.battle_open,"real fixed contest starts")
 if not b.battle_open:b.free();quit(1);return
 check(b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))==[1004],"contest exact original enemy1004")
 var before:Dictionary=b.session.snapshot();b.save_path="user://miner-no-parent/save.json"
 fight(b)
 check(b.session.snapshot()==before and not b.original_quests.npc_by_id(GUARD).is_empty(),"failed contest save preserves permit and visible NPC")
 b.save_path=""
 check(b.handle({"type":"battle_close"}).ok and 2533 in b.session.snapshot().original_items and not 2535 in b.session.snapshot().original_items,"contest retry commits original reward and consumes qualification")
 check(b.original_quests.npc_by_id(GUARD).is_empty(),"successful saved victory hides only personal guard")
 save_failure(b,LEADER,"failed END27 save retains won mining rights")
 var thanks:=choose(b,talk(b,LEADER),"yes")
 check(choose(b,thanks,"ok").ok and Rules.flag(b.session.snapshot(),"ended",27) and b.session.snapshot().original_items.count(2527)==1,"actual final trade writes END27 and one upper-floor ticket")
 check(not choose(b,thanks,"ok").ok,"final reward token single-use")
 if not b.original_quests.npc_by_id(GATE).is_empty():
  save_failure(b,GATE,"failed gate save preserves ticket and location")
  check(trade(b,GATE).ok and b.automation.position_map==31806 and not 2527 in b.session.snapshot().original_items,"original gate consumes exactly one ticket and warps")
  check(not trade(b,GATE).ok or b.automation.position_map!=31806,"no-ticket entry is rejected")
 else:check(false,"original ticket gate must be imported")
 b.session._profile.player.gold=999
 var balance:int=b.session.snapshot().player.gold
 check(not trade(b,LEADER).ok and b.session.snapshot().player.gold==balance and not 2527 in b.session.snapshot().original_items,"insufficient1000 does not issue ticket")
 b.session._profile.player.gold=2000
 save_failure(b,LEADER,"failed paid ticket is atomic")
 check(trade(b,LEADER).ok and int(b.session.snapshot().player.gold)==1000 and b.session.snapshot().original_items.count(2527)==1,"original replacement costs exactly1000")
 now[0]+=300;b.original_quests.refresh_npc_state()
 check(b.original_quests.npc_by_id(GUARD).is_empty(),"exact300 remains hidden")
 now[0]+=1;b.original_quests.refresh_npc_state()
 check(not b.original_quests.npc_by_id(GUARD).is_empty(),"greater300 respawns personal guard")
 var path:="user://miner-contest-earned.json";check(b.session.save_game(path),"real earned profile saved")
 var restored=Session.new()
 check(restored.load_game(path) and Rules.flag(restored.snapshot(),"ended",27) and restored.snapshot().original_items==b.session.snapshot().original_items,"save reload retains actual END27 and ticket")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 b.free()
 await miner_lan()
 print("MINER CONTEST: %d failures"%failures);quit(1 if failures else 0)
func miner_lan()->void:
 var b=fresh();root.add_child(b)
 check(trade(b,LEADER).ok and trade(b,RIVAL).ok,"LAN actual request and mining permit")
 mine(b)
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"miner LAN port0")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two real miner sockets")
 check(preload("res://tests/support/legacy_cave_route.gd").approach(b,b.original_quests.npc_by_id(RIVAL)).ok,"LAN qualification stays on actual original route")
 var a:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":RIVAL})
 a=await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes"})
 await request(links[0],{"type":"ping"})
 var c:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":RIVAL})
 check(not (await request(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"ok"})).ok,"second device invalidates old qualification token")
 c=await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"yes"})
 check((await request(links[1],{"type":"quest_choose","token":c.dialogue.token,"choice":"ok"})).ok,"second device commits source qualification")
 check(not (await request(links[0],{"type":"quest_choose","token":c.dialogue.token,"choice":"ok"})).ok and b.session.snapshot().original_items.count(2535)==1 and not 2534 in b.session.snapshot().original_items,"LAN replay cannot clone qualification")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free();await process_frame

func natural_mining()->void:
 var b=fresh()
 check(trade(b,LEADER).ok and trade(b,RIVAL).ok,"natural route earns original mining permit")
 check(preload("res://tests/support/original_route_driver.gd").walk(b,31801,Vector2i(37,48),range(31801,31806)).ok,"natural mining actually walks back down to original first-floor point")
 # Exercise the actual random-group + art gate, not only roll_group/Session.
 b.encounter_rng.seed=27
 var found:=false
 for attempt in range(100):
  var result:Dictionary=b.wild_encounter(31801,Vector2i(37,48))
  check(result.ok,"natural original encounter passes data/art/Session gates")
  if not result.ok:b.free();return
  found=result.troop.enemies.any(func(e):return int(e.source_enemy_id)==1043)
  fight(b);b.handle({"type":"battle_close"})
  if found:break
 check(found and b.session.snapshot().original_items.count(2534)>=1,"seed27 natural weighted encounters reach original ore and settle")
 b.free()

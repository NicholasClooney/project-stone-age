extends SceneTree
## Real source branches on real Backend/Session; fixture data is never activated.
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Server=preload("res://server/ws_server.gd")
const Link=preload("res://network/ws_link.gd")
const Wait=preload("res://tests/support/wait.gd")
const SHARK="seimu/event/event02_1"
const MINER="giiru/event/giruev2_1"
var failures:=0
var links:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func setup():
 var b=Backend.new()
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/bonus-quest-transactions.json"))
 b.quest_catalog.npcs.append_array(fixture.npcs)
 b.quest_catalog.items.merge(fixture.items)
 b.quest_catalog.reward_pets.merge(fixture.reward_pets)
 b.quest_catalog.enabled_events.append_array([35,27])
 b.session.gm_raise_level(-1,80)
 b.session._profile.pets=[];b.session._profile.active_pet=-1;b.session._profile.ride_pet=-1
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 return b
func place(b,id:String) -> void:
 var npc:Dictionary=b.original_quests.npc_by_id(id)
 if int(npc.map_id) in range(31801,31807):
  check(preload("res://tests/support/legacy_cave_route.gd").approach(b,npc).get("ok",false),"fee fixture follows original miner entrance and five floors")
 else:b.automation.position_changed(int(npc.map_id),Vector2i(int(npc.cell[0]),int(npc.cell[1])))
func talk(b,id:String) -> Dictionary:
 place(b,id)
 return b.handle({"type":"quest_talk","npc_id":id})
func choose(b,r:Dictionary,choice:String) -> Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":choice})
func trade(b,id:String) -> Dictionary:
 var r:=choose(b,talk(b,id),"yes")
 return choose(b,r,"ok") if r.has("dialogue") else r
func add(b,species:int,level:int=25) -> String:
 check(b.session.gm_grant_pet(species),"real original pet birth %d"%species)
 var uid:String=b.session._profile.pets[-1].pet_id
 check(b.session.level_pet_to(uid,level),"real original pet growth")
 return uid
func run() -> void:
 pets()
 fees()
 level_fees()
 await lan()
 print("BONUS QUEST TRANSACTIONS: %d failures"%failures)
 quit(1 if failures else 0)
func pets() -> void:
 var b=setup()
 check(trade(b,SHARK).ok and Rules.flag(b.session.snapshot(),"now",35),"original REQUEST35")
 var a:=add(b,223,24);var c:=add(b,224,26)
 check(not Rules.matches(b.session.snapshot(),"PET=25-223*1&PET=25-224*1"),"24 and 26 are not exact25")
 b.session.level_pet_to(a,25)
 # Rebuild this fixture pet through real progression rather than keep forged stats.
 b.session._profile.pets.remove_at(1);c=add(b,224)
 b.session._profile.pets[1].original_end_event=1
 check(not Rules.matches(b.session.snapshot(),"PET=25-223*1&PET=25-224*1"),"event provenance pet rejected")
 b.session._profile.pets[1].original_end_event=0
 check(not Rules.matches(b.session.snapshot(),"PET=25-223*1&PET=25-223*1"),"one UID cannot satisfy two predicates")
 var spare:=add(b,223)
 var replacement:=add(b,224)
 var r:=choose(b,talk(b,SHARK),"yes")
 b.session._profile.pets[1].original_end_event=1
 var before:Dictionary=b.session.snapshot()
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"bound second UID cannot silently switch to spare")
 b.session._profile.pets[1].original_end_event=0
 b.session._profile.active_pet=1;b.session._profile.ride_pet=3
 b.session._profile.automation_settings={"capture":{"pet":3,"pet_id":replacement}}
 b.automation.settings.capture_pet=3;b.automation.settings.capture_pet_id=replacement
 b.automation.training_pet_id=a
 r=choose(b,talk(b,SHARK),"yes")
 before=b.session.snapshot();b.save_path="user://blocked-bonus-parent/child.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"failed save restores both pets and all indexes")
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"failed transaction token cannot repeat")
 b.save_path=""
 check(trade(b,SHARK).ok,"exact25 first pair commits")
 var state:Dictionary=b.session.snapshot()
 check(state.pets.map(func(p):return str(p.pet_id))==[spare,replacement] and state.original_items==[2607],"two source UIDs consumed, spare pair kept, original proof")
 check(state.active_pet==-1 and state.ride_pet==1 and state.automation_settings.capture.pet==1 and state.automation_settings.capture.pet_id==replacement,"surviving ride/capture slots rebase by two")
 check(b.automation.training_pet_id=="" and b.automation.settings.capture_pet==1,"automation references update only after commit")
 add(b,221);add(b,222)
 for i in range(Session.PET_CAPACITY-b.session._profile.pets.size()):add(b,173,1)
 r=choose(b,talk(b,SHARK),"yes")
 before=b.session.snapshot();b.save_path="user://blocked-bonus-parent/child.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"second pair save failure restores proof/UID counter/full roster")
 b.save_path="user://bonus-pet-roundtrip.json"
 check(trade(b,SHARK).ok,"full roster permits net two-for-one reward")
 state=b.session.snapshot()
 check(state.pets.size()==Session.PET_CAPACITY-1 and state.pets[-1].source_enemy_id==93 and state.pets[-1].level==1 and Rules.flag(state,"ended",35) and not 2607 in state.original_items,"exact original reward93 and END35 together")
 var loaded=Session.new()
 var loaded_ok:bool=loaded.load_game(b.save_path)
 check(loaded_ok and JSON.parse_string(JSON.stringify(loaded.snapshot().pets))==JSON.parse_string(JSON.stringify(state.pets)) and loaded.snapshot().next_pet_id==state.next_pet_id,"reward and monotonic UID persist on reload")
 var count:int=state.pets.size();trade(b,SHARK)
 check(b.session.snapshot().pets.size()==count,"finished event35 cannot reward again")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(b.save_path+suffix)
 b.free()
func fees() -> void:
 var b=setup();Rules.set_flag(b.session._profile,"ended",27,true)
 b.session._profile.player.gold=999
 place(b,MINER)
 var before:Dictionary=b.session.snapshot()
 check(not trade(b,MINER).ok and b.session.snapshot()==before,"original fee1000 rejects999 without ticket")
 b.session._profile.player.gold=1000
 before=b.session.snapshot();b.save_path="user://blocked-bonus-parent/child.json"
 check(not trade(b,MINER).ok and b.session.snapshot()==before,"fee/ticket save failure rolls back")
 b.save_path=""
 var r:=talk(b,MINER)
 b.session._profile.player.gold=999
 before=b.session.snapshot()
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"fee checked again after dialogue")
 b.session._profile.player.gold=1000
 r=talk(b,MINER)
 var token:String=r.dialogue.token
 check(choose(b,r,"yes").ok and b.session.snapshot().player.gold==0 and b.session.snapshot().original_items==[2527],"exact balance deducted once with original ticket")
 check(not b.handle({"type":"quest_choose","token":token,"choice":"yes"}).ok and b.session.snapshot().original_items==[2527],"fee request replay cannot issue another ticket")
 b.free()
func level_fees() -> void:
 var b=setup()
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-level-fees.json"))
 b.quest_catalog.npcs.append_array(fixture.npcs);b.quest_catalog.items.merge(fixture.items)
 b.quest_catalog.enabled_events.append(44)
 var npc:="quiz/uketuke2@4020:18:13"
 b.session._profile.player.gold=4000
 var r:=talk(b,npc)
 check(r.dialogue.text.contains("3200stone") and not r.dialogue.text.contains("%8d"),"source fee prompt expands authoritative Lv80*40")
 r=choose(b,r,"yes")
 b.session.gm_raise_level(-1,81)
 b.session._profile.player.gold=3239
 var before:Dictionary=b.session.snapshot()
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"reward confirmation recalculates changed level and balance")
 b.session._profile.player.gold=3240
 r=choose(b,talk(b,npc),"yes")
 b.save_path="user://blocked-bonus-parent/child.json";before=b.session.snapshot()
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"scaled fee and ticket roll back on save failure")
 b.save_path=""
 r=choose(b,talk(b,npc),"yes")
 var token:String=r.dialogue.token
 check(choose(b,r,"ok").ok and b.session.snapshot().player.gold==0 and b.session.snapshot().original_items==[2757],"current Lv81*40 exact balance commits C ticket once")
 check(not b.handle({"type":"quest_choose","token":token,"choice":"ok"}).ok and b.session.snapshot().original_items==[2757],"scaled transaction replay rejected")
 # Fresh real level progression exercises the other create and original A/B branches.
 for pair in [[30,600,2755],[50,2000,2756]]:
  b.session._profile=Session.new().snapshot();b.session.gm_raise_level(-1,pair[0]);b.session._profile.player.gold=pair[1]
  for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
  check(trade(b,"quiz/uketuke@2020:18:13").ok and b.session.snapshot().player.gold==0 and b.session.snapshot().original_items==[pair[2]],"original level-selected ticket %d with exact fee"%pair[2])
 var profile:Dictionary=b.session.snapshot()
 for invalid in ["LV*30","LV*20+1","-1","+1","2147483648","99999999999999999999999"]:
  check(Rules.stone_cost(profile,invalid)==-1,"unknown/overflow cost fails closed: "+invalid)
 profile.player.level=53687091
 check(Rules.stone_cost(profile,"LV*40")==2147483640,"signed int maximum safe multiplication")
 profile.player.level=53687092
 check(Rules.stone_cost(profile,"LV*40")==-1,"signed int multiplication overflow rejected")
 b.free()
func poll() -> void:
 for link in links:link.poll(0.01)
func request(link,command:Dictionary) -> Dictionary:
 var result:Array=[]
 link.request(command,func(reply):result.append(reply))
 check(await Wait.until(self,func():poll();return not result.is_empty()),"real LAN round trip")
 return result[0] if not result.is_empty() else {}
func lan() -> void:
 var b=setup();root.add_child(b)
 check(trade(b,SHARK).ok,"LAN original request")
 var first:=add(b,223);add(b,224)
 place(b,SHARK)
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"LAN ephemeral server port")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port)
  links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two real devices connect")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var one:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":SHARK})
 var two:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":SHARK})
 var stale:Dictionary=await request(links[0],{"type":"quest_choose","token":one.dialogue.token,"choice":"yes"})
 check(not stale.ok,"second device invalidates first confirmation")
 var reply:Dictionary=await request(links[1],{"type":"quest_choose","token":two.dialogue.token,"choice":"yes"})
 var result:Dictionary=await request(links[1],{"type":"quest_choose","token":reply.dialogue.token,"choice":"ok"})
 check(result.ok and not b.session.snapshot().pets.any(func(p):return str(p.pet_id)==first) and b.session.snapshot().original_items==[2607],"LAN source pair committed by second device")
 result=await request(links[0],{"type":"quest_choose","token":reply.dialogue.token,"choice":"ok"})
 check(not result.ok and b.session.snapshot().original_items==[2607],"other device cannot replay committed pair")
 for link in links:link.close()
 links=[]
 server.stop();server.queue_free();b.queue_free()

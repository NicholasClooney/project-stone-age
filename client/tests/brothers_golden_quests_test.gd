extends SceneTree
const Clock=preload("res://scripts/clock.gd")
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Hub=preload("res://server/profile_hub.gd")
const KUY="king/event69_1"
var failures:=0
var suite_started:int=Clock.ticks_msec()
func timing(label:String,started:int)->void:print("TIMING "+label+" "+str(Clock.ticks_msec()-started)+" ms")
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func fresh():
 var b=Backend.new()
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 b.session.gm_raise_level(-1,80)
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 return b
func brother_walk(b,id:String)->bool:
 var npc:Dictionary=b.original_quests.npc_by_id(id)
 if npc.is_empty():return false
 if b.automation.position_map not in range(31701,31707):
  var entrance:Dictionary={}
  for link in b.quest_helper.places.links(300).values():
   if int(link.to_map)==31701 and not bool(link.get("disabled",false)):entrance=link;break
  if entrance.is_empty():return false
  b.automation.position_changed(300,Vector2i(int(entrance.cell[0]),int(entrance.cell[1])))
  if not b.handle({"type":"report_position","map_id":31701,"cell":entrance.target}).get("ok",false):return false
 return preload("res://tests/support/water_route_driver.gd").walk_near(b,npc,range(31701,31707))
func golden_walk(b,id:String)->bool:
 var travel=preload("res://tests/support/water_route_driver.gd")
 var npc:Dictionary=b.original_quests.npc_by_id(id)
 if npc.is_empty():return false
 if not b.automation.position_map in range(31901,31912):
  var entry:Dictionary={}
  for link in b.quest_helper.places.links(300).values():
   if int(link.to_map)==31901 and not bool(link.get("disabled",false)):entry=link;break
  if entry.is_empty():return false
  # Public departure setup; all protected route steps below are actual reports.
  b.automation.position_changed(300,Vector2i(int(entry.cell[0]),int(entry.cell[1])))
  if not b.handle({"type":"report_position","map_id":31901,"cell":entry.target}).get("ok",false):return false
 if int(npc.map_id)>=31904 and b.automation.position_map<=31903:
  var gate:Dictionary=b.original_quests.npc_by_id("genout/wpm_31903_39_4")
  if not travel.walk_near(b,gate,range(31901,31904)) or not travel.commit(b,gate):return false
 if int(npc.map_id)>=31910 and b.automation.position_map<=31909:
  var guide:Dictionary=b.original_quests.npc_by_id("giiru/event/event30_7")
  if not travel.walk_near(b,guide,range(31904,31910)) or not travel.commit(b,guide):return false
 if int(npc.map_id)==31911 and b.automation.position_map==31910:
  var truth:Dictionary=b.original_quests.npc_by_id("genout/wpm_31910_8_9")
  if not travel.walk_near(b,truth,[31910]) or not travel.commit(b,truth):return false
 return travel.walk_near(b,npc,range(31901,31912))
func talk(b,id:String) -> Dictionary:
 b.original_quests.pending={}
 if preload("res://server/brothers_arrival_helper.gd").owns(b.original_quests.npc_by_id(id)):
  check(brother_walk(b,id),"walk original brothers route to "+id)
  return b.handle({"type":"quest_talk","npc_id":id})
 if preload("res://server/golden_arrival_helper.gd").owns(b.original_quests.npc_by_id(id)):
  check(golden_walk(b,id),"walk original golden route to "+id)
  return b.handle({"type":"quest_talk","npc_id":id})
 var visit:Dictionary=b.handle({"type":"quest_visit","npc_id":id,"mode":"near"})
 check(visit.ok,"safe original NPC "+id)
 return b.handle({"type":"quest_talk","npc_id":id})
func choose(b,r:Dictionary,choice:String) -> Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":choice})
func trade(b,id:String) -> Dictionary:
 var r:=talk(b,id)
 var phase:String=str(b.original_quests.pending.get("phase",""))
 if phase=="end":choose(b,r,"ok");return {"ok":true}
 r=choose(b,r,"yes")
 if r.has("dialogue"):r=choose(b,r,"ok")
 return r
func adult(b) -> void:
 check(preload("res://tests/support/original_route_driver.gd").complete_adult(b).get("ok",false),"adult actual original level gate and channel prerequisite")

func return_from_brother_trap(b,choice:int)->bool:
 # Four original corridors are decoys, not alternative entrances to the
 # reward hall. Follow their actual portal and re-enter for the next guard.
 var source:Vector2i=[Vector2i(45,58),Vector2i(5,60),Vector2i(35,60),Vector2i(25,60)][choice-1]
 var link:Dictionary=b.quest_helper.places.links(31706).get(source,{})
 if link.is_empty():return false
 var route=preload("res://tests/support/original_route_driver.gd")
 if not route.walk(b,31706,source,[31706]).get("ok",false):return false
 if not b.handle({"type":"report_position","map_id":int(link.to_map),"cell":link.target}).get("ok",false):return false
 check(b.automation.position_map==([300,31705,31705,300][choice-1]),"original decoy corridor destination")
 if b.automation.position_map==300:
  var root_link:Dictionary=b.quest_helper.places.links(300).get(b.automation.position_cell,{})
  if int(root_link.get("to_map",-1))!=31701:return false
  if not b.handle({"type":"report_position","map_id":31701,"cell":root_link.target}).get("ok",false):return false
 if not trade(b,"genout/wpm_31705_25_8").get("ok",false):return false
 return true
func brothers(b) -> void:
 var started:int=Clock.ticks_msec()
 check(trade(b,"giiru/event/ev28_0").ok,"brothers REQUEST28")
 # Select the actual source branch that issues each correct paper.
 for item in [2507,2509,2511,2513,2515]:
  var options:Array=b.quest_helper.candidates(b,28,"GetItem",item)
  check(not options.is_empty(),"source correct answer exists %d"%item)
  check(trade(b,str(options[0].npc.id)).ok and item in b.session.snapshot().original_items,"real answer paper %d"%item)
 check(trade(b,"giiru/event/ev28_end").ok and Rules.flag(b.session.snapshot(),"ended",28) and 2517 in b.session.snapshot().original_items,"five papers to crystal END28")
 check(trade(b,"giiru/event/ev28_end").ok and Rules.flag(b.session.snapshot(),"now",31),"source REQUEST31")
 check(trade(b,"genout/wpm_31705_25_8").ok and b.automation.position_map==31706,"source floor gate")
 timing("brothers papers/crystal/request",started)
 for choice in range(1,6):
  started=Clock.ticks_msec()
  brother_guard(b,choice)
  timing("brothers guard%d savefail/retry"%choice,started)
  if choice!=5:
   started=Clock.ticks_msec()
   check(return_from_brother_trap(b,choice),"walk original decoy exit and original reentry")
   timing("brothers original decoy%d return"%choice,started)
 check(brother_walk(b,"giiru/event/ev28_ed5"),"actual fifth corridor establishes reward hall arrival")
 # Alternatives to one real, source-earned pre-reward state. Arrival/marks are
 # never copied or assigned; each alternative walks within the actual hall.
 var earned:Dictionary=b.session.snapshot()
 started=Clock.ticks_msec()
 for choice in range(1,6):
  b.session._profile=earned.duplicate(true)
  b.original_quests.pending={}
  brother_reward(b,choice)
 timing("brothers five reward alternatives",started)
func brother_guard(b,choice:int)->void:
 var guard:="300/sb_5b%d.arg"%choice
 var before:Dictionary=b.session.snapshot()
 check(trade(b,guard).ok and b.battle_open and b.session._pending.has("quest_guard"),"real original fixed guard battle")
 check(b.session._pending.enemies[0].source_enemy_id==[1001,1012,1013,1014,1015][choice-1],"exact original guard enemy")
 var location:Dictionary=before.location
 b.save_path="user://missing-brothers/save.json"
 fight(b)
 check(not b.battle_state.get("settled",false) and b.session.snapshot().original_items==before.original_items and b.session.snapshot().completed_battles==before.completed_battles and b.session.snapshot().location==location,"guard failed save rolls back rewards and warp")
 check(not b.handle({"type":"battle_close"}).ok,"failed settlement remains retryable")
 b.save_path=""
 check(b.handle({"type":"battle_close"}).ok and b.automation.position_map==31706 and b.automation.position_cell.y in [16,17],"guard retry commits exact original warp")
func brother_reward(b,choice:int)->void:
 var reward_id:="giiru/event/ev28_ed%d"%choice
 check(brother_walk(b,reward_id),"walk original victory corridor and reward portal")
 var before_reward:Dictionary=b.session.snapshot()
 b.save_path="user://missing-brothers/save.json"
 check(not trade(b,reward_id).ok and b.session.snapshot()==before_reward,"pet reward failed save preserves UID, crystal and flags")
 b.save_path=""
 var pet_copy:Dictionary=b.session.snapshot()
 for i in range(Session.PET_CAPACITY-b.session._profile.pets.size()):b.session.gm_grant_pet(91)
 check(not trade(b,reward_id).ok and 2517 in b.session.snapshot().original_items,"pet capacity preflight preserves crystal")
 b.session._profile=pet_copy
 var reward_reply:=choose(b,talk(b,reward_id),"yes")
 var reward_token:String=str(reward_reply.get("dialogue",{}).get("token",""))
 check(choose(b,reward_reply,"ok").ok and Rules.flag(b.session.snapshot(),"ended",31),"five-choice original reward END31")
 check(not b.handle({"type":"quest_choose","token":reward_token,"choice":"ok"}).ok,"single-use final reward token")
 var pet:Dictionary=b.session.snapshot().pets[-1]
 check(pet.source_enemy_id==[54,57,55,56,481][choice-1] and pet.level==1,"exact source GetPet variant and level")
 var snapshot:Dictionary=b.session.snapshot()
 trade(b,"giiru/event/ev28_ed%d"%choice)
 check(b.session.snapshot()==snapshot,"completed reward cannot repeat")
func fight(b) -> void:
 for i in range(100):
  if not b.battle.snapshot().active:return
  b.handle({"type":"battle_command","action":"attack","target":0})
 check(not b.battle.snapshot().active,"actual battle completes")
func golden(b,lost:=false) -> void:
 check(trade(b,"giiru/event/event30_1").ok and Rules.flag(b.session.snapshot(),"now",30) and 2549 in b.session.snapshot().original_items,"quarry request and actual key")
 check(trade(b,"genout/wpm_31903_39_4").ok and b.automation.position_map==31904,"key gate original warp")
 check(trade(b,"giiru/event/event30_2").ok and Rules.flag(b.session.snapshot(),"now",54),"spirit request54")
 trade(b,"giiru/event/event30_3");trade(b,"giiru/event/event30_4")
 check(trade(b,KUY).ok and Rules.flag(b.session.snapshot(),"ended",30) and 2547 in b.session.snapshot().original_items,"live-bound Kuy source gives first mirror END30")
 if lost:
  check(b.handle({"type":"quest_discard","item_id":2547}).ok,"discard first mirror")
  check(trade(b,KUY).ok and 2532 in b.session.snapshot().original_items,"source replacement mirror2532")
 var rng:=RandomNumberGenerator.new();rng.seed=40
 var area:Dictionary=b.encounter_catalog.area_at(31907,Vector2i(24,43))
 check(b.encounter_catalog.roll_group(area,522,rng,[]).is_empty(),"source mirror item gate enforced")
 var troop:Dictionary={}
 for i in range(100):
  troop=b.encounter_catalog.roll_group(area,521 if lost else 522,rng,b.session.snapshot().original_items)
  if troop.get("enemies",[]).any(func(e):return int(e.source_enemy_id)==1060):break
 check(troop.get("enemies",[]).any(func(e):return int(e.source_enemy_id)==1060 and e.generated_drops==[2548]),"real source group produces messenger and guaranteed eye")
 var config:Dictionary=b.session.start_wild_battle_config(troop)
 check(not config.is_empty(),"source encounter accepted")
 b.open_battle(config);fight(b)
 check(b.handle({"type":"battle_close"}).ok and 2548 in b.session.snapshot().original_items,"kill messenger actual authoritative loot")
 check(trade(b,"giiru/event/event30_2").ok and Rules.flag(b.session.snapshot(),"now",29),"eye source REQUEST29")
 check(trade(b,"giiru/event/event30_7").ok and b.automation.position_map==31910,"spirit messenger true chamber warp")
 var before:Dictionary=b.session.snapshot()
 var r:=choose(b,talk(b,"genout/wpm_31910_8_9"),"yes")
 b.save_path="user://missing-brothers/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before and b.automation.position_map==31910,"eye consumption and warp save rollback")
 b.save_path=""
 check(trade(b,"genout/wpm_31910_8_9").ok and not 2548 in b.session.snapshot().original_items and b.automation.position_map==31911,"correct original messenger consumes eye and moves")
 check(trade(b,"giiru/event/event30_6").ok and Rules.flag(b.session.snapshot(),"ended",29) and 2551 in b.session.snapshot().original_items,"spirit source armor END29")
 var count:int=b.session.snapshot().pets.size()
 check(trade(b,KUY).ok and Rules.flag(b.session.snapshot(),"ended",54),"return actual mirror END54")
 check(b.session.snapshot().pets.size()==count+(0 if lost else 1),"replacement never grants antelope")
 if not lost:check(b.session.snapshot().pets[-1].source_enemy_id==355,"exact antelope enemy355")
 var after:Dictionary=b.session.snapshot();trade(b,KUY)
 check(b.session.snapshot().pets==after.pets and b.session.snapshot().next_pet_id==after.next_pet_id,"no repeat antelope; source may reissue2532 because NOW54 remains set")
func golden_wrong_door(b)->void:
 # Isolated wrong-door source case: audited inventory/earlier flags are
 # explicit fixtures, never arrival proofs. The actual cave/gates are walked.
 Session.OriginalEquipment.add(b.session._profile,2548)
 Session.OriginalEquipment.add(b.session._profile,2549)
 for flag in [["ended",4],["ended",30],["now",29],["now",54]]:Rules.set_flag(b.session._profile,flag[0],flag[1],true)
 check(trade(b,"genout/wpm_31910_10_11").ok and not 2548 in b.session.snapshot().original_items and b.automation.position_map==31904 and b.automation.position_cell==Vector2i(53,30),"wrong original messenger consumes eye and returns exact source coordinate")

func run() -> void:
 var b=Backend.new()
 b.session.gm_raise_level(-1,30)
 var low:=talk(b,"giiru/event/ev28_0")
 check(str(b.original_quests.pending.phase)=="end" and not Rules.flag(b.session.snapshot(),"now",28),"original LV>30 boundary")
 b.original_quests.pending={};b.session.gm_raise_level(-1,80)
 trade(b,"giiru/event/ev28_0");trade(b,"giiru/event/ev28_1")
 check(2508 in b.session.snapshot().original_items,"wrong answer gives original wrong paper")
 trade(b,"giiru/event/ev28_end")
 check(not 2508 in b.session.snapshot().original_items and not Rules.flag(b.session.snapshot(),"ended",28),"failed five-answer check removes papers without END28")
 b.free();b=fresh()
 for npc in b.quest_catalog.active_npcs():
  if not npc.events.any(func(e):return int(e) in [28,29,30,31,54]):continue
  check(FileAccess.file_exists("res://assets/legacy/"+str(npc.path)),"original NPC graphic "+str(npc.id))
  if not preload("res://server/brothers_arrival_helper.gd").owns(npc) and not preload("res://server/golden_arrival_helper.gd").owns(npc):check(not b.quest_helper.destination(b,npc,"near").is_empty(),"NPC reachable neighbour "+str(npc.id))
 check(b.original_quests.npc_by_id("giiru/event/event30_5").is_empty() and not b.original_quests.npc_by_id(KUY).is_empty(),"actual create binding only")
 adult(b);brothers(b)
 var phase_started:int=Clock.ticks_msec()
 golden(b);timing("golden original mirror route",phase_started)
 b.free()
 b=fresh();Rules.set_flag(b.session._profile,"ended",28,true)
 check(trade(b,"giiru/event/ev28_end").ok and 2517 in b.session.snapshot().original_items,"missing crystal recoverable via source REQUEST31")
 check(b.session.save_game("user://brothers-reload.json"),"temporary crystal save")
 var loaded=Session.new()
 check(loaded.load_game("user://brothers-reload.json") and not 2517 in loaded.snapshot().original_items,"source logout crystal removed on authoritative reload")
 b.free()
 lan()
 timing("suite total",suite_started)
 print("BROTHERS GOLDEN QUESTS: %d failures"%failures)
 quit(1 if failures else 0)
func lan() -> void:
 var dir:="user://brothers-hub-%d"%OS.get_process_id()
 DirAccess.make_dir_recursive_absolute(dir)
 var hub=Hub.new(dir.path_join("accounts.json"));hub.tick=false;hub.backups=false;hub.share_dir=""
 check(hub.start(),"LAN profile hub starts")
 check(hub.handle(1,{"type":"create_profile","name":"Alice","pin":"1111"}).ok and hub.handle(2,{"type":"login","name":"Alice","pin":"1111"}).ok,"two devices share authority")
 var b=hub.backend_of(1);b.session.gm_raise_level(-1,40)
 check(brother_walk(b,"giiru/event/ev28_0"),"LAN original brothers entrance")
 var one:Dictionary=hub.handle(1,{"type":"quest_talk","npc_id":"giiru/event/ev28_0"})
 var two:Dictionary=hub.handle(2,{"type":"quest_talk","npc_id":"giiru/event/ev28_0"})
 check(not hub.handle(1,{"type":"quest_choose","token":one.dialogue.token,"choice":"yes"}).ok,"second device invalidates first token")
 check(hub.handle(2,{"type":"quest_choose","token":two.dialogue.token,"choice":"yes"}).ok and Rules.flag(hub.backend_of(1).session.snapshot(),"now",28),"shared source transition consistent")
 hub.shut_down();hub.free()
 for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir.path_join(f))
 DirAccess.remove_absolute(dir)

func party_retry(failed_slot:int) -> void:
 var folder:="user://brothers-party-retry-%d-%d"%[OS.get_process_id(),failed_slot]
 DirAccess.make_dir_recursive_absolute(folder)
 var hub=Hub.new(folder.path_join("accounts.json"),func():return 10.0)
 hub.tick=false;hub.backups=false;hub.share_dir=""
 hub.presence_clock=func():return 10000
 hub.battle_clock=func():return 500000
 root.add_child(hub);hub.start()
 for i in range(2):
  hub.handle(i+1,{"type":"create_profile","name":"Eye%d"%i,"pin":"1111"})
  hub.handle(i+1,{"type":"report_position","map_id":1000,"cell":[80+i,90],"client":"eye%d"%i})
 check(hub.handle(2,{"type":"party_join","facing":1}).ok,"eye real two-member party")
 var peers:Array=[hub.backends[hub.profile_of(1)],hub.backends[hub.profile_of(2)]]
 for b in peers:
  for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
  b.session.gm_set_base_stat(-1,"vitality",10000)
  b.session._profile.player.hp=b.session._profile.player.max_hp
 peers[1].session.gm_set_base_stat(-1,"strength",10000)
 var enemy:Dictionary=peers[0].encounter_catalog.actor(1060,peers[0].encounter_rng)
 check(enemy.generated_drops==[2548],"party uses real1060 original eye roll")
 var config:Dictionary=peers[0].session.start_wild_battle_config({"area_id":373,"group_id":522,"enemies":[enemy]})
 peers[0].open_battle(config)
 check(peers[0].party_battle() and peers[1].party_battle(),"eye uses real PartyBattleSession and both Backends")
 var entry:Dictionary=hub.party_battles.fighting[hub.profile_of(1)]
 var before:Array=[];var pending:Array=[];var paths:Array=[]
 var blocker=FileAccess.open(folder.path_join("not-a-directory"),FileAccess.WRITE)
 blocker.store_string("intentional save failure fixture");blocker.close()
 for slot in range(2):
  before.append(peers[slot].session.snapshot());pending.append(peers[slot].session._pending.duplicate(true));paths.append(peers[slot].save_path)
  if slot==failed_slot or failed_slot==2:peers[slot].save_path=folder.path_join("not-a-directory/save.json")
 for turn in range(100):
  if not peers[0].battle.snapshot().active:break
  for slot in range(2):
   var state:Dictionary=peers[slot].battle.snapshot()
   hub.handle(slot+1,{"type":"battle_command","battle_id":state.battle_id,"turn":state.turn,"slot":state.party_slot,"action":"defend" if slot==0 else "attack","target":0})
 check(not peers[0].battle.snapshot().active and entry.settled.size()==2 and hub.party_battles.fighting.is_empty(),"party dispatch already consumed both terminal slices")
 check(entry.session.drop_claims_for(0).is_empty() and entry.session.drop_claims_for(1).size()==1,"only member owns enemy1060 drop claim")
 for slot in range(2):
  var b=peers[slot]
  var expected=Session.new();expected._profile=before[slot].duplicate(true);expected._pending=pending[slot].duplicate(true)
  var personal:Dictionary=entry.session.slice_for(slot,str(entry.own[slot]))
  check(expected.apply_battle_result(personal,entry.session.drop_claims_for(slot)),"independent personal slice expected settlement")
  if slot==failed_slot or failed_slot==2:
   check(not b.battle_state.get("settled",false) and b.session.snapshot()==before[slot],"party failed save rolls back whole personal profile")
   check(not b.handle({"type":"battle_close"}).ok and b.session.snapshot()==before[slot],"party repeated failed close stays rolled back")
  b.save_path=paths[slot]
  check(b.handle({"type":"battle_close"}).ok,"party restore real save and retry original slice")
  check(b.session.snapshot()==expected.snapshot(),"party retry exact personal HP XP currency UID and own loot")
  var saved=Session.new()
  check(saved.load_game(paths[slot]) and saved.snapshot()==expected.snapshot(),"party retry persisted exact personal result to real save")
  check(b.session.snapshot().original_items.count(2548)==slot,"eye never duplicated or forwarded to leader")
  var after:Dictionary=b.session.snapshot()
  b.handle({"type":"battle_close"});hub.party_battles._push(entry)
  check(b.session.snapshot()==after,"duplicate close and consumed party push grant nothing")
 hub.shut_down();hub.queue_free();await process_frame

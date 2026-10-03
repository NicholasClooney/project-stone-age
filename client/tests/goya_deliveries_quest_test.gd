extends "res://tests/yam_axe_quest_test.gd"
const BOY="jaruga/event/event06_1@20401:12:13"
const MERCHANT="jaruga/event/event06_2@4000:71:97"
const SKY="jaruga/event/event07_1@20401:14:10"
const FLOWER="jaruga/event/event07_3@20404:44:13"
const BEAUTY="jaruga/event/event07_2@20406:36:34"
func fresh():
 var b=Backend.new();b.quest_catalog.enabled_events=[6,7,8]
 return b
func talk(b,id:String) -> Dictionary:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 var npc:Dictionary=b.original_quests.npc_by_id(id)
 if int(npc.map_id) in range(20401,20407):
  check(preload("res://tests/support/legacy_cave_route.gd").approach(b,npc).ok,"actual original Goya route to "+id)
 else:check(b.handle({"type":"quest_visit","npc_id":id,"mode":"near"}).ok,"public original merchant visit")
 return b.handle({"type":"quest_talk","npc_id":id})
func failure(b,id:String,note:String) -> void:
 var thanks:=choose(b,talk(b,id),"yes")
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-goya-parent/save.json"
 check(not choose(b,thanks,"ok").ok and b.session.snapshot()==before,note)
 b.save_path=""
func shell_start(b) -> void:
 check(trade(b,BOY).ok and Rules.flag(b.session.snapshot(),"now",6),"real boy source starts NOW6")
 check(trade(b,MERCHANT).ok and b.session.snapshot().original_items.count(2414)==2,"real merchant source grants two free shells")
func run() -> void:
 var b=Backend.new()
 for e in [6,7,8]:check(e in b.quest_catalog.enabled_events and not row(b,e).steps.is_empty(),"registered event has helper stages %d"%e)
 b.quest_catalog.enabled_events=[6,7,8]
 if b.original_quests.npc_by_id(BOY).is_empty():b.free();quit(1);return
 for id in [BOY,MERCHANT,SKY,FLOWER,BEAUTY]:
  var npc:Dictionary=b.original_quests.npc_by_id(id)
  check(FileAccess.file_exists("res://assets/legacy/"+str(npc.path)),"original NPC art exists "+id)
  for mode in ["arrival","near"]:check(not b.quest_helper.destination(b,npc,mode).is_empty(),"safe real map destination "+id+" "+mode)
 check(talk(b,SKY).dialogue.text=="噗唏！","without shell original pig only grunts")
 var gold:=int(b.session.snapshot().player.gold)
 shell_start(b)
 check(int(b.session.snapshot().player.gold)==gold,"merchant never charges money")
 var before:Dictionary=b.session.snapshot();talk(b,MERCHANT)
 check(b.session.snapshot().original_items==before.original_items,"merchant with two shells never issues more")
 failure(b,BOY,"failed pet-reward save retains both shells and NOW6")
 for i in range(Session.PET_CAPACITY):check(b.session.gm_grant_pet(173),"real imported filler pet")
 var full:Dictionary=b.session.snapshot()
 check(not trade(b,BOY).ok and b.session.snapshot().pets==full.pets and b.session.snapshot().original_items==full.original_items,"full pet roster cannot consume shell or complete quest")
 b.session._profile.pets=[];b.session._profile.active_pet=-1;b.session._profile.ride_pet=-1
 check(trade(b,BOY).ok,"two-shell delivery succeeds")
 var reward:Dictionary=b.session.snapshot().pets[-1]
 check(int(reward.source_enemy_id)==44 and int(reward.template_id)==63 and int(reward.level)==1,"two-shell branch grants exact one-level Trokon")
 check(b.session.snapshot().original_items.count(2414)==1 and Rules.flag(b.session.snapshot(),"ended",6),"two-shell branch consumes exactly one and writes END6")
 before=b.session.snapshot();talk(b,BOY)
 check(b.session.snapshot().pets==before.pets and b.session.snapshot().original_items==before.original_items,"END6 cannot repeat pet reward")
 check(b.handle({"type":"quest_discard","item_id":2414}).ok,"discard last shell uses backend transaction")
 check(row(b,6).steps.any(func(s):return s.id=="goya6:replace" and s.actionable),"completed quest retains useful replacement helper")
 failure(b,MERCHANT,"replacement save failure preserves absent shell and completed END6")
 check(trade(b,MERCHANT).ok and b.session.snapshot().original_items.count(2414)==1 and b.session.snapshot().pets.size()==1,"completed merchant restores one shell without a pet")
 check(trade(b,SKY).ok and 2425 in b.session.snapshot().original_items,"pig request after END6 gives original letter")
 failure(b,FLOWER,"flower save failure preserves original letter and no flower")
 check(trade(b,FLOWER).ok and 2424 in b.session.snapshot().original_items and int(b.session.snapshot().player.gold)==gold,"source flower shop gives free flower")
 before=b.session.snapshot();talk(b,FLOWER)
 check(b.session.snapshot().original_items==before.original_items,"held flower cannot be duplicated")
 check(b.handle({"type":"quest_discard","item_id":2424}).ok and trade(b,FLOWER).ok,"lost flower reissued through original branch")
 failure(b,BEAUTY,"failed END7 saves retain both flower and letter")
 check(trade(b,BEAUTY).ok and Rules.flag(b.session.snapshot(),"ended",7) and not Rules.flag(b.session.snapshot(),"ended",8),"flower and letter complete END7 separately")
 check(b.session.snapshot().original_items==[2414],"END7 consumes both gifts but retains shell")
 check(trade(b,BEAUTY).ok and Rules.flag(b.session.snapshot(),"now",8) and 2426 in b.session.snapshot().original_items,"second conversation gives reply and NOW8")
 check(b.handle({"type":"quest_discard","item_id":2426}).ok,"discard reply")
 var charm:=int(b.session.snapshot().player.charm)
 check(trade(b,BEAUTY).ok and int(b.session.snapshot().player.charm)==charm-1 and trade(b,BEAUTY).ok,"lost reply cancelled and reaccepted with original charm penalty")
 check(b.handle({"type":"quest_discard","item_id":2414}).ok,"remove language shell during return")
 check(talk(b,SKY).dialogue.text=="噗唏！" and 2426 in b.session.snapshot().original_items,"without shell pig cannot accept reply")
 check(trade(b,MERCHANT).ok,"real merchant restores missing language shell")
 failure(b,SKY,"failed final save keeps reply and does not create bracelet")
 var thanks:=choose(b,talk(b,SKY),"yes")
 check(choose(b,thanks,"ok").ok and Rules.flag(b.session.snapshot(),"ended",8),"reply commits END8")
 check(not choose(b,thanks,"ok").ok and b.session.snapshot().original_items.count(1206)==1 and b.session.snapshot().original_items.count(2414)==1,"final token cannot duplicate bracelet; shell remains")
 before=b.session.snapshot();talk(b,SKY);talk(b,BEAUTY)
 check(b.session.snapshot().original_items==before.original_items and b.session.snapshot().original_events==before.original_events,"completed pig chain cannot grant duplicates")
 var path:="user://goya-full-chain.json"
 check(b.session.save_game(path),"earned pet bracelet and flags persist")
 var loaded=Session.new()
 var earned_pets:Array=b.session.snapshot().pets.duplicate(true)
 # JSON catalog numbers enter element arrays as floats; save loading normalizes
 # integer-valued metadata. Compare all pet fields after that lossless cast.
 for pet in earned_pets:pet.elements=pet.elements.map(func(v):return int(v))
 var load_ok:=loaded.load_game(path)
 # Runtime pet_id/favorite/loyalty keys are StringNames; JSON restores String
 # keys. Compare each persisted value and count without relying on key types.
 var pets_match:bool=loaded.snapshot().pets.size()==earned_pets.size()
 if pets_match:
  for i in range(earned_pets.size()):
   var actual:Dictionary=loaded.snapshot().pets[i]
   pets_match=pets_match and actual.size()==earned_pets[i].size()
   for key in earned_pets[i]:pets_match=pets_match and actual.has(str(key)) and actual[str(key)]==earned_pets[i][key]
 check(load_ok and loaded.snapshot().original_items==b.session.snapshot().original_items and loaded.snapshot().original_events==b.session.snapshot().original_events and pets_match,"real save roundtrip preserves every Goya pet field, items and END flags")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 b.free()
 alternatives()
 await lan()
 print("GOYA DELIVERIES: %d failures"%failures)
 quit(1 if failures else 0)
func alternatives() -> void:
 var independent=fresh()
 Session.OriginalEquipment.add(independent.session._profile,2414)
 check(trade(independent,SKY).ok and Rules.flag(independent.session.snapshot(),"now",7) and not Rules.flag(independent.session.snapshot(),"ended",6),"an existing language shell starts pig chain without inventing END6 prerequisite")
 independent.free()
 var capacity=fresh()
 check(trade(capacity,BOY).ok,"capacity fixture earns NOW6")
 for i in range(14):Session.OriginalEquipment.add(capacity.session._profile,2424)
 var capacity_before:Dictionary=capacity.session.snapshot()
 check(not trade(capacity,MERCHANT).ok and capacity.session.snapshot().original_items==capacity_before.original_items and not 2414 in capacity.session.snapshot().original_items,"merchant cannot partially grant two shells into full bag")
 capacity.free()
 for count in [1,3]:
  var b=fresh();shell_start(b)
  if count==1:check(b.handle({"type":"quest_discard","item_id":2414}).ok,"prepare one-shell reward through actual discard")
  else:Session.OriginalEquipment.add(b.session._profile,2414)
  check(trade(b,BOY).ok,"original quantity branch %d"%count)
  check(int(b.session.snapshot().pets[-1].source_enemy_id)==(47 if count==1 else 44) and b.session.snapshot().original_items.count(2414)==count-1,"quantity>= branch and distinct pet match source")
  if count==1:check(trade(b,MERCHANT).ok and b.session.snapshot().original_items.count(2414)==1,"one-shell pet outcome can regain shell for pig chain")
  b.free()
 var b=fresh();shell_start(b)
 b.handle({"type":"quest_discard","item_id":2414})
 check(trade(b,MERCHANT).ok and b.session.snapshot().original_items.count(2414)==2,"active merchant with one shell tops up exactly one")
 b.free()
func lan() -> void:
 var b=fresh();root.add_child(b);shell_start(b)
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"Goya LAN server uses port0")
 var links:Array=[];var states:Array=[];var pollers:Array=[]
 for i in range(2):
  var link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
  var state=preload("res://network/client_state.gd").new();link.message.connect(state.apply)
  var poller:Callable=func():link.poll(0.016)
  process_frame.connect(poller);links.append(link);states.append(state);pollers.append(poller);link.connect_now()
  check(await Wait.until(self,func():return link.online and not state.profile.is_empty()),"Goya second device connected")
  await rpc(link,{"type":"ping"})
 check(preload("res://tests/support/legacy_cave_route.gd").approach(b,b.original_quests.npc_by_id(BOY)).ok,"LAN reward fixture walks actual Goya entrance")
 var opened:Dictionary=await rpc(links[0],{"type":"quest_talk","npc_id":BOY})
 var thanks:Dictionary=await rpc(links[0],{"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 await rpc(links[0],{"type":"ping"})
 var other:Dictionary=await rpc(links[1],{"type":"quest_talk","npc_id":BOY})
 check(not (await rpc(links[0],{"type":"quest_choose","token":thanks.dialogue.token,"choice":"ok"})).ok,"other device invalidates pending pet reward")
 other=await rpc(links[1],{"type":"quest_choose","token":other.dialogue.token,"choice":"yes"})
 check((await rpc(links[1],{"type":"quest_choose","token":other.dialogue.token,"choice":"ok"})).ok,"other device commits one pet reward")
 for link in links:await rpc(link,{"type":"ping"})
 check(states.all(func(s):return Rules.flag(s.profile,"ended",6) and s.profile.pets.size()==1 and int(s.profile.pets[0].source_enemy_id)==44 and s.profile.original_items.count(2414)==1),"both devices see exactly one pet and one retained shell")
 for i in range(2):links[i].close();process_frame.disconnect(pollers[i])
 server.stop();server.queue_free();b.queue_free();await process_frame

extends "res://tests/original_fixed_guards_test.gd"
const Encounters=preload("res://server/encounter_catalog.gd")
const PersonalState=preload("res://server/quest_npc_state.gd")
var fixtures:Array=[]
var now:=1000
func install(b)->void:
 for fixture in fixtures:
  b.quest_catalog.npcs.append_array(fixture.module.npcs.duplicate(true))
  b.quest_catalog.items.merge(fixture.module.items)
 b.quest_catalog.enabled_events.append_array([13,14,27,45])
 b.original_quests.npc_state.clock=func():return now
func grant(b,id:int)->void:b.session.OriginalEquipment.add(b.session._profile,id)
func run()->void:
 fixtures=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/personal-quest-npcs.json"))
 var trusted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/quests/catalog.json"))
 var original:Dictionary=trusted.duplicate(true)
 for fixture in fixtures:
  if fixture.module.has("drops"):trusted.reviewed_drops[fixture.manifest.id]={"active":true,"entries":fixture.module.drops}
 Encounters.configure_reviewed_drops(trusted)
 var b=fresh();install(b)
 for fixture in fixtures.slice(0,2):
  for npc in fixture.module.npcs:
   var required:=int(npc.branches[0].guard.required_items[0])
   var r:=source_talk(b,npc)
   check(not choose(b,r,"yes").ok and not b.battle_open,"source entry item required")
   grant(b,required);grant(b,required)
   r=source_talk(b,npc)
   check(choose(b,r,"yes").ok and b.battle_open,"source dieact0 battle starts")
   if not b.battle_open:continue
   var before:Dictionary=b.session.snapshot()
   var ids:Array=b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))
   check(ids==npc.branches[0].guard.enemy_ids.map(func(id):return int(id)),"exact real source troop")
   b.save_path="user://missing-personal-guard/save.json"
   fight(b)
   check(b.session.snapshot()==before and not b.session._pending.is_empty(),"save failure restores every profile field and retains pending")
   check(not b.original_quests.npc_by_id(npc.id).is_empty(),"failed save does not hide guard")
   b.save_path="user://personal-guard.json"
   check(b.handle({"type":"battle_close"}).ok,"same terminal result saves and closes")
   check(b.original_quests.npc_by_id(npc.id).is_empty(),"successful save hides this character's guard")
   var item:int=2533 if required==2535 else 2428+ids[0]-513
   check(b.session.snapshot().original_items.count(item)==1,"source guaranteed drop delivered once")
   check(b.session.snapshot().original_items.count(required)==(1 if required==2535 else before.original_items.count(required)),"only steal1 removes one source item on victory")
   var after:Dictionary=b.session.snapshot()
   b.handle({"type":"battle_close"})
   check(b.session.snapshot()==after,"repeat close cannot redeliver loot or steal another item")
   now+=300;b.original_quests.refresh_npc_state()
   check(b.original_quests.npc_by_id(npc.id).is_empty(),"exactly300 seconds remains hidden")
   now+=1;b.original_quests.refresh_npc_state()
   check(not b.original_quests.npc_by_id(npc.id).is_empty(),"strictly more than300 restores guard")
   if required==2431:
    while required in b.session._profile.original_items:b.session.OriginalEquipment.remove(b.session._profile,required)
 var npc:Dictionary=fixtures[2].module.npcs[0]
 for item in [2760,2761,2762,2763,2764]:grant(b,item)
 var r:=source_talk(b,npc)
 r=choose(b,r,"yes")
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-personal-guard/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"NpcWarp reward save failure is atomic")
 check(not b.original_quests.npc_state.records.has(npc.id),"failed NpcWarp does not advance private counter")
 b.save_path="user://personal-guard.json"
 r=source_talk(b,npc);r=choose(b,r,"yes")
 check(choose(b,r,"ok").ok,"actual five-item source reward commits")
 var moved:Dictionary=b.original_quests.npc_by_id(npc.id)
 check(int(moved.get("map_id",0))==4000 and moved.get("cell",[])==[53,101],"first source NpcWarp point selected")
 check(b.session.snapshot().location==before.location,"NpcWarp moves NPC rather than player")
 b.original_quests.npc_state.defeated(str(fixtures[0].module.npcs[0].id),300)
 var again=Backend.new();install(again)
 check(again.load_profile(b.save_path),"real saved profile reads back")
 check(again.original_quests.npc_state.records.is_empty() and int(again.original_quests.npc_by_id(npc.id).map_id)==6000,"server restart resets runtime NPC position without changing save format")
 var state=PersonalState.new();var points:Array=[[1,2,3],[4,5,6],[7,8,9],[10,11,12]]
 for i in range(5):
  state.moved("source",points)
  check(int(state.snapshot().source.map_id)==int(points[i%4][0]),"source counter cycles all four points")
 check(not JSON.stringify(state.snapshot()).contains("counter"),"public snapshot omits private counter")
 b.free();again.free()
 await personal_lan()
 Encounters.configure_reviewed_drops(original)
 print("PERSONAL QUEST NPCS: %d failures"%failures)
 quit(1 if failures else 0)
func personal_lan()->void:
 var folder:="user://personal-npc-lan-%d"%OS.get_process_id()
 var hub=Hub.new(folder.path_join("accounts.json"));hub.tick=false;hub.backups=false;hub.share_dir=""
 root.add_child(hub);check(hub.start(),"personal state hub starts")
 for name in ["Alice","Bob"]:check(hub.accounts.create(name,"1234").ok,"real isolated character account")
 var server=Server.new(hub,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"personal NPC LAN ephemeral port")
 var snapshots:Array=[{}, {}, {}]
 for i in range(3):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link)
  link.message.connect(func(event):
   if event.get("type","") in ["snapshot","profile"]:snapshots[i]=event)
  link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.awaiting_login)),"three physical sockets open")
 for i in range(3):
  var answer:=[{}]
  links[i].login({"type":"login","name":"Alice" if i<2 else "Bob","pin":"1234"},func(reply):answer[0]=reply)
  check(await Wait.until(self,func():poll();return links[i].online),"devices log into authoritative character")
 var a=hub.backends.alice;var other=hub.backends.bob
 for backend in [a,other]:
  install(backend)
  backend.session._profile=fresh_profile()
 var npc:Dictionary=fixtures[0].module.npcs[0]
 grant(a,2431);source_talk(a,npc);a.original_quests.pending={}
 var r:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":npc.id})
 var started:Dictionary=await request(links[1],{"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 check(started.ok and a.battle_open,"same-character second device confirms source battle")
 var path:String=a.save_path;a.save_path="user://missing-personal-lan/save.json"
 fight(a)
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check(not a.original_quests.npc_by_id(npc.id).is_empty(),"LAN failed save keeps guard visible")
 a.save_path=path
 check((await request(links[1],{"type":"battle_close"})).ok,"other same-character device retries settlement")
 await request(links[0],{"type":"ping"});await request(links[2],{"type":"ping"})
 check(snapshots[0].derived.quest_npcs.get(npc.id,{}).get("hidden",false) and snapshots[1].derived.quest_npcs.get(npc.id,{}).get("hidden",false),"same character devices receive identical hidden NPC")
 check(not snapshots[2].derived.quest_npcs.has(npc.id) and not other.original_quests.npc_by_id(npc.id).is_empty(),"different character keeps guard visible")
 check(not (await request(links[0],{"type":"quest_talk","npc_id":npc.id})).ok,"hidden source NPC cannot be called through raw id")
 now+=301
 # A server lookup may expire the record before the next host tick.
 a.original_quests.npc_by_id(npc.id)
 a._process(0.0)
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 check(not snapshots[0].derived.quest_npcs.has(npc.id) and not snapshots[1].derived.quest_npcs.has(npc.id),"cooldown restoration broadcasts to both devices")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();hub.queue_free()
func fresh_profile()->Dictionary:
 var b=fresh();var result:Dictionary=b.session.snapshot();b.free();return result

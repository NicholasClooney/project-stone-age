extends "res://tests/original_fixed_guards_test.gd"
const State=preload("res://server/quest_npc_state.gd")
var npc:Dictionary={}
var now:=1000.0
func install(b,seed_value:int)->void:
 # A registered event35 may already have spawned during ProfileHub login.
 # Replace only this fixture identity and its runtime state, never other NPCs.
 b.quest_catalog.npcs=b.quest_catalog.npcs.filter(func(entry):return str(entry.id)!=str(npc.id))
 b.quest_catalog.npcs.append(npc.duplicate(true))
 if not 35 in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(35)
 var state=b.original_quests.npc_state
 var was_present:bool=state.records.erase(str(npc.id))
 state.spawn_attempts.erase(str(npc.id));b.quest_catalog.npc_overrides.erase(str(npc.id))
 if was_present:state.version+=1
 b.original_quests.npc_state.clock=func():return now
 b.original_quests.npc_state.spawn_rng.seed=seed_value
func seed_for(walkable:bool)->int:
 var rng:=RandomNumberGenerator.new()
 for candidate in range(100000):
  rng.seed=candidate
  var index:=rng.randi_range(0,6215)
  if (str(npc.source_spawn.walkable).substr(index,1)=="1")==walkable:return candidate
 return -1
func run()->void:
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-area-spawn.json"));npc=fixture.module.npcs[0]
 var b=Backend.new();install(b,seed_for(true));b.original_quests.refresh_npc_state()
 check(b.original_quests.npc_state.records.has(npc.id),"fixture starts with production-style already born NPC")
 b.original_quests.npc_state.records["unrelated-fixture"]={"map_id":100,"cell":[1,1]}
 b.original_quests.npc_state.spawn_attempts["unrelated-fixture"]=now
 b.quest_catalog.npc_overrides["unrelated-fixture"]={"map_id":100,"cell":[1,1]}
 install(b,seed_for(false))
 check(b.quest_catalog.npcs.filter(func(entry):return str(entry.id)==str(npc.id)).size()==1,"fixture replaces registered identity without duplicate NPC")
 check(b.original_quests.npc_state.records.has("unrelated-fixture") and b.original_quests.npc_state.spawn_attempts.has("unrelated-fixture") and b.quest_catalog.npc_overrides.has("unrelated-fixture"),"fixture reset preserves unrelated NPC runtime and projection")
 check(not b.quest_catalog.active_npcs().any(func(n):return n.id==npc.id),"area NPC absent until server chooses valid source point")
 var before:Dictionary=b.session.snapshot()
 check(b.original_quests.npc_by_id(npc.id).is_empty(),"one original blocked draw leaves NPC absent")
 b.original_quests.npc_state.spawn_rng.seed=seed_for(true)
 check(b.original_quests.npc_by_id(npc.id).is_empty(),"failed draw cannot retry repeatedly in same server second")
 now+=0.999
 check(b.original_quests.npc_by_id(npc.id).is_empty(),"retry waits full original one-second interval")
 now+=0.001
 var active:Dictionary=b.original_quests.npc_by_id(npc.id)
 check(not active.is_empty() and active.cell!=npc.cell,"next server second draws original area instead of fixed corner")
 if active.is_empty():b.free();quit(1);return
 var cell:Array=active.cell
 var index:=(int(cell[1])-180)*296+int(cell[0])-230
 check(str(npc.source_spawn.walkable).substr(index,1)=="1","chosen point follows original two-layer mapset collision")
 var map:Dictionary=preload("res://scripts/map_file.gd").load_map(b.session.world_catalog.file(100))
 check(map.blocked[int(cell[1])*int(map.width)+int(cell[0])]==0,"actual imported terrain permits chosen point")
 for offset in range(6216):
  if str(npc.source_spawn.walkable).substr(offset,1)=="1":
   if map.blocked[(180+int(offset/296))*int(map.width)+230+offset%296]!=0:check(false,"source birth candidates agree with actual imported terrain");break
 now+=100
 check(b.original_quests.npc_by_id(npc.id).cell==cell and b.session.snapshot()==before,"birth stays stable without changing save data")
 b.automation.position_changed(100,Vector2i(int(npc.cell[0]),int(npc.cell[1])))
 check(not b.handle({"type":"quest_talk","npc_id":npc.id,"cell":cell}).ok,"raw placeholder position cannot impersonate randomly born NPC")
 check(source_talk(b,active).ok,"real backend dialogue reachable only at actual born position")
 b.save_path="user://area-spawn.json";check(b.save(),"source spawn profile saves normally")
 var reloaded=Backend.new();install(reloaded,seed_for(false))
 check(reloaded.load_profile(b.save_path) and reloaded.original_quests.npc_state.records.is_empty(),"restart does not restore old birth from save; blocked fresh draw remains absent")
 b.free();reloaded.free()
 await lan_birth()
 print("ORIGINAL AREA SPAWN: %d failures"%failures);quit(1 if failures else 0)
func lan_birth()->void:
 var hub=Hub.new("user://area-spawn-lan-%d/accounts.json"%OS.get_process_id());hub.tick=false;hub.backups=false;hub.share_dir=""
 root.add_child(hub);check(hub.start(),"area real ProfileHub")
 for name in ["Alice","Bob"]:check(hub.accounts.create(name,"1234").ok,"area character created")
 var server=Server.new(hub,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"area ephemeral socket")
 var snapshots:Array=[{},{},{}]
 for i in range(3):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link)
  link.message.connect(func(event):
   if event.get("type","") in ["snapshot","profile"]:snapshots[i]=event)
  link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.awaiting_login)),"three area sockets")
 for i in range(3):
  links[i].login({"type":"login","name":"Alice" if i<2 else "Bob","pin":"1234"},func(_reply):pass)
  check(await Wait.until(self,func():poll();return links[i].online),"area login")
 var a=hub.backends.alice;var other=hub.backends.bob
 # Reproduce successful login-time creation even before event35 is registered.
 for backend in [a,other]:
  install(backend,seed_for(true));backend._publish()
 install(a,seed_for(true));install(other,seed_for(false))
 a._process(0.0);other._process(0.0)
 for link in links:await request(link,{"type":"ping"})
 check(snapshots[0].derived.quest_npcs.has(npc.id) and snapshots[0].derived.quest_npcs[npc.id]==snapshots[1].derived.quest_npcs[npc.id],"same-character devices receive identical actual birthplace")
 check(not snapshots[2].derived.quest_npcs.has(npc.id) and other.original_quests.npc_state.records.is_empty(),"other character independent unsuccessful draw")
 other.original_quests.npc_state.spawn_rng.seed=seed_for(true);now+=1;other._process(0.0)
 await request(links[2],{"type":"ping"})
 check(snapshots[2].derived.quest_npcs.has(npc.id),"later successful birth publishes on server tick")
 var public:Dictionary=snapshots[0].derived.quest_npcs[npc.id]
 check(public.keys().size()==2 and public.has("map_id") and public.has("cell"),"projection exposes no RNG or retry state")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();hub.queue_free()

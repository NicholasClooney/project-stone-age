extends "res://tests/lan_party_auto_test.gd"
## Position authority through real Backend commands, sockets, and the actual Hub.
const Backend=preload("res://server/backend.gd")
const Link=preload("res://network/ws_link.gd")
var links:Array=[]
const HERE:=[637,493]
func poll()->void:
 for link in links:link.poll(0.01)
func request(link,command:Dictionary)->Dictionary:
 var reply:Dictionary={}
 link.request(command,func(value):reply.merge(value,true))
 check(await Wait.until(self,func():poll();return reply.has("ok")),"socket reply received")
 return reply
func fresh():
 var b=Backend.new();b.set_process(false);b.automation.auto_tick=false
 b.handle({"type":"report_position","map_id":100,"cell":HERE});b.encounter_rng.seed=918
 return b
func frozen(b)->Array:
 return [b.automation.position_map,b.automation.position_cell,b.encounter_rng.state,b.encounter_catalog.pressure,b.encounter_serial,b.session._pending.duplicate(true),b.session.snapshot(),b.automation.hunt_map,b.automation.hunt_cell,b.automation.flow_map,b.automation.flow_cell,b.automation.flow_phase,b.automation.hunt_rolls,b.automation.settings.duplicate(true),b.original_quests.pending.duplicate(true),b.stationary.running]
func run()->void:
 var unknown=Backend.new();var seed:int=unknown.encounter_rng.state
 check(not unknown.handle({"type":"wild_encounter","map_id":100,"cell":HERE}).ok and unknown.encounter_rng.state==seed,"unknown authority cannot be initialized by wild command")
 check(not unknown.handle({"type":"auto_start","kind":"hunt","map_id":100,"cell":HERE}).ok and unknown.automation.position_map==-1,"auto start cannot initialize authority from client coordinates")
 unknown.free()
 var b=fresh()
 for type in ["wild_encounter","field_step","auto_start","auto","auto_step","stationary_encounters","stationary_keepalive"]:
  for point in [{"map_id":200,"cell":HERE},{"map_id":100,"cell":[638,493]},{"map_id":100,"cell":[1.5,493]},{"map_id":100,"cell":[]},{"map_id":"100","cell":HERE}]:
   var command:Dictionary={"type":type,"kind":"hunt","enabled":true,"encounter":true,"client":"party","arrival_kind":"walk","map_changed":false}
   command.merge(point,true);var before:Array=frozen(b)
   check(not b.handle(command).ok and frozen(b)==before,"%s rejects %s before RNG/pressure/pending/profile changes"%[type,str(point)])
 b.session._profile.no_random_encounters=true
 check(not b.handle({"type":"field_step","map_id":42,"cell":[34,35]}).ok,"disabled walking encounters do not bypass coordinate validation")
 b.session._profile.no_random_encounters=false
 check(b.handle({"type":"stationary_encounters","enabled":true}).ok,"real stationary mode starts for rejection-side-effect check")
 b.original_quests.pending={"token":"existing-window"}
 for fields in [{"position_map":42,"position_cell":[34,35]},{"hunt_map":42,"hunt_cell":[34,35]},{"flow_map":42,"flow_cell":[34,35],"flow_phase":"hunt"},{"settings":{"speed":4},"position_map":42}]:
  var before:Array=frozen(b)
  check(not b.handle({"type":"auto","name":"set","fields":fields}).ok and frozen(b)==before,"legacy set rejects internal/mixed fields atomically")
 b.original_quests.pending={};b.stationary.stop(b,"test")
 var before:Array=frozen(b)
 check(not b.handle({"type":"set_automation_settings","settings":{"training":{"hp":15},"position_map":42}}).ok and frozen(b)==before,"public settings reject mixed unknown field atomically")
 check(b.handle({"type":"set_automation_settings","settings":{"training":{"hp":15},"hunt":{"rate":1}}}).ok,"explicit public settings stay usable")
 # Compare the authoritative production roll with the untouched source generator.
 var reference=Backend.new();reference.encounter_rng.seed=918
 var expected:Dictionary=reference.encounter_catalog.roll(100,Vector2i(637,493),reference.encounter_rng,b.session.snapshot().original_items)
 check(b.handle({"type":"wild_encounter","map_id":100,"cell":HERE}).ok,"normal exact-position wild opens real battle")
 check(b.session._pending.enemies.size()==expected.enemies.size() and b.encounter_rng.state==reference.encounter_rng.state,"normal encounter retains original RNG distribution and troop size")
 before=frozen(b)
 check(not b.handle({"type":"wild_encounter","map_id":42,"cell":[34,35]}).ok and frozen(b)==before,"active frozen pending is preserved on forged encounter")
 b.abandon_battle()
 check(b.session._pending.is_empty(),"existing ordinary battle close remains usable")
 reference.free();b.free()
 for native in [false,true]:
  b=fresh()
  check(b.handle({"type":"auto_start","kind":"hunt","map_id":100,"cell":HERE,"filter":{"templates":[113,114],"level_one":true,"total":8,"offsets":[2,2,2,2],"auto_capture":false,"fast":native,"rate":0}}).ok,"authorized hunt starts before stale-position test")
  if native:b.automation._fast_process()
  var rolls:int=b.automation.hunt_rolls
  b.automation.position_changed(100,Vector2i(638,493))
  if native:b.automation._fast_process()
  else:b.handle({"type":"auto","name":"hunt_scan"})
  check(not b.automation.hunt_running and not b.battle_open and b.automation.hunt_rolls==rolls and not b.automation.fast_hunt.running(),"stale slow/native search cannot consume or open an off-position roll")
  b.free()
 await sockets()
 mining_retry()
 await party_position()
 print("WILD POSITION AUTHORITY: %d failures"%failures);quit(1 if failures else 0)
func sockets()->void:
 var b=fresh();root.add_child(b)
 var server=WsServer.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"real socket server starts on port zero")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two real devices connect")
 for link in links:await request(link,{"type":"ping"})
 for command in [{"type":"wild_encounter","map_id":42,"cell":[34,35]},{"type":"field_step","map_id":100,"cell":[638,493],"encounter":true},{"type":"auto","name":"set","fields":{"position_map":42,"hunt_map":42,"flow_phase":"hunt","settings":{"speed":4}}}]:
  var before:Array=frozen(b)
  check(not (await request(links[0],command)).ok and frozen(b)==before,"remote forgery rejected atomically")
 check((await request(links[1],{"type":"report_position","map_id":100,"cell":[638,493]})).ok,"second device confirms actual movement")
 var before:Array=frozen(b)
 check(not (await request(links[0],{"type":"wild_encounter","map_id":100,"cell":HERE})).ok and frozen(b)==before,"first device's old position cannot select old area")
 check((await request(links[0],{"type":"wild_encounter","map_id":100,"cell":[638,493]})).ok and b.battle_open,"current synchronized socket coordinates open normal battle")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free();await process_frame
func party_position()->void:
 dir="user://wild-position-party-%d"%OS.get_process_id();DirAccess.make_dir_recursive_absolute(dir)
 var made:Array=party_hub();var hub=made[0];var leader=hub.backends.alice;var member=hub.backends.bob
 check(hub.handle(1,{"type":"report_position","map_id":100,"cell":[601,500]}).ok and member.automation.position_cell==CELL,"production Hub follows member to leader's prior cell")
 var before:Array=frozen(leader)
 check(not hub.handle(1,{"type":"wild_encounter","map_id":42,"cell":[34,35]}).ok and frozen(leader)==before,"party leader cannot select a different map's troop")
 check(not hub.handle(2,{"type":"wild_encounter","map_id":100,"cell":[600,500]}).ok and not member.battle_open,"party member still cannot open an independent wild battle")
 check(hub.handle(1,{"type":"wild_encounter","map_id":100,"cell":[601,500]}).ok and leader.battle_open and member.battle_open,"legal followed party enters actual leader encounter together")
 check(drive(hub,func():return not leader.battle.snapshot().active,[1,2,3]),"real party commands finish the authoritative encounter")
 for connection in [1,2,3]:check(hub.handle(connection,{"type":"battle_close"}).ok,"each party member closes its saved ordinary result")
 await close(hub);remove_tree(dir)

func mining_retry()->void:
 var b=fresh()
 b.session.gm_raise_level(-1,80)
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 preload("res://server/original_equipment.gd").add(b.session._profile,2536)
 var entrance:Dictionary={}
 for link in b.quest_helper.places.links(300).values():
  if int(link.to_map)==31801 and not link.has("gate_source"):entrance=link;break
 check(not entrance.is_empty(),"real public miner entrance exists")
 if entrance.is_empty():b.free();return
 b.automation.position_changed(300,Vector2i(int(entrance.cell[0]),int(entrance.cell[1])))
 check(b.handle({"type":"report_position","map_id":31801,"cell":entrance.target}).ok,"permit fixture crosses actual original mine entrance")
 check(preload("res://tests/support/original_route_driver.gd").walk(b,31801,Vector2i(37,48),[31801]).ok,"continuous original route reaches mining point")
 var data:Dictionary=preload("res://scripts/map_file.gd").load_map(b.quest_helper.places.file(31801))
 check(not data.is_empty() and int(data.blocked[48*int(data.width)+37])==0,"ore test uses an actual walkable first-floor cell")
 check(b.encounter_catalog.area_at(31801,Vector2i(37,48))==b.encounter_catalog.area_at(31801,Vector2i(24,24)),"walkable ore fixture preserves original seed27 area")
 b.encounter_rng.seed=27
 var found:=false
 for attempt in range(100):
  var opened:Dictionary=b.handle({"type":"wild_encounter","map_id":31801,"cell":[37,48]})
  if not opened.ok:check(false,"seed27 original mining opens %s"%str(opened));break
  found=opened.troop.enemies.any(func(e):return int(e.source_enemy_id)==1043)
  if found:b.save_path="user://wild-authority-missing/save.json"
  for turn in range(100):
   if not b.battle.snapshot().active:break
   var target:int=0
   for j in range(b.battle._state.enemies.size()):
    if int(b.battle._state.enemies[j].hp)>0:target=j;break
   b.handle({"type":"battle_command","action":"attack","target":target})
  if found:
   var pending:Dictionary=b.session._pending.duplicate(true)
   check(not pending.is_empty() and not b.battle_state.get("settled",false),"actual source ore battle save failure keeps pending")
   check(not b.handle({"type":"battle_close"}).ok and b.session._pending==pending,"failed ore retry keeps exact frozen claims")
   var before:Array=frozen(b)
   check(not b.handle({"type":"wild_encounter","map_id":31806,"cell":[24,24]}).ok and frozen(b)==before,"fake encounter cannot overwrite failed pending settlement")
   check(not b.handle({"type":"wild_encounter","map_id":31801,"cell":[37,48]}).ok and frozen(b)==before,"even exact-position new encounter cannot reroll an unsettled battle")
   check(not b.handle({"type":"field_step","map_id":31801,"cell":[37,48],"encounter":true}).ok and frozen(b)==before,"walking cannot reroll or accumulate pressure during failed settlement")
   b.save_path=""
   check(b.handle({"type":"battle_close"}).ok and b.session.snapshot().original_items.count(2534)==1,"save retry commits one ore without reroll")
   var saved:Dictionary=b.session.snapshot();b.handle({"type":"battle_close"})
   check(b.session.snapshot()==saved,"close replay cannot duplicate ore")
   break
  b.handle({"type":"battle_close"})
 check(found,"unchanged seed27 real weighted mining reaches ore enemy")
 b.free()

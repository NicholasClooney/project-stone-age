extends "res://tests/golden_bui_ui_test.gd"
## Imported production world/catalog + genuine route before remote GameScene.
## No source fixture install, map relocation, helper teleport or arrival grants.
const FinalRoute=preload("res://tests/support/transmigration_arrival_route.gd")
const Candidates=preload("res://tests/transmigration_candidate_test.gd")
const KING="777/ten.arg@32021:31:28"
func real_guard(source:String)->bool:
 var npc:Dictionary=FinalRoute.npc(host,source)
 var opened:Dictionary=host.handle({"type":"quest_talk","npc_id":npc.id})
 if not check(opened.has("dialogue"),"imported source guard opens "+source):return false
 var started:Dictionary=host.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"})
 if not check(started.get("ok",false) and host.battle_open,"actual original guardian battle starts"):return false
 for i in range(100):
  var state:Dictionary=host.battle.snapshot()
  if not state.active:break
  var target:=0
  for j in range(state.enemies.size()):
   if int(state.enemies[j].hp)>0:target=j;break
  host.handle({"type":"battle_command","action":"attack","target":target})
 var closed:Dictionary=host.handle({"type":"battle_close"})
 return check(closed.get("ok",false) and closed.get("outcome","")=="win","actual saved guard outcome and original Warp")
func prepare()->bool:
 host=Backend.new();authority=host
 host.save_path="user://confirmation-scene-%d.json"%root.size.x
 host.session._profile.default_companions_claimed=true;host.session._profile.no_random_encounters=true
 host.session.gm_raise_level(-1,80)
 host.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 Session.Progression.refresh(host.session._profile.player)
 host.session._profile.player.hp=host.session._profile.player.max_hp
 host.session._profile.pets=[Candidates.pet(693,1),Candidates.pet(6,2)]
 host.session._profile.next_pet_id=3;host.session._profile.active_pet=1
 for e in [39,40,42,46]:Rules.set_flag(host.session._profile,"ended",e,true)
 for e in [48,49,50,51,52]:
  if e not in host.quest_catalog.enabled_events:host.quest_catalog.enabled_events.append(e)
 host.quest_helper.places.set_quest_catalog(host.quest_catalog)
 if not check(not host.original_quests.npc_by_id(KING).is_empty(),"actual private imported king exists"):return false
 # The only placement fixture is public outside300(102,228), in FinalRoute.entry.
 if not check(FinalRoute.entry(host),"product world original outer gate and cave entry"):return false
 if not check(FinalRoute.near(host,"300/sb_skr.arg",range(32001,32011)),"product-world walking and portals reach first guardian"):return false
 if not real_guard("300/sb_skr.arg"):return false
 if not check(FinalRoute.near(host,"genout/wpm_32016_31_39",range(32011,32017)) and FinalRoute.commit(host,"genout/wpm_32016_31_39"),"actual middle gate after first battle"):return false
 if not check(FinalRoute.near(host,"300/sb_skt.arg",range(32016,32021)),"product-world later portals reach final guardian"):return false
 if not real_guard("300/sb_skt.arg"):return false
 if not check(FinalRoute.near(host,"genout/wpm_32021_31_51",[32021]) and FinalRoute.commit(host,"genout/wpm_32021_31_51") and FinalRoute.near(host,"777/ten.arg",[32021]),"actual last door and original king approach"):return false
 var actual:Vector2i=host.automation.position_cell
 # Synchronize the already reached location for the new remote scene's snapshot.
 host.session.set_location(host.automation.position_map,actual.x,actual.y)
 return check(host.quest_arrival.check_action(host,host.original_quests.npc_by_id(KING),{},"SERVICE").is_empty(),"legal king eligibility exists without injected receipt")
func scene(url:String,width:int)->bool:
 var script=load("res://scripts/game.gd");script.server_url_override=url
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://confirmation-scene-%d.cfg"%width
 var catalog=preload("res://scripts/quest_catalog.gd").new()
 for e in [48,49,50,51,52]:
  if e not in catalog.enabled_events:catalog.enabled_events.append(e)
 world.world_catalog.set_quest_catalog(catalog)
 root.add_child(world)
 if not await ready(func():return world.link.online and not world.data.is_empty() and not world.area_transition_busy,"production remote GameScene loaded"):return false
 return check(world.backend==null and await Wait.settle(self,world),"GameScene is remote-only with settled authority position")
func run()->void:
 root.unfocusable=true;root.position=Vector2i(-10000,-10000);root.content_scale_size=Vector2i.ZERO
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 for viewport in [Vector2i(1280,900),Vector2i(390,844)]:
  root.size=viewport
  if not prepare():quit(1);return
  root.add_child(host)
  host.save_path="user://confirmation-scene-%d.json"%viewport.x
  var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
  if not check(server.start()==OK,"GameScene isolated actual WS server"):return
  var url:="ws://127.0.0.1:%d"%server.port
  if not await scene(url,viewport.x):return
  if not check(int(world.data.map_id)==32021 and world.cell==host.automation.position_cell,"production cave and actual reached cell render"):return
  await proof("%d-king-world"%viewport.x)
  if not await click_source(KING):return
  var view=world.world_travel.quest_dialogue.confirmation
  if not check(is_instance_valid(view) and view.preview.sacrifices[0].pet_id=="pet-1","actual king sprite click opens authoritative confirmation"):return
  if not check(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(view.card.get_global_rect()),"real scene confirmation fits viewport"):return
  await proof("%d-king-preview"%viewport.x)
  if not await click(view.confirm):return
  if not await ready(func():return int(world.session.snapshot().player.transmigration)==1 and int(world.data.get("map_id",-1))==1006 and world.cell==Vector2i(15,22) and not world.area_transition_busy,"actual confirmation returns GameScene to original village"):return
  if not check(not world.paused_input and not world.world_travel.overlay.visible,"confirmation releases input after real map transition"):return
  await proof("%d-village-return"%viewport.x)
  var committed:Dictionary=host.session.snapshot()
  if not check(committed.pets.size()==2 and not committed.pets.any(func(p):return p.pet_id=="pet-1") and committed.rebirth.last_transaction!="","real source pet consumed and transaction persisted"):return
  world.link.close();world.music.stop();world.effect.stop();world.queue_free();await process_frame
  if not await scene(url,viewport.x):return
  if not await ready(func():return int(world.data.get("map_id",-1))==1006 and world.cell==Vector2i(15,22) and not world.area_transition_busy,"reconnected GameScene reopens actual village"):return
  check(host.session.snapshot()==committed and int(world.session.snapshot().player.transmigration)==1,"reconnect does not replay transaction or reward")
  await proof("%d-village-reconnect"%viewport.x)
  world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free();await process_frame
 print("TRANSMIGRATION CONFIRMATION GAMESCENE: %d failures"%failures);quit(1 if failures else 0)

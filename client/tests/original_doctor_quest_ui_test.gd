extends SceneTree
const CaveRoute=preload("res://tests/support/legacy_cave_route.gd")
const Backend=preload("res://server/backend.gd")
const WsServer=preload("res://server/ws_server.gd")
const Wait=preload("res://tests/support/wait.gd")
const Rules=preload("res://server/original_quests.gd")
const DOCTOR="sainasu/event/event15_1"
const ASSISTANT="sainasu/event/event15_2"
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func click(world,id:String) -> void:
 var travel=world.world_travel
 var entries:Array=travel.entries.filter(func(entry):return str(entry.get("id",""))==id)
 check(entries.size()==1,"real imported remote NPC in travel entries "+id)
 if entries.is_empty():return
 var index:int=travel.entries.find(entries[0])
 var sprite=travel.sprites[index]
 check(sprite.texture!=null,"remote original NPC texture loaded")
 check(travel.handle_click(sprite.to_global(sprite.get_rect().get_center())),"actual sprite click starts approach")
 check(await Wait.until(self,func():return travel.quest_dialogue.active and not travel.quest_dialogue.busy),"remote click opens original dialogue")
func close(world) -> void:
 world.world_travel.quest_dialogue.close()
 await Wait.settle(self,world)
func confirm(world) -> void:
 var dialogue=world.world_travel.quest_dialogue
 dialogue.choose("yes")
 check(await Wait.until(self,func():return dialogue.active and not dialogue.busy),"remote yes displays original thanks")
 dialogue.choose("ok")
 check(await Wait.until(self,func():return not dialogue.active) and await Wait.settle(self,world),"remote final OK settles")
func walk_to_npc(world,id:String)->void:
 var npc:Dictionary=world.world_travel.entries.filter(func(n):return str(n.id)==id)[0]
 for delta in preload("res://scripts/npc_interaction.gd").offsets():
  var goal:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))+delta
  var path:Array[Vector2i]=world.travel_router._path_to(goal)
  if path.is_empty():continue
  world.walk_to(goal)
  check(await Wait.until(self,func():return world.cell==goal and not world.moving) and await Wait.settle(self,world),"actual client walks between nearby original NPCs")
  return
 check(false,"original NPC has a walkable approach")
func run() -> void:
 var b=Backend.new();root.add_child(b)
 b.session._profile.default_companions_claimed=true
 b.session.gm_raise_level(-1,16)
 b.session._profile.no_random_encounters=true
 check(CaveRoute.approach(b,b.original_quests.npc_by_id(DOCTOR)).ok,"real six-floor route establishes UI fixture arrival")
 var server=WsServer.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"doctor server listens on ephemeral port")
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 var world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://doctor-ui-remote.cfg"
 root.add_child(world)
 check(await Wait.until(self,func():return not world.data.is_empty() and world.link.online) and await Wait.settle(self,world),"remote doctor world connects")
 check(world.backend==null,"remote UI contains no backend")
 await walk_to_npc(world,DOCTOR)
 await click(world,DOCTOR)
 check(world.world_travel.body.text.contains("我是在这儿研究动物"),"original doctor REQUEST text rendered")
 await confirm(world)
 check(Rules.flag(world.session.snapshot(),"now",15),"remote request sets server NOW15")
 await walk_to_npc(world,ASSISTANT)
 await click(world,ASSISTANT)
 check(world.world_travel.body.text.contains("１５级"),"assistant original capture and raising advice visible")
 await close(world)
 check(b.session.gm_grant_pet(74),"native remote return fixture birth")
 var pet_id:String=b.session._profile.pets[-1].pet_id
 b.session.level_pet_to(pet_id,15);b.publish();await Wait.settle(self,world)
 await walk_to_npc(world,DOCTOR)
 await click(world,DOCTOR)
 check(world.world_travel.body.text.contains("鲁尼帖斯先拿好"),"original ACCEPT explains first matching pet")
 var dialogue=world.world_travel.quest_dialogue
 dialogue.choose("yes");await Wait.until(self,func():return dialogue.active and not dialogue.busy)
 check(world.session.snapshot().pets.size()==1 and world.session.snapshot().original_items.is_empty(),"remote thanks holds source pet until OK")
 dialogue.choose("ok");await Wait.until(self,func():return not dialogue.active);await Wait.settle(self,world)
 check(world.session.snapshot().pets.is_empty() and world.session.snapshot().original_items.size()==1 and Rules.flag(world.session.snapshot(),"ended",15),"remote final OK atomically exchanges pet and random reward")
 await click(world,DOCTOR);await confirm(world)
 check(Rules.flag(world.session.snapshot(),"now",16),"real remote second-stage request")
 b.session.gm_grant_pet(191);pet_id=b.session._profile.pets[-1].pet_id;b.session.level_pet_to(pet_id,30);b.publish();await Wait.settle(self,world)
 await click(world,DOCTOR);await confirm(world)
 check(world.session.snapshot().pets.size()==1 and world.session.snapshot().pets[0].species=="original_173" and world.session.snapshot().pets[0].level==1 and Rules.flag(world.session.snapshot(),"ended",16),"remote second click exchanges Beluka for original Lv1 Bukubuku")
 world.quest_helper_menu.open_menu()
 check(world.quest_helper_menu.find_child("QuestHelper_6",true,false).text.contains("已完成") and world.quest_helper_menu.find_child("QuestHelper_7",true,false).text.contains("已完成"),"remote helper shows both original journal jobs completed")
 world.quest_helper_menu.close_menu()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();b.queue_free()
 await process_frame;await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path("user://doctor-ui-remote.cfg"))
 print("ORIGINAL DOCTOR QUEST UI: %d failures"%failures)
 quit(1 if failures else 0)

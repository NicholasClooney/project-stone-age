extends SceneTree
const Backend=preload("res://server/backend.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func run() -> void:
 var backend=Backend.new()
 backend.session._profile.player.gold=10000
 root.add_child(backend)
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
 root.add_child(server)
 check(server.start()==OK,"isolated real server listens on port0")
 var script=load("res://scripts/game.gd")
 script.server_url_override="ws://127.0.0.1:%d"%server.port
 var world=load("res://scenes/main.tscn").instantiate()
 script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://charm-ui-remote.cfg"
 root.add_child(world)
 check(await Wait.until(self,func():return not world.data.is_empty() and world.link.online) and await Wait.settle(self,world),"remote startup settles")
 check(world.backend==null and not world.link.is_local(),"remote game owns no backend")
 for map_id in [1005,2005]:
  backend.session._profile.player.charm=60
  backend.publish()
  var npc:Dictionary=backend.original_quests.npc_by_id("original/charm/%d"%map_id)
  world.load_area_id(map_id,Vector2i(npc.cell[0]-1,npc.cell[1]))
  await Wait.settle(self,world)
  var travel=world.world_travel
  var index:int=travel.entries.find(travel.entries.filter(func(entry):return str(entry.get("id",""))==str(npc.id))[0])
  check(travel.sprites[index].texture!=null and travel.blocks(Vector2i(npc.cell[0],npc.cell[1])),"real sprite and navigation block")
  check(world.world_catalog.village_for(map_id)==(1000 if map_id==1005 else 2000),"original hospital village ownership")
  check(travel.handle_click(travel.sprites[index].to_global(travel.sprites[index].get_rect().get_center())),"real remote sprite click")
  var dialogue=travel.quest_dialogue
  check(await Wait.until(self,func():return dialogue.active and not dialogue.busy),"server start choices arrive")
  check(dialogue.buttons.size()==2 and dialogue.buttons[0].text=="给我魅力" and dialogue.buttons[1].text=="什麽也不做","original choices visible")
  dialogue.buttons[0].pressed.emit()
  check(await Wait.until(self,func():return not dialogue.busy and travel.body.text.contains("需要")),"real button obtains fee confirmation")
  var before:Dictionary=world.session.snapshot()
  dialogue.buttons[0].pressed.emit()
  check(await Wait.until(self,func():return not dialogue.busy and world.session.snapshot().player.charm==65),"remote YES commits base charm")
  check(world.session.snapshot().player.gold==before.player.gold-200 and travel.body.text.contains("真的变得好可爱"),"server stone charge and original character-type text")
  dialogue.buttons[0].pressed.emit()
  check(await Wait.until(self,func():return not dialogue.active),"original OK closes")
  var events:Dictionary=world.session.snapshot().original_events.duplicate(true)
  check(events==before.original_events,"service creates no quest flags or journal")
 world.music.stop();world.effect.stop();world.queue_free()
 server.queue_free();backend.queue_free()
 await process_frame
 print("ORIGINAL CHARM UI: ","PASS" if failures==0 else "FAIL")
 quit(1 if failures else 0)

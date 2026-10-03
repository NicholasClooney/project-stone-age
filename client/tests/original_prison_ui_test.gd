extends "res://tests/transmigration_fire_ui_test.gd"
const Prison=preload("res://server/original_prison_service.gd")
func bounded()->bool:
 var d=world.world_travel.quest_dialogue
 var viewport:=Rect2(Vector2.ZERO,Vector2(root.size))
 if not check(viewport.encloses(d.panel.get_global_rect()) and viewport.encloses(d.service_scroll.get_global_rect()),"actual desktop/mobile viewport contains dialogue and scroll"):return false
 for button in d.service_controls.buttons:
  if not check(button.size.y>=44,"service touch target at least44px"):return false
 return true
func run()->void:
 root.unfocusable=true;root.content_scale_size=Vector2i.ZERO
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 for viewport in [Vector2i(1280,800),Vector2i(390,844)]:
  root.size=viewport
  host=Backend.new();root.add_child(host)
  host.session._profile.default_companions_claimed=true;host.session._profile.no_random_encounters=true
  host.session._profile.player.gold=11
  for event in range(48,53):
   if not event in host.quest_catalog.enabled_events:host.quest_catalog.enabled_events.append(event)
  # Isolated public service fixture; no reward/route arrival credential granted.
  # Entrance endpoints/maze scope are covered by the map/arrival owner suites.
  host.automation.position_changed(117,Vector2i(7,5));host.session.set_location(117,7,5)
  var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
  if not check(server.start()==OK,"prison actual port0 UI server"):return
  var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
  world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
  world.profile_persistence=false;world.viewer_prefs_path="user://prison-ui-%d.cfg"%viewport.x
  var catalog=preload("res://scripts/quest_catalog.gd").new()
  for event in range(48,53):
   if not event in catalog.enabled_events:catalog.enabled_events.append(event)
  world.world_catalog.set_quest_catalog(catalog);root.add_child(world)
  if not await ready(func():return not world.data.is_empty() and world.link.online and int(world.data.get("map_id",0))==117,"actual prison rendered"):return
  if not check(world.backend==null and await Wait.settle(self,world),"prison remote authority only"):return
  if not await click_source("genout/wpm_117_6_5") or not bounded():return
  var dialogue=world.world_travel.quest_dialogue
  if not check(str(dialogue.body.text).contains("10石币"),"actual fixed10 price readable"):return
  await proof("prison-%d-01-fixed-quote"%viewport.x)
  if not await choose("no"):return
  if not check(host.session.snapshot().player.gold==11 and host.automation.position_map==117,"cancel retains money and prison position"):return
  if not await click_source("genout/wpm_117_6_5") or not await choose("yes"):return
  if not await ready(func():return int(world.data.get("map_id",0))==110 and not world.area_transition_busy,"paid original110 destination rendered"):return
  if not check(await Wait.settle(self,world) and host.session.snapshot().player.gold==1 and host.session.snapshot().location=={"map_id":110,"x":23,"y":27},"actual click atomically pays10 and moves"):return
  await proof("prison-%d-02-paid"%viewport.x)
  if not await click_source("genout/wpm_110_37_20") or not bounded():return
  await proof("prison-%d-03-free-birth"%viewport.x)
  if not await choose("yes"):return
  if not await ready(func():return int(world.data.get("map_id",0))==1006 and not world.area_transition_busy,"free birth destination rendered"):return
  if not check(await Wait.settle(self,world) and host.session.snapshot().player.gold==1 and host.session.snapshot().location=={"map_id":1006,"x":15,"y":22},"actual guide click returns birth village without logout"):return
  await proof("prison-%d-04-birth"%viewport.x)
  world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free();await process_frame
 print("ORIGINAL PRISON UI: %d failures"%failures);quit(1 if failures else 0)

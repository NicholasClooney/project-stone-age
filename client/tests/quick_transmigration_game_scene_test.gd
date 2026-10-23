extends "res://tests/quick_transmigration_remote_test.gd"
## Production menu + real WebSocket authority, isolated user:// save, no GM command.
var world
func ready(condition: Callable, label: String) -> bool:
 var ok: bool=await Wait.until(self,condition)
 check(ok,label)
 if not ok:quit(1)
 return ok
func click(button: Control) -> void:
 var point: Vector2=button.get_global_transform_with_canvas()*(button.size/2)
 var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
 check(root.gui_get_hovered_control()==button,"real GUI target: "+str(button.name))
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
  event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await process_frame
func open_menu():
 check(await Wait.settle(self,world),"settle authority before menu action")
 if world.adventure_menu.visible:world.close_adventure_menu()
 world.show_adventure_menu("status")
 await process_frame
 await click(world.adventure_menu.panel.get_node("QuickTransmigration"))
 return world.adventure_menu.quick_transmigration_menu
func run() -> void:
 root.unfocusable=true;root.position=Vector2i(-10000,-10000);root.content_scale_size=Vector2i.ZERO
 for viewport in [Vector2i(1280,900),Vector2i(390,844)]:
  root.size=viewport
  var b=fresh();b.save_path="user://quick-rebirth-scene-%d.json"%viewport.x;root.add_child(b)
  var before: Dictionary=b.session.snapshot()
  var server=Server.new(b,0,"127.0.0.1");root.add_child(server)
  check(server.start()==OK,"isolated real WebSocket authority")
  var url:="ws://127.0.0.1:%d"%server.port
  var script=load("res://scripts/game.gd");script.server_url_override=url
  world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
  world.profile_persistence=false;world.viewer_prefs_path="user://quick-rebirth-scene-%d.cfg"%viewport.x;root.add_child(world)
  if not await ready(func():return world.link.online and not world.data.is_empty() and not world.area_transition_busy,"production remote scene ready"):return
  check(world.backend==null and not b.admin and await Wait.settle(self,world),"ordinary player UI has no backend or admin")
  before=b.session.snapshot()
  var view=await open_menu()
  check(is_instance_valid(view) and view.modes.selected==1 and view.bonus.button_pressed,"real ordinary player entry defaults to120/20")
  if not is_instance_valid(view):quit(1);return
  check(view.modes.is_item_disabled(0) and view.eligibility.text.contains("低于80"),"current below80 visibly disabled in real scene")
  await click(view.refresh)
  if not await ready(func():return not view.busy,"server preview returned"):return
  check(not view.token.is_empty() and not view.confirm.disabled,"real server preview enables confirm")
  if view.token.is_empty():print(view.status.text);quit(1);return
  check(b.quick_transmigration.pending.options.level_mode=="120" and b.quick_transmigration.pending.options.bonus_quests==20 and b.quick_transmigration.pending.options.allocation_stats.size()==4,"authority receives default full options")
  check(b.session.snapshot()==before,"preview does not alter real profile")
  var candidate: Dictionary=b.quick_transmigration.pending.candidate.duplicate(true)
  check(candidate.player.level==1 and candidate.player.transmigration==1,"candidate only one turn atLv1")
  await click(view.cancel)
  if not await ready(func():return b.quick_transmigration.pending.is_empty(),"cancel reaches authority"):return
  check(b.session.snapshot()==before,"cancel leaves all assets and history unchanged")
  view=await open_menu();view.modes.select(2);view._options_changed()
  await click(view.refresh)
  if not await ready(func():return not view.busy,"130 preview returned"):return
  check(not view.token.is_empty() and b.quick_transmigration.pending.options.level_mode=="130" and b.session.snapshot()==before,"130 simulation is candidate-only")
  check((int(b.quick_transmigration.pending.candidate.rebirth.equation)&65535)==130 and Session.MAX_LEVEL==120,"130 recorded for inheritance without changing natural120 cap")
  # Another device supersedes a valid visible token without a profile change.
  var old: String=view.token
  var other=Link.new(url);links.append(other);other.connect_now()
  if not await ready(func():poll();return other.online,"second device connected"):return
  await request(other,{"type":"ping"})
  var newer: Dictionary=await request(other,packet())
  check(newer.has("quick_transmigration") and newer.quick_transmigration.token!=old,"second device supersedes UI token")
  await click(view.confirm)
  if not await ready(func():return not view.busy,"expired confirmation returns"):return
  check(view.stale and view.confirm.disabled and view.status.text.contains("过期") and b.session.snapshot()==before,"expired UI token rejected with visible reason and no mutation")
  if viewport.x==1280:
   view.modes.select(1);view._options_changed()
  await click(view.refresh)
  if not await ready(func():return not view.busy,"fresh confirmation preview returned"):return
  candidate=b.quick_transmigration.pending.candidate.duplicate(true)
  check((int(candidate.rebirth.equation)&65535)==(120 if viewport.x==1280 else 130),"desktop confirms default120; mobile confirms explicit130")
  var token: String=view.token
  await click(view.confirm)
  if not await ready(func():return int(world.session.snapshot().player.transmigration)==1 and int(world.data.get("map_id",-1))==int(candidate.location.map_id) and not world.area_transition_busy,"confirmed remote scene returns to birth village"):return
  var committed: Dictionary=b.session.snapshot()
  check(committed.player.level==1 and committed.player.transmigration==1 and committed.pets.size()==before.pets.size()+1 and committed.rebirth.last_transaction==token,"exactly one turn, Lv1 and one reward")
  check(committed.player.base_stats==candidate.player.base_stats and committed.player.stat_points==10,"authority commits exact preview inheritance and new free points")
  check(not is_instance_valid(world.adventure_menu.quick_transmigration_menu),"successful operation closes overlay")
  var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(b.save_path))
  check(int(saved.player.level)==1 and int(saved.player.transmigration)==1 and saved.pets.size()==committed.pets.size(),"real isolated save contains one settlement")
  var duplicate: Dictionary=await request(other,{"type":"quick_transmigration","action":"confirm","token":token})
  check(not duplicate.ok and b.session.snapshot()==committed,"duplicate confirmation does not grant another pet or turn")
  # Fresh preview becomes stale on a real authority profile push.
  view=await open_menu();await click(view.refresh)
  if not await ready(func():return not view.busy,"post-turn preview available"):return
  await request(other,{"type":"allocate_stat","stat":"strength","amount":1})
  if not await ready(func():return view.stale,"other-device state update invalidates preview"):return
  check(view.confirm.disabled,"state-changed UI confirmation disabled")
  await click(view.cancel)
  other.close();links=[];world.link.close();world.music.stop();world.effect.stop();world.queue_free()
  server.stop();server.queue_free();b.queue_free();await process_frame
 print("QUICK TRANSMIGRATION GAMESCENE: %d failures"%failures);quit(1 if failures else 0)

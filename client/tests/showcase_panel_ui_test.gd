extends "res://tests/quest_helper_ui_test.gd"
var visual:=false
const SHOTS="/private/tmp/ui-panel-followups-shots/"
func shot(id:String)->void:
 if not visual:return
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(SHOTS+id+".png")
func run()->void:
 root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO
 visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
 if visual:DirAccess.make_dir_recursive_absolute(SHOTS)
 world=load("res://scenes/main.tscn").instantiate()
 world.profile_persistence=false;world.viewer_prefs_path="user://showcase-panel.cfg"
 root.add_child(world)
 if not await ready(func():return not world.data.is_empty(),"World ready"):return
 world.backend.set_process(false)
 world.set_process(false)
 var ticker=world.showcase_ticker
 var status:Dictionary={"flow":{"showcase":true,"phase":"hunt","log":[{"kind":"found","text":"找到凯比，等待捕获"},{"kind":"captured","text":"已捕获凯比，保留至宠物仓库"}]}}
 for dimensions in [Vector2i(1280,720),Vector2i(390,844)]:
  root.size=dimensions
  var tag:="%dx%d"%[dimensions.x,dimensions.y]
  ticker.on_status({"flow":{"showcase":false}})
  ticker.on_status(status)
  if not await ready(func():return ticker.visible and ticker.size.x<=dimensions.x,"Responsive ticker visible"):return
  await process_frame
  var before:Dictionary=world.session.snapshot().duplicate(true)
  if not await click(ticker.fold_button):return
  if not check(ticker.minimized and ticker.visible and not ticker.content.visible,"Running true click minimizes viewer"):return
  if not check(world.session.snapshot()==before and status.flow.phase=="hunt","Viewer does not mutate session or requested automation status"):return
  await shot(tag+"-compact")
  if not await click(ticker.fold_button):return
  if not check(not ticker.minimized and ticker.content.visible,"True click restores log"):return
  await shot(tag+"-expanded")
  preload("res://server/original_quests.gd").set_flag(world.backend.session._profile,"ended",18,true)
  world.backend.session._profile.original_items=[2478]
  world.backend.publish()
  world.quest_helper_menu.detail_open=false
  world.quest_helper_menu.open_menu()
  var wood:Dictionary={}
  for q in world.quest_helper_menu.model().get("quests",[]):
   if int(q.event)==18:wood=q
  if not check(not wood.is_empty() and wood.status=="进行中","Wood permit projection reaches real UI as active"):return
  var wood_button=world.quest_helper_menu.find_child("QuestHelper_%d"%int(wood.id),true,false)
  if not await click(wood_button):return
  if not check(world.quest_helper_menu.selected_id==int(wood.id),"True click selects wood in current tasks"):return
  if not await ready(func():return not ticker.visible,"Quest helper suppresses ticker"):return
  await shot(tag+"-quest-uncovered")
  world.quest_helper_menu.close_menu()
  for kind in ["inventory","pets"]:
   world.adventure_menu.open_menu(kind)
   world.quest_helper_menu.open_menu()
   if not await click(world.quest_helper_menu.find_child("QuestHelperClose",true,false)):return
   if not check(not world.quest_helper_menu.visible,"Top quest close receives click above "+kind):return
   world.adventure_menu.hide()
  world.helper_menu.open_menu()
  if not await click(world.helper_menu.find_child("HelperQuest",true,false)):return
  if not check(world.quest_helper_menu.visible,"Game helper actual button opens quest helper"):return
  if not await click(world.quest_helper_menu.find_child("QuestHelperClose",true,false)):return
  world.helper_menu.hide()
  # Three actual widget implementations, with isolated presentation fixtures.
  var other=preload("res://scripts/automation_chip.gd").new()
  world.ui_root.add_child(other);other.setup(world,"自动抓宠",0,func():pass);other.show()
  world.state.derived.quest_auto={"running":true,"quest_id":11,"message":"行走到原任务入口"}
  var chip=world.find_child("QuestAutoChip",true,false)
  if not await ready(func():return chip.visible and ticker.visible and not chip.get_global_rect().intersects(other.get_global_rect()),"Task and hunt chips stack"):return
  if not check(not ticker.get_global_rect().intersects(chip.get_global_rect()) and not ticker.get_global_rect().intersects(other.get_global_rect()),"Ticker does not overlap either automation chip"):return
  await shot(tag+"-three-panels")
  if not await click(ticker.fold_button):return
  if not check(ticker.minimized,"Ticker fold works alongside chips"):return
  if not await click(chip.restore_button):return
  if not await ready(func():return world.quest_helper_menu.visible and not ticker.visible,"Task chip restores helper without progress obstruction"):return
  await shot(tag+"-chip-restored-helper")
  if not await click(world.quest_helper_menu.find_child("QuestHelperClose",true,false)):return
  world.state.derived.quest_auto={"running":false}
  other.queue_free()
  status.flow.phase="idle";ticker.on_status(status)
  if not await ready(func():return ticker.visible and ticker.close_button.visible,"Stopped run can close"):return
  await shot(tag+"-stopped")
  if not await click(ticker.close_button):return
  ticker.on_status(status);ticker._process(0)
  if not check(not ticker.visible and ticker.dismissed,"Repeated idle publications do not resurrect dismissed panel"):return
  status.flow.phase="hunt";ticker.on_status(status)
  if not check(ticker.visible and not ticker.dismissed and not ticker.minimized,"Next run automatically restores progress"):return
 world.queue_free()
 await process_frame
 print("SHOWCASE PANEL UI: PASS")
 quit(0)

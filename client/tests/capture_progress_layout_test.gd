extends "res://tests/quest_helper_ui_test.gd"
## Server-owned log fixtures delivered over a real socket to the production UI.
## They isolate Container updates; they do not claim a natural capture replay.
const PROOF="/private/tmp/tmux-agents/capture-progress-layout/"
var authority: Node
var visual:=false
var baseline:=false
var sampled_heights:Array[float]=[]
var sampling:=false
func sample_layout()->void:
 if sampling and is_instance_valid(world) and world.showcase_ticker.visible:sampled_heights.append(world.showcase_ticker.size.y)
func proof(label:String)->void:
 if not visual:return
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(PROOF+label+".png")==OK,"Rendered "+label)
func publish_log(serial:int)->void:
 authority.automation.flow_showcase=true
 authority.automation.flow_phase="hunt"
 authority.automation.showcase_log=[
  {"kind":"capture","text":"开始捕获：布鲁顿 · 第597058917组"},
  {"kind":"captured","text":"捕获成功：布鲁顿 pet-6440，开始练到120级。"},
  {"kind":"level","text":"布鲁顿 pet-6440 练到120级：攻283 防167 敏175 血1257 · 三围合625 · 与预测一致"},
  {"kind":"kept","text":"布鲁顿 pet-6440 留下：防御第2"}]
 authority.automation.showcase_dropped_count=serial
 authority.automation.showcase_dropped_species={"1":serial}
 authority.automation._emit_status()
func run()->void:
 baseline="--baseline" in OS.get_cmdline_user_args()
 visual="--visual-review" in OS.get_cmdline_user_args()
 process_frame.connect(sample_layout)
 root.unfocusable=true;root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO
 if visual and not check(DisplayServer.get_name()!="headless","Real renderer required"):return
 authority=preload("res://server/backend.gd").new()
 root.add_child(authority)
 var server=preload("res://server/ws_server.gd").new(authority,0,"127.0.0.1")
 root.add_child(server)
 if not check(server.start()==OK,"Ephemeral server"):return
 var script=load("res://scripts/game.gd")
 script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate()
 script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://capture-progress-layout.cfg"
 root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Remote world ready"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Actual remote viewer has no backend"):return
 authority.set_process(false)
 var ticker=world.showcase_ticker
 if not baseline:
  authority.automation.flow_showcase=true;authority.automation.flow_phase="hunt"
  authority.automation.showcase_log=[];authority.automation._emit_status()
  if not check(await Wait.settle(self,world),"Started run before first log"):return
  if not await ready(func():return is_instance_valid(world.pet_hunt_menu.chip) and world.pet_hunt_menu.chip.visible and not ticker.visible,"Running hunt always has one entry before first log"):return
 for dimensions in [Vector2i(1280,720),Vector2i(390,844)]:
  root.size=dimensions
  if not await ready(func():return world.get_viewport_rect().size==Vector2(dimensions),"Viewport resized"):return
  var tag:="%dx%d"%[dimensions.x,dimensions.y]
  publish_log(23)
  if not check(await Wait.settle(self,world),"Published log received"):return
  world.pet_hunt_menu.minimize()
  if not baseline:
   if ticker.visible:
    if not await click(ticker.fold_button):return
   if not await click(world.pet_hunt_menu.chip.restore_button):return
  if not await ready(func():return ticker.visible and ticker.content.size.y>0,"Expanded production ticker"):return
  await proof(("before-" if baseline else "after-")+tag+"-expanded")
  sampled_heights.clear();sampling=true
  var heights:Array[float]=[]
  for serial in range(24,40):
   publish_log(serial)
   if not check(await Wait.settle(self,world),"Updated log received"):return
   heights.append(ticker.size.y)
   if serial==24:await proof(("before-" if baseline else "after-")+tag+"-update-%d"%serial)
  sampling=false
  print("LAYOUT ",tag," heights=",heights," content=",ticker.content.size," panel=",ticker.size)
  if baseline:continue
  if not check(not sampled_heights.is_empty() and sampled_heights.max()-sampled_heights.min()<1 and sampled_heights.max()<360 and heights.max()-heights.min()<1,"Repeated server log updates keep bounded stable height"):return
  if not check(ticker.summary.text.contains("遇敌") and ticker.summary.text.contains("总用时"),"Expanded detail retains live counters from the single bar"):return
  if not check(not world.pet_hunt_menu.chip.visible and Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(ticker.get_global_rect()),"Expanded detail is the sole progress view and fits viewport"):return
  var before:Dictionary=world.session.snapshot().duplicate(true)
  if not await click(ticker.fold_button):return
  if not check(not ticker.visible and world.pet_hunt_menu.chip.visible and world.session.snapshot()==before,"Running fold only changes the viewer; one bar remains"):return
  if not check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(world.pet_hunt_menu.chip.get_global_rect()),"Collapsed bar fits actual viewport"):return
  authority.quest_auto.running=true
  authority.quest_auto.quest_id=11
  authority.quest_auto.message="正在走向任务入口"
  authority.publish()
  if not check(await Wait.settle(self,world),"Other task status delivered"):return
  var quest_chip=world.find_child("QuestAutoChip",true,false)
  if not await ready(func():return quest_chip.visible and not quest_chip.get_global_rect().intersects(world.pet_hunt_menu.chip.get_global_rect()),"Real task chip stacks above collapsed capture bar"):return
  await proof("after-"+tag+"-collapsed")
  authority.quest_auto.running=false;authority.publish()
  if not check(await Wait.settle(self,world),"Other task ends"):return
  if not await click(world.pet_hunt_menu.chip.restore_button):return
  if not await click(ticker.actions.get_child(1)):return
  if not await ready(func():return world.adventure_menu.visible and not ticker.visible and not world.pet_hunt_menu.chip.visible,"History covers both progress forms"):return
  world.close_adventure_menu()
  if not await ready(func():return ticker.visible,"Closing history restores detail"):return
  if not await click(ticker.actions.get_child(0)):return
  if not await ready(func():return world.pet_hunt_menu.visible and not ticker.visible,"Settings accessible from detail"):return
  world.pet_hunt_menu.minimize()
  if not await click(world.pet_hunt_menu.chip.restore_button):return
  authority.automation.showcase_log=[{"kind":"level","text":"很长的抓宠进度；保留完整结果与属性说明。".repeat(120)}]
  authority.automation._emit_status()
  if not check(await Wait.settle(self,world),"Long authoritative line delivered"):return
  if not await ready(func():return ticker.scroll.get_v_scroll_bar().visible,"Long details use internal scroll"):return
  if not check(ticker.size.y<=344 and ticker.scroll.size.y<=180,"Long log cannot grow outer panel beyond cap"):return
  var point:Vector2=ticker.scroll.get_global_rect().get_center()
  var motion:=InputEventMouseMotion.new();motion.position=point
  root.push_input(motion,true)
  if not await ready(func():return root.gui_get_hovered_control()==ticker.scroll,"Hover reaches log scrolling viewport"):return
  for pressed in [true,false]:
   var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=pressed;wheel.position=point
   root.push_input(wheel,true)
  if not await ready(func():return ticker.scroll.scroll_vertical>0,"Actual wheel input scrolls long log internally"):return
  await proof("after-"+tag+"-long-scroll")
  publish_log(42)
  if not check(await Wait.settle(self,world),"Normal log restored"):return
  if not await click(ticker.stop_button):return
  if not check(await Wait.settle(self,world),"Stop passes through real remote authority"):return
  if not await ready(func():return not world.pet_workflow.active() and ticker.close_button.visible,"Actual stop leaves reviewable result"):return
  if not await click(ticker.close_button):return
  authority.automation._emit_status()
  if not check(await Wait.settle(self,world),"Repeated stopped status delivered"):return
  if not check(not ticker.visible and not world.pet_hunt_menu.chip.visible,"Dismissed stopped run stays closed"):return
  publish_log(43)
  if not check(await Wait.settle(self,world),"Next run delivered"):return
  if not await ready(func():return not ticker.visible and world.pet_hunt_menu.chip.visible,"Next run reopens only collapsed entry"):return
  if not await click(world.pet_hunt_menu.chip.restore_button):return
  authority.automation.flow_phase="idle"
  authority.automation._emit_status()
  if not check(await Wait.settle(self,world),"Inactive fixture before training notices"):return
  var helper=world.training_helper
  world.last_adventure_message="自动练级：旧停止原因"
  helper.on_status({"running":false})
  if not check(world.last_adventure_message.is_empty() and helper.status.text.is_empty(),"Inactive training clears old persistent field state"):return
  var reason:="当地没有可进入且能获得经验的练级敌群，请换个位置或关闭挑敌群。"
  helper.on_event({"kind":"battle_stopped","reason":reason,"battles":0})
  if not check(helper.stop_notice.visible and helper.stop_notice_text.text.contains(reason) and world.last_adventure_message.is_empty(),"Real stop reason retained in bounded notice, not map status"):return
  await proof("after-"+tag+"-training-stop")
  helper._process(helper.STOP_NOTICE_SECONDS)
  if not check(not helper.stop_notice.visible and helper.result.text.contains(reason),"Notice expires; detailed stop reason remains available"):return
  helper.on_event({"kind":"battle_refused","reason":"连接错误：无法开始自动练级"})
  if not check(helper.stop_notice.visible and helper.stop_notice_text.text.contains("连接错误"),"Genuine refusal is not swallowed"):return
  helper.hide();helper._process(helper.STOP_NOTICE_SECONDS)
 world.queue_free();server.queue_free();authority.queue_free()
 print("CAPTURE PROGRESS LAYOUT: PASS")
 quit(0)

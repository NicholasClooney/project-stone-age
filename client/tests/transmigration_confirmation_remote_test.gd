extends "res://tests/transmigration_service_test.gd"
## Actual service + source portal route; isolated client view, not GameScene art.
const UiFixture=preload("res://tests/transmigration_confirmation_ui_test.gd")
const SessionClient=preload("res://network/session_client.gd")
const DialogueUi=preload("res://scripts/quest_dialogue.gd")
class RemoteWorld extends UiFixture.World:
 var backend=null
 var controller
 var open_button:Button
 func _process(delta:float)->void:link.poll(delta)
 func receive(event:Dictionary)->void:
  state.apply(event)
  if event.get("type")=="position":
   data.map_id=int(event.map_id);cell=Vector2i(int(event.cell[0]),int(event.cell[1]))
  if event.get("type")=="profile" or event.get("type")=="snapshot":
   var player:Dictionary=state.profile.get("player",{})
   open_button.text="精灵王确认测试 · 当前第%d转\n服务器地点：%s"%[int(player.get("transmigration",0)),str(state.profile.get("location",{}))]
func remote_world(url:String):
 var w=RemoteWorld.new();w.link=Link.new(url)
 w.session=SessionClient.new(w.link,w.state)
 root.add_child(w);w.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 w.theme=Theme.new();w.theme.default_font=preload("res://assets/fonts/NotoSansSC.ttf")
 w.message.position=Vector2(8,100);w.message.size.x=root.size.x-16
 w.message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 w.dialogue.hide();w.battle_view.hide();w.add_child(w.dialogue);w.add_child(w.battle_view);w.add_child(w.message)
 w.open_button=Button.new();w.open_button.position=Vector2(8,8);w.open_button.size=Vector2(360,80)
 w.open_button.text="与精灵王交谈（隔离远程视图）";w.add_child(w.open_button)
 w.open_button.add_theme_font_override("font",preload("res://assets/fonts/NotoSansSC.ttf"))
 var overlay:=Control.new();w.add_child(overlay);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.hide()
 var panel:=Control.new();overlay.add_child(panel)
 var scroll:=ScrollContainer.new();panel.add_child(scroll)
 var body:=Label.new();scroll.add_child(body)
 w.controller=DialogueUi.new();w.add_child(w.controller);w.controller.setup(w,overlay,body)
 w.open_button.pressed.connect(func():w.controller.open(KING))
 w.link.message.connect(w.receive);w.link.connect_now()
 return w
func ready(condition:Callable,label:String)->bool:
 var ok:bool=await Wait.until(self,condition)
 check(ok,label)
 if not ok:quit(1)
 return ok
func click_ui(control:Control)->void:
 await process_frame
 var point:=control.get_global_rect().get_center()
 var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
 await process_frame
 check(root.gui_get_hovered_control()==control,"remote rendered target receives hover: "+str(control.name))
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
 await process_frame
func picture(width:int,label:String)->void:
 var directory:=OS.get_environment("STONE_AGE_PROOF_DIR")
 if directory.is_empty():return
 DirAccess.make_dir_recursive_absolute(directory)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory+"/%d-%s.png"%[width,label])
func open_ui(w)->bool:
 await click_ui(w.open_button)
 return await ready(func():return is_instance_valid(w.controller.confirmation),"real king preview reaches production UI")
func run()->void:
 root.unfocusable=true;root.position=Vector2i(-10000,-10000);root.content_scale_size=Vector2i.ZERO
 for viewport in [Vector2i(1280,900),Vector2i(390,844)]:
  root.size=viewport
  var b=final_backend()
  var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-final-source.json"))
  b.quest_catalog.reward_pets.merge(source.reward_pets,true)
  b.session._profile.pets=[Candidates.pet(693,1),Candidates.pet(693,2),Candidates.pet(6,3)]
  b.session._profile.next_pet_id=4;b.session._profile.active_pet=2
  check(FinalRoute.entry(b) and FinalRoute.near(b,"300/sb_skr.arg",range(32001,32011)),"actual outer gates and source route to first guardian")
  actual_guard(b,"300/sb_skr.arg",FIRST)
  check(FinalRoute.near(b,"genout/wpm_32016_31_39",range(32011,32017)) and FinalRoute.commit(b,"genout/wpm_32016_31_39") and FinalRoute.near(b,"300/sb_skt.arg",range(32016,32021)),"actual middle gate and original later portals")
  actual_guard(b,"300/sb_skt.arg",LAST)
  check(FinalRoute.near(b,"genout/wpm_32021_31_51",[32021]) and FinalRoute.commit(b,"genout/wpm_32021_31_51") and FinalRoute.near(b,"777/ten.arg",[32021]),"actual last gate and continuous king approach; no proof injection")
  root.add_child(b)
  var server=Server.new(b,0,"127.0.0.1");root.add_child(server);check(server.start()==OK,"isolated actual WS server")
  var url:="ws://127.0.0.1:%d"%server.port
  var w=remote_world(url)
  if not await ready(func():return w.link.online and not w.state.profile.is_empty(),"remote snapshot ready with no backend"):return
  check(w.backend==null and w.link.backend==null,"client view has no backend")
  var before:Dictionary=b.session.snapshot()
  if not await open_ui(w):return
  var view=w.controller.confirmation
  check(view.selectors.size()==2 and view.selected_ids==["pet-1"],"real species schema exposes both valid UIDs in source slot order")
  await picture(viewport.x,"preview")
  await click_ui(view.cancel)
  if not await ready(func():return b.transmigration.pending.is_empty(),"cancel reaches actual service"):return
  check(b.session.snapshot()==before,"cancel consumes no pet, stats or saved history")
  if not await open_ui(w):return
  view=w.controller.confirmation
  await ready(func():view.scroll.ensure_control_visible(view.selectors[1]);return view.scroll.get_global_rect().encloses(view.selectors[1].get_global_rect()),"alternate exact UID visible")
  await click_ui(view.selectors[1]);check(view.confirm.disabled,"UID change disables old confirmation")
  await click_ui(view.refresh)
  if not await ready(func():return not view.busy and view.preview.sacrifices[0].pet_id=="pet-2","authority accepts explicitly selected same-template UID"):return
  await picture(viewport.x,"selected")
  var old_token:String=view.token
  var other=Link.new(url);links.append(other);other.connect_now()
  await ready(func():poll();return other.online,"second actual device connects")
  var newer:Dictionary=await request(other,{"type":"transmigration","action":"preview","npc_id":KING,"pet_ids":["pet-2"]})
  check(newer.has("transmigration") and newer.transmigration.token!=old_token,"other device supersedes actual token")
  await click_ui(view.confirm)
  if not await ready(func():return not view.busy and view.status.text.contains("已过期"),"old device receives understandable expiry rejection"):return
  check(view.confirm.disabled and b.session.snapshot()==before,"stale token cannot settle")
  await picture(viewport.x,"superseded")
  await click_ui(view.cancel)
  await request(other,{"type":"ping"})
  check(b.transmigration.pending.token==newer.transmigration.token,"late old cancel cannot clear other-device pending")
  if not await open_ui(w):return
  view=w.controller.confirmation
  await ready(func():view.scroll.ensure_control_visible(view.selectors[1]);return view.scroll.get_global_rect().encloses(view.selectors[1].get_global_rect()),"alternate UID remains selectable")
  await click_ui(view.selectors[1]);await click_ui(view.refresh)
  if not await ready(func():return not view.busy and view.preview.sacrifices[0].pet_id=="pet-2","fresh preview selected UID restored"):return
  var enabled:bool=bool(before.get("no_random_encounters",false))
  check((await request(other,{"type":"no_random_encounters","enabled":not enabled})).ok,"other device updates a real saved preference")
  if not await ready(func():return view.stale and view.confirm.disabled,"live profile event disables old confirmation on first device"):return
  await picture(viewport.x,"profile-changed")
  check((await request(other,{"type":"no_random_encounters","enabled":enabled})).ok,"other device restores preference without inventing route eligibility")
  await click_ui(view.refresh)
  if not await ready(func():return not view.busy and not view.stale,"fresh preview after real multi-device profile update"):return
  var token:String=view.token
  var frozen:Dictionary=b.transmigration.pending.candidate.duplicate(true)
  b.save_path="user://absent-confirmation-ui-parent/save.json"
  await click_ui(view.confirm)
  if not await ready(func():return not view.busy and view.status.text.contains("保存失败"),"actual disk failure returns readable retry state"):return
  check(view.token==token and not view.confirm.disabled and b.session.snapshot()==before and b.transmigration.pending.candidate==frozen,"same token/seed/entire prestate preserved")
  await picture(viewport.x,"save-failed")
  b.save_path="user://confirmation-remote-%d.json"%viewport.x
  await click_ui(view.confirm)
  if not await ready(func():return not w.controller.active and int(w.state.profile.player.transmigration)==1,"real confirmation saves, updates remote profile and closes"):return
  check(b.session.snapshot()==frozen and b.session.snapshot().pets.any(func(p):return p.pet_id=="pet-1") and not b.session.snapshot().pets.any(func(p):return p.pet_id=="pet-2"),"exact alternate sacrifice consumed once; all candidate fields committed")
  await picture(viewport.x,"returned")
  check(not (await request(other,{"type":"transmigration","action":"confirm","token":token})).ok and b.session.snapshot()==frozen,"second device cannot duplicate settled reward")
  w.link.close();w.queue_free();await process_frame
  w=remote_world(url)
  if not await ready(func():return w.link.online and int(w.state.profile.get("player",{}).get("transmigration",0))==1,"reconnected remote view reads committed round"):return
  check(w.session.snapshot().location==frozen.location,"reconnect retains actual village without replay")
  await picture(viewport.x,"reconnected")
  var restored=Backend.new();check(restored.load_profile(b.save_path) and restored.session.snapshot()==restored.session._normalize_numbers(frozen),"new server loads exact persisted reward/history/village")
  restored.free();w.link.close();w.queue_free();other.close();links=[];server.stop();server.queue_free();b.queue_free();await process_frame
 print("TRANSMIGRATION CONFIRMATION REMOTE: %d failures"%failures);quit(1 if failures else 0)

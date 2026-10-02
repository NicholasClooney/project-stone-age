extends "res://tests/original_herb_use_ui_test.gd"
## Real remote viewport input plus optional rendered 390x844 evidence.
const Equipment=preload("res://server/original_equipment.gd")
var visual:=false
func click(control:Control)->bool:
 var point:=control.get_global_rect().get_center()
 var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point
 root.push_input(move,true)
 if not check(await Wait.until(self,func():return root.gui_get_hovered_control()==control),"viewport hover reaches target"):return false
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
  event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
  root.push_input(event,true)
  await process_frame
 return true
func shot(name:String)->void:
 if not visual:return
 await process_frame
 await RenderingServer.frame_post_draw
 var folder:=OS.get_environment("STONE_AGE_PROOF_DIR")
 if folder.is_empty():folder="/private/tmp/bonus-item-details"
 DirAccess.make_dir_recursive_absolute(folder)
 root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func run()->void:
 root.unfocusable=true
 root.content_scale_size=Vector2i.ZERO
 root.size=Vector2i(390,844)
 visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
 var b=Backend.new();root.add_child(b)
 b.session._profile.default_companions_claimed=true
 b.session.gm_raise_level(-1,30)
 Equipment.add(b.session._profile,2418)
 Equipment.add(b.session._profile,2518)
 var uid:=int(b.session._profile.original_instances[0].uid)
 var server=WsServer.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"isolated server starts")
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 var world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://item-details-layout.cfg";root.add_child(world)
 check(await Wait.until(self,func():return world.link.online and not world.data.is_empty()) and await Wait.settle(self,world) and world.backend==null,"remote UI has no backend")
 var menu=world.adventure_menu
 menu.open_menu("inventory")
 await click(menu.panel.get_node("OriginalItemSlot_0"))
 var scroll:ScrollContainer=menu.panel.get_node("OriginalItemDetailsScroll")
 var content:VBoxContainer=scroll.get_node("OriginalItemDetailsContent")
 var equip:Button=menu.panel.get_node("EquipOriginalItem")
 check(await Wait.until(self,func():return content.size.y>scroll.size.y),"long equipment description creates vertical scroll")
 check(scroll.get_global_rect().end.y<=equip.get_global_rect().position.y and scroll.get_global_rect().end.x<=390,"bounded details leave action and screen clear")
 await shot("390-helmet-top")
 var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.position=scroll.get_global_rect().get_center();wheel.global_position=wheel.position
 root.push_input(wheel,true)
 wheel=wheel.duplicate();wheel.pressed=false;root.push_input(wheel,true)
 check(await Wait.until(self,func():return scroll.scroll_vertical>0),"actual pointer wheel scrolls detail text")
 scroll.scroll_vertical=10000
 await shot("390-helmet-description")
 await click(equip)
 check(await Wait.until(self,func():return int(world.session.snapshot().original_equipment.head)==uid) and await Wait.settle(self,world),"actual remote click equips after scrolling")
 await click(menu.panel.get_node("OriginalItemSlot_0"))
 await shot("390-helmet-equipped")
 await click(menu.panel.get_node("EquipOriginalItem"))
 check(await Wait.until(self,func():return int(world.session.snapshot().original_equipment.head)==0) and await Wait.settle(self,world),"actual remote click unequips")
 await click(menu.panel.get_node("OriginalItemSlot_1"))
 await shot("390-original-reward")
 var effect_label:Label=menu.panel.find_child("OriginalEffectsMetadata",true,false)
 check(effect_label!=null and effect_label.text.contains("滋润的精灵 Lv2") and effect_label.text.contains("未生效"),"actual original A reward shows named inactive magic and stats")
 check(effect_label.tooltip_text.contains("2101") and effect_label.tooltip_text.contains("magicid"),"real item UI retains original row and field evidence")
 check(not menu.panel.has_node("EquipOriginalItem"),"unsupported reward gains no equip action")
 world.music.stop();world.effect.stop();world.link.close();world.queue_free();server.stop();server.queue_free();b.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path("user://item-details-layout.cfg"))
 print("ORIGINAL ITEM DETAILS LAYOUT: %d failures"%failures)
 quit(1 if failures else 0)

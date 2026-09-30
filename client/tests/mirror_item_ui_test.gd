extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,message:String):
 if not ok:failures+=1;push_error(message)
 else:print("PASS: ",message)
func double_click(control:Control):
 var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.double_click=true;control.gui_input.emit(event)
func run():
 var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game)
 await process_frame
 game.random_encounters=false
 game.load_area_id(1002,Vector2i(16,15))
 game.session._profile.player.gold=10000
 var menu=game.adventure_menu
 menu.selected_item="mirror_charm";menu.open_menu("shop")
 await process_frame
 for child in menu.panel.get_children():
  if child is Label and child.position==Vector2(111,305):check(child.position.y+child.size.y<=352,"shop description stays above sell price")
 check(menu.item_name("mirror_charm")=="美丽尼亚护身符1","original accessory appears in shop")
 game.perform_adventure_action("buy_mirror_charm")
 check(game.session.snapshot().inventory.mirror_charm==1 and game.session.snapshot().player.gold==5200,"shop buys original4800charm")
 menu.open_menu("inventory")
 double_click(menu.panel.get_node("ItemSlot_mirror_charm"));await process_frame
 check(game.session.snapshot().equipped_mirror,"double-click equips accessory")
 for child in menu.panel.get_children():
  if child is Label and child.position==Vector2(15,354):check(child.position.y+child.size.y<=404,"inventory description stays above action")
 check(not menu.panel.has_node("BagIcon_mirror_charm"),"equipped only copy leaves bag")
 var icon=menu.panel.get_node("EquippedMirrorIcon")
 check(icon.position+icon.texture.get_size()/2==Vector2(32,68),"original DECORATION1 center retained")
 check(menu.item_description("mirror_charm").contains("主动") and menu.item_description("mirror_charm").contains("5 点气力"),"active cast and its 5 气力 described")
 double_click(menu.panel.get_node("EquippedMirror"));await process_frame
 check(not game.session.snapshot().equipped_mirror and menu.panel.has_node("BagIcon_mirror_charm"),"unequip returns accessory to bag")
 menu.open_menu("shop");game.perform_adventure_action("sell_mirror_charm")
 check(game.session.snapshot().inventory.mirror_charm==0 and game.session.snapshot().player.gold==7600,"unequipped accessory sells at half price")
 game.close_adventure_menu();game.music.stop();game.effect.stop()
 await create_timer(0.3).timeout
 game.queue_free();await process_frame;await process_frame;quit(1 if failures else 0)

extends "res://tests/original_wood_equipment_test.gd"
var visual:=false
var desktop:=false
func run() -> void:
 root.gui_embed_subwindows=true
 root.content_scale_size=Vector2i.ZERO
 desktop="--desktop" in OS.get_cmdline_user_args()
 root.size=Vector2i(1280,720) if desktop else Vector2i(390,844)
 visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
 if visual:DirAccess.make_dir_recursive_absolute("/private/tmp/body-revival-shots")
 var backend=Backend.new();root.add_child(backend)
 backend.save_path="user://body-revival-ui.json"
 backend.session.gm_raise_level(-1,30)
 var armor:=add(backend.session,1052);var medicine:=add(backend.session,2450)
 backend.session.grant_starter_pets();backend.session.select_pet(0)
 var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
 root.add_child(server);check(server.start()==OK,"ephemeral remote UI server")
 var script=load("res://scripts/game.gd")
 script.server_url_override="ws://127.0.0.1:%d"%server.port
 var world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://body-revival-ui.cfg";root.add_child(world)
 check(await Wait.until(self,func():return not world.data.is_empty() and world.link.online) and await Wait.settle(self,world),"remote game ready")
 check(world.backend==null,"remote client has no backend")
 var menu=world.adventure_menu
 menu.open_menu("inventory");await process_frame
 await click(menu.panel.get_node("OriginalItemSlot_0"))
 check(root.get_visible_rect().encloses(menu.panel.get_global_rect()),"inventory panel inside viewport")
 await shot("390-body-before")
 await click(menu.panel.get_node("EquipOriginalItem"))
 check(await Wait.until(self,func():return int(world.session.snapshot().original_equipment.body)==armor),"real click equips BODY over websocket")
 check(await Wait.settle(self,world),"equipment projection settles")
 check(menu.panel.get_node("OriginalItemSlot_0").position==Vector2(111,106),"armor occupies native BODY silhouette")
 await shot("390-body-equipped")
 await click(menu.panel.get_node("OriginalItemSlot_1"))
 check(menu.panel.find_child("OriginalItemDescription",true,false).text.contains("仅战斗"),"field UI explains battle-only medicine")
 check(not menu.panel.has_node("OriginalItemUse"),"no field revival action offered")
 await shot("390-medicine-details")
 world.close_adventure_menu()
 world.load_area_id(100,Vector2i(637,493));await Wait.settle(self,world)
 var config:Dictionary=backend.session.start_battle_config()
 var active:int=int(config.active_pet)
 config.pets[active].hp=0
 # Genuine admission contains the owned pet; only the fixture's battle HP is
 # dead before presentation, allowing a real target click on its corpse.
 config.pet.hp=0
 backend.session._pending=config.duplicate(true)
 backend.open_battle(config)
 check(await Wait.until(self,func():return world.battle_view.visible and not world.battle_view.is_animating()),"battle UI ready with dead participating pet")
 var view=world.battle_view
 await click(view.command_panel.get_node("Item"))
 check(await Wait.until(self,func():return view.choice_panel.has_node("OriginalRevivalItem")),"real battle item button exposes medicine")
 await shot("390-battle-medicine")
 await click(view.choice_panel.get_node("OriginalRevivalItem") if desktop else view.get_node("RevivalPhonePanel/OriginalRevivalItemPhone"))
 check(view.selected_action=="revival:%d"%medicine,"medicine selection carries owned UID")
 if not desktop:
  for button in view.revival_phone.find_children("*","Button",true,false):check(button.size.y>=44,"phone revival controls are at least44px")
 check(await Wait.until(self,func():return not view.target_buttons[2].disabled),"dead pet is a selectable real target")
 await shot("390-battle-target")
 var initial:Dictionary=backend.battle.snapshot()
 if desktop:
  check(view.target_buttons[2].is_visible_in_tree() and root.get_visible_rect().encloses(view.target_buttons[2].get_global_rect()),"desktop corpse target is shown inside viewport")
 await click(view.target_buttons[2] if desktop else view.find_child("RevivalPhoneTarget2",true,false))
 check(await Wait.until(self,func():return backend.battle.snapshot().turn>initial.turn),"real target click submits battle action")
 check(backend.battle.snapshot().original_revival_items.is_empty() and backend.battle.snapshot().pet_hp>0,"real remote battle revives pet and consumes one medicine")
 var second=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
 second.connect_now()
 check(await Wait.until(self,func():second.poll(0.01);return second.online),"second real websocket device connected")
 var replies:Array=[]
 second.request({"type":"battle_command","battle_id":initial.battle_id,"turn":initial.turn,"action":"revival:%d"%medicine,"target":1},func(reply):replies.append(reply))
 check(await Wait.until(self,func():second.poll(0.01);return not replies.is_empty()),"second device receives replay response")
 check(not replies[0].ok and replies[0].get("stale",false),"second device with old turn cannot repeat consumption")
 second.close()
 check(await Wait.until(self,func():return not view.is_animating()),"revival animation completes")
 await shot("390-battle-revived")
 backend.handle({"type":"battle_escape_dev"})
 var disk=Session.new()
 check(disk.load_game(backend.save_path) and not 2450 in disk.snapshot().original_items and disk.snapshot().pets[0].hp>0,"remote action persists consumed UID and revived pet")
 world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free();await process_frame
 remove_files("user://body-revival-ui.json");remove_files("user://body-revival-ui.cfg")
 print("BODY REVIVAL UI: %d failures"%failures)
 quit(1 if failures else 0)
func shot(id:String) -> void:
 if not visual:return
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/private/tmp/body-revival-shots/"+(id.replace("390-","1280-") if desktop else id)+".png")

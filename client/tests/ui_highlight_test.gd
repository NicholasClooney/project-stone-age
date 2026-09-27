extends SceneTree
var failures:=0
var game
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures+=1
func frames(count:int=3)->void:
	for i in range(count):await process_frame
func hover(control:Control)->void:
	var motion:=InputEventMouseMotion.new()
	motion.position=control.get_global_rect().get_center()
	root.push_input(motion,true)
	await frames()
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/stone-age-"+name+".png")
func run()->void:
	game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game);await frames()
	game.session._profile.inventory.club=2
	game.show_adventure_menu("inventory");await frames()
	var menu=game.adventure_menu
	var potion=menu.panel.get_node("ItemSlot_potion")
	var club=menu.panel.get_node("ItemSlot_club")
	await hover(club)
	check(club.get_node("OriginalHighlight").hovered,"bag item gains source hover rectangle through actual pointer input")
	check(potion.get_node("OriginalHighlight").selected,"chosen item retains separate cyan selection while hovering another")
	check(club.get_node("OriginalHighlight").mouse_filter==Control.MOUSE_FILTER_IGNORE,"highlight never intercepts item clicks")
	await capture("inventory-highlights")
	club.pressed.emit();await frames()
	check(menu.panel.get_node("ItemSlot_club/OriginalHighlight").selected and not menu.panel.get_node("ItemSlot_potion/OriginalHighlight").selected,"click moves persistent selection to chosen item")
	game.session._profile.equipped=true;menu.rebuild();await frames()
	menu.panel.get_node("EquippedClub").pressed.emit();await frames()
	check(menu.panel.get_node("EquippedClub/OriginalHighlight").selected and not menu.panel.get_node("ItemSlot_club/OriginalHighlight").selected,"equipped weapon and spare bag copy have distinct selection")
	game.session.grant_starter_pets()
	menu.open_menu("pets");await frames()
	var row=menu.panel.get_node("PetRow0")
	await hover(row)
	check(row.get_node("OriginalHighlight").hovered and row.get_node("OriginalHighlight").bounds.size.y==22,"pet name uses source text outline rather than full-row fill")
	await capture("pet-highlights")
	game.close_adventure_menu();await frames()
	var hud=game.classic_hud
	hud.pointer_position=Vector2(650,hud.size.y-4)
	await create_timer(0.25).timeout
	var tab=hud.task_buttons[3]
	await hover(tab)
	check(tab.get_node("OriginalHighlight").hovered,"bottom menu tab gets independent source hover outline")
	check(tab.texture_hover==tab.texture_normal and tab.texture_pressed!=tab.texture_normal,"hover preserves raised menu art; press has its own state")
	await capture("menu-highlights")
	tab.disabled=true;await frames()
	check(not tab.get_node("OriginalHighlight").hovered,"disabled button has no actionable hover rectangle")
	game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null
	game.queue_free();await frames(3);await create_timer(0.3).timeout
	print("UI HIGHLIGHTS: %d failures" % failures)
	quit(1 if failures else 0)

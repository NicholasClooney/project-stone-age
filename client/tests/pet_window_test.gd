extends SceneTree
var failures:=0
func check(value:bool,note:String)->void:
	if value:print("PASS: "+note)
	else:failures+=1;push_error("FAIL: "+note)
func _initialize()->void:call_deferred("run")
func capture(path:String)->void:
	if "--capture" not in OS.get_cmdline_user_args():return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run()->void:
	var world=load("res://scenes/main.tscn").instantiate()
	world.profile_persistence=false
	root.add_child(world)
	await process_frame
	world.muted=true
	for i in range(5):
		var pet={"name":"乌力伙伴%d" % (i+1),"species":"wooli","sprite":100250,"level":i+1,"xp":i*3,"hp":25+i,"max_hp":35+i,"attack":8+i,"defence":4+i,"speed":10+i,"skill_unlocked":false,"learned_skills":[3,10,50] if i==0 else []}
		world.session._profile.pets.append(pet)
	world.session._profile.active_pet=0
	world.show_adventure_menu("pets")
	var menu=world.adventure_menu
	check(menu.pet_view=="list" and menu.panel.size==Vector2(272,320) and menu.panel.position==Vector2(4,4),"OG list replaces detail at native leftanchor")
	check(menu.panel.get_node("PetRow4").position==Vector2(67,232),"allfive rows use51pixelspacing")
	await capture("/tmp/pet-window-list.png")
	var click:=InputEventMouseButton.new()
	click.position=menu.panel.get_node("PetRow0").get_global_transform_with_canvas()*Vector2(80,12)
	click.pressed=true
	click.button_index=MOUSE_BUTTON_LEFT
	var motion:=InputEventMouseMotion.new()
	motion.position=click.position
	root.push_input(motion,true)
	root.push_input(click,true)
	click.pressed=false
	root.push_input(click,true)
	check(menu.pet_view=="detail" and menu.panel.size==Vector2(272,332),"row opens originalstatuswindow")
	check(menu.panel.get_node_or_null("PetPortrait")!=null,"nativepetportrait displayed")
	await capture("/tmp/pet-window-detail.png")
	menu.pet_switch_view("skills")
	check(menu.panel.size==Vector2(272,348),"originalskillwindowdimensions")
	await capture("/tmp/pet-window-skills.png")
	menu.pet_switch_view("detail")
	menu.pet_rename=true
	menu.rebuild()
	check(menu.name_edit.position==Vector2(18,356),"rename appears below originalstatuswindow")
	menu.name_edit.text="新名字"
	world.perform_adventure_action("rename_pet",0)
	check(world.session.snapshot().pets[0].name=="新名字","rename remainsfunctional")
	menu.pet_switch_view("list")
	menu.panel.get_node("PetState0").pressed.emit()
	check(world.session.snapshot().active_pet==-1,"activepetstatebutton withdraws")
	await process_frame
	menu.panel.get_node("PetState1").pressed.emit()
	check(world.session.snapshot().active_pet==1,"restingpetstatebutton selects")
	world.close_adventure_menu()
	world.music.stop();world.effect.stop();world.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("PET WINDOW: %d failures" % failures)
	quit(1 if failures else 0)

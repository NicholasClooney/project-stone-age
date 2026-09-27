extends SceneTree
const Catalog = preload("res://scripts/pet_skills.gd")
const Training = preload("res://scripts/pet_training.gd")
var failures := 0
func check(value: bool, description: String) -> void:
	if value:print("PASS: "+description)
	else:failures+=1; push_error("FAIL: "+description)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	check(Catalog.available(1003)==[3,10,50] and Catalog.available(1000).is_empty(),"source training service onlyatSamgir petshop")
	check(Catalog.SKILLS[3].cost==1500 and Catalog.SKILLS[10].cost==2000 and Catalog.SKILLS[50].cost==2000,"original skill prices retained")
	var world = load("res://scenes/main.tscn").instantiate()
	world.profile_persistence=false
	root.add_child(world)
	await process_frame
	world.muted=true
	check(world.load_area_id(1003,Vector2i(18,15)),"original trainerinterior loads")
	await process_frame
	var menu = world.pet_training
	menu.open_training(1003)
	check(menu.visible and menu.panel.size==Vector2(432,428) and menu.original(26139)!=null,"original skill-shop asset andlayout")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/pet-training-original.png")
	menu._select_skill(3)
	check(menu.stage==0 and menu.feedback=="石币不足。","unaffordable skill stayslist")
	world.session._profile.player.gold=5000
	menu._select_skill(3)
	check(menu.stage==1 and menu.panel.size==Vector2(448,240),"affordableskill opens originalpetselection")
	world.session._profile.pets=[{"name":"乌力","level":1,"learned_skills":[]}]
	world.session._profile.location={"map_id":1003,"x":18,"y":15}
	menu.selected_pet=0
	menu.stage=2
	menu.rebuild()
	menu._confirm()
	check(world.session.snapshot().pets[0].learned_skills==[3] and world.session.snapshot().player.gold==3500,"confirmed training teaches once andcharges originalcost")
	check(not world.session.learn_pet_skill(0,3) and world.session.snapshot().player.gold==3500,"duplicate learning cannot charge twice")
	world.session._profile.location.map_id=1000
	check(not world.session.learn_pet_skill(0,10),"remote learning refused")
	menu.close_training()
	check(not menu.visible and not world.paused_input,"close restores worldinput")
	world.music.stop()
	world.effect.stop()
	world.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("PET TRAINING: %d failures" % failures)
	quit(1 if failures else 0)

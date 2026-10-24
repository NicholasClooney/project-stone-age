extends SceneTree
const Clock=preload("res://scripts/clock.gd")
const Wait=preload("res://tests/support/wait.gd")
## Bracket the real portrait process pass without assuming a frame is <=60ms.
class ClockStart extends Node:
	var tick := -1
	func _process(_delta:float)->void:tick=Clock.ticks_msec()
class ClockEnd extends Node:
	var start:ClockStart
	var portrait:Control
	var sample:Dictionary={}
	func _process(_delta:float)->void:
		if start.tick<0:return
		sample={"from":start.tick,"to":Clock.ticks_msec(),"image":portrait.current_image,
			"visible":portrait.is_visible_in_tree(),"processing":portrait.is_processing()}
		set_process(false);start.set_process(false)
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
## The image must match the global clock inside the actual update interval.
## Both endpoints are recorded before this test coroutine resumes on a later frame.
func shows_clock(portrait,animation:Dictionary,sample:Dictionary)->bool:
	for tick in range(int(sample.from),int(sample.to)+1):
		if int(portrait.frame_at(animation,tick).image)==int(sample.image):return true
	return false
func process_sample(portrait)->Dictionary:
	var start:=ClockStart.new();start.process_priority=portrait.process_priority-1
	var end:=ClockEnd.new();end.start=start;end.portrait=portrait
	end.process_priority=portrait.process_priority+1
	root.add_child(start);root.add_child(end)
	var sampled:bool=await Wait.until(self,func():return not end.sample.is_empty(),3.0)
	var result:Dictionary=end.sample.duplicate()
	start.queue_free();end.queue_free()
	check(sampled,"portrait real process pass was observed")
	return result
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
	var portrait=menu.panel.get_node("PetPortrait")
	var standing:Dictionary=portrait.animation_for("100250",3,1)
	check(portrait.facing==1 and portrait.action==3 and preload("res://scripts/sprite_art.gd").frame_count(standing)>1,"portrait loops the standing animation at original facing 1")
	var sample:Dictionary=await process_sample(portrait)
	if sample.is_empty():quit(1);return
	check(sample.visible and sample.processing,"portrait is visible and automatically processing")
	print("PET CLOCK: process interval=",sample.from,"..",sample.to," image=",sample.image," observation_age_ms=",Clock.ticks_msec()-int(sample.to))
	check(shows_clock(portrait,standing,sample),"portrait frame follows the shared clock")
	var first:int=portrait.current_image
	var deadline:=Clock.ticks_msec()+3000
	while portrait.current_image==first and Clock.ticks_msec()<deadline:await process_frame
	check(portrait.current_image!=first,"portrait advances frames over time")
	var turn:=InputEventMouseButton.new()
	turn.button_index=MOUSE_BUTTON_LEFT
	turn.pressed=true
	portrait._gui_input(turn)
	check(portrait.facing==2 and menu.pet_portrait_facing==2,"clicking the portrait turns it one facing")
	var rebuild_from:=Clock.ticks_msec()
	menu.rebuild()
	var rebuild_to:=Clock.ticks_msec()
	var rebuilt=menu.panel.get_node("PetPortrait")
	var turned:Dictionary=rebuilt.animation_for("100250",3,2)
	check(rebuilt.facing==2 and shows_clock(rebuilt,turned,{"from":rebuild_from,"to":rebuild_to,"image":rebuilt.current_image}),"rebuilt portrait keeps its facing and clock position")
	var shown:int=rebuilt.current_image
	deadline=Clock.ticks_msec()+3000
	while rebuilt.current_image==shown and Clock.ticks_msec()<deadline:await process_frame
	check(rebuilt.current_image!=shown,"portrait keeps animating after a menu rebuild")
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
	# 存入仓库 beside 宠物技能 stores the pet shown in the status page.
	menu.selected_pet=3
	menu.pet_switch_view("detail")
	await process_frame
	var stash=menu.panel.get_node_or_null("PetStatusStore")
	var before_pets:int=world.session.snapshot().pets.size()
	var before_storage:int=world.session.snapshot().get("pet_storage",[]).size()
	check(stash!=null and not stash.disabled and menu.panel.get_rect().has_point(menu.panel.position+stash.position),"the status page has 存入仓库 beside 宠物技能")
	await capture("/tmp/pet-window-store.png")
	if stash!=null:stash.pressed.emit()
	await process_frame
	check(world.session.snapshot().pets.size()==before_pets-1 and world.session.snapshot().get("pet_storage",[]).size()==before_storage+1 and world.session.snapshot().pet_storage.back().name=="乌力伙伴4","it stores that pet in the warehouse")
	world.close_adventure_menu()
	world.music.stop();world.effect.stop();world.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("PET WINDOW: %d failures" % failures)
	quit(1 if failures else 0)

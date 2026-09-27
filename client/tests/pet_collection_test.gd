extends SceneTree
var failures:=0
var game
func check(ok:bool,message:String)->void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures+=1
func frames(count:int=2)->void:
	for i in range(count):await process_frame
func _initialize()->void:call_deferred("run")
func run()->void:
	game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game);await frames()
	game.show_adventure_menu("pets");await frames()
	var menu=game.adventure_menu
	menu.panel.get_node("StarterPets").pressed.emit();await frames()
	check(game.session.snapshot().pets.size()==3,"developer starter button grants requested three families")
	menu.panel.get_node("StarterPets").pressed.emit();await frames()
	check(game.session.snapshot().pets.size()==3,"starter grant idempotent")
	for i in range(6):
		var pet:Dictionary=game.session.snapshot().pets[0].duplicate(true)
		pet.name="分页伙伴%d" % i
		game.session._profile.pets.append(pet)
	menu.rebuild();await frames()
	check(menu.panel.has_node("PetRow0") and menu.panel.has_node("PetRow4") and not menu.panel.has_node("PetRow5"),"original pet frame shows five rows only")
	menu.pet_page=1;menu.rebuild();await frames()
	check(menu.panel.has_node("PetRow5") and menu.panel.has_node("PetRow8") and not menu.panel.has_node("PetRow0"),"second page uses original stable roster indices")
	menu.panel.get_node("PetRow7").pressed.emit();await frames()
	check(menu.selected_pet==7 and menu.pet_view=="detail","page selection opens correct real pet")
	menu.pet_view="list";menu.pet_category="老虎";menu.rebuild();await frames()
	check(menu.filtered_pet_indices(game.session.snapshot())==[1] and menu.panel.has_node("PetRow1"),"category filter retains actual roster index")
	game.change_character("100010")
	check(game.session.mount_pet(1),"compatible original character mounts golden tiger")
	check(game.session.select_pet(0),"separate dragon can be battle companion")
	menu.rebuild();await frames()
	var riding_title:=false
	for child in menu.panel.get_children():
		if child is Label and child.text.begins_with("[骑]"):riding_title=true
	check(riding_title,"riding companion marked separately from battle state")
	menu.panel.get_node("PetGrowthToggle").pressed.emit();await frames()
	check(menu.pet_growth_open and menu.selected_pet==1,"growth forecast follows filtered selected pet")
	var comparison_header:=false
	var comparison_value:=false
	for child in menu.panel.get_children():
		if child is Label:
			if child.text=="同种上限":comparison_header=true
			if child.text=="1324":comparison_value=true
	check(comparison_header and comparison_value,"forecast shows selected tiger species ceiling in comparison table")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/stone-age-pet-growth.png")
	var before:Dictionary=game.session.snapshot()
	menu.rebuild();await frames()
	check(game.session.snapshot()==before,"opening and refreshing growth estimates leaves save unchanged")
	game.set_process(false);game.set_physics_process(false)
	game.music.stop();game.effect.stop()
	game.queue_free();await frames(3);await create_timer(0.3).timeout
	print("PET COLLECTION: %d failures" % failures)
	quit(1 if failures else 0)

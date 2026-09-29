extends SceneTree
## 宠物大全: the real catalog, family, potential and landing data (functional
## core), then the window with fake travel for the rule checks and one real
## 瞬移去抓 into 自动抓极品.
const Encyclopedia = preload("res://scripts/pet_encyclopedia.gd")
const Thumbs = preload("res://scripts/pet_thumbnails.gd")
const Rules = preload("res://server/progression.gd")
const Shortcuts = preload("res://scripts/shortcuts.gd")
var failures := 0
func _initialize():call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func run() -> void:
	core()
	await window()
	print("PET ENCYCLOPEDIA: %d failures" % failures)
	quit(1 if failures else 0)

func core() -> void:
	var catalog: Dictionary = preload("res://server/encounter_catalog.gd").new().data
	var maps: Dictionary = preload("res://scripts/world_catalog.gd").new().maps
	var book = Encyclopedia.new(catalog,Encyclopedia.read_json(Encyclopedia.FAMILIES_PATH),Encyclopedia.read_json(Encyclopedia.POTENTIAL_PATH),Encyclopedia.read_json(Encyclopedia.SPOTS_PATH).spots,maps,Encyclopedia.read_json(Encyclopedia.PETS_PATH))
	var pets := 0
	for key in catalog.templates:
		if int(catalog.templates[key].pet_flag) != 0:pets += 1
	check(book.by_template.size() == pets,"every pet template belongs to one entry (%d)" % pets)
	check(book.families[0].name == "乌力系" and book.species[book.families[0].species[0]].name == "乌力","album page 0 is 乌力系, starting with 乌力")
	var dragons: Dictionary = {}
	for family in book.families:
		if family.name == "人龙系":dragons = family
	check(dragons.species.has(92),"扬奇洛斯 (92) is in 人龙系")
	var blue: Dictionary = book.entry_for(92)
	check(blue.initial == 29 and blue.weights == [27,36,16,20] and blue.rank == 1 and blue.alias == "蓝人龙","92: initial 29, weights 27/36/16/20, 成长级 1, alias 蓝人龙")
	check(absf(float(blue.potential.mean_sum)-616.8) < 0.3 and int(blue.potential.top1) == 621 and int(blue.potential.top01) in [622,623],"92 full-grade Lv1→120 mean %.2f, top1%% %d, top0.1%% %d (pet-quality.md: 616.8, 621, 622–623)" % [float(blue.potential.mean_sum),int(blue.potential.top1),int(blue.potential.top01)])
	check(book.entry_for(106).id == 303 and book.entry_for(303).alias == "红暴龙","identical 巴朵兰恩 templates 106 and 303 merge under 303 (红暴龙)")
	check(book.entry_for(586).id == book.entry_for(3).id and book.entry_for(6).id != book.entry_for(3).id,"乌力斯坦 586 merges with 3; template 6 has other stats and stays separate")
	var red: Dictionary = book.entry_for(303)
	check(int(red.wild_lowest) == int(red.wild_potential.level) and int(red.wild_lowest) > 1,"红暴 is caught from Lv.%d in the wild and has that second prediction" % int(red.wild_lowest))
	var rex: Dictionary = book.entry_for(304)
	check(rex.locations.is_empty() and Encyclopedia.where_text(rex) == "无野外出现" and not rex.catchable and rex.alias == "机暴","机暴 (304): no wild spawn, shown as 无野外出现")
	check(Encyclopedia.best_location(rex).is_empty(),"no 瞬移去抓 target without a wild spawn")
	var kuni: Dictionary = book.entry_for(113)
	var first: Dictionary = Encyclopedia.best_location(kuni)
	check(kuni.catchable and int(first.level_min) == 1 and first.reason.is_empty() and first.cell.size() == 2,"昆伊's best location is a verified Lv.1 landing")
	var plan := Encyclopedia.catch_plan(first)
	check(plan.template_id == 113 and plan.level_one and plan.cell == Vector2i(first.cell[0],first.cell[1]),"catch plan targets 113 with the Lv.1 limit")
	var unimported: Array = []
	for id in book.order:
		for place in book.species[id].locations:
			if not place.imported:unimported.append(place)
	check(not unimported.is_empty() and Encyclopedia.catch_plan(unimported[0]).has("error"),"places on maps not imported cannot be teleported to")
	var ranked: Array = Encyclopedia.ranked(book.species,book.order)
	var ordered := true
	for i in range(1,ranked.size()):
		if float(book.species[ranked[i]].potential.get("mean_sum",-1)) > float(book.species[ranked[i-1]].potential.get("mean_sum",-1)):ordered = false
	check(ordered and ranked.size() == book.order.size(),"default ranking: 三围合 mean, highest first")
	var reverse: Array = Encyclopedia.ranked(book.species,book.order,"sum",true)
	check(reverse[0] == ranked[-1] or float(book.species[reverse[0]].potential.get("mean_sum",-1)) == float(book.species[ranked[-1]].potential.get("mean_sum",-1)),"reverse ranking starts at the lowest")
	var by_rank: Array = Encyclopedia.ranked(book.species,book.order,"rank")
	check(int(book.species[by_rank[0]].rank) == 0 and int(book.species[by_rank[-1]].rank) >= int(book.species[by_rank[0]].rank),"成长级 sorts 0 first")
	check(book.filtered("人龙").has(92) and not book.filtered("",true).has(304) and book.filtered("",true).has(113),"search by family name; 只看野外可抓 drops 机暴")
	# The shipped JSON against the project's own GDScript rules: 200 full-grade
	# blue dragons caught at Lv.1 and grown to 120.
	var total := 0.0
	for seed_value in range(200):
		var actor := Rules.species_actor("original_92",1,9000+seed_value,[2,2,2,2])
		actor.level = 1
		var grown := Rules.project_pet(actor,120)
		total += int(grown.attack)+int(grown.defence)+int(grown.speed)
	check(absf(total/200.0-float(blue.potential.mean_sum)) < 1.0,"progression.gd mean over 200 pets %.2f matches the shipped mean %.2f" % [total/200.0,float(blue.potential.mean_sum)])
	var own := Rules.species_actor("original_92",1,77,[2,2,2,2])
	own.merge({"species":"blue_dragon","level":1,"name":"甲","pet_id":"pet-1"})
	var stored := Rules.species_actor("original_92",1,78,[0,0,0,0])
	stored.merge({"species":"original_92","level":1,"name":"乙","pet_id":"pet-2"})
	var profile := {"pets":[own],"pet_storage":[stored,{"species":"original_113","level":1,"name":"丙"}]}
	var counts: Dictionary = book.owned_counts(profile)
	check(counts.get(92,{}) == {"carried":1,"stored":1} and counts.get(113,{}).get("stored",0) == 1,"starter blue_dragon and original_92 both count as 92")
	var best: Dictionary = book.owned_best(profile,blue)
	var projected := Rules.project_pet(own,120)
	check(best.count == 2 and best.best_sum >= int(projected.attack)+int(projected.defence)+int(projected.speed),"best owned Lv.120 三围合 uses the exact projection (%d)" % best.best_sum)

func window() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	game.random_encounters = false
	check(Shortcuts.defaults().get("encyclopedia",[]).has(KEY_B) and Shortcuts.owner_of(Shortcuts.defaults(),KEY_B,"encyclopedia") == "","宠物大全 has its own default key B")
	var helper_names: Array = game.helper_menu.entries().map(func(entry):return entry[0])
	check(helper_names.has("HelperEncyclopedia"),"游戏助手 lists 宠物大全")
	var menu = game.pet_encyclopedia
	# A fake picture for 乌力 stands in for the renderer headless runs lack.
	var picture := ImageTexture.create_from_image(Image.create(8,8,false,Image.FORMAT_RGBA8))
	Thumbs.set_texture(100250,picture)
	menu.open_menu()
	await process_frame
	check(menu.visible and game.paused_input and menu.view == "grid","opens on the grid and holds the character")
	var cell = menu.body.find_child("Species1",true,false)
	check(cell != null and cell.find_child("Placeholder",true,false).visible == false,"乌力's cell shows its picture")
	check(menu.body.find_child("Family9",true,false) != null and menu.body.find_child("Species92",true,false) != null,"人龙系 row shows 扬奇洛斯")
	cell = menu.body.find_child("Species92",true,false)
	cell.pressed.emit()
	await process_frame
	check(menu.view == "detail" and menu.body.find_child("SpeciesName",true,false).text == "扬奇洛斯" and menu.body.find_child("PotentialLv1",true,false) != null,"clicking a cell opens its page with the Lv.120 prediction")
	check(menu.body.find_child("SpeciesVariants",true,false).get_child_count() == menu.book.families.filter(func(f):return f.name == "人龙系")[0].species.size(),"the page lists the family's species")
	menu.show_species(304)
	await process_frame
	check(menu.body.find_child("NoWildSpawn",true,false) != null,"机暴's page says 无野外出现")
	# 瞬移去抓 rules with a fake teleport: refused in battle, nothing moves.
	var moves: Array = []
	menu.travel = func(plan: Dictionary) -> bool:
		moves.append(plan)
		return true
	var hunts: Array = []
	menu.open_hunt = func(plan: Dictionary) -> void:hunts.append(plan)
	var place: Dictionary = Encyclopedia.best_location(menu.book.entry_for(113))
	game.battle_view.visible = true
	check(not menu.go_catch(place) and moves.is_empty() and menu.feedback.contains("战斗"),"no 瞬移去抓 during a battle")
	game.battle_view.visible = false
	check(not menu.go_catch({"reason":"地图未导入"}) and menu.feedback == "地图未导入","a place that cannot be reached explains why")
	check(menu.go_catch(place) and moves.size() == 1 and not menu.visible and hunts.is_empty() and not menu.pending_hunt.is_empty(),"fake teleport: the window closes and waits for arrival before opening the hunt")
	menu.pending_hunt = {}
	# 列表: ranking, sorting, a row's 瞬移去抓 state.
	menu.open_menu()
	menu._switch("list")
	await process_frame
	var rows: Array = menu.body.find_children("Row*","PanelContainer",true,false)
	var ranked: Array = Encyclopedia.ranked(menu.book.species,menu.book.order)
	check(rows.size() == menu.PAGE_SIZE and rows[0].name == "Row%d" % int(ranked[0]),"list shows a page ranked by 三围合 mean")
	menu.body.find_child("Sort_name",true,false).pressed.emit()
	await process_frame
	check(menu.sort_key == "name" and menu.body.find_children("Row*","PanelContainer",true,false)[0].name == "Row%d" % int(Encyclopedia.ranked(menu.book.species,menu.book.order,"name")[0]),"a column header sorts by that column")
	menu.search.text = "帖拉所伊朵"
	menu.search.text_changed.emit(menu.search.text)
	await process_frame
	var go = menu.body.find_child("Go304",true,false)
	check(go != null and go.disabled,"机暴's row cannot 瞬移去抓")
	menu.search.text = ""
	menu.search.text_changed.emit("")
	menu.close_menu()
	# One real 瞬移去抓: teleport to 昆伊's Lv.1 area and open 自动抓极品 on it.
	menu.travel = menu._travel
	menu.open_hunt = menu._open_hunt
	menu.open_menu(113)
	await process_frame
	check(menu.view == "detail" and menu.current == 113,"open_menu(template) opens that species")
	var button = menu.body.find_child("GoPlace%d_%d" % [int(place.map_id),int(place.area_id)],true,false)
	check(button != null and not button.disabled,"the Lv.1 place has 瞬移去抓")
	button.pressed.emit()
	for i in range(5):await process_frame
	var hunt = game.pet_hunt_menu
	check(int(game.data.map_id) == int(place.map_id) and game.cell == Vector2i(place.cell[0],place.cell[1]),"teleported to the verified cell")
	check(hunt.visible and hunt.species.get_selected_id() == 113 and int(game.automation_settings().hunt.template) == 113 and bool(game.automation_settings().hunt.level_one),"自动抓极品 opens with 昆伊 and the Lv.1 limit")
	check(hunt.stat_species.get_selected_id() == 113 and int(game.automation_settings().hunt.stat_species) == 113,"its 属性条件 page shows 昆伊, remembered with the character")
	hunt.close_menu()
	# The pet window's entry opens on the selected pet's species.
	game.session.grant_starter_pets()
	game.show_adventure_menu("pets")
	await process_frame
	var adventure = game.adventure_menu
	var selected: Dictionary = game.session.snapshot().pets[adventure.selected_pet]
	var entry_button = adventure.panel.get_node("PetEncyclopedia")
	check(Rect2(288,0,256,480).encloses(entry_button.get_rect()) and not entry_button.get_rect().intersects(adventure.panel.get_node("PetHunt").get_rect()),"宠物大全 sits beside 自动抓极品 in the pet tools")
	entry_button.pressed.emit()
	await process_frame
	var expected: Dictionary = menu.book.entry_for_pet(selected)
	check(menu.visible and not adventure.visible and menu.view == "detail" and menu.current == int(expected.id),"the pet window opens 宠物大全 on %s" % selected.name)
	menu.close_menu()
	Thumbs.clear()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop()
	game.effect.stop()
	game.queue_free()
	await process_frame
	await create_timer(0.3).timeout

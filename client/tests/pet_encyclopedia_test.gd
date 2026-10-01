extends SceneTree
## 宠物大全: the real catalog, family, potential and landing data (functional
## core), then the window with fake travel for the rule checks and one real
## 瞬移去抓 into 自动抓极品.
const Encyclopedia = preload("res://scripts/pet_encyclopedia.gd")
const Thumbs = preload("res://scripts/pet_thumbnails.gd")
const Rules = preload("res://server/progression.gd")
const Shortcuts = preload("res://scripts/shortcuts.gd")
const BattleArt = preload("res://scripts/battle_art.gd")
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
	var ram: Dictionary = book.entry_for(313)
	check(int(ram.wild_lowest) == int(ram.wild_potential.level) and int(ram.wild_lowest) > 1,"卡伊霍恩 is caught from Lv.%d in the wild and has that second prediction" % int(ram.wild_lowest))
	var gold: Dictionary = book.entry_for(178)
	check(gold.locations.is_empty() and Encyclopedia.where_text(gold) == "无野外出现" and not gold.catchable and gold.name == "莱恩奇夫","莱恩奇夫 (178): no wild spawn, shown as 无野外出现")
	check(Encyclopedia.best_location(gold).is_empty(),"no 瞬移去抓 target without a wild spawn")
	rare_places(book)
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
	check(int(book.species[by_rank[0]].rank) == 0 and int(book.species[by_rank[-1]].rank) == -1,"成长级 sorts 0 first, unknown (8.0 pets) last")
	# Every pet's battle sprite is imported (tools/import_encounter_art.py);
	# only two 8.0 sprites point at a missing bitmap in the original data.
	var pictured: Array = book.order.filter(func(id):return Thumbs.has_art(int(book.species[id].sprite)))
	var missing: Array = book.order.filter(func(id):return not Thumbs.has_art(int(book.species[id].sprite))).map(func(id):return str(book.species[id].name))
	check(book.order.size() >= 570 and missing.size() <= 2,"%d of %d species have battle art; without: %s" % [pictured.size(),book.order.size(),"、".join(missing)])
	# The later pets from the 8.5 album: art from the 8.0 data, no original stats.
	var baya: Dictionary = book.entry_for(10417)
	check(baya.name == "巴雅" and not baya.stats_known and baya.source == "8.0" and baya.potential.is_empty() and baya.locations.is_empty() and int(baya.rank) == -1,"巴雅 (album 417): an 8.0 pet with no stats, no prediction, no wild spawn")
	check(BattleArt.is_extra(int(baya.sprite)) and Thumbs.has_art(int(baya.sprite)) and not AnimatedPortraitFrames(int(baya.sprite)).is_empty(),"its sprite (%d) lives in its own file and loads on demand" % int(baya.sprite))
	check(book.species[book.families.filter(func(f):return f.species.has(10417))[0].species[0]].family_name == "沃斯姆系","and it joins its album page's family")
	var unknown: Array = book.order.filter(func(id):return not book.species[id].stats_known)
	check(unknown.size() == 131 and unknown.all(func(id):return int(id) >= 10000),"131 stat-less 8.0 species, template 10000 + album number")
	check(book.filtered("人龙").has(92) and not book.filtered("",true).has(178) and book.filtered("",true).has(113),"search by family name; 只看野外可抓 drops 莱恩奇夫")
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
	classic(book,catalog,profile)

## The rare Lv.1 spots of data/rare-encounters.json (tools/import_encounters.py):
## every one is a 瞬移去抓 location of its species, marked by origin.
func rare_places(book) -> void:
	var data: Dictionary = Encyclopedia.read_json("res://data/rare-encounters.json")
	var bad: Array = []
	for item in data.get("encounters",[]):
		var entry: Dictionary = book.entry_for(int(item.template_id))
		var found: Array = entry.get("locations",[]).filter(func(place):return int(place.map_id) == int(item.map_id) and int(place.area_id) == int(item.area_id) and str(place.get("origin","")) == str(item.origin))
		if found.size() != 1 or int(found[0].level_min) != 1 or int(found[0].level_max) != 1 or not found[0].capturable or not str(found[0].reason).is_empty() or found[0].cell.size() != 2:
			bad.append("%s@%d/%d" % [item.name,int(item.map_id),int(item.area_id)])
	check(data.get("encounters",[]).size() >= 20 and bad.is_empty(),"%d rare Lv.1 spots are reachable Lv.1 locations of their species%s" % [data.get("encounters",[]).size(),"" if bad.is_empty() else ": "+"、".join(bad)])
	var rex: Dictionary = book.entry_for(304)
	var best: Dictionary = Encyclopedia.best_location(rex)
	check(rex.catchable and int(best.map_id) == 32020 and best.origin == "added" and Encyclopedia.where_text(rex).ends_with("非原版") and Encyclopedia.origin_text(best.origin) == "原版无野外，非原版","机暴 (304): caught only at its added Lv.1 spot in 漆黑的洞窟 地下20楼, shown as 非原版")
	var red: Dictionary = book.entry_for(303)
	var original: Array = red.locations.filter(func(place):return str(place.origin).is_empty() and int(place.map_id) == 500 and int(place.area_id) == 639)
	check(original.size() == 1 and int(original[0].level_min) >= 90 and int(Encyclopedia.best_location(red).level_min) == 1 and Encyclopedia.best_location(red).origin == "original_area" and Encyclopedia.where_text(red).ends_with("Lv.1为补充"),"红暴 keeps its original Lv.90–95 place and gains a separate 补充 Lv.1 place")
	var green: Dictionary = book.entry_for(91)
	var north: Array = green.locations.filter(func(place):return str(place.origin).is_empty() and int(place.map_id) == 300 and int(place.level_min) >= 51)
	var green_best: Dictionary = Encyclopedia.best_location(green)
	check(not north.is_empty() and int(green_best.map_id) == 300 and int(green_best.area_id) == 473 and int(green_best.level_min) == 1 and green_best.origin == "original_area" and Encyclopedia.origin_text(green_best.origin).begins_with("补充"),"利则诺顿 keeps its original Lv.51–53 吉鲁岛 places and gains a 补充 Lv.1 in area 473")
	var water: Dictionary = book.entry_for(252)
	check(water.locations.any(func(place):return int(place.map_id) == 32018 and int(place.level_min) == 1 and str(place.origin).is_empty()),"布林帖斯's original Lv.1 in 地下18楼 stays unmarked")

## 经典宠物: the data file's shape, and the classic and ownership filters.
func classic(book, catalog: Dictionary, profile: Dictionary) -> void:
	var data: Dictionary = Encyclopedia.read_json(Encyclopedia.CLASSIC_PATH)
	var pets: Array = data.get("pets",[])
	var categories: Array = data.get("categories",[]).map(func(category):return str(category.id))
	var sources: Dictionary = data.get("sources",{})
	var bad: Array = []
	var templates := {}
	for pet in pets:
		var why := ""
		for key in ["name","alias","family","reason","obtained","category"]:
			if str(pet.get(key,"")).strip_edges().is_empty():why += " no "+key
		if not categories.has(str(pet.get("category",""))):why += " unknown category"
		if pet.get("sources",[]).is_empty():why += " no source"
		for source in pet.get("sources",[]):
			if not sources.has(source) or str(sources[source].get("url","")).is_empty():why += " unknown source "+str(source)
		if not pet.has("original_wild"):why += " no original_wild"
		var template = pet.get("template_id",null)
		if template == null:
			if str(pet.get("note","")).is_empty():why += " missing without a note"
		else:
			var row: Dictionary = catalog.templates.get(str(int(template)),{})
			if row.is_empty() or int(row.pet_flag) == 0 or str(row.name) != str(pet.name):why += " template %d is not %s" % [int(template),pet.name]
			if templates.has(int(template)):why += " listed twice"
			templates[int(template)] = true
		if not why.is_empty():bad.append(str(pet.get("name","?"))+why)
	check(pets.size() >= 30 and bad.is_empty(),"classic-pets.json: %d pets, each with name, 俗称, reason, how it was got, category and resolvable sources; templates match their names or are marked missing%s" % [pets.size(),"" if bad.is_empty() else ": "+"；".join(bad)])
	book.load_classic(data)
	var missing: Array = book.classic.filter(func(record):return int(record.entry_id) < 0)
	check(book.classic.size() == pets.size() and missing.map(func(record):return record.name) == ["摩卡"],"every classic pet but 摩卡 resolves to an encyclopedia entry")
	check(book.entry_for(94).classic.alias == "红人龙" and book.entry_for(94).alias == "红人龙" and book.entry_for(303).alias == "红暴龙","红人龙 gets its 俗称; 红暴 keeps its starter name")
	check(book.entry_for(105).has("classic") and book.filtered("金飞",false,true) == [274],"蓝暴 (302 merged under 105) is classic; searching a 俗称 finds 金飞")
	var shown: Array = book.filtered("",false,true)
	check(shown.size() == pets.size()-1 and shown.all(func(id):return book.species[id].has("classic")),"经典宠物 filter shows the %d classic species" % shown.size())
	var wild: Dictionary = book.entry_for(94)
	check(Encyclopedia.classic_where_text(book.entry_for(312).classic,book.entry_for(312)).ends_with("非原版") and Encyclopedia.classic_where_text(book.entry_for(304).classic,book.entry_for(304)).ends_with("非原版") and Encyclopedia.classic_where_text(missing[0],{}) == "资料里没有这只宠物" and Encyclopedia.classic_where_text(wild.classic,wild) == Encyclopedia.where_text(wild),"这里能不能抓: 红人龙 where it lives, 金羊 and 机暴 only at a 非原版 spot, 摩卡 not in the data")
	# Ownership: 甲 (carried) and 乙 (stored) are 扬奇洛斯, 丙 (stored) 昆伊.
	var owned: Dictionary = book.owned_counts(profile)
	check(book.filtered("",false,false,"owned",owned) == [92,113] and book.filtered("",false,false,"unowned",owned).size() == book.order.size()-2,"已拥有 lists 扬奇洛斯 and 昆伊 (carried and stored), 未拥有 the other %d" % (book.order.size()-2))
	var unowned: Array = book.filtered("",false,true,"unowned",owned)
	check(book.filtered("",false,true,"owned",owned) == [92] and unowned.has(94) and not unowned.has(92) and not unowned.has(113),"经典 + 已拥有 is 蓝人龙 alone; 经典 + 未拥有 has 红人龙, not 蓝人龙")
	check(book.classic_filtered("",false,"owned",owned).map(func(record):return record.name) == ["扬奇洛斯"] and book.classic_filtered("",false,"unowned",owned).size() == pets.size()-1,"the classic list agrees, and 未拥有 keeps 摩卡")
	check(not book.classic_filtered("",true).any(func(record):return int(record.entry_id) < 0 or not book.species[int(record.entry_id)].catchable),"只看野外可抓 drops 摩卡 and the pets with no wild spawn")

static func AnimatedPortraitFrames(sprite: int) -> PackedInt32Array:
	return preload("res://scripts/animated_portrait.gd").animation_for(str(sprite),3,1).get("frames",PackedInt32Array())

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
	# Pre-cut thumbnails (tools/build_pet_thumbs.py): every picture is a region
	# of a small atlas, so no sprite sheet is loaded to show the grid.
	check(Thumbs.atlas_index().get("sprites",{}).size() > 600 and Thumbs.atlas_path(100373).begins_with(Thumbs.THUMBS),"红暴's thumbnail is in a pre-cut atlas")
	var cut := Thumbs.texture(100373)
	check(cut is AtlasTexture and cut.region.size.x > 0 and cut.region.size.x <= 128 and cut.region.size.y <= 128,"and the picture is that atlas region, at most 128 px")
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
	menu.show_species(178)
	await process_frame
	check(menu.body.find_child("NoWildSpawn",true,false) != null,"莱恩奇夫's page says 无野外出现")
	menu.show_species(304)
	await process_frame
	var added = menu.body.find_child("Place32020_630_added",true,false)
	check(added != null and added.find_child("Origin",true,false).text == "原版无野外，非原版" and menu.body.find_child("GoPlace32020_630_added",true,false) != null,"机暴's page lists 漆黑的洞窟 地下20楼 marked 原版无野外，非原版")
	menu.show_species(303)
	await process_frame
	var extra = menu.body.find_child("Place500_639_original_area",true,false)
	check(extra != null and extra.find_child("Origin",true,false).text.begins_with("补充") and menu.body.find_child("Place500_639",true,false).find_child("Origin",true,false) == null,"红暴's page shows the original Lv.90–95 place unmarked and the added Lv.1 one as 补充")
	menu.show_species(10417)
	await process_frame
	check(menu.body.find_child("SpeciesUnknown",true,false) != null and menu.body.find_child("PotentialLv1",true,false) == null and menu.body.find_child("SpeciesPortrait",true,false) != null,"巴雅's page shows its sprite and says it has no original stats")
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
	menu.search.text = "莱恩奇夫"
	menu.search.text_changed.emit(menu.search.text)
	await process_frame
	var go = menu.body.find_child("Go178",true,false)
	check(go != null and go.disabled,"莱恩奇夫's row cannot 瞬移去抓")
	menu.search.text = ""
	menu.search.text_changed.emit("")
	# 经典宠物: the list in data order with 俗称 and 这里能不能抓, then the grid.
	menu.classic_box.button_pressed = true
	await process_frame
	var first_classic: Dictionary = menu.book.classic[0]
	var classic_rows: Array = menu.body.find_children("Row*","PanelContainer",true,false)
	check(menu.view == "list" and classic_rows[0].name == "Row%d" % int(first_classic.entry_id) and menu.body.find_child("Sort_sum",true,false) == null,"经典宠物 list starts with %s in the file's order, without sorting" % first_classic.name)
	check(menu.body.find_child("Where94",true,false).text == Encyclopedia.where_text(menu.book.entry_for(94)) and menu.body.find_child("Where910",true,false).text.ends_with("非原版") and menu.body.find_child("Where304",true,false).text.ends_with("非原版"),"红人龙 says where it lives here; 吉比 and 机暴 only at 非原版 spots")
	check(menu.body.find_child("Go94",true,false) != null and not menu.body.find_child("Go94",true,false).disabled and not menu.body.find_child("Go910",true,false).disabled,"红人龙 and 吉比 (at its 非原版 spot) both have 瞬移去抓")
	menu.list_page = 1
	menu.rebuild()
	check(menu.body.find_child("Missing_摩卡",true,false) != null,"摩卡, not in the data, is listed as 资料里没有")
	menu._switch("grid")
	await process_frame
	check(menu.body.find_child("Classic_pk",true,false) != null and menu.body.find_child("Species94",true,false) != null and menu.body.find_child("Missing_摩卡",true,false).disabled and menu.body.find_child("Species113",true,false) == null,"the grid groups the classic pets by category and greys out 摩卡")
	menu.show_species(304)
	await process_frame
	check(menu.body.find_child("SpeciesClassic",true,false) != null,"a classic species' page shows its 经典宠物 card")
	menu.view = "grid"
	menu.classic_box.button_pressed = false
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
	# 已拥有 in the list: the character's species, each with 我的 (count, best Lv.120).
	var mine: Dictionary = menu.book.owned_counts(game.session.snapshot())
	menu.view = "list"
	menu.set_ownership("owned")
	await process_frame
	var owned_rows: Array = menu.body.find_children("Row*","PanelContainer",true,false)
	var mine_label = menu.body.find_child("Mine%d" % int(expected.id),true,false)
	check(owned_rows.size() == mine.size() and mine.has(int(expected.id)) and mine_label != null and mine_label.text.contains("只 · 最佳120级三围合"),"已拥有 lists the %d owned species with 我的: %s" % [mine.size(),mine_label.text if mine_label != null else "none"])
	menu.set_ownership("unowned")
	await process_frame
	check(menu.body.find_child("Row%d" % int(expected.id),true,false) == null and menu.body.find_child("Mine%d" % int(expected.id),true,false) == null,"未拥有 hides it")
	menu.set_ownership("all")
	menu.close_menu()
	Thumbs.clear()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop()
	game.effect.stop()
	game.queue_free()
	await process_frame
	await create_timer(0.3).timeout

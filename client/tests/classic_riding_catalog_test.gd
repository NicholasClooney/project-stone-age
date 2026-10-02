extends SceneTree
## Native pair membership, distinct growth variants, real remote input and rendering.
const Book = preload("res://scripts/pet_encyclopedia.gd")
const Riding = preload("res://scripts/riding.gd")
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
var visual := false
var review_menu
const SHOTS := "/private/tmp/tmux-agents/ride-classic-audit/shots/"
func _initialize():run.call_deferred()
func check(ok: bool, note: String):
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1
func click(control):
	if not is_instance_valid(control):
		check(false,"click target exists")
		return
	var point: Vector2 = control.get_global_transform_with_canvas()*(control.size/2)
	var motion := InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
		root.push_input(event,true)
		await process_frame
func reveal(menu, control):
	if not is_instance_valid(control):
		check(false,"scroll target exists")
		return
	# Let deferred scroll restoration finish before requesting a different target.
	await process_frame
	check(await Wait.until(self,func():
		menu.scroll.ensure_control_visible(control)
		return control.size.x > 0 and control.size.y > 0 and menu.scroll.get_global_rect().encloses(control.get_global_rect())),"complete control reachable: "+str(control.name))
func shot(label: String):
	if not visual:return
	check(await Wait.until(self,func():
		return review_menu._thumbs.all(func(item):return not is_instance_valid(item[0]) or not item[0].get_global_rect().intersects(review_menu.scroll.get_global_rect()))),"visible thumbnails loaded for "+label)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(SHOTS+label+".png") == OK,"rendered "+label)
func mounts(book) -> Array:return book.classic.filter(func(record):return record.has("variant_ids"))
func model(book, catalog: Dictionary):
	var records := mounts(book)
	var sprites: Array = records.map(func(record):return int(record.sprite))
	var expected := [100279,100283,100288,100310,100327,100328,100329,100330,100346,100351,100352,100353,100354,100358,100362,100369,100370,100372,100373,100374,100396,100904,100907,101532,101576]
	check(sprites == expected,"exact 25 native appearances, stable order")
	check(records.reduce(func(total,record):return total+record.variant_ids.size(),0) == 28,"28 real growth entries inside 25 cards, four starter tigers excluded")
	check(book.mount_record(100329).variant_ids.has(book.entry_for(524).id) and book.mount_record(100373).variant_ids.has(724) and book.mount_record(100907).variant_ids.has(1036),"same sprite preserves 卡特利奴 and both stronger rex variants")
	check(book.mount_record(100329).entry_id == book.entry_for(193).id and not book.mount_record(100329).variant_ids.has(163),"normal red tiger is primary, starter excluded")
	check(book.entry_for(625).is_empty() and book.entry_for(20).is_empty() and book.entry_for(77).is_empty(),"non-pet reference templates never become riding entries")
	check(book.entry_for(71).id == book.entry_for(99).id and book.entry_for(105).id == book.entry_for(302).id and book.entry_for(106).id == book.entry_for(303).id,"same stats aliases resolve through existing template deduplication")
	check(book.entry_for(303).alias == "红暴龙" and book.entry_for(194).classic.category == "rare" and book.entry_for(92).classic.category == "pk","starter alias and original rare/PK categories survive")
	check(book.classic_filtered("扬奇洛斯").size() == 2 and book.classic_filtered("卡特利奴")[0].entry_id == book.entry_for(524).id,"cross-category duplicates and variant search")
	var owned := {724:{"stored":1,"carried":0}}
	var found: Array = book.classic_filtered("",false,"owned",owned)
	check(found.size() == 1 and found[0].entry_id == 724 and found[0].variant_ids == [724],"owned stronger variant remains discoverable without owning primary")
	check(not book.entry_for(1036).classic.has("original_wild") and Book.classic_where_text(book.entry_for(1036).classic,book.entry_for(1036)).contains("未核实"),"growth variant does not inherit an unaudited original acquisition claim")
	var original: Dictionary = Book.read_json(Book.CLASSIC_PATH)
	var injected := Riding.index().duplicate(true)
	injected.pairs["100000:1009999"] = {"pet":int(catalog.templates["113"].sprite),"rider":100000,"sprite":101004}
	injected.pairs["missing"] = {"pet":999999,"rider":100000,"sprite":999999}
	book.load_classic(original,injected)
	check(mounts(book).size() == 26 and not book.mount_record(int(catalog.templates["113"].sprite)).is_empty(),"new valid pair automatically appears; missing composite/template does not")
	book.load_classic(original)
	check(mounts(book).size() == 25 and not book.entry_for(113).has("classic"),"reloading removes stale generated membership")
func run():
	visual = "--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(SHOTS)
	root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	var backend = Backend.new();root.add_child(backend)
	var server = WsServer.new(backend,0,"127.0.0.1");root.add_child(server)
	check(server.start() == OK,"isolated WebSocket authority on port 0")
	var script = load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
	var game = load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	game.profile_persistence=false;game.viewer_prefs_path="user://classic-riding-catalog.cfg";root.add_child(game)
	check(await Wait.until(self,func():return game.link.online and not game.data.is_empty()) and await Wait.settle(self,game),"real remote client connects")
	check(game.backend == null,"remote UI has no local backend")
	game.random_encounters=false
	game.session.set_character("100000")
	check(await Wait.settle(self,game),"initial appearance settles")
	var menu = game.pet_encyclopedia;review_menu=menu;menu.open_menu()
	model(menu.book,backend.encounter_catalog.data)
	menu.view="grid";menu.classic_box.button_pressed=true;menu.search.text="";menu.set_ownership("all");menu.rebuild()
	check(await Wait.until(self,func():return menu.body.find_children("MountCard*","PanelContainer",true,false).size()==25),"actual grid shows 25 appearance cards")
	var card = menu.body.find_child("MountCard100329",true,false)
	await reveal(menu,card)
	await shot("desktop-mounts")
	var variant = card.find_child("MountVariant524",true,false)
	await click(variant)
	check(await Wait.until(self,func():return menu.view=="detail" and menu.current==menu.book.entry_for(524).id),"real remote click opens 卡特利奴 distinct growth detail")
	await shot("desktop-variant-detail")
	menu.view="grid";menu.rebuild()
	var gold = menu.body.find_child("MountStatus100330",true,false)
	check(gold.text == "换造型可骑","gold tiger requires another appearance initially")
	game.session.set_character("100010")
	check(await Wait.until(self,func():return gold.text=="当前造型可骑"),"open card responds to actual remote character change")
	check(menu.body.find_child("MountStatus100329",true,false).text == "换造型可骑","red tiger updates without rebuilding/removing cards")
	for size in [Vector2i(1280,800),Vector2i(390,844)]:
		root.size=size;root.content_scale_size=size;menu.relayout();menu.view="grid";menu.search.text="";menu.rebuild()
		check(await Wait.until(self,func():return menu.panel.size.x<=size.x),"resized panel width %s at %s"%[menu.panel.size,size])
		card=menu.body.find_child("MountCard100329",true,false)
		await reveal(menu,card)
		check(menu.panel.get_global_rect().size.x<=size.x,"panel fits %d viewport: rect=%s min=%s"%[size.x,menu.panel.get_global_rect(),menu.panel.get_combined_minimum_size()])
		await shot("%d-mount-variants"%size.x)
		await click(card.find_child("MountVariant524",true,false))
		check(menu.current==menu.book.entry_for(524).id and menu.view=="detail","variant entry clickable at %d"%size.x)
		await shot("%d-variant-detail"%size.x)
		menu.view="grid";menu.rebuild()
		await reveal(menu,menu.body.find_child("MountCard101576",true,false))
		await shot("%d-mount-bottom"%size.x)
	for tid in [724,1036]:
		menu.view="grid";menu.rebuild()
		var alternative=menu.body.find_child("MountVariant%d"%tid,true,false)
		await reveal(menu,alternative)
		await click(alternative)
		check(menu.view=="detail" and menu.current==tid,"mobile real click opens growth variant %d"%tid)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	menu.view="list";menu.search.text="斑尼迪克";menu.rebuild()
	var list_variant=menu.body.find_child("MountVariant1036",true,false)
	await reveal(menu,list_variant)
	await shot("desktop-classic-list")
	await click(list_variant)
	check(menu.view=="detail" and menu.current==1036,"classic list also opens its growth variant")
	menu.search.text=""
	root.size=Vector2i(390,844);root.content_scale_size=root.size
	# Real remote teleport clicks use each new original Lv1 target and safe landing.
	for tid in [809,1110,1095]:
		menu.open_menu(tid)
		var entry: Dictionary=menu.book.entry_for(tid)
		var place: Dictionary=Book.best_location(entry)
		check(not place.is_empty() and int(place.level_min)==1 and str(place.origin)=="added","new pet has verified added Lv1 location: %d"%tid)
		var go=menu.body.find_child("GoPlace%d_%d_added"%[int(place.map_id),int(place.area_id)],true,false)
		await reveal(menu,go)
		await click(go)
		check(await Wait.until(self,func():return menu.pending_hunt.is_empty() and game.pet_hunt_menu.visible and int(game.data.map_id)==int(place.map_id)),"real remote click teleports to %d"%tid)
		check(await Wait.settle(self,game),"teleport settings round trip")
		check(int(game.automation_settings().hunt.template)==tid and int(game.automation_settings().hunt.stat_species)==tid,"both hunt target fields select %d"%tid)
		check(int(backend.encounter_catalog.area_at(int(place.map_id),Vector2i(int(place.cell[0]),int(place.cell[1]))).id)==int(place.area_id),"actual effective area contains target")
		game.pet_hunt_menu.close_menu()
	game.link.close();game.music.stop();game.effect.stop();game.queue_free();server.queue_free();backend.queue_free()
	await process_frame
	print("CLASSIC RIDING CATALOG: %d failures"%failures);quit(1 if failures else 0)

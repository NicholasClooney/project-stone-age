extends SceneTree
## Original gold-rex art through the production session, backend and GameScene.
const Riding = preload("res://scripts/riding.gd")
const SpriteArt = preload("res://scripts/sprite_art.gd")
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
const Wait = preload("res://tests/support/wait.gd")
const BODIES = [103266,103262,103263,103264,103272,103273,103265,103267,103269,103268,103271,103270]
const SHOTS = "/private/tmp/tmux-agents/golden-rex-riding-import/"
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok: failures += 1
func _initialize() -> void:call_deferred("run")
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(SHOTS+name+".png")==OK,"real rendered "+name)
func click(button: Control) -> void:
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)
	await process_frame
func run() -> void:
	var count := 0
	for body in range(12):
		for colour in range(4):
			var rider := str(100000+20*body+5*colour)
			if rider=="100100":continue
			count += 1
			var pair := Riding.pair(rider,100907)
			check(int(pair.get("sprite",-1))==BODIES[body] and not pair.has("certificate") and pair.get("source_certificate_namespace","")=="anson1788-lua","source pair "+rider)
	check(count==47 and Riding.composite("100030",100907)==103262,"47 selectable source pairs; 100030 uses 103262")
	for rider in ["100100","100700","100705","101177","100001"]:
		check(Riding.composite(rider,100907)<0 and not Riding.can_mount({"character_id":rider,"player":{"level":1},"pets":[{"sprite":100907,"hp":10,"level":1,"loyalty":100}],"active_pet":-1},0).is_empty(),"unsupported shape rejected "+rider)
	check(int(Riding.pair("100030",100369).get("certificate",-1))==13,"C Holk certificate bit 13 preserved")
	for composite in BODIES:
		var art := Riding.art(str(composite))
		var valid: bool = art.animations.size()==104
		var frames := 0
		for action in range(13):
			for direction in range(8):
				var animation: Dictionary = art.animations.get("%d_%d"%[action,direction],{})
				valid = valid and SpriteArt.frame_count(animation)>0
				for i in range(SpriteArt.frame_count(animation)):
					frames += 1
					var bitmap := SpriteArt.image(animation,i)
					var texture := Riding.frame_texture(str(composite),bitmap)
					valid = valid and texture!=null and PaletteSheet.is_palette(texture) and Vector2i(texture.get_size())==SpriteArt.image_size(art,bitmap)
		check(valid and frames==568,"all 104 clips / 568 frames / palette textures "+str(composite))
	await pack_downloads()
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	game.muted = true
	game.random_encounters = false
	game.load_area_id(100,Vector2i(600,500))
	check(game.session.set_character("100030") and game.session.gm_grant_pet(812),"real session grants template 812 to player 100030")
	check(game.session.grant_starter_pets() and game.session.select_pet(1),"independent active pet for follower")
	game.show_adventure_menu("pets")
	var menu = game.adventure_menu
	menu.selected_pet = 0
	menu.rebuild()
	var button: Button = menu.panel.find_child("PetMount",true,false)
	check(button!=null and not button.disabled,"production pet menu enables gold-rex riding")
	await click(button)
	check(await Wait.until(self,func():return game.player.mounted_character_id=="103262"),"ride button updates map composite")
	check(game.session.snapshot().player.get("riding_certificates",[]).is_empty(),"gold rex mount teaches no C certificate bit")
	check(int(game.session.snapshot().pets[0].template_id)==812 and int(game.session.snapshot().ride_pet)==0,"backend mounts actual template 812")
	check(game.pet_follower!=null,"map retains independent pet follower")
	game.close_adventure_menu()
	# Walk through the production movement/session path so the follower trails
	# behind instead of covering the mounted sprite at its spawn point.
	for step in range(4):
		var moved := false
		for direction in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1)]:
			if game.request_step(game.cell+direction):moved=true;break
		check(moved and await Wait.until(self,func():return not game.moving),"mounted original walking step "+str(step))
	await capture("golden-rex-map")
	if not game.begin_battle(false,1):
		check(false,"real backend begins mounted battle")
		game.queue_free();quit(1);return
	check(true,"real backend begins mounted battle")
	check(await Wait.until(self,func():return game.battle_view.visible and game.battle_view.actors[0].character_id=="103262" and not game.battle_view.is_animating()),"production battle draws gold-rex composite and accepts input")
	check(int(game.battle_session.snapshot().mounted_sprite)==103262 and game.battle_view.riding_hp_bar.visible,"backend battle carries actual mounted sprite and mount health")
	await capture("golden-rex-battle")
	var view = game.battle_view
	await click(view.commands[0])
	check(view.selected_action=="attack","real attack button selects command")
	await click(view.target_buttons[1])
	if view.command_phase=="pet":
		check(await Wait.until(self,func():return view.elapsed>=view.feedback_until),"pet command panel ready")
		for child in view.choice_panel.get_children():
			if child is Button and child.get_meta("pet_action","")=="defend":
				await click(child)
				break
	check(await Wait.until(self,func():return not game.battle_session.snapshot().get("last_player_command","").is_empty()),"battle target click submits through session/backend")
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	print("Golden rex riding failures: ",failures)
	quit(1 if failures else 0)

func pack_downloads() -> void:
	var store = preload("res://tests/asset_packs_test.gd").FakeStore.new()
	store.dir = "user://golden-rex-packs/"
	store.index = {"packs":{},"riding":{}}
	DirAccess.make_dir_recursive_absolute(store.dir)
	for composite in BODIES:
		var id := str(composite)
		var name := "riding-"+id
		var path: String = store.dir+name+".pck"
		var packer := PCKPacker.new()
		check(packer.pck_start(path)==OK,"start real PCK "+id)
		var source := Riding.ROOT+"composites/"+id+".json"
		check(packer.add_file(source,source)==OK,"PCK owns composite "+id)
		for file in Riding.art(id).files:
			var sheet := Riding.ROOT+str(file)
			check(packer.add_file(sheet,sheet)==OK,"PCK owns native palette sheet "+id)
		check(packer.flush()==OK,"write real PCK "+id)
		store.network[name+".pck"] = FileAccess.get_file_as_bytes(path)
		DirAccess.remove_absolute(path)
		store.index.packs[name] = {"file":name+".pck","bytes":store.network[name+".pck"].size()}
		store.index.riding[id] = name
	var packs := preload("res://scripts/asset_packs.gd").new()
	root.add_child(packs)
	packs.configure("https://test.invalid/",store)
	var loaded := [false]
	packs.load_index(func(ok: bool):loaded[0]=ok)
	check(await Wait.until(self,func():return loaded[0]),"load actual riding download index")
	var wanted := []
	for composite in BODIES:wanted.append(packs.riding_pack(composite))
	var ready := [false]
	packs.ensure(wanted,func(ok: bool):ready[0]=ok)
	check(await Wait.until(self,func():return ready[0]),"download and mount all twelve real gold-rex PCKs")
	check(packs.downloaded_count==12 and packs.is_ready(wanted) and store.network_requests.size()==12,"riding download entry resolves all twelve packages")
	packs.queue_free()
	await process_frame

extends SceneTree
var game
var failures := 0
var ticks_done := 0
const SAVE := "user://mvp-journey-test.json"
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
var palette_checked := false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, description: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+description)
	if not ok:failures += 1
func frames(n: int = 2) -> void:
	for i in range(n):await process_frame
func walk_until(map_id: int, modal: bool = false) -> void:
	for i in range(600):
		game._physics_process(0.5)
		while game.area_transition_busy:await process_frame
		if modal and (game.dialogue.visible or game.adventure_menu.visible):break
		if not modal and int(game.data.map_id)==map_id and not game.moving and game.path.is_empty():break
		if game.battle_view.visible:break
		if i%10==0:await frames()
	await frames()
func settle() -> void:
	for i in range(20):
		if not game.moving:break
		game._physics_process(0.5)
		while game.area_transition_busy:await process_frame
func fight(capture: bool = false, boss: bool = false) -> String:
	settle()
	if not game.battle_view.visible:
		check(game.begin_battle(boss,1),"encounter starts through world")
	for i in range(30):
		var s: Dictionary = game.battle_session.snapshot()
		if not s.active:break
		if capture:
			game.battle_session.set_pet_command("defend")
			game.battle_action("capture" if s.enemy_hp*100<=s.enemy_max_hp*60 else "attack")
		else:
			if s.skill_unlocked and not s.skill_used:game.battle_session.set_pet_command("skill")
			game.battle_action("item" if s.player_hp<18 and s.potions>0 else "attack")
	var outcome: String = game.battle_session.snapshot().outcome
	while game.battle_view.is_animating():game.battle_view._process(0.1)
	if not palette_checked:
		palette_checked = true
		game.battle_view._process(0.1)
		var drawn: Array = game.battle_view.actors.filter(func(actor):return actor.sprite.texture!=null)
		check(drawn.any(func(actor):return PaletteSheet.is_palette(actor.sprite.texture)) and drawn.all(func(actor):return actor.sprite.material==PaletteSheet.material_of(actor.sprite.texture)),"battle sprites draw from palette sheets with their sheet's material")
	game.return_from_battle()
	await frames()
	# Player growth is now chosen through the status menu, not automatic.
	if int(game.session.snapshot().player.stat_points)>0:
		game.show_adventure_menu("status")
		var allocated := 0
		while int(game.session.snapshot().player.stat_points)>0 and allocated<30:
			game.perform_adventure_action("allocate_stat",["strength","vitality","toughness"][allocated%3])
			allocated += 1
		check(int(game.session.snapshot().player.stat_points)==0,"level-up points applied through status menu")
		game.close_adventure_menu()
		await frames()
	return outcome
func visit_villager() -> void:
	if int(game.data.map_id)!=1000:game.load_area_id(1000,game.SPAWN)
	game.approach_npc()
	await walk_until(1000,true)
	check(game.dialogue.visible,"resident dialogue reached by walking")
	game.close_dialogue()
	game.show_adventure_menu("quest")
	check(game.adventure_menu.visible,"quest opens only at resident")
func recover() -> void:
	await visit_villager()
	game.perform_adventure_action("heal")
	check(game.session.snapshot().player.hp==game.session.snapshot().player.max_hp,"village recovery restores HP")
	game.close_adventure_menu()
	game.switch_area(true,Vector2i(45,45))
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	game.random_encounters = false
	await frames()
	await visit_villager()
	game.perform_adventure_action("accept_quest")
	check(game.session.snapshot().quest.accepted,"accept quest through village menu")
	game.close_adventure_menu()
	game.walk_to(Vector2i(67,108))
	await walk_until(1002)
	check(int(game.data.map_id)==1002,"walk through original shop doorway")
	game.approach_npc()
	await walk_until(1002,true)
	check(game.adventure_menu.visible and game.adventure_menu.kind=="shop" and game.cell==Vector2i(16,15),"merchant reached across original counter")
	var gold: int = game.session.snapshot().player.gold
	game.perform_adventure_action("buy_potion")
	check(game.session.snapshot().player.gold==gold-10,"original shop menu purchase changes authoritative balance")
	game.perform_adventure_action("sell_potion")
	check(game.session.snapshot().player.gold==gold-5,"shop sale pays half price")
	game.close_adventure_menu()
	game.walk_to_exit()
	await walk_until(1000)
	check(int(game.data.map_id)==1000,"shop return doorway works")
	game.walk_to_exit()
	await walk_until(100)
	check(int(game.data.map_id)==100,"wilderness reached from village")
	check(await fight(true)=="captured","capture creates first pet")
	check(game.session.snapshot().pets.size()==1 and is_instance_valid(game.pet_follower),"captured pet follows player")
	game.pet_follower._process(0.1)
	check(PaletteSheet.is_palette(game.pet_follower.sprite.texture) and game.pet_follower.sprite.material==PaletteSheet.material_of(game.pet_follower.sprite.texture),"the following pet draws from its palette sheet")
	game.show_adventure_menu("pets")
	await frames()
	check(game.adventure_menu.visible,"original pet tab opens roster")
	game.adventure_menu.pet_switch_view("detail")
	game.adventure_menu.pet_rename = true
	game.adventure_menu.rebuild()
	game.adventure_menu.name_edit.text = "小伙伴"
	game.perform_adventure_action("rename_pet",0)
	game.close_adventure_menu()
	check(game.session.snapshot().pets[0].name=="小伙伴" and game.pet_follower.pet_name=="小伙伴","rename affects roster and follower")
	for i in range(3):
		await recover()
		check(await fight()=="win","pet and player win progression encounter")
	check(game.session.snapshot().player.level>=2 and game.session.snapshot().pets[0].level >= 2,"player and pet gain original growth")
	await recover()
	check(game.session.can_fight_boss(),"quest unlocks tougher encounter")
	check(await fight(false,true)=="win","boss defeated with companion")
	await visit_villager()
	game.perform_adventure_action("claim_quest")
	check(game.session.snapshot().quest.claimed,"quest reward claimed via original dialogue flow")
	var reward_gold: int = game.session.snapshot().player.gold
	game.perform_adventure_action("claim_quest")
	check(game.session.snapshot().player.gold==reward_gold,"quest reward cannot be duplicated")
	game.close_adventure_menu()
	game.load_area_id(1002,Vector2i(11,15))
	game.approach_npc(); await walk_until(1002,true)
	game.perform_adventure_action("buy_club")
	game.close_adventure_menu()
	game.show_adventure_menu("inventory")
	game.perform_adventure_action("equip",true)
	check(game.session.snapshot().equipped,"equipment menu equips purchased club")
	game.close_adventure_menu()
	game.save_path = SAVE
	game.profile_persistence = true
	check(game.checkpoint(),"world saves finished progression and position")
	var expected: Dictionary = game.session.snapshot()
	game.profile_persistence = false
	game.music.stop();game.effect.stop();await create_timer(0.2).timeout
	game.queue_free();await frames()
	game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	game.save_path = SAVE
	# Login luck rerolls when the 5400-second native day changes; pin the clock
	# so a real day boundary between save and reload cannot alter the profile.
	var saved_luck_time:int=int(expected.player.get("last_luck_time",0))
	game.session.login_clock=func():return saved_luck_time
	check(game.session.load_game(SAVE),"new app session loads saved adventure")
	root.add_child(game);await frames()
	game.restore_location()
	await frames()
	var restored: Dictionary = game.session.snapshot()
	for key in expected:
		if restored.get(key)!=expected[key]:print("RESTORE DIFF %s: saved=%s restored=%s"%[key,str(expected[key]).left(300),str(restored.get(key)).left(300)])
	check(restored==expected,"all saved progression remains identical on world restore")
	check(int(game.data.map_id)==1002 and game.cell==Vector2i(16,15),"reload restores safe interior position")
	check(is_instance_valid(game.pet_follower),"reload restores companion")
	game.music.stop();game.effect.stop();await create_timer(0.2).timeout
	game.queue_free();await frames()
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))
	var bad_file := FileAccess.open(SAVE,FileAccess.WRITE)
	bad_file.store_string("unreadable original")
	bad_file.close()
	var fresh = load("res://scenes/main.tscn").instantiate()
	fresh.save_path = SAVE
	check(not fresh.load_profile() and not fresh.profile_persistence,"unreadable saves disable autosave rather than overwrite originals")
	check(FileAccess.get_file_as_string(SAVE)=="unreadable original","unreadable original file is preserved")
	fresh.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("MVP JOURNEY: %d failures" % failures)
	quit(1 if failures else 0)

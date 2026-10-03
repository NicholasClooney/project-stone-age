extends SceneTree
const Rules = preload("res://server/progression.gd")
const Game = preload("res://server/game_session.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok:print("PASS: "+message)
	else:
		failures += 1
		push_error("FAIL: "+message)
func _initialize() -> void:
	var stats := Rules.derived({"vitality":1000,"strength":1000,"toughness":1000,"dexterity":1000})
	check(stats == {"max_hp":70,"attack":12,"defence":12,"speed":10},"source four-stat coefficients and integer truncation")
	check(Rules.derived({"vitality":999,"strength":999,"toughness":999,"dexterity":999}).max_hp == 69,"fractional base stats survive until derived truncation")
	var game = Game.new()
	check(game.snapshot().player.max_hp == 47 and game.snapshot().player.attack == 8,"legal twenty-point starter")
	game._gain_xp(game._profile.player,30)
	check(game.snapshot().player.stat_points == 3,"three allocation points awarded")
	var before: Dictionary = game.snapshot().player
	check(game.allocate_stat("strength"),"allocate strength")
	check(game.snapshot().player.max_hp == before.max_hp+1,"strength also raises max HP")
	game._profile.inventory.club = 1
	check(game.equip_item() and game.effective_player_stats().attack == game.snapshot().player.attack+4,"equipment applies after base derivation once")

	var bulk=Game.new()
	bulk._profile.player.level=120
	var bulk_before: Dictionary=bulk.snapshot().player
	check(bulk.distribute_stats(["vitality","strength","dexterity"]),"hundreds of points distributed to selected stats")
	var allocated: Dictionary=bulk.snapshot().player.allocated_stats
	check(allocated=={"vitality":119,"strength":119,"toughness":0,"dexterity":119} and bulk.snapshot().player.stat_points==0,"exact three-way division leaves unselected stat unchanged")
	check(bulk.snapshot().player.max_hp>bulk_before.max_hp,"bulk allocation applies derived stats")
	bulk=Game.new();bulk._profile.player.level=2
	check(not bulk.distribute_stats(["vitality","invalid"]) and bulk.snapshot().player.stat_points==3,"invalid distribution is atomic")
	check(not bulk.distribute_stats(["strength","strength"]),"duplicate distribution rejected")
	check(bulk.distribute_stats(["vitality","strength","toughness","dexterity"]) and bulk.snapshot().player.allocated_stats.dexterity==0,"uneven remainder is deterministic")
	bulk=Game.new();bulk._profile.player.level=4
	check(bulk.allocate_stat("strength",100) and bulk.snapshot().player.allocated_stats.strength==9,"bulk UP clamps to remaining points")
	check(not bulk.allocate_stat("strength",-10),"negative allocation rejected")
	bulk=Game.new();bulk._profile.player.level=2;bulk.start_battle_config()
	check(not bulk.distribute_stats(["strength"]) and not bulk.allocate_stat("strength",2),"allocation blocked during active battle")
	var a := Rules.species_actor("wooli",1,101)
	var b := Rules.species_actor("wooli",1,101)
	Rules.grow_pet(a,2);Rules.grow_pet(b,2)
	check(a == b,"pet growth deterministic across restored seed")
	check(a.max_hp > Rules.species_actor("wooli",1,101).max_hp,"species pet gains HP from original growth")
	check(Rules.species_actor("wooli_wooli",1,101).base_stats != Rules.species_actor("wooli",1,101).base_stats,"species tables affect generation")
	var old: Dictionary = game.snapshot()
	old.version = 1
	old.erase("rebirth");old.player.erase("transmigration") # Historical format predates v7.
	check(not game._valid_profile(old),"v1 stats profile with v6 warehouse fields is an invalid hybrid")
	for key in Game.ItemStorage.FIELDS:old.erase(key)
	old.player.erase("base_stats")
	old.player.erase("legacy_stat_offset")
	old.player.max_hp = 65;old.player.hp = 42;old.player.attack = 13;old.player.defence = 2;old.player.speed = 12
	old.pets = [{"species":"wooli","name":"旧伙伴","sprite":100250,"hp":31,"max_hp":40,"attack":6,"defence":0,"speed":9,"level":2,"xp":10,"skill_unlocked":true}]
	old.active_pet = 0
	var path := "user://progression-migration-test.json"
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(old));file.close()
	var migrated = Game.new()
	var loaded_legacy: bool=migrated.load_game(path)
	check(loaded_legacy,"legacy save accepted")
	if not loaded_legacy:quit(1);return
	var restored: Dictionary = migrated.snapshot()
	for key in ["max_hp","hp","attack","defence","speed","level","xp","allocated_stats"]:
		check(restored.player[key] == old.player[key],"migration preserves player "+key)
	check(restored.pets.size()==old.pets.size(),"migration retains the original pet count")
	if restored.pets.size()!=old.pets.size():quit(1);return
	for key in old.pets[0]:
		if key=="skill_unlocked":
			# Existing load migration replaces the old unnamed boolean with the
			# authoritative learned skill list; it must not invent a paid skill.
			check(restored.pets[0].learned_skills.is_empty() and not restored.pets[0].skill_unlocked,"legacy unnamed skill flag normalizes to no learned skills")
		else:check(restored.pets[0][key]==old.pets[0][key],"migration preserves complete old pet field "+key)
	check(restored.pets[0].max_hp == 40 and restored.pets[0].attack == 6 and restored.pets[0].hp == 31,"migration preserves pet earned strength and damage")
	check(migrated.save_game(path) and migrated.load_game(path) and migrated.snapshot() == restored,"versioned migration idempotent")
	check(migrated.allocate_stat("toughness") and migrated.snapshot().player.max_hp == 66,"migrated allocation uses restored cross-stat formula")
	var malformed: Dictionary = migrated.snapshot()
	malformed.player.base_stats.strength = "bad"
	check(not migrated._valid_profile(malformed),"malformed fixed-point stats rejected")
	malformed = migrated.snapshot();malformed.pets[0].growth_weights = [1]
	check(not migrated._valid_profile(malformed),"malformed growth metadata rejected")
	migrated._profile.player.gold = 6000
	check(not migrated.learn_pet_skill(0,3),"training requires actual trainer location")
	check(migrated.set_location(1003,18,15),"reach trainer across counter")
	check(migrated.learn_pet_skill(0,3) and migrated.snapshot().player.gold == 4500,"original skill training charges source price")
	check(not migrated.learn_pet_skill(0,3) and not migrated.learn_pet_skill(5,10),"duplicate and invalid pet training rejected")
	check(migrated.save_game(path) and migrated.load_game(path) and migrated.snapshot().pets[0].learned_skills == [3],"trained skill survives JSON reload")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("PROGRESSION: %d failures" % failures)
	quit(1 if failures else 0)

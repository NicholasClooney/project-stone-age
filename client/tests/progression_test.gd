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
	var a := Rules.species_actor("wooli",1,101)
	var b := Rules.species_actor("wooli",1,101)
	Rules.grow_pet(a,2);Rules.grow_pet(b,2)
	check(a == b,"pet growth deterministic across restored seed")
	check(a.max_hp > Rules.species_actor("wooli",1,101).max_hp,"species pet gains HP from original growth")
	check(Rules.species_actor("wooli_wooli",1,101).base_stats != Rules.species_actor("wooli",1,101).base_stats,"species tables affect generation")
	var old: Dictionary = game.snapshot()
	old.version = 1
	old.player.erase("base_stats")
	old.player.erase("legacy_stat_offset")
	old.player.max_hp = 65;old.player.hp = 42;old.player.attack = 13;old.player.defence = 2;old.player.speed = 12
	old.pets = [{"species":"wooli","name":"旧伙伴","sprite":100250,"hp":31,"max_hp":40,"attack":6,"defence":0,"speed":9,"level":2,"xp":10,"skill_unlocked":true}]
	old.active_pet = 0
	var path := "user://progression-migration-test.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(old));file.close()
	var migrated = Game.new()
	check(migrated.load_game(path),"legacy save accepted")
	var restored: Dictionary = migrated.snapshot()
	for key in ["max_hp","hp","attack","defence","speed","level","xp","allocated_stats"]:
		check(restored.player[key] == old.player[key],"migration preserves player "+key)
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

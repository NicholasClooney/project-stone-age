extends SceneTree
const Game = preload("res://server/game_session.gd")
const Battle = preload("res://server/battle_session.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error("FAIL: " + message)
		failures += 1
	else:
		print("PASS: " + message)
func fight(game, capture: bool = false, boss: bool = false) -> Dictionary:
	var battle = Battle.new()
	var config: Dictionary = game.start_battle_config("wooli",boss)
	if config.is_empty():
		return {}
	battle.start_battle(config)
	while battle.snapshot().active:
		var state: Dictionary = battle.snapshot()
		if capture and state.enemy_hp * 100 <= state.enemy_max_hp * 60:
			battle.submit_action("capture")
		elif state.player_hp < 15 and state.potions > 0:
			battle.submit_action("item")
		else:
			battle.submit_action("attack")
	var result: Dictionary = battle.snapshot()
	check(game.apply_battle_result(result),"authority applies terminal result")
	check(not game.apply_battle_result(result),"battle reward is idempotent")
	return result
func _initialize() -> void:
	var game = Game.new()
	var copy: Dictionary = game.snapshot()
	copy.player.gold = 999
	check(game.snapshot().player.gold == 20,"snapshot is isolated")
	check(not game.buy_item("unknown") and not game.select_pet(0) and not game.claim_quest(),"invalid commands rejected")
	check(game.accept_quest() and not game.accept_quest(),"quest accepts once")
	check(not game.can_fight_boss(),"boss progression gate")
	check(fight(game,true).outcome == "captured","weakened enemy captured")
	check(game.snapshot().pets.size() == 1 and game.snapshot().active_pet == 0,"first captured pet joins battle slot")
	check(game.rename_pet(0,"小伙伴") and not game.rename_pet(0,""),"pet rename validated")
	for i in range(3):
		game.heal()
		check(fight(game).outcome == "win","player and pet win encounter")
	check(game.snapshot().player.level > 1 and game.snapshot().pets[0].level > 1,"player and pet earn levels")
	check(game.can_fight_boss(),"three wins and capture unlock boss")
	game.heal()
	check(fight(game,false,true).outcome == "win","boss beatable through progression")
	check(game.claim_quest() and not game.claim_quest(),"quest reward claimed once")
	var before_stats: Dictionary = game.snapshot().player
	check(before_stats.stat_points == (before_stats.level-1)*3,"level-ups award three allocatable points")
	check(not game.allocate_stat("bad"),"unknown allocation rejected")
	for stat in ["vitality","strength","toughness","dexterity"]:
		check(game.allocate_stat(stat),"allocate " + stat)
	var after_stats: Dictionary = game.snapshot().player
	check(after_stats.max_hp == before_stats.max_hp+7 and after_stats.attack == before_stats.attack+1 and after_stats.defence == before_stats.defence+2 and after_stats.speed == before_stats.speed+1,"all four allocations affect combat stats")
	while game.snapshot().player.stat_points > 0:game.allocate_stat("strength")
	check(not game.allocate_stat("strength") and game.snapshot().player.stat_points == 0,"cannot overspend allocation points")
	check(game.buy_item("club") and game.equip_item("club"),"shop weapon equipment")
	check(not game.sell_item("club"),"cannot sell equipped last weapon")
	check(game.buy_item("potion") and game.sell_item("potion"),"buy and sell validated")
	check(game.set_location(1002,10,15) and not game.set_location(9,0,0),"location validates map")
	var path := "user://mvp-authority-test.json"
	check(game.save_game(path),"atomic save succeeds")
	var restored = Game.new()
	check(restored.load_game(path),"load succeeds")
	check(restored.snapshot().pets == game.snapshot().pets and restored.snapshot().quest == game.snapshot().quest,"save preserves progression and pets")
	check(restored.snapshot().location == game.snapshot().location,"save preserves valid location")
	for malformed in [null, [], {"version":1}, {"version":1,"profile_id":"samgir-singleplayer-v1","player":[]}]:
		check(not game._valid_profile(malformed),"malformed save type rejected")
	var forged: Dictionary = game.snapshot()
	forged.location.x = "bad"
	check(not game._valid_profile(forged),"invalid coordinate rejected")
	forged = game.snapshot()
	forged.completed_battles = [42]
	check(not game._valid_profile(forged),"invalid replay log rejected")
	check(game.save_game(path),"second save creates backup")
	var broken := FileAccess.open(path,FileAccess.WRITE)
	broken.store_string('{"version":1}')
	broken.close()
	check(restored.load_game(path),"corrupt primary recovers verified backup")
	var legacy_path := path + ".legacy"
	var legacy: Dictionary = game.snapshot()
	legacy.player.erase("stat_points")
	legacy.player.erase("allocated_stats")
	var legacy_file := FileAccess.open(legacy_path,FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	var migrated = Game.new()
	check(migrated.load_game(legacy_path) and migrated.snapshot().player.stat_points == (legacy.player.level-1)*3,"older leveled save gains missing allocation budget")
	check(migrated.allocate_stat("vitality") and migrated.save_game(legacy_path),"migrated allocation saves")
	var migrated_profile: Dictionary = migrated.snapshot()
	check(migrated.load_game(legacy_path) and migrated.snapshot() == migrated_profile,"migration cannot grant duplicate points after save reload")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path+suffix))
	var stale: Dictionary = migrated_profile.duplicate(true)
	stale.player.stat_points = 0
	var stale_file := FileAccess.open(legacy_path,FileAccess.WRITE)
	stale_file.store_string(JSON.stringify(stale));stale_file.close()
	check(migrated.load_game(legacy_path) and migrated.snapshot().player.stat_points == migrated_profile.player.stat_points,"stale zero points repaired from unspent level budget")
	stale.player.erase("stat_points")
	stale_file = FileAccess.open(legacy_path,FileAccess.WRITE)
	stale_file.store_string(JSON.stringify(stale));stale_file.close()
	check(migrated.load_game(legacy_path) and migrated.snapshot().player.allocated_stats == migrated_profile.player.allocated_stats and migrated.snapshot().player.stat_points == migrated_profile.player.stat_points,"missing points repaired without refunding spent allocations")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	var config: Dictionary = game.start_battle_config()
	var fake := {"active":false,"battle_id":config.battle_id,"outcome":"win","player_hp":48,"potions":config.potions,"enemy_hp":20}
	check(not game.apply_battle_result(fake),"impossible win rejected")
	check(not game.save_game(path) and not game.heal() and game.start_battle_config().is_empty(),"active battle blocks out of combat changes")
	# Guaranteed-danger fixture: native weak foes may deal zero against guarding defence.
	config.enemies[0].attack = 100
	var battle = Battle.new()
	battle.start_battle(config)
	while battle.snapshot().active:
		battle.set_pet_command("defend")
		battle.submit_action("defend")
	check(game.apply_battle_result(battle.snapshot()),"defeat result accepted")
	check(game.snapshot().player.hp == game.snapshot().player.max_hp and game.snapshot().location.map_id == 1000,"defeat safely recovers in village")
	game.select_pet(-1)
	for i in range(Game.PET_CAPACITY-game.snapshot().pets.size()):
		game.heal()
		# Isolate collection capacity from random critical hits that can kill a
		# low-level target while weakening it. Capture and settlement remain real.
		config = game.start_battle_config()
		config.enemies[0].hp = int(config.enemies[0].max_hp/2)
		battle = Battle.new()
		battle.start_battle(config)
		battle.submit_action("capture")
		check(battle.snapshot().outcome == "captured" and game.apply_battle_result(battle.snapshot()),"additional roster capture")
	check(game.snapshot().pets.size() == Game.PET_CAPACITY,"expanded collection limit reached")
	config = game.start_battle_config()
	battle = Battle.new()
	battle.start_battle(config)
	var before: Dictionary = battle.snapshot()
	check(battle.submit_action("capture") == before,"full roster rejects capture without consuming turn")
	check(not battle.set_pet_command("skill"),"absent pet cannot issue skill")
	for suffix in ["",".bak",".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var malformed_file := FileAccess.open(path,FileAccess.WRITE)
	malformed_file.store_string("unreadable original")
	malformed_file.close()
	var untouched = Game.new()
	var original_profile: Dictionary = untouched.snapshot()
	check(not untouched.load_game(path) and untouched.snapshot() == original_profile,"malformed JSON rejected quietly without changing profile")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("MVP authority failures: ",failures)
	quit(1 if failures else 0)

extends SceneTree
const Game = preload("res://server/game_session.gd")
const Growth = preload("res://server/progression.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+text)
	if not ok:failures += 1
func _initialize() -> void:
	var game = Game.new()
	check(game.claim_default_companions(),"default companions can be claimed once")
	check(not game.claim_default_companions(),"normal startup claim cannot repeat")
	var profile: Dictionary = game.snapshot()
	check(profile.pets.size()==3 and profile.pets[0].sprite==100288 and profile.pets[1].sprite==100330 and profile.pets[2].sprite==100373,"blue dragon, gold tiger and exactly one red rex use verified original IDs")
	check(game.grant_starter_pets() and game.snapshot().pets.size()==3,"repeated starter grant never duplicates companions")
	var imported: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/pets/catalog.json"))
	for species in imported:
		check(imported[species].initial == Growth.SPECIES[species].initial and imported[species].weights.map(func(value):return int(value)) == Growth.SPECIES[species].weights,"growth parameters agree with original template: "+species)
	check(game.select_pet(0) and game.set_character("100010") and game.mount_pet(1),"blue dragon fights while compatible character rides gold tiger")
	check(not game.select_pet(1),"riding pet cannot also occupy battle companion slot")
	var stats: Dictionary = game.effective_player_stats()
	check(stats.attack>game.snapshot().player.attack,"riding changes effective combat stats")
	check(game.save_game("user://starter-pets-test.json"),"starter pack and mount save")
	var restored = Game.new()
	check(restored.load_game("user://starter-pets-test.json") and restored.snapshot().ride_pet==1 and restored.snapshot().pets.size()==3,"starter pack and mount survive reload")
	var config: Dictionary = restored.start_battle_config()
	check(config.ride_pet_index==1 and config.mounted_sprite==101006 and config.player_attack==restored.snapshot().player.attack,"battle receives original mounted sprite and unmodified inputs to avoid double stat bonus")
	check(not restored.grant_starter_pets() and not restored.mount_pet(-1),"battle locks roster and mounting mutations")
	check(game.set_character("100000") and game.snapshot().ride_pet == -1,"unsupported character safely dismounts")
	for suffix in ["",".bak",".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://starter-pets-test.json"+suffix))
	quit(1 if failures else 0)

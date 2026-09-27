extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok: failures += 1
func _initialize() -> void:
	var session = preload("res://server/game_session.gd").new()
	session.grant_starter_pets()
	session.set_character("100010")
	var before: Dictionary = session.snapshot()
	var mount_index := -1
	for i in range(before.pets.size()):
		if int(before.pets[i].sprite) == 100330: mount_index = i
	check(mount_index >= 0 and session.mount_pet(mount_index),"native gold tiger mount available")
	var config: Dictionary = session.start_battle_config("wooli",false,1)
	# Isolate reward bookkeeping from the already-covered combat probability.
	config.player_attack = 10000
	config.player_speed = 10000
	var battle = preload("res://server/battle_session.gd").new()
	battle.start_battle(config)
	var result: Dictionary = battle.submit_action("attack")
	check(result.outcome == "win" and result.enemies[0].get("defeated_with_ride_index",-1) == mount_index,"rider kill records its living mount")
	var forged := result.duplicate(true)
	forged.enemies[0].defeated_with_ride_index = 0
	check(not session.apply_battle_result(forged),"settlement rejects mount reward assigned to unrelated pet")
	check(session.apply_battle_result(result),"mounted battle settles successfully")
	var after: Dictionary = session.snapshot()
	check(int(after.pets[mount_index].xp) == 12,"living mount receives original60percent reward")
	check(int(after.ride_pet) == mount_index,"healthy mount remains mounted after victory")
	for ending in ["mixed","capture_only","escaped","defeat","mount_ko","pet_kill"]:check_outcome(ending)
	var riding = preload("res://scripts/riding.gd")
	check(riding.experience(20,6,1)==12,"level gap5 receives full mounted rate")
	check(riding.experience(20,7,1)==10,"level gap6 truncates penalty before60percent")
	check(riding.experience(20,21,1)==0 and riding.experience(1,1,1)==0,"minimum pre-share1XP can truncate to0 for mount")
	print("Riding settlement failures: ",failures)
	quit(1 if failures else 0)

func check_outcome(ending: String) -> void:
	var session = preload("res://server/game_session.gd").new()
	session.grant_starter_pets()
	session.set_character("100010")
	var mount := -1
	var profile: Dictionary = session.snapshot()
	for i in range(profile.pets.size()):
		if int(profile.pets[i].sprite)==100330:mount=i
	session.mount_pet(mount)
	var config: Dictionary = session.start_battle_config("wooli",false,2)
	var battle = preload("res://server/battle_session.gd").new()
	var result: Dictionary = battle.start_battle(config)
	# Terminal fixtures isolate settlement: authority-produced kill is covered above.
	result.active=false
	result.outcome="captured"
	result.enemies[0].hp=0
	result.enemies[0]["defeated_with_ride_index"]=mount
	result.enemies[1].hp=0
	result.enemies[1].captured=true
	result.captured_species_list=["wooli"]
	if ending=="capture_only":
		result.enemies[0].captured=true
		result.captured_species_list.append("wooli")
	elif ending in ["escaped","defeat"]:
		result.outcome=ending
		result.enemies[1].captured=false
		result.enemies[1].hp=config.enemies[1].max_hp
		result.captured_species_list=[]
		if ending=="defeat":result.player_hp=0
	elif ending=="mount_ko":
		result.pets[mount].hp=0
		result.ride_pet=-1
	elif ending=="pet_kill":
		result.enemies[0].defeated_with_ride_index=-1
	check(session.apply_battle_result(result),ending+" settlement accepted")
	var expected := 12 if ending=="mixed" else 0
	check(int(session.snapshot().pets[mount].xp)==expected,ending+" mount XP only from eligible rider kills")
	check(int(result.xp)==(20 if ending in ["mixed","mount_ko","pet_kill"] else 0),ending+" captures do not invent kill rewards")

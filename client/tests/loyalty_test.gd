extends SceneTree
## 人物魅力 and 宠物忠诚度 (server/loyalty.gd): the pinned formulas, the battle
## loyalty check in manual and automated battles, settlement changes and the
## save migration. Real rules and sessions; battles use fixed seeds.
const Loyalty = preload("res://server/loyalty.gd")
const Game = preload("res://server/game_session.gd")
const Battle = preload("res://server/battle_session.gd")
const Growth = preload("res://server/progression.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures += 1

func _initialize() -> void:
	formulas()
	loyalty_check()
	migration()
	capture_and_settlement()
	battles()
	quit(1 if failures else 0)

func formulas() -> void:
	# char.c:2924: 1 × 60 × 1.1 / (1 × 150) × 100 = 44.
	check(Loyalty.value(1,60,1,150,0)==44,"Lv1 owner, charm 60, Lv1 乌力 (modai 150): loyalty 44")
	check(Loyalty.value(30,60,1,300,0)==100,"the owner part caps at 100")
	check(Loyalty.value(30,60,1,300,-4000)==60 and Loyalty.value(30,60,1,300,10000)==100,"variable part adds in hundredths, total caps at 100")
	check(Loyalty.value(1,60,1,0,0)==66,"modai 0 counts as 100")
	check(Loyalty.value(1,60,40,300,-2000)==0,"loyalty never goes below 0")
	check(Loyalty.capture_variable(30,60,1,300)==-4000,"a caught pet above 60 owes the excess (starts at 60)")
	check(Loyalty.capture_variable(1,60,1,150)==0,"a caught pet at or below 60 keeps its formula value")
	var pet := {"variable_ai":9800}
	Loyalty.add_variable(pet,Loyalty.AI_PET_LEVEL_UP)
	check(pet.variable_ai==10000,"variable part is clamped at +10000")
	var player := {"charm":99}
	Loyalty.add_charm(player,Loyalty.CHARM_PLAYER_LEVEL_UP)
	check(player.charm==100,"charm is capped at 100")
	Loyalty.add_charm(player,-200)
	check(player.charm==0,"charm never goes below 0")
	check(Loyalty.death_penalty(Loyalty.CHARM_PLAYER_DEAD,10)==-1 and Loyalty.death_penalty(Loyalty.AI_PET_DEAD,11)==-500,"death penalties halve up to owner level 10")

func loyalty_check() -> void:
	check(Loyalty.check(80,1)=="normal" and Loyalty.check(100,1)=="normal","80 or more always obeys")
	check(Loyalty.check(79,9)=="random_target" and Loyalty.check(79,10)=="normal","70-79: roll below 10 picks a random target")
	check(Loyalty.check(60,19)=="random_target" and Loyalty.check(60,20)=="normal","60-69: below 20")
	check(Loyalty.check(50,34)=="random_target" and Loyalty.check(50,35)=="normal","50-59: below 35")
	check(Loyalty.check(40,49)=="random_target" and Loyalty.check(40,50)=="normal","40-49: below 50")
	check(Loyalty.check(39,69)=="random_action" and Loyalty.check(20,69)=="random_action" and Loyalty.check(20,70)=="normal","20-39: below 70 acts at random")
	check(Loyalty.check(19,79)=="attack_owner" and Loyalty.check(10,80)=="attack_enemy","10-19: attacks its owner below 80, else an enemy")
	check(Loyalty.check(9,59)=="attack_owner" and Loyalty.check(0,60)=="escape","below 10: attacks its owner below 60, else leaves")

func migration() -> void:
	var player := {"level":50,"charm":60}
	Loyalty.migrate_charm(player)
	check(player.charm==100 and player.charm_rules==1,"old Lv50 save: +2 charm per level gained, capped at 100")
	player.charm = 70
	Loyalty.migrate_charm(player)
	check(player.charm==70,"charm migrates once")
	var young := {"level":6,"charm":60}
	Loyalty.migrate_charm(young)
	check(young.charm==70,"old Lv6 save: 60 + 10")
	var trained := {"species":"wooli","level":120}
	Loyalty.migrate_pet(trained,player)
	Loyalty.refresh(trained,player)
	check(trained.variable_ai==10000 and trained.loyalty==100,"an old Lv120 pet migrates to loyalty 100")
	var fresh := {"species":"wooli","level":1}
	Loyalty.migrate_pet(fresh,{"level":50,"charm":100})
	Loyalty.refresh(fresh,{"level":50,"charm":100})
	check(fresh.loyalty==60,"an old Lv1 pet of a strong owner migrates like a new catch: 60")
	var mid := {"species":"wooli","level":9}
	Loyalty.migrate_pet(mid,{"level":50,"charm":100})
	Loyalty.refresh(mid,{"level":50,"charm":100})
	check(mid.loyalty==100,"Lv9: +40 from eight level-ups on top of 60")
	var starter := {"species":"blue_dragon","level":1,"loyalty":100}
	Loyalty.migrate_pet(starter,player)
	check(starter.variable_ai==Loyalty.AI_GM_PET,"the developer starter pack keeps loyalty 100")
	# Saved and loaded through the session.
	var game := Game.new()
	game._profile.player.level = 20
	game._profile.player.erase("charm_rules")
	var old := Growth.species_actor("wooli",1,7)
	old.merge({"species":"wooli","name":"老乌力","sprite":100250,"level":40,"xp":0,"skill_unlocked":false})
	game._profile.pets = [old]
	game._profile.active_pet = 0
	var path := "/tmp/stoneage-loyalty-migration-test.json"
	check(game.save_game(path),"pre-rules profile saves")
	var loaded := Game.new()
	check(loaded.load_game(path),"pre-rules profile loads")
	var state: Dictionary = loaded.snapshot()
	check(state.player.charm==98 and state.pets[0].loyalty==100,"load migrates charm (60+38) and the Lv40 pet (loyalty 100)")
	check(loaded.save_game(path) and Game.new().load_game(path),"migrated profile saves and loads again")

func wild_config(game) -> Dictionary:
	var config: Dictionary = game.start_battle_config("wooli",false,1)
	config.player_attack = 1000;config.player_speed = 1000;config.player_defence = 1000
	return config

func capture_and_settlement() -> void:
	var game := Game.new()
	game._profile.player.level = 30
	var config := wild_config(game)
	config.capture_bonus = 200
	for enemy in config.enemies:enemy.hp = 1
	var battle := Battle.new();battle.start_battle(config)
	battle.submit_action("capture",0)
	var result: Dictionary = battle.snapshot()
	check(result.outcome=="captured" and game.apply_battle_result(result),"guaranteed capture settles")
	var caught: Dictionary = game.snapshot().pets[0]
	check(caught.modai==150 and caught.variable_ai==-4000 and caught.loyalty==60,"a Lv1 乌力 caught by a Lv30 owner starts at loyalty 60 (modai from enemybase)")
	# A win that levels the pet: +5 per level and the kill bonus.
	game._profile.active_pet = 0
	config = wild_config(game)
	# The session settles from its own copy of the troop (game._pending).
	for troop in [config,game._pending]:
		troop.enemies[0].level = 3
		troop.enemies[0].reward_xp = 30
	battle = Battle.new();battle.start_battle(config)
	battle.submit_action("attack",0)
	result = battle.snapshot()
	check(result.outcome=="win" and game.apply_battle_result(result),"a win settles")
	caught = game.snapshot().pets[0]
	check(caught.level==2 and caught.variable_ai==-4000+Loyalty.AI_PET_GOLD_WIN+Loyalty.AI_PET_LEVEL_UP,"a kill of a higher-level enemy (+0.2) and one level-up (+5)")
	# A defeat: charm -2 and the out pet -1 (owner above level 10).
	var charm := int(game.snapshot().player.charm)
	var before := int(caught.variable_ai)
	config = wild_config(game)
	config.player_defence = 0
	config.enemies[0].attack = 100000
	battle = Battle.new();battle.start_battle(config)
	for turn in range(40):
		if not battle.snapshot().active:break
		battle.set_pet_command("defend")
		battle.submit_action("defend")
	result = battle.snapshot()
	check(result.outcome=="defeat" and game.apply_battle_result(result),"a defeat settles")
	var after: Dictionary = game.snapshot()
	var died: bool = int(result.pets[0].hp)==0
	check(after.player.charm==charm-2,"the owner falling costs 2 charm")
	check(after.pets[0].variable_ai==before+Loyalty.AI_PLAYER_DEAD+(Loyalty.AI_PET_DEAD if died else 0),"the out pet loses 1 loyalty (and 5 more if it fell)")

func battle_with(loyalty: int, seed_value: int, automated: bool) -> Battle:
	var game := Game.new()
	var pet := Growth.species_actor("wooli",1,11)
	pet.merge({"species":"wooli","name":"小乌力","sprite":100250,"level":1,"xp":0,"skill_unlocked":false})
	game._profile.pets = [pet]
	game._profile.active_pet = 0
	var config: Dictionary = game.start_battle_config("wooli",false,3)
	config.pet.loyalty = loyalty;config.pets[0].loyalty = loyalty
	for enemy in config.enemies:
		enemy.hp = 100000;enemy.max_hp = 100000;enemy.attack = 1
	config.player_defence = 1000
	var battle := Battle.new()
	battle.rng_seed = seed_value
	battle.automated = automated
	battle.start_battle(config)
	return battle

func battles() -> void:
	# A loyal pet draws no loyalty roll: seeded battles are unchanged.
	var a := battle_with(80,5,false);var b := battle_with(100,5,false)
	for turn in range(5):
		a.submit_action("defend");b.submit_action("defend")
	check(a.snapshot().enemies==b.snapshot().enemies and a.snapshot().events==b.snapshot().events,"loyalty 80 and 100 play the same seeded battle")
	# Below 10 the pet attacks its owner or leaves; over many turns both happen.
	var seen := {}
	for seed_value in range(1,30):
		var battle := battle_with(0,seed_value,false)
		battle.submit_action("defend")
		var state: Dictionary = battle.snapshot()
		for frame in state.turn_frames:
			if frame.actor=="pet" and not str(frame.disobey).is_empty():seen[str(frame.disobey)] = true
		if seen.has("escape") and state.active_pet==-1:
			check(state.pet_escapes==1 and state.pet.is_empty(),"a pet that leaves is out of the battle and counted")
	check(seen.has("attack_owner") and seen.has("escape"),"loyalty 0: attacks its owner and leaves")
	# Automated battles: a disobeying pet only loses its action.
	var automated_seen := {}
	var owner_hurt := false
	for seed_value in range(1,30):
		var battle := battle_with(0,seed_value,true)
		battle.submit_action("defend")
		var state: Dictionary = battle.snapshot()
		for frame in state.turn_frames:
			if frame.actor=="pet" and not str(frame.disobey).is_empty():
				automated_seen[str(frame.disobey)] = true
				check(frame.outcome=="standby","automated disobedience is a skipped action")
		owner_hurt = owner_hurt or state.active_pet!=0 or int(state.pet_escapes)!=0
	check(automated_seen.has("attack_owner") or automated_seen.has("escape"),"automated battles still roll the check")
	check(not owner_hurt,"automated: the pet never leaves")
	# 40-79: sometimes a random target, never the owner.
	var random_seen := false
	for seed_value in range(1,40):
		var battle := battle_with(45,seed_value,false)
		battle.set_pet_target(0)
		battle.submit_action("defend")
		for frame in battle.snapshot().turn_frames:
			if frame.actor=="pet" and frame.disobey=="random_target":random_seen = true
			if frame.actor=="pet":check(frame.disobey in ["","random_target"],"loyalty 45 only mistargets")
	check(random_seen,"loyalty 45 sometimes attacks a random enemy")

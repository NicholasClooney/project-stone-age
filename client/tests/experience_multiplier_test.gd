extends SceneTree
const Session = preload("res://server/game_session.gd")
const Battle = preload("res://server/battle_session.gd")
const Riding = preload("res://scripts/riding.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures+=1
func lifetime_xp(actor: Dictionary) -> int:
	return int(actor.xp)+int(actor.level)*int(actor.level-1)*15
func _initialize() -> void:
	for multiplier in [1,2,10,100]:verify_multiplier(multiplier)
	var session = Session.new()
	check(session.experience_multiplier==1,"assist is opt-in")
	for invalid in [0,-1,3,1000]:
		session.experience_multiplier=invalid
		check(session.experience_multiplier==1,"unsupported multiplier falls back to ordinary XP")
	for ending in ["escaped","defeat","captured"]:verify_no_reward(ending)
	verify_wild_rounding()
	verify_level_cap()
	print("EXPERIENCE MULTIPLIER: %d failures" % failures)
	quit(1 if failures else 0)
func verify_multiplier(multiplier: int) -> void:
	var session = Session.new()
	session.grant_starter_pets()
	session.set_character("100010")
	session.select_pet(0)
	check(session.mount_pet(1),"riding setup")
	session.experience_multiplier=multiplier
	var config: Dictionary=session.start_battle_config("wooli",false,2)
	check(config.experience_multiplier==multiplier,"battle snapshots %dx" % multiplier)
	# Public return values and settings cannot rewrite the authoritative snapshot.
	config.experience_multiplier=1000
	session.experience_multiplier=1 if multiplier!=1 else 100
	var battle = Battle.new()
	var result: Dictionary=battle.start_battle(config)
	result.active=false
	result.outcome="win"
	for foe in result.enemies:foe.hp=0
	result.enemies[0].defeated_by_pet_index=0
	result.enemies[1].defeated_with_ride_index=1
	check(session.apply_battle_result(result),"victory settles %dx" % multiplier)
	var profile: Dictionary=session.snapshot()
	check(result.xp==40*multiplier and lifetime_xp(profile.player)==40*multiplier,"player gets multiplier exactly once")
	check(result.experience_multiplier==multiplier,"settlement reports authoritative multiplier")
	check(profile.player.gold==40 and result.gold==20,"stone currency never multiplied")
	check(lifetime_xp(profile.pets[0])==20*multiplier,"active pet gets multiplied kill XP")
	check(lifetime_xp(profile.pets[1])==Riding.experience(20*multiplier,1,1),"mount shares multiplied XP through original rate")
	check(lifetime_xp(profile.pets[2])==0,"standby pet gets no XP")
	check(profile.player.stat_points==(profile.player.level-1)*3,"all crossed levels grant stat points")
	check(not session.apply_battle_result(result) and session.snapshot()==profile,"replayed settlement gives no duplicate rewards")
func verify_no_reward(ending: String) -> void:
	var session = Session.new()
	session.experience_multiplier=100
	var config: Dictionary=session.start_battle_config()
	var battle = Battle.new()
	var result: Dictionary=battle.start_battle(config)
	result.active=false
	result.outcome=ending
	if ending=="defeat":result.player_hp=0
	if ending=="captured":
		result.enemies[0].hp=0
		result.enemies[0].captured=true
		result.captured_species_list=["wooli"]
	check(session.apply_battle_result(result),ending+" settles")
	check(result.xp==0 and result.gold==0 and lifetime_xp(session.snapshot().player)==0,ending+" earns no fabricated rewards")

func verify_wild_rounding() -> void:
	var session = Session.new()
	session.grant_starter_pets()
	session.set_character("100010")
	session.gm_raise_level(-1,2)
	session.gm_raise_level(1,7)
	check(session.mount_pet(1),"over-level mount setup")
	var enemy: Dictionary=preload("res://server/progression.gd").species_actor("original_113",1,123)
	enemy.merge({"species":"original_113","name":"昆依","sprite":100297,"level":1,"reward_xp":7,"reward_gold":3,"can_capture":true},true)
	session.experience_multiplier=10
	var config: Dictionary=session.start_wild_battle_config({"enemies":[enemy],"area_id":1,"group_id":2})
	check(not config.is_empty() and config.experience_multiplier==10,"source encounter snapshots multiplier")
	var before: Dictionary=session.snapshot()
	var result: Dictionary=Battle.new().start_battle(config)
	result.active=false
	result.outcome="win"
	result.enemies[0].hp=0
	result.enemies[0].defeated_with_ride_index=1
	check(session.apply_battle_result(result),"source encounter settles")
	check(lifetime_xp(session.snapshot().pets[1])-lifetime_xp(before.pets[1])==39,"multiplier precedes mount penalty and integer rounding")
	check(result.xp==70 and result.gold==3+int(config.battle_gold),"source XP amplified; currency is troop gold plus one unmultiplied battle payout")

func verify_level_cap() -> void:
	var session = Session.new()
	session.grant_starter_pets()
	# Maximum legal ten-enemy source reward at 100x; no unbounded growth loop.
	var huge_reward: int=1000000000*10*100
	session._gain_xp(session._profile.player,huge_reward)
	session._gain_xp(session._profile.pets[0],huge_reward)
	var profile: Dictionary=session.snapshot()
	check(profile.player.level==120 and profile.player.xp==0,"huge player reward stops at supported Lv120")
	check(profile.pets[0].level==120 and profile.pets[0].xp==0,"huge pet reward stops at supported Lv120")
	check(profile.player.stat_points==357,"level cap grants all 119 levels of allocation points")
	check(session._valid_profile(profile),"maximum assisted reward leaves a valid save profile")
	session._gain_xp(session._profile.player,huge_reward)
	session._gain_xp(session._profile.pets[0],huge_reward)
	check(session.snapshot()==profile,"further XP at cap does not change level or growth")

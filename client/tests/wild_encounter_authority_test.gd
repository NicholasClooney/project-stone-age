extends SceneTree
const Catalog = preload("res://server/encounter_catalog.gd")
const Session = preload("res://server/game_session.gd")
const Battle = preload("res://server/battle_session.gd")
const Rules = preload("res://server/progression.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures += 1
func _initialize() -> void:
	var catalog = Catalog.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 892
	var actor: Dictionary = catalog.actor(120,rng)
	actor.can_capture=true
	var original := actor.duplicate(true)
	var session = Session.new()
	var config: Dictionary = session.start_wild_battle_config({"area_id":21,"group_id":88,"enemies":[actor]})
	check(not config.is_empty() and config.enemies[0].level==original.level,"source wild config keeps actual encounter level")
	check(session.start_wild_battle_config({"enemies":[actor]}).is_empty(),"pending battle cannot be overwritten")
	var battle = Battle.new()
	var result: Dictionary = battle.start_battle(config)
	result.active=false;result.outcome="captured";result.enemies[0].hp=0;result.enemies[0].captured=true
	result.captured_species_list=[original.species]
	check(session.apply_battle_result(result),"source capture settles")
	var pet: Dictionary = session.snapshot().pets[0]
	check(pet.level==original.level and pet.base_stats==original.base_stats and pet.growth_weights==original.growth_weights,"capture preserves wild level, stats and growth rolls")
	check(pet.hp==pet.max_hp and pet.xp==0,"captured animal starts healthy without invented XP")
	check(not session.apply_battle_result(result),"capture settlement cannot replay")
	var path := "user://wild-encounter-authority-test.json"
	check(session.save_game(path),"source companion saves")
	var restored = Session.new()
	check(restored.load_game(path),"source companion loads through template validation")
	check(restored.snapshot().pets[0].base_stats==pet.base_stats,"save roundtrip retains precise base stats")
	var malformed: Dictionary = restored.snapshot()
	malformed.pets[0].species="original_999999"
	check(not restored._valid_profile(malformed),"unknown source species rejected")
	malformed=restored.snapshot();malformed.pets[0].sprite=123
	check(not restored._valid_profile(malformed),"mismatched source sprite rejected")
	var grown := pet.duplicate(true)
	Rules.grow_pet(grown,int(grown.level)+1)
	check(grown.max_hp>pet.max_hp,"captured source pet continues original domesticated growth")
	var denied_session = Session.new()
	actor.can_capture=false
	var denied_config: Dictionary = denied_session.start_wild_battle_config({"enemies":[actor]})
	var denied_battle = Battle.new()
	denied_battle.start_battle(denied_config)
	var denied: Dictionary = denied_battle.submit_action("capture",0)
	check(denied.turn==0 and denied.captured_species_list.is_empty(),"uncapturable source enemy rejects capture without consuming turn")
	denied.active=false;denied.outcome="captured";denied.enemies[0].hp=0;denied.enemies[0].captured=true;denied.captured_species_list=[actor.species]
	check(not denied_session.apply_battle_result(denied),"forged capture bypass rejected by settlement")
	var ten := []
	for i in range(10):ten.append(original.duplicate(true))
	var group_session = Session.new()
	var group_config: Dictionary = group_session.start_wild_battle_config({"enemies":ten})
	var group_battle = Battle.new()
	check(group_battle.start_battle(group_config).enemies.size()==10,"all ten original troop positions survive authority")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("WILD AUTHORITY: %d failures"%failures)
	quit(1 if failures else 0)

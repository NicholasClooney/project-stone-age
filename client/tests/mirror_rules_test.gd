extends SceneTree
const Battle=preload("res://server/battle_session.gd")
const Session=preload("res://server/game_session.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if ok:print("PASS: "+label)
	else:push_error(label);failures+=1
func _initialize()->void:
	var battle=Battle.new()
	var original:Dictionary=battle.start_battle()
	check(battle.submit_action("mirror_self")==original,"no spell without equipped accessory")
	battle=Battle.new()
	battle.start_battle({"mirror_available":true,"enemy_max_hp":500,"player_speed":999})
	battle._player_action("mirror_self")
	check(battle.snapshot().mirror_self==1 and not battle.snapshot().has("player_mp"),"active self cast grants one charge without MP")
	for i in range(25): battle._player_action("mirror_self")
	check(battle.snapshot().mirror_self==1,"25 casts remain free and do not stack charges")
	var hp:int=battle.snapshot().player_hp
	check(not battle._reflect_incoming(0,false) and battle.snapshot().mirror_self==1,"zero damage does not consume mirror")
	check(battle._reflect_incoming(12,false) and battle.snapshot().player_hp==hp and battle.snapshot().enemy_hp==488,"positive physical hit reflected away from player")
	check(battle.snapshot().mirror_self==0 and not battle._reflect_incoming(12,false),"shield consumed exactly once")
	check(battle._pending_counter.is_empty(),"reflection does not schedule recursive counter")
	battle=Battle.new()
	battle.start_battle({"mirror_available":true,"pet":{"hp":50,"max_hp":50,"attack":10,"defence":0,"speed":10,"name":"宠物"},"enemy_max_hp":500})
	battle._player_action("mirror_pet")
	check(battle._reflect_incoming(10,true) and battle.snapshot().pet_hp==50,"active pet receives individual reflection shield")
	var reflected_counter:=false
	for seed_value in range(20):
		battle=Battle.new();battle.rng_seed=seed_value
		battle.start_battle({"mirror_available":true,"enemy_max_hp":500,"enemy_attack":30})
		battle._player_action("mirror_self")
		battle._pending_counter={"actor":"enemy","enemy_index":0,"target":"player"}
		battle._resolve_counter()
		if battle._last_outcome=="reflect":
			reflected_counter=true
			check(battle.snapshot().player_hp==48 and battle._pending_counter.is_empty(),"enemy counter reflects without harming player or chaining")
			break
	check(reflected_counter,"physical counter reflection path exercised")
	var session=Session.new()
	session._profile.player.gold=10000
	check(session.buy_item("mirror_charm") and session.equip_item("mirror_charm"),"shop accessory buys and equips")
	check(session.start_battle_config().mirror_available,"equipped charm grants command")
	var old=Session.new()
	old._profile.inventory.erase("mirror_charm");old._profile.erase("equipped_mirror")
	var path:="user://mirror-legacy-test.json"
	check(old.save_game(path),"legacy profile without accessory fields saves")
	var loaded=Session.new()
	check(loaded.load_game(path) and loaded._profile.inventory.mirror_charm==0 and not loaded._profile.equipped_mirror,"legacy saves default to no charm")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("MIRROR RULE FAILURES: ",failures)
	quit(1 if failures else 0)

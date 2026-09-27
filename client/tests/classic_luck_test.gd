extends SceneTree
const Luck=preload("res://server/classic_luck.gd")
const Session=preload("res://server/game_session.gd")
var failures:=0
func check(value:bool,label:String)->void:
	if value:print("PASS: "+label)
	else:push_error("FAIL: "+label);failures+=1
func _initialize()->void:
	var counts=[0,0,0,0,0]
	for roll in range(100):counts[Luck.from_roll(roll)-1]+=1
	check(counts==[40,30,20,7,3],"source luck distribution exact across100 rolls")
	var now=Luck.ERA+1500*Luck.DAY_SECONDS+50
	var rng=RandomNumberGenerator.new();rng.seed=87
	var player={}
	check(Luck.login(player,now,rng) and player.charm==60 and player.luck>=1 and player.luck<=5,"old profile initializes native charm and luck")
	var before=player.duplicate();var rng_before=rng.state
	check(not Luck.login(player,now+40,rng) and player==before and rng.state==rng_before,"same-day login preserves luck and consumes no random roll")
	check(Luck.login(player,now+Luck.DAY_SECONDS,rng) and player.last_luck_time==now+Luck.DAY_SECONDS,"new native day refreshes on login")
	var session=Session.new()
	var state=session.snapshot()
	check(state.player.charm==60 and state.player.luck in [1,2,3,4,5],"new game has original charm and validluck")
	var path="/tmp/stoneage-capture-luck-test.json"
	check(session.save_game(path),"test profile saves optional original stats")
	var loaded=Session.new()
	check(loaded.load_game(path) and loaded.snapshot().player.luck==state.player.luck,"same-day save/load preserves luck")
	var config=loaded.start_battle_config()
	check(config.player_charm==60 and config.player_luck==state.player.luck,"battle uses persisted original charm/luck")
	check(Luck.day_at(Luck.ERA+Luck.DAY_SECONDS-1)==0 and Luck.day_at(Luck.ERA+Luck.DAY_SECONDS)==1,"native day changes at exactly 5400 seconds")
	var clock={"now":Luck.ERA+99*Luck.DAY_SECONDS+5399}
	var seeded=RandomNumberGenerator.new();seeded.seed=421
	var timed=Session.new(func():return clock.now,seeded)
	var timed_before:Dictionary=timed.snapshot()
	var timed_path="/tmp/stoneage-native-luck-clock-test.json"
	check(timed.save_game(timed_path),"injected clock profile saves")
	clock.now+=1
	check(timed.load_game(timed_path) and timed.snapshot().player.last_luck_time==clock.now,"100-day native year rollover refreshes luck on login")
	var year_luck:Dictionary=timed.snapshot().player.duplicate(true)
	var saved_rng=seeded.state
	check(timed.save_game(timed_path) and timed.load_game(timed_path) and seeded.state==saved_rng and timed.snapshot().player==year_luck,"same native day reload after saving cannot reroll luck")
	clock.now+=Luck.DAY_SECONDS
	var battle:Dictionary=timed.start_battle_config()
	check(battle.player_luck==year_luck.luck and seeded.state==saved_rng,"crossing a day while online does not reroll luck when battle starts")
	var legacy:Dictionary=timed_before.duplicate(true)
	for key in ["charm","luck","last_luck_time"]:legacy.player.erase(key)
	var legacy_path="/tmp/stoneage-native-luck-legacy-test.json"
	var legacy_file=FileAccess.open(legacy_path,FileAccess.WRITE);legacy_file.store_string(JSON.stringify(legacy));legacy_file.close()
	var migrated=Session.new(func():return clock.now)
	check(migrated.load_game(legacy_path) and migrated.snapshot().player.charm==60 and migrated.snapshot().player.last_luck_time==clock.now,"legacy save gets native fields without changing old gameplay stats")
	for field in ["hp","max_hp","level","base_stats"]:check(migrated.snapshot().player[field]==legacy.player[field],"luck migration preserves "+field)
	for invalid in [{"key":"luck","value":0},{"key":"luck","value":6},{"key":"charm","value":101},{"key":"last_luck_time","value":-1}]:
		var malformed:Dictionary=migrated.snapshot();malformed.player[invalid.key]=invalid.value
		check(not migrated._valid_profile(malformed),"reject malformed native field "+str(invalid))
	for file_path in [path,path+".bak",timed_path,timed_path+".bak",legacy_path]:
		if FileAccess.file_exists(file_path):DirAccess.remove_absolute(file_path)
	print("CLASSIC LUCK: %d failures"%failures)
	quit(1 if failures else 0)

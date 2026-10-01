extends SceneTree
## 自动抓宠 leaves the battle after the catch (automation.gd, finish_after_capture):
## the other enemies are not fought, so the weaken pet earns no experience and
## stays under its level cap for the next capture.
var failures:=0
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
	game.session.grant_starter_pets()
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,120);game.session.gm_heal()
	var helper=game.training_helper;helper.set_process(false)
	helper.capture_hp.value=100
	var before:Dictionary=game.session.snapshot()
	var levels:Dictionary={}
	for pet in before.pets:levels[str(pet.pet_id)]=int(pet.level)
	# Two Lv.1 enemies: the first is caught, the second is left standing.
	# 凯比特 Lv.1 (enemy row 122, up to 2 in group 91 near 萨姆吉尔村).
	var rng:=RandomNumberGenerator.new();rng.seed=7
	var catalog=game.backend.encounter_catalog
	var troop:={"area_id":21,"group_id":91,"enemies":[catalog.actor(122,rng),catalog.actor(122,rng)]}
	var config:Dictionary=game.session.start_wild_battle_config(troop)
	check(not config.is_empty() and game.open_battle_config(config),"a battle with two Lv.1 enemies opens")
	helper.start_capture_battle(0,true)
	var steps:=0
	while helper.running and steps<300:
		for frame in range(20):game.battle_view._process(0.2)
		helper.advance();steps+=1
	for frame in range(60):game.battle_view._process(0.2);await process_frame
	var after:Dictionary=game.session.snapshot()
	var last:Dictionary=game.battle_session.snapshot()
	check(after.pets.size()==before.pets.size()+1,"the target was caught (%d → %d pets)"%[before.pets.size(),after.pets.size()])
	var raised:Array=[]
	for pet in after.pets:
		if levels.has(str(pet.pet_id)) and int(pet.level)!=int(levels[str(pet.pet_id)]):raised.append(str(pet.name))
	check(raised.is_empty(),"no carried pet gained a level (the run left instead of fighting on): %s"%str(raised))
	var report:String=game.battle_view.report.text if is_instance_valid(game.battle_view.report) else ""
	check(str(game.battle_session.snapshot().get("outcome",""))=="escaped","the battle ends by escaping, the second enemy untouched (%s)"%report)
	var why:=str(game.backend.automation.stop_reason)
	check(why=="本场自动战斗已完成","the find-pet flow counts escaping with the catch as a finished capture, not 战斗未获胜 (%s)"%why)
	game.queue_free()
	await process_frame
	print("CAPTURE THEN LEAVE: %d failures"%failures)
	quit(1 if failures else 0)

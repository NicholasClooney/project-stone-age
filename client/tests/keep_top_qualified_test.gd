extends SceneTree
## 达标只保留前 N 只: this run's qualifying pets are ranked by the player's order
## (default 三围合 then 攻击, ties by the remaining stats and then the older pet)
## and only the best N stay. Favourites, earlier runs and retrieved pets are
## never released; N 0 keeps everything.
const Filter=preload("res://scripts/pet_stat_filter.gd")
const Settings=preload("res://scripts/automation_settings.gd")
var failures:=0
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")

func pet(id: String, attack: int, defence: int, speed: int, hp: int = 1300) -> Dictionary:
	return {"pet_id":id,"template_id":92,"species":"original_92","level":120,"attack":attack,"defence":defence,"speed":speed,"max_hp":hp}

func ids(pets: Array) -> Array:
	return pets.map(func(p):return str(p.pet_id))

func rules() -> void:
	# pet-1..pet-5: sum 625/625/626/624/625, attack varies.
	var pets:=[pet("pet-1",290,183,152),pet("pet-2",293,180,152),pet("pet-3",288,186,152),pet("pet-4",294,178,152),pet("pet-5",293,181,151)]
	check(ids(Filter.ranked(pets,["sum","attack"]))==["pet-3","pet-5","pet-2","pet-1","pet-4"],"default order: 三围合 first, then 攻击 (626, then the 625s by attack, then 624)")
	check(ids(Filter.ranked(pets,["attack"]))==["pet-4","pet-5","pet-2","pet-1","pet-3"],"攻击 first: equal attacks fall back to 三围合")
	check(ids(Filter.ranked(pets,["speed","sum"]))==["pet-3","pet-2","pet-1","pet-4","pet-5"],"a custom order: 敏捷, then 三围合, then the fixed order")
	var tied:=[pet("pet-12",292,180,152,1300),pet("pet-9",292,180,152,1300),pet("pet-10",292,180,152,1310)]
	check(ids(Filter.ranked(tied,["sum","attack"]))==["pet-10","pet-9","pet-12"],"full ties fall back to 体力, then the older pet (pet-9 before pet-12, compared as numbers)")
	check(Filter.rank_order(["speed"])==["speed","sum","attack","defence","max_hp"],"the remaining keys follow in a fixed order")
	check(Filter.describe_order(["sum","attack"])=="三围合 → 攻击","the order reads as 三围合 → 攻击")

func settings() -> void:
	var filter:=Settings.default_stat_filter(92)
	check(int(filter.keep_qualified)==0 and filter.rank==["sum","attack"],"defaults: keep every qualifier, rank by 三围合 then 攻击")
	var good:=Settings.apply_patch({},{"stat_filters":{"92":{"keep_qualified":5,"rank":["speed","max_hp","sum"]}}})
	check(good.ok and good.overrides.stat_filters["92"].keep_qualified==5 and good.overrides.stat_filters["92"].rank==["speed","max_hp","sum"],"a keep count and a custom order are accepted")
	for bad in [["sum","sum"],["luck"],[],"sum",["sum","attack","defence","speed","max_hp","sum"]]:
		check(not Settings.apply_patch({},{"stat_filters":{"92":{"rank":bad}}}).ok,"an invalid order is refused: %s" % str(bad))
	check(not Settings.apply_patch({},{"stat_filters":{"92":{"keep_qualified":-1}}}).ok and not Settings.apply_patch({},{"stat_filters":{"92":{"keep_qualified":1001}}}).ok,"the keep count is 0 to 1000")
	var back:=Settings.apply_patch(good.overrides,{"stat_filters":{"92":{"keep_qualified":0,"rank":["sum","attack"]}}})
	check(back.ok and not back.overrides.get("stat_filters",{}).get("92",{}).has("rank") and not back.overrides.get("stat_filters",{}).get("92",{}).has("keep_qualified"),"values equal to the defaults are not stored")
	var old:=Settings.sanitize({"stat_filters":{"92":{"stop_after":3,"rank":["nonsense"]}}})
	check(Settings.stat_filter(old,92).rank==["sum","attack"] and int(Settings.stat_filter(old,92).keep_qualified)==0 and int(Settings.stat_filter(old,92).stop_after)==3,"an older or broken save keeps its valid parts and gets the defaults")

func run()->void:
	rules()
	settings()
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
	game.session.grant_starter_pets();game.load_area_id(300,Vector2i(509,90));game.session.gm_heal()
	var hunt=game.pet_hunt_menu;hunt.set_process(false)
	var flow=game.pet_workflow;flow.set_process(false)
	game.training_helper.set_process(false)

	# Session rule: only this run's stored qualifiers are candidates.
	var session=game.backend.session
	var run_ids:=[]
	for i in range(5):
		var p:=pet("pet-%d"%(900+i),290+i,180,152);p.auto_qualified=true;session._profile.pet_storage.append(p);run_ids.append(p.pet_id)
	var fav:=pet("pet-890",280,180,150);fav.auto_qualified=true;fav.favorite=true;session._profile.pet_storage.append(fav);run_ids.append(fav.pet_id)
	var earlier:=pet("pet-880",280,180,150);earlier.auto_qualified=true;session._profile.pet_storage.append(earlier)
	var manual:=pet("pet-870",280,180,150);session._profile.pet_storage.append(manual);run_ids.append(manual.pet_id)
	var other:=pet("pet-860",280,180,150);other.template_id=194;other.auto_qualified=true;session._profile.pet_storage.append(other);run_ids.append(other.pet_id)
	check(session.release_unranked_qualified(92,0,["sum","attack"],run_ids).is_empty(),"N 0 keeps every qualifier")
	var released:Array=session.release_unranked_qualified(92,2,["sum","attack"],run_ids)
	var left:Array=ids(session._profile.pet_storage)
	check(released==["pet-902","pet-901","pet-900"] and left.has("pet-904") and left.has("pet-903"),"only the best 2 of this run's qualifiers stay; the rest are released worst last")
	check(left.has("pet-890") and left.has("pet-880") and left.has("pet-870") and left.has("pet-860"),"favourites, earlier runs, player-stored pets and other species stay")
	var back:int=left.find("pet-904")
	session.retrieve_pet(back)
	check(not session._profile.pets.back().has("auto_qualified"),"retrieving a qualifier makes it the player's again")
	session._profile.pets.pop_back()
	session._profile.pet_storage=session._profile.pet_storage.filter(func(p):return not str(p.pet_id).begins_with("pet-8") and not str(p.pet_id).begins_with("pet-9"))

	# The find-pet cycle: collect without stopping, keep only the best 3.
	var source:Dictionary=session.snapshot().pets[0].duplicate(true)
	var target:=Settings.default_stat_filter(92);target.stop_after=0;target.keep_qualified=3
	game.backend.automation.flow_held_count=0
	flow.kept_count=0;flow.collected_count=0;flow.target_stat_filter=target
	game.backend.automation.flow_run_kept_ids=[];game.backend.automation.flow_released_count=0
	# (attack, defence, speed): every one qualifies (sum >=624 or attack >292).
	var found_stats:=[[292,180,152],[293,180,152],[290,183,152],[294,178,152],[288,186,152],[293,181,152],[289,183,152],[295,176,150]]
	var released_new:=0
	for turn in range(found_stats.size()):
		var found:Dictionary=source.duplicate(true);found.pet_id="pet-%d"%(700+turn);found.species="original_92";found.template_id=92;found.level=120
		found.attack=found_stats[turn][0];found.defence=found_stats[turn][1];found.speed=found_stats[turn][2];found.erase("gm_modified")
		session._profile.pets.append(found);session._profile.active_pet=session._profile.pets.size()-1
		if turn==2:
			# The player favourites a stored qualifier mid-run: it is never released.
			for stored in session._profile.pet_storage:
				if stored.pet_id=="pet-700":stored.favorite=true
		flow.pet_id=found.pet_id;flow.phase="train";flow.complete_trained_pet(found)
		if flow.last_result.contains("已放生"):released_new+=1
		check(flow.phase=="restart","qualifier #%d: the cycle carries on" % (turn+1))
		flow.phase="idle"
	var kept:Array=session._profile.pet_storage.filter(func(p):return str(p.pet_id).begins_with("pet-7"))
	var kept_ids:Array=ids(kept);kept_ids.sort()
	# Candidates (pet-700 is a favourite): 701 (625/293), 702 (625/290), 703 (624/294), 704 (626/288), 705 (626/293), 706 (624/289), 707 (621/295).
	check(kept_ids==["pet-700","pet-701","pet-704","pet-705"],"the best 3 by 三围合 then 攻击 stay (626/293, 626/288, 625/293), plus the favourite")
	check(kept.all(func(p):return p.get("auto_qualified",false)),"kept qualifiers carry the hunt's marker until retrieved")
	check(flow.collected_count==8 and flow.released_count==4 and flow.held_count==3 and flow.keep_best==3,"status: 8 found, 4 released, 3 held (the favourite is outside the count)")
	check(released_new>0,"a new qualifier that does not make the top 3 is reported as released")
	var status:String=hunt.workflow_summary()
	check(status.contains("只留最好3只") and status.contains("已放生4只"),"the hunt window shows the keep and the releases")

	# UI: the 属性条件 page edits the keep count and the order.
	hunt.open_menu();hunt.show_stat_settings()
	check(hunt.stat_keep_best.value==0 and hunt.rank_choice()==["sum","attack"] and hunt.stat_rank[2].get_selected_id()==0,"the page shows keep 0 and 第一 三围合, 第二 攻击, 第三 无")
	hunt.stat_keep_best.value=5
	hunt.stat_rank[1].select(hunt.stat_rank[1].get_item_index(Filter.RANK_KEYS.find("speed")+1))
	hunt.stat_rank[2].select(hunt.stat_rank[2].get_item_index(Filter.RANK_KEYS.find("sum")+1))
	hunt.save_stat_settings(true);game.flush_automation_settings()
	check(int(game.stat_filter(92).keep_qualified)==5 and game.stat_filter(92).rank==["sum","speed"],"keep 5 and 三围合 → 敏捷 are saved; a repeated key is dropped")
	game.link.request({"type":"set_automation_settings","settings":{"stat_filters":{"92":{"rank":["max_hp","attack","sum"],"keep_qualified":7}}}})
	hunt.load_stat_settings()
	check(hunt.stat_keep_best.value==7 and hunt.rank_choice()==["max_hp","attack","sum"],"a change from elsewhere shows in the page")
	hunt.hide();game.paused_input=false

	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	print("KEEP TOP QUALIFIED: %d failures" % failures)
	quit(1 if failures else 0)

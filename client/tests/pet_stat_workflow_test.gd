extends SceneTree
const Filter=preload("res://scripts/pet_stat_filter.gd")
var failures:=0
var fake_msec:=1000
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")
## The blue dragon default resolved against owned bests that give the former
## fixed thresholds: 三围合 ≥ 625−1 = 624, 攻击 ≥ 294−1 = 293 (and so on).
func blue_filter()->Dictionary:
	return Filter.resolve(Filter.defaults(92),{"sum":625,"attack":294,"defence":180,"speed":152})
## 找到N只后停止 is the run's hunt.stop_after, read from its settings snapshot.
func run_stop_after(game, count: int)->void:
	game.backend.automation.flow_settings_overrides={"hunt":{"stop_after":count}}
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
	game.session.grant_starter_pets();game.load_area_id(300,Vector2i(509,90));game.session.gm_heal()
	# 展示模式 off: this suite covers the full-speed find-pet cycle.
	game.link.request({"type":"set_automation_settings","settings":{"hunt":{"showcase":false}}})
	var hunt=game.pet_hunt_menu;hunt.set_process(false)
	var flow=game.pet_workflow;flow.set_process(false);flow.timer_clock=func():return fake_msec
	game.training_helper.set_process(false);game.training_helper.capture_hp.value=100
	check(Filter.enabled(Filter.defaults(92)) and int(Filter.defaults(92).conditions.sum.minus)==1 and int(blue_filter().conditions.sum.value)==624,"blue dragon defaults to 三围合 ≥ 最高 − 1")
	check(not Filter.enabled(Filter.defaults(194)),"blue default does not leak to other species")
	hunt.open_menu();hunt.show_stat_settings()
	check(hunt.stat_page.visible and not hunt.capture_page.visible and not hunt.species.visible,"attribute tab exclusively displays its own controls")
	var shown_best:=Filter.maxima(preload("res://scripts/keep_rule.gd").species_pets(game.state.profile,92).map(preload("res://scripts/keep_rule.gd").stats_of))
	var sum_check:CheckBox=hunt.stat_checks.sum
	check(sum_check.text=="三围合 ≥ 最高%d −" % int(shown_best.sum) and hunt.stat_results.sum.text=="= %d" % (int(shown_best.sum)-1) and hunt.stat_results.sum.tooltip_text=="三围合 ≥ 最高 %d − 1 = %d" % [int(shown_best.sum),int(shown_best.sum)-1],"the page reads %s [1] %s" % [sum_check.text,hunt.stat_results.sum.text])
	for metric in Filter.METRICS:
		var row_check:CheckBox=hunt.stat_checks[metric]
		check(row_check.position.x+row_check.get_combined_minimum_size().x<=hunt.stat_numbers[metric].position.x and hunt.stat_results[metric].position.x+hunt.stat_results[metric].get_combined_minimum_size().x<=hunt.stat_keeps[metric].position.x-40,"the %s row fits: check, x, result, 留前" % metric)
	hunt.stat_numbers.sum.get_line_edit().grab_focus();hunt.stat_numbers.sum.get_line_edit().text="3";hunt.commit_stat_settings()
	check(int(game.stat_filter(92).conditions.sum.minus)==3,"typed x commits to the profile on first start/apply")
	hunt.stat_numbers.sum.get_line_edit().release_focus();hunt.stat_numbers.sum.value=5;hunt.save_stat_settings()
	check(flow.start_cycle(),"workflow starts with current per-species filter settings")
	check(int(flow.stat_filter_snapshot[92].conditions.sum.minus)==5,"loop snapshots current configuration")
	fake_msec=31000
	check(flow.elapsed_seconds()==30.0 and hunt.summary().contains("流程总用时 30秒"),"workflow displays elapsed wall time separately from round duration")
	game.link.request({"type":"set_automation_settings","settings":{"stat_filters":{"92":{"conditions":{"sum":{"minus":9}}}}}})
	check(int(game.stat_filter(92).conditions.sum.minus)==9 and int(flow.stat_filter_snapshot[92].conditions.sum.minus)==9,"a later settings change applies to the running loop at once")
	# 相对 ↔ 绝对 on the page, while the cycle runs.
	hunt.set_controls(true)
	check(not hunt.stat_threshold_mode.disabled and not hunt.stat_checks.sum.disabled and hunt.stat_numbers.sum.editable and hunt.stat_values.sum.editable and hunt.level_one.disabled,"属性条件 stays editable while the cycle runs; the search settings are locked")
	hunt.load_stat_settings()
	check(hunt.stat_threshold_mode.selected==0 and hunt.stat_heading.text.contains("最高 − x"),"relative is the default mode")
	hunt.stat_threshold_mode.select(1);hunt.stat_threshold_mode.item_selected.emit(1)
	var fixed:Dictionary=game.stat_filter(92)
	check(Filter.absolute(fixed) and int(fixed.conditions.sum.value)==int(shown_best.sum)-9 and int(fixed.conditions.attack.value)==int(shown_best.attack)-1 and int(fixed.conditions.sum.minus)==9,"switching to 绝对 fills in the thresholds hunted now (三围合 %d, 攻击 %d) and keeps x" % [int(fixed.conditions.sum.value),int(fixed.conditions.attack.value)])
	check(Filter.absolute(flow.stat_filter_snapshot[92]) and int(Filter.resolve(flow.stat_filter_snapshot[92],{}).conditions.sum.value)==int(shown_best.sum)-9,"the running loop switches too")
	check(hunt.stat_values.sum.visible and not hunt.stat_numbers.sum.visible and hunt.stat_checks.sum.text=="三围合 ≥" and hunt.stat_results.sum.text=="（现有最高%d）" % int(shown_best.sum) and hunt.stat_results.sum.tooltip_text=="三围合 ≥ %d（现有最高 %d）" % [int(shown_best.sum)-9,int(shown_best.sum)] and hunt.stat_heading.text.contains("固定数值"),"the row reads %s [%d] %s" % [hunt.stat_checks.sum.text,int(hunt.stat_values.sum.value),hunt.stat_results.sum.text])
	for metric in Filter.METRICS:
		var row_check:CheckBox=hunt.stat_checks[metric]
		var value_box:SpinBox=hunt.stat_values[metric]
		var result:Label=hunt.stat_results[metric]
		check(row_check.position.x+row_check.get_combined_minimum_size().x<=value_box.position.x and value_box.position.x+value_box.size.x<=result.position.x and result.position.x+result.get_combined_minimum_size().x<=hunt.stat_keeps[metric].position.x,"the absolute %s row fits: check, value, best, 留前" % metric)
	hunt.stat_values.sum.value=600;hunt.commit_stat_settings()
	check(int(game.stat_filter(92).conditions.sum.value)==600 and int(Filter.resolve(flow.stat_filter_snapshot[92],{}).conditions.sum.value)==600,"a typed value is saved and hunted at once")
	hunt.stat_threshold_mode.select(0);hunt.stat_threshold_mode.item_selected.emit(0)
	check(not Filter.absolute(game.stat_filter(92)) and int(game.stat_filter(92).conditions.sum.minus)==9 and int(game.stat_filter(92).conditions.sum.value)==600 and hunt.stat_numbers.sum.visible and hunt.stat_results.sum.text=="= %d" % (int(shown_best.sum)-9),"back to 相对: x is still 9 and the value is kept")
	hunt.stat_threshold_mode.select(1);hunt.stat_threshold_mode.item_selected.emit(1)
	check(int(game.stat_filter(92).conditions.sum.value)==600 and int(game.stat_filter(92).conditions.attack.value)==int(shown_best.attack)-1,"switching to 绝对 again keeps the player's own value")
	hunt.stat_threshold_mode.select(0);hunt.stat_threshold_mode.item_selected.emit(0)
	hunt.stop_hunt("test boundary");hunt.hide();game.paused_input=false
	var source:Dictionary=game.session.snapshot().pets[0].duplicate(true)
	var previous_storage:int=game.session.snapshot().pet_storage.size()
	var wild:Dictionary=source.duplicate(true);wild.template_id=92;wild.level=1;wild.erase("gm_modified")
	var fixed_filters:Dictionary=game.backend.automation.flow_stat_filters;var fixed_blue:=Filter.defaults(92);fixed_blue["threshold_mode"]="absolute";fixed_filters[92]=fixed_blue;flow.predicted_rejects=0;flow.best_predicted={}
	fixed_blue.conditions.sum["value"]=99999;fixed_blue.conditions.attack["value"]=99999
	check(not flow.accepts_prediction(wild) and flow.predicted_rejects==1 and int(flow.best_predicted.sum)>0,"impossible predicted Lv.120 stats are skipped before capture")
	fixed_blue.conditions.sum["value"]=0;fixed_blue.conditions.attack["value"]=0
	check(flow.accepts_prediction(wild) and flow.predicted_rejects==1,"predicted qualifying pet proceeds to capture")
	fixed_filters.erase(92)
	flow.predicted_rejects=0;flow.best_predicted={}
	var instant:Dictionary=source.duplicate(true);instant.pet_id="pet-instant";instant.level=1;instant.xp=0;instant.erase("gm_modified")
	var gradual:Dictionary=instant.duplicate(true);gradual.pet_id="pet-gradual"
	game.session._profile.pets.append(instant)
	check(game.session.level_pet_to("pet-instant",120),"instant level-up accepts carried pet")
	while int(gradual.level)<120:game.session._gain_xp(gradual,7)
	var leveled:Dictionary=game.session._profile.pets.back()
	check(int(leveled.level)==120 and leveled.base_stats==gradual.base_stats and int(leveled.attack)==int(gradual.attack) and int(leveled.speed)==int(gradual.speed),"instant level-up yields identical stats to small XP steps")
	check(not leveled.has("gm_modified"),"instant workflow level-up is not a GM edit")
	game.session._profile.pets.pop_back()
	for turn in range(2):
		var pet:Dictionary=source.duplicate(true);pet.pet_id="pet-filter-%d"%turn;pet.level=120;pet.attack=290;pet.defence=178;pet.speed=151
		game.session._profile.pets.append(pet);game.session._profile.active_pet=game.session._profile.pets.size()-1
		flow.pet_id=pet.pet_id;flow.phase="train";flow.target_stat_filter=blue_filter()
		fake_msec+=60000
		flow.complete_trained_pet(pet)
		check(flow.phase=="restart" and flow.stored_count==turn+1 and game.session.snapshot().pet_storage.back().pet_id==pet.pet_id,"unmet actual stats store exact trained individual, round %d"%turn)
		flow.complete_trained_pet(pet)
		check(game.session.snapshot().pet_storage.size()==previous_storage+turn+1,"duplicate completion never stores another pet")
		flow.advance()
		check(flow.elapsed_seconds()==30.0+60.0*(turn+1),"total timer survives store and automatic restart")
		check(flow.phase=="hunt" and hunt.running and hunt.status.text.contains("未达标") and hunt.status.text.contains("滚动淘汰") and hunt.status.text.contains(pet.pet_id),"next hunt starts and retained notification identifies stored individual")
		hunt.stop_hunt("test boundary");hunt.hide();game.paused_input=false
	var storage:Array=game.session._profile.pet_storage
	check(storage.back().get("auto_hunt",false),"workflow flags pets it stores")
	var manual:Dictionary=source.duplicate(true);manual.pet_id="pet-manual-low";manual.template_id=92;manual.attack=1;manual.defence=0;manual.speed=1;storage.append(manual)
	var favored:Dictionary=source.duplicate(true);favored.pet_id="pet-fav-low";favored.template_id=92;favored.attack=1;favored.defence=0;favored.speed=1;favored.auto_hunt=true;favored.favorite=true;storage.append(favored)
	var earlier:Dictionary=source.duplicate(true);earlier.pet_id="pet-earlier-low";earlier.template_id=92;earlier.attack=1;earlier.defence=0;earlier.speed=1;earlier.auto_hunt=true;storage.append(earlier)
	var run_ids:=["pet-manual-low","pet-fav-low"]
	for i in range(30):
		# Sums rise with i; attack is highest for low i, so top-attack picks differ from top-sum picks.
		var hunted:Dictionary=source.duplicate(true);hunted.pet_id="pet-hunt-%d"%i;hunted.template_id=92;hunted.attack=300-i;hunted.defence=150+2*i;hunted.speed=100;hunted.auto_hunt=true;storage.append(hunted);run_ids.append(hunted.pet_id)
	var removed:int=game.session.prune_hunt_pets(92,{"sum":15,"attack":5,"defence":0,"speed":0},run_ids)
	var ids:=[]
	for pet in game.session._profile.pet_storage:ids.append(str(pet.pet_id))
	var hunt_left:=ids.filter(func(id):return str(id).begins_with("pet-hunt-"))
	check(hunt_left.size()==20 and removed>=10,"rolling keep holds exactly 15 by sum plus 5 by attack")
	check("pet-hunt-29" in ids and "pet-hunt-15" in ids and not "pet-hunt-14" in ids,"top 15 sums survive and the 16th is not kept by sum")
	check("pet-hunt-0" in ids and "pet-hunt-4" in ids and not "pet-hunt-5" in ids,"next 5 by attack survive among the rest")
	check("pet-manual-low" in ids and "pet-fav-low" in ids,"player-stored and favorite pets are never pruned")
	check("pet-earlier-low" in ids,"flagged pets from earlier runs are never pruned")
	check(game.session.prune_hunt_pets(92,{"sum":0,"attack":0,"defence":0,"speed":0},run_ids)==0,"all-zero keep deletes nothing")
	var back_index:int=ids.find("pet-hunt-29")
	game.session.retrieve_pet(back_index)
	check(not game.session._profile.pets.back().has("auto_hunt"),"retrieving returns the pet to player ownership")
	game.session.store_pet(game.session._profile.pets.size()-1)
	game.session._profile.pet_storage=game.session._profile.pet_storage.filter(func(pet):return not (str(pet.pet_id).begins_with("pet-hunt-") or str(pet.pet_id) in ["pet-manual-low","pet-fav-low","pet-earlier-low"]))
	var keeper:Dictionary=source.duplicate(true);keeper.pet_id="pet-keep-0";keeper.species="original_92";keeper.template_id=92;keeper.level=120;keeper.attack=288;keeper.defence=184;keeper.speed=152;keeper.erase("gm_modified")
	var keep_ids:=[]
	var ten:=blue_filter();run_stop_after(game,10)
	flow.kept_count=0;flow.collected_count=0;flow.target_stat_filter=ten
	for turn in range(10):
		var found:Dictionary=keeper.duplicate(true);found.pet_id="pet-keep-%d"%turn;keep_ids.append(found.pet_id)
		if turn==1:found.attack=293;found.defence=170;found.speed=150
		game.session._profile.pets.append(found);game.session._profile.active_pet=game.session._profile.pets.size()-1
		flow.pet_id=found.pet_id;flow.phase="train";flow.complete_trained_pet(found)
		if turn<10-1:
			var stored:Dictionary=game.session.snapshot().pet_storage.back()
			check(flow.phase=="restart" and flow.collected_count==turn+1 and stored.pet_id==found.pet_id and not stored.get("auto_hunt",false),"qualifier #%d is stored unflagged, safe from rolling keep, and the hunt continues"%(turn+1))
			flow.phase="idle"
	check(flow.phase=="compare" and flow.reason.contains("收集完成") and flow.collected_count==10 and game.adventure_menu.pet_compare_id=="pet-keep-%d"%(10-1),"tenth qualifier found this run ends the hunt at comparison")
	game.adventure_menu.hide();game.paused_input=false
	game.session._profile.pet_storage=game.session._profile.pet_storage.filter(func(pet):return not str(pet.pet_id) in keep_ids)
	flow.phase="idle"
	var endless:=blue_filter();run_stop_after(game,0)
	flow.collected_count=0;flow.target_stat_filter=endless
	var endless_ids:=[]
	for turn in range(12):
		var found:Dictionary=keeper.duplicate(true);found.pet_id="pet-endless-%d"%turn;endless_ids.append(found.pet_id)
		game.session._profile.pets.append(found);game.session._profile.active_pet=game.session._profile.pets.size()-1
		flow.pet_id=found.pet_id;flow.phase="train";flow.complete_trained_pet(found)
		if flow.phase!="restart":break
		flow.phase="idle"
	check(flow.collected_count==12 and flow.phase=="idle" and flow.collect_target_text()=="不限","stop_after 0 keeps storing matches without stopping")
	game.session._profile.pet_storage=game.session._profile.pet_storage.filter(func(pet):return not str(pet.pet_id) in endless_ids)
	hunt.show_stat_settings();hunt.stat_species.select(hunt.stat_species.get_item_index(92));hunt.load_stat_settings()
	check(hunt.stat_keeps.sum.value==15 and hunt.stat_keeps.attack.value==10 and hunt.stat_page.find_child("StatStopAfter",true,false)==null,"attribute tab shows blue dragon defaults (keep 15 by sum and 10 by attack) and no per-species stop count")
	hunt.show();hunt.show_capture_settings(true);await process_frame
	check(hunt.stop_after.get_parent()==hunt.capture_page and hunt.stop_after.is_visible_in_tree() and int(hunt.stop_after.value)==0,"找到N只后停止 is on 抓宠设置, 0 (keep going) by default")
	var note:Control=hunt.capture_page.get_node("HuntStopAfterNote")
	var stop_rect:Rect2=hunt.stop_after.get_global_rect().merge(note.get_global_rect())
	check(hunt.panel.get_global_rect().encloses(stop_rect) and note.get_global_rect().end.x<=hunt.showcase.get_global_rect().position.x and hunt.stop_after.size.y>=38,"the stop count row fits the panel's left column at touch height")
	var neighbours:=[hunt.status]
	for child in hunt.capture_page.get_children():
		if child is Control and child!=note and child!=hunt.stop_after:neighbours.append(child)
	check(neighbours.all(func(other):return other==hunt.stop_after or not (other.get_global_rect().intersects(hunt.stop_after.get_global_rect()) or other.get_global_rect().intersects(note.get_global_rect()))),"and overlaps no other capture setting")
	hunt.stop_after.get_line_edit().grab_focus();hunt.stop_after.get_line_edit().text="7";hunt.commit_stat_settings()
	check(int(game.automation_settings().hunt.stop_after)==7 and not game.automation_settings().get("stat_filters",{}).get("92",{}).has("stop_after"),"typed stop count commits to hunt.stop_after, for the whole run")
	hunt.stop_after.get_line_edit().release_focus();hunt.stop_after.value=1;game.flush_automation_settings()
	check(int(game.automation_settings().hunt.stop_after)==1,"and back to 1")
	hunt.set_controls(true)
	check(hunt.stop_after.editable and not game.training_helper.capture_hp.editable,"it stays editable during a run, which follows it at once")
	hunt.set_controls(false);hunt.hide();game.paused_input=false
	flow.phase="idle"
	var good:Dictionary=source.duplicate(true);good.pet_id="pet-filter-good";good.level=120;good.attack=292;good.defence=181;good.speed=151
	game.session._profile.pets.append(good);game.session._profile.active_pet=game.session._profile.pets.size()-1
	var storage_before_good:int=game.session.snapshot().pet_storage.size()
	var single:=blue_filter();run_stop_after(game,1)
	flow.pet_id=good.pet_id;flow.phase="train";flow.target_stat_filter=single;flow.complete_trained_pet(good)
	fake_msec+=5000
	check(flow.elapsed_seconds()==150.0,"successful comparison freezes whole workflow elapsed time")
	check(flow.phase=="compare" and flow.reason.contains("已达标") and game.adventure_menu.pet_compare_id==good.pet_id,"stop_after 1: actual sum 624 stops loop and opens correct comparison")
	check(game.session.snapshot().pet_storage.size()==storage_before_good and not hunt.running,"qualified pet remains carried and no new hunt starts")
	var all_conditions:=blue_filter()
	for condition in all_conditions.conditions.values():condition.enabled=true
	flow.reason="已达标 · pet-long-identifier · "+Filter.describe(good,all_conditions)
	game.adventure_menu.rebuild();await process_frame
	var overlay=game.adventure_menu.panel.get_node("PetComparisonPanel")
	var info=overlay.get_node("PetComparisonInfo")
	var pinned=overlay.get_node("ComparePinned_选中")
	check(info.position.y+info.size.y<=pinned.position.y and info.size.x<=overlay.size.x,"four threshold results stay within dedicated wrapped area above selected stats")
	check(hunt.status.position.y+hunt.status.size.y<=hunt.start_button.position.y,"loop progress stays above hunt action buttons")
	game.adventure_menu.hide();game.paused_input=false
	flow.phase="restart"
	var cancel:=InputEventAction.new();cancel.action="ui_cancel";cancel.pressed=true;root.push_input(cancel);flow.advance()
	check(flow.phase=="paused" and not hunt.running,"manual stop between storage and restart is final")
	var stored_before:int=game.session.snapshot().pet_storage.size()
	game.session._profile.ride_pet=game.session.snapshot().pets.size()-1
	flow.phase="train";flow.target_stat_filter.conditions.sum.value=999;flow.target_stat_filter.conditions.attack.value=999;flow.complete_trained_pet(good)
	check(flow.phase=="paused" and game.session.snapshot().pet_storage.size()==stored_before and not hunt.running,"storage rejection pauses without deleting, swapping or restarting")
	game.session._profile.ride_pet=-1
	flow.phase="train";flow.target_stat_filter=Filter.defaults(194);flow.complete_trained_pet(good)
	check(flow.phase=="compare" and game.session.snapshot().pet_storage.size()==stored_before,"no enabled conditions retains legacy single cycle even below blue threshold")
	game.adventure_menu.hide();game.paused_input=false
	check(flow.start_cycle(),"fresh user start accepted after comparison")
	check(flow.elapsed_seconds()==0.0,"new user start resets total time")
	fake_msec+=4000;flow.stop_cycle();fake_msec+=9000
	check(flow.elapsed_seconds()==4.0,"manual stop freezes total time")
	check(flow.start_cycle(),"new start after manual stop resets clock")
	fake_msec+=6000
	flow.phase="restart";flow.prepare_scene_reload();flow.advance()
	fake_msec+=7000
	check(flow.elapsed_seconds()==6.0,"scene reload freezes elapsed time")
	check(flow.phase=="paused" and not hunt.running,"scene reload after storage cancels restart")
	game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.queue_free();await process_frame
	print("PET STAT WORKFLOW: %d failures"%failures);quit(1 if failures else 0)

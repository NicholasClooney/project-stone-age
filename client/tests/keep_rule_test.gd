extends SceneTree
## 保留规则 (scripts/keep_rule.gd): the top tiers of 三围合 keep their best few by
## the player's order, each chosen single stat keeps its best few across the
## species, favourites / 出战 / 骑乘 / the capture helper always stay, and the
## rest is released: only after 放生所选 in 同种比较, or automatically in the
## find-pet cycle when 找宠时自动整理 is on (off by default).
const KeepRule=preload("res://scripts/keep_rule.gd")
const Settings=preload("res://scripts/automation_settings.gd")
const Filter=preload("res://scripts/pet_stat_filter.gd")
const Progression=preload("res://server/progression.gd")
var failures:=0
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")

func pet(id: String, attack: int, defence: int, speed: int, hp: int = 1300) -> Dictionary:
	return {"pet_id":id,"template_id":92,"species":"original_92","name":"扬奇洛斯","level":120,"attack":attack,"defence":defence,"speed":speed,"max_hp":hp}

func kept(verdict: Dictionary) -> Array:
	var result:=[]
	for id in verdict.reasons:
		if not verdict.reasons[id].is_empty():result.append(id)
	result.sort_custom(func(a,b):return int(a.trim_prefix("pet-"))<int(b.trim_prefix("pet-")))
	return result

func default_rule() -> Dictionary:
	return Settings.default_stat_filter(92).keep_rule

func rules() -> void:
	# The reference split: 65 real dragons, the reference script's answer.
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/keep_rule_dragons.json"))
	var verdict:=KeepRule.evaluate(fixture.pets,default_rule())
	check(kept(verdict)==fixture.keep and verdict.release.size()==fixture.release.size(),"the default rule keeps exactly the reference split of 65 real dragons (%d kept)" % fixture.keep.size())
	check(verdict.reasons["pet-268"]==["626档第1","攻击第1"],"a pet lists every reason it stays")

	var pets:=[pet("pet-1",294,179,153,1314),pet("pet-2",293,180,153,1312),pet("pet-3",293,181,152,1317),pet("pet-4",292,180,154,1313),
		pet("pet-5",294,178,153,1314),pet("pet-6",293,180,152,1307),pet("pet-7",292,182,151,1313),pet("pet-8",294,178,153,1314),pet("pet-9",290,180,150,1330)]
	var rule:={"tiers":1,"per_tier":2,"order":["attack","speed","max_hp"],"champions":1,"champion_stats":["attack","defence","speed","max_hp"]}
	var one:=KeepRule.evaluate(pets,rule)
	check(one.reasons["pet-1"]==["626档第1","攻击第1"] and one.reasons["pet-2"]==["626档第2"],"only the top tier keeps pets, ranked 攻击 → 敏捷 → 血")
	check(one.reasons["pet-3"].is_empty(),"a 626 outside the tier quota and no stat champion is released")
	check(one.reasons["pet-4"]==["敏捷第1"] and one.reasons["pet-7"]==["防御第1"] and one.reasons["pet-9"]==["血第1"],"stat champions stay whatever their tier")
	check(one.reasons["pet-5"].is_empty() and one.reasons["pet-8"].is_empty(),"625s tied with the attack champion's attack lose to its higher 三围合")
	var dup:=KeepRule.evaluate([pet("pet-12",294,178,153),pet("pet-11",294,178,153)],{"tiers":1,"per_tier":1,"order":["attack"],"champions":0,"champion_stats":[]})
	check(dup.release==["pet-12"],"duplicates beyond the quota go, the older id stays (numbers, not text)")
	var by_hp:=KeepRule.evaluate(pets,{"tiers":1,"per_tier":1,"order":["max_hp"],"champions":0,"champion_stats":[]})
	check(by_hp.reasons["pet-3"]==["626档第1"],"a custom tier order (血 first) picks a different 626")
	var champions_only:=KeepRule.evaluate(pets,{"tiers":0,"per_tier":3,"order":["attack"],"champions":1,"champion_stats":["defence"]})
	check(kept(champions_only)==["pet-7"],"0 tiers and only 防御 checked keeps the one defence champion")
	var two_tiers:=KeepRule.evaluate(pets,{"tiers":2,"per_tier":1,"order":["attack","speed","max_hp"],"champions":0,"champion_stats":[]})
	check(kept(two_tiers)==["pet-1","pet-5"],"two tiers keep the best of 626 and of 625")

	var favourite:=pet("pet-20",280,170,140);favourite.favorite=true
	var guarded:=KeepRule.evaluate([pet("pet-21",294,180,153),favourite,pet("pet-22",281,170,140)],{"tiers":1,"per_tier":1,"order":["attack"],"champions":0,"champion_stats":[]},{"pet-22":"削血宠"})
	check(guarded.reasons["pet-20"]==["收藏"] and guarded.reasons["pet-22"]==["削血宠"] and guarded.release.is_empty(),"favourites and protected pets stay, with the reason shown")
	check(KeepRule.describe(["626档第1"])=="保留：626档第1" and KeepRule.describe([])=="按规则放生","row text reads 保留：… or 按规则放生")

	# The capture helper: chosen by id, by slot, or automatically (every carried pet at or under the cap).
	var party:={"pets":[{"pet_id":"pet-40","level":1},{"pet_id":"pet-41","level":8},{"pet_id":"pet-42","level":120}]}
	check(KeepRule.capture_helpers(party,{"pet":-1,"pet_id":"","pet_max_level":10}).keys()==["pet-40","pet-41"],"automatic choice protects every carried pet at or under the level cap")
	check(KeepRule.capture_helpers(party,{"pet":-1,"pet_id":"pet-42","pet_max_level":10}).keys()==["pet-42"] and KeepRule.capture_helpers(party,{"pet":1,"pet_id":"","pet_max_level":10}).keys()==["pet-41"],"a chosen helper (by id or slot) is the only one protected")

	# Pets under Lv120 are judged by their exact Lv120 projection.
	var young:Dictionary=Progression.species_actor("original_92",1,424242)
	young.merge({"pet_id":"pet-30","template_id":92,"species":"original_92","level":1})
	var projected:=Progression.project_pet(young,120)
	var seen:=KeepRule.stats_of(young)
	check(seen.projected and seen.attack==int(projected.attack) and seen.defence==int(projected.defence) and seen.speed==int(projected.speed) and seen.max_hp==int(projected.max_hp),"a Lv1 pet is judged by its exact Lv120 stats")

func settings() -> void:
	var rule:=default_rule()
	check(rule=={"tiers":2,"per_tier":3,"order":["attack","speed","max_hp"],"champions":2,"champion_stats":["attack","defence","speed","max_hp"],"auto":false},"defaults: 2 tiers x 3, 攻击 → 敏捷 → 血, top 2 of all four stats, auto tidy off")
	var good:=Settings.apply_patch({},{"stat_filters":{"92":{"keep_rule":{"tiers":1,"champion_stats":["attack"],"auto":true}}}})
	check(good.ok and good.overrides.stat_filters["92"].keep_rule=={"tiers":1,"champion_stats":["attack"],"auto":true},"a partial rule is stored")
	check(Settings.stat_filter(good.overrides,92).keep_rule.per_tier==3,"unset parts keep their defaults")
	for bad in [{"tiers":21},{"per_tier":-1},{"order":[]},{"order":["luck"]},{"champion_stats":["luck"]},{"champion_stats":["attack","attack"]},{"auto":1},{"bogus":1}]:
		check(not Settings.apply_patch({},{"stat_filters":{"92":{"keep_rule":bad}}}).ok,"an invalid rule is refused: %s" % str(bad))
	check(not Settings.apply_patch({},{"stat_filters":{"92":{"keep_qualified":3}}}).ok,"the replaced keep_qualified setting is no longer accepted")
	var migrated:=Settings.sanitize({"stat_filters":{"92":{"keep_qualified":5,"rank":["speed","sum","attack"],"mode":"all"}}})
	var filter:=Settings.stat_filter(migrated,92)
	check(filter.keep_rule.order==["speed","attack"] and not filter.has("keep_qualified") and not filter.has("rank") and str(filter.mode)=="all","an older save's chosen rank becomes the tier order (三围合 dropped); keep_qualified goes")
	var untouched:=Settings.sanitize({"stat_filters":{"92":{"keep_qualified":5}}})
	check(Settings.stat_filter(untouched,92).keep_rule==default_rule(),"an older save without a rank gets the default rule")

func run()->void:
	rules()
	settings()
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
	game.session.grant_starter_pets();game.load_area_id(300,Vector2i(509,90));game.session.gm_heal()
	var hunt=game.pet_hunt_menu;hunt.set_process(false)
	var flow=game.pet_workflow;flow.set_process(false)
	game.training_helper.set_process(false)
	var session=game.backend.session

	# Session tidy: carried pets can go; favourites, 出战, 骑乘 and protected stay.
	var party_count:int=session._profile.pets.size()
	var active:=pet("pet-600",250,150,140);var mount:=pet("pet-601",251,150,140);var carried:=pet("pet-602",252,150,140)
	session._profile.pets.append_array([active,mount,carried])
	session._profile.active_pet=party_count;session._profile.ride_pet=party_count+1
	var stored_fav:=pet("pet-603",253,150,140);stored_fav.favorite=true
	session._profile.pet_storage.append_array([pet("pet-610",294,180,153),pet("pet-611",280,160,140),stored_fav,pet("pet-612",281,160,140)])
	var other:=pet("pet-620",200,100,100);other.template_id=194;other.species="original_194";session._profile.pet_storage.append(other)
	var starter_id:=""
	for p in session._profile.pets:
		if p.species=="blue_dragon":starter_id=str(p.pet_id)
	var released:Array=session.apply_keep_rule(92,{"tiers":1,"per_tier":1,"order":["attack"],"champions":0,"champion_stats":[]},{starter_id:"削血宠"})
	var left:Array=(session._profile.pets+session._profile.pet_storage).map(func(p):return str(p.pet_id))
	check(released.has("pet-602") and not left.has("pet-602"),"a carried pet outside the rule is released")
	check(left.has("pet-600") and left.has("pet-601") and left.has("pet-603") and left.has(starter_id),"出战, 骑乘, favourite and protected pets stay")
	check(left.has("pet-610") and not left.has("pet-611") and not left.has("pet-612"),"the warehouse keeps the tier's best and releases the rest")
	check(left.has("pet-620"),"other species are untouched")
	check(int(session._profile.active_pet)>=0 and str(session._profile.pets[int(session._profile.active_pet)].pet_id)=="pet-600","the active pet is still active after releases")
	session._profile.pets=session._profile.pets.filter(func(p):return not str(p.pet_id).begins_with("pet-6"))
	session._profile.pet_storage=session._profile.pet_storage.filter(func(p):return not str(p.pet_id).begins_with("pet-6"))
	session._profile.active_pet=0;session._profile.ride_pet=-1

	# The find-pet cycle: auto tidy off leaves everything, on keeps the rule.
	var source:Dictionary=session.snapshot().pets[0].duplicate(true)
	var found_stats:=[[292,180,152],[293,180,152],[290,183,152],[294,178,152],[288,186,152],[293,181,152],[280,170,150]]
	var cycle:=func(target: Dictionary, base: int) -> Array:
		flow.kept_count=0;flow.collected_count=0;flow.target_stat_filter=target
		game.backend.automation.flow_released_count=0;game.backend.automation.flow_held_count=0
		var results:=[]
		for turn in range(found_stats.size()):
			var found:Dictionary=source.duplicate(true);found.pet_id="pet-%d"%(base+turn);found.species="original_92";found.template_id=92;found.level=120
			found.attack=found_stats[turn][0];found.defence=found_stats[turn][1];found.speed=found_stats[turn][2];found.erase("gm_modified")
			session._profile.pets.append(found);session._profile.active_pet=session._profile.pets.size()-1
			flow.pet_id=found.pet_id;flow.phase="train";flow.complete_trained_pet(found)
			results.append(flow.last_result)
			flow.phase="idle"
		return results
	# 三围合 ≥ 625−1 or 攻击 ≥ 294−1, as the cycle resolves 最高 − 1.
	var target:=Filter.resolve(Settings.default_stat_filter(92),{"sum":625,"attack":294})
	# 找到0只后停止 (hunt.stop_after, the whole run): every qualifier is stored.
	game.backend.automation.flow_settings_overrides={"hunt":{"stop_after":0}}
	cycle.call(target,700)
	var stored:Array=session._profile.pet_storage.filter(func(p):return str(p.pet_id).begins_with("pet-7"))
	check(stored.size()==7 and flow.released_count==0 and not flow.keep_auto,"auto tidy off (the default): every qualifier is stored")
	session._profile.pet_storage=session._profile.pet_storage.filter(func(p):return not str(p.pet_id).begins_with("pet-7"))
	target.keep_rule=target.keep_rule.duplicate(true);target.keep_rule.merge({"tiers":1,"per_tier":2,"champions":1,"champion_stats":["attack","defence"],"auto":true},true)
	var results:Array=cycle.call(target,800)
	var species_left:Array=KeepRule.species_pets(session.snapshot(),92).map(func(p):return str(p.pet_id))
	# Found: 800 624/292, 801 625/293, 802 625/290, 803 624/294, 804 626/288, 805 626/293, 806 600/280.
	check(species_left.has("pet-805") and species_left.has("pet-804") and species_left.has("pet-803"),"the 626 tier's best two and the attack champion stay")
	check(species_left.has("pet-802") or species_left.has("pet-804"),"the defence champion stays")
	check(not species_left.has("pet-800") and not species_left.has("pet-801") and not species_left.has("pet-806"),"pets outside the rule are released as the run goes")
	check(species_left.has(starter_id),"the Lv1 starter (a possible capture helper) is never released")
	check(flow.keep_auto and flow.released_count>=2 and flow.held_count==species_left.size(),"status: auto tidy on, released and remaining counts")
	check(results.any(func(text):return text.contains("按保留规则放生") or text.contains("不在保留规则内")),"a new pet outside the rule is reported as released")
	var status:String=hunt.workflow_summary()
	check(status.contains("保留规则自动整理") and status.contains("已放生"),"the hunt window reports the tidy")

	# UI: the 属性条件 page edits the rule and saves it.
	game.link.request({"type":"set_automation_settings","settings":{"stat_filters":null}});game.sync_state()
	hunt.open_menu();hunt.show_stat_settings()
	check(int(hunt.rule_tiers.value)==2 and int(hunt.rule_per_tier.value)==3 and int(hunt.rule_champions.value)==2 and hunt.rank_choice()==["attack","speed","max_hp"] and not hunt.rule_auto.button_pressed and hunt.rule_stats.defence.button_pressed,"the page shows the default rule")
	hunt.rule_tiers.value=1;hunt.rule_champions.value=3;hunt.rule_stats.max_hp.button_pressed=false;hunt.rule_auto.button_pressed=true
	hunt.stat_rank[1].select(hunt.stat_rank[1].get_item_index(Filter.RANK_KEYS.find("max_hp")+1))
	hunt.stat_rank[2].select(0)
	hunt.save_stat_settings(true);game.flush_automation_settings()
	var saved:Dictionary=game.stat_filter(92).keep_rule
	check(saved.tiers==1 and saved.champions==3 and saved.champion_stats==["attack","defence","speed"] and saved.order==["attack","max_hp"] and saved.auto,"the page saves tiers, champions, stats, order and auto tidy")
	game.link.request({"type":"set_automation_settings","settings":{"stat_filters":{"92":{"keep_rule":{"per_tier":5,"auto":false}}}}})
	hunt.load_stat_settings()
	check(int(hunt.rule_per_tier.value)==5 and not hunt.rule_auto.button_pressed,"a change from elsewhere shows on the page")
	hunt.hide();game.paused_input=false
	game.link.request({"type":"set_automation_settings","settings":{"stat_filters":null}});game.sync_state()

	# 同种比较: 按保留规则选中 selects exactly the rule's releases, releases nothing.
	session._profile.pet_storage=session._profile.pet_storage.filter(func(p):return not str(p.pet_id).begins_with("pet-8"))
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/keep_rule_dragons.json"))
	for entry in fixture.pets:
		var copy:Dictionary=entry.duplicate(true);copy.name="扬奇洛斯";copy.hp=copy.max_hp
		session._profile.pet_storage.append(copy)
	session._profile.next_pet_id=100000
	for i in range(session._profile.pets.size()):
		if str(session._profile.pets[i].pet_id)==starter_id:session._profile.active_pet=i
	game.sync_state()
	var expected:=KeepRule.evaluate(KeepRule.species_pets(session.snapshot(),92),default_rule(),KeepRule.always_kept(session.snapshot()))
	var menu=game.adventure_menu
	game.show_adventure_menu("pets")
	check(menu.open_pet_comparison("pet-268"),"the comparison opens")
	await process_frame
	var before:int=session.snapshot().pet_storage.size()
	menu.panel.find_child("CompareKeepRuleSelect",true,false).pressed.emit();await process_frame
	var chosen:Array=menu.pet_release_selected.keys();chosen.sort()
	var wanted:Array=expected.release.duplicate();wanted.sort()
	check(chosen==wanted and not chosen.is_empty(),"按保留规则选中 selects exactly the pets the rule releases (%d)" % chosen.size())
	check(not chosen.has(starter_id) and fixture.release.all(func(id):return chosen.has(id)),"the starter (出战 or capture helper) is not selected; every reference release is")
	check(session.snapshot().pet_storage.size()==before,"selecting releases nothing by itself")
	var overlay=menu.panel.get_node("PetComparisonPanel")
	var row=overlay.find_child("CompareRow_pet_storage_%d" % session.snapshot().pet_storage.map(func(p):return str(p.pet_id)).find("pet-268"),true,false)
	check(row!=null and row.tooltip_text.contains("保留：626档第1、攻击第1") and row.find_children("*","Label",true,false).any(func(label):return label.text=="保留：626档第1、攻击第1"),"a kept pet's row says why it stays")
	check(overlay.find_child("PetComparisonInfo",true,false).text.contains("按保留规则：保留"),"the panel summarises the rule and the counts")
	menu.panel.find_child("CompareClearSelection",true,false).pressed.emit();await process_frame
	check(menu.pet_release_selected.is_empty() and menu.pet_rule_reasons.is_empty(),"clearing the selection drops the rule preview")
	game.close_adventure_menu()

	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	print("KEEP RULE: %d failures" % failures)
	quit(1 if failures else 0)

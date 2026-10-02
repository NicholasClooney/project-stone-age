extends SceneTree
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, description: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+description)
	if not ok:failures+=1
func run() -> void:
	# 凯比特 (100298) stands in for original art that cannot be shown. Its
	# bitmaps decode now that overrunning runs are clipped like the original
	# client, so the skip-without-substitute path marks it missing here.
	preload("res://server/troop_art.gd")._validation["100298"] = false
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game)
	await process_frame
	game.pet_hunt_menu.open_menu();game.pet_hunt_menu.auto_capture.button_pressed=false
	check(game.pet_hunt_menu.start_button.disabled,"village cannot start hunting")
	game.pet_hunt_menu.close_menu()
	check(game.switch_area(true,Vector2i(45,45)),"enter original wilderness")
	var menu=game.pet_hunt_menu
	menu.open_menu();menu.auto_capture.button_pressed=false
	check(menu.preset.selected==3 and menu.total.value==8 and menu.min_offsets()==[2,2,2,2],"default is full four-stat +2 quality")
	check(menu.rate.value==0,"default requested rate is unlimited")
	check(not menu.start_button.disabled and game.paused_input,"modal pauses walking and enables local hunt")
	check(menu.species.item_count==3 and menu.species.is_item_disabled(2),"unavailable original pet art is explicit")
	if "--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("/tmp/pet-hunt-menu.png")
	var before: Dictionary=game.session.snapshot().duplicate(true)
	game.encounter_rng.seed=1234
	menu.start_hunt()
	menu.scan_once()
	check(game.session.snapshot()==before,"skipping a troop grants nothing and starts no battle")
	menu.close_menu()
	check(not menu.running and not game.paused_input and menu.total.editable,"closing cancels and unlocks settings")
	# 本机极速模式: on by default, saved with the character, greyed where the helper cannot run.
	var FastHunt=load("res://server/fast_hunt.gd")
	menu.open_menu()
	check(menu.fast.button_pressed and bool(game.automation_settings().hunt.fast),"本机极速模式 is on by default")
	menu.fast.button_pressed=false
	check(not bool(game.automation_settings().hunt.fast),"turning it off is saved with the character")
	menu.fast.button_pressed=true
	# 只进无其他敌人的遇敌 and its exception, on 抓宠设置.
	check(menu.clean_only.button_pressed and not menu.mixed_if_stats.button_pressed and not menu.mixed_if_stats.disabled and menu.runtime_page.is_ancestor_of(menu.clean_only),"运行设置 shows 跳过含高等级敌人的敌群 on and 属性达标仍进混合遇敌 off")
	menu.mixed_if_stats.button_pressed=true
	menu.clean_only.button_pressed=false
	check(not bool(game.automation_settings().hunt.clean_only) and bool(game.automation_settings().hunt.mixed_if_stats) and menu.mixed_if_stats.disabled,"both are saved with the character; the exception is greyed while the rule is off")
	menu.clean_only.button_pressed=true;menu.mixed_if_stats.button_pressed=false
	check(bool(game.automation_settings().hunt.clean_only) and not menu.mixed_if_stats.disabled,"turning the rule back on is saved too")
	var clean_rect: Rect2=menu.clean_only.get_global_rect()
	check(menu.runtime_page.is_ancestor_of(menu.clean_only) and menu.runtime_page.is_ancestor_of(menu.mixed_if_stats),"both remain reachable inside the runtime scroll")
	FastHunt.helper_override="/nonexistent/fast_hunt"
	game.backend.automation.fast_unavailable=FastHunt.unavailable_reason()
	game.backend.automation._emit_status()
	menu.close_menu();menu.open_menu()
	check(menu.fast.disabled and menu.fast.text.contains("不可用") and menu.fast.tooltip_text.contains("未编译"),"without the helper the option is greyed with the reason")
	FastHunt.helper_override=""
	game.backend.automation.fast_unavailable=""
	game.backend.automation._emit_status()
	menu.close_menu()
	menu.open_menu();menu.auto_capture.button_pressed=false
	menu.start_hunt()
	for i in range(20000):
		if not menu.running:break
		menu.scan_once()
	check(not menu.last_hit.is_empty(),"real source rolls find a matching newborn")
	check(game.battle_view.visible and not menu.visible,"match enters ordinary battle")
	if not menu.last_hit.is_empty() and game.battle_view.visible:
		var index: int=menu.last_hit.index
		var actor: Dictionary=menu.last_hit.actor
		var state: Dictionary=game.battle_session.snapshot()
		check(state.enemies[index].growth_weights==actor.growth_weights and state.enemies[index].base_stats==actor.base_stats,"exact individual survives battle handoff without reroll")
		check(state.enemies[index].name==actor.name,"highlight does not mutate pet name")
		check(game.battle_view.actor_labels[game.battle_view.enemy_actor(index)].text.begins_with("★"),"matched enemy is visibly marked")
		check(menu.last_hit.quality.total_offset==8 and actor.level==1,"found individual meets requested filters")
	check(game.session.snapshot().pets==before.pets,"helper does not capture automatically")
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null
	game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("PET HUNT UI: %d failures"%failures)
	quit(1 if failures else 0)

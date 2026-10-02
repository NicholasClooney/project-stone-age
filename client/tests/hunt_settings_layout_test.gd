extends SceneTree
## Native screenshots exercise the same production scene as the headless geometry checks.
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
var visual:=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func shot(name:String)->void:
	if not visual:return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/hunt-runtime-shots/"+name+".png")
func run()->void:
	root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO
	visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;game.viewer_prefs_path="user://hunt-settings-layout-new.cfg";root.add_child(game)
	await process_frame;game.switch_area(true,Vector2i(45,45))
	var menu=game.pet_hunt_menu;menu.open_menu()
	for size in [Vector2i(1280,720),Vector2i(390,844),Vector2i(844,390)]:
		root.size=size;menu.relayout();await process_frame
		for page in ["runtime","keep"]:
			menu.show_page(page);await process_frame
			var scroll:ScrollContainer=menu.runtime_scroll if page=="runtime" else menu.keep_scroll
			check(scroll.size.x<=menu.window_scroll.size.x and scroll.horizontal_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"new page fits width without horizontal scrolling")
			scroll.scroll_vertical=0;await process_frame
			await shot("layout-%dx%d-%s-top"%[size.x,size.y,page])
			var selected:Array=[menu.fast,menu.showcase,menu.show_battles,menu.train_after_capture,menu.capture_only,menu.battle_training,menu.clean_only,menu.mixed_if_stats,menu.rule_auto,menu.resume_after_restart] if page=="runtime" else [menu.queue_size,menu.rule_tiers,menu.rule_per_tier,menu.rule_champions]+menu.stat_rank+menu.rule_stats.values()
			for control in selected:
				scroll.ensure_control_visible(control);await process_frame
				check(await Wait.until(self,func():return scroll.get_global_rect().encloses(control.get_global_rect())),"complete control reachable: "+str(control.name))
				check(not control.get_global_rect().intersects(menu.status.get_global_rect()),"separate status: "+str(control.name))
				check(control.size.y>=44,"touch target at least44px")
			if page=="runtime":
				scroll.ensure_control_visible(menu.capture_only);await process_frame
				await shot("layout-%dx%d-runtime-modes"%[size.x,size.y])
				check(not menu.capture_only.get_global_rect().intersects(menu.train_after_capture.get_global_rect()),"capture-only and cultivation rows do not overlap")
				scroll.ensure_control_visible(menu.rule_auto);await process_frame
				await shot("layout-%dx%d-runtime-bottom"%[size.x,size.y])
			else:
				scroll.scroll_vertical=10000;await shot("layout-%dx%d-keep-bottom"%[size.x,size.y])
		root.size=Vector2i(1280,720);menu.show_page("capture");await process_frame
		var helper=game.training_helper
		var fields:Array=[helper.capture_hp,helper.capture_pet,helper.capture_pet_max_level,helper.capture_fallback_attempts,helper.capture_fallback_rate,helper.capture_fallback_hp]
		for i in range(fields.size()):
			for j in range(i):check(not fields[i].get_global_rect().intersects(fields[j].get_global_rect()),"capture tactic fields do not overlap")
		await shot("layout-1280x720-capture")
		menu.show_stat_settings();await process_frame
		check(menu.stat_page.get_node("StatSettingsScroll").get_global_rect().encloses(menu.stat_species.get_global_rect()),"species control fully visible at top of stat page")
		check(not menu.stat_page.is_ancestor_of(menu.rule_auto) and not menu.stat_page.is_ancestor_of(menu.rule_tiers),"shared keep and automatic tidy no longer squeeze species thresholds")
		await shot("layout-1280x720-stats")
	game.music.stop();game.effect.stop();game.queue_free();await process_frame
	print("HUNT SETTINGS LAYOUT: %d failures"%failures);quit(1 if failures else 0)

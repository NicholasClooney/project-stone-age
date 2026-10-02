extends SceneTree
## Shared settings migration and real backend/session/queue decisions.
const Settings=preload("res://scripts/automation_settings.gd")
const Backend=preload("res://server/backend.gd")
const KeepRule=preload("res://scripts/keep_rule.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func migrations()->void:
	var old:={"hunt":{"stat_species":93,"template":92},"stat_filters":{"92":{"keep_rule":{"tiers":1,"order":["attack"]},"conditions":{"sum":{"keep":9}}},"93":{"keep_rule":{"tiers":4,"order":["speed"]}},"94":{"keep_rule":{"tiers":5}}}}
	var migrated:=Settings.sanitize(old)
	check(Settings.keep_rule(migrated).tiers==4 and Settings.keep_rule(migrated).order==["speed"],"last edited species rule wins across different legacy rules")
	check(Settings.stat_filter(migrated,92).conditions.sum.keep==9 and not Settings.stat_filter(migrated,92).has("keep_rule"),"per-species threshold quota stays independent and deprecated rule disappears")
	old.hunt.stat_species=999
	check(Settings.keep_rule(Settings.sanitize(old)).tiers==1,"legacy target is second migration choice")
	old.hunt.template=999
	check(Settings.keep_rule(Settings.sanitize(old)).tiers==1,"first saved rule is final migration choice")
	old.hunt.stat_species={"invalid":"value"}
	check(Settings.keep_rule(Settings.sanitize(old)).tiers==1,"invalid saved species selector is normalized before migration")
	old.hunt.keep_rule={"tiers":7,"order":["max_hp"],"auto":true}
	check(Settings.keep_rule(Settings.sanitize(old)).tiers==7,"explicit shared save rule wins")
	old.hunt.keep_rule={"tiers":999,"per_tier":4,"order":["attack","attack"],"auto":1,"bogus":1}
	var normalized:=Settings.keep_rule(Settings.sanitize(old))
	check(normalized.tiers==2 and normalized.per_tier==4 and normalized.order==["attack","speed","max_hp"] and not normalized.auto,"invalid stored shared leaves use defaults without falling back to old rules")
	check(Settings.keep_rule(Settings.sanitize({}))==Settings.keep_rule({}),"missing old and shared rules use defaults")
	var current:=Settings.sanitize({"hunt":{"keep_rule":{"tiers":7}}})
	var ignored:=Settings.apply_patch(current,{"stat_filters":{"92":{"keep_rule":{"tiers":0,"auto":true},"conditions":{"sum":{"minus":6}}},"93":{"keep_rule":"invalid old client value"}}})
	check(ignored.ok and Settings.keep_rule(ignored.overrides).tiers==7 and not Settings.keep_rule(ignored.overrides).auto,"old client rule writes are accepted and ignored even for another species")
	check(Settings.stat_filter(ignored.overrides,92).conditions.sum.minus==6,"old client still edits its species thresholds")
	for bad in [{"tiers":21},{"order":[]},{"order":["speed","speed"]},{"auto":1},{"champion_stats":["sum"]},{"extra":1}]:
		check(not Settings.apply_patch(current,{"hunt":{"keep_rule":bad}}).ok,"shared patch strictly rejects "+str(bad))
	check(Settings.keep_rule(Settings.apply_patch(current,{"hunt":{"keep_rule":null}}).overrides)==Settings.keep_rule({}),"null shared rule resets to defaults")
func run()->void:
	migrations()
	var backend=Backend.new();backend.set_process(false);root.add_child(backend)
	var auto=backend.automation
	var rule:={"tiers":1,"per_tier":1,"order":["speed"],"champions":0,"champion_stats":[],"auto":true}
	check(backend.handle({"type":"set_automation_settings","settings":{"hunt":{"keep_rule":rule,"stop_after":0}}}).ok,"real backend accepts shared rule")
	auto.flow_settings_overrides=backend.session.automation_settings()
	auto.flow_target_filter={"keep_rule":{"tiers":0,"auto":false}}
	# Real original pet generation, leveling and warehouse commands.
	for template in [92,93]:
		for i in range(3):
			check(backend.session.gm_grant_pet(template,true),"original species pet granted")
			var index:int=backend.session.snapshot().pets.size()-1
			check(backend.session.gm_raise_level(index,120),"real progression levels pet")
			check(backend.session.store_pet(index,true),"real session stores pet")
	var before93:=KeepRule.species_pets(backend.session.snapshot(),93).map(func(p):return p.pet_id)
	var released:Array=auto._tidy_species({"template_id":92})
	check(released.size()==2 and KeepRule.species_pets(backend.session.snapshot(),92).size()==1,"current shared rule tidies species even with conflicting old captured filter")
	check(KeepRule.species_pets(backend.session.snapshot(),93).map(func(p):return p.pet_id)==before93,"tidying one species never ranks or releases another species")
	check(auto._tidy_species({"template_id":93}).size()==2 and KeepRule.species_pets(backend.session.snapshot(),93).size()==1,"same quota applies separately to another species")
	var a:={"actor":{"template_id":92},"index":1,"prediction":{"attack":300,"defence":150,"speed":100,"max_hp":1200}}
	var b:={"actor":{"template_id":92},"index":2,"prediction":{"attack":200,"defence":150,"speed":200,"max_hp":1200}}
	check(auto._showcase_better(b,a),"queue uses shared speed priority")
	auto.hunt_filter={"templates":[92,93]}
	var key:String=auto.threshold_key()
	auto.flow_phase="hunt"
	backend.handle({"type":"set_automation_settings","settings":{"hunt":{"keep_rule":{"order":["attack"]}}}})
	check(auto._showcase_better(a,b) and auto.threshold_key()!=key,"live shared order change updates queue comparison and native restart key")
	var candidates:=[]
	for template in [92,93]:
		for i in range(2):candidates.append({"template_id":template,"serial":template*10+i,"prediction":{"attack":200+i,"defence":150-i,"speed":100,"max_hp":1200}})
	var picked:Array=auto.survey_choose(candidates)
	check(picked.size()==2 and picked.any(func(c):return int(c.template_id)==92) and picked.any(func(c):return int(c.template_id)==93),"survey applies shared rule within separate species groups")
	backend.save_path="user://shared-keep-save.json"
	check(backend.save(),"real shared settings save")
	var fresh=Backend.new();fresh.set_process(false);root.add_child(fresh)
	check(fresh.load_profile(backend.save_path) and Settings.keep_rule(fresh.session.automation_settings()).order==["attack"],"shared rule survives profile restart")
	check(not fresh.session.automation_settings().get("stat_filters",{}).get("92",{}).has("keep_rule"),"saved profile has no deprecated per-species rule")
	# A real narrow viewport checks geometry without opening a graphical window.
	var phone:=SubViewport.new();phone.size=Vector2i(390,844);root.add_child(phone)
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false;game.viewer_prefs_path="user://shared-keep-phone.cfg"
	phone.add_child(game);await process_frame
	var menu=game.pet_hunt_menu
	menu.open_menu();menu.show_page("keep");await process_frame
	var frame:Rect2=menu.window_scroll.get_global_rect()
	check(Rect2(Vector2.ZERO,Vector2(390,844)).encloses(frame),"mobile hunt viewport is bounded by the narrow screen")
	check(menu.panel.size.x<=390 and menu.window_scroll.size.x<=390,"shared rules fit narrow viewport without horizontal scrolling")
	check(not menu.rule_tiers.get_global_rect().intersects(menu.rule_per_tier.get_global_rect()) and not menu.rule_champions.get_global_rect().intersects(menu.rule_auto.get_global_rect()),"mobile keep rows have no overlapping controls")
	menu.keep_scroll.ensure_control_visible(menu.stat_rank[2]);await process_frame
	check(frame.intersects(menu.stat_rank[2].get_global_rect()),"vertical scrolling reaches complete third ranking selector")
	menu.window_scroll.scroll_horizontal=0;menu.show_page("runtime");await process_frame
	menu.runtime_scroll.ensure_control_visible(menu.stop_after);await process_frame
	check(not menu.stop_after.get_global_rect().intersects(menu.train_after_capture.get_global_rect()) and not menu.stop_after.get_global_rect().intersects(menu.capture_only.get_global_rect()),"mobile stop-after has a separate runtime row")
	game.link.request({"type":"set_automation_settings","settings":{"hunt":{"keep_rule":{"tiers":0,"champions":0}}}})
	for template in [92,93]:
		game.link.request({"type":"gm_grant_pet","template":template,"full_grade":true})
		game.link.request({"type":"store_pet","index":game.session.snapshot().pets.size()-1})
	var compare=game.adventure_menu
	compare.pet_release_species="original_92"
	compare.select_by_keep_rule(game.session.snapshot())
	var preview:Array=compare.pet_release_selected.keys()
	var dragon_ids:Array=KeepRule.species_pets(game.session.snapshot(),92).map(func(p):return p.pet_id)
	check(not preview.is_empty() and preview.all(func(id):return id in dragon_ids),"same-species preview reads shared quota and never selects another species")
	game.music.stop();game.effect.stop();phone.queue_free()
	backend.queue_free();fresh.queue_free();await process_frame
	print("HUNT SHARED KEEP RULE: %d failures"%failures);quit(1 if failures else 0)

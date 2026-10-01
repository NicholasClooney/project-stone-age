extends SceneTree
## Automation settings over a real localhost WebSocket: they belong to the
## character, so a change on one device shows in another device's open
## 自动抓极品 / 自动练级 windows and in a reloaded page, while the battle
## playback speed stays with the device that chose it.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const MAP := 100
const CELL := Vector2i(637,493)
const Wait = preload("res://tests/support/wait.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func until(condition: Callable, seconds: float = Wait.DEADLINE) -> bool:
	return await Wait.until(self,condition,seconds)

func prefs(tag: String) -> String:
	return "user://remote-settings-test-%s.cfg" % tag

func connect_client(port: int, tag: String):
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = "ws://127.0.0.1:%d" % port
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	game.viewer_prefs_path = prefs(tag)
	root.add_child(game)
	check(await until(func():return not game.data.is_empty() and game.link.online) and await Wait.settle(self,game),"a client connects and its startup reaches the backend")
	game.random_encounters = false
	return game

func close_client(game) -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.link.close()
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame

## Nothing in the way of opening a window (see pet_hunt_menu.gd open_menu).
func idle(game) -> bool:
	return not game.paused_input and not game.area_transition_busy and not game.battle_view.visible

func hunt_settings(backend) -> Dictionary:
	return backend.session.automation_settings().get("hunt",{})

func run() -> void:
	for tag in ["a","b","c"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs(tag)))
	var backend = Backend.new()
	root.add_child(backend)
	backend.handle({"type":"grant_starter_pets"})
	var port := 0 # any free port; the server reports the one it got
	var server = WsServer.new(backend,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"backend listens on localhost")
	port = server.port

	var a = await connect_client(port,"a")
	var b = await connect_client(port,"b")
	check(not a.link.is_local() and not b.link.is_local(),"two remote devices connect")
	a.load_area_id(MAP,CELL)
	check(await until(func():return backend.automation.position_map==MAP and int(b.data.map_id)==MAP and b.cell==CELL),"both devices stand on the hunting ground")
	check(await until(func():return idle(a) and idle(b)),"both devices have arrived and can open a window")
	var hunt_a = a.pet_hunt_menu
	var hunt_b = b.pet_hunt_menu
	hunt_a.open_menu();hunt_b.open_menu()
	check(hunt_a.visible and hunt_b.visible and hunt_b.rate.value==0 and hunt_b.level_one.button_pressed,"both hunt windows open on the defaults")

	hunt_a.target_button.get_popup().id_pressed.emit(-3)
	check(await until(func():return hunt_settings(backend).get("templates",null)==[]) and await until(func():return hunt_b.target_ids.is_empty()),"remote checklist all-none saves through server and snapshots")
	hunt_a.target_button.get_popup().id_pressed.emit(113)
	check(await until(func():return hunt_settings(backend).get("templates",[])==[113]) and await until(func():return hunt_b.target_ids==[113]),"remote actual checklist click selects one species without a local backend")
	hunt_a.target_button.get_popup().id_pressed.emit(-2)
	check(await until(func():return hunt_settings(backend).get("templates",[]).size()>=1),"remote all-select reaches authoritative profile")
	check(a.training_helper.select_troops.button_pressed and b.training_helper.select_troops.button_pressed,"remote training selection defaults on")
	a.training_helper.select_troops.button_pressed=false
	check(await until(func():return not preload("res://scripts/automation_settings.gd").effective(backend.session.automation_settings()).training.select_troops) and await until(func():return not b.training_helper.select_troops.button_pressed),"actual remote checkbox saves false through server and synchronizes other device")
	a.training_helper.select_troops.button_pressed=true
	check(await until(func():return preload("res://scripts/automation_settings.gd").effective(backend.session.automation_settings()).training.select_troops) and await until(func():return b.training_helper.select_troops.button_pressed),"remote checkbox restores default selection and snapshots")
	check(a.training_helper.borrow_troops.button_pressed and b.training_helper.borrow_troops.button_pressed,"remote borrowing is default on without a backend")
	a.training_helper.borrow_troops.button_pressed=false
	check(await until(func():return not preload("res://scripts/automation_settings.gd").effective(backend.session.automation_settings()).training.borrow_troops) and await until(func():return not b.training_helper.borrow_troops.button_pressed),"remote true checkbox click saves borrow off and updates second device")
	b.training_helper.borrow_troops.button_pressed=true
	check(await until(func():return preload("res://scripts/automation_settings.gd").effective(backend.session.automation_settings()).training.borrow_troops) and await until(func():return a.training_helper.borrow_troops.button_pressed),"remote borrow-on roundtrip updates authority and both snapshots")
	# A choice is saved at once; typed numbers once the player pauses.
	hunt_a.level_one.button_pressed = false
	check(await until(func():return hunt_settings(backend).get("level_one",true)==false),"device A's choice reaches the profile")
	check(await until(func():return not hunt_b.level_one.button_pressed),"device B's open window shows device A's choice")
	for value in [10,11,12,13]:hunt_a.rate.value = value
	check(await until(func():return int(hunt_settings(backend).get("rate",0))==13),"stepped numbers are saved once")
	check(await until(func():return int(hunt_b.rate.value)==13),"device B's open window shows the new rate")

	# A number being typed on B is left alone; other values still follow.
	hunt_b.limit.get_line_edit().grab_focus()
	hunt_a.limit.value = 500;hunt_a.total.value = 5
	check(await until(func():return int(hunt_settings(backend).get("limit",0))==500 and int(hunt_b.total.value)==5),"a change from A arrives while B is typing")
	check(int(hunt_b.limit.value)==0 and hunt_b.limit.get_line_edit().has_focus(),"the field B is typing in is not rewritten")
	hunt_b.limit.get_line_edit().release_focus()
	check(await until(func():return int(hunt_b.limit.value)==500),"once B stops typing without a change, the field shows A's value")
	check(int(hunt_settings(backend).get("limit",0))==500,"leaving the field unchanged does not send B's old value")
	# A change B makes and has not sent yet is kept, then saved.
	hunt_b.rate.value = 40
	hunt_a.total.value = 6
	check(await until(func():return int(hunt_settings(backend).get("total",0))==6 and int(hunt_settings(backend).get("rate",0))==40),"both devices' changes are saved")
	check(await until(func():return int(hunt_a.rate.value)==40 and int(hunt_b.total.value)==6),"and each device shows the other's")

	# Stat conditions per species follow as well.
	hunt_a.show_stat_settings();hunt_b.show_stat_settings()
	var shown := str(hunt_a.stat_species.get_selected_id())
	check(shown==str(hunt_b.stat_species.get_selected_id()) and shown!="-1","both devices' 属性条件 show the same species")
	hunt_a.stat_numbers.sum.value = 4
	check(await until(func():return int(backend.session.automation_settings().get("stat_filters",{}).get(shown,{}).get("conditions",{}).get("sum",{}).get("minus",0))==4),"a stat condition reaches the profile")
	check(await until(func():return int(hunt_b.stat_numbers.sum.value)==4),"device B's attribute tab shows the new condition")
	# 保留规则 follows too.
	hunt_a.rule_per_tier.value = 4
	hunt_a.stat_rank[1].select(hunt_a.stat_rank[1].get_item_index(5)) # 体力
	hunt_a.rule_auto.button_pressed = true
	hunt_a.save_stat_settings(true)
	check(await until(func():
		var rule: Dictionary = backend.session.automation_settings().get("hunt",{}).get("keep_rule",{})
		return int(rule.get("per_tier",0))==4 and rule.get("order",[])==["attack","max_hp"] and bool(rule.get("auto",false))),"the keep rule reaches the profile")
	check(await until(func():return int(hunt_b.rule_per_tier.value)==4 and hunt_b.rank_choice()==["attack","max_hp"] and hunt_b.rule_auto.button_pressed),"device B's attribute tab shows it")


	# Choose a different species on device B; only conditions switch.
	var other:=-1
	for i in range(hunt_b.stat_species.item_count):
		if not hunt_b.stat_species.is_item_disabled(i) and hunt_b.stat_species.get_item_id(i)!=int(shown):other=i;break
	check(other>=0,"hunting ground exposes another species")
	if other>=0:
		hunt_b.stat_species.select(other);hunt_b.stat_species.item_selected.emit(other)
		check(await until(func():return int(hunt_b.rule_per_tier.value)==4 and hunt_b.rule_auto.button_pressed),"another species shows the same shared rule")
		hunt_b.rule_champions.value=5;hunt_b.save_stat_settings(true)
		check(await until(func():return int(hunt_a.rule_champions.value)==5),"shared rule change from another species synchronizes original device")
	check(a.backend==null and b.backend==null,"remote rule clicks use no local backend")
	await process_frame
	var bounded:ScrollContainer=hunt_b.stat_page.get_node("StatSettingsScroll")
	check(bounded.get_global_rect().end.y<=hunt_b.status.get_global_rect().position.y,"stat settings viewport ends above status")
	check(not hunt_b.rule_tiers.get_global_rect().intersects(hunt_b.rule_per_tier.get_global_rect()) and not hunt_b.rule_champions.get_global_rect().intersects(hunt_b.rule_auto.get_global_rect()),"keep control rows have separate rectangles")
	var outer:ScrollContainer=hunt_b.window_scroll
	check(outer.get_rect().size.x<=b.get_viewport_rect().size.x and outer.get_rect().size.y<=b.get_viewport_rect().size.y,"hunt scroll viewport fits screen")

	# Training settings: per character, except the playback speed.
	var helper_a = a.training_helper
	var helper_b = b.training_helper
	hunt_a.close_menu();hunt_b.close_menu()
	helper_a.open_menu()
	helper_a.hp_floor.value = 33;helper_a.speed.select(1);helper_a.compact.button_pressed = false
	helper_a.apply_settings();helper_a.close_menu()
	check(await until(func():return int(backend.session.automation_settings().get("training",{}).get("hp",0))==33),"applied training settings reach the profile")
	check(await until(func():return int(helper_b.hp_floor.value)==33 and not helper_b.compact.button_pressed),"device B's training controls follow, compact battles included")
	check(a.battle_view.playback_speed==2.0 and b.battle_view.playback_speed==1.0 and helper_b.speed.selected==3,"the playback speed stays with the device that chose it")
	check(not backend.session.automation_settings().get("training",{}).has("speed"),"the playback speed is not saved with the character")

	# A reloaded page shows the character's settings.
	await close_client(a)
	var c = await connect_client(port,"c")
	check(await until(func():return idle(c)),"the reloaded page has arrived and can open a window")
	var hunt_c = c.pet_hunt_menu
	hunt_c.open_menu()
	check(int(hunt_c.rate.value)==40 and int(hunt_c.limit.value)==500 and int(hunt_c.total.value)==6 and not hunt_c.level_one.button_pressed and hunt_c.preset.selected==4,"a reloaded page shows the saved hunt settings")
	hunt_c.show_stat_settings()
	check(int(hunt_c.stat_numbers.sum.value)==int(preload("res://scripts/automation_settings.gd").stat_filter(backend.session.automation_settings(),hunt_c.stat_species.get_selected_id()).conditions.sum.minus) and int(preload("res://scripts/automation_settings.gd").stat_filter(backend.session.automation_settings(),int(shown)).conditions.sum.minus)==4,"saved species choice reloads its independent conditions without changing original species")
	check(int(c.training_helper.hp_floor.value)==33 and not c.training_helper.compact.button_pressed and c.training_helper.speed.selected==3,"and the saved training settings, with this device's own speed")
	hunt_c.close_menu()

	# The hunt runs with the profile's settings; the client sends none.
	hunt_c.open_menu()
	hunt_c.auto_capture.button_pressed = false
	hunt_c.train_after_capture.button_pressed = false
	hunt_c.start_hunt()
	check(await until(func():return backend.automation.hunt_running and hunt_c.running),"a hunt starts from the saved settings")
	var used: Dictionary = backend.automation.hunt_filter
	check(int(used.get("rate",0))==40 and int(used.get("limit",0))==500 and not bool(used.get("level_one",true)),"the backend hunts with the character's settings")
	hunt_c.close_menu()
	check(await until(func():return not backend.automation.hunt_running),"closing stops the hunt")

	await close_client(b);await close_client(c)
	server.stop()
	backend.queue_free();server.queue_free()
	await process_frame
	for tag in ["a","b","c"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs(tag)))
	print("REMOTE SETTINGS: %d failures" % failures)
	quit(1 if failures else 0)

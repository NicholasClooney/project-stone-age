extends SceneTree
## 宠物大全 瞬移去抓 to an added rare Lv.1 spot on a remote client that, like
## the web build, has only the maps it has downloaded: a real mouse click on
## the button downloads the target map first, then teleports onto drawn
## ground and opens 自动抓极品 with the target in both pickers before the
## settings round trip returns. A failed download reopens 宠物大全 and says so.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const Wait = preload("res://tests/support/wait.gd")
const OKA := 301 # 奥卡洛斯 (绿暴): 补充 Lv.1 on 五十年前波拉岛 area 652
const EDI := 968 # 艾迪希洛 (机豹): 非原版 Lv.1 on map 32019
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func until(condition: Callable, seconds: float = Wait.DEADLINE) -> bool:
	return await Wait.until(self,condition,seconds)

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await process_frame

## Pretends the map's pack is being downloaded, as on the web: nothing is
## fetched, and finish_download() ends it.
func web_packs(game, map_id: int) -> void:
	var pack := "map-%d" % map_id
	game.asset_packs.enabled = true
	game.asset_packs.index = {"packs":{pack:{"file":pack+".pck","bytes":1}},"maps":{str(map_id):[pack]}}
	game.asset_packs._mounted.clear()
	game.asset_packs._active[HTTPRequest.new()] = pack

func finish_download(game, ok: bool) -> void:
	var packs = game.asset_packs
	for request in packs._active.keys():request.free()
	packs._active.clear()
	for pack in packs.index.packs:
		if ok:packs._mounted[pack] = true
		else:packs._failed[pack] = true
	packs._settle()

func place_button(menu, template_id: int, origin: String):
	menu.open_menu(template_id)
	await process_frame
	var entry: Dictionary = menu.book.entry_for(template_id)
	var places: Array = entry.locations.filter(func(place):return str(place.get("origin","")) == origin and int(place.level_min) <= 1)
	if places.is_empty():return [null,{}]
	var place: Dictionary = places[0]
	return [menu.body.find_child("GoPlace%d_%d_%s" % [int(place.map_id),int(place.area_id),origin],true,false),place]

func run() -> void:
	var backend = Backend.new()
	root.add_child(backend)
	backend.handle({"type":"grant_starter_pets"})
	var server = WsServer.new(backend,0,"127.0.0.1")
	root.add_child(server)
	check(server.start() == OK,"backend listens on localhost")
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = "ws://127.0.0.1:%d" % server.port
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	game.viewer_prefs_path = "user://rare-teleport-test.cfg"
	root.add_child(game)
	check(await until(func():return not game.data.is_empty() and game.link.online) and await Wait.settle(self,game),"a remote client connects")
	game.random_encounters = false
	# The character last hunted 蓝人龙 and looked at its 属性条件.
	game.link.request({"type":"set_automation_settings","settings":{"hunt":{"template":92,"stat_species":92,"level_one":false}}})
	check(await until(func():return int(game.automation_settings().hunt.stat_species) == 92),"the saved hunt is 蓝人龙")
	var menu = game.pet_encyclopedia
	var hunt = game.pet_hunt_menu

	# 奥卡洛斯: its map is not downloaded yet.
	web_packs(game,500)
	var found: Array = await place_button(menu,OKA,"original_area")
	var button: Button = found[0]
	var place: Dictionary = found[1]
	check(button != null and not button.disabled and button.is_visible_in_tree(),"奥卡洛斯's page has 瞬移去抓 for its 补充 Lv.1 place")
	if button == null:return finish(game,backend,server)
	await click(button)
	check(not menu.visible and int(game.data.map_id) != 500 and not menu.pending_hunt.is_empty() and game.asset_packs.blocking(),"a click closes 宠物大全 and downloads the map before the teleport")
	finish_download(game,true)
	var cell := Vector2i(place.cell[0],place.cell[1])
	check(await until(func():return hunt.visible),"自动抓极品 opens on arrival")
	check(int(game.data.map_id) == 500 and game.cell == cell,"teleported to 五十年前波拉岛 %s" % cell)
	check(int(game.data.ground[cell.y*int(game.data.width)+cell.x]) != 0,"the landing cell has ground, not the black void outside the walls")
	check(hunt.species.get_selected_id() == OKA and hunt.stat_species.get_selected_id() == OKA,"both pickers show 奥卡洛斯 at once, before the settings come back")
	check(await until(func():return int(backend.session.automation_settings().hunt.get("stat_species",-1)) == OKA and int(backend.session.automation_settings().hunt.get("template",-1)) == OKA),"the character's hunt settings follow")
	check(await until(func():return int(game.automation_settings().hunt.stat_species) == OKA) and hunt.species.get_selected_id() == OKA and hunt.stat_species.get_selected_id() == OKA,"and the reply keeps 奥卡洛斯 in both pickers")
	check(hunt.stat_species.get_item_index(92) < 0,"属性条件 lists only species that live here, without 蓝人龙")
	hunt.close_menu()
	await until(func():return not game.paused_input)

	# 艾迪希洛: the download fails, so 宠物大全 comes back and says why.
	web_packs(game,32019)
	found = await place_button(menu,EDI,"added")
	button = found[0]
	check(button != null and not button.disabled,"艾迪希洛's page has 瞬移去抓 for its 非原版 Lv.1 place")
	if button == null:return finish(game,backend,server)
	await click(button)
	check(not menu.visible,"the second click closes 宠物大全 too")
	finish_download(game,false)
	check(await until(func():return menu.visible),"a failed download reopens 宠物大全")
	check(menu.feedback.contains("下载失败") and menu.feedback_label.visible and int(game.data.map_id) == 500 and menu.pending_hunt.is_empty(),"and says the map could not be downloaded")
	menu.close_menu()
	await until(func():return not game.paused_input)

	# 刷怪传送 to a map not downloaded yet: the map comes first, then the teleport.
	var leveling = game.leveling_destinations
	leveling.open_menu()
	var pick := -1
	for i in range(leveling.ranked.size()):
		if int(leveling.ranked[i].map_id) != 500:
			pick = i
			break
	check(pick >= 0,"刷怪传送 lists a spot on another map")
	if pick < 0:return finish(game,backend,server)
	var spot: Dictionary = leveling.ranked[pick]
	web_packs(game,int(spot.map_id))
	check(leveling.visit(pick) and leveling.details.text.contains("正在下载地图") and int(game.data.map_id) == 500,"刷怪传送 waits for the map's download instead of refusing the landing")
	finish_download(game,true)
	check(await until(func():return int(game.data.map_id) == int(spot.map_id) and game.cell == Vector2i(spot.cell[0],spot.cell[1]) and not game.area_transition_busy),"then teleports to the spot (%s)" % str(spot.cell))
	await Wait.settle(self,game)

	# 地图导航's Lv.1 place on a map not downloaded yet: the same.
	var nav = game.dev_map_overview
	var target := {"name":"奥卡洛斯 Lv1","cell":cell,"map_id":500,"area_id":int(place.area_id),"kind":"pet_added"}
	web_packs(game,500)
	nav.open_map()
	check(nav.select_poi(target) and nav.note.text.contains("正在下载地图"),"地图导航 waits for the map's download before checking the landing")
	finish_download(game,true)
	check(await until(func():return nav.current_map == 500),"then browses the downloaded map to travel there")
	nav.close_map()
	finish(game,backend,server)

func finish(game, backend, server) -> void:
	game.asset_packs.enabled = false
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.link.close()
	game.music.stop();game.effect.stop();game.queue_free()
	server.stop()
	backend.queue_free();server.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://rare-teleport-test.cfg"))
	print("RARE TELEPORT: %d failures" % failures)
	quit(1 if failures else 0)

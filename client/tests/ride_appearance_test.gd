extends SceneTree
## Real indexed art, authoritative save rollback, and two WebSocket game clients.
const Backend = preload("res://server/backend.gd")
const Riding = preload("res://scripts/riding.gd")
const Wait = preload("res://tests/support/wait.gd")
## Real AssetPacks ensure/is_ready/waiter settlement; only the download shell
## is held back. No importer, network downloader or resource mount runs here.
class DelayedPacks extends "res://scripts/asset_packs.gd":
	func _mount_local(_pack: String) -> bool:return false
	func _pump() -> void:pass
	func complete(packs: Array) -> void:
		for pack in packs:_mounted[pack] = true
		_settle()

var failures := 0
const OUT := "/private/tmp/ride-pick-appearance/"
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1
func fixture():
	var backend = Backend.new()
	root.add_child(backend)
	for template in [191,194,776,777]:check(backend.session.gm_grant_pet(template,true),"original pet fixture %d" % template)
	backend.session.set_character("100030")
	backend.session.select_pet(-1)
	backend.handle({"type":"report_position","map_id":1000,"cell":[80,90]})
	backend.publish()
	return backend
func command(backend, index: int = 1) -> Dictionary:
	var profile: Dictionary = backend.session.snapshot()
	return {"type":"mount_pet_as","pet_id":str(profile.pets[index].pet_id),"character_id":"100010","expected_character":str(profile.character_id),"map_id":backend.automation.position_map,"cell":[backend.automation.position_cell.x,backend.automation.position_cell.y]}
func authority() -> void:
	var backend = fixture()
	var profile: Dictionary = backend.session.snapshot()
	check(Riding.composite("100030",int(profile.pets[0].sprite))>=0,"100030 has original 贝鲁卡 riding art")
	check(Riding.composite("100030",int(profile.pets[1].sprite))<0 and "100010" in Riding.compatible_characters(int(profile.pets[1].sprite)),"gold tiger needs another indexed appearance")
	for i in [2,3]:check(Riding.compatible_characters(int(profile.pets[i].sprite)).is_empty(),"776/777 have no fabricated riding art")
	check(backend.handle({"type":"mount_pet","index":0}).ok and backend.session.snapshot().character_id=="100030","direct ride preserves appearance")
	backend.handle({"type":"mount_pet","index":-1})
	var before: Dictionary = backend.session.snapshot()
	var request := command(backend)
	for field in ["pet_id","character_id","expected_character","map_id","cell"]:
		var bad := request.duplicate(true)
		bad[field] = {"pet_id":"missing","character_id":"100030","expected_character":"100000","map_id":100,"cell":[81,90]}[field]
		check(not backend.handle(bad).ok and backend.session.snapshot()==before,"stale or incompatible %s leaves profile untouched" % field)
	for i in [2,3]:
		check(not backend.handle(command(backend,i)).ok and backend.session.snapshot()==before,"unsupported source pet rejected atomically")
	backend.session._profile.active_pet = 1
	check(not backend.handle(request).ok,"deployed pet remains prohibited")
	backend.session._profile.active_pet = -1
	backend.session._profile.pets[1].variable_ai = -10000
	check(not backend.handle(request).ok,"loyalty requirement remains enforced")
	backend.session._profile = before.duplicate(true)
	backend.battle_open = true
	check(not backend.handle(request).ok,"open battle prohibits new appearance transaction")
	backend.battle_open = false
	backend.session._pending = {"party":true}
	check(not backend.handle(request).ok,"pending party battle prohibits transaction")
	backend.session._pending = {}
	backend.automation.running = true
	check(not backend.handle(request).ok,"automatic activity prohibits transaction")
	backend.automation.running = false
	backend.save_path = "user://ride-appearance-missing-parent/save.json"
	var rev: int = backend.rev
	check(not backend.handle(request).ok and backend.session.snapshot()==before and backend.rev==rev,"save failure rolls back appearance and mount without publishing")
	backend.save_path = "user://ride-appearance-save.json"
	check(backend.handle(request).ok,"confirmed appearance transaction succeeds")
	var restored = preload("res://server/game_session.gd").new()
	check(restored.load_game(backend.save_path) and restored.snapshot().character_id=="100010" and int(restored.snapshot().ride_pet)==1,"appearance and mount persist together after reload")
	var presence: Dictionary = backend.presence_state()
	check(presence.look.c=="100010" and int(presence.look.ride)==int(before.pets[1].sprite),"LAN presence includes changed appearance and native mount")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(backend.save_path+suffix))
	backend.queue_free()
func connect_game(port: int, tag: String):
	var script = load("res://scripts/game.gd")
	script.server_url_override = "ws://127.0.0.1:%d" % port
	var game = load("res://scenes/main.tscn").instantiate()
	script.server_url_override = ""
	game.profile_persistence = false
	game.viewer_prefs_path = "user://ride-appearance-%s.cfg" % tag
	root.add_child(game)
	check(await Wait.until(self,func():return not game.data.is_empty() and game.link.online) and await Wait.settle(self,game),"remote game connects and settles")
	game.random_encounters = false
	return game
func screenshot(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
func click(button: Button) -> void:
	var point := button.get_global_transform_with_canvas()*(button.size/2)
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)

func pick_pet(game,index: int) -> Button:
	if not game.adventure_menu.visible:game.show_adventure_menu("pets")
	game.adventure_menu.selected_pet = index
	game.adventure_menu.rebuild()
	return game.adventure_menu.panel.get_node("PetMount")
func delayed_packs(game):
	var packs := DelayedPacks.new()
	packs.enabled = true
	packs.index = {"characters":{},"riding":{},"packs":{}}
	for choice in game.character_catalog.choices:
		var id := str(choice.id)
		var name := "character-"+id
		packs.index.characters[id] = name
		packs.index.packs[name] = {"bytes":1}
	for id in Riding.index().composites:
		var name := "riding-"+str(id)
		packs.index.riding[str(id)] = name
		packs.index.packs[name] = {"bytes":1}
	root.add_child(packs)
	return packs

func second_device_assets(a,b,backend) -> void:
	var original = b.asset_packs
	var fake = delayed_packs(b)
	b.asset_packs = fake
	fake._mounted["character-100030"] = true
	check(b.character_selection.shell==null,"second device never opened appearance chooser")
	var pet_id := str(a.session.snapshot().pets[1].pet_id)
	a.session.mount_pet_as(pet_id,"100010",{"expected_character":"100030","map_id":1000,"cell":[80,90]})
	await Wait.settle(self,a)
	check(await Wait.until(self,func():return b.session.snapshot().character_id=="100010" and fake._queued.has("character-100010") and fake._queued.has("riding-101006")),"second device requests both unseen base character and riding packs")
	check(b.player.character_id=="100030","missing base pack does not expose an unready appearance")
	a.session.mount_pet(-1)
	await Wait.settle(self,a)
	check(await Wait.until(self,func():return int(b.session.snapshot().ride_pet)==-1),"dismount arrives while second device art downloads")
	fake.complete(["riding-101006"])
	check(b.player.character_id=="100030" and b.player.mounted_character_id.is_empty(),"riding pack alone cannot restore stale mounted state")
	fake.complete(["character-100010"])
	check(await Wait.until(self,func():return b.player.character_id=="100010" and b.player.mounted_character_id.is_empty() and b.player.last_render_character=="100010" and b.player.sprite.texture!=null),"late base art draws latest dismounted character bitmap")
	# Start an older pair download again, then replace the appearance before
	# it finishes. Finishing it must request the new character, not apply old.
	a.session.set_character("100030")
	await Wait.settle(self,a)
	check(await Wait.until(self,func():return b.player.character_id=="100030"),"return to cached old base appearance")
	fake._mounted.erase("character-100010")
	fake._mounted.erase("riding-101006")
	fake._queued.clear()
	a.session.mount_pet_as(pet_id,"100010",{"expected_character":"100030","map_id":1000,"cell":[80,90]})
	await Wait.settle(self,a)
	check(await Wait.until(self,func():return fake._queued.has("character-100010") and fake._queued.has("riding-101006")),"second delayed appearance transaction requests both packs again")
	a.session.mount_pet(-1)
	a.session.set_character("100020")
	await Wait.settle(self,a)
	check(await Wait.until(self,func():return b.session.snapshot().character_id=="100020" and fake._queued.has("character-100020")),"newer appearance requests its own base pack")
	fake.complete(["character-100020"])
	check(await Wait.until(self,func():return b.player.character_id=="100020" and b.player.mounted_character_id.is_empty() and b.player.last_render_character=="100020" and b.player.sprite.texture!=null),"latest loaded pack and actual rendered character ID agree")
	fake.complete(["character-100010","riding-101006"])
	check(b.player.character_id=="100020" and b.player.mounted_character_id.is_empty() and b.player.last_render_character=="100020","late old pair does not overwrite already rendered newer appearance")
	# A world can disappear while callbacks wait; the independent download
	# shell may outlive it. Also exercise a missing player during a callback.
	var c = await connect_game(backend.get_meta("ride_test_port"),"asset-c")
	c.hide();c.ui_layer.hide()
	var orphan = delayed_packs(c)
	c.asset_packs = orphan
	c._character.refresh_riding()
	var actor = c.player
	c.player = null
	orphan.complete(["character-100020"])
	check(c.player==null,"download completion tolerates released player")
	c.player = actor
	orphan._mounted.clear()
	c._character.refresh_riding()
	c.link.close();c.music.stop();c.effect.stop();c.queue_free()
	await process_frame
	orphan.complete(orphan.index.packs.keys())
	check(not is_instance_valid(c),"download completion tolerates released world")
	orphan.queue_free()
	b.asset_packs = original
	fake.queue_free()
	a.session.set_character("100030")
	await Wait.settle(self,a)
	check(await Wait.until(self,func():return b.player.character_id=="100030" and a.player.character_id=="100030"),"native pack path still synchronizes both devices")

func download_lifecycle(a,b,backend) -> void:
	var original = a.asset_packs
	var fake = delayed_packs(a)
	a.asset_packs = fake
	var chooser = a.character_selection
	var pets: Array = a.session.snapshot().pets
	var before: Dictionary = backend.session.snapshot()
	chooser.open_for_mount(pets[1])
	var old_packs: Array = chooser.character_packs()
	check(not chooser.visible and fake._waiters.size()==1,"real AssetPacks holds chooser while download shell waits")
	chooser.close_menu()
	fake.complete(old_packs)
	check(not chooser.visible and backend.session.snapshot()==before,"late download after close never revives or mounts")
	fake._mounted.clear()
	chooser.open_for_mount(pets[1])
	old_packs = chooser.character_packs()
	chooser.open_for_mount(pets[0])
	var new_packs: Array = chooser.character_packs()
	fake.complete(old_packs)
	check(not chooser.visible and str(chooser.ride_pet.pet_id)==str(pets[0].pet_id),"old pet download cannot open or reuse replacement pet intent")
	fake.complete(new_packs)
	check(chooser.visible and str(chooser.ride_pet.pet_id)==str(pets[0].pet_id) and backend.session.snapshot()==before,"only replacement download opens replacement preview without mutation")
	chooser.close_menu()
	fake._mounted.clear()
	chooser.open_for_mount(pets[1])
	old_packs = chooser.character_packs()
	check(b.load_area_id(1002,Vector2i(11,15)),"other device requests original shop map during download")
	await Wait.settle(self,b)
	check(await Wait.until(self,func():return not chooser._loading),"map position event cancels pending chooser intent")
	fake.complete(old_packs)
	fake.complete(fake.index.packs.keys())
	check(await Wait.until(self,func():return int(a.data.map_id)==1002 and not a.area_transition_busy),"both clients arrive on changed map")
	check(not chooser.visible and int(backend.session.snapshot().ride_pet)==-1,"map change invalidates late download without mounting")
	fake._mounted.clear()
	var disposable = preload("res://scripts/character_selection.gd").new()
	disposable.configure(a)
	a.ui_layer.get_child(0).add_child(disposable)
	disposable.open_for_mount(pets[1])
	old_packs = disposable.character_packs()
	disposable.queue_free()
	await process_frame
	fake.complete(old_packs)
	check(not is_instance_valid(disposable),"late download safely ignores freed chooser")
	fake._mounted.clear()
	chooser.open_for_mount(pets[1])
	old_packs = chooser.character_packs()
	a.link.close()
	check(await Wait.until(self,func():return not a.link.online),"real socket disconnects during download")
	fake.complete(old_packs)
	check(not chooser.visible and int(backend.session.snapshot().ride_pet)==-1,"disconnect invalidates late download without mounting")
	a.asset_packs = original
	fake.queue_free()

func rejected_confirmations(a,b,backend) -> void:
	var chooser = a.character_selection
	for kind in ["appearance","position","save"]:
		pick_pet(a,1).pressed.emit()
		chooser._choose("100010")
		if kind=="appearance":
			b.session.set_character("100000")
			await Wait.settle(self,b)
			check(await Wait.until(self,func():return a.session.snapshot().character_id=="100000"),"other device changes appearance before confirmation")
		elif kind=="position":
			b.link.request({"type":"report_position","map_id":1000,"cell":[82,90]})
			await Wait.settle(self,b)
			check(await Wait.until(self,func():return a.cell==Vector2i(82,90)),"other device moves before confirmation")
		else:backend.save_path = "user://ride-appearance-missing-parent/save.json"
		var before: Dictionary = backend.session.snapshot()
		chooser._confirm_mount()
		check(chooser.visible and chooser._pending_confirm and chooser.confirm_button.disabled,"pending %s keeps chooser open and disables confirm" % kind)
		var sent: int = a.link.messages_out
		chooser._confirm_mount()
		check(a.link.messages_out==sent,"pending %s suppresses duplicate requests" % kind)
		check(await Wait.until(self,func():return not chooser._pending_confirm),"%s rejection callback arrives" % kind)
		check(chooser.visible and chooser.ride_selected=="100010" and not chooser._ride_error.is_empty() and backend.session.snapshot()==before,"%s rejection preserves selection, explains failure and keeps authority unchanged" % kind)
		if kind=="save":await screenshot("06-save-rejected")
		chooser.close_menu()
		backend.save_path = ""
		b.session.set_character("100030")
		b.link.request({"type":"report_position","map_id":1000,"cell":[80,90]})
		await Wait.settle(self,b)
		check(await Wait.until(self,func():return a.session.snapshot().character_id=="100030" and a.cell==Vector2i(80,90)),"reset context after rejection")
	# A sent operation may finish after dismissal. The receipt must not reopen
	# or touch the destroyed UI; the command itself still belongs to authority.
	var disposable = preload("res://scripts/character_selection.gd").new()
	disposable.configure(a)
	a.ui_layer.get_child(0).add_child(disposable)
	disposable.open_for_mount(a.session.snapshot().pets[1])
	disposable._choose("100010")
	disposable._confirm_mount()
	disposable.close_menu()
	disposable.free()
	check(await Wait.settle(self,a),"receipt after closed and freed chooser completes safely")
	b.session.mount_pet(-1)
	b.session.set_character("100030")
	await Wait.settle(self,b)
	check(await Wait.until(self,func():return a.session.snapshot().character_id=="100030" and int(a.session.snapshot().ride_pet)==-1),"reset after dismissed in-flight confirmation")

func remote_ui() -> void:
	var backend = fixture()
	var server = preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"test WebSocket server uses an ephemeral port")
	backend.set_meta("ride_test_port",server.port)
	var a = await connect_game(server.port,"a")
	var b = await connect_game(server.port,"b")
	b.hide()
	b.ui_layer.hide()
	check(a.backend==null and b.backend==null,"both remote clients have no backend")
	check(await Wait.until(self,func():return not a.area_transition_busy and not b.area_transition_busy),"both clients finish loading")
	await second_device_assets(a,b,backend)
	var direct := pick_pet(a,0)
	check(not direct.disabled,"current-compatible pet remains directly rideable")
	direct.pressed.emit()
	check(await Wait.until(self,func():return int(a.session.snapshot().ride_pet)==0 and int(b.session.snapshot().ride_pet)==0),"direct ride synchronizes both remote devices")
	check(not a.character_selection.visible,"direct ride skips appearance chooser")
	await Wait.settle(self,a)
	pick_pet(a,0).pressed.emit()
	check(await Wait.until(self,func():return int(a.session.snapshot().ride_pet)==-1),"dismount round trip")
	var button := pick_pet(a,1)
	check(not button.disabled,"gold tiger button enabled despite incompatible current look")
	var before: Dictionary = backend.session.snapshot()
	button.pressed.emit()
	var chooser = a.character_selection
	check(chooser.visible and a.paused_input,"pet button opens existing chooser and blocks movement")
	var displayed: Array[String] = []
	for id in chooser.buttons:
		if chooser.buttons[id].visible:displayed.append(id)
	check(displayed.size()==Riding.compatible_characters(int(before.pets[1].sprite)).size() and not "100030" in displayed,"only compatible appearances are shown")
	var actor = chooser.buttons["100010"].get_child(0)
	check(await Wait.until(self,func():return actor.sprite.texture!=null),"preview loads original composite pixels")
	var frame: int = actor.current_image
	check(await Wait.until(self,func():return actor.current_image!=frame),"preview advances original walking bitmap")
	await screenshot("01-compatible-choices")
	click(chooser.buttons["100010"])
	check(chooser.confirmation.text.contains("换成") and chooser.confirmation.text.contains(str(before.pets[1].name)),"selection asks explicit appearance-and-pet confirmation")
	check(backend.session.snapshot()==before,"preview and selection never mutate authority")
	await screenshot("02-confirmation")
	click(chooser.find_child("CancelMountAppearance",true,false))
	await Wait.settle(self,a)
	check(backend.session.snapshot()==before and not chooser.visible,"cancel leaves appearance and mount unchanged")
	pick_pet(a,1).pressed.emit()
	click(chooser.buttons["100010"])
	click(chooser.confirm_button)
	check(await Wait.until(self,func():return a.session.snapshot().character_id=="100010" and b.session.snapshot().character_id=="100010" and int(b.session.snapshot().ride_pet)==1),"confirm changes appearance and mounts on both remote devices")
	check(await Wait.until(self,func():return a.player.character_id=="100010" and b.player.character_id=="100010" and a.player.mounted_character_id=="101006" and b.player.mounted_character_id=="101006"),"both visible map actors synchronize native riding composite")
	a.close_adventure_menu()
	await screenshot("03-mounted-map")
	await Wait.settle(self,a)
	pick_pet(a,1).pressed.emit()
	check(await Wait.until(self,func():return int(a.session.snapshot().ride_pet)==-1),"dismount before unsupported pet check")
	for i in [2,3]:
		var disabled := pick_pet(a,i)
		check(disabled.disabled and disabled.tooltip_text.contains("任何造型"),"no-art pet is disabled with all-appearance explanation")
	await screenshot("04-no-art")
	a.session.set_character("100030")
	await Wait.settle(self,a)
	await rejected_confirmations(a,b,backend)
	# Exercise the chooser at a genuinely narrow layout, with real rendering.
	a.session.set_character("100030")
	await Wait.settle(self,a)
	check(await Wait.until(self,func():return a.session.snapshot().character_id=="100030"),"restore incompatible appearance for mobile chooser")
	pick_pet(a,1).pressed.emit()
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(390,844)
	await process_frame
	chooser.relayout()
	await process_frame
	click(chooser.buttons["100010"])
	await process_frame
	await process_frame
	check(chooser.grid.columns==2 and Rect2(Vector2.ZERO,chooser.size).encloses(chooser.shell.get_rect()),"390px chooser keeps two columns and confirmation inside screen")
	chooser._turn_preview(1)
	check(actor.facing==2 and actor.mounted_character_id=="101006","mobile direction control preserves original composite")
	await screenshot("05-mobile-confirmation")
	chooser.close_menu()
	await download_lifecycle(a,b,backend)
	for game in [a,b]:
		game.link.close();game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	server.stop();server.queue_free();backend.queue_free()
	await process_frame
func run() -> void:
	authority()
	await remote_ui()
	print("RIDE APPEARANCE: %d failures" % failures)
	quit(1 if failures else 0)

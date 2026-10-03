extends SceneTree
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
var visual := false
func _initialize():call_deferred("run")
func check(ok: bool, note: String):
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1
func click(control: Control):
	check(await Wait.until(self,func():return control.is_visible_in_tree() and control.size.x>0),"real mouse target laid out")
	var point: Vector2 = control.get_global_transform_with_canvas()*(control.size/2)
	var motion := InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;root.push_input(event,true)
		await process_frame
func shot(name: String):
	if not visual:return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/stationary-production-render/"+name+".png")
func layout(menu):
	await process_frame
	await process_frame
	print("LAYOUT root=",root.size," viewport=",root.get_visible_rect()," menu=",menu.get_global_rect())
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(menu.get_global_rect()),"helper fits viewport")
	var scroll = menu.find_child("HelperScroll",true,false)
	check(scroll.get_h_scroll_bar().max_value<=scroll.size.x+1,"no horizontal overflow")
	for name in ["HelperNoRandomEncounters","HelperStationaryEncounters"]:
		var control = menu.find_child(name,true,false)
		check(control.size.y>=44,"touch target "+name)
func request(game, command: Dictionary) -> Dictionary:
	var result:Dictionary={}
	game.link.request(command,func(reply):result.merge(reply))
	check(await Wait.until(self,func():return not result.is_empty()),"remote request answered: "+str(command.type))
	return result
func fixture_seed(b,point:Vector2i,minimum:int=1)->int:
	var catalog=preload("res://server/encounter_catalog.gd").new(b.encounter_catalog.data)
	var rng=RandomNumberGenerator.new()
	for seed_value in range(10000):
		rng.seed=seed_value;catalog.pressure=0
		for step in range(1,41):
			if not catalog.step(200,point,rng):continue
			var troop:Dictionary=catalog.roll(200,point,rng,[2478])
			if step>=minimum and int(troop.get("group_id",-1))==414 and troop.enemies.any(func(e):return 2468 in e.generated_drops):
				print("FIXTURE seed=",seed_value," natural_steps=",step," source_group=414 source_drop=2468")
				return seed_value
			break
	check(false,"source RNG fixture found")
	return 0
func win(game,b,tag:String):
	check(await Wait.until(self,func():return game.battle_view.visible and not game.battle_view.is_animating()),"real battle UI ready "+tag)
	await shot(tag+"-battle")
	for turn in range(30):
		if not b.battle.snapshot().active:break
		var state:Dictionary=b.battle.snapshot()
		var target:int=0
		for j in range(state.enemies.size()):
			if int(state.enemies[j].hp)>0:target=j;break
		await request(game,{"type":"battle_command","action":"attack","target":target})
	check(b.battle.snapshot().outcome=="win","actual resolver victory "+tag)
	check(await Wait.until(self,func():return game.battle_view.return_button.is_visible_in_tree() and not game.battle_view.is_animating()),"settled result UI "+tag)
	await shot(tag+"-result")
	var disk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(b.save_path))
	print("SAVED ",tag," wood=",b.session.snapshot().original_items.count(2468)," file=",b.save_path)
	check(disk.get("original_items",[]).filter(func(item):return int(item)==2468).size()==b.session.snapshot().original_items.count(2468) and b.session.last_error.is_empty(),"victory wood count saved to isolated real file "+tag)
	await click(game.battle_view.return_button)
	check(await Wait.until(self,func():return not b.battle_open and not game.battle_view.visible),"actual continue exploration click "+tag)
func run():
	root.unfocusable=true;root.position=Vector2i(-10000,-10000);root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	if visual:DirAccess.make_dir_recursive_absolute("/private/tmp/stationary-production-render")
	var b=TraceBackend.new();root.add_child(b)
	# Completed axe/water steps and an issued license: exact harvest-stage profile.
	var quests=preload("res://server/original_quests.gd")
	quests.set_flag(b.session._profile,"ended",18,true);quests.set_flag(b.session._profile,"ended",19,true)
	b.session._profile.original_items=[2478]
	b.session._profile.player.level=15
	check(b.session.gm_set_base_stat(-1,"strength",10000),"isolated legal GM combat-stat fixture")
	b.save_path="user://stationary-production-save.json"
	b.handle({"type":"report_position","map_id":200,"cell":[644,345]})
	b.encounter_rng.seed=918
	var server=WsServer.new(b,0,"127.0.0.1");root.add_child(server)
	check(server.start()==OK,"isolated port0 server")
	var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
	var game=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	game.profile_persistence=false;game.viewer_prefs_path="user://stationary-production.cfg";root.add_child(game)
	check(await Wait.until(self,func():return game.link.online and not game.data.is_empty() and not game.area_transition_busy) and await Wait.settle(self,game),"remote ready")
	check(game.backend==null,"real remote viewer has no backend")
	var old_area:Dictionary=b.encounter_catalog.area_at(200,Vector2i(644,345))
	check(int(old_area.id)==87 and int(old_area.event_now)==-1 and int(old_area.event_end)==-1,"reported coordinate selects ordinary area87, not event-conditioned area")
	check(not old_area.groups.any(func(g):return int(g.id)==414),"reported coordinate cannot roll tree group")
	var menu=game.helper_menu
	menu.open_menu();await Wait.settle(self,game)
	await click(menu.find_child("HelperStationaryEncounters",true,false))
	check(await Wait.until(self,func():return b.battle_open,45),"unmodified production clock encounters normally at old coordinate")
	check(b.stationary.running,"negative WS connection identity lease remains alive")
	await win(game,b,"old-coordinate")
	# Fetch the authoritative helper target, then travel through the real session RPC.
	var harvest:Dictionary=b.quest_helper.resolve_step(b,22,"wood:harvest")
	var point:=Vector2i(int(harvest.cell[0]),int(harvest.cell[1]))
	print("HARVEST target=",point," selected_area=",b.encounter_catalog.area_at(200,point).id)
	check(int(b.encounter_catalog.area_at(200,point).id)==88,"helper chooses actual source tree area")
	await request(game,{"type":"quest_visit","quest_id":22,"step_id":"wood:harvest","mode":"near"})
	check(await Wait.until(self,func():return game.cell==point and not game.area_transition_busy),"remote helper lands at actual tree area")
	check(not b.stationary.running,"real helper travel stops stationary")
	# Same production roll used by both real walking and stationary encounters.
	var rng=RandomNumberGenerator.new();rng.seed=1
	var excluded:=true
	for i in range(40):excluded=excluded and int(b.encounter_catalog.roll(200,point,rng,[]).get("group_id",-1))!=414
	check(excluded,"no bag license excludes tree group across 40 source rolls")
	for dimensions in [Vector2i(390,844),Vector2i(1280,720)]:
		root.size=dimensions
		var tag:="%dx%d"%[dimensions.x,dimensions.y]
		game.quest_helper_menu.open_menu();await Wait.settle(self,game)
		await click(game.quest_helper_menu.find_child("QuestHelper_22",true,false))
		await shot(tag+"-harvest")
		await click(game.quest_helper_menu.find_child("QuestHelperClose",true,false))
		menu.open_menu();await Wait.settle(self,game);await layout(menu);await shot(tag+"-helper")
		b.encounter_rng.seed=fixture_seed(b,point,12);b.encounter_catalog.pressure=0
		var before:int=b.session.snapshot().original_items.count(2468)
		var start:int=Time.get_ticks_msec()
		await click(menu.find_child("HelperStationaryEncounters",true,false))
		await request(game,{"type":"report_position","map_id":200,"cell":[point.x,point.y]})
		await request(game,{"type":"set_automation_settings","settings":game.automation_settings()})
		check(b.stationary.running,"unchanged position and saved window settings preserve run")
		check(await Wait.until(self,func():return b.battle_open,60),"natural stationary tree encounter "+tag)
		print("NATURAL ms=",Time.get_ticks_msec()-start," lease=",b.stationary.lease," owner=",b.stationary.connection," commands=",b.requests)
		check(b.battle.snapshot().enemies.any(func(e):return int(e.get("source_enemy_id",-1))==563),"actual source tree monster "+tag)
		await win(game,b,tag)
		check(b.session.snapshot().original_items.count(2468)>before,"actual victory increases wood count "+tag)
		check(b.stationary.running,"saved win continues stationary "+tag)
		check(await Wait.until(self,func():return b.stationary.battle_id.is_empty()),"next natural interval begins")
		b.encounter_rng.seed=fixture_seed(b,point);b.encounter_catalog.pressure=0
		check(await Wait.until(self,func():return b.battle_open,60),"next battle without re-enabling "+tag)
		await win(game,b,tag+"-next")
		game.settings_menu.open_menu();await Wait.settle(self,game)
		check(await Wait.until(self,func():return not b.stationary.running),"real settings window stops stationary")
		game.settings_menu.close_menu()
	# Keyboard input drives ordinary GameScene movement; no direct field_step/tick.
	b.encounter_rng.seed=fixture_seed(b,point);b.encounter_catalog.pressure=0
	var before:int=b.session.snapshot().original_items.count(2468)
	for step in range(80):
		if b.battle_open:break
		var event:=InputEventAction.new();event.action="east" if step%2==0 else "west";event.pressed=true
		root.push_input(event,true)
		check(await Wait.until(self,func():return game.moving),"actual keyboard starts walking")
		event=InputEventAction.new();event.action="east" if step%2==0 else "west";event.pressed=false;root.push_input(event,true)
		check(await Wait.until(self,func():return not game.moving),"ordinary walking arrives")
		await Wait.settle(self,game)
	check(b.battle_open,"ordinary walking production pressure opens battle")
	check(b.battle.snapshot().enemies.any(func(e):return int(e.get("source_enemy_id",-1))==563),"ordinary walking uses same tree group")
	await win(game,b,"walking")
	check(b.session.snapshot().original_items.count(2468)>before,"ordinary walking actual victory increases wood count")
	menu.open_menu();await Wait.settle(self,game)
	await click(menu.find_child("HelperStationaryEncounters",true,false));await Wait.settle(self,game)
	var move:=InputEventAction.new();move.action="west";move.pressed=true;root.push_input(move,true)
	check(await Wait.until(self,func():return game.moving),"real manual movement begins while stationary")
	move=InputEventAction.new();move.action="west";move.pressed=false;root.push_input(move,true)
	check(await Wait.until(self,func():return not game.moving and not b.stationary.running),"real movement stops stationary")
	menu.open_menu();await Wait.settle(self,game)
	await click(menu.find_child("HelperStationaryEncounters",true,false));await Wait.settle(self,game)
	game.link.close()
	check(await Wait.until(self,func():return not b.stationary.running,15),"natural lease expires after disconnect")
	game.music.stop();game.effect.stop();game.queue_free();server.stop();server.queue_free();b.queue_free()
	await process_frame
	print("STATIONARY PRODUCTION: %d failures"%failures)
	quit(1 if failures else 0)
class TraceBackend extends Backend:
	var requests:Dictionary={}
	func handle(command: Dictionary) -> Dictionary:
		var reply=super.handle(command)
		var type:String=str(command.get("type",""));requests[type]=int(requests.get(type,0))+1
		print("REQUEST ms=",Time.get_ticks_msec()," ",command," ok=",reply.get("ok")," running=",stationary.running," reason=",stationary.reason)
		return reply

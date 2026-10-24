extends SceneTree
const Clock=preload("res://scripts/clock.gd")
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
	check(await Wait.until(self,func():return control.is_visible_in_tree() and control.size.x>0 and (not control is BaseButton or not control.disabled)),"real mouse target laid out")
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
	root.get_texture().get_image().save_png("/private/tmp/tmux-agents/stationary-manual-resume/render/"+name+".png")
func request(game, command: Dictionary) -> Dictionary:
	var result:Dictionary={}
	game.link.request(command,func(reply):result.merge(reply))
	check(await Wait.until(self,func():return not result.is_empty()),"remote request answered: "+str(command.type))
	return result
func win(game,b,tag:String):
	check(await Wait.until(self,func():return game.battle_view.visible and not game.battle_view.is_animating()),"real battle UI ready "+tag)
	for turn in range(30):
		if not b.battle.snapshot().active:break
		var state:Dictionary=b.battle.snapshot()
		var target:int=0
		for j in range(state.enemies.size()):
			if int(state.enemies[j].hp)>0:target=j;break
		var view=game.battle_view
		print("MANUAL_WAIT server_turn=",state.turn," viewer_turn=",view.state.get("turn")," animating=",view.is_animating())
		# Authority can advance before its WebSocket battle_turn reaches the
		# viewer. Waiting only on the old view's idle animation races that
		# packet: it replaces the selection between Attack and target clicks.
		check(await Wait.until(self,func():return str(view.state.get("battle_id",""))==str(state.battle_id) and int(view.state.get("turn",-1))==int(state.turn) and not view.is_animating() and view.command_phase=="player" and view.commands[0].is_visible_in_tree() and not view.commands[0].disabled),"matching client turn and enabled manual commands ready")
		print("MANUAL_READY battle=",view.state.get("battle_id")," server_turn=",state.turn," viewer_turn=",view.state.get("turn")," animating=",view.is_animating()," attack_disabled=",view.commands[0].disabled)
		await click(view.commands[0])
		check(await Wait.until(self,func():return view.selected_action=="attack"),"real attack selection accepted")
		var actor_index:int=1 if target==0 else target+2
		await click(view.target_buttons[actor_index])
		if view.command_phase=="pet":
			check(await Wait.until(self,func():return not view.is_animating() and view.elapsed>=view.feedback_until),"manual pet turn ready")
			await click(view.target_buttons[actor_index])
		check(await Wait.until(self,func():return not b.battle.snapshot().active or int(b.battle.snapshot().turn)>int(state.turn)),"manual input resolved")

	check(b.battle.snapshot().outcome=="win","actual resolver victory "+tag)
	if tag=="old-coordinate" and "--level-up" in OS.get_cmdline_user_args():
		check(b.battle_state.get("result_summary",[]).any(func(row):return bool(row.get("level_up",false))),"real settlement has level-up result")
	check(await Wait.until(self,func():return game.battle_view.return_button.is_visible_in_tree() and not game.battle_view.is_animating()),"settled result UI "+tag)
	var disk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(b.save_path))
	print("SAVED ",tag," wood=",b.session.snapshot().original_items.count(2468)," file=",b.save_path)
	check(disk.get("original_items",[]).filter(func(item):return int(item)==2468).size()==b.session.snapshot().original_items.count(2468) and b.session.last_error.is_empty(),"victory wood count saved to isolated real file "+tag)
	if "--residual" in OS.get_cmdline_user_args():
		# Controlled UI-only stale minimized state; no backend automation flags.
		game.training_helper.minimized=true
		check(not b.automation.running and not b.automation.hunt_running and not b.automation.flow_active(),"idle bar fixture has no competing authority")
	await click(game.battle_view.return_button)
	check(await Wait.until(self,func():return not b.battle_open and not game.battle_view.visible),"actual continue exploration click "+tag)
func run():
	root.unfocusable=true;root.position=Vector2i(-10000,-10000);root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	if visual:DirAccess.make_dir_recursive_absolute("/private/tmp/tmux-agents/stationary-manual-resume/render")
	var b=TraceBackend.new();b.account_name="stationary-fixture";root.add_child(b)
	# Completed axe/water steps and an issued license: exact harvest-stage profile.
	var quests=preload("res://server/original_quests.gd")
	quests.set_flag(b.session._profile,"ended",18,true);quests.set_flag(b.session._profile,"ended",19,true)
	b.session._profile.original_items=[2478]
	b.session._profile.player.level=15
	if "--level-up" in OS.get_cmdline_user_args():b.session._profile.player.xp=449
	check(b.session.gm_set_base_stat(-1,"strength",10000),"isolated legal GM combat-stat fixture")
	b.save_path="user://stationary-manual-save.json"
	b.handle({"type":"report_position","map_id":200,"cell":[644,345]})
	b.encounter_rng.seed=918
	var server=WsServer.new(b,0,"127.0.0.1");root.add_child(server)
	check(server.start()==OK,"isolated port0 server")
	var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
	var game=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	game.profile_persistence=false;game.viewer_prefs_path="user://stationary-manual.cfg";root.add_child(game)
	check(await Wait.until(self,func():return game.link.online and not game.data.is_empty() and not game.area_transition_busy) and await Wait.settle(self,game),"remote ready")
	check(game.backend==null,"real remote viewer has no backend")
	var old_area:Dictionary=b.encounter_catalog.area_at(200,Vector2i(644,345))
	check(int(old_area.id)==87 and int(old_area.event_now)==-1 and int(old_area.event_end)==-1,"reported coordinate selects ordinary area87, not event-conditioned area")
	check(not old_area.groups.any(func(g):return int(g.id)==414),"reported coordinate cannot roll tree group")
	if "--conflict-only" in OS.get_cmdline_user_args():
		await conflict_probe(game,b)
		game.queue_free();server.stop();server.queue_free();b.queue_free()
		await process_frame
		print("CONFLICT PROBE: %d failures"%failures)
		quit(1 if failures else 0)
		return
	var menu=game.helper_menu
	menu.open_menu();await Wait.settle(self,game)
	await click(menu.find_child("HelperStationaryEncounters",true,false))
	# Only the presentation download completion is gated; the real backend
	# clock still opens and owns the battle through the production path.
	var original_packs=game.asset_packs
	var gate=DelayedBattlePacks.new();gate.enabled=true;game.add_child(gate);game.asset_packs=gate
	check(await Wait.until(self,func():return b.battle_open,45),"unmodified production clock encounters normally at old coordinate")
	check(await Wait.until(self,func():return gate.completion.is_valid()),"production battle presentation awaits art")
	await Wait.settle(self,game)
	check(game.state.battle_open and game.paused_input and not game.battle_view.visible,"real authority opened battle before its view is ready")
	check(b.stationary.running and not menu.stationary_ui.blocked(game,menu),"battle art loading preserves stationary lease")
	game.asset_packs=original_packs
	gate.completion.call(true);gate.queue_free()
	check(b.stationary.running,"negative WS connection identity lease remains alive")
	check(await Wait.until(self,func():return int(game.state.derived.get("stationary",{}).get("encounters",0))==1),"first encounter count published by server")
	await win(game,b,"old-coordinate")
	await Wait.settle(self,game)
	check(b.stationary.running,"first manual result preserves stationary")
	for i in range(2):
		check(await Wait.until(self,func():return b.battle_open or not b.stationary.running,60),"next encounter or stop observed")
		print("AFTER_MANUAL running=",b.stationary.running," reason=",b.stationary.reason," battle_id=",b.stationary.battle_id," saved_win=",b.stationary.saved_win," paused_input=",game.paused_input," blocked=",menu.stationary_ui.blocked(game,menu))
		if not b.stationary.running:break
		await win(game,b,"manual-%d"%i)
	await chip_checks(game,b)
	if "--residual" in OS.get_cmdline_user_args():
		game.helper_menu.open_menu();await Wait.settle(self,game)
		await click(game.helper_menu.find_child("HelperStationaryEncounters",true,false))
		check(await Wait.until(self,func():return b.stationary.running),"idle minimized bar allows explicit restart")
		game.settings_menu.open_menu();await Wait.settle(self,game)
		check(await Wait.until(self,func():return not b.stationary.running),"real modal still stops with idle bar present")
		game.settings_menu.close_menu()
	game.music.stop();game.effect.stop();game.queue_free();server.stop();server.queue_free();b.queue_free()
	await process_frame
	print("STATIONARY MANUAL RESUME: %d failures"%failures)
	quit(1 if failures else 0)
func chip_checks(game,b):
	var chip=game.ui_root.find_child("StationaryEncounterChip",true,false)
	check(await Wait.until(self,func():return chip.visible and chip.label.text.contains("3 次")),"chip counts three authoritative encounters")
	# Presentation-only idle bars: no automation flags, commands or authority.
	var automation_chip=game.training_helper._chip()
	automation_chip.present("自动练级已停止","仅保留浮条布局")
	automation_chip.pop_up()
	var quest_chip=game.ui_root.find_child("QuestAutoChip",true,false)
	quest_chip.set_process(false);quest_chip.restore_button.text="自动任务已停止";quest_chip.show()
	for dimensions in [Vector2i(390,844),Vector2i(1280,720)]:
		root.size=dimensions
		quest_chip.size=Vector2(minf(330,dimensions.x-24),70)
		quest_chip.position=Vector2(dimensions.x-quest_chip.size.x-12,dimensions.y-190)
		check(await Wait.until(self,func():return Rect2(Vector2.ZERO,Vector2(root.size)).encloses(chip.get_global_rect()) and not chip.get_global_rect().intersects(automation_chip.get_global_rect()) and not chip.get_global_rect().intersects(quest_chip.get_global_rect())),"stationary chip fits and avoids both bars "+str(dimensions))
		await shot("%dx%d-running-chip"%[dimensions.x,dimensions.y])
	await click(chip.stop_button)
	check(await Wait.until(self,func():return not b.stationary.running and not chip.stop_button.visible and chip.label.text.contains("已关闭")),"real chip stop closes authority and shows true reason")
	await shot("1280-stopped-chip")
	check(int(game.state.derived.stationary.encounters)==b.stationary.encounters and b.stationary.encounters>=3,"stopped count retained on server")
	check(await Wait.until(self,func():return not chip.visible),"stop notice expires by presentation clock")
	automation_chip.hide();quest_chip.hide();quest_chip.set_process(true)
	# Explicit rejection through the UI callback (a start rejected after input).
	game.helper_menu.open_menu();await Wait.settle(self,game)
	b.stationary_party_member=func():return true
	game.helper_menu.stationary_ui.toggle(game,game.helper_menu,true)
	check(await Wait.until(self,func():return chip.visible and chip.label.text.contains("组队")),"server rejection also appears in chip")
	await shot("1280-rejected-chip")
	b.stationary_party_member=Callable()
	game.helper_menu.close_menu()

func conflict_probe(game,b):
	await request(game,{"type":"report_position","map_id":100,"cell":[637,493]})
	check(await Wait.until(self,func():return int(game.data.map_id)==100 and not game.area_transition_busy),"conflict fixture map loaded")
	await request(game,{"type":"set_automation_settings","settings":{"capture":{"capture_hp":100}}})
	for kind in ["hunt","find_pet"]:
		var reply=await request(game,{"type":"auto_start","kind":kind,"filter":{"rate":1,"total":8,"offsets":[2,2,2,2]},"settings":{"capture_hp":100}})
		check(reply.get("ok",false) and b.automation.hunt_running,"real background start accepted "+kind)
		game.pet_hunt_menu.minimize()
		game.helper_menu.open_menu();await Wait.settle(self,game)
		check(game.helper_menu.find_child("HelperStationaryEncounters",true,false).disabled,"actual background activity disables stationary "+kind)
		check(game.helper_menu.find_child("HelperEncounterNote",true,false).text.contains("请先停止"),"visible conflict action guidance "+kind)
		var rejected=await request(game,{"type":"stationary_encounters","enabled":true})
		check(not rejected.get("ok",true) and str(rejected.get("reason","")).contains("请先停止"),"server enforces conflict "+kind)
		await shot("conflict-"+kind)
		await request(game,{"type":"auto","name":"stop_flow" if kind=="find_pet" else "stop_hunt","now":true})
		game.helper_menu.close_menu()
	check(not b.stationary.running,"rejected stationary never starts or counts encounters")

class TraceBackend extends Backend:
	var requests:Dictionary={}
	func handle(command: Dictionary) -> Dictionary:
		var reply=super.handle(command)
		var type:String=str(command.get("type",""));requests[type]=int(requests.get(type,0))+1
		print("REQUEST ms=",Clock.ticks_msec()," ",command," ok=",reply.get("ok")," running=",stationary.running," reason=",stationary.reason," battle_id=",stationary.battle_id," saved_win=",stationary.saved_win," active=",battle.snapshot().get("active",false))
		return reply

class DelayedBattlePacks extends "res://scripts/asset_packs.gd":
	var completion: Callable
	func is_ready(_packs: Array) -> bool:return false
	func ensure(_packs: Array, done: Callable = Callable(), _label: String = "") -> void:
		completion=done

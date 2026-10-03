extends SceneTree
## Real catalog/backend/session/game; only the download completion is gated.
const Wait=preload("res://tests/support/wait.gd")
class PackGate extends "res://scripts/asset_packs.gd":
	var waiting: Callable
	var held:=true
	func ensure(packs: Array, done: Callable=Callable(), label: String="") -> void:
		if held:waiting=done
		else:super.ensure(packs,done,label)
	func finish(ok: bool) -> void:
		held=false
		var callback:=waiting
		waiting=Callable()
		if callback.is_valid():callback.call(ok)
var failures:=0
var world: Node
func _initialize() -> void:call_deferred("run")
func check(value: bool, message: String) -> bool:
	if not value:
		failures+=1
		push_error(message)
		quit(1)
	return value
func ready(condition: Callable, message: String) -> bool:
	return check(await Wait.until(self,condition),message)
func click(button: Control) -> bool:
	if not check(is_instance_valid(button),"Click target exists"):return false
	if not await ready(func():return button.is_visible_in_tree() and button.size.x>0 and button.size.y>0,"Button layout ready"):return false
	var ancestor=button.get_parent()
	var scroll: ScrollContainer
	while is_instance_valid(ancestor):
		if ancestor is ScrollContainer:scroll=ancestor;break
		ancestor=ancestor.get_parent()
	if is_instance_valid(scroll):scroll.ensure_control_visible(button)
	var point: Vector2=button.get_global_transform_with_canvas()*(button.size/2)
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	motion.global_position=point
	root.push_input(motion,true)
	if not await ready(func():
		if is_instance_valid(scroll):scroll.ensure_control_visible(button)
		point=button.get_global_transform_with_canvas()*(button.size/2)
		motion.position=point
		root.push_input(motion,true)
		return root.gui_get_hovered_control()==button,"Mouse hover reaches intended button"):return false
	point=button.get_global_transform_with_canvas()*(button.size/2)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.position=point
		event.global_position=point
		root.push_input(event,true)
	return true
func visit_button(id: String, mode: String, job:int=11) -> Button:
	world.quest_helper_menu.selected_steps[job]=id
	world.quest_helper_menu.select_quest(job)
	return world.quest_helper_menu.find_child(("QuestVisit_%s_%s_%s" % [job,id,mode]).validate_node_name(),true,false)
func choose(id: String) -> bool:
	var dialogue=world.world_travel.quest_dialogue
	if not await ready(func():return dialogue.active and not dialogue.busy,"Original dialogue reply arrives"):return false
	# Choices are parented to the original overlay, not the controller.
	var button=world.world_travel.overlay.find_child("QuestChoice_"+id,true,false)
	if not await click(button):return false
	return check(await Wait.settle(self,world),"Original choice settles")
func run() -> void:
	var backend=preload("res://server/backend.gd").new()
	backend.quest_catalog.enabled_events=[1,2]
	root.add_child(backend)
	var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
	root.add_child(server)
	if not check(server.start()==OK,"Real ephemeral server starts"):return
	var script=load("res://scripts/game.gd")
	script.server_url_override="ws://127.0.0.1:%d" % server.port
	world=load("res://scenes/main.tscn").instantiate()
	script.server_url_override=""
	world.profile_persistence=false
	world.viewer_prefs_path="user://quest-helper-ui.cfg"
	var catalog=preload("res://scripts/quest_catalog.gd").new()
	catalog.enabled_events=[1,2]
	world.world_catalog.set_quest_catalog(catalog)
	root.add_child(world)
	if not await ready(func():return not world.data.is_empty() and world.link.online,"Remote startup connects"):return
	if not check(await Wait.settle(self,world),"Remote startup settles"):return
	if not check(world.backend==null,"Remote helper has no backend"):return
	world.helper_menu.open_menu()
	if not await click(world.helper_menu.find_child("HelperQuest",true,false)):return
	if not check(world.quest_helper_menu.visible,"Viewport click opens task helper"):return
	if not check(world.quest_helper_menu.find_child("QuestHelper_11",true,false).text.ends_with("未开始"),"Not-started quest remains visible"):return
	var giver: Dictionary=catalog.npcs.filter(func(npc):return int(npc.map_id)==1000 and str(npc.id).begins_with("sainasu/event/event02_"))[0]
	var receiver: Dictionary=catalog.npcs.filter(func(npc):return int(npc.map_id)==2000 and str(npc.id).begins_with("sainasu/event/event02_"))[0]
	var original_packs=world.asset_packs
	var gate:=PackGate.new()
	root.add_child(gate)
	world.asset_packs=gate
	var before: Dictionary=backend.automation.status().position
	if not await click(visit_button("shell:request","near")):return
	if not check(gate.waiting.is_valid() and world.quest_helper_travel.phase=="download" and backend.automation.status().position==before,"Download-first prevents server visit before completion"):return
	gate.finish(true)
	if not await ready(func():return not world.quest_helper_travel.active,"Authoritative visit completes"):return
	if not check(await Wait.settle(self,world),"Visit position settles"):return
	var npc_cell:=Vector2i(giver.cell[0],giver.cell[1])
	if not check(world.cell!=npc_cell and world.cell.distance_to(npc_cell)==1,"Server lands on safe NPC neighbour"):return
	world.asset_packs=original_packs
	world.world_travel.quest_dialogue.open(str(giver.id))
	if not await choose("yes"):return
	if not await choose("ok"):return
	if not await ready(func():return not world.world_travel.quest_dialogue.active,"REQUEST closes"):return
	world.quest_helper_menu.open_menu()
	if not check(world.quest_helper_menu.find_child("QuestHelper_11",true,false).text.ends_with("进行中"),"Helper reads current server progress"):return
	if not await click(visit_button("shell:exchange","arrival")):return
	if not await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Arrival navigation approaches current-map NPC and opens original dialogue"):return
	if not await choose("yes"):return
	if not check(world.session.snapshot().original_items==[2415],"YES leaves reward exchange pending until OK"):return
	if not await choose("ok"):return
	if not await ready(func():return not world.world_travel.quest_dialogue.active,"ACCEPT closes"):return
	if not check(world.session.snapshot().original_items==[2414],"OK grants original shell"):return
	world.quest_helper_menu.open_menu()
	if not check(world.quest_helper_menu.find_child("QuestHelper_11",true,false).text.ends_with("已完成"),"Completed quest remains visible"):return
	# New herb quest uses the same remote-only real viewport controls.
	if not await click(visit_button("herb:request","near",30)):return
	if not await ready(func():return not world.quest_helper_travel.active,"Herb safe teleport completes"):return
	if not check(await Wait.settle(self,world),"Herb position settles"):return
	if not check(int(world.data.map_id)==3110 and world.cell.distance_to(Vector2i(16,15))==1,"Herb teleport lands beside girl on downloaded map"):return
	world.world_travel.quest_dialogue.open("jaruga/event/event01_1")
	if not await choose("yes"):return
	if not await choose("ok"):return
	world.quest_helper_menu.open_menu()
	if not await click(visit_button("herb:medicine","arrival",30)):return
	if not await ready(func():return not world.quest_helper_travel.active,"Mountain helper stops at public entrance"):return
	if not check(int(world.data.map_id)==200 and not world.world_travel.quest_dialogue.active,"Arrival mode cannot teleport into cave or approach an unrelated outdoor cell"):return
	if not check(await Wait.settle(self,world),"Public entrance settles before route fixture"):return
	backend.session._profile.no_random_encounters=true
	var doctor:Dictionary=backend.original_quests.npc_by_id("jaruga/event/event01_2")
	if not check(preload("res://tests/support/legacy_cave_route.gd").approach(backend,doctor).ok,"Fixture walks all five original floors through real authority"):return
	var reached:Vector2i=backend.automation.position_cell
	backend._emit({"type":"position","map_id":20105,"cell":[reached.x,reached.y],"client":"route_fixture"})
	if not await ready(func():return int(world.data.map_id)==20105 and not world.area_transition_busy,"Remote renders legitimate route endpoint"):return
	if not check(await Wait.settle(self,world),"Original route endpoint settles"):return
	world.quest_helper_menu.open_menu()
	if not await click(visit_button("herb:medicine","arrival",30)):return
	if not await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Legitimate nearby helper opens doctor dialogue"):return
	if not check(int(world.data.map_id)==20105 and world.backend==null,"Doctor reached through original route and server-owned position"):return
	if not await choose("yes"):return
	if not check(world.world_travel.body.text.contains("这可是医生的职责所在呢") and not 2401 in world.session.snapshot().original_items,"Numbered doctor thanks visible before receipt"):return
	if not await choose("ok"):return
	if not check(2401 in world.session.snapshot().original_items,"Remote doctor gives original medicine"):return
	world.quest_helper_menu.open_menu()
	if not await click(visit_button("herb:return","arrival",30)):return
	if not await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Return arrival walks back to original girl"):return
	if not await choose("yes"):return
	if not await choose("ok"):return
	if not check(2427 in world.session.snapshot().original_items and not 2401 in world.session.snapshot().original_items,"Remote return grants original amulet"):return
	world.quest_helper_menu.open_menu()
	if not check(world.quest_helper_menu.find_child("QuestHelper_30",true,false).text.ends_with("已完成"),"Herb completed row retained"):return
	# Restore the shell receiver map for the existing cancellation assertions.
	if not await click(visit_button("shell:exchange","near")):return
	if not await ready(func():return not world.quest_helper_travel.active,"Return to shell map"):return
	world.quest_helper_menu.open_menu()
	var journey=world.quest_helper_travel
	# Exercise actual download failure and close while download completion waits.
	world.asset_packs=gate
	gate.held=true
	before=backend.automation.status().position
	if not await click(visit_button("shell:request","near")):return
	gate.finish(false)
	if not check(not journey.active and backend.automation.status().position==before,"Download failure never requests a visit"):return
	world.quest_helper_menu.open_menu()
	gate.held=true
	if not await click(visit_button("shell:request","near")):return
	var ticket: int=journey.generation
	world.quest_helper_menu.close_menu()
	gate.finish(true)
	if not check(not journey.active and backend.automation.status().position==before,"Closing cancels late download completion"):return
	journey._visited({"ok":true,"target":{"map_id":1000,"cell":[56,124]}},ticket)
	if not check(not journey.active and int(world.data.map_id)==2000,"Closing cancels late visit reply"):return
	world.asset_packs=original_packs
	journey.active=true;journey.phase="landing"
	journey.map_reported({"ok":false,"reason":"rejected"},journey.generation)
	if not check(not journey.active,"Rejected position report cancels approach"):return
	journey.active=true;journey.phase="landing";journey.report_ok=true
	journey.target={"mode":"arrival","map_id":int(world.data.map_id),"cell":[-100,-100],"npc_id":""}
	journey._process(0)
	if not check(not journey.active,"Route failure stops approach"):return
	journey.active=true;journey.phase="request"
	server.stop()
	if not await ready(func():return not world.link.online and not journey.active,"Disconnect stops pending visit"):return
	world.link.close()
	world.music.stop();world.effect.stop();world.queue_free()
	server.queue_free();backend.queue_free();gate.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Remote world disposed"):return
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://quest-helper-ui.cfg"))
	if not await local_flow():return
	print("QUEST HELPER UI: PASS")
	quit(0)

func local_flow() -> bool:
	world=load("res://scenes/main.tscn").instantiate()
	world.profile_persistence=false
	world.viewer_prefs_path="user://quest-helper-ui-local.cfg"
	root.add_child(world)
	if not await ready(func():return not world.data.is_empty() and is_instance_valid(world.quest_helper_menu),"Local real core starts"):return false
	world.quest_helper_menu.open_menu()
	world.quest_helper_menu.selected_steps[22]="wood:harvest"
	world.quest_helper_menu.select_quest(22)
	var harvest: Button
	# Locate by source metadata: original jobdaily IDs need not be invented.
	var harvest_buttons: Array=[]
	for button in world.quest_helper_menu.find_children("QuestVisit_*","Button",true,false):
		if str(button.get_meta("quest_step",{}).get("id",""))=="wood:harvest":harvest_buttons.append(button)
	if not check(harvest_buttons.size()==2,"Harvest place has both navigation buttons without NPC"):return false
	for button in harvest_buttons:
		if str(button.get_meta("visit_mode"))=="near":harvest=button
	if not await click(harvest):return false
	if not await ready(func():return not world.quest_helper_travel.active,"Local harvest visit finishes with authoritative report"):return false
	if not check(int(world.data.map_id)==int(harvest.get_meta("quest_step").map_id) and world.world_travel.quest_dialogue.active==false,"Harvest visit changes map without inventing dialogue"):return false
	world.quest_helper_menu.open_menu()
	var arrival: Button
	for button in world.quest_helper_menu.find_children("QuestVisit_*","Button",true,false):
		if str(button.get_meta("quest_step",{}).get("id",""))=="wood:harvest" and str(button.get_meta("visit_mode"))=="arrival":arrival=button
	if not await click(arrival):return false
	if not await ready(func():return not world.quest_helper_travel.active,"Local harvest arrival completes router without NPC approach"):return false
	if not check(not world.world_travel.quest_dialogue.active,"Harvest arrival never opens a synthetic dialogue"):return false
	var journey=world.quest_helper_travel
	journey.active=true;journey.phase="download"
	world.travel_router.request(int(world.data.map_id),world.cell)
	if not check(not journey.active,"New route cancels pending task navigation"):return false
	journey.active=true;journey.phase="download"
	world.walk_to(world.cell)
	if not check(not journey.active,"Manual movement cancels pending task navigation"):return false
	journey.active=true;journey.phase="download"
	world.battle_view.show()
	journey._process(0)
	if not check(not journey.active,"Battle stops task navigation"):return false
	world.battle_view.hide()
	journey.active=true;journey.phase="landing";journey.report_ok=false
	var ticket: int=journey.generation
	journey.cancel()
	journey.active=true;journey.phase="landing"
	journey.map_reported({"ok":true},ticket)
	if not check(not journey.report_ok,"Old map report cannot confirm a newer journey"):return false
	journey.cancel()
	world.music.stop();world.effect.stop();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Local world disposed"):return false
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://quest-helper-ui-local.cfg"))
	return true

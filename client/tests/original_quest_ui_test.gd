extends SceneTree
## Real source catalog, backend commands and game UI; no scripted quest fixtures.
const Catalog=preload("res://scripts/quest_catalog.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:failures+=1;push_error(message)

func run() -> void:
	var source=Catalog.new()
	check(source.npcs.size()==7,"Real reviewed shell and wood quest NPC data exists")
	check(source.active_npcs().filter(func(npc):return str(npc.id).begins_with("sainasu/event/event02_")).size()==(2 if 2 in source.enabled_events else 0),"Public shell NPC activation follows tracked enabled events")
	source.enabled_events=[2]
	var world=load("res://scenes/main.tscn").instantiate()
	world.profile_persistence=false
	world.world_catalog.set_quest_catalog(source)
	root.add_child(world)
	await process_frame
	world.backend.quest_catalog.enabled_events=[2]
	world.adventure_menu.quest_catalog=source
	var npc: Dictionary=source.npcs.filter(func(entry):return int(entry.map_id)==1000)[0]
	var travel=world.world_travel
	var index: int=travel.entries.find(travel.entries.filter(func(entry):return str(entry.get("id",""))==str(npc.id))[0])
	check(travel.sprites[index].texture!=null,"Original source NPC texture is loaded")
	check(travel.sprites[index].position==Vector2(npc.offset[0],npc.offset[1]),"Original sprite offset is preserved")
	var point:=Vector2i(npc.cell[0],npc.cell[1])
	check(travel.blocks(point),"Source NPC retains navigation blocking")
	world.cell=point+Vector2i.LEFT;world.target_cell=world.cell;world.from_cell=world.cell
	world.logical_position=Vector2(world.cell);world.moving=false
	world.link.request({"type":"report_position","map_id":1000,"cell":[world.cell.x,world.cell.y]})
	check(travel.handle_click(travel.sprites[index].to_global(travel.sprites[index].get_rect().get_center())),"Clicking original sprite selects the existing approach path")
	await Wait.until(self,func():return travel.quest_dialogue.active)
	var dialogue=travel.quest_dialogue
	check(dialogue.active and world.paused_input,"Existing approach opens server-owned dialogue and pauses walking")
	var request: Dictionary=npc.branches.filter(func(branch):return str(branch.type)=="REQUEST")[0]
	check(travel.body.text.ends_with(str(request.texts.RequestMsg)),"Visible text is original server REQUEST text")
	dialogue.choose("no")
	check(not dialogue.active and world.session.snapshot().original_items.is_empty(),"NO cancels without granting items")
	travel.selected=index;travel._open()
	dialogue.choose("yes")
	check(world.session.snapshot().original_items==[2415],"Real backend gives one original flower instance")
	check(travel.body.text.ends_with(str(request.texts.ThanksMsg)),"Server thanks phase is displayed")
	dialogue.choose("ok")
	world.adventure_menu.open_menu("inventory")
	var menu=world.adventure_menu
	check(menu.panel.has_node("ItemSlot_potion"),"Existing prototype node names remain available")
	var icon: TextureRect=menu.panel.get_node("OriginalItemIcon_0")
	check(icon.texture!=null and icon.texture.resource_path.ends_with(str(source.items["2415"].icon_path)),"Original flower uses its imported icon")
	menu.panel.get_node("OriginalItemSlot_0").pressed.emit()
	check(menu.panel.get_node("OriginalItemName").text==str(source.items["2415"].name),"Selecting flower displays original name")
	check(menu.panel.get_node("OriginalItemDescription").text==str(source.items["2415"].description),"Selecting flower displays original description")
	check(menu.panel.get_node("OriginalItemSlot_0").gui_input.get_connections().is_empty(),"Quest item has no equipment/double-click handler")
	var slots:=0
	for node in menu.panel.get_children():
		if str(node.name).begins_with("ItemSlot_") or str(node.name).begins_with("OriginalItemSlot_") or str(node.name).begins_with("EmptyItemSlot_"):slots+=1
	check(slots==15,"Positive prototype keys and original instances share exactly 15 bag cells")
	check(not menu.panel.has_node("QuestJournal"),"Inventory no longer carries helper journal")
	world.close_adventure_menu()
	world.quest_helper_menu.open_menu()
	check(world.quest_helper_menu.find_child("QuestHelper_11",true,false).text=="不可思议的贝壳 · 进行中","Helper reads server title and status")
	world.quest_helper_menu.close_menu()
	travel.selected=index;travel._open()
	var old_token: String=dialogue.token
	world.cell+=Vector2i.LEFT
	dialogue._process(0)
	check(not dialogue.active and world.backend.original_quests.pending.is_empty(),"Movement cancels the server token")
	check(not world.link.request({"type":"quest_choose","token":old_token,"choice":"yes"}).ok,"Closed token cannot replay")
	world.music.stop();world.effect.stop();world.queue_free()
	await process_frame
	await process_frame
	await remote_flow(source)
	print("ORIGINAL QUEST UI: ","PASS" if failures==0 else "FAIL")
	quit(1 if failures else 0)

func remote_flow(source) -> void:
	var backend=preload("res://server/backend.gd").new()
	backend.quest_catalog.enabled_events=[2]
	root.add_child(backend)
	var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"Real quest backend listens on an ephemeral port")
	var script=load("res://scripts/game.gd")
	script.server_url_override="ws://127.0.0.1:%d" % server.port
	var world=load("res://scenes/main.tscn").instantiate()
	script.server_url_override=""
	world.profile_persistence=false
	world.viewer_prefs_path="user://original-quest-ui-remote.cfg"
	world.world_catalog.set_quest_catalog(source)
	root.add_child(world)
	check(await Wait.until(self,func():return not world.data.is_empty() and world.link.online) and await Wait.settle(self,world),"Real remote game connects and startup settles")
	check(world.backend==null and not world.link.is_local(),"Remote UI has no authority backend")
	world.adventure_menu.quest_catalog=source
	var giver: Dictionary=source.npcs.filter(func(entry):return int(entry.map_id)==1000)[0]
	var receiver: Dictionary=source.npcs.filter(func(entry):return int(entry.map_id)==2000)[0]
	var destination:=Vector2i(giver.cell[0]-1,giver.cell[1])
	world.load_area_id(1000,destination)
	await Wait.settle(self,world)
	var dialogue=world.world_travel.quest_dialogue
	dialogue.open(str(giver.id))
	check(await Wait.until(self,func():return dialogue.active and not dialogue.busy),"Remote REQUEST reply reaches the UI")
	dialogue.choose("yes")
	check(await Wait.until(self,func():return world.session.snapshot().original_items==[2415] and not dialogue.busy),"Remote proxy snapshot reads original flower from the server")
	dialogue.choose("ok")
	await Wait.until(self,func():return not dialogue.active)
	destination=Vector2i(receiver.cell[0]-1,receiver.cell[1])
	world.load_area_id(2000,destination)
	await Wait.settle(self,world)
	dialogue=world.world_travel.quest_dialogue
	dialogue.open(str(receiver.id))
	await Wait.until(self,func():return dialogue.active and not dialogue.busy)
	dialogue.choose("yes")
	await Wait.until(self,func():return dialogue.active and not dialogue.busy)
	check(world.session.snapshot().original_items==[2415] and dialogue.buttons.size()==1 and dialogue.buttons[0].name=="QuestChoice_ok","Original ACCEPT thanks waits for OK before exchanging items")
	dialogue.choose("ok")
	check(await Wait.until(self,func():return not dialogue.active and world.session.snapshot().original_items==[2414]),"Remote OK commits real shell reward")
	world.quest_helper_menu.open_menu()
	check(world.quest_helper_menu.find_child("QuestHelper_11",true,false).text=="不可思议的贝壳 · 已完成","Remote helper retains completed quests")
	world.quest_helper_menu.close_menu()
	dialogue.open(str(receiver.id))
	await Wait.until(self,func():return dialogue.active and not dialogue.busy)
	world.help.show()
	dialogue.close()
	check(world.paused_input,"Closing dialogue retains another component's pause")
	world.help.hide()
	world.paused_input=false
	dialogue.open(str(receiver.id))
	dialogue.close()
	await Wait.settle(self,world)
	check(await Wait.until(self,func():return backend.original_quests.pending.is_empty()),"Closing before the async reply clears the server's new token")
	dialogue.open(str(receiver.id))
	await Wait.until(self,func():return dialogue.active and not dialogue.busy)
	var cancel:=InputEventAction.new()
	cancel.action="ui_cancel";cancel.pressed=true
	root.push_input(cancel,true)
	check(not dialogue.active,"Escape cancels through the existing world input route")
	await Wait.settle(self,world)
	dialogue.open(str(receiver.id))
	await Wait.until(self,func():return dialogue.active and not dialogue.busy)
	world.load_area_id(1000,Vector2i(giver.cell[0]-1,giver.cell[1]))
	await process_frame
	await Wait.settle(self,world)
	check(backend.original_quests.pending.is_empty(),"Changing maps closes the old dialogue and token")
	dialogue=world.world_travel.quest_dialogue
	dialogue.open(str(giver.id))
	world.load_area_id(2000,Vector2i(receiver.cell[0]-1,receiver.cell[1]))
	await process_frame
	await Wait.settle(self,world)
	check(await Wait.until(self,func():return backend.original_quests.pending.is_empty()),"Map removal before an async reply still cancels its server token")
	dialogue=world.world_travel.quest_dialogue
	dialogue.open(str(receiver.id))
	await Wait.until(self,func():return dialogue.active and not dialogue.busy)
	server.stop()
	check(await Wait.until(self,func():return not world.link.online and not dialogue.active),"Real server disconnect closes quest UI")
	world.link.close()
	world.music.stop();world.effect.stop();world.queue_free()
	server.queue_free();backend.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://original-quest-ui-remote.cfg"))

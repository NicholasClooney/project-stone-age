extends "res://tests/brothers_golden_ui_test.gd"
## Actual remote scene, source questions, rendered viewport and mouse/key input.
const DojoRoute=preload("res://tests/support/golden_bui_route.gd")
const Service = preload("res://server/golden_bui_service.gd")
const QUIZ := "genout/quz_800_29_19@800:29:19"
const FIST := "genout/jan_802_29_19@802:29:19"
var host
var private_data: Dictionary

func route_and_sync(id:String)->bool:
	var npc: Dictionary=host.original_quests.npc_by_id(id)
	if not check(await Wait.settle(self,world),"Settle before server original route"):return false
	if not check(DojoRoute.near(host,npc),"True gate, services and original portals precede source click"):return false
	var cell:Vector2i=host.automation.position_cell
	host.session.set_location(int(npc.map_id),cell.x,cell.y)
	host.publish()
	host._emit({"type":"position","map_id":int(npc.map_id),"cell":[cell.x,cell.y],"client":"golden-bui-ui-fixture"})
	if not await ready(func():return int(world.data.get("map_id",-1))==int(npc.map_id) and world.cell==cell and not world.moving and not world.area_transition_busy,"Remote source floor arrives"):return false
	if not check(await Wait.settle(self,world),"Remote source position settled"):return false
	return true

func place_and_click(id:String)->bool:
	return await route_and_sync(id) and await click_source(id)

func click_source(id:String)->bool:
	var matches: Array=world.world_travel.entries.filter(func(n):return str(n.id)==id)
	if not check(matches.size()==1,"Source NPC rendered once"):return false
	var sprite=world.world_travel.sprites[world.world_travel.entries.find(matches[0])]
	if not check(sprite.texture!=null,"Original source NPC texture loaded"):return false
	var point: Vector2=sprite.get_global_transform_with_canvas()*sprite.get_rect().get_center()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
		root.push_input(event,true)
	return await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Actual source NPC mouse click opens service")

func select_question(input_kind: String) -> bool:
	var npc: Dictionary=host.original_quests.npc_by_id(QUIZ)
	var rng:=RandomNumberGenerator.new()
	for seed_value in range(1000):
		rng.seed=seed_value
		var context: Dictionary={"catalog":private_data,"rng":rng,"in_party":false}
		var plan: Dictionary=Service.reply(npc,host.session.snapshot(),{"phase":"confirm"},"yes","",context)
		if str(plan.get("dialogue",{}).get("input",""))==input_kind:
			host.original_quests.services.rng.seed=seed_value
			return true
	return check(false,"Actual source contains required question kind")

func bounded() -> bool:
	var d=world.world_travel.quest_dialogue
	var viewport:=Rect2(Vector2.ZERO,Vector2(390,844))
	if not check(viewport.encloses(d.panel.get_global_rect()) and viewport.encloses(d.service_scroll.get_global_rect()),"390x844 dialogue and parent scroll fit viewport"):return false
	for button in d.service_controls.buttons:
		if not check(button.size.y>=44,"Every service touch target is at least44px"):return false
	return true

func run() -> void:
	root.unfocusable=true
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
	if not proof_dir.is_empty() and not check(DisplayServer.get_name()!="headless","Pixel evidence requires actual silent offscreen rendering"):return
	if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
	private_data=JSON.parse_string(FileAccess.get_file_as_string(Service.CATALOG_PATH))
	host=Backend.new();root.add_child(host)
	host.quest_catalog.enabled_events=[44]
	host.session._profile.default_companions_claimed=true
	host.session._profile.no_random_encounters=true
	host.session.gm_raise_level(-1,30)
	for key in host.session._profile.inventory:host.session._profile.inventory[key]=0
	Session.OriginalEquipment.add(host.session._profile,2752)
	Session.OriginalEquipment.add(host.session._profile,2752)
	var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
	if not check(server.start()==OK,"Real isolated WebSocket server"):return
	var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
	world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	world.profile_persistence=false;world.viewer_prefs_path="user://golden-bui-ui.cfg"
	var catalog=preload("res://scripts/quest_catalog.gd").new();catalog.enabled_events=[44]
	world.world_catalog.set_quest_catalog(catalog)
	root.add_child(world)
	if not await ready(func():return not world.data.is_empty() and world.link.online,"Actual remote scene ready"):return
	if not check(world.backend==null and await Wait.settle(self,world),"UI has only remote session/link"):return
	if not await place_and_click(QUIZ):return
	await proof("390x844-quiz-entry")
	if not select_question("choice") or not await choose("yes"):return
	if not await ready(func():return world.world_travel.quest_dialogue.service_controls.buttons.size()>=3,"Source choices laid out"):return
	if not bounded():return
	await proof("390x844-quiz-choices")
	world.world_travel.quest_dialogue.service_scroll.ensure_control_visible(world.world_travel.quest_dialogue.service_controls.buttons[-1])
	await proof("390x844-quiz-choices-scrolled")
	if not await choose("cancel"):return
	if not check(host.session.snapshot().original_items.count(2752)==1,"Actual cancel retains original entry debit"):return
	if not await place_and_click(QUIZ):return
	if not select_question("text") or not await choose("yes"):return
	var d=world.world_travel.quest_dialogue
	if not await ready(func():return is_instance_valid(d.service_controls.answer) and d.service_controls.answer.size.y>=44,"Original text input laid out"):return
	if not bounded() or not await click(d.service_controls.answer):return
	var prompt: String=d.body.text
	var source_answer:=""
	for q in private_data.services["genout/quz_800_29_19"].questions:
		if prompt.ends_with(str(q.text)):source_answer=str(q.options[0]);break
	if not check(not source_answer.is_empty(),"Source text-answer oracle found only on server fixture"):return
	# Feed actual text key events. No field assignment or direct service submission.
	for character in source_answer:
		var event:=InputEventKey.new();event.pressed=true;event.unicode=character.unicode_at(0)
		root.push_input(event,true)
	if not check(d.service_controls.answer.text==source_answer,"Focused LineEdit receives real text input"):return
	await proof("390x844-quiz-text-input")
	if not await choose("submit"):return
	if not check(2754 in host.session.snapshot().original_items,"Clicked source answer grants original first-floor prize"):return
	if not await place_and_click(FIST):return
	if not check(world.world_travel.quest_dialogue.body.text.contains("原版行为"),"Approved no-ticket original behavior visibly labelled"):return
	await proof("390x844-janken-original-behavior")
	world.world_travel.quest_dialogue.service_scroll.ensure_control_visible(world.world_travel.quest_dialogue.service_controls.buttons[0])
	await proof("390x844-janken-original-behavior-scrolled")
	if not await choose("yes"):return
	if not await ready(func():return world.world_travel.quest_dialogue.service_controls.buttons.size()==3,"Three original hands ready"):return
	if not bounded():return
	await proof("390x844-janken-hands")
	world.world_travel.quest_dialogue.service_scroll.ensure_control_visible(world.world_travel.quest_dialogue.service_controls.buttons[-1])
	await proof("390x844-janken-hands-scrolled")
	if not await choose("rock"):return
	if not check(not 2751 in host.session.snapshot().original_items,"No-ticket click never invents a coupon"):return
	world.world_travel.quest_dialogue.close()
	world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free()
	await process_frame
	print("GOLDEN BUI UI: %d failures"%failures)
	quit(1 if failures else 0)

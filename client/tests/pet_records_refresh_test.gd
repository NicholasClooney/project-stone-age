extends SceneTree
## Real local backend/session pushes while records stay open. No fake world.
const Wait=preload("res://tests/support/wait.gd")
const PetTable=preload("res://scripts/pet_table.gd")
const Progression=preload("res://server/progression.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func scroll(menu)->ScrollContainer:
	return menu.panel.find_child("RecordsScroll",true,false)
func settled(menu)->void:
	await Wait.until(self,func():return not menu.records_loading and not menu._records_refresh_pending)
	await process_frame
func press(menu,node_name:String)->void:
	(menu.panel.find_child(node_name,true,false) as Button).pressed.emit()
	await settled(menu)
func highlight_checks(game,menu)->void:
	# Actual controls exercise callbacks copied from successive draft trees.
	for pair in [["caught","RecordsTabCaught"],["released","RecordsTabReleased"],["stops","RecordsTabStops"],["queue","RecordsTabQueue"],["caught","RecordsTabCaught"],["released","RecordsTabReleased"]]:
		await press(menu,pair[1])
		check(menu.records_tab==pair[0],"tab click selects %s"%pair[0])
		for tab in [["caught","RecordsTabCaught"],["released","RecordsTabReleased"],["stops","RecordsTabStops"],["queue","RecordsTabQueue"]]:
			var button:Button=menu.panel.find_child(tab[1],true,false)
			check((button.get_theme_color("font_color")==PetTable.GOLD)==(tab[0]==pair[0]) and (button.get_theme_color("font_pressed_color")==PetTable.GOLD)==(tab[0]==pair[0]),"only current tab has gold normal/pressed colors (%s / %s)"%[pair[0],tab[0]])
	await press(menu,"RecordsSort_attack")
	await press(menu,"RecordsSort_speed")
	check(menu.records_sorts.released[0]=="speed" and menu.panel.find_child("RecordsSort_speed",true,false).get_theme_color("font_color")==PetTable.GOLD and menu.panel.find_child("RecordsSort_attack",true,false).get_theme_color("font_color")!=PetTable.GOLD,"sort click moves highlight to new column")
	var next:Button
	for button in menu.panel.find_children("*","Button",true,false):
		if button.text=="▶":next=button;break
	next.pressed.emit();await settled(menu)
	check(menu.records_page==1 and int(menu.records_data.page)==1,"actual next-page callback requests the next backend page")
	await press(menu,"RecordsTabCaught")
	var run:OptionButton=menu.panel.find_child("RecordsRun",true,false)
	run.select(1);run.item_selected.emit(1);await settled(menu)
	check(menu.records_run=="","actual run selector callback shows all captures")
	game.session.gm_grant_pet(1)
	var pet_id:String=str(game.backend.capture_log.entries()[-1].pet_id)
	check(await Wait.until(self,func():return menu.records_data.entries.any(func(item):return str(item.pet_id)==pet_id)),"new real species arrives before selector click")
	await settled(menu)
	var species:OptionButton=menu.panel.find_child("RecordsSpecies",true,false)
	var choice:int=-1
	var choices:Array=[-1]
	for item in menu.records_data.species:choices.append(int(item.template_id))
	choice=choices.find(1)
	check(choice>=0,"updated species choices contain newly granted species")
	if choice<0:return
	species.select(choice);species.item_selected.emit(choice);await settled(menu)
	check(menu.records_template==1 and menu.records_data.entries.all(func(item):return int(item.template_id)==1),"species click uses refreshed choices callback and backend filter")
	var row:PanelContainer=menu.panel.find_child("CaughtRow_0",true,false)
	var line:HBoxContainer=row.get_child(0).get_child(0)
	var badge:PanelContainer=line.get_child(line.get_child_count()-1)
	check(badge.get_theme_stylebox("panel").border_color==PetTable.GOOD,"unreleased row has green badge style")
	badge.get_child(0).add_theme_color_override("font_outline_color",PetTable.BAD)
	game.session.release_pets([pet_id])
	check(await Wait.until(self,func():return not menu.records_data.entries[0].get("released",{}).is_empty()),"real release updates caught row")
	await settled(menu)
	check(is_instance_valid(badge) and badge.get_theme_stylebox("panel").border_color==PetTable.BAD and not badge.get_child(0).has_theme_color_override("font_outline_color"),"reused row updates style and removes overrides absent from draft")
	game.session.gm_grant_pet(1)
	var fresh:String=str(game.backend.capture_log.entries()[-1].pet_id)
	check(await Wait.until(self,func():return str(menu.records_data.entries[0].pet_id)==fresh),"new caught row replaces released content")
	await settled(menu)
	check(is_instance_valid(badge) and badge.get_theme_stylebox("panel").border_color==PetTable.GOOD and badge.get_child(0).get_theme_color("font_color")==PetTable.GOOD,"same badge clears old red text and row style for new capture")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false;game.viewer_prefs_path="user://records-refresh.cfg";root.add_child(game)
	await process_frame
	game.session.grant_starter_pets();game.load_area_id(100,Vector2i(637,493))
	for node in [game.pet_workflow,game.pet_hunt_menu,game.training_helper]:node.set_process(false)
	game.backend.automation.auto_tick=false
	for i in range(45):
		game.session.gm_grant_pet(92)
		game.session.release_pets([str(game.backend.capture_log.entries()[-1].pet_id)])
	var menu=game.adventure_menu
	for tab in ["caught","released"]:
		menu.open_pet_records(tab)
		menu.records_run="";menu.records_page=1
		if tab=="released":menu.records_sorts.released=["attack",false]
		menu.fetch_records();await settled(menu)
		var panel=menu.panel;var window=panel.find_child("PetRecordsPanel",true,false)
		var list=scroll(menu)
		check(await Wait.until(self,func():return list.get_v_scroll_bar().max_value>list.size.y),"%s fixture has scrollable contents"%tab)
		list.scroll_vertical=137
		var at:int=list.scroll_vertical
		var row=panel.find_child("CaughtRow_0" if tab=="caught" else "ReleaseLogRow_0",true,false)
		var draws:int=menu.records_draw_count
		for battle in range(3):
			check(bool(game.link.request({"type":"begin_battle"}).get("ok",false)),"%s real battle starts"%tab)
			game.training_helper.preset.select(0);game.training_helper.compact.button_pressed=false
			game.training_helper.start_training()
			check(game.backend.automation.running,"%s backend automatic battle runs"%tab)
			game.backend.automation._emit_status()
			game.backend._refresh_battle_state()
			game.link.request({"type":"battle_escape_dev"});game.link.request({"type":"battle_close"})
			game.training_helper.stop_training("test finished")
			menu.fetch_records(true)
			await settled(menu)
		check(menu.panel==panel and panel.find_child("PetRecordsPanel",true,false)==window and scroll(menu)==list,"%s preserves window and scroll nodes through continuous battles"%tab)
		check(list.scroll_vertical==at and menu.records_page==1,"%s keeps exact scroll and page"%tab)
		check(menu.records_draw_count==draws and is_instance_valid(row),"%s unchanged data does not redraw or replace hovered row"%tab)
		var total:int=int(menu.records_data.total)
		var selector:OptionButton=panel.find_child("RecordsSpecies",true,false)
		selector.get_popup().popup()
		var before_update:int=menu.records_draw_count
		game.session.gm_grant_pet(92);game.session.release_pets([str(game.backend.capture_log.entries()[-1].pet_id)])
		check(await Wait.until(self,func():return int(menu.records_data.get("total",0))==total+1),"%s real log event updates contents"%tab)
		check(selector.get_popup().visible and menu.records_draw_count==before_update,"%s refresh waits for open species popup"%tab)
		selector.get_popup().hide()
		check(await Wait.until(self,func():return menu.records_draw_count>before_update),"%s renders newest data after popup closes"%tab)
		await settled(menu)
		check(menu.panel==panel and scroll(menu)==list and list.scroll_vertical==at and is_instance_valid(row),"%s changed contents keep nodes and exact scroll"%tab)
		if tab=="released":check(menu.records_sorts.released==["attack",false],"live refresh preserves release sort")
	var automation=game.backend.automation
	automation.flow_showcase=true;automation.flow_phase="hunt"
	var actor:Dictionary=Progression.species_actor("wooli",1,573)
	actor.merge({"species":"wooli","name":"乌力","template_id":1,"level":1,"xp":0})
	for i in range(10):automation._showcase_enqueue(i,0,{"enemies":[actor]},{"valid":true,"offsets":[0,0,0,0],"total_offset":0})
	actor.template_id=2
	for i in range(10):automation._showcase_enqueue(20+i,0,{"enemies":[actor]},{"valid":true,"offsets":[0,0,0,0],"total_offset":0})
	menu.open_pet_records("queue");await settled(menu)
	menu.sort_records("attack");await process_frame
	var panel=menu.panel;var list=scroll(menu)
	var window=panel.find_child("PetRecordsPanel",true,false)
	check(await Wait.until(self,func():return list.get_v_scroll_bar().max_value>list.size.y),"queue fixture has scrollable contents")
	list.scroll_vertical=137
	var queue_at:int=list.scroll_vertical
	var row=panel.find_child("QueueRow_0",true,false)
	var draws:int=menu.records_draw_count
	for i in range(3):
		automation.battles+=1;automation._emit_status()
		menu.fetch_records(true);await settled(menu)
	check(menu.records_draw_count==draws and panel==menu.panel and is_instance_valid(row),"queue battle status with unchanged view does not redraw")
	actor.growth_seed=99991;actor.template_id=3
	automation._showcase_enqueue(99,0,{"enemies":[actor]},{"valid":true,"offsets":[2,2,2,2],"total_offset":8})
	check(await Wait.until(self,func():return menu.records_data.entries.any(func(item):return int(item.roll)==100)),"real queue event refreshes entries")
	await settled(menu)
	check(menu.panel==panel and panel.find_child("PetRecordsPanel",true,false)==window and scroll(menu)==list and list.scroll_vertical==queue_at and menu.records_sorts.queue==["attack",false],"queue refresh preserves window, scroll node and sort")
	# A real caught pet's level is read by the backend's current train row.
	game.session.gm_grant_pet(92)
	automation.showcase_current=automation.showcase_queue.pop_front()
	automation.flow_phase="train"
	automation.flow_pet_id=str(game.backend.capture_log.entries()[-1].pet_id)
	automation._emit_status()
	check(await Wait.until(self,func():return menu.records_data.entries.any(func(item):return bool(item.current) and str(item.phase)=="train")),"queue shows the real current training pet")
	var pets:Array=game.session.snapshot().pets
	var pet_index:int=-1
	for i in range(pets.size()):
		if str(pets[i].pet_id)==automation.flow_pet_id:pet_index=i
	game.session.gm_raise_level(pet_index,30)
	automation.battles+=1;automation._emit_status()
	check(await Wait.until(self,func():return menu.records_data.entries.any(func(item):return bool(item.current) and int(item.level)==30)),"training battle status refreshes current pet level from the real session")
	await settled(menu)
	check(menu.panel==panel and scroll(menu)==list and list.scroll_vertical==queue_at and menu.records_sorts.queue==["attack",false],"training level updates preserve window, exact scroll and sort")
	await highlight_checks(game,menu)
	menu.pet_records_open=false;game.close_adventure_menu();game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free();await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://records-refresh.cfg"))
	print("PET RECORDS REFRESH: %d failures"%failures);quit(1 if failures else 0)

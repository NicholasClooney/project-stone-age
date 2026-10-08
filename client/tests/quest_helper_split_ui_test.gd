extends "res://tests/quest_helper_ui_test.gd"
const Rules=preload("res://server/original_quests.gd")
var visual:=false
func run() -> void:
	root.gui_embed_subwindows=true
	root.content_scale_size=Vector2i.ZERO
	visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	if visual:DirAccess.make_dir_recursive_absolute("/private/tmp/quest-helper-split-shots")
	for remote in [false,true]:
		if not await exercise(remote):return
	print("QUEST HELPER SPLIT UI: PASS")
	quit(0)
func shot(id:String) -> void:
	if not visual:return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/quest-helper-split-shots/"+id+".png")
func exercise(remote:bool) -> bool:
	var backend
	var server
	var script=load("res://scripts/game.gd")
	if remote:
		backend=preload("res://server/backend.gd").new();root.add_child(backend)
		server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
		if not check(server.start()==OK,"Ephemeral split UI server starts"):return false
		script.server_url_override="ws://127.0.0.1:%d"%server.port
	world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	world.profile_persistence=false;world.viewer_prefs_path="user://quest-split.cfg";root.add_child(world)
	if not await ready(func():return not world.data.is_empty() and (not remote or world.link.online),"Real world ready"):return false
	if not check(await Wait.settle(self,world),"Initial projection settles"):return false
	if not remote:backend=world.backend
	if not check(not remote or world.backend==null,"Remote UI has no backend"):return false
	Rules.set_flag(backend.session._profile,"now",2,true);backend.publish()
	if not check(await Wait.settle(self,world),"Current task projection settles"):return false
	var menu=world.quest_helper_menu
	for dimensions in [Vector2i(1280,720),Vector2i(390,844)]:
		root.size=dimensions
		menu.detail_open=false;menu.selected_steps.clear();menu.open_menu()
		if not await ready(func():return menu.narrow==(dimensions.x<720),"Responsive mode updates"):return false
		await process_frame
		if not root.get_visible_rect().encloses(menu.get_global_rect()):
			print_geometry_failure(menu,remote,dimensions)
		if not check(root.get_visible_rect().encloses(menu.get_global_rect()),"Menu stays inside viewport"):return false
		var current=menu.find_child("QuestCurrentScroll",true,false)
		if not check(current.is_ancestor_of(menu.find_child("QuestHelper_11",true,false)),"In-progress tasks pinned above remaining list"):return false
		await shot(("remote" if remote else "local")+"-%dx%d-list"%[dimensions.x,dimensions.y])
		var row=menu.find_child("QuestHelper_30",true,false)
		if not await click(row):return false
		if not check(menu.selected_id==30 and menu.detail_open,"Real quest row opens selected details"):return false
		if not await ready(func():return menu.detail_scroll.size.x>0,"Detail layout ready"):return false
		if not check(menu.find_child("QuestAutoStart_11",true,false)==null,"Other task details absent"):return false
		if not check(menu.group_for({"status":"未开始","blocked_reason":"需要前置","steps":[{"current":true,"actionable":true}]})=="未开始","Blocked prerequisite never advertised as available"):return false
		# A new server catalog entry is discovered without a client-side task list.
		backend.quest_catalog.jobs.append({"id":9901,"event":9901,"title":"服务器新增任务"})
		backend.quest_helper.cached_key="";backend.publish()
		if not check(await Wait.settle(self,world),"New catalog projection settles"):return false
		if not await ready(func():return menu.find_child("QuestHelper_9901",true,false)!=null,"Dynamic server quest appears"):return false
		if not check(menu.selected_id==30,"Model update preserves selected task"):return false
		for control in menu.find_children("*","Button",true,false):
			if not control.is_visible_in_tree():continue
			if not check(control.size.x>=44 and control.size.y>=44,"Visible touch control has 44px height: "+str(control.name)):return false
		await shot(("remote" if remote else "local")+"-%dx%d-detail"%[dimensions.x,dimensions.y])
		if dimensions.x<720:
			if not check(not menu.list_scroll.is_visible_in_tree(),"Phone details replace list"):return false
			if not await click(menu.find_child("QuestHelperBack",true,false)):return false
			if not check(menu.list_scroll.is_visible_in_tree() and menu.selected_id==30,"Back preserves selection"):return false
			if not await click(menu.find_child("QuestHelper_30",true,false)):return false
		if dimensions.x<720:
			# The fixed stop remains reachable even on the phone's list page.
			var packs=world.asset_packs
			var gate:=PackGate.new();root.add_child(gate);world.asset_packs=gate
			if not await click(menu.find_child("QuestAutoStart_30",true,false)):return false
			if not check(gate.waiting.is_valid(),"Phone automatic action enters real download gate"):return false
			if not await click(menu.find_child("QuestHelperBack",true,false)):return false
			await shot(("remote" if remote else "local")+"-390x844-stop")
			if not await click(menu.find_child("QuestAutoStop",true,false)):return false
			gate.finish(true)
			if not check(await Wait.settle(self,world) and not backend.quest_auto.running,"Phone stop cancels delayed auto start"):return false
			world.asset_packs=packs;gate.queue_free()
			if not await click(menu.find_child("QuestHelper_30",true,false)):return false
		var step=menu.find_child("QuestStep_30_herb_medicine",true,false)
		# validate_node_name replaces colon with underscore.
		if step==null:step=menu.find_child("QuestStep_30_"+"herb:medicine".validate_node_name(),true,false)
		if not await click(step):return false
		if not check(menu.find_child("QuestVisit_30_herb_medicine_near",true,false)!=null,"Choosing another step exposes its navigation"):return false
		if dimensions.x<720:
			if not await click(menu.find_child("QuestHelperBack",true,false)):return false
			print_scroll_diagnostic(menu,remote,dimensions,"before-lower-click",-1)
			if not await click(menu.find_child("QuestHelper_9901",true,false)):return false
			var saved_scroll:int=menu.list_position
			print_scroll_diagnostic(menu,remote,dimensions,"after-lower-click",saved_scroll)
			if not check(saved_scroll>0,"Selecting lower task records list scroll"):return false
			print_scroll_diagnostic(menu,remote,dimensions,"before-back-click",saved_scroll)
			if not await click(menu.find_child("QuestHelperBack",true,false)):return false
			print_scroll_diagnostic(menu,remote,dimensions,"after-back-click",saved_scroll)
			var diagnostic_previous:Array[String]=[""]
			var diagnostic_count:Array[int]=[0]
			var diagnostic_observer:Callable=func():
				if diagnostic_count[0]>32:return
				if diagnostic_count[0]==32:
					diagnostic_count[0]+=1
					print("DIAGNOSTIC SPLIT SCROLL: snapshot limit 32 reached; further collection disabled")
					return
				var snapshot:String=scroll_diagnostic_snapshot(menu,remote,dimensions,"restore-wait",saved_scroll)
				if snapshot!=diagnostic_previous[0]:
					diagnostic_previous[0]=snapshot
					diagnostic_count[0]+=1
					print("DIAGNOSTIC SPLIT SCROLL: "+snapshot)
			process_frame.connect(diagnostic_observer)
			var scroll_restored:bool=await ready(func():return menu.list_scroll.scroll_vertical==saved_scroll,"Back restores exact list scroll")
			if process_frame.is_connected(diagnostic_observer):process_frame.disconnect(diagnostic_observer)
			if not scroll_restored:return false
		var retained_id:int=menu.selected_id
		Rules.set_flag(backend.session._profile,"ended",1,true);backend.publish()
		if not check(await Wait.settle(self,world),"Changed task status settles"):return false
		if not await ready(func():return menu.find_child("QuestHelper_30",true,false).text.ends_with("已完成"),"Changed status moves task to completed group"):return false
		if not check(menu.selected_id==retained_id,"Status updates never jump selected task"):return false
		Rules.set_flag(backend.session._profile,"ended",1,false);backend.publish()
		if not check(await Wait.settle(self,world),"Status fixture restored"):return false
		# Esc retains existing stop/close and pause policy.
		var esc:=InputEventKey.new();esc.keycode=KEY_ESCAPE;esc.pressed=true;root.push_input(esc,true)
		if not await ready(func():return not menu.visible,"Esc closes helper"):return false
		if not check(not world.paused_input,"Esc restores exploration input"):return false
		backend.quest_catalog.jobs=backend.quest_catalog.jobs.filter(func(job):return int(job.id)!=9901)
		backend.quest_helper.cached_key="";backend.publish()
	world.music.stop();world.effect.stop()
	if remote:world.link.close()
	world.queue_free()
	if remote:server.stop();server.queue_free();backend.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Split UI world disposed"):return false
	return true

func print_geometry_failure(menu,remote:bool,dimensions:Vector2i)->void:
	print("SPLIT GEOMETRY DIAGNOSTIC: remote=%s dimensions=%s viewport=%s narrow=%s detail_open=%s"%[remote,dimensions,root.get_visible_rect(),menu.narrow,menu.detail_open])
	var listing:Control=menu.list_scroll.get_parent() if is_instance_valid(menu.list_scroll) else null
	var details:Control=menu.detail_scroll.get_parent() if is_instance_valid(menu.detail_scroll) else null
	var panes:Control=listing.get_parent() if is_instance_valid(listing) else null
	var status:Control=menu.find_child("QuestHelperStatusScroll",true,false)
	var controls:Dictionary={"menu":menu,"body":menu.body,"status":status,"panes":panes,"list":listing,"detail":details,"list_scroll":menu.list_scroll,"detail_scroll":menu.detail_scroll}
	if is_instance_valid(status) and status.get_child_count()>0:controls["status_body"]=status.get_child(0)
	for id in controls:
		var control:Control=controls[id]
		if not is_instance_valid(control):
			print("SPLIT GEOMETRY %s: absent"%id)
			continue
		print("SPLIT GEOMETRY %s: name=%s visible=%s rect=%s combined_min=%s custom_min=%s size=%s position=%s"%[id,control.name,control.is_visible_in_tree(),control.get_global_rect(),control.get_combined_minimum_size(),control.custom_minimum_size,control.size,control.position])

func print_scroll_diagnostic(menu,remote:bool,dimensions:Vector2i,phase:String,saved:int)->void:
	print("DIAGNOSTIC SPLIT SCROLL: "+scroll_diagnostic_snapshot(menu,remote,dimensions,phase,saved))
func scroll_diagnostic_snapshot(menu,remote:bool,dimensions:Vector2i,phase:String,saved:int)->String:
	var facts:Dictionary={"phase":phase,"remote":remote,"dimensions":dimensions,"viewport":root.get_visible_rect(),"saved":saved,"remembered":menu.list_position,"detail_open":menu.detail_open,"selected_id":menu.selected_id}
	var listing:Control=menu.list_scroll.get_parent() if is_instance_valid(menu.list_scroll) else null
	var details:Control=menu.detail_scroll.get_parent() if is_instance_valid(menu.detail_scroll) else null
	var status:Control=menu.find_child("QuestHelperStatusScroll",true,false)
	var controls:Dictionary={"menu":menu,"body":menu.body,"status":status,"list":listing,"detail":details,"list_scroll":menu.list_scroll,"detail_scroll":menu.detail_scroll}
	if is_instance_valid(listing):controls["panes"]=listing.get_parent()
	if is_instance_valid(status) and status.get_child_count()>0:controls["status_body"]=status.get_child(0)
	for id in controls:
		var control:Control=controls[id]
		if not is_instance_valid(control):
			facts[id]={"present":false}
			continue
		var item:Dictionary={"id":control.get_instance_id(),"visible":control.is_visible_in_tree(),"rect":control.get_global_rect(),"size":control.size,"minimum":control.get_combined_minimum_size(),"custom_minimum":control.custom_minimum_size}
		if control is ScrollContainer:
			var bar:VScrollBar=control.get_v_scroll_bar()
			item.merge({"scroll":control.scroll_vertical,"value":bar.value,"min":bar.min_value,"max":bar.max_value,"page":bar.page})
		facts[id]=item
	return JSON.stringify(facts)

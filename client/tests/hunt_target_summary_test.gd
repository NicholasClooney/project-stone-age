extends SceneTree
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func click(point:Vector2)->void:
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
func single_caption(menu)->bool:
	var rect:Rect2=menu.target_button.get_global_rect()
	var count:=0
	for child in menu.panel.get_children():
		if child is Control and child.is_visible_in_tree() and child.get_global_rect().intersects(rect) and (child is Button or child is Label):count+=1
	return count==1 and not menu.species.is_visible_in_tree()
func client(port:int,tag:String):
	var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%port
	var game=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	game.profile_persistence=false;game.viewer_prefs_path="user://hunt-summary-%s.cfg"%tag
	root.add_child(game)
	check(await Wait.until(self,func():return not game.data.is_empty() and game.link.online) and await Wait.settle(self,game),"remote device connects and settles")
	game.random_encounters=false
	return game
func run()->void:
	root.size=Vector2i(1280,800)
	root.gui_embed_subwindows=true
	var backend=preload("res://server/backend.gd").new();root.add_child(backend)
	var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1");root.add_child(server)
	check(server.start()==OK,"isolated server uses dynamic port")
	var b=await client(server.port,"b")
	var a=await client(server.port,"a")
	a.load_area_id(100,Vector2i(637,493))
	check(await Wait.until(self,func():return int(b.data.map_id)==100 and b.cell==Vector2i(637,493) and not a.area_transition_busy and not b.area_transition_busy),"both remote devices arrive")
	check(await Wait.settle(self,a) and await Wait.settle(self,b),"position commands settle before UI changes")
	var menu=a.pet_hunt_menu;var other=b.pet_hunt_menu
	other.open_menu();menu.open_menu()
	check(a.backend==null and b.backend==null,"remote menus have no backend")
	check(single_caption(menu),"target row has exactly one visible caption on open")
	for page in ["capture","stats","filters","capture","filters"]:menu.show_page(page)
	check(single_caption(menu),"page switching never reveals legacy dropdown")
	menu._target_pressed(-3)
	check(menu.target_button.text=="未选","none updates caption immediately")
	check(await Wait.settle(self,a) and await Wait.until(self,func():return other.target_ids.is_empty()),"none persists and reaches second snapshot")
	menu._target_pressed(-2)
	var available:int=menu.target_ids.size()
	check(available>=2 and menu.target_button.text=="全部 %d 种"%available,"all caption counts only locally usable species")
	check(await Wait.settle(self,a),"all selection reaches authority")
	menu._target_pressed(int(menu.target_ids.back()))
	check(menu.target_button.text.begins_with("已选 %d 种："%menu.target_ids.size()) and menu.target_button.text.contains(str(menu.candidates[0].name)),"partial caption includes Chinese species names")
	check(await Wait.settle(self,a),"partial selection settles")
	a.link.request({"type":"set_automation_settings","settings":{"hunt":{"templates":[92]}}})
	check(await Wait.settle(self,a) and await Wait.until(self,func():return menu.target_ids==[92]),"off-map target reaches UI")
	check(menu.target_button.text=="未选" and menu.target_button.tooltip_text.contains("此处不可抓") and menu.target_button.tooltip_text.contains("扬奇洛斯"),"local none distinguishes saved off-map species in full tooltip")
	check(menu.settings_patch().get("hunt",{}).get("templates",[92])==[92],"display never replaces saved off-map choice")
	menu.show_page("capture");menu.show_page("filters")
	await process_frame
	await click(menu.target_button.get_global_transform_with_canvas()*(menu.target_button.size/2))
	check(await Wait.until(self,func():return menu.target_button.get_popup().visible),"real viewport pointer opens remote checklist")
	var popup:PopupMenu=menu.target_button.get_popup()
	check(popup.is_embedded() and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(Rect2(Vector2(popup.position),Vector2(popup.size))),"checklist popup is embedded and fits viewport")
	# The first item is 全选. Route input through the real window dispatch to
	# the embedded popup viewport rather than emitting a control signal.
	await click(Vector2(popup.position)+Vector2(30,15))
	check(await Wait.until(self,func():return menu.target_button.text=="全部 %d 种"%available),"real popup click immediately selects all")
	check(await Wait.settle(self,a) and await Wait.until(self,func():return other.target_button.text==menu.target_button.text),"clicked selection persists and updates another device summary")
	await click(menu.target_button.get_global_transform_with_canvas()*(menu.target_button.size/2))
	check(await Wait.until(self,func():return popup.visible),"reopen actual checklist")
	await click(Vector2(popup.position)+Vector2(30,40))
	check(menu.target_button.text=="未选","real all-none click updates immediately")
	check(await Wait.settle(self,a) and await Wait.until(self,func():return other.target_ids.is_empty()),"real all-none click saves across devices")
	await click(menu.target_button.get_global_transform_with_canvas()*(menu.target_button.size/2))
	check(await Wait.until(self,func():return popup.visible),"open checklist to toggle actual species")
	await click(Vector2(popup.position)+Vector2(40,84))
	check(menu.target_ids.size()==1 and popup.is_item_checked(3) and popup.visible and menu.target_button.text.contains(str(menu.candidates[0].name)),"actual species checkbox stays open and immediately updates named summary")
	check(await Wait.settle(self,a) and await Wait.until(self,func():return other.target_ids==menu.target_ids),"species click persists across device snapshots")
	popup.hide()
	var before:Vector2=menu.target_button.size
	for item in menu.candidates:item.name="这是用于验证手机单行省略的超长中文宠物品种名称".repeat(6)
	menu.target_ids=[int(menu.candidates[0].id)];menu._update_target_checks()
	await process_frame
	check(menu.target_button.text.length()>80 and menu.target_button.tooltip_text.contains(menu.target_button.text),"long summary retains full tooltip")
	check(menu.target_button.clip_text and menu.target_button.text_overrun_behavior==TextServer.OVERRUN_TRIM_ELLIPSIS and menu.target_button.size==before,"long name stays one fixed-width ellipsis caption")
	check(menu.panel.get_global_rect().encloses(menu.target_button.get_global_rect()) and not menu.target_button.get_global_rect().intersects(menu.level_one.get_global_rect()) and not menu.target_button.get_global_rect().intersects(menu.auto_capture.get_global_rect()),"actual canvas geometry contains target and clears neighboring controls")
	for index in range(30):popup.add_check_item("用于验证长名单滚动的中文目标品种名称".repeat(10),1000+index)
	await click(menu.target_button.get_global_transform_with_canvas()*(menu.target_button.size/2))
	check(await Wait.until(self,func():return popup.visible),"desktop opens long checklist through actual pointer")
	popup.id_pressed.disconnect(menu._target_pressed)
	var pressed_ids:=[]
	popup.id_pressed.connect(func(id):pressed_ids.append(id))
	popup.scroll_to_item(popup.item_count-1)
	await process_frame
	await click(Vector2(popup.position)+Vector2(40,popup.size.y-16))
	check(1029 in pressed_ids,"scrolling makes last species reachable by actual pointer click")
	popup.id_pressed.connect(menu._target_pressed)
	popup.hide()
	root.content_scale_size=Vector2i(1280,800);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.size=Vector2i(390,844)
	await process_frame
	var transform:Transform2D=root.get_final_transform()
	var phone_rect:Rect2=transform*menu.target_button.get_global_rect()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(phone_rect) and single_caption(menu),"phone viewport canvas bounds contain exactly one target caption")
	await click(root.get_final_transform()*(menu.target_button.get_global_transform_with_canvas()*(menu.target_button.size/2)))
	check(await Wait.until(self,func():return popup.visible),"phone canvas opens long checklist through actual pointer")
	check(popup.size.x<=366 and popup.size.y<=360 and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(root.get_final_transform()*Rect2(Vector2(popup.position),Vector2(popup.size))),"long checklist fits phone viewport width, position and scrolling height")
	check(popup.get_item_text(popup.item_count-1).ends_with("…") and popup.get_item_tooltip(popup.item_count-1).length()>popup.get_item_text(popup.item_count-1).length(),"popup long labels truncate with complete tooltips")
	popup.hide()
	for game in [a,b]:
		game.process_mode=Node.PROCESS_MODE_DISABLED;game.link.close();game.music.stop();game.effect.stop();game.queue_free()
	server.stop();server.queue_free();backend.queue_free();await process_frame
	print("HUNT TARGET SUMMARY: %d failures"%failures);quit(1 if failures else 0)

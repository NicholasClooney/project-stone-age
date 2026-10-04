extends "res://tests/quest_auto_background_ui_test.gd"
## Real remote game + profile settings transactions, not a route/loot execution test.
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	remote_mode=true
	backend_node=Backend.new();backend_node.set_process(false)
	backend_node.save_path="user://quest-auto-v2-settings-remote.json"
	root.add_child(backend_node)
	server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
	if not check(server_node.start()==OK,"Settings server port0"):return
	if not await create_world():return
	var menu=world.quest_helper_menu
	menu.open_menu()
	if not await click(menu.find_child("QuestAutoSettingsOpen",true,false)):return
	var panel=menu.settings_panel
	if not check(world.backend==null and panel.mode.selected==0 and panel.budget.value==30,"Remote backend-null page defaults A/30"):return
	panel.mode.select(2);panel.mode.item_selected.emit(2);panel.budget.value=45
	if not await click(panel.apply_button):return
	if not check(await Wait.settle(self,world),"Settings save roundtrip"):return
	if not await ready(func():return not menu.settings_pending and panel.feedback.text.contains("已保存"),"Successful save acknowledged"):return
	if not check(backend_node.session.automation_settings().quest=={"mode":"C","loot_minutes":45} and world.state.derived.quest_auto.settings.mode=="C","Real server and remote snapshot persist requested C/45"):return
	if not check(world.state.derived.quest_auto.effective_mode=="C" and world.state.derived.quest_auto.available_modes==["A","B","C"] and panel.feedback.text.contains("七条公开走廊"),"Authority exposes C policy with exact audited-corridor limitation"):return
	var reloaded=Backend.new()
	if not check(reloaded.load_profile(backend_node.save_path) and reloaded.session.automation_settings().quest.mode=="C","Real saved profile reload retains preference"):return
	reloaded.free()
	backend_node.save_path="user://missing-v2-settings-parent/save.json"
	panel.mode.select(1);panel.budget.value=90
	if not await click(panel.apply_button):return
	if not check(await Wait.settle(self,world),"Save rejection roundtrip"):return
	if not await ready(func():return not menu.settings_pending,"Save failure finishes request"):return
	if not check(backend_node.session.automation_settings().quest=={"mode":"C","loot_minutes":45} and panel.mode.selected==2 and panel.budget.value==45 and not menu.settings_feedback.contains("已保存"),"Save failure rolls authority and UI back"):return
	backend_node.save_path="user://quest-auto-v2-settings-remote.json"
	world.link.close()
	if not await ready(func():return not world.link.online and panel.apply_button.disabled,"Offline settings cannot submit"):return
	world.link.connect_now()
	if not await ready(func():return world.link.online and not panel.apply_button.disabled,"Reconnected settings enable explicit save"):return
	if not check(await Wait.settle(self,world),"Reconnect settles"):return
	if not check(world.state.derived.quest_auto.settings=={"mode":"C","loot_minutes":45},"Reconnect keeps saved settings"):return
	menu.close_menu()
	var pump:=LinkPump.new();root.add_child(pump)
	var other=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server_node.port)
	pump.links=[other];other.connect_now()
	if not await ready(func():return other.online,"Second settings client connects"):return
	if not check((await rpc(other,{"type":"set_automation_settings","settings":{"quest":{"mode":"B","loot_minutes":60}}})).ok,"Second device saves preference"):return
	if not check(await Wait.settle(self,world),"Other-device publish settles"):return
	menu.open_menu()
	if not check(menu.settings_panel.mode.selected==1 and menu.settings_panel.budget.value==60,"Reopened settings use fresh authority from second device"):return
	other.close();pump.queue_free()
	world.link.close();world.music.stop();world.effect.stop();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Settings world disposed"):return
	server_node.stop();server_node.queue_free();backend_node.queue_free()
	for suffix in ["",".bak",".tmp",".resume.json"]:
		var path:String="user://quest-auto-v2-settings-remote.json"+suffix
		if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("QUEST AUTO V2 SETTINGS REMOTE UI: PASS")
	quit(0)

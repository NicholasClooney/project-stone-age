extends "res://tests/quest_auto_background_ui_test.gd"
## Synthetic authority snapshots only: this does not prove any delivery route.
func run() -> void:
	root.gui_embed_subwindows=true
	root.content_scale_size=Vector2i.ZERO
	for dimensions in [Vector2i(1280,720),Vector2i(390,844)]:
		root.size=dimensions
		if not await create_world():return
		world.set_process(false)
		var chip=world.find_child("QuestAutoChip",true,false)
		var menu=world.quest_helper_menu
		menu.open_menu()
		for job in [12,13,24,25,5,9]:
			menu.select_quest(job)
			var entry=menu.find_child("QuestAutoStart_%d"%job,true,false)
			if not check(is_instance_valid(entry) and entry.text=="自动推进","Reviewed job exposes original-route entry %d"%job):return
		menu.select_quest(23)
		if not check(menu.find_child("QuestAutoStart_23",true,false)==null,"Goya pet exchange has no automatic entry"):return
		menu.close_menu()
		world.state.derived.quest_auto={"running":true,"quest_id":11,"strict_walk":true,"phase":"walking","message":"正在原路前往交付地点","pause_reason":""}
		if not await ready(func():return chip.visible and chip.restore_button.text.contains("连续原路自动推进"),"Strict snapshot labels original walking"):return
		if not check(chip.restore_button.text.contains("正在原路前往交付地点"),"Authority message is not replaced by helper step"):return
		var generation:int=world.quest_helper_travel.generation
		world.battle_view.show()
		world.quest_helper_travel._process(0)
		if not check(world.quest_helper_travel.generation==generation,"Strict battle remains server-owned, not cancelled by UI"):return
		world.battle_view.hide()
		world.state.derived.quest_auto.detached=true
		if not await ready(func():return chip.restore_button.text.contains("等待设备确认"),"Detached snapshot explains wait"):return
		world.state.derived.quest_auto={"running":false,"quest_id":11,"strict_walk":true,"phase":"manual","message":"旧消息不得覆盖原因","pause_reason":"贝壳不足，请手动取得贝壳"}
		if not await ready(func():return chip.visible and chip.restore_button.text.contains("已停止") and not chip.stop_button.visible,"Manual handoff stays visible without running controls"):return
		if not check(chip.restore_button.text.contains("贝壳不足") and not chip.restore_button.text.contains("旧消息"),"Manual reason has precedence"):return
		if not check(root.get_visible_rect().encloses(chip.get_global_rect()),"Manual chip fits viewport"):return
		if not await click(chip.restore_button):return
		if not await ready(func():return menu.visible and menu.selected_id==11 and not chip.visible,"Manual chip reopens the correct quest"):return
		if not check(menu.find_child("QuestAutoStop",true,false)==null,"Manual phase does not show background stop"):return
		var action=menu.find_child("QuestAutoStart_11",true,false)
		if not check(is_instance_valid(action),"Manual handoff offers explicit restart"):return
		if not check(menu.find_child("QuestAutoMessage",true,false).text.contains("贝壳不足"),"Menu shows true handoff reason"):return
		world.state.derived.quest_auto.pause_reason="战斗失败，请手动处理"
		if not await ready(func():return menu.find_child("QuestAutoMessage",true,false).text.contains("战斗失败"),"Reason updates without helper model change"):return
		world.quest_helper_travel._process(0)
		if not check(not world.quest_helper_travel.active and not backend_node.quest_auto.running,"Rendering handoff never starts or resumes automation"):return
		menu.close_menu()
		world.state.derived.quest_auto={"running":true,"quest_id":11,"phase":"travel","message":"便捷任务传送"}
		if not await ready(func():return chip.restore_button.text.contains("便利导航模式"),"Old snapshot remains explicitly convenience mode"):return
		if not check(not chip.restore_button.text.contains("原路"),"Old task is not mislabeled original walking"):return
		world.state.derived.quest_auto={"running":false,"phase":"done"}
		if not await ready(func():return not chip.visible,"Completed snapshot removes chip"):return
		world.music.stop();world.effect.stop();world.queue_free()
		if not await ready(func():return not is_instance_valid(world),"Synthetic world disposed"):return
	print("QUEST DELIVERY UI SYNTHETIC: PASS")
	quit(0)

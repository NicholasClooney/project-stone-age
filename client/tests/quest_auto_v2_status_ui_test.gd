extends "res://tests/quest_auto_background_ui_test.gd"
## Synthetic projections: proves state presentation, not actual quest transactions.
func run()->void:
	root.content_scale_size=Vector2i.ZERO
	for dimensions in [Vector2i(390,844),Vector2i(1280,720)]:
		root.size=dimensions
		if not await create_world():return
		world.set_process(false)
		var menu=world.quest_helper_menu
		var chip=world.find_child("QuestAutoChip",true,false)
		world.state.derived.quest_auto={"running":true,"quest_id":12,"strict_walk":true,"phase":"waiting_reward","run_id":"run-ui","step_id":"reward-ui","revision":3,"settings":{"mode":"C","loot_minutes":30},"effective_mode":"A","budget":{},"message":"请选择奖励","waiting":{"kind":"reward","token":"fixture-token","npc_id":"fixture-npc"}}
		if not await ready(func():return chip.visible and chip.restore_button.text.contains("等待选择奖励"),"Reward wait has own chip heading"):return
		if not check(not world.quest_helper_travel.auto_status().contains("分钟"),"Empty budget never invents counters"):return
		if not check(world.quest_helper_travel.auto_mode().contains("实际 A") and world.quest_helper_travel.auto_mode().contains("意图 C 尚未生效"),"Requested C is not presented as active C"):return
		menu.open_menu()
		menu.select_quest(12)
		if not await ready(func():return menu.visible and menu.find_child("QuestAutoStop",true,false)!=null,"Waiting reward remains cancellable"):return
		if not check(menu.find_child("QuestAutoContinue",true,false)==null and menu.find_child("QuestAutoStart_12",true,false)==null,"Reward wait offers neither Boss continue nor new start"):return
		world.state.derived.quest_auto.phase="waiting_boss"
		world.state.derived.quest_auto.can_continue=false
		if not await ready(func():return menu.find_child("QuestAutoContinue",true,false)!=null,"Boss wait exposes explicit continuation"):return
		if not check(menu.find_child("QuestAutoContinue",true,false).disabled,"Boss cannot continue before authority permits"):return
		world.state.derived.quest_auto.can_continue=true
		if not await ready(func():return not menu.find_child("QuestAutoContinue",true,false).disabled,"Saved Boss win may enable continuation"):return
		world.state.derived.quest_auto.phase="battle"
		if not await ready(func():return menu.find_child("QuestAutoContinue",true,false)==null,"Ordinary battle never offers Boss continue"):return
		world.state.derived.quest_auto.budget={"step_id":"loot","limit_seconds":1800,"used_seconds":60,"saved_battles":3,"new_items":2,"existing_items":5}
		if not check(world.quest_helper_travel.auto_status().contains("1.0 / 30.0 分钟") and world.quest_helper_travel.auto_status().contains("已保存 3 场") and world.quest_helper_travel.auto_status().contains("本步新增 2 · 已有 5"),"Budget projection keeps elapsed, fights, new and existing separate"):return
		if not await click(menu.find_child("QuestAutoSettingsOpen",true,false)):return
		if not await ready(func():return menu.find_child("QuestAutoSettings",true,false)!=null,"Settings entry opens independent page"):return
		var settings=menu.settings_panel
		if not check(settings.mode.selected==2 and settings.budget.value==30 and settings.feedback.text.contains("实际执行：A"),"Settings show saved intent alongside effective mode"):return
		settings.budget.value=45
		world.state.derived.quest_auto.message="服务状态变化"
		menu._process(0)
		if not check(settings.budget.value==45,"Background state changes do not erase unsaved form input"):return
		if not await click(settings.find_child("QuestAutoSettingsBack",true,false)):return
		world.state.derived.quest_auto={"running":false,"phase":"manual","quest_id":12,"pause_reason":"需手动处理"}
		if not await ready(func():return menu.find_child("QuestAutoStart_12",true,false)!=null and menu.find_child("QuestAutoContinue",true,false)==null,"Manual stop offers restart, not waiting continuation"):return
		menu.close_menu()
		world.state.derived.quest_auto={"running":false,"phase":"done"}
		world.music.stop();world.effect.stop();world.queue_free()
		if not await ready(func():return not is_instance_valid(world),"Projection fixture disposed"):return
	print("QUEST AUTO V2 STATUS UI SYNTHETIC: PASS")
	quit(0)

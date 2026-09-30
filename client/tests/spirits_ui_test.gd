extends SceneTree
## A real game client (scenes/main.tscn over its in-process backend) with
## 气力 and the healing 精灵: the status window's 气力 row, the field HUD, the
## spirit equipment in the shop and bag, a field cast from the item window,
## and the battle 精灵 menu (cost/气力, the refusal sound without 气力, a
## target click for 滋润, the hover line's 气力).
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func labels(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Label:found.append(child)
		found.append_array(labels(child))
	return found

func find(node: Node, wanted: String) -> Node:
	for child in node.get_children():
		if child.name==wanted:return child
		var inner := find(child,wanted)
		if inner!=null:return inner
	return null

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	var menu = game.adventure_menu
	game.session.gm_raise_level(-1,10)
	game.session.gm_heal(-2)
	check(game.session.gm_grant_spirits(),"GM 调试 grants the spirit equipment")
	var profile: Dictionary = game.session.snapshot()
	check(int(profile.inventory.haru_armor)==1 and int(profile.inventory.freya_robe)==1 and int(profile.inventory.teo_robe)==1 and int(profile.inventory.koyala_charm)==1,"one 哈鲁, 芙雷雅, 提欧 and 柯雅拉 each")
	menu.open_menu("status")
	await process_frame
	check(labels(menu.panel).any(func(label):return label.text=="100 / 100" and label.position==Vector2(87,154)),"the status window's 气力 row reads 100 / 100 (was 「—」)")
	menu.open_menu("inventory")
	await process_frame
	check(find(menu.panel,"ItemSlot_haru_armor")!=null and find(menu.panel,"BagIcon_koyala_charm")!=null,"the bag shows the new pieces (second row)")
	game.perform_adventure_action("equip_haru_armor")
	await process_frame
	check(game.session.snapshot().equipment.body=="haru_armor" and find(menu.panel,"Equipped_haru_armor")!=null,"double-click equipping puts 哈鲁Lv1铠2 on the body slot")
	menu.selected_item = "haru_armor"
	menu.rebuild()
	var cast = find(menu.panel,"SpiritOnSelf")
	check(cast!=null and not cast.disabled,"a worn 治愈 offers 精灵→自己 in the item window")
	game.session._profile.player.hp = 1
	var hp_before := int(game.session.snapshot().player.hp)
	cast.pressed.emit()
	await process_frame
	var after: Dictionary = game.session.snapshot()
	check(int(after.player.hp)>hp_before and int(after.player.mp)==95 and menu.feedback.begins_with("耐久力回复"),"it heals outside battle for 5 气力 and says 耐久力回复N: %s" % menu.feedback)
	menu.hide()
	game.dev_go_adventure()
	game.begin_battle()
	await process_frame
	var view = game.battle_view
	for i in range(100):view._process(0.1)
	check(view.visible and int(game.battle_session.snapshot().player_mp)==95,"a battle opens with the player's 气力 (95)")
	check("气力 95" in view.hover_actor_text(0),"hovering the player shows 气力 (mouse.cpp:690): %s" % view.hover_actor_text(0))
	var magic_button = view.commands.filter(func(button):return str(button.get_meta("action",""))=="magic")[0]
	check(not magic_button.disabled,"the 精灵 button works with a spirit worn")
	view._request_action("magic")
	var row = find(view.choice_panel,"Spirit_body")
	check(row!=null and "治愈的精灵 Lv1" in row.text and "5/95" in row.text,"the 精灵 menu lists 治愈的精灵 Lv1 at cost/气力 5/95: %s" % (row.text if row!=null else ""))
	game.session._profile.player.hp = 10
	row.pressed.emit()
	for i in range(100):view._process(0.1)
	var state: Dictionary = game.battle_session.snapshot()
	check(int(state.turn)==1 and int(state.player_mp)==90 and "治愈的精灵" in str(state.events),"choosing it casts 治愈 on the player: the turn resolves for 5 气力")
	check(view.state.turn_frames.any(func(frame):return str(frame.get("outcome",""))=="spirit"),"the battle view plays the cast's frame")
	# Too little 气力: the entry is red and choosing it plays the refusal sound.
	game.backend.battle._state.player_mp = 3
	game.backend._refresh_battle_state()
	view.show_state(game.battle_session.snapshot())
	for i in range(100):view._process(0.1)
	var sounds: Array = []
	view.sound_requested.connect(func(ident):sounds.append(ident))
	view._request_action("magic")
	row = find(view.choice_panel,"Spirit_body")
	row.pressed.emit()
	check(220 in sounds and view.hint.text=="气力不足。" and int(game.battle_session.snapshot().turn)==1,"without 5 气力 the entry refuses with sound 220 and 气力不足。")
	view.cancel_selection()
	if game.battle_session.snapshot().active:game.battle_action("developer_escape")
	for i in range(300):view._process(0.1)
	game.return_from_battle()
	check(int(game.session.snapshot().player.mp)==3,"the battle's 气力 is on the profile afterwards")
	# 滋润 (MAGIC_TARGET_OTHER): the menu asks for a member of the player's side.
	game.adventure_menu.open_menu("inventory")
	game.perform_adventure_action("equip_freya_robe")
	game.adventure_menu.hide()
	game.session.gm_heal(-2)
	game.begin_battle()
	await process_frame
	for i in range(100):view._process(0.1)
	view._request_action("magic")
	row = find(view.choice_panel,"Spirit_body")
	check(row!=null and "滋润的精灵 Lv1" in row.text and "8/100" in row.text,"after 休息-like GM heal the menu shows 滋润 at 8/100")
	row.pressed.emit()
	check(view.selected_action=="spirit:body" and "请点击我方目标" in view.hint.text,"滋润 waits for a target click: %s" % view.hint.text)
	view.select_target(1)
	check(int(game.battle_session.snapshot().turn)==0,"an enemy is no target for it")
	view.select_target(0)
	for i in range(100):view._process(0.1)
	check(int(game.battle_session.snapshot().turn)==1 and int(game.battle_session.snapshot().player_mp)==92,"clicking the player casts it for 8 气力")
	if game.battle_session.snapshot().active:game.battle_action("developer_escape")
	for i in range(300):view._process(0.1)
	game.return_from_battle()

	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null;game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("SPIRITS UI: %d failures" % failures)
	quit(1 if failures else 0)

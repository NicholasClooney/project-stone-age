extends RefCounted
## The villager and merchant of the game scene (scripts/game.gd): placing the
## NPC, talking to it, and opening, closing and acting in the adventure menu
## (status, pets, items, shop, quest). The menu and the NPC stay on the game;
## see docs/technical/game-scripts.md.
var game: GameScene
const Spirits = preload("res://server/spirits.gd")


func _init(owner: GameScene) -> void:
	game = owner

func setup_npc() -> void:
	if int(game.data.map_id)==1002 and not game.mvp_manifest.is_empty():
		game.npc_data = game.mvp_manifest.merchant.duplicate(true)
	elif not FileAccess.file_exists("res://assets/legacy/samgir-npc.json"):
		return
	else:
		game.npc_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/samgir-npc.json"))
	game.npc_cell = Vector2i(game.npc_data.cell[0],game.npc_data.cell[1])
	game.navigation.set_point_solid(game.npc_cell,true)
	game.npc = Node2D.new()
	game.npc.position = game.project(Vector2(game.npc_cell))
	game.actors.add_child(game.npc)
	game.npc_sprite = Sprite2D.new()
	game.npc_sprite.texture = load("res://assets/legacy/mvp/"+str(game.npc_data.path)) if int(game.data.map_id)==1002 else load("res://assets/legacy/samgir-villager.png")
	game.npc_sprite.centered = false
	game.npc_sprite.position = Vector2(game.npc_data.offset[0],game.npc_data.offset[1])
	game.npc.add_child(game.npc_sprite)
	var label := game.text(game.npc_data.name,14)
	label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	label.position = Vector2(-28,-94)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.npc.add_child(label)

func in_talk_range(point: Vector2i) -> bool:
	var delta := (point-game.npc_cell).abs()
	# Cardinal neighbours avoid talking diagonally through blocked corners.
	return (point==Vector2i(16,15)) if int(game.data.map_id)==1002 else delta.x+delta.y == 1

func open_dialogue() -> void:
	if game.moving or not in_talk_range(game.cell):
		return
	if int(game.data.map_id)==1002:
		show_adventure_menu("shop")
		return
	game.clear_input()
	game.paused_input = true
	game.player.set_action(3)
	game.player.facing = (GameScene.SCREEN_DIRECTIONS.find(game.npc_cell-game.cell)+4)%8
	game.dialogue_name.text = game.npc_data.name
	game.dialogue_text.text = game.npc_data.text
	game.dialogue.show()
	game.play_ui_sound(202)

func close_dialogue() -> void:
	if not game.dialogue.visible:
		return
	game.play_ui_sound(203)
	game.dialogue.hide()
	game.paused_input = game.help.visible
	game.clear_input()
	game.message.text = "Click the villager to talk again, or keep exploring."

func show_adventure_menu(kind: String) -> void:
	# The old 系统 page is 设置 now (settings_menu.gd).
	if kind=="system":
		if game.settings_menu.visible:game.settings_menu.close_menu()
		else:game.settings_menu.open_menu()
		return
	if is_instance_valid(game.character_selection) and game.character_selection.visible:return
	if is_instance_valid(game.changelog_menu) and game.changelog_menu.visible:return
	if is_instance_valid(game.dev_gm_menu) and game.dev_gm_menu.visible:return
	if is_instance_valid(game.dev_map_overview) and game.dev_map_overview.visible:return
	if is_instance_valid(game.pet_training) and game.pet_training.visible:return
	if is_instance_valid(game.world_travel) and game.world_travel.overlay.visible:return
	if game.adventure_menu.visible and game.adventure_menu.kind == kind:
		close_adventure_menu()
		return
	# In a battle only the pet window (宠物, 仓库, 同种比较, 宠物记录) opens.
	if game.battle_view.visible and kind!="pets":
		game.play_battle_sound(220)
		return
	if game.moving or game.dialogue.visible or game.help.visible:return
	if kind=="shop" and (int(game.data.map_id)!=1002 or not in_talk_range(game.cell)):return
	if kind=="pets":
		var portraits := game.pet_packs()
		if not game.asset_packs.is_ready(portraits):
			game.asset_packs.ensure(portraits,func(ok: bool):if ok:show_adventure_menu(kind),"宠物图像")
			return
	if kind=="quest" and (int(game.data.map_id)!=1000 or not in_talk_range(game.cell)):return
	game.clear_input()
	game.paused_input = true
	game.classic_hud.map_panel.hide()
	game.adventure_menu.open_menu(kind)
	game.play_ui_sound(202)

func close_adventure_menu() -> void:
	game.adventure_menu.hide()
	game.release_input()
	game.clear_input()
	game.refresh_companion()
	game.checkpoint()
	game.play_ui_sound(203)

func perform_adventure_action(action: String, value: Variant = null) -> void:
	# During a battle the pet window may browse and deploy (the backend explains
	# why deploying waits); nothing else acts until the battle ends.
	if not game.adventure_menu.visible or (game.battle_view.visible and action not in ["mute","pet_preview","select_pet"]):return
	var success := false
	var note := ""
	var at_shop := int(game.data.map_id)==1002 and in_talk_range(game.cell)
	var at_villager := int(game.data.map_id)==1000 and in_talk_range(game.cell)
	match action:
		"pet_preview":
			game.adventure_menu.selected_pet = int(value)
			game.adventure_menu.refresh()
			return
		"buy_potion":success = at_shop and game.session.buy_item("potion")
		"buy_club":success = at_shop and game.session.buy_item("club")
		"buy_mirror_charm":success = at_shop and game.session.buy_item("mirror_charm")
		"sell_potion":success = at_shop and game.session.sell_item("potion")
		"sell_club":success = at_shop and game.session.sell_item("club")
		"sell_mirror_charm":success = at_shop and game.session.sell_item("mirror_charm")
		"use_potion":success = game.session.use_item("potion")
		"use_original_item":
			if game.adventure_menu.original_item_busy:return
			game.adventure_menu.original_item_busy=true
			success=game.session.use_item(str(value[0]),str(value[1]),func(reply:Dictionary):
				if not is_instance_valid(game.adventure_menu):return
				game.adventure_menu.original_item_busy=false
				game.adventure_menu.refresh(str(reply.get("note","已使用。")) if reply.get("ok",false) else "使用失败："+str(reply.get("reason","")))
			)
			note=game.session.last_note if success else game.session.last_error
		"equip":success = game.session.equip_item("club")
		"heal_pets":success = game.session.heal_carried_pets()
		"equip_mirror":success = game.session.equip_item("mirror_charm")
		"allocate_stat":success = game.session.allocate_stat(str(value),game.adventure_menu.allocation_amount)
		"distribute_stats":
			var selected: Array=[]
			for key in ["vitality","strength","toughness","dexterity"]:
				if key in game.adventure_menu.allocation_stats:selected.append(key)
			success=game.session.distribute_stats(selected)
		"select_pet":success = game.session.select_pet(int(value))
		"rename_pet":success = game.session.rename_pet(int(value),game.adventure_menu.name_edit.text)
		"accept_quest":success = at_villager and game.session.accept_quest()
		"claim_quest":success = at_villager and game.session.claim_quest()
		"heal":success = at_villager and game.session.heal()
		"save":success = game.checkpoint()
		"mute":game.toggle_mute(); success = true
		"use_spirit":
			# A field 精灵 (治愈 / 滋润): value [slot, target].
			success = game.session.use_spirit(str(value[0]),int(value[1]))
			note = game.session.last_note if success else game.session.last_error
		_:
			# The other shop rows and the 精灵 equipment (server/spirits.gd).
			var item := action.trim_prefix("buy_").trim_prefix("sell_").trim_prefix("equip_")
			if action.begins_with("buy_"):success = at_shop and game.session.buy_item(item)
			elif action.begins_with("sell_"):success = at_shop and game.session.sell_item(item)
			elif action.begins_with("equip_") and (item in Spirits.SPIRIT_ITEMS or item.begins_with("original:")):
				success = game.session.equip_item(item)
				if not success:note = game.session.last_error
	if success:
		if action!="use_original_item":game.checkpoint()
		if note.is_empty():note = "已完成。"
		if action=="claim_quest":note = "委托完成！获得石币、经验与回复药。"
		elif action=="heal":note = "你与伙伴恢复了体力。"
		elif action=="accept_quest":note = "委托已接受，出发去村外吧！"
	elif action=="select_pet" and not game.session.last_error.is_empty():note = game.session.last_error
	elif note.is_empty() and action in ["equip_mirror"] and not game.session.last_error.is_empty():note = game.session.last_error
	elif note.is_empty():note = "现在无法这样做，请检查条件、石币或数量。"
	game.adventure_menu.refresh(note)
	game.play_ui_sound(201)

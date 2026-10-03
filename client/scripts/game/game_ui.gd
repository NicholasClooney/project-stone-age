extends RefCounted
## Building the interface of the game scene (scripts/game.gd): the UI layer
## and windows (built once; there is no toolbar, the windows open from
## 游戏助手, 设置, the map window and shortcuts), the map-specific parts refreshed on every
## map change, the dialogue box, the adventure hint and the shared text,
## button and panel-style helpers every window uses (world.text() and so on).
## The controls stay on the game; see docs/technical/game-scripts.md.
const AdventureMenu = preload("res://scripts/adventure_menu.gd")
const BattleView = preload("res://scripts/battle_view.gd")
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

func box(color: Color, border: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(2)
	result.set_corner_radius_all(3)
	result.content_margin_left = 12
	result.content_margin_right = 12
	result.content_margin_top = 7
	result.content_margin_bottom = 7
	return result

func text(value: String, size: int = 15) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	label.add_theme_color_override("font_color",Color("f8edc7"))
	return label

func button(value: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = value
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size",13)
	b.add_theme_stylebox_override("normal",box(Color("574431"),Color("9d8354")))
	b.add_theme_stylebox_override("hover",box(Color("775b3c"),Color("e6c284")))
	# Every state keeps box()'s margins, so a button never changes size: the
	# engine's own disabled look is smaller and nearly invisible on these panels.
	b.add_theme_stylebox_override("pressed",box(Color("4a3826"),Color("e6c284")))
	b.add_theme_stylebox_override("hover_pressed",box(Color("5e4630"),Color("e6c284")))
	b.add_theme_stylebox_override("disabled",box(Color("2b3131"),Color("5b5d55")))
	b.add_theme_color_override("font_disabled_color",Color("9a927e"))
	b.pressed.connect(callback)
	return b

## Built once. A map change keeps every panel (and what it shows) and only
## refreshes the parts that belong to the map: see refresh_map_ui().
func build_ui() -> void:
	game.ui_layer = CanvasLayer.new()
	game.add_child(game.ui_layer)
	var root := Control.new()
	game.ui_root = root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	var font: Font = load("res://assets/fonts/NotoSansSC.ttf")
	var readable_font := FontVariation.new()
	readable_font.base_font = font
	readable_font.variation_opentype = {2003265652:450.0} # OpenType wght axis tag.
	ui_theme.default_font = readable_font
	# Tooltips are separate popups: give them their own opaque background.
	var tooltip_box := StyleBoxFlat.new()
	tooltip_box.bg_color = Color("242a2b")
	tooltip_box.border_color = Color("b49b66")
	tooltip_box.set_border_width_all(1)
	tooltip_box.content_margin_left = 12;tooltip_box.content_margin_right = 12
	tooltip_box.content_margin_top = 8;tooltip_box.content_margin_bottom = 8
	ui_theme.set_stylebox("panel","TooltipPanel",tooltip_box)
	ui_theme.set_color("font_color","TooltipLabel",Color("fff4d5"))
	root.theme = ui_theme
	game.ui_layer.add_child(root)
	game.coordinates = text("")
	game.message = text("")
	root.add_child(game.coordinates)
	root.add_child(game.message)
	game.coordinates.hide()
	game.message.hide()
	game.classic_hud = preload("res://scripts/classic_hud.gd").new()
	game.classic_hud.world = game
	root.add_child(game.classic_hud)
	game.character_selection = preload("res://scripts/character_selection.gd").new()
	game.character_selection.configure(game)
	root.add_child(game.character_selection)
	game.travel_landing=preload("res://scripts/travel_landing.gd").new()
	game.travel_landing.configure(game)
	game.leveling_destinations=preload("res://scripts/leveling_destinations.gd").new()
	game.leveling_destinations.configure(game);root.add_child(game.leveling_destinations)
	game.pet_hunt_menu = preload("res://scripts/pet_hunt_menu.gd").new()
	game.pet_hunt_menu.configure(game)
	root.add_child(game.pet_hunt_menu)
	game.training_helper = preload("res://scripts/training_helper.gd").new()
	game.training_helper.configure(game)
	root.add_child(game.training_helper)
	# 五人镜像队 lives in the 自动练级 window beside its other battle options.
	game.clone_button=CheckBox.new()
	game.clone_button.name="CloneSquadToggle";game.clone_button.text="五人镜像队"
	game.clone_button.focus_mode=Control.FOCUS_NONE
	game.clone_button.position=Vector2(560,164)
	game.clone_button.button_pressed=game.session.clone_squad_enabled
	game.clone_button.tooltip_text="复制当前出战宠与骑乘状态，本体优先，四组人宠自动跟随目标；经验仍归本体和真实宠物。下一场生效。"
	game.clone_button.toggled.connect(func(enabled):
		if not game.battle_session.snapshot().active and not game.area_transition_busy:game.set_clone_squad_enabled(enabled)
		else:game.clone_button.set_pressed_no_signal(game.session.clone_squad_enabled))
	game.training_helper.panel.add_child(game.clone_button)
	game.pet_workflow = preload("res://scripts/pet_workflow.gd").new()
	game.pet_workflow.configure(game)
	root.add_child(game.pet_workflow)
	game.radio = preload("res://scripts/radio.gd").new()
	game.radio.name = "Radio"
	game.add_child(game.radio)
	game.radio.configure(game)
	game.web_audio = preload("res://scripts/web_audio.gd").new()
	game.web_audio.name = "WebAudio"
	game.add_child(game.web_audio)
	game.web_audio.configure(game)
	game.radio_panel = preload("res://scripts/radio_panel.gd").new()
	root.add_child(game.radio_panel)
	game.radio_panel.configure(game,game.radio)
	game.pet_encyclopedia = preload("res://scripts/pet_encyclopedia_menu.gd").new()
	game.pet_encyclopedia.configure(game)
	root.add_child(game.pet_encyclopedia)
	game.changelog_menu = preload("res://scripts/changelog_menu.gd").new()
	game.changelog_menu.configure(game)
	root.add_child(game.changelog_menu)
	game.settings_menu = preload("res://scripts/settings_menu.gd").new()
	root.add_child(game.settings_menu)
	game.settings_menu.configure(game)
	game.help = game.settings_menu
	game.quest_helper_travel=preload("res://scripts/quest_helper_travel.gd").new()
	game.quest_helper_travel.configure(game)
	game.add_child(game.quest_helper_travel)
	game.quest_helper_menu=preload("res://scripts/quest_helper_menu.gd").new()
	game.quest_helper_menu.configure(game)
	root.add_child(game.quest_helper_menu)
	var quest_chip=preload("res://scripts/quest_auto_chip.gd").new()
	quest_chip.configure(game)
	root.add_child(quest_chip)
	game.helper_menu = preload("res://scripts/helper_menu.gd").new()
	root.add_child(game.helper_menu)
	game.helper_menu.configure(game)
	game.remote_players = preload("res://scripts/remote_players.gd").new()
	game.remote_players.name = "RemotePlayers"
	game.remote_players.configure(game)
	game.add_child(game.remote_players)
	game.chat_panel = preload("res://scripts/chat_panel.gd").new()
	root.add_child(game.chat_panel)
	game.chat_panel.configure(game)
	game.party_panel = preload("res://scripts/party_panel.gd").new()
	root.add_child(game.party_panel)
	game.party_panel.configure(game)
	build_dialogue(root)
	game.adventure_menu = AdventureMenu.new()
	game.adventure_menu.configure(game)
	root.add_child(game.adventure_menu)
	game.pet_training = preload("res://scripts/pet_training.gd").new()
	game.pet_training.configure(game)
	root.add_child(game.pet_training)
	game.dev_map_overview = preload("res://scripts/dev_map_overview.gd").new()
	game.dev_map_overview.configure(game)
	root.add_child(game.dev_map_overview)
	game.dev_gm_menu=preload("res://scripts/dev_gm_menu.gd").new()
	game.dev_gm_menu.configure(game)
	root.add_child(game.dev_gm_menu)
	game.adventure_hint = text("",14)
	# Below the classic top-left icons and the 游戏助手 button.
	game.adventure_hint.position = Vector2(18,126)
	game.adventure_hint.add_theme_color_override("font_shadow_color",Color.BLACK)
	game.adventure_hint.add_theme_constant_override("shadow_offset_x",1)
	game.adventure_hint.add_theme_constant_override("shadow_offset_y",1)
	game.adventure_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(game.adventure_hint)
	# The one button of this project on the field: everything else is in its list.
	game.helper_button = button(helper_caption(),func(): game.helper_menu.open_menu())
	game.helper_button.name = "HelperButton"
	game.helper_button.tooltip_text = "本项目加入的功能：自动练级、自动抓极品、电台、地图导航、刷怪传送等"
	game.helper_button.position = Vector2(14,88)
	root.add_child(game.helper_button)
	game.battle_view = BattleView.new()
	root.add_child(game.battle_view)
	# Just above the classic HUD: the windows a battle allows (宠物, 设置,
	# 游戏助手, 电台, 宠物大全) come later in the tree, so they take clicks
	# before the battle; their z_index already draws them above it.
	root.move_child(game.battle_view,game.classic_hud.get_index()+1)
	game.battle_view.configure(game)
	game.battle_view.playback_speed=game.playback_speed()
	game.battle_view.action_requested.connect(game.battle_action)
	game.battle_view.return_requested.connect(game.return_from_battle)
	game.battle_view.sound_requested.connect(game.play_battle_sound)
	game.battle_view.capture_music_requested.connect(game._audio.capture_music)
	game.showcase_ticker = preload("res://scripts/showcase_ticker.gd").new()
	root.add_child(game.showcase_ticker)
	game.showcase_ticker.configure(game)
	game.battle_view.pet_command_requested.connect(func(command: String):
		if command == "skill": game.battle_session.set_pet_skill(int(game.battle_view.get("selected_pet_skill")))
		else: game.battle_session.set_pet_command(command))
	refresh_map_ui()

## The map-specific parts of the UI: the residents with their travel
## dialogue, and the HUD's map window.
func refresh_map_ui() -> void:
	game.world_travel = preload("res://scripts/world_travel.gd").new()
	game.actors.add_child(game.world_travel)
	game.world_catalog.quest_catalog.npc_overrides=game.state.derived.get("quest_npcs",{}).duplicate(true)
	game.world_catalog.set_quest_catalog(game.world_catalog.quest_catalog)
	var residents: Array = []
	for entry in game.world_catalog.residents:
		if int(entry.map_id)==int(game.data.map_id) and Vector2i(entry.cell[0],entry.cell[1])!=game.npc_cell:residents.append(entry)
	game.world_travel.setup(game,game.ui_root,residents)
	if is_instance_valid(game.classic_hud) and game.classic_hud.is_node_ready():game.classic_hud.refresh_map()

## Whether a panel that stops walking is open; a map change keeps panels open.
## A minimized automation window is hidden, so it does not count; see
## automation_minimized() for how it still holds the character in place.
func _panel_open() -> bool:
	for node in [game.quest_helper_menu,game.leveling_destinations,game.training_helper,game.pet_hunt_menu,game.changelog_menu,game.character_selection,game.dev_gm_menu,game.dev_map_overview,game.pet_training,game.adventure_menu,game.help,game.helper_menu,game.pet_encyclopedia]:
		if is_instance_valid(node) and node.visible:return true
	return false

func update_adventure_hint() -> void:
	if not is_instance_valid(game.adventure_hint):return
	game.adventure_hint.visible = not game.battle_view.visible and not game.adventure_menu.visible and not game.dialogue.visible
	if is_instance_valid(game.helper_button):
		game.helper_button.visible = not game.battle_view.visible and not game.dialogue.visible
		game.helper_button.text = helper_caption()
	var profile: Dictionary = game.session.snapshot()
	# Only the status: the early quest's goals (村外的伙伴) no longer lead anywhere.
	game.adventure_hint.text = "Lv.%d  体力 %d/%d  气力 %d  石币 %d" % [profile.player.level,profile.player.hp,profile.player.max_hp,int(profile.player.get("mp",100)),profile.player.gold]
	if not game.last_adventure_message.is_empty():game.adventure_hint.text += "\n"+game.last_adventure_message

## 游戏助手 with its current key (快捷键 can rebind it).
func helper_caption() -> String:
	for event in InputMap.action_get_events("helper") if InputMap.has_action("helper") else []:
		if event is InputEventKey:
			var code: int = event.physical_keycode if event.physical_keycode!=0 else event.keycode
			if code!=0:return "游戏助手 [%s]" % OS.get_keycode_string(code)
	return "游戏助手"

## The original box is 384 x 192 at x1.25, centred and at y 450 of 800.
## On another screen it keeps that scale while it fits (16 px either side),
## shrinks on a narrow one, and keeps the same share of the height above the
## bottom bar.
func place_dialogue(panel: Control) -> void:
	var screen: Vector2 = game.dialogue.size if game.dialogue.size.x > 0 else Vector2(1280,800)
	var scale := minf(game.classic_hud.SCALE,(screen.x-32)/384.0)
	panel.scale = Vector2.ONE*scale
	var bottom: float = game.classic_hud.bar.size.y if is_instance_valid(game.classic_hud) and is_instance_valid(game.classic_hud.bar) else 30.0
	var top := minf(screen.y*450.0/800.0,screen.y-bottom-8-192*scale)
	panel.position = Vector2((screen.x-384*scale)/2,maxf(8,top))

func build_dialogue(root: Control) -> void:
	game.dialogue = Control.new()
	game.dialogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.dialogue.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(game.dialogue)
	var panel := Control.new()
	panel.name = "OriginalDialogue"
	panel.size = Vector2(384,192)
	game.dialogue.add_child(panel)
	# Placed for the screen it is on (a phone in portrait, 界面大小): centred,
	# where the original puts it on 1280 x 800, and smaller on a narrow screen.
	game.dialogue.resized.connect(func():place_dialogue(panel))
	place_dialogue(panel)
	# WindowDisp composes a stone frame from the original 64×48 tiles.
	for y in range(4):
		for x in range(6):
			var row := 0 if y==0 else (2 if y==3 else 1)
			var column := 0 if x==0 else (2 if x==5 else 1)
			game.classic_hud.picture(panel,26001+row*3+column,Vector2(x*64,y*48))
	game.dialogue_name = text("",15)
	game.dialogue_name.position = Vector2(18,15)
	game.dialogue_name.add_theme_color_override("font_color",Color.YELLOW)
	game.dialogue_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(game.dialogue_name)
	game.dialogue_text = text("",15)
	game.dialogue_text.position = Vector2(18,45)
	game.dialogue_text.size = Vector2(348,90)
	game.dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.dialogue_text.add_theme_color_override("font_color",Color.WHITE)
	game.dialogue_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(game.dialogue_text)
	var button_art: Texture2D = game.classic_hud.art[26091]
	var close_button: TextureButton = game.classic_hud.icon(panel,26091,26091,Vector2((384-button_art.get_width())/2.0,156),"确定 · Enter / Esc")
	close_button.name = "ConfirmDialogue"
	close_button.pressed.connect(game.close_dialogue)
	var quest_choice := Button.new()
	quest_choice.text = "村外的伙伴 / 休息"
	quest_choice.position = Vector2(105,112)
	quest_choice.size = Vector2(190,30)
	quest_choice.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	quest_choice.add_theme_stylebox_override("hover",StyleBoxEmpty.new())
	quest_choice.pressed.connect(func(): game.close_dialogue(); game.show_adventure_menu("quest"))
	panel.add_child(quest_choice)
	game.dialogue.hide()

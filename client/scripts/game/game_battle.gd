extends RefCounted
## Battles for the game scene (scripts/game.gd): asking the backend to start
## one, presenting what it opened, resolved and closed, sending the player's
## commands, and the art packs a battle needs on the web. The battle view and
## the field state stay on the game; see docs/technical/game-scripts.md.
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

func begin_battle(boss: bool = false, enemy_count: int = 0) -> bool:
	if game.moving or game.paused_input or not game.world_catalog.field(int(game.data.map_id)) or game.battle_view==null:
		return false
	if not preload("res://scripts/battle_art.gd").present():
		game.message.text = "Import original battle assets first; see README.md."
		return false
	var reply: Dictionary = game.link.request({"type":"begin_battle","boss":boss,"enemy_count":enemy_count})
	return bool(reply.ok) or bool(reply.get("pending",false))

func begin_wild_battle() -> bool:
	game.last_encounter_error=""
	if game.moving or game.paused_input or game.area_transition_busy or game.battle_view==null or game.battle_view.visible:return false
	if not game.world_catalog.field(int(game.data.map_id)):return false
	var reply: Dictionary = game.link.request({"type":"wild_encounter","map_id":int(game.data.map_id),"cell":[game.cell.x,game.cell.y]},_on_encounter_reply)
	return bool(reply.ok) or bool(reply.get("pending",false))

func _on_encounter_reply(reply: Dictionary) -> void:
	var skipped := str(reply.get("skipped",""))
	if skipped.is_empty():return
	game.last_encounter_error=skipped
	if skipped=="data":
		game.message.text = "这里没有可用的普通野外遇敌。" if str(reply.reason).is_empty() else "此区域的原版遇敌数据或条件尚未完整支持，暂时跳过。"
	elif skipped=="art":
		game.message.text = "本次敌群的原版动画缺失或损坏，已跳过；未替换敌人。"

## No battle view for this battle: compact 自动练级, or a party member's
## 组队自动战斗 with 快速战斗 (LAN phase 4c, party_panel.gd compact_battle).
func compact_view() -> bool:
	return (is_instance_valid(game.training_helper) and game.training_helper.compact_active) or game.party_compact()

func open_battle_config(config: Dictionary) -> bool:
	if config.is_empty():return false
	var reply: Dictionary = game.link.request({"type":"open_battle","config":config})
	return bool(reply.ok) or bool(reply.get("pending",false))

## Presentation for a battle the backend has just opened.
func present_battle_start(battle_state: Dictionary) -> bool:
	if game.asset_packs.enabled and not compact_view():
		var needed := battle_packs(battle_state)
		if not game.asset_packs.is_ready(needed):
			game.clear_input()
			game.paused_input = true
			var battle_id := str(battle_state.get("battle_id",""))
			game.asset_packs.ensure(needed,func(ok: bool):
				if ok and game.state.battle_open and str(game.state.battle.get("battle_id",""))==battle_id and not game.battle_view.visible:present_battle_start(game.state.battle)
				elif not ok and is_instance_valid(game.message):game.message.text = "战斗素材下载失败，战斗仍在进行；稍后重试。","战斗素材")
			return true
	if is_instance_valid(game.travel_router):game.travel_router.cancel("战斗中断了自动寻路，请重新选择目的地。")
	game.clear_input()
	game.paused_input = true
	game.player.set_action(3)
	game.classic_hud.map_panel.hide()
	if compact_view():
		return true
	# Windows a battle allows (宠物, 设置, 游戏助手, 电台, 宠物大全) stay open
	# above it; the battle waits for commands until they close.
	game.battle_view.open_battle(battle_state)
	refresh_pet_window()
	var manifest: Dictionary = preload("res://scripts/battle_art.gd").index()
	if game.showcase_music_active():game.begin_showcase_music()
	game._audio.begin_battle_music(game.music_track("res://assets/legacy/battle/"+str(manifest.audio.bgm)))
	game.play_battle_sound(215)
	return true

## The pet window open over a battle greys its participants (出战中, 骑乘中,
## 削血宠); it redraws when the battle starts and ends so the locks follow.
func refresh_pet_window() -> void:
	if game.adventure_menu.visible and not game._typing_in(game.adventure_menu):game.rebuild_keeping_scroll(game.adventure_menu)

## Whether a window a battle allows is open over it (宠物, 设置, 游戏助手,
## 电台, 宠物大全, the automation windows): battle commands wait meanwhile.
func battle_window_open() -> bool:
	for node in [game.adventure_menu,game.settings_menu,game.helper_menu,game.radio_panel,game.pet_encyclopedia,game.training_helper,game.pet_hunt_menu,game.dev_gm_menu]:
		if is_instance_valid(node) and node.visible:return true
	return false

func battle_action(action: String) -> void:
	if not game.battle_view.visible and not (is_instance_valid(game.training_helper) and game.training_helper.compact_active):
		return
	var target: int = int(game.battle_view.get("player_target"))
	game.battle_session.set_pet_target(int(game.battle_view.get("pet_target")))
	var skill_id: int = int(game.battle_view.get("selected_pet_skill"))
	if skill_id > 0 and game.battle_session.snapshot().pet_command == "skill":
		game.battle_session.set_pet_skill(skill_id)
	if action=="developer_escape":game.battle_session.developer_escape()
	else:game.battle_session.submit_action(action,target,int(game.battle_view.get("switch_pet_index")))

## Presentation for one resolved turn, from the player or a backend runner.
func present_battle_turn(battle_state: Dictionary) -> void:
	if battle_state.get("settled",false):
		game.checkpoint()
		refresh_pet_window()
	if compact_view():return
	if not is_instance_valid(game.battle_view) or not game.battle_view.visible:return
	game.battle_view.show_state(battle_state)
	game.play_ui_sound(217 if game.ui_sounds.has(217) else 201)

func return_from_battle() -> void:
	var compact_battle: bool=compact_view()
	if (not game.battle_view.visible and not compact_battle) or game.battle_session.snapshot().active or (not compact_battle and game.battle_view.is_animating()):
		return
	game.link.request({"type":"battle_close"})

## Presentation after the backend closed a battle.
func present_battle_close(outcome: String) -> void:
	if game.battle_view.visible:game._audio.close_battle_music()
	game.battle_view.close_battle()
	game.clear_input()
	# A window opened during the battle keeps the field paused.
	game.paused_input = game.automation_minimized() or game._panel_open()
	game.field_steps = 0
	game.play_ui_sound(203)
	if outcome=="defeat":
		game.switch_area(false,GameScene.SPAWN)
	game.refresh_companion()
	game.checkpoint()
	# The battle's pets are free again: the pet window drops their locks.
	refresh_pet_window()
	# A running automation keeps the map locked between its battles.
	if bool(game.state.automation.get("running",false)):game.paused_input = true

## Battle art packs for one battle state; also fixes its background choice.
func battle_packs(battle_state: Dictionary) -> Array:
	var art: Dictionary = game.battle_view.required_art(battle_state)
	var packs: Array = []
	for ident in art.sprites:packs.append(game.asset_packs.sprite_pack(ident))
	for ident in art.riding:packs.append(game.asset_packs.riding_pack(ident))
	for path in art.files:packs.append(game.asset_packs.file_pack(path))
	return packs

func dev_encounter() -> void:
	if game.paused_input or game.area_transition_busy or game.battle_view.visible:return
	# Force a source-backed local encounter; move to Samgir wilderness only from a safe map.
	if game.moving:
		game.moving = false
		game.logical_position = Vector2(game.cell)
		game.player.position = game.project(game.logical_position)
	game.clear_input()
	if not game.world_catalog.field(int(game.data.map_id)):
		if not game.switch_area(true,Vector2i(45,45)):return
	begin_wild_battle()

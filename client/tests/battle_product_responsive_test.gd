extends SceneTree
## Production GameScene, real Backend/Battle and product mouse/controller routing.
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
var game
var view
const SIZES = [Vector2i(1280,720),Vector2i(800,800),Vector2i(720,1280),Vector2i(390,844)]
const SHOTS = "/private/tmp/battle-responsive-fix-shots/"
func _initialize(): run.call_deferred()
func check(ok: bool, note: String):
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok: failures+=1
func settle():
	check(await Wait.until(self,func():
		view._process(0.1)
		return not view.is_animating()),"presentation reaches input phase")
	view._process(0)
func click(control: Control):
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new(); motion.position=at
	root.push_input(motion,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=at; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=down
		root.push_input(event,true)
	await process_frame
	view._process(0)
func press(button: JoyButton):
	for down in [true,false]:
		var event := InputEventJoypadButton.new(); event.button_index=button; event.pressed=down
		Input.parse_input_event(event)
		await process_frame
	view._process(0)
func photograph(name: String, dimensions: Vector2i):
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size()==dimensions,"native pixels match requested "+str(dimensions))
	image.save_png(SHOTS+"%s-%dx%d.png"%[name,dimensions.x,dimensions.y])
func geometry(note: String):
	var viewport := Rect2(Vector2.ZERO,view.size)
	var menu: Rect2 = view.player_menu_rect()
	check(menu.position.y>=0 and menu.end.y<view.size.y*0.3 and absf(menu.end.x-view.size.x)<24*view.stage.scale.x,"PLAYER actual rect stays top right "+note)
	check(view.command_panel.z_index>view.arena.z_index and view.choice_panel.z_index>view.arena.z_index,"menus draw above camps "+note)
	check(view.battlefield.get_rect()==viewport,"cover fills viewport "+note)
	var camps := [[],[]]
	for i in range(view.actors.size()):
		var sprite: Sprite2D = view.actors[i].sprite
		if not sprite.visible or sprite.texture==null: continue
		var box := sprite.get_global_transform()*Rect2(Vector2.ZERO,sprite.texture.get_size())
		check(viewport.encloses(box),"actor %d inside viewport %s"%[i,note])
		check(not menu.intersects(box),"actor %d avoids PLAYER rect %s"%[i,note])
		if view.choice_panel.visible and view.choice_panel.get_child_count()>0:
			check(not view.menu_rect(view.choice_panel).intersects(box),"actor %d avoids active choices %s"%[i,note])
		check(view.target_buttons[i].get_global_rect().is_equal_approx(box),"input rect follows actor %d %s"%[i,note])
		camps[0 if view.enemy_index(i)>=0 else 1].append(box)
	for enemy in camps[0]:
		for friend in camps[1]: check(not enemy.intersects(friend),"opposing sprite bounds separate "+note)
func finish():
	if game.battle_session.snapshot().active: game.battle_action("developer_escape")
	await settle()
	game.return_from_battle()
	check(root.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_KEEP,"leaving battle restores original map canvas aspect")
	game.session.gm_heal()
func run():
	DirAccess.make_dir_recursive_absolute(SHOTS)
	root.size=SIZES[0]
	game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game)
	await process_frame
	view=game.battle_view
	view.set_process(false)
	game.load_area_id(100,Vector2i(637,493))
	check(game.session.grant_starter_pets() and game.session.select_pet(0) and game.session.set_character("100010") and game.session.mount_pet(1),"configure mounted player and independent pet through session")
	for scenario in ["single","five-mirrors"]:
		game.clone_button.button_pressed=scenario=="five-mirrors"
		for dimensions in SIZES:
			root.size=dimensions
			await process_frame
			if scenario=="five-mirrors":
				var catalog=preload("res://server/encounter_catalog.gd").new()
				var rng:=RandomNumberGenerator.new();rng.seed=892
				var actor: Dictionary=catalog.actor(120,rng)
				actor.can_capture=true
				var enemies:=[]
				for i in range(10):enemies.append(actor.duplicate(true))
				var config: Dictionary=game.session.start_wild_battle_config({"enemies":enemies})
				check(not config.is_empty(),"backend issues complete original ten-enemy troop")
				check(game.open_battle_config(config),"real Backend opens ten-enemy squad config")
			else:check(game.begin_battle(false,3),"real Backend starts "+scenario)
			await settle()
			geometry("%s %s"%[scenario,dimensions])
			if scenario=="five-mirrors":check(view.actors.size()==20 and view.enemies_of(view.state).size()==10,"real squad supplies ten enemies, five riders and five pets")
			await photograph(scenario,dimensions)
			var turn: int=game.battle_session.snapshot().turn
			await click(view.commands[0])
			await click(view.target_buttons[4])
			check(view.command_phase=="pet" and view.player_target==2 and game.battle_session.snapshot().turn==turn,"real mouse enemy index2 enters pet phase")
			await settle()
			var pet_attack: Button
			for child in view.choice_panel.get_children():
				if child is Button and child.text=="攻击":pet_attack=child
			check(pet_attack!=null,"product pet command panel appears")
			geometry("pet-phase %s %s"%[scenario,dimensions])
			await photograph(scenario+"-pet-phase",dimensions)
			if pet_attack!=null:await click(pet_attack)
			await click(view.target_buttons[1])
			check(game.battle_session.snapshot().turn==turn+1,"product mouse commands resolve exactly one authority turn")
			await click(view.commands[0]); await click(view.target_buttons[1])
			check(game.battle_session.snapshot().turn==turn+1,"rapid product input cannot submit during animation")
			await settle()
			await photograph(scenario+"-after-turn",dimensions)
			await finish()
	# Gamepad A uses the product's synthetic mouse routing at every size.
	game.clone_button.button_pressed=false
	for dimensions in SIZES:
		root.size=dimensions; await process_frame
		check(game.begin_battle(false,3),"real backend starts controller battle")
		await settle()
		game.gamepad.target=view.commands[0]
		await press(JOY_BUTTON_A)
		check(view.target_buttons[1] in game.gamepad.candidates(view),"controller can reach real enemy at "+str(dimensions))
		game.gamepad.target=view.target_buttons[1]
		await press(JOY_BUTTON_A)
		check(view.command_phase=="pet" and view.player_target==0,"controller A commands and targets at "+str(dimensions))
		await settle()
		for child in view.choice_panel.get_children():
			if child is Button and child.text=="攻击":game.gamepad.target=child;break
		await press(JOY_BUTTON_A)
		game.gamepad.target=view.target_buttons[1]
		await press(JOY_BUTTON_A)
		check(game.battle_session.snapshot().turn==1,"controller player and pet commands resolve a real turn at "+str(dimensions))
		await finish()
	# Real capture response while resizing; effects follow the same arena mapping.
	root.size=SIZES[0]; await process_frame
	check(game.begin_battle(false,3),"real backend starts capture battle")
	await settle()
	await click(view.commands[2]); await click(view.target_buttons[1]); await settle()
	for child in view.choice_panel.get_children():
		if child is Button and child.text=="防御":
			await click(child)
			break
	check(game.battle_session.snapshot().turn==1 and view.captures_presented>0,"backend capture result schedules mounted capture presentation")
	view._process(1.2)
	view.mirror_cues.append({"at":view.elapsed,"id":100610,"index":0})
	view._process(0)
	view.battle_effects.impact(view.actors[1].point,77)
	for dimensions in SIZES:
		root.size=dimensions; await process_frame
		view.layout();view._process(0)
		check(view.mirror_effects[0].position.is_equal_approx(view.responsive.point(view.mirror_effects[0].get_meta("native_point"))),"mirror follows resize "+str(dimensions))
		check(not view.battle_effects.active.is_empty(),"impact survives resize "+str(dimensions))
		await photograph("capture-effects",dimensions)
	await finish()
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	print("BATTLE PRODUCT RESPONSIVE: %d failures"%failures)
	quit(1 if failures else 0)

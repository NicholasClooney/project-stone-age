extends SceneTree
const Battle = preload("res://server/battle_session.gd")
var failures := 0
var view
var production_canvas := OS.get_environment("BATTLE_RESPONSIVE_CANVAS")!="0"
var shot_prefix := "canvas-" if production_canvas else ""
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok: failures+=1
func run():
	if production_canvas:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_size = Vector2i(1280,800)
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	else: root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	view = preload("res://scripts/battle_view.gd").new()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	var authority = Battle.new()
	var mount := {"name":"金虎","sprite":100330,"hp":100,"max_hp":100}
	var initial: Dictionary = authority.start_battle({"player_hp":500,"player_max_hp":500,"enemy_max_hp":1000,"pets":[mount,{"name":"乌力","sprite":100250,"hp":100,"max_hp":100}],"active_pet":1,"ride_pet_index":0,"ride_pet":mount,"mounted_sprite":101006})
	initial.allies = []
	for i in range(4): initial.allies.append({"name":"分身%d"%i,"character_id":100000,"mounted_sprite":101006,"hp":100,"max_hp":100})
	initial.ally_pets = []
	for i in range(4): initial.ally_pets.append({"name":"队友乌力%d"%i,"sprite":100250,"hp":100,"max_hp":100})
	for scenario in ["single","party"]:
		var state := initial.duplicate(true)
		if scenario=="single": state.erase("allies"); state.erase("ally_pets")
		else:
			while state.enemies.size()<10: state.enemies.append(state.enemies[0].duplicate(true))
		view.open_battle(state)
		view._process(view.feedback_until+0.1)
		for dimensions in [Vector2i(1280,720),Vector2i(800,800),Vector2i(720,1280),Vector2i(390,844)]:
			root.size = dimensions
			await process_frame
			view.open_battle(state)
			view._process(view.feedback_until+0.1)
			view.size = root.get_visible_rect().size
			view.layout()
			view._process(0)
			check(view.battlefield.get_rect()==Rect2(Vector2.ZERO,view.size),"background fills %s %s"%[scenario,dimensions])
			for actor in view.actors:
				if not actor.sprite.visible or actor.sprite.texture==null: continue
				var box := Rect2(actor.sprite.global_position,actor.sprite.texture.get_size()*view.arena.scale)
				check(Rect2(Vector2.ZERO,view.size).encloses(box),"visible actor inside viewport %s %s"%[scenario,dimensions])
			var opponents: Array[Rect2] = []
			var friends: Array[Rect2] = []
			for i in range(view.actors.size()):
				var actor: Dictionary = view.actors[i]
				if not actor.sprite.visible or actor.sprite.texture==null: continue
				var box := Rect2(actor.sprite.global_position,actor.sprite.texture.get_size()*view.arena.scale)
				if view.enemy_index(i)>=0: opponents.append(box)
				else: friends.append(box)
			for enemy in opponents:
				for friend in friends: check(not enemy.intersects(friend),"opposing sprites do not overlap %s %s"%[scenario,dimensions])
			check(view.target_buttons[1].get_global_rect().is_equal_approx(Rect2(view.actors[1].sprite.global_position,view.actors[1].sprite.texture.get_size()*view.arena.scale)),"actual target bounds track sprite")
			if DisplayServer.get_name()!="headless":
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/private/tmp/battle-responsive-shots/%s%s-%dx%d.png"%[shot_prefix,scenario,dimensions.x,dimensions.y])
			view._request_action("attack")
			view._process(0)
			var chosen := 4 if scenario=="party" else 1
			var button: Button = view.target_buttons[chosen]
			view.player_target = -1
			var at := button.get_global_rect().get_center()
			# Keep the synthetic click atomic: an offscreen native window can
			# receive OS mouse-leave events between frames while resizing.
			var motion := InputEventMouseMotion.new()
			motion.position = at
			root.push_input(motion,true)
			var press := InputEventMouseButton.new()
			press.position = at; press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
			root.push_input(press,true)
			press = press.duplicate(); press.pressed = false
			root.push_input(press,true)
			await process_frame
			check(view.player_target==view.enemy_index(chosen),"real target click %s %s"%[scenario,dimensions])
			view.cancel_selection()
			print("LAYOUT %s %s vertical=%s scale=%s"%[scenario,dimensions,view.responsive.vertical,view.responsive.factor])
	# Capture and mirror effects use the same coordinate mapping during resize.
	view.open_battle(initial)
	view._process(view.feedback_until+0.1)
	var timing: Dictionary = view.queue_capture(view.elapsed,true)
	view.feedback_until = timing.end
	view._process(1.2)
	view.mirror_cues.append({"at":view.elapsed,"id":100610,"index":0})
	view._process(0.01)
	view.battle_effects.impact(view.actors[1].point,77)
	for dimensions in [Vector2i(1280,720),Vector2i(800,800),Vector2i(720,1280),Vector2i(390,844)]:
		root.size = dimensions
		await process_frame
		view.size = root.get_visible_rect().size; view.layout(); view._process(0)
		check(view.mirror_effects[0].position.is_equal_approx(view.responsive.point(view.mirror_effects[0].get_meta("native_point"))),"mirror follows resized arena")
		check(view.battle_effects.active.size()>0,"damage effects survive resized arena")
		if DisplayServer.get_name()!="headless":
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/battle-responsive-shots/%scapture-effects-%dx%d.png"%[shot_prefix,dimensions.x,dimensions.y])
	view.queue_free()
	await process_frame
	quit(1 if failures else 0)

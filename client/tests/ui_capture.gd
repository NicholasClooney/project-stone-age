extends SceneTree
var game
func _initialize() -> void:
	call_deferred("run")
func snapshot(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/"+name+".png"))
func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	game.paused_input=true
	var hud=game.classic_hud
	# Deterministic render states; UI interaction is covered by headless ui_smoke.
	hud.set_process_input(false)
	hud.pointer_position=Vector2(650,790)
	hud._process(1)
	hud.set_process(false)
	hud.toggle_map()
	await snapshot("classic-ui-map")
	hud.toggle_map()
	hud.pointer_position=Vector2.ZERO
	hud._process(1)
	game.maximum_zoom_out()
	await snapshot("classic-ui-zoom-out")
	game.set_zoom(1)
	await snapshot("classic-ui")
	game.music.stop()
	game.effect.stop()
	await create_timer(0.2).timeout
	game.queue_free()
	await process_frame
	quit()

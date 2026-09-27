extends SceneTree
var game
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.paused_input = true
	game.clear_input()
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").path_join("../artifacts")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join("samgir-original.png"))
	game.help.show()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("samgir-help.png"))
	game.music.stop()
	game.effect.stop()
	await create_timer(0.2).timeout
	game.queue_free()
	await process_frame
	quit()

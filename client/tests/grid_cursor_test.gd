extends SceneTree
class MapStub extends Node2D:
	func project(tile: Vector2) -> Vector2:return Vector2((tile.x-tile.y)*32,(tile.x+tile.y)*24)
	func unproject(point: Vector2) -> Vector2:return Vector2(point.x/64+point.y/48,point.y/48-point.x/64)
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok:failures += 1
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var map := MapStub.new()
	root.add_child(map)
	var marker = preload("res://scripts/legacy_grid_cursor.gd").new()
	marker.world = map
	map.add_child(marker)
	marker.set_process(false)
	check(marker.texture.get_size()==Vector2(64,47),"native yellow grid cursor dimensions")
	check(marker.offset==Vector2(-32,-24) and not marker.centered,"original ADRN hotspot preserved")
	marker.update_tile(map.project(Vector2(3.2,2.3)))
	check(marker.position==map.project(Vector2(3,2)),"hover snaps to original isometric tile")
	check(marker.z_index==100,"marker appears above scenery and below UI")
	if DisplayServer.get_name()!="headless":
		marker.position=Vector2(200,150)
		marker.scale=Vector2(3,3)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/original-yellow-grid-cursor.png")
	map.queue_free()
	await process_frame
	quit(1 if failures else 0)

extends Sprite2D
## map.cpp drawGrid: native tile-snapped hover graphic, above actors/below UI.
const ART := "res://assets/legacy/grid-cursor/"
var world: Node2D
func _ready() -> void:
	centered = false
	z_index = 100
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not FileAccess.file_exists(ART+"manifest.json"):
		set_process(false)
		return
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART+"manifest.json"))
	texture = load(ART+"25001.png")
	offset = Vector2(metadata.x,metadata.y)
func _process(_delta: float) -> void:
	visible = not world.data.is_empty() and not world.paused_input and not world.area_transition_busy and not world.battle_view.visible
	# Godot's UI hit test is the equivalent of the native menu-priority check.
	visible = visible and get_viewport().gui_get_hovered_control() == null
	if visible:update_tile(world.get_local_mouse_position())

func update_tile(point: Vector2) -> void:
	var tile: Vector2 = world.unproject(point).round()
	position = world.project(tile)

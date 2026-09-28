extends Panel
## Minimized automation window: a small bar at the right screen edge that shows
## live progress and a button to bring the full window back. It sits beside the
## HUD, never covers the world or other panels, and the controller reaches its
## button in HUD mode.
const WIDTH := 330.0
const HEIGHT := 58.0
var world: Node
var title: Label
var detail: Label
var restore_button: Button

## `slot` stacks several bars upward from the bottom-right corner.
func setup(owner: Node, caption: String, slot: int, on_restore: Callable) -> void:
	world = owner
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	size = Vector2(WIDTH,HEIGHT)
	add_theme_stylebox_override("panel",world.box(Color("20292f",0.94),Color("b29b65")))
	title = world.text(caption,14)
	title.position = Vector2(10,4)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	detail = world.text("",12)
	detail.position = Vector2(10,30)
	detail.size = Vector2(WIDTH-94,22)
	detail.clip_text = true
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(detail)
	restore_button = world.button("展开",on_restore)
	restore_button.name = "RestoreAutomation"
	restore_button.tooltip_text = "展开完整窗口"
	restore_button.position = Vector2(WIDTH-72,12)
	restore_button.size = Vector2(62,34)
	add_child(restore_button)
	var screen: Vector2 = world.get_viewport_rect().size
	# Above the classic bottom bar, clear of the left-anchored pet windows.
	position = Vector2(screen.x-WIDTH-12,screen.y-44-(HEIGHT+6)*(slot+1))
	hide()

func present(heading: String, line: String) -> void:
	title.text = heading
	detail.text = line
	tooltip_text = line

## Shows the bar above sibling panels (input goes to the last sibling first).
func pop_up() -> void:
	if not visible:
		get_parent().move_child(self,get_parent().get_child_count()-1)
		show()

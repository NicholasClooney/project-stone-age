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

## `slot` stacks several bars upward from the bottom-right corner; `lines`
## and `width` size a bar with more to show.
func setup(owner: Node, caption: String, slot: int, on_restore: Callable, lines: int = 1, width: float = WIDTH) -> void:
	world = owner
	var height := HEIGHT+18.0*(lines-1)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	size = Vector2(width,height)
	add_theme_stylebox_override("panel",world.box(Color("20292f",0.94),Color("b29b65")))
	title = world.text(caption,14)
	title.position = Vector2(10,4)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	detail = world.text("",12)
	detail.position = Vector2(10,30)
	detail.size = Vector2(width-94,22+18.0*(lines-1))
	detail.clip_text = true
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(detail)
	restore_button = world.button("展开",on_restore)
	restore_button.name = "RestoreAutomation"
	restore_button.tooltip_text = "展开完整窗口"
	restore_button.position = Vector2(width-72,(height-34)/2)
	restore_button.size = Vector2(62,34)
	add_child(restore_button)
	_slot = slot
	_place()
	hide()

var _slot := 0

## Above the classic bottom bar at the right edge, clear of the left-anchored
## pet windows. Placed every frame: 设置 → 画面 can change the screen's size
## (铺满屏幕, 界面大小) after the chip was made.
func _place() -> void:
	var screen: Vector2 = world.get_viewport_rect().size
	position = Vector2(screen.x-size.x-12,screen.y-44-(size.y+6)-(HEIGHT+6)*_slot)

func _process(_delta: float) -> void:
	if visible:_place()

func present(heading: String, line: String) -> void:
	title.text = heading
	detail.text = line
	tooltip_text = line

## Shows the bar above sibling panels (input goes to the last sibling first).
func pop_up() -> void:
	if not visible:
		get_parent().move_child(self,get_parent().get_child_count()-1)
		show()

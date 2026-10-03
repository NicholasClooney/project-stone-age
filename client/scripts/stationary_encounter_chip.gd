extends PanelContainer
## Presentation only: the backend owns both the encounter count and lifetime.
const AutomationChip = preload("res://scripts/automation_chip.gd")
const QuestChip = preload("res://scripts/quest_auto_chip.gd")
const NOTICE_SECONDS := 7.0
var world: Node
var label: Label
var stop_button: Button
var was_running := false
var notice_left := 0.0
var notice := ""
var feedback_revision := 0
var stop_pending := false

func configure(owner: Node) -> void:
	world = owner
	name = "StationaryEncounterChip"
	z_index = 60
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel",world.box(Color("20292f",0.96),Color("b29b65")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	add_child(row)
	label = world.text("",14)
	label.name = "StationaryStatus"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	stop_button = world.button("停止",stop)
	stop_button.name = "StationaryStop"
	stop_button.custom_minimum_size = Vector2(64,44)
	row.add_child(stop_button)
	hide()

func stop() -> void:
	if stop_pending:return
	stop_pending = true
	stop_button.disabled = true
	world.link.request({"type":"stationary_encounters","enabled":false},func(reply: Dictionary):
		stop_pending = false
		if not bool(reply.get("ok",false)):
			notice = str(reply.get("reason","停止请求未成功。"))
			notice_left = NOTICE_SECONDS)

func _process(delta: float) -> void:
	var state: Dictionary = world.state.derived.get("stationary",{})
	var running := bool(state.get("running",false))
	var observer = world.helper_menu.stationary_ui
	if observer.feedback_revision!=feedback_revision:
		feedback_revision = observer.feedback_revision
		notice = str(observer.feedback)
		notice_left = NOTICE_SECONDS
	if was_running and not running:
		notice = str(state.get("stop_reason",state.get("reason","")))
		notice_left = NOTICE_SECONDS
	was_running = running
	visible = running or notice_left>0
	if not visible:return
	notice_left = maxf(0,notice_left-delta)
	label.text = "原地遇敌中 · 已遇 %d 次"%int(state.get("encounters",0)) if running else notice
	tooltip_text = label.text
	stop_button.visible = running
	stop_button.disabled = stop_pending or not observer.connected(world)
	var screen: Vector2 = world.get_viewport_rect().size
	custom_minimum_size = Vector2(minf(380,screen.x-24),56)
	size = Vector2(custom_minimum_size.x,maxf(56,get_combined_minimum_size().y))
	var bottom := screen.y-50
	# Existing automation and quest bars keep their own positions; this bar
	# stacks above their actual rectangles, including taller hunt details.
	for sibling in get_parent().get_children():
		if sibling is Control and sibling.visible and sibling.get_script() in [AutomationChip,QuestChip]:
			bottom = minf(bottom,sibling.position.y-6)
	position = Vector2(screen.x-size.x-12,maxf(8,bottom-size.y))

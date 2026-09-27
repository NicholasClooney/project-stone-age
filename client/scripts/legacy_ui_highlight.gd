extends Control
## Original mouse.cpp hitFlag=2 / menu.cpp MakeHitBox, not map graphic25001.
## The checked reference branch pulses system palette250,15,2 (green).
const PULSE := [Color(0,1,0),Color8(40,225,40),Color8(0,128,0),Color8(40,225,40)]
var target: BaseButton
var bounds := Rect2()
var selected := false
var hovered := false
var phase := -1
static func attach(button: BaseButton, rectangle: Rect2, chosen: bool = false) -> Control:
	var overlay = load("res://scripts/legacy_ui_highlight.gd").new()
	overlay.name="OriginalHighlight"
	overlay.target=button
	overlay.bounds=rectangle
	overlay.selected=chosen
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.z_index=1
	button.add_child(overlay)
	return overlay
func _process(_delta: float) -> void:
	var next_hover := target.is_hovered() and not target.disabled
	# Original 60-frame cycle: 45 bright, 5 light, 5 dark, 5 light.
	var tick := int(Time.get_ticks_msec()*60/1000)%60
	var next_phase := 0 if tick<45 else (1 if tick<50 else (2 if tick<55 else 3))
	if next_hover!=hovered or next_phase!=phase:
		hovered=next_hover;phase=next_phase;queue_redraw()
func _draw() -> void:
	if hovered:draw_rect(bounds,PULSE[maxi(0,phase)],false,1.0)
	# Persistent selected inventory rectangle uses SYSTEM_PAL_AQUA254.
	if selected and not target.disabled:draw_rect(bounds,Color.CYAN,false,1.0)

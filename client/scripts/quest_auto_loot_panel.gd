extends PanelContainer
## Read-only cached projection display. No timer, request, or permission inference.
const View=preload("res://scripts/quest_auto_loot_view.gd")
var text:Label
var controls:Button
var _key:String=""
func _ready()->void:
	name="QuestAutoLootPanel"
	var scroll:=ScrollContainer.new()
	scroll.name="QuestAutoLootScroll"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y=150
	add_child(scroll)
	var body:=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	text=Label.new();text.name="QuestAutoLootText"
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(text)
	controls=Button.new();controls.name="QuestAutoLootControls"
	controls.text="本步调限 / 重置尚未开放"
	controls.disabled=true
	body.add_child(controls)
func present_snapshot(auto:Dictionary,offline:bool)->void:
	if text==null:return
	# This is one existing ClientState cache, not an authenticated epoch check.
	var view=View.new();view.replace_snapshot(auto,true)
	if offline:view.disconnected()
	var next:String="\n".join(view.lines())
	if next!=_key:
		_key=next;text.text=next
	controls.disabled=true # No public commands exist, even if a future flag changes.
func content()->String:
	return text.text if is_instance_valid(text) else ""

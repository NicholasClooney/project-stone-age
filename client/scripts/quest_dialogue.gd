extends Node
## Server-owned original dialogue; no branch or reward rules live in the UI.

## The link retains this receiver while a reply is in flight. A map may free
## the window before that reply arrives; the receiver still cancels its token.
class ReplyGuard extends RefCounted:
	var controller: WeakRef
	var link
	var generation: int
	static func deliver(reply: Dictionary, guard: ReplyGuard) -> void:
		guard.receive(reply)
	func receive(reply: Dictionary) -> void:
		var target=controller.get_ref()
		if is_instance_valid(target):
			target._receive(reply,generation)
			return
		var abandoned: Dictionary=reply.get("dialogue",{})
		if not abandoned.is_empty():link.request({"type":"quest_close","token":str(abandoned.get("token",""))})

var world: Node
var overlay: Control
var panel: Control
var body: Label
var buttons: Array[Button] = []
var service_scroll: ScrollContainer
var service_controls: VBoxContainer
var token := ""
var active := false
var busy := false
var generation := 0
var origin_map := -1
var origin_cell := Vector2i.ZERO
var prior_pause := false

func setup(owner: Node, root: Control, content: Label) -> void:
	world=owner;overlay=root;body=content;panel=body.get_parent().get_parent()
	if world.link.has_signal("disconnected"):world.link.disconnected.connect(close)

func open(npc_id: String) -> void:
	if active:close()
	prior_pause=world.paused_input
	world.clear_input();world.paused_input=true
	origin_map=int(world.data.map_id);origin_cell=world.cell
	active=true;overlay.show();body.text=""
	_send({"type":"quest_talk","npc_id":npc_id})

func _send(command: Dictionary) -> void:
	busy=true
	for button in buttons:button.disabled=true
	if is_instance_valid(service_controls):service_controls.set_busy(true)
	var expected:=generation
	var guard:=ReplyGuard.new()
	guard.controller=weakref(self);guard.link=world.link;guard.generation=expected
	world.link.request(command,ReplyGuard.deliver.bind(guard))

func _receive(reply: Dictionary, expected: int) -> void:
	if not active or expected!=generation:
		var abandoned: Dictionary=reply.get("dialogue",{})
		if not abandoned.is_empty():world.link.request({"type":"quest_close","token":str(abandoned.get("token",""))})
		return
	busy=false
	if not bool(reply.get("ok",false)):
		world.message.text=str(reply.get("reason","无法交谈。"));close();return
	if bool(reply.get("closed",false)):close();return
	var dialogue: Dictionary=reply.get("dialogue",{})
	if dialogue.is_empty():close();return
	token=str(dialogue.get("token",""))
	body.get_parent().scroll_vertical=0
	body.text=str(dialogue.get("name",""))+"\n\n"+str(dialogue.get("text","")).strip_edges()
	for button in buttons:button.queue_free()
	buttons.clear()
	_clear_service()
	if str(dialogue.get("kind","")) in ["golden_bui_quiz","golden_bui_janken","golden_bui_gate","original_keyword"]:
		_show_service(dialogue)
		return
	var choices: Array=dialogue.get("choices",[])
	for i in range(choices.size()):
		var entry: Dictionary=choices[i]
		var button:=Button.new()
		button.name="QuestChoice_"+str(entry.id)
		button.text=str(entry.text)
		button.position=Vector2(24+i*160,166);button.size=Vector2(150,28)
		button.pressed.connect(func():choose(str(entry.id)))
		panel.add_child(button);buttons.append(button)
	if not buttons.is_empty():buttons[0].grab_focus()

func _clear_service() -> void:
	if is_instance_valid(service_scroll):
		service_scroll.hide()
		service_scroll.queue_free()
	service_scroll=null;service_controls=null
	if is_instance_valid(body):body.get_parent().show()

func _show_service(dialogue: Dictionary) -> void:
	body.get_parent().hide()
	service_scroll=ScrollContainer.new()
	service_scroll.name="QuestServiceScroll"
	service_scroll.position=Vector2(18,15);service_scroll.size=Vector2(348,183)
	service_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(service_scroll)
	var content:=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",8)
	service_scroll.add_child(content)
	var prompt:=Label.new()
	prompt.text=body.text;prompt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size.x=310
	prompt.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_child(prompt)
	service_controls=preload("res://scripts/golden_bui_controls.gd").new()
	service_controls.configure(dialogue)
	service_controls.submitted.connect(choose)
	content.add_child(service_controls)
	buttons.assign(service_controls.buttons)

func choose(choice: String, text: String = "") -> void:
	if not active or busy:return
	_send({"type":"quest_choose","token":token,"choice":choice,"text":text})

func close() -> void:
	if not active:return
	active=false;generation+=1
	if not token.is_empty():world.link.request({"type":"quest_close","token":token})
	token="";busy=false
	for button in buttons:
		if is_instance_valid(button):button.queue_free()
	buttons.clear()
	_clear_service()
	if is_instance_valid(overlay):overlay.hide()
	# Restore only this window's pause; other overlays retain their own pause.
	var other_travel: bool=is_instance_valid(world.world_travel) and is_instance_valid(world.world_travel.overlay) and world.world_travel.overlay.visible
	world.paused_input=prior_pause or other_travel or world._panel_open() or world.dialogue.visible or world.battle_view.visible or world.automation_minimized()
	world.clear_input()

func _process(_delta: float) -> void:
	if active and (int(world.data.map_id)!=origin_map or world.cell!=origin_cell or world.moving):close()

func _exit_tree() -> void:
	close()

extends Node
const Confirmation = preload("res://scripts/transmigration_confirmation.gd")
## Server-owned original dialogue; no branch or reward rules live in the UI.

## The link retains this receiver while a reply is in flight. A map may free
## the window before that reply arrives; the receiver still cancels its token.
class ReplyGuard extends RefCounted:
	var controller: WeakRef
	var link
	var generation: int
	var preview_request := false
	var auto_reward := false
	static func deliver(reply: Dictionary, guard: ReplyGuard) -> void:
		guard.receive(reply)
	func receive(reply: Dictionary) -> void:
		var target=controller.get_ref()
		if is_instance_valid(target):
			if auto_reward:
				target.receive_auto_reply(reply,generation)
				return
			target._receive(reply,generation)
			if preview_request:
				Confirmation.finish_preview(link,reply,target.confirmation if target.active and target.generation==generation and is_instance_valid(target.confirmation) else null)
			return
		if auto_reward:return
		if preview_request:Confirmation.finish_preview(link,reply)
		var abandoned: Dictionary=reply.get("dialogue",{})
		if not abandoned.is_empty():link.request({"type":"quest_close","token":str(abandoned.get("token",""))})

var auto_identity:Dictionary={}
var confirmation: Control
var npc_id := ""
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

func open(source_id: String) -> void:
	if active:close()
	npc_id=source_id
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
	guard.auto_reward=not auto_identity.is_empty()
	guard.preview_request=command.get("type","")=="quest_talk" and str(command.get("npc_id",""))==Confirmation.NPC_ID
	if guard.preview_request:Confirmation.begin_preview(world.link)
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
	if reply.has("transmigration"):
		var value: Dictionary=reply.transmigration
		if npc_id!=Confirmation.NPC_ID or str(value.get("npc_id",""))!=Confirmation.NPC_ID or str(value.get("token","" )).is_empty():
			world.message.text="无效的精灵王转生预览。";close();return
		_clear_service()
		confirmation=Confirmation.new()
		overlay.add_child(confirmation)
		confirmation.setup(world)
		confirmation.dismissed.connect(close)
		confirmation.show_preview(value)
		return
	var dialogue: Dictionary=reply.get("dialogue",{})
	if dialogue.is_empty():close();return
	token=str(dialogue.get("token",""))
	body.get_parent().scroll_vertical=0
	body.text=str(dialogue.get("name",""))+"\n\n"+str(dialogue.get("text","")).strip_edges()
	for button in buttons:button.queue_free()
	buttons.clear()
	_clear_service()
	if str(dialogue.get("kind","")) in ["golden_bui_quiz","golden_bui_janken","golden_bui_gate","original_jug_shop","original_keyword","original_pet_selection","original_prison"]:
		_show_service(dialogue)
		return
	if not auto_identity.is_empty():
		_show_auto_choices(dialogue)
		return
	var choices: Array=dialogue.get("choices",[])
	for i in range(choices.size()):
		var entry: Dictionary=choices[i]
		var button:=Button.new()
		button.name="QuestChoice_"+str(entry.id)
		button.text=str(entry.text)
		button.position=Vector2(24+i*160,166);button.size=Vector2(150,28)
		var rendered_generation:=generation
		button.pressed.connect(func():
			if rendered_generation==generation:choose(str(entry.id)))
		panel.add_child(button);buttons.append(button)
	if not buttons.is_empty():buttons[0].grab_focus()

func _clear_service() -> void:
	if is_instance_valid(confirmation):
		confirmation.shutdown()
		confirmation.queue_free()
	confirmation=null
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
	service_controls=preload("res://scripts/quest_pet_selection_controls.gd").new() if str(dialogue.get("kind",""))=="original_pet_selection" else preload("res://scripts/golden_bui_controls.gd").new()
	service_controls.configure(dialogue)
	if str(dialogue.get("kind",""))=="original_pet_selection":service_controls.submitted.connect(choose_pets)
	else:
		var rendered_generation:=generation
		service_controls.submitted.connect(func(choice:String,text:String=""):
			if rendered_generation==generation:choose(choice,text))
	content.add_child(service_controls)
	buttons.assign(service_controls.buttons)

func choose(choice: String, text: String = "") -> void:
	if not active or busy:return
	var command:Dictionary={"type":"quest_choose","token":token,"choice":choice,"text":text}
	if not auto_identity.is_empty():
		if not matches_auto():close(false);return
		command.merge(auto_identity)
	_send(command)

func choose_pets(choice:String, pet_ids:Array) -> void:
	if not active or busy:return
	_send({"type":"quest_choose","token":token,"choice":choice,"pet_ids":pet_ids})

func close(cancel_pending:bool=true) -> void:
	if not active:return
	active=false;generation+=1
	if cancel_pending and not token.is_empty():
		if auto_identity.is_empty():world.link.request({"type":"quest_close","token":token})
		elif matches_auto():
			var command:Dictionary={"type":"quest_close","token":token}
			command.merge(auto_identity)
			world.link.request(command)
	auto_identity.clear()
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
	if active and not auto_identity.is_empty() and not matches_auto():
		var current:Dictionary=world.state.derived.get("quest_auto",{})
		var next_stage:bool=current.get("running",false) and str(current.get("phase",""))=="waiting_reward" and str(current.get("run_id",""))==str(auto_identity.quest_run_id) and str(current.get("step_id",""))==str(auto_identity.quest_step_id)
		close(false)
		if next_stage:open_auto(current)
		return
	if active and (int(world.data.map_id)!=origin_map or world.cell!=origin_cell or world.moving):close()

func _exit_tree() -> void:
	close()

## Frozen capability belongs to the rendered choices, never to a later click.
func identity_of(auto:Dictionary)->Dictionary:
	return {"quest_run_id":str(auto.get("run_id","")),"quest_step_id":str(auto.get("step_id","")),"quest_revision":int(auto.get("revision",-1))}

func matches_auto()->bool:
	var current:Dictionary=world.state.derived.get("quest_auto",{})
	var waiting:Dictionary=current.get("waiting",{})
	return current.get("running",false) and str(current.get("phase",""))=="waiting_reward" and identity_of(current)==auto_identity and str(waiting.get("token",""))==token and str(waiting.get("npc_id",""))==npc_id

func open_auto(auto:Dictionary)->void:
	var waiting:Dictionary=auto.get("waiting",{})
	var current:Dictionary=world.state.derived.get("quest_auto",{})
	if identity_of(auto)!=identity_of(current) or waiting!=current.get("waiting",{}):return
	var dialogue:Dictionary=waiting.get("dialogue",{})
	if not auto.get("running",false) or str(auto.get("phase",""))!="waiting_reward" or dialogue.is_empty():return
	if str(dialogue.get("token","" )).is_empty() or str(dialogue.get("token",""))!=str(waiting.get("token","")):return
	# UID and final rebirth stay in their existing explicit manual services.
	if str(dialogue.get("kind",""))=="original_pet_selection" or str(waiting.get("npc_id",""))==Confirmation.NPC_ID:return
	if active:close(false)
	npc_id=str(waiting.get("npc_id",""))
	prior_pause=world.paused_input
	world.clear_input();world.paused_input=true
	origin_map=int(world.data.map_id);origin_cell=world.cell
	active=true;overlay.show()
	auto_identity=identity_of(auto)
	_receive({"ok":true,"dialogue":dialogue.duplicate(true)},generation)

func receive_auto_reply(reply:Dictionary,expected:int)->void:
	# A snapshot is the only authority for a new stage or successful continuation.
	# Never close a token from an abandoned auto reply: it may now name a newer stage.
	if not active or expected!=generation or auto_identity.is_empty():return
	if not reply.get("ok",false):
		world.message.text=str(reply.get("reason","奖励选择失败。"))
		close(false)
	elif reply.get("closed",false):close(false)

func _show_auto_choices(dialogue:Dictionary)->void:
	body.get_parent().hide()
	service_scroll=ScrollContainer.new()
	service_scroll.name="QuestAutoRewardScroll"
	service_scroll.position=Vector2(18,15);service_scroll.size=Vector2(348,183)
	service_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(service_scroll)
	var content:=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",8)
	service_scroll.add_child(content)
	var prompt:=Label.new()
	prompt.text=body.text
	prompt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	prompt.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_child(prompt)
	var rendered_generation:=generation
	for entry in dialogue.get("choices",[]):
		var button:=Button.new()
		button.name="QuestChoice_"+str(entry.id)
		button.text=str(entry.text)
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y=44
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			if rendered_generation==generation:choose(str(entry.id)))
		content.add_child(button);buttons.append(button)
	if not buttons.is_empty():buttons[0].grab_focus()

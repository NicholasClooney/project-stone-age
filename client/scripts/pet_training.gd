extends "res://scripts/adventure_menu.gd"
## login.cpp serverWindowType6: skill list → pet → confirmation.
## Slot replacement is intentionally outside the supported three learned skills.
const Catalog = preload("res://scripts/pet_skills.gd")
var stage := 0
var skill_id := 3
var trainer_map := 1003

func open_training(map_id: int) -> void:
	if Catalog.available(map_id).is_empty():return
	trainer_map = map_id
	stage = 0
	feedback = ""
	kind = "training"
	world.clear_input()
	world.paused_input = true
	show()
	rebuild()
	world.play_ui_sound(202)

func rebuild() -> void:
	if world==null or not visible:return
	if is_instance_valid(panel):
		remove_child(panel)
		panel.queue_free()
	panel = Control.new()
	panel.size = Vector2(432,428) if stage==0 else (Vector2(448,240) if stage==1 else Vector2(512,96))
	add_child(panel)
	layout_panel()
	var profile: Dictionary = world.session.snapshot()
	if stage==0:
		image(26139,Vector2.ZERO)
		label("超级饲育员",Vector2(145,18),260)
		label("好了！要教它什么好呢？",Vector2(18,48),390)
		label("石币 %d" % profile.player.gold,Vector2(244,84),180)
		var row := 0
		for ident in Catalog.available(trainer_map):
			var skill: Dictionary = Catalog.SKILLS[ident]
			var button := _row(str(skill.name),Vector2(32,116+row*21),func(): _select_skill(int(ident)))
			button.size = Vector2(270,21)
			label(str(skill.cost),Vector2(312,118+row*21),100,14)
			button.mouse_entered.connect(func(): feedback=str(skill.description); _description())
			row += 1
		var description := label(feedback,Vector2(27,308),378,15)
		description.name = "Description"
		_exit(Vector2(176,389))
	elif stage==1:
		stone(Rect2(Vector2.ZERO,panel.size))
		label("要让哪只宠物学习「%s」？" % Catalog.SKILLS[skill_id].name,Vector2(20,18),410)
		if profile.pets.is_empty():label("还没有宠物。",Vector2(28,65),360)
		for i in range(profile.pets.size()):
			var pet: Dictionary = profile.pets[i]
			var learned: bool = skill_id in pet.get("learned_skills",[])
			var button := _row("%s  Lv.%d%s" % [pet.name,pet.level,"  已学会" if learned else ""],Vector2(28,55+i*27),func(): selected_pet=i; stage=2; world.play_ui_sound(202); rebuild())
			button.disabled = learned
		_exit(Vector2(184,207))
	else:
		stone(Rect2(Vector2.ZERO,panel.size))
		var pet: Dictionary = profile.pets[selected_pet]
		label(feedback if not feedback.is_empty() else "让[%s]学习[%s]" % [pet.name,Catalog.SKILLS[skill_id].name],Vector2(20,20),472)
		label("需要 %d 石币。这样可以吗？" % Catalog.SKILLS[skill_id].cost,Vector2(20,43),472)
		_art_button(26094,Vector2(170,72),_confirm)
		_art_button(26095,Vector2(340,72),func(): stage=1; world.play_ui_sound(203); rebuild())

func _art_button(ident: int, center: Vector2, callback: Callable) -> void:
	var button := TextureButton.new()
	button.texture_normal = original(ident)
	button.position = center-button.texture_normal.get_size()/2
	button.pressed.connect(callback)
	panel.add_child(button)

func _description() -> void:
	var description := panel.get_node_or_null("Description")
	if description:description.text=feedback

func _row(caption: String, point: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.position = point
	button.size = Vector2(392,26)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size",15)
	for style in ["normal","hover","pressed","focus","disabled"]:button.add_theme_stylebox_override(style,StyleBoxEmpty.new())
	button.add_theme_color_override("font_hover_color",Color.YELLOW)
	button.pressed.connect(callback)
	panel.add_child(button)
	return button

func _select_skill(ident: int) -> void:
	if world.session.snapshot().player.gold < Catalog.SKILLS[ident].cost:
		world.play_battle_sound(220)
		feedback = "石币不足。"
		_description()
		return
	skill_id=ident
	stage=1
	feedback=""
	world.play_ui_sound(202)
	rebuild()

func _confirm() -> void:
	if world.session.learn_pet_skill(selected_pet,skill_id):
		world.checkpoint()
		close_training()
	else:
		world.play_battle_sound(220)
		feedback="无法学习：请检查石币、宠物与饲育员的位置。"
		rebuild()

func _exit(point: Vector2) -> void:
	var button := TextureButton.new()
	button.texture_normal=original(26091)
	button.position=point
	button.pressed.connect(func():
		if stage>0:stage-=1; world.play_ui_sound(203); rebuild()
		else:close_training())
	panel.add_child(button)

func close_training() -> void:
	hide()
	world.paused_input=false
	world.clear_input()
	world.play_ui_sound(203)

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_training()
		get_viewport().set_input_as_handled()

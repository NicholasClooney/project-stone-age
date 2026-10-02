extends VBoxContainer
## Presentation only: relay the visible choice/text to the caller's Session link.
signal submitted(choice: String, text: String)
var buttons: Array[Button] = []
var answer: LineEdit

func configure(dialogue: Dictionary) -> void:
	name = "GoldenBuiControls"
	add_theme_constant_override("separation",8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if str(dialogue.get("input","choice")) == "text":
		answer = LineEdit.new()
		answer.name = "GoldenBuiAnswer"
		answer.placeholder_text = "写下你的答案"
		answer.max_length = 120
		answer.custom_minimum_size.y = 44
		answer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		answer.text_submitted.connect(func(_text: String):_submit("submit"))
		add_child(answer)
	for entry in dialogue.get("choices",[]):
		var button := Button.new()
		button.name = "QuestChoice_"+str(entry.id)
		button.text = str(entry.text)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_submit.bind(str(entry.id)))
		add_child(button)
		buttons.append(button)

func _submit(choice: String) -> void:
	var text := answer.text if is_instance_valid(answer) and choice == "submit" else ""
	submitted.emit(choice,text)

func set_busy(value: bool) -> void:
	for button in buttons: button.disabled = value
	if is_instance_valid(answer): answer.editable = not value

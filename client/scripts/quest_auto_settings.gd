extends VBoxContainer
## Presentation only. The caller maps authority settings to these controls and
## handles the apply signal; this component never writes a profile or runner.
signal apply_requested(mode_index:int, minutes:int)
signal back_requested
const MODE_LABELS=["A · 正常原路", "B · 公开入口直达", "C · 原路分段快移"]
const MODE_DETAILS=[
	"默认方式：按原路正常行走。",
	"项目改动：仅直达下一处已审核公开入口；减少沿途行走及遇敌。",
	"项目改动：沿 A 的同条路线分段快移，每个逻辑步保留原遇敌判定，单位时间遇敌更多。速度由服务统一配置。"]
var mode:OptionButton
var budget:SpinBox
var apply_button:Button
var description:Label
var feedback:Label
var editable:=false

func _init()->void:
	name="QuestAutoSettings"
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",10)
	add_text("自动任务设置",20)
	mode=OptionButton.new()
	mode.name="QuestAutoMovementMode"
	mode.custom_minimum_size.y=44
	mode.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for caption in MODE_LABELS:mode.add_item(caption)
	mode.item_selected.connect(func(_index:int):update_description())
	add_child(mode)
	description=add_text("",14)
	description.name="QuestAutoModeDescription"
	add_text("仅审核公开走廊可快移；其余公开段、保护洞窟、门、迷宫及入口保护段始终逐格原路。项目快移不会获得到达资格。",14)
	add_text("后续刷物任务时限偏好（分钟，尚未开放）",16)
	budget=SpinBox.new()
	budget.name="QuestAutoLootMinutes"
	budget.min_value=1
	budget.max_value=180
	budget.step=1
	budget.value=30
	budget.custom_minimum_size.y=44
	budget.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_child(budget)
	add_text("当前仅保存偏好，不会启动刷物或计时。供后续刷物任务使用，默认 30 分钟，可设 1–180 分钟。",14)
	feedback=add_text("",14)
	feedback.name="QuestAutoSettingsFeedback"
	apply_button=Button.new()
	apply_button.name="QuestAutoSettingsApply"
	apply_button.text="保存设置"
	apply_button.custom_minimum_size.y=44
	apply_button.pressed.connect(func():
		if editable and not apply_button.disabled:
			budget.apply()
			apply_requested.emit(mode.selected,int(budget.value)))
	add_child(apply_button)
	var back:=Button.new()
	back.name="QuestAutoSettingsBack"
	back.text="返回任务助手"
	back.custom_minimum_size.y=44
	back.pressed.connect(func():back_requested.emit())
	add_child(back)
	present(0,30,[],false)

func add_text(value:String,font_size:int)->Label:
	var label:=Label.new()
	label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",font_size)
	add_child(label)
	return label

func present(mode_index:int,minutes:int,available_modes:Array,can_edit:bool,reason:String="")->void:
	mode.select(clampi(mode_index,0,2))
	budget.value=clampi(minutes,1,180)
	for index in range(3):mode.set_item_disabled(index,not index in available_modes)
	editable=can_edit
	mode.disabled=not can_edit
	budget.editable=can_edit
	apply_button.disabled=not can_edit
	feedback.text=reason
	feedback.visible=not reason.is_empty()
	update_description()

func update_description()->void:
	description.text=MODE_DETAILS[mode.selected]

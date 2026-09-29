extends Control
## 展示模式's cards (server/automation.gd publishes the card in the automation
## status as flow.card): 亮相 before a found pet's capture, a 里程碑 toast at
## Lv30/60/90 of its shown training, and the 最终属性 card at Lv120. Every
## watching device shows the card while the flow is in that step, so a reload
## or another device sees the same one. It never takes input.
const Rarity = preload("res://scripts/showcase_rarity.gd")
const WIDTH := 460.0
const NAMES := {"attack":"攻", "defence":"防", "speed":"敏", "max_hp":"血"}
var world: Node
var panel: PanelContainer
var shown_id := -1
var kind := ""

func configure(owner: Node) -> void:
	world = owner
	name = "ShowcaseCards"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80
	hide()

## The card the flow is showing now, or {} when none applies to its step.
static func current(automation: Dictionary) -> Dictionary:
	var flow: Dictionary = automation.get("flow", {})
	var card: Dictionary = flow.get("card", {})
	if card.is_empty() or not bool(flow.get("showcase", false)):return {}
	var phase := str(flow.get("phase", ""))
	var segment := str(flow.get("segment", ""))
	match str(card.get("kind", "")):
		"reveal":return card if phase == "reveal" else {}
		"milestone":return card if phase == "train" and segment == "level" else {}
		"final":return card if phase == "train" and segment == "final" else {}
	return {}

func on_status(automation: Dictionary) -> void:
	var card := current(automation)
	if card.is_empty():
		if visible:hide()
		shown_id = -1
		return
	if int(card.get("id", -1)) == shown_id and visible:return
	present(card)

func present(card: Dictionary) -> void:
	shown_id = int(card.get("id", -1))
	kind = str(card.get("kind", ""))
	for child in get_children():
		remove_child(child)
		child.queue_free()
	panel = PanelContainer.new()
	panel.name = "ShowcaseCard"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gold := Color("e6c284")
	panel.add_theme_stylebox_override("panel", world.box(Color("1b2226", 0.95), gold if kind != "milestone" else Color("9d8354")))
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	match kind:
		"reveal":_reveal(body, card)
		"milestone":_milestone(body, card)
		"final":_final(body, card)
	show()
	panel.reset_size()
	_place()

func _place() -> void:
	var screen: Vector2 = world.get_viewport_rect().size
	var size_now := panel.get_combined_minimum_size()
	if kind == "milestone":panel.position = Vector2((screen.x - size_now.x) / 2.0, 96)
	else:panel.position = Vector2((screen.x - size_now.x) / 2.0, maxf(40.0, (screen.y - size_now.y) / 2.0 - 60))

func _line(body: Control, value: String, size: int, color: Color = Color("f8edc7")) -> Label:
	var label: Label = world.text(value, size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = WIDTH if kind != "milestone" else 0.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if kind != "milestone" else TextServer.AUTOWRAP_OFF
	body.add_child(label)
	return label

static func stats_text(stats: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in ["attack", "defence", "speed", "max_hp"]:parts.append("%s %d" % [NAMES[key], int(stats.get(key, 0))])
	return "  ".join(parts)

static func grades_text(offsets: Array) -> String:
	var parts: PackedStringArray = []
	for value in offsets:parts.append("%+d" % int(value))
	return "/".join(parts)

func _reveal(body: Control, card: Dictionary) -> void:
	_line(body, "发现！", 15, Color("b6aa8a")).name = "ShowcaseKind"
	var grade := "满档" if bool(card.get("full", false)) else "先天 " + grades_text(card.get("offsets", []))
	_line(body, "%s · Lv.1 · %s" % [str(card.get("name", "")), grade], 22, Color("ffd98a")).name = "ShowcaseTitle"
	_line(body, "预测 120 级", 14, Color("b6aa8a"))
	_line(body, stats_text(card.get("prediction", {})), 18).name = "ShowcasePrediction"
	_line(body, "三围合 %d" % int(card.get("sum", 0)), 26, Color("ffd98a")).name = "ShowcaseSum"
	for text in card.get("rarity", []):_line(body, str(text), 14, Color("d8cfb0"))
	var waiting := int(card.get("queue", 0))
	_line(body, "第 %d 组遇敌 · 马上捕获%s" % [int(card.get("roll", 0)), "；后台还有 %d 只在排队" % waiting if waiting > 0 else ""], 12, Color("9aa3a0"))

func _milestone(body: Control, card: Dictionary) -> void:
	_line(body, "里程碑 Lv%d  ·  %s 现在 Lv.%d  ·  %s" % [int(card.get("milestone", card.get("level", 0))), str(card.get("name", "")), int(card.get("level", 0)), stats_text(card.get("stats", {}))], 16, Color("ffd98a")).name = "ShowcaseMilestone"

func _final(body: Control, card: Dictionary) -> void:
	_line(body, "练成 120 级", 15, Color("b6aa8a")).name = "ShowcaseKind"
	_line(body, "%s · %s" % [str(card.get("name", "")), str(card.get("pet_id", ""))], 22, Color("ffd98a")).name = "ShowcaseTitle"
	_line(body, "实际  " + stats_text(card.get("actual", {})), 18).name = "ShowcaseActual"
	_line(body, "预测  " + stats_text(card.get("prediction", {})) + ("（完全一致）" if bool(card.get("matches", false)) else "  与预测不同"), 14, Color("b6d6a0") if bool(card.get("matches", false)) else Color("e89a8a")).name = "ShowcaseMatch"
	_line(body, "三围合 %d" % int(card.get("sum", 0)), 26, Color("ffd98a"))
	_line(body, "同种第 %d 名（共 %d 只）" % [int(card.get("rank", 0)), int(card.get("of", 0))], 16).name = "ShowcaseRank"
	for text in card.get("rarity", []):_line(body, str(text), 14, Color("d8cfb0"))
	var outcome := str(card.get("outcome", ""))
	if not outcome.is_empty():
		_line(body, outcome, 14, Color("e89a8a") if bool(card.get("released", false)) else Color("b6d6a0")).name = "ShowcaseOutcome"

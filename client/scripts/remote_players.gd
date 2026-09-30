extends Node
## Other players on this map (LAN phase 2, docs/development/lan-profiles.md):
## draws what network/presence_model.gd knows with the original character
## and riding art, a name at the feet (character.cpp: centred, y-10, white
## with a shadow), the original V.S. mark (CG_VS_MARK_1A, 25610) over the
## head while they fight, a speech bubble while they talk, and a small card
## when the pointer rests on one (or a click, which still walks as usual).
##
## They are scenery: they never block a cell, never take a click or a key
## away from the field, and change nothing in encounters or automation. A
## game without a multi-profile server never receives presence events, so
## nothing is drawn.
const PresenceModel = preload("res://network/presence_model.gd")
const LegacyActor = preload("res://scripts/legacy_actor.gd")
const Riding = preload("res://scripts/riding.gd")
const Faces = preload("res://scripts/faces.gd")
const BATTLE_MARK := "res://assets/legacy/ui/25610.png"
const CARD_PIN_SECONDS := 4.0
## Hit box around a player's feet, in map pixels.
const HIT := Rect2(-22,-78,44,84)
const BUBBLE_WIDTH := 150.0

var world: Node2D
var model = PresenceModel.new()
## id -> Node2D holder (actor, name, mark, bubble), children of world.actors.
var nodes: Dictionary = {}
var card: PanelContainer
var _card_text: Label
var _card_face: TextureRect
var _hovered := ""
var _card_for := ""
## The local character's own bubble (a child of world.player) and its time.
var _own_bubble: PanelContainer
var _own_left := 0.0
var _pinned := ""
var _pinned_left := 0.0
var _battle_mark: Texture2D

func configure(owner: Node2D) -> void:
	world = owner
	if ResourceLoader.exists(BATTLE_MARK):_battle_mark = load(BATTLE_MARK)

## A backend event: presence and chat change the model; the rest is ignored.
func on_event(event: Dictionary) -> void:
	var kind := str(event.get("type",""))
	if kind!="presence" and kind!="chat":return
	var result: Dictionary = model.apply(event)
	for id in result.despawned:_drop(id)
	if kind=="chat" and bool(event.get("mine",false)):_say_own(str(event.get("text","")))

## The local character's bubble when this profile speaks (from any device).
func _say_own(line: String) -> void:
	if world==null or not is_instance_valid(world.player):return
	if not is_instance_valid(_own_bubble) or _own_bubble.get_parent()!=world.player:
		_own_bubble = speech_bubble()
		world.player.add_child(_own_bubble)
	say_into(_own_bubble,line)
	_own_bubble.position = Vector2(-_own_bubble.size.x/2,-100-_own_bubble.size.y)
	_own_bubble.show()
	_own_left = PresenceModel.SPEECH_SECONDS

func _drop(id: String) -> void:
	if nodes.has(id) and is_instance_valid(nodes[id]):nodes[id].queue_free()
	nodes.erase(id)
	if _hovered==id:_hovered = ""
	if _pinned==id:_pinned = ""

## Forget everyone (a logout, or the connection dropped: the server sends a
## full list again).
func reset() -> void:
	for id in nodes.keys():_drop(id)
	model.clear()
	_update_card()

func _process(delta: float) -> void:
	model.step(delta)
	if _own_left>0:
		_own_left -= delta
		if _own_left<=0 and is_instance_valid(_own_bubble):_own_bubble.hide()
	var here: bool = world!=null and not world.data.is_empty() and model.map_id==int(world.data.get("map_id",-2)) and is_instance_valid(world.actors)
	for id in model.players:
		if not here:
			_drop(id)
			continue
		_draw_player(model.players[id])
	if not here and not nodes.is_empty():
		for id in nodes.keys():_drop(id)
	_hover(delta)

func _draw_player(player: Dictionary) -> void:
	var id := str(player.id)
	var holder: Node2D = nodes.get(id)
	if holder==null or not is_instance_valid(holder) or holder.get_parent()!=world.actors:
		if holder!=null and is_instance_valid(holder):holder.queue_free()
		holder = _build(player)
		nodes[id] = holder
		world.actors.add_child(holder)
	holder.position = world.project(player.pos)
	var actor = holder.get_node("Actor")
	actor.facing = int(player.facing)
	actor.set_action(4 if bool(player.walking) else 3)
	_look(actor,player)
	holder.get_node("Name").text = str(player.name)
	var mark: Sprite2D = holder.get_node("Mark")
	mark.visible = bool(player.b) and _battle_mark!=null
	var bubble: PanelContainer = holder.get_node("Bubble")
	var talking := not str(player.speech).is_empty()
	bubble.visible = talking
	if talking:
		say_into(bubble,str(player.speech))
		bubble.position = Vector2(-bubble.size.x/2,-100-bubble.size.y-(16 if mark.visible else 0))

## Appearance and mount, once their art is here (web packs load on demand).
func _look(actor, player: Dictionary) -> void:
	var character := str(player.c)
	var composite := Riding.composite(character,int(player.ride)) if int(player.ride)>=0 else -1
	var key := "%s:%d" % [character,composite]
	if actor.get_meta("look","")==key:return
	var packs: Array = [world.asset_packs.character_pack(character)]
	if composite>=0:packs.append(world.asset_packs.riding_pack(composite))
	if not world.asset_packs.is_ready(packs):
		world.asset_packs.ensure(packs)
		return
	actor.set_meta("look",key)
	actor.character_id = character if world.data.characters.has(character) else "100000"
	actor.mounted_character_id = str(composite) if composite>=0 else ""
	actor.current_image = -1

func _build(player: Dictionary) -> Node2D:
	var holder := Node2D.new()
	holder.name = "RemotePlayer_"+str(player.id)
	var actor = LegacyActor.new()
	actor.name = "Actor"
	actor.world = world
	holder.add_child(actor)
	# Names, marks and bubbles over every actor, as the original's font layer.
	var label: Label = world.text("",12)
	label.name = "Name"
	label.add_theme_color_override("font_color",Color.WHITE)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(160,16)
	label.position = Vector2(-80,-10)
	label.z_index = 20
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(label)
	var mark := Sprite2D.new()
	mark.name = "Mark"
	mark.texture = _battle_mark
	mark.position = Vector2(0,-96)
	mark.z_index = 20
	mark.visible = false
	holder.add_child(mark)
	holder.add_child(speech_bubble())
	return holder

## A speech bubble: dark text on the cream of the original balloon (26500).
func speech_bubble() -> PanelContainer:
	var bubble := PanelContainer.new()
	bubble.name = "Bubble"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f8f4e4")
	style.border_color = Color("3b2f1e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	bubble.add_theme_stylebox_override("panel",style)
	bubble.z_index = 21
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.visible = false
	var label: Label = world.text("",12)
	label.name = "Text"
	label.add_theme_color_override("font_color",Color("2a2218"))
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(label)
	return bubble

## Puts a line into a bubble; long lines wrap at BUBBLE_WIDTH.
func say_into(bubble: PanelContainer, line: String) -> void:
	var label: Label = bubble.get_node("Text")
	if label.text==line:return
	label.text = line
	var width: float = label.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
	label.custom_minimum_size.x = minf(ceilf(width)+2,BUBBLE_WIDTH)
	bubble.reset_size()

# ---- the card --------------------------------------------------------------

## The player under a point on the map (map pixels), "" for none.
func player_at(point: Vector2) -> String:
	var best := ""
	var best_y := -INF
	for id in nodes:
		var holder: Node2D = nodes[id]
		if not is_instance_valid(holder):continue
		if HIT.has_point(point-holder.position) and holder.position.y>best_y:
			best = id
			best_y = holder.position.y
	return best

func _hover(delta: float) -> void:
	if _pinned_left>0:
		_pinned_left -= delta
		if _pinned_left<=0:_pinned = ""
	var hovered := ""
	if not nodes.is_empty() and world.is_inside_tree() and world.get_viewport().gui_get_hovered_control()==null:
		hovered = player_at(world.get_global_mouse_position())
	_hovered = hovered
	var shown := _hovered if not _hovered.is_empty() else _pinned
	if shown!=_card_for:_update_card()
	elif card!=null and card.visible:_place_card()

## A click on a player pins its card for a moment; the click still walks.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not nodes.is_empty():
		var id := player_at(world.get_global_transform_with_canvas().affine_inverse()*event.position)
		if not id.is_empty():
			_pinned = id
			_pinned_left = CARD_PIN_SECONDS
			_update_card()

func _update_card() -> void:
	var id := _hovered if not _hovered.is_empty() else _pinned
	var player: Dictionary = model.players.get(id,{})
	_card_for = id if not player.is_empty() else ""
	if player.is_empty():
		if card!=null:card.hide()
		return
	if card==null:_build_card()
	var lines: PackedStringArray = [str(player.name),"等级 %d" % int(player.lv)]
	if int(player.ride)>=0:lines.append("骑乘：%s" % (str(player.rn) if not str(player.rn).is_empty() else Riding.pet_name(int(player.ride))))
	if bool(player.b):lines.append("战斗中")
	_card_text.text = "\n".join(lines)
	_card_face.texture = Faces.texture(str(player.c),int(player.face))
	_card_face.visible = _card_face.texture!=null
	card.reset_size()
	card.show()
	_place_card()

func _build_card() -> void:
	card = PanelContainer.new()
	card.name = "PlayerCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel",_card_style())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation",8)
	card.add_child(row)
	_card_face = TextureRect.new()
	_card_face.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_card_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_card_face)
	_card_text = world.text("",13)
	_card_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_card_text)
	world.ui_root.add_child(card)

func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13,0.1,0.07,0.9)
	style.border_color = Color("9d8354")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,6)
	return style

func _place_card() -> void:
	var id := _hovered if not _hovered.is_empty() else _pinned
	var holder: Node2D = nodes.get(id)
	if holder==null or not is_instance_valid(holder):return
	var screen: Vector2 = holder.get_global_transform_with_canvas().origin
	var bounds: Vector2 = world.get_viewport().get_visible_rect().size
	card.position = (screen+Vector2(24,-card.size.y-24)).clamp(Vector2.ZERO,(bounds-card.size).max(Vector2.ZERO))

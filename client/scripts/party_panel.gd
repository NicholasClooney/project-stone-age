extends Control
## 组队 on a multi-profile server (LAN phase 3, docs/development/lan-profiles.md;
## the server side is server/party.gd, run by the hub).
##
## - The classic bar's 加入队伍 button (26105) joins the player in front of
##   you, or leaves the party when you are in one (field.cpp FIELD_FUNC_PARTY
##   sends PR 1 or PR 0). A leader leaving disbands the party.
## - The 组队 switch (「接受其他人加入队伍」) starts on and lives in 设置 → 组队
##   (settings_menu.gd): only players with it on can be joined. The original
##   keeps it in MENU (26101)'s 其他设定 window (field.cpp etcSwitch, with
##   决斗, 名片, 聊天 and 交易); here MENU opens 设置 instead.
## - The party list (top left) shows the members, the leader first with ★;
##   the leader can 踢出 a member or 解散队伍, a member can 离开队伍.
## - When the leader meets enemies, every member not already fighting joins
##   the same battle (LAN phase 4a, server/party_battles.gd); a member who
##   escaped from it sees 「队长战斗中」 until it ends.
## - 「队伍共享经验」 (ours, not the original's): in the list, the leader's
##   switch, on by default; members see whether it is on.
## - The leader wears the original leader flag (SPR_leader 100500, the frames
##   tools/import_ui.py writes as ui/25600..25609), over the head where the
##   V.S. mark goes, hidden while fighting (character.cpp).
##
## Members cannot walk on their own: GameScene asks party_locked() before a
## step, a 瞬移 or a map load, and the server moves them after the leader.
## A game without a multi-profile server never gets a `party` event; the
## button then only plays the original's refusal sound.
const MARK_FALLBACK_COLOR := Color("ffd040")

var world: Node2D
## The last `party` event: {accept, leader, members: [{id, name, lv}], battle, me}.
var view: Dictionary = {}
var list: PanelContainer
var list_rows: VBoxContainer
var banner: Label
var _own_mark: Node2D
var _list_key := ""

func configure(owner: Node2D) -> void:
	world = owner
	name = "PartyPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	list = PanelContainer.new()
	list.name = "PartyList"
	list.position = Vector2(8,86)
	list.add_theme_stylebox_override("panel",_style())
	list.hide()
	add_child(list)
	list_rows = VBoxContainer.new()
	list_rows.add_theme_constant_override("separation",3)
	list.add_child(list_rows)
	banner = world.text("队长战斗中",20)
	banner.name = "LeaderBattle"
	banner.add_theme_color_override("font_color",Color("ffe070"))
	banner.add_theme_color_override("font_outline_color",Color.BLACK)
	banner.add_theme_constant_override("outline_size",4)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 96
	banner.offset_left = -160
	banner.offset_right = 160
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.hide()
	add_child(banner)
	if not world.last_party_event.is_empty():on_event(world.last_party_event)

# ---- state ------------------------------------------------------------------

## Logged into a multi-profile server: there is someone to party with.
func available() -> bool:
	return world!=null and world.link!=null and not world.link.is_local() and not world.link.account.is_empty()

func in_party() -> bool:
	return not str(view.get("leader","")).is_empty()

func is_leader() -> bool:
	return in_party() and str(view.leader)==str(view.get("me",""))

## A member follows the leader and cannot walk, warp or meet enemies itself.
func is_member() -> bool:
	return in_party() and str(view.leader)!=str(view.get("me",""))

## A backend event; only `party` concerns this panel.
func on_event(event: Dictionary) -> void:
	if str(event.get("type",""))!="party":return
	view = event.duplicate()
	_refresh()

## The connection dropped: the server sends the view again after a reconnect.
func reset() -> void:
	view = {}
	world.last_party_event = {}
	_refresh()

func _refresh() -> void:
	var key := JSON.stringify([view.get("leader",""),view.get("members",[]),view.get("me",""),view.get("share_exp",true)])
	if key!=_list_key:
		_list_key = key
		_rebuild_list()

func _process(_delta: float) -> void:
	var shown: bool = available() and in_party() and not world.data.is_empty()
	list.visible = shown
	if shown:_place_list()
	banner.visible = shown and bool(view.get("battle",false)) and not (is_instance_valid(world.battle_view) and world.battle_view.visible)
	_own_leader_mark()

## Below the top-left HUD (游戏助手 and the Lv / 体力 / 石币 line, which can
## grow a second line for the automation), never over it.
func _place_list() -> void:
	var top := 86.0
	for node in [world.get("helper_button"),world.get("adventure_hint")]:
		if node is Control and is_instance_valid(node) and node.is_visible_in_tree():
			top = maxf(top,node.position.y+node.size.y+6)
	list.position = Vector2(8,top)

# ---- 加入队伍 ------------------------------------------------------------------

## The classic bar's 加入队伍: join the player in front, or leave the party.
func press_party_button() -> void:
	if not available():
		world.play_battle_sound(220)
		_say("单人模式没有其他玩家，不能组队。")
		return
	if in_party():
		leave()
		return
	if is_instance_valid(world.battle_view) and world.battle_view.visible:
		world.play_battle_sound(220)
		return
	_face_neighbour()
	world.play_battle_sound(217)
	world.link.request({"type":"party_join","facing":int(world.player.facing)},func(reply: Dictionary):
		if not bool(reply.get("ok",false)) and str(reply.get("reason",""))!="offline":_say(str(reply.get("reason","无法加入团队。"))))

## Nobody on the cell in front but exactly one player right next to you: turn
## to face them first, so joining does not need a step to turn around.
func _face_neighbour() -> void:
	if not is_instance_valid(world.remote_players):return
	var cell: Vector2i = world.cell
	var ahead: Vector2i = cell+world.SCREEN_DIRECTIONS[(int(world.player.facing)+4)%8]
	var around: Array = []
	for player in world.remote_players.model.players.values():
		var at: Vector2i = player.cell
		if at==ahead:return
		if at!=cell and maxi(absi(at.x-cell.x),absi(at.y-cell.y))==1 and not at in around:around.append(at)
	if around.size()!=1:return
	world.player.facing = (world.SCREEN_DIRECTIONS.find(Vector2i(around[0])-cell)+4)%8
	world.player.set_action(3)

func leave() -> void:
	world.play_battle_sound(217)
	world.link.request({"type":"party_leave"},_on_reply)

func kick(id: String) -> void:
	world.link.request({"type":"party_kick","id":id},_on_reply)

func set_accept(on: bool) -> void:
	world.link.request({"type":"party_switch","on":on},_on_reply)

func _on_reply(reply: Dictionary) -> void:
	if not bool(reply.get("ok",false)) and str(reply.get("reason",""))!="offline":_say(str(reply.get("reason","")))

## Feedback in the chat lines (yellow, as the original's system lines).
func _say(line: String) -> void:
	if line.is_empty():return
	if is_instance_valid(world.chat_panel) and world.chat_panel.available():world.chat_panel.add_line(line,world.chat_panel.SYSTEM_COLOR)
	if is_instance_valid(world.message):world.message.text = line

## What the bar says when the pointer rests on 加入队伍 (field.cpp).
func button_caption() -> String:
	if not available():return "不能加入队伍。"
	if is_leader():return "解散队伍。"
	if in_party():return "离开队伍。"
	return "加入队伍。"

# ---- the party list ---------------------------------------------------------

func _rebuild_list() -> void:
	for child in list_rows.get_children():child.queue_free()
	if not in_party():return
	var members: Array = view.get("members",[])
	var title: Label = world.text("队伍（%d/%d）" % [members.size(),5],13)
	title.add_theme_color_override("font_color",Color("ffe070"))
	list_rows.add_child(title)
	for member in members:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",6)
		var leader: bool = str(member.id)==str(view.leader)
		var label: Label = world.text("%s%s  Lv%d%s" % ["★" if leader else "　",str(member.name),int(member.lv),"（队长）" if leader else ""],13)
		if str(member.id)==str(view.get("me","")):label.add_theme_color_override("font_color",Color("b8f0ff"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if is_leader() and not leader:
			var id := str(member.id)
			var out: Button = world.button("踢出",func():kick(id))
			out.name = "Kick_"+id
			out.add_theme_font_size_override("font_size",11)
			row.add_child(out)
		list_rows.add_child(row)
	list_rows.add_child(_share_row())
	var action: Button = world.button("解散队伍" if is_leader() else "离开队伍",leave)
	action.name = "LeaveParty"
	action.add_theme_font_size_override("font_size",11)
	list_rows.add_child(action)
	if is_member():
		var note: Label = world.text("跟着队长走；队长遇敌时一起战斗。",11)
		note.add_theme_color_override("font_color",Color("c8bea0"))
		list_rows.add_child(note)
	list.reset_size()

## 「队伍共享经验」: every defeated enemy gives its full experience to every
## living member and their pets (not split; the original's level gap still
## applies). Off: the original's rule, only whoever defeated it. The leader
## switches it; it counts from the party's next battle.
func _share_row() -> Control:
	var on := shares_exp()
	if is_leader():
		var box := CheckBox.new()
		box.name = "PartyShareExp"
		box.text = "队伍共享经验"
		box.button_pressed = on
		box.add_theme_font_size_override("font_size",12)
		box.tooltip_text = "打开：每个被打倒的敌人，全额经验给每位活着的队员和他们的宠物（仍按原版等级差折减）。\n关闭：原版规则，只给打倒它的人或宠物。\n本作新增的便利功能，不是原版规则。"
		box.toggled.connect(set_share_exp)
		return box
	var note: Label = world.text("队伍共享经验：%s" % ("开" if on else "关"),11)
	note.name = "PartyShareExpNote"
	note.add_theme_color_override("font_color",Color("c8bea0"))
	return note

func shares_exp() -> bool:
	return bool(view.get("share_exp",true))

func set_share_exp(on: bool) -> void:
	world.link.request({"type":"party_share_exp","on":on},_on_reply)

# ---- the 组队 switch (设置 → 组队) ------------------------------------------------

## Whether others may join this player's party (the server's view; on by default).
func accepting() -> bool:
	return bool(view.get("accept",true))

func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13,0.1,0.07,0.88)
	style.border_color = Color("9d8354")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,6)
	return style

# ---- the leader flag ----------------------------------------------------------

func _own_leader_mark() -> void:
	var wanted: bool = is_leader() and is_instance_valid(world.player) and not (is_instance_valid(world.battle_view) and world.battle_view.visible)
	if wanted and (not is_instance_valid(_own_mark) or _own_mark.get_parent()!=world.player):
		_own_mark = leader_mark()
		world.player.add_child(_own_mark)
	if is_instance_valid(_own_mark):_own_mark.visible = wanted

## The original leader flag: SPR_leader (100500), 16 frames in 2 s, over the
## head. Before tools/import_ui.py has written its frames, a small 队长 badge.
static func leader_mark() -> Node2D:
	var frames := _leader_frames()
	var mark: Node2D
	if frames!=null:
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.play("default")
		mark = sprite
	else:
		var badge := Label.new()
		badge.text = "队长"
		badge.add_theme_font_size_override("font_size",11)
		badge.add_theme_color_override("font_color",MARK_FALLBACK_COLOR)
		badge.add_theme_color_override("font_outline_color",Color.BLACK)
		badge.add_theme_constant_override("outline_size",3)
		badge.position = Vector2(-12,-10)
		mark = Node2D.new()
		mark.add_child(badge)
	mark.name = "LeaderMark"
	mark.position = Vector2(0,-96)
	mark.z_index = 20
	return mark

static var _frames_cache: SpriteFrames
static var _frames_checked := false
static func _leader_frames() -> SpriteFrames:
	if _frames_checked:return _frames_cache
	_frames_checked = true
	var path := "res://assets/legacy/ui/manifest.json"
	if not FileAccess.file_exists(path):return null
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	var info = manifest.get("leader_mark",{}) if manifest is Dictionary else {}
	if not info is Dictionary or info.get("frames",[]).is_empty():return null
	var frames := SpriteFrames.new()
	var sequence: Array = info.frames
	frames.set_animation_speed("default",sequence.size()*1000.0/maxf(1.0,float(info.get("duration_ms",2000))))
	frames.set_animation_loop("default",true)
	for ident in sequence:
		var file := "res://assets/legacy/ui/%d.png" % int(ident)
		if not ResourceLoader.exists(file):return null
		frames.add_frame("default",load(file))
	_frames_cache = frames
	return frames

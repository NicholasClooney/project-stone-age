extends RefCounted
## Redrawing open panels for the game scene (scripts/game.gd) when backend
## data changes: throttling while automation runs, keeping each list's scroll
## place, and not rebuilding under text the player is typing. The timestamps
## and flags stay on the game; see docs/technical/game-scripts.md.
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

## Profile updates can arrive after the action that caused them (always over a
## network link, or from automation). Redraw whatever is open, once per frame.
## Returns true when a panel kept its old contents because the player is
## typing in it; the caller redraws it once they stop.
func refresh_open_panels() -> bool:
	var deferred := false
	if is_instance_valid(game.dev_gm_menu) and game.dev_gm_menu.visible:game.dev_gm_menu._refresh_actor()
	for panel in [game.adventure_menu,game.pet_training]:
		if not is_instance_valid(panel) or not panel.visible:continue
		if _typing_in(panel):deferred = true
		else:rebuild_keeping_scroll(panel)
	var profile_now: Dictionary = game.state.profile
	var active := int(profile_now.get("active_pet",-1))
	var pets: Array = profile_now.get("pets",[])
	var companion_key := [active,int(profile_now.get("ride_pet",-1)),str(profile_now.get("character_id","")),
		pets[active].get("sprite",-1) if active>=0 and active<pets.size() else -1,int(pets[active].get("hp",0))>0 if active>=0 and active<pets.size() else false]
	if companion_key!=game._companion_key:
		game._companion_key = companion_key
		game.refresh_companion()
	return deferred

## One redraw path for both links. A remote client learns of every profile
## change late, its own actions included. In-process, panels redraw themselves
## after the player's actions, so only automation running behind a minimized
## window changes the profile under an open panel.
func _mark_ui_stale() -> void:
	if not game.link.is_local() or game.automation_minimized():game._ui_stale = true

## While automation runs, open panels redraw at most every UI_REFRESH_MSEC and
## never under a held mouse button, so a click lands on the button it pressed.
func _ui_refresh_held() -> bool:
	if not game._automation_running():return false
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Time.get_ticks_msec()-game._ui_refreshed_msec < GameScene.UI_REFRESH_MSEC

## Lifts the field-input lock unless a battle, the adventure menu or minimized
## automation still needs it.
func release_input() -> void:
	game.paused_input = game.battle_view.visible or game.adventure_menu.visible or game.automation_minimized()

## Rebuilds a panel for new data without moving the player's place in its
## lists: scroll areas are matched by order and restored once laid out.
func rebuild_keeping_scroll(panel: Control) -> void:
	var controls := _scroll_areas(panel)
	var before := capture_scroll(panel)
	panel.rebuild()
	# Reconciled warehouses/records retain their scroll controls and handle
	# layout themselves. A deferred restore would overwrite a later user scroll.
	if controls!=_scroll_areas(panel):restore_scroll(panel,before)

## Scroll positions of every scroll area under root, in tree order.
func capture_scroll(root: Node) -> Array[Vector2i]:
	var before: Array[Vector2i] = []
	for scroll in _scroll_areas(root):before.append(Vector2i(scroll.scroll_horizontal,scroll.scroll_vertical))
	return before

## Puts positions from capture_scroll back on root's rebuilt scroll areas.
func restore_scroll(root: Node, before: Array[Vector2i]) -> void:
	if before.is_empty() or before.all(func(position: Vector2i):return position==Vector2i.ZERO):return
	var after := _scroll_areas(root)
	for i in range(mini(before.size(),after.size())):
		var scroll: ScrollContainer = after[i]
		var position: Vector2i = before[i]
		var restore := func():
			if is_instance_valid(scroll):
				scroll.scroll_horizontal = position.x
				scroll.scroll_vertical = position.y
		# The new content has no size yet: apply after this frame's layout, and
		# again next frame in case its content sorted later.
		restore.call_deferred()
		game.get_tree().process_frame.connect(restore,CONNECT_ONE_SHOT)

func _scroll_areas(root: Node) -> Array[ScrollContainer]:
	var found: Array[ScrollContainer] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		if node.is_queued_for_deletion():continue
		if node is ScrollContainer:found.append(node)
		pending.append_array(node.get_children())
	return found

## A rebuild would discard text the player is typing (a pet name, a filter).
## Focus alone is not typing: a number box keeps focus after a click on it or
## its arrows, and treating that as typing froze the panel (for example the
## 同种比较 list missing a newly caught pet) until focus moved elsewhere.
func _typing_in(panel: Control) -> bool:
	var focused := game.get_viewport().gui_get_focus_owner()
	return focused is LineEdit and panel.is_ancestor_of(focused) and Time.get_ticks_msec()-game._last_typing_msec < GameScene.TYPING_GRACE_MSEC

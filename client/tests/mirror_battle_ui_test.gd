extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
	if ok:print("PASS: "+label)
	else:push_error(label);failures+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	var battle=preload("res://server/battle_session.gd").new()
	var initial:Dictionary=battle.start_battle({"mirror_available":true,"enemy_max_hp":500,"player_speed":999})
	var view=preload("res://scripts/battle_view.gd").new()
	root.add_child(view);await process_frame
	view.open_battle(initial)
	view._process(view.feedback_until-view.elapsed+0.1)
	view._request_action("magic")
	check(view.choice_panel.get_child_count()==3,"magic offers mirror self, mirror pet and healing charm")
	check(view.choice_panel.get_child(1).disabled,"pet cast unavailable without active pet")
	check(view.choice_panel.get_child(2).disabled,"healing charm unavailable without charm or active pet")
	view.pending_action="mirror_self"
	var after:Dictionary=battle.submit_action("mirror_self")
	view.state=after
	view.queue_group_turn(initial)
	check(view.mirror_cues.size()>=2 and view.mirror_cues[0].id==100600 and view.mirror_cues[1].id==100610,"cast schedules original caster and reflection sequences")
	check(view.mirror_cues[1].index==0,"self cast targets player actor")
	view.pending_action="mirror_pet";view.queue_group_turn(initial)
	check(view.mirror_cues[1].index==2,"pet cast targets pet actor")
	view.pending_action="mirror_self";view.queue_group_turn(initial)
	view._process(0.1)
	check(not view.mirror_effects.is_empty() and view.mirror_effects[0].sprite.texture!=null,"original effect sprite texture loads during playback")
	view._process(5.0)
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/mvp/mirror-effects.json"))
	check(data.images.size()==48,"both original effect sequences expose 48 images")
	view.queue_free();await process_frame
	quit(1 if failures else 0)

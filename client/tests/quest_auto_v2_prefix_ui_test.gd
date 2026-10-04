extends "res://tests/quest_auto_v2_motion_ui_test.gd"
## Synthetic bent committed prefix; no route authorization or pixels claim.
class Actor extends Node2D:
	var facing:=0
	func set_action(_action:int)->void:pass
func stride(count:int)->Dictionary:
	var event:=packet(1,count)
	event.quest_segment_id="bend";event.quest_ack_required=count==3
	event.cell=[[11,10],[11,11],[12,11]][count-1]
	event.quest_segment={"id":"bend","kind":"public_stride","mode":"C","from_map":1000,"from_cell":[10,10],"interval_seconds":0.1,"cells":[]}
	for cell in [[11,10],[11,11],[12,11]].slice(0,count):event.quest_segment.cells.append({"map_id":1000,"cell":cell})
	return event
func run()->void:
	Game.server_url_override="ws://127.0.0.1:1";game=Game.new();Game.server_url_override=""
	wire=RecordingLink.new();game.link=wire
	game.data={"map_id":1000};game.cell=Vector2i(10,10)
	game.player=Actor.new();game.add_child(game.player)
	game.battle_view=Control.new();game.battle_view.hide();game.add_child(game.battle_view)
	game.state.derived.quest_auto={"running":true,"phase":"travel","run_id":"run-one","step_id":"step-one","revision":1,"motion":{"awaiting_ack":true}}
	if not check(game._remote.accept_quest_position(stride(1)),"First committed cell accepted"):return
	if not check(game._remote._step_follow() and game.target_cell==Vector2i(11,10),"First prefix starts exact first cell"):return
	if not check(game._remote.accept_quest_position(stride(3)),"Final prefix can arrive during first animation"):return
	if not check(game._remote.quest_prefix.size()==3 and is_equal_approx(game._remote.follow_interval(),0.1),"Only committed three cells queued at server cadence"):return
	for expected in [Vector2i(11,10),Vector2i(11,11),Vector2i(12,11)]:
		if not check(game.target_cell==expected and not game._remote.report_position(),"No shortcut or premature endpoint ACK"):return
		game.cell=game.target_cell;game.moving=false;game._following_step=false
		game._remote._step_follow()
	if not check(game._remote.quest_prefix.is_empty() and game._remote.report_position() and wire.commands.back().quest_position_seq==3,"Final shown bend endpoint ACK uses final event identity"):return
	game._remote.clear_quest_receipt();game.cell=Vector2i(10,10)
	game._remote.accept_quest_position(stride(3))
	var next_segment:=packet(1,4)
	next_segment.cell=[12,12];next_segment.quest_segment_id="next-bend"
	next_segment.quest_segment={"id":"next-bend","kind":"public_stride","mode":"C","from_map":1000,"from_cell":[12,11],"interval_seconds":0.1,"cells":[{"map_id":1000,"cell":[12,12]}]}
	game._remote.accept_quest_position(next_segment)
	if not check(game._remote.quest_prefix.size()==4,"Slow second-device display retains earlier committed bends across next segment"):return
	game._remote.clear_quest_receipt();game.cell=Vector2i(11,11)
	game._remote.accept_quest_position(stride(3))
	if not check(game._remote.quest_prefix==[[1000,Vector2i(12,11)]],"New observer already at a prefix cell never replays earlier cells backwards"):return
	game._remote.clear_quest_receipt();game.cell=Vector2i(10,10)
	game._remote.accept_quest_position(stride(1));game._remote._step_follow()
	game.state.automation={"position":{"map_id":1000,"cell":[11,10]}}
	game.state.derived.quest_auto.phase="battle";game.state.derived.quest_auto.motion={}
	game._remote.sync_quest_receipt()
	if not check(game._remote.quest_prefix.is_empty() and not game.moving and not game._remote.accept_quest_position(stride(3)),"Battle discards old prefix and rejects late tail"):return
	game.state.derived.quest_auto.phase="segment_landing"
	game.state.derived.quest_auto.motion={"awaiting_ack":true}
	var correction:=packet(1,4);correction.quest_segment={"kind":"walk","mode":"A"}
	game.cell=Vector2i(10,10);game._followed=[1000,game.cell]
	game._remote.accept_quest_position(correction)
	if not check(game._remote.report_position() and wire.commands.back().quest_segment_id==correction.quest_segment_id,"A/walk correction with required ACK retains complete identity"):return
	game.state.derived.quest_auto.settings={"mode":"C"};game.state.derived.quest_auto.effective_mode="A"
	game.state.derived.quest_auto.mode_notice="重启恢复先沿A原路推进；重新启动任务后应用所选模式。"
	var travel=preload("res://scripts/quest_helper_travel.gd").new();travel.configure(game)
	if not check(travel.auto_mode().contains("实际 A") and travel.auto_mode().contains("意图 C") and travel.auto_status().contains("重新启动"),"Restart notice retains preference and names fresh-start requirement"):return
	travel.free();game.free()
	print("QUEST AUTO V2 PREFIX UI: PASS");quit(0)

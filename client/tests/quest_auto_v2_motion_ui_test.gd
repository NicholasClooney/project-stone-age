extends SceneTree
## Isolated production client adapter with synthetic snapshots and a recording
## transport. No backend, rendered pixels, B/C executor or route claim.
const Game=preload("res://scripts/game.gd")
class RecordingLink extends RefCounted:
	var commands:Array=[]
	var online:=true
	func is_local()->bool:return false
	func request(command:Dictionary,_done:Callable=Callable())->Dictionary:
		commands.append(command.duplicate(true));return {"ok":true}
var game
var wire:RecordingLink
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->bool:
	if not value:push_error(label);quit(1)
	return value
func packet(revision:int,serial:int=1)->Dictionary:
	return {"type":"position","client":"quest_auto","map_id":1000,"cell":[10,10],"quest_run_id":"run-one","quest_step_id":"step-one","quest_revision":revision,"quest_segment_id":"segment-%d"%serial,"quest_position_seq":serial,"quest_ack_required":true}
func run()->void:
	Game.server_url_override="ws://127.0.0.1:1"
	game=Game.new();Game.server_url_override=""
	wire=RecordingLink.new();game.link=wire
	game.data={"map_id":1000};game.cell=Vector2i(10,10)
	game._followed=[1000,game.cell]
	game.state.automation={"position":{"map_id":1000,"cell":[10,10]}}
	game.state.derived.quest_auto={"running":true,"phase":"landing","run_id":"run-one","step_id":"step-one","revision":1,"motion":{"awaiting_ack":true}}
	if not check(game.backend==null,"Adapter runs without a backend"):return
	if not check(not game._remote.report_position() and wire.commands.is_empty(),"Snapshot alone cannot invent a new-protocol receipt"):return
	var event:=packet(2)
	if not check(game._remote.accept_quest_position(event),"New event may precede updated profile snapshot"):return
	event.quest_revision=999
	if not check(game.get_meta("quest_position_receipt",{}).quest_revision==2,"Receipt is a deep copy of the event"):return
	game.moving=true
	if not check(not game._remote.report_position() and wire.commands.is_empty(),"Unfinished animation cannot acknowledge"):return
	game.moving=false;game.area_transition_busy=true
	if not check(not game._remote.report_position(),"Unfinished map transition cannot acknowledge"):return
	game.area_transition_busy=false
	if not check(game._remote.report_position() and wire.commands.back().quest_revision==2 and wire.commands.back().quest_step_id=="step-one","ACK freezes event identity rather than older snapshot"):return
	if not check(not game._remote.accept_quest_position(packet(2)),"Repeated sequence is ignored"):return
	game.state.derived.quest_auto.revision=3
	if not check(not game._remote.report_position(),"Newer snapshot cannot re-label an old displayed event"):return
	game._remote.sync_quest_receipt()
	if not check(game.get_meta("quest_position_receipt",{}).is_empty() and not game._remote.accept_quest_position(packet(2)),"New revision clears and rejects stale event"):return
	if not check(game._remote.accept_quest_position(packet(3,2)),"Current replacement event accepted"):return
	game._follow=[1000,Vector2i(11,10)];game._following_step=true;game.moving=true
	game._remote._on_link_disconnected()
	if not check(game.get_meta("quest_position_receipt",{}).is_empty() and game._follow.is_empty() and not game.moving and not game._following_step,"Disconnect clears receipt and old in-flight presentation"):return
	game.state.derived.quest_auto.detached=true
	game.cell=Vector2i(9,10)
	if not check(not game._remote.report_position(),"Reconnect cannot report stale local position"):return
	game.cell=Vector2i(10,10)
	if not check(game._remote.report_position(),"Reconnect reports current authority cell"):return
	for field in game._remote.QUEST_RECEIPT_FIELDS:
		if not check(not wire.commands.back().has(field),"Handshake has no cached "+field):return
	if not check(game._remote.accept_quest_position(packet(3,3)),"Fresh rebind event can precede detached=false profile publish"):return
	game.state.derived.quest_auto.detached=false
	game._remote.sync_quest_receipt()
	game._followed=[1000,game.cell]
	if not check(game._remote.report_position() and wire.commands.back().quest_position_seq==3,"Fresh server event restores full acknowledgement"):return
	game.state.derived.quest_auto.running=false
	game._remote.sync_quest_receipt()
	if not check(game.get_meta("quest_position_receipt",{}).is_empty() and not game._remote.accept_quest_position(packet(3,3)),"Cancelled run cannot restore motion via late packet"):return
	game.state.derived.quest_auto={}
	if not check(game._remote.accept_quest_position({"quest_position_seq":7,"map_id":1000,"cell":[10,10]}) and game._remote.report_position() and wire.commands.back().quest_position_seq==7 and not wire.commands.back().has("quest_run_id"),"Old A server seq-only presentation remains compatible"):return
	game.free()
	print("QUEST AUTO V2 MOTION UI SYNTHETIC: PASS")
	quit(0)

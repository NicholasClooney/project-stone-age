extends "res://tests/quest_auto_background_ui_test.gd"
## Explicit closed capability fixture plus isolated consumer/callback guards. The
## synthetic true event and reply cases below are not public-server admission.
class ClosedBackend:
	extends "res://server/backend.gd"
	func _quest_loot_public_enabled()->bool:return false

class TestPeer extends RefCounted:
	pass

class DeferredLink extends RefCounted:
	signal connected
	signal disconnected
	var online:=true
	var account:Dictionary={}
	var _lifecycle:=1
	var _peer=TestPeer.new()
	var commands:Array=[]
	var callbacks:Array=[]
	var sequences:Array=[]
	var next_sequence:=1
	func is_local()->bool:return false
	func request(command:Dictionary,done:Callable=Callable())->Dictionary:
		commands.append(command.duplicate(true))
		callbacks.append(done)
		sequences.append(next_sequence)
		next_sequence+=1
		return {"ok":false,"pending":true}
	func answer(index:int,reply:Dictionary)->void:
		if index>=0 and index<callbacks.size() and callbacks[index].is_valid():callbacks[index].call(reply)
	func drop()->void:
		online=false
		_lifecycle+=1
		_peer=TestPeer.new()
		disconnected.emit()
	func reconnect()->void:
		_lifecycle+=1
		_peer=TestPeer.new()
		online=true
		connected.emit()

func apply_synthetic_profile(capability:Variant,can_start:Variant,reason:String,running_override:Variant=null)->void:
	var derived:Dictionary=world.state.derived.duplicate(true)
	var auto_value=derived.get("quest_auto",{})
	var auto:Dictionary=auto_value.duplicate(true) if auto_value is Dictionary else {}
	if running_override is bool:auto.running=running_override
	auto["budget"]={"can_start":can_start,"reason":reason,"entry":null,"recovery_blocked":false}
	derived["quest_auto"]=auto
	var event:Dictionary={"type":"profile","rev":world.state.rev+1,"profile":world.state.profile.duplicate(true),"derived":derived,"options":world.state.options.duplicate(true),"capabilities":{"quest_loot_enabled":capability}}
	world.state.apply(event)

func synthetic_snapshot(can_start:bool,reason:String)->Dictionary:
	var derived:Dictionary=world.state.derived.duplicate(true)
	var auto_value=derived.get("quest_auto",{})
	var auto:Dictionary=auto_value.duplicate(true) if auto_value is Dictionary else {}
	auto["budget"]={"can_start":can_start,"reason":reason,"entry":null,"recovery_blocked":false}
	derived["quest_auto"]=auto
	return {"type":"snapshot","v":1,"rev":world.state.rev+1,"profile":world.state.full_profile(),"derived":derived,"options":world.state.options.duplicate(true),"battle":world.state.battle.duplicate(true),"battle_open":world.state.battle_open,"automation":world.state.automation.duplicate(true),"capabilities":{"quest_loot_enabled":true}}

func synthetic_started_snapshot(run_revision:int=3,budget_revision:int=4,running:bool=true,can_start:bool=false,recovery_blocked:bool=false,run_id:String="0123456789abcdef0123456789abcdef",budget_id:String="abcdef0123456789abcdef0123456789",budget_generation:int=1,entry_present:bool=true)->Dictionary:
	var snapshot:=synthetic_snapshot(false,"")
	var auto:Dictionary=snapshot.derived.quest_auto
	auto.running=running
	auto.run_id=run_id
	auto.step_id="jewels:hunt:2760"
	auto.revision=run_revision
	auto.budget.can_start=can_start
	auto.budget.recovery_blocked=recovery_blocked
	auto.budget.activity="recovery_locked" if recovery_blocked else ("running" if running else "stopped")
	auto.budget.reason="预算恢复锁定，请人工处理。" if recovery_blocked else ("服务器当前允许开始。" if can_start else "")
	auto.budget.entry={"step_id":"jewels:hunt:2760","budget_id":budget_id,"generation":budget_generation,"revision":budget_revision} if entry_present else null
	return snapshot

func ack(sequence:int,ok:bool,persisted:bool=true,run_id:String="0123456789abcdef0123456789abcdef",budget_id:String="abcdef0123456789abcdef0123456789",budget_generation:int=1)->Dictionary:
	return {"type":"ack" if ok else "rejected","seq":sequence,"ok":ok,"persisted":persisted,"run_identity":{"run_id":run_id,"step_id":"jewels:hunt:2760","revision":3},"budget_identity":{"budget_id":budget_id,"generation":budget_generation,"revision":4},"reason":"test-only reply"}

func public_start_button_disabled(expected:bool)->bool:
	var button=world.quest_helper_menu.find_child("QuestLootStart",true,false)
	return button is Button and button.disabled==expected

func public_start_reason_matches(expected:String)->bool:
	var reason=world.quest_helper_menu.find_child("QuestLootStartReason",true,false)
	return reason is Label and reason.text==expected

func run()->void:
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1280,720)
	remote_mode=true
	backend_node=ClosedBackend.new();backend_node.set_process(false);root.add_child(backend_node)
	server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
	if not check(server_node.start()==OK,"Closed public UI test server starts on port zero"):return
	if not await create_world():return
	world.set_physics_process(false)
	var menu=world.quest_helper_menu
	menu.open_menu()
	if not check(world.backend==null and not world.state.quest_loot_enabled(),"Real remote ClosedBackend snapshot keeps public loot capability false"):return
	if not check(menu.find_child("QuestLootStart",true,false)==null,"Missing/false capability hides the public start entry completely"):return
	if not check(not world.quest_helper_travel.start_public_loot(),"Closed capability cannot dispatch a start request"):return
	apply_synthetic_profile("true",true,"")
	if not await ready(func():return menu.find_child("QuestLootStart",true,false)==null,"Non-boolean capability cannot reveal the public start entry"):return
	apply_synthetic_profile(true,"true","can_start must be a boolean")
	if not await ready(func():
		var entry=menu.find_child("QuestLootStart",true,false)
		return entry is Button and entry.disabled and menu.find_child("QuestLootStartReason",true,false)!=null,
		"Synthetic consumer event shows but disables malformed eligibility"):return
	apply_synthetic_profile(true,false,"服务端暂不允许开始。")
	if not await ready(func():return public_start_button_disabled(true) and public_start_reason_matches("服务端暂不允许开始。"),"Strict false preserves the server refusal reason"):return
	apply_synthetic_profile(false,true,"")
	if not await ready(func():return menu.find_child("QuestLootStart",true,false)==null and not world.quest_helper_travel.start_public_loot(),"Capability revocation hides the entry and blocks dispatch despite true budget eligibility"):return
	apply_synthetic_profile(true,true,"")
	if not await ready(func():return public_start_button_disabled(false),"Synthetic consumer event enables only literal true eligibility"):return
	var real_link=world.link
	var fake:=DeferredLink.new()
	fake.disconnected.connect(world.quest_helper_travel._on_loot_link_changed)
	fake.connected.connect(world.quest_helper_travel._on_loot_link_changed)
	world.link=fake
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	if not check(fake.commands==[{"type":"quest_loot_start"}] and fake.sequences.size()==1 and world.quest_helper_travel.loot_start_pending,"One click dispatches exactly one type-only dedicated start request and waits for its callback"):return
	# An unrelated but valid state event can race the command reply. It does not
	# resolve an ambiguous persisted-negative response for this operation.
	apply_synthetic_profile(true,true,"")
	var before_budget:Dictionary=world.state.derived.quest_auto.budget.duplicate(true)
	fake.answer(0,{"type":"rejected","seq":fake.sequences[0],"ok":false,"persisted":true,"reason":"启动状态待确认"})
	if not check(fake.commands.size()==2 and fake.commands[1]=={"type":"snapshot"} and world.state.derived.quest_auto.budget==before_budget and world.quest_helper_travel.loot_start_waiting_snapshot,"Persisted-negative refreshes once even after a racing state event, without mutating budget or replaying start"):return
	fake.answer(1,{"type":"ack","seq":fake.sequences[1],"ok":true,"snapshot":synthetic_snapshot(false,"已有预算")})
	if not await ready(func():return not world.quest_helper_travel.loot_start_waiting_snapshot and not world.quest_helper_travel.loot_snapshot_pending and world.state.derived.quest_auto.budget.can_start==false,"Snapshot consumer installs the authoritative closed eligibility state"):return
	if not check(fake.commands.size()==2,"Snapshot resolution does not retry quest_loot_start"):return
	apply_synthetic_profile(true,true,"")
	if not await ready(func():return public_start_button_disabled(false),"Fresh synthetic state permits an isolated callback case"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	var lifecycle_index:=2
	var before_lifecycle_reply:Dictionary=world.state.derived.quest_auto.budget.duplicate(true)
	fake.drop()
	if not check(not world.quest_helper_travel.loot_start_pending and world.quest_helper_travel.loot_start_waiting_snapshot,"Link lifecycle change retires the pending UI request"):return
	var lifecycle_feedback:String=world.quest_helper_travel.loot_start_feedback
	fake.answer(lifecycle_index,ack(fake.sequences[lifecycle_index],true))
	if not check(world.state.derived.quest_auto.budget==before_lifecycle_reply and world.quest_helper_travel.loot_start_feedback==lifecycle_feedback and fake.commands.size()==3,"Reply from the retired peer cannot update state or dispatch a retry"):return
	fake.reconnect()
	apply_synthetic_profile(true,true,"")
	if not await ready(func():return not world.quest_helper_travel.loot_start_waiting_snapshot and public_start_button_disabled(false),"Fresh profile event clears only the stale-view lock"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	var generation_index:=3
	world.quest_helper_travel._retire_public_loot_start(world.quest_helper_travel.loot_start_generation,"test-local generation retirement")
	apply_synthetic_profile(true,true,"")
	if not await ready(func():return not world.quest_helper_travel.loot_start_waiting_snapshot and public_start_button_disabled(false),"Fresh state allows a distinct operation after local retirement"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	if not check(fake.commands.size()==5 and fake.commands[3]=={"type":"quest_loot_start"} and fake.commands[4]=={"type":"quest_loot_start"},"Each distinct enabled user action sends one type-only start; no implicit replay"):return
	var feedback_before:String=world.quest_helper_travel.loot_start_feedback
	fake.answer(generation_index,ack(fake.sequences[generation_index],true))
	if not check(world.quest_helper_travel.loot_start_pending and world.quest_helper_travel.loot_start_feedback==feedback_before and world.state.derived.quest_auto.budget.can_start==true,"Older operation generation cannot consume the current request or alter ClientState"):return
	var identity_reply:=ack(fake.sequences[4],true)
	identity_reply.run_identity={};identity_reply.budget_identity={}
	fake.answer(4,identity_reply)
	if not check(fake.commands.size()==6 and fake.commands[5]=={"type":"snapshot"} and not world.quest_helper_travel.loot_start_pending and world.quest_helper_travel.loot_start_waiting_snapshot and not world.quest_helper_travel.loot_start_feedback.contains("已确认持久化"),"Malformed ACK identities neither claim success nor trigger another start"):return
	fake.answer(5,{"type":"ack","seq":fake.sequences[5],"ok":true,"snapshot":synthetic_snapshot(true,"")})
	if not await ready(func():return not world.quest_helper_travel.loot_start_waiting_snapshot,"Ordinary snapshot consumer releases the malformed-reply hold"):return
	apply_synthetic_profile(true,true,"")
	if not await ready(func():return public_start_button_disabled(false),"New server-shaped event enables the logout-generation case"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	var malformed_boolean_index:=6
	var malformed_boolean_reply:=ack(fake.sequences[malformed_boolean_index],true)
	malformed_boolean_reply.ok="true"
	malformed_boolean_reply.persisted="true"
	fake.answer(malformed_boolean_index,malformed_boolean_reply)
	if not check(fake.commands.size()==8 and fake.commands[7]=={"type":"snapshot"} and world.quest_helper_travel.loot_start_waiting_snapshot and not world.quest_helper_travel.loot_start_feedback.contains("已确认持久化"),"Non-boolean ok/persisted fields cannot claim success and request one authoritative snapshot"):return
	fake.answer(7,{"type":"ack","seq":fake.sequences[7],"ok":true,"snapshot":synthetic_snapshot(true,"")})
	if not await ready(func():return not world.quest_helper_travel.loot_start_waiting_snapshot and public_start_button_disabled(false),"Snapshot resolves malformed boolean ACK without retrying start"):return
	apply_synthetic_profile(true,true,"")
	if not await ready(func():return public_start_button_disabled(false),"New server-shaped event enables the logout-generation case"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	var logout_generation_index:=8
	world._remote.logout_generation+=1
	fake.answer(logout_generation_index,ack(fake.sequences[logout_generation_index],true))
	if not check(not world.quest_helper_travel.loot_start_pending and world.quest_helper_travel.loot_start_waiting_snapshot and not world.quest_helper_travel.loot_start_feedback.contains("已确认持久化") and fake.commands.size()==9,"Late ACK after profile-switch generation change is ignored without retry"):return
	apply_synthetic_profile(true,true,"")
	if not await ready(func():return not world.quest_helper_travel.loot_start_waiting_snapshot and public_start_button_disabled(false),"Fresh state permits owner-disposal case"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	var replaced_link_index:=9
	var before_replaced_link:Dictionary=world.state.derived.quest_auto.budget.duplicate(true)
	var replacement_link:=DeferredLink.new()
	replacement_link.disconnected.connect(world.quest_helper_travel._on_loot_link_changed)
	replacement_link.connected.connect(world.quest_helper_travel._on_loot_link_changed)
	world.link=replacement_link
	fake.answer(replaced_link_index,ack(fake.sequences[replaced_link_index],true))
	if not check(fake.commands.size()==10 and world.state.derived.quest_auto.budget==before_replaced_link and not world.quest_helper_travel.loot_start_pending and world.quest_helper_travel.loot_start_waiting_snapshot,"Reply from a replaced Link cannot update current state or dispatch a retry"):return
	apply_synthetic_profile(true,true,"")
	if not await ready(func():return not world.quest_helper_travel.loot_start_waiting_snapshot and public_start_button_disabled(false),"Fresh state permits owner-disposal case"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	var stale_eligibility_index:=0
	replacement_link.answer(stale_eligibility_index,ack(replacement_link.sequences[stale_eligibility_index],true))
	if not check(replacement_link.commands.size()==2 and replacement_link.commands[1]=={"type":"snapshot"} and world.quest_helper_travel.loot_start_waiting_snapshot and world.state.derived.quest_auto.budget.can_start==true,"Positive start ACK keeps stale eligibility closed and requests one ordinary snapshot"):return
	if not check(not world.quest_helper_travel.start_public_loot() and replacement_link.commands.size()==2,"A second explicit start is blocked while ACK identities await authoritative projection"):return
	var late_start_snapshot:Dictionary=synthetic_snapshot(false,"")
	var late_start_reply:Dictionary={"type":"ack","seq":replacement_link.sequences[1],"ok":true,"snapshot":late_start_snapshot}
	apply_synthetic_profile(true,true,"unrelated newer profile")
	var newer_profile_revision:int=world.state.rev
	var newer_profile_budget:Dictionary=world.state.derived.quest_auto.budget.duplicate(true)
	if not check(world.quest_helper_travel.loot_start_waiting_snapshot and not world.quest_helper_travel.loot_snapshot_pending,"A later nonmatching profile retires the pending snapshot but preserves the start hold"):return
	replacement_link.answer(1,late_start_reply)
	if not check(world.state.rev==newer_profile_revision and world.state.derived.quest_auto.budget==newer_profile_budget and world.quest_helper_travel.loot_start_waiting_snapshot,"Late snapshot callback exits without overwriting a newer profile or releasing the hold"):return
	world.state.apply(synthetic_started_snapshot(2,3))
	if not check(world.quest_helper_travel.loot_start_waiting_snapshot,"Older revisions of the acknowledged run and budget cannot resolve the start hold"):return
	world.state.apply(synthetic_started_snapshot(5,6))
	if not await ready(func():return not world.quest_helper_travel.loot_start_waiting_snapshot and not world.quest_helper_travel.loot_snapshot_pending and public_start_button_disabled(true),"Same run/budget with monotonic successor revisions confirms the running start"):return
	if not check(replacement_link.commands.size()==2 and not world.quest_helper_travel.start_public_loot(),"Matching authoritative state cannot trigger another start while eligibility is false"):return
	# A terminal successor may enable a later user action. It still resolves the
	# old ACK because both authoritative identities match and both revisions
	# moved forward; the current server eligibility controls the button.
	apply_synthetic_profile(true,true,"",false)
	if not await ready(func():return public_start_button_disabled(false),"A stopped run's current server eligibility can permit a new explicit start"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	replacement_link.answer(2,ack(replacement_link.sequences[2],true,true,"fedcba9876543210fedcba9876543210","1234567890abcdef1234567890abcdef",2))
	if not check(world.quest_helper_travel.loot_snapshot_pending and world.quest_helper_travel.loot_start_waiting_snapshot,"A new start whose run identity is not yet projected waits for one ordinary snapshot"):return
	world.state.apply(synthetic_started_snapshot(7,8,false,true,false,"deadbeef76543210fedcba9876543210","1234567890abcdef1234567890abcdef",2))
	if not check(world.quest_helper_travel.loot_start_waiting_snapshot,"A different run cannot satisfy the previous start ACK"):return
	world.state.apply(synthetic_started_snapshot(7,8,false,true,false,"fedcba9876543210fedcba9876543210","abcdef0123456789abcdef0123456789",2))
	if not check(world.quest_helper_travel.loot_start_waiting_snapshot,"A different budget id cannot satisfy the previous start ACK"):return
	world.state.apply(synthetic_started_snapshot(7,8,false,true,false,"fedcba9876543210fedcba9876543210","1234567890abcdef1234567890abcdef",3))
	if not check(world.quest_helper_travel.loot_start_waiting_snapshot,"A different budget generation cannot satisfy the previous start ACK"):return
	world.state.apply(synthetic_started_snapshot(7,8,false,true,false,"fedcba9876543210fedcba9876543210","1234567890abcdef1234567890abcdef",2))
	if not await ready(func():return not world.quest_helper_travel.loot_start_waiting_snapshot and not world.quest_helper_travel.loot_snapshot_pending and public_start_button_disabled(false),"Same run/budget terminal successor releases the hold and follows current can_start=true"):return
	var terminal_revision:int=world.state.rev
	replacement_link.answer(3,{"type":"ack","seq":replacement_link.sequences[3],"ok":true,"snapshot":synthetic_snapshot(false,"stale late snapshot")})
	if not check(world.state.rev==terminal_revision and not world.quest_helper_travel.loot_start_waiting_snapshot,"Snapshot reply arriving after a terminal successor is ignored"):return
	# A stopped recovery-locked successor also resolves only for the same
	# run and budget generation. The server reason remains visible and disables
	# the button; no local restart or recovery action is introduced.
	apply_synthetic_profile(true,true,"",false)
	if not await ready(func():return public_start_button_disabled(false),"Current server eligibility permits the recovery-lock race setup"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	replacement_link.answer(4,ack(replacement_link.sequences[4],true,true,"00112233445566778899aabbccddeeff","ffeeddccbbaa99887766554433221100",3))
	if not check(world.quest_helper_travel.loot_snapshot_pending,"Recovery-lock successor is resolved from a fresh ordinary snapshot"):return
	world.state.apply(synthetic_started_snapshot(9,10,false,false,true,"00112233445566778899aabbccddeeff","ffeeddccbbaa99887766554433221100",3,false))
	if not check(world.quest_helper_travel.loot_start_waiting_snapshot,"Root recovery lock keeps the start wait while no budget entry can correlate the ACK"):return
	var root_lock_button_ready:bool=await Wait.until(self,func():
		var current_button=menu.find_child("QuestLootStart",true,false)
		return current_button is Button and current_button.disabled)
	if not root_lock_button_ready:
		var root_lock_button=menu.find_child("QuestLootStart",true,false)
		var root_lock_auto=world.state.derived.get("quest_auto",{})
		var root_lock_budget=root_lock_auto.get("budget",{}) if root_lock_auto is Dictionary else {}
		var root_lock_can_start=root_lock_budget.get("can_start",null) if root_lock_budget is Dictionary else null
		var root_lock_reason=root_lock_budget.get("reason",null) if root_lock_budget is Dictionary else null
		print("PUBLIC UI ROOT LOCK WAIT: waiting=%s snapshot_pending=%s can_start=%s reason=%s button_exists=%s button_disabled=%s" % [world.quest_helper_travel.loot_start_waiting_snapshot,world.quest_helper_travel.loot_snapshot_pending,root_lock_can_start,root_lock_reason,root_lock_button is Button,root_lock_button.disabled if root_lock_button is Button else null])
	if not check(root_lock_button_ready,"Root recovery lock button reaches its current disabled state after the existing menu refresh"):return
	if not check(world.quest_helper_travel.loot_start_waiting_snapshot and public_start_button_disabled(true),"Root recovery lock without a budget entry cannot be correlated to the acknowledged budget"):return
	var locked_successor:=synthetic_started_snapshot(11,12,false,false,true,"00112233445566778899aabbccddeeff","ffeeddccbbaa99887766554433221100",3)
	world.state.apply(locked_successor)
	var recovery_reason_ready:bool=await Wait.until(self,func():
		if world.quest_helper_travel.loot_start_waiting_snapshot or world.quest_helper_travel.loot_snapshot_pending:return false
		return public_start_button_disabled(true) and public_start_reason_matches("预算恢复锁定，请人工处理。"))
	if not recovery_reason_ready:
		var recovery_button=menu.find_child("QuestLootStart",true,false)
		var recovery_reason=menu.find_child("QuestLootStartReason",true,false)
		var recovery_auto=world.state.derived.get("quest_auto",{})
		var recovery_budget=recovery_auto.get("budget",{}) if recovery_auto is Dictionary else {}
		var recovery_can_start=recovery_budget.get("can_start",null) if recovery_budget is Dictionary else null
		var recovery_server_reason=recovery_budget.get("reason",null) if recovery_budget is Dictionary else null
		print("PUBLIC UI RECOVERY REASON WAIT: waiting=%s snapshot_pending=%s can_start=%s server_reason=%s button_exists=%s button_type=%s button_disabled=%s reason_exists=%s reason_type=%s reason_text=%s state_rev=%s frame=%s" % [world.quest_helper_travel.loot_start_waiting_snapshot,world.quest_helper_travel.loot_snapshot_pending,recovery_can_start,recovery_server_reason,recovery_button!=null,type_string(typeof(recovery_button)),recovery_button.disabled if recovery_button is Button else null,recovery_reason!=null,type_string(typeof(recovery_reason)),recovery_reason.text if recovery_reason is Label else null,world.state.rev,Engine.get_process_frames()])
	if not check(recovery_reason_ready,"Same identity recovery-locked successor releases stale ACK wait and preserves server reason"):return
	if not check(not world.quest_helper_travel.start_public_loot() and replacement_link.commands.size()==6,"Recovery lock does not dispatch a start or any recovery command"):return
	# Applying a snapshot emits ClientState.changed synchronously. Replace the
	# active link from that callback and ensure the returning consumer does not
	# overwrite the new operation's UI state after apply() returns.
	apply_synthetic_profile(true,true,"",false)
	if not await ready(func():return public_start_button_disabled(false),"Fresh eligibility sets up the synchronous state callback case"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	replacement_link.answer(6,ack(replacement_link.sequences[6],true,true,"11223344556677889900aabbccddeeff","0011aabb2233ccdd4455eeff66778899",4))
	if not check(world.quest_helper_travel.loot_snapshot_pending and replacement_link.commands.size()==8,"Third accepted start awaits one authoritative snapshot without replay"):return
	var reentrant_link:=DeferredLink.new()
	var reentrant_feedback:="State callback replaced the active link"
	var replace_link_during_apply:=func(kind:String):
		if kind=="snapshot":
			world.link=reentrant_link
			world.quest_helper_travel.loot_start_feedback=reentrant_feedback
	world.state.changed.connect(replace_link_during_apply)
	replacement_link.answer(7,{"type":"ack","seq":replacement_link.sequences[7],"ok":true,"snapshot":synthetic_started_snapshot(11,12,false,true,false,"11223344556677889900aabbccddeeff","0011aabb2233ccdd4455eeff66778899",4)})
	world.state.changed.disconnect(replace_link_during_apply)
	if not check(world.link==reentrant_link and world.quest_helper_travel.loot_start_feedback==reentrant_feedback and world.quest_helper_travel.loot_start_waiting_snapshot and not world.quest_helper_travel.loot_snapshot_pending,"Post-apply revalidation preserves the replacement callback and keeps the old ACK hold unresolved"):return
	world.link=replacement_link
	world.state.apply(synthetic_started_snapshot(15,16,false,true,false,"11223344556677889900aabbccddeeff","0011aabb2233ccdd4455eeff66778899",4))
	if not await ready(func():return public_start_button_disabled(false),"A later distinct synthetic projection enables the disposal case"):return
	if not await click(menu.find_child("QuestLootStart",true,false)):return
	var owner_reply_index:=replacement_link.callbacks.size()-1
	var weak_world:WeakRef=weakref(world)
	world.link=real_link
	world.music.stop();world.effect.stop();real_link.close();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Public UI owner is fully disposed while a reply is retained by the link double"):return
	replacement_link.answer(owner_reply_index,ack(replacement_link.sequences[owner_reply_index],true))
	if not check(weak_world.get_ref()==null,"Late callback retains neither the old scene nor its travel node"):return
	server_node.stop();server_node.queue_free();backend_node.queue_free()
	print("QUEST AUTO LOOT PUBLIC UI CONSUMER: PASS (real remote closed gate; synthetic event/reply cases)")
	quit(0)

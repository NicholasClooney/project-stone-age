extends "res://tests/original_quest_auto_test.gd"
## Static-only candidate: real transport peer binding, public UI start and the
## original E1 writer/ACK on two backend-null clients. Never account auth.
## Encounter suppression is test-only and narrows this to an idle UI/E1-close
## fixture; this is not a natural encounter, battle or drop test.
const ProductionLootBackend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const GameScene = preload("res://scripts/game.gd")
const MapFile = preload("res://scripts/map_file.gd")
const LootState = preload("res://server/quest_auto_loot_state.gd")
const Sources = preload("res://server/quest_auto_loot_sources.gd")
const JewelPlan = preload("res://server/quest_auto_jewel_loot_plan.gd")
const Settings = preload("res://scripts/automation_settings.gd")
const ProfileCompare = preload("res://tests/support/quest_auto_loot_profile_compare.gd")
const STEP = "jewels:hunt:2760"
const SAVE_PATH = "user://quest-loot-public-remote.json"
const AUDIT_PATH = "user://quest-loot-public-remote-audit.json"

class IdleEncounterCatalog:
	extends "res://server/encounter_catalog.gd"
	var suppressed_step_calls := 0
	func step(_map_id: int, _cell: Vector2i, _rng: RandomNumberGenerator, _is_portal := false) -> bool:
		suppressed_step_calls += 1
		return false # Explicit test-only idle fixture; real encounter rolls are out of scope.

class PublicBackend:
	extends "res://server/backend.gd"
	const KEY = "jewels:hunt:2760"
	var observe := false
	var observation_error := ""
	var start_records: Array = []
	var start_event_count := 0
	var writer_records: Array = []
	var writer_event_count := 0
	var writer_event_ring: Array = []
	var profile_event_count := 0
	var profile_event_ring: Array = []
	const EVENT_RING_LIMIT := 16
	const START_RECORD_LIMIT := 4
	var reply_server_ref: WeakRef
	var expected_binding_refs: Dictionary = {} # WeakRefs only; never prolong a binding lifetime.

	func expect_binding(connection: int, reference: WeakRef) -> void:
		expected_binding_refs[connection]=reference

	func _expected_binding_ref(connection: int) -> WeakRef:
		var reference=expected_binding_refs.get(connection,null)
		return reference if reference is WeakRef else null

	func _binding_matches(connection: int, reference: WeakRef) -> bool:
		if reference==null or not is_instance_valid(reference):return false
		var expected=reference.get_ref()
		if not expected is RefCounted or not is_instance_valid(expected):return false
		var current=_fee_bindings.get(connection,null)
		return current is RefCounted and is_instance_valid(current) and is_same(current,expected)

	func _binding_evidence(connection: int, reference: WeakRef) -> Dictionary:
		var expected=reference.get_ref() if reference!=null and is_instance_valid(reference) else null
		var current=_fee_bindings.get(connection,null)
		var expected_valid=expected is RefCounted and is_instance_valid(expected)
		var current_valid=current is RefCounted and is_instance_valid(current)
		return {"connection_key":connection,"expected_type":type_string(typeof(expected)),"expected_valid":expected_valid,"expected_id":expected.get_instance_id() if expected_valid else null,"current_type":type_string(typeof(current)),"current_valid":current_valid,"current_id":current.get_instance_id() if current_valid else null,"same_object":expected_valid and current_valid and is_same(current,expected)}


	func _disk_file(path: String) -> Dictionary:
		if not FileAccess.file_exists(path):
			return {"exists":false,"path":path}
		var file := FileAccess.open(path,FileAccess.READ)
		var open_error := FileAccess.get_open_error()
		if file == null:
			return {"exists":true,"ok":false,"path":path,"open_error":open_error}
		var declared := file.get_length()
		file.seek(0)
		var bytes: PackedByteArray = file.get_buffer(declared)
		var read_error := file.get_error()
		file.close()
		var hash_error := OK
		var digest := ""
		var hash := HashingContext.new()
		hash_error = hash.start(HashingContext.HASH_SHA256)
		if hash_error == OK and not bytes.is_empty():
			hash_error = hash.update(bytes)
		if hash_error == OK:
			digest = hash.finish().hex_encode()
		return {"exists":true,"ok":open_error==OK and read_error==OK and hash_error==OK and declared==bytes.size(),"path":path,"declared":declared,"actual":bytes.size(),"open_error":open_error,"read_error":read_error,"hash_error":hash_error,"sha256":digest,"bytes":bytes}

	func _disk_set(path: String) -> Dictionary:
		return {"primary":_disk_file(path),"backup":_disk_file(path+".bak"),"tmp":_disk_file(path+".tmp")}

	func _native(owner) -> Dictionary:
		if not is_instance_valid(owner) or not owner.get("_profile") is Dictionary:
			observation_error = "writer owner/profile is unavailable"
			return {}
		return owner._profile.duplicate(true)

	func _timer_evidence() -> Dictionary:
		var sample:Dictionary=quest_loot.cached_sample.duplicate(true)
		var sample_lifetime=sample.get("lifetime",null)
		var live_lifetime=quest_loot.lifetime
		return {"anchor_ms":quest_loot.anchor_ms,"base_used_ms":quest_loot.base_used_ms,"frozen":quest_loot.frozen,"frozen_ms":quest_loot.frozen_ms,"storage_paused":quest_loot.storage_paused,"sample_used_ms":sample.get("used_ms",null),"sample_span":sample.get("span",{}).duplicate(true) if sample.get("span",{}) is Dictionary else {},"sample_lifetime_is_current":sample_lifetime is RefCounted and is_instance_valid(sample_lifetime) and live_lifetime is RefCounted and is_instance_valid(live_lifetime) and is_same(sample_lifetime,live_lifetime),"sample_lifetime_id":sample_lifetime.get_instance_id() if sample_lifetime is RefCounted and is_instance_valid(sample_lifetime) else null,"live_lifetime_id":live_lifetime.get_instance_id() if live_lifetime is RefCounted and is_instance_valid(live_lifetime) else null}

	func _capture_start_boundary(command: Dictionary, result: Dictionary, before: Dictionary) -> void:
		if not observe:
			return
		var connection = command.get("_quest_connection",null)
		var expected_binding_ref := _expected_binding_ref(int(connection)) if connection is int else null
		var after_profile = session._profile.duplicate(true)
		var record := {"frame":Engine.get_process_frames(),"backend_revision":rev,"profile_event_count":profile_event_count,"seq":command.get("seq",null),"type":command.get("type",null),"keys":command.keys(),"server_peer_id":connection,"binding_current":_binding_matches(int(connection),expected_binding_ref) if connection is int else false,"binding_evidence":_binding_evidence(int(connection),expected_binding_ref) if connection is int else {},"before":before,"after_profile":after_profile,"after_cache":last_saved_payload,"after_serial":quest_save_serial,"after_disk":_disk_set(save_path),"handler_result":result.duplicate(true),"run_identity":quest_auto.identity.checkpoint().duplicate(true),"runner_running":quest_auto.running,"runner_phase":quest_auto.phase,"entry":session._profile.quest_loot.entries.get(KEY,{}).duplicate(true)}
		start_event_count += 1
		if start_records.size()<START_RECORD_LIMIT:
			start_records.append(record)
		else:
			observation_error="start command evidence reached its fixed record bound"
		if result.get("ok",false) and result.get("persisted",null) is bool and result.persisted and result.get("type",null)=="ack" and result.get("seq",null) is int and int(result.seq)>0:
			var server = reply_server_ref.get_ref() if reply_server_ref!=null else null
			if not is_instance_valid(server):
				observation_error = "held-reply server expired before the real ACK send boundary"
			elif not server.arm_actual_ack(int(connection),int(record.seq)):
				observation_error = "real reply hold could not be armed for the observed transport/sequence"

	func _cmd_quest_loot_start(command: Dictionary) -> Dictionary:
		var connection=command.get("_quest_connection",null)
		var expected_binding_ref=_expected_binding_ref(int(connection)) if connection is int else null
		var before := {"profile":session._profile.duplicate(true),"cache":last_saved_payload,"serial":quest_save_serial,"disk":_disk_set(save_path),"binding_current":_binding_matches(int(connection),expected_binding_ref) if connection is int else false,"binding_evidence":_binding_evidence(int(connection),expected_binding_ref) if connection is int else {}}
		var result: Dictionary = super._cmd_quest_loot_start(command)
		_capture_start_boundary(command,result,before)
		return result

	func _record_writer(kind: String, payload: String, owner, path: String, ok: bool, serial_before: int, revision_before: int, event_count_before: int, frame_before: int, cache_before: String, disk_before: Dictionary, timer_before: Dictionary) -> void:
		if not observe:
			return
		writer_event_count += 1
		var live_owner := is_instance_valid(owner) and is_same(owner,session)
		var disk_after:Dictionary=_disk_set(path)
		var summary:Dictionary={"kind":kind,"ok":ok,"payload_bytes":payload.to_utf8_buffer().size(),"payload_sha256":payload.sha256_text(),"owner_is_current_session":live_owner,"owner_instance_id":owner.get_instance_id() if is_instance_valid(owner) else null,"path_is_current":path==save_path,"serial_before":serial_before,"serial_after":quest_save_serial,"revision_before":revision_before,"revision_after":rev,"event_count_before":event_count_before,"event_count_after":profile_event_count,"frame_before":frame_before,"frame_after":Engine.get_process_frames(),"cache_before_sha256":cache_before.sha256_text(),"cache_after_sha256":last_saved_payload.sha256_text(),"disk_before":_disk_summary(disk_before),"disk_after":_disk_summary(disk_after),"normal_generation":_normal_process_generation}
		if kind=="loot_settlement_written" and writer_records.size()<3:
			var owner_profile := _native(owner) if live_owner else {}
			var record:Dictionary=summary.duplicate(true)
			record.merge({"payload":payload,"cache_before":cache_before,"cache_after":last_saved_payload,"native_profile_after":owner_profile,"disk_before_full":disk_before,"disk_after_full":disk_after,"timer_before":timer_before},true)
			writer_records.append(record)
		if writer_event_ring.size()>=EVENT_RING_LIMIT:writer_event_ring.remove_at(0)
		writer_event_ring.append(summary)

	func _disk_summary(value:Dictionary)->Dictionary:
		var result:Dictionary={}
		for slot in ["primary","backup","tmp"]:
			var item=value.get(slot,{})
			if item is Dictionary:
				result[slot]={"exists":item.get("exists",false),"ok":item.get("ok",false),"declared":item.get("declared",null),"actual":item.get("actual",null),"sha256":item.get("sha256","")}
			else:
				result[slot]={"invalid_record":true}
		return result

	func _loot_settlement_written(payload: String, owner, path: String) -> void:
		var serial_before := quest_save_serial
		var revision_before := rev
		var event_count_before := profile_event_count
		var frame_before := Engine.get_process_frames()
		var cache_before := last_saved_payload
		var disk_before := _disk_set(path) if observe else {}
		var timer_before := _timer_evidence() if observe else {}
		super._loot_settlement_written(payload,owner,path)
		_record_writer("loot_settlement_written",payload,owner,path,true,serial_before,revision_before,event_count_before,frame_before,cache_before,disk_before,timer_before)

	func _save_profile_boundary(checkpoint: Dictionary = {}) -> bool:
		var serial_before := quest_save_serial
		var revision_before := rev
		var event_count_before := profile_event_count
		var frame_before := Engine.get_process_frames()
		var cache_before := last_saved_payload
		var disk_before := _disk_set(save_path) if observe else {}
		var timer_before := _timer_evidence() if observe else {}
		var result: bool = super._save_profile_boundary(checkpoint)
		_record_writer("save_profile_boundary",last_saved_payload,session,save_path,result,serial_before,revision_before,event_count_before,frame_before,cache_before,disk_before,timer_before)
		return result

	func observe_event(message: Dictionary) -> void:
		if not observe or message.get("type","")!="profile":
			return
		var event_profile = message.get("profile",null)
		if not event_profile is Dictionary:
			observation_error = "profile event omitted its complete profile dictionary"
			return
		var derived = message.get("derived",{})
		var auto = derived.get("quest_auto",{}) if derived is Dictionary else {}
		var budget = auto.get("budget",{}) if auto is Dictionary else {}
		var entry = budget.get("entry",null) if budget is Dictionary else null
		if not entry is Dictionary:
			return
		profile_event_count += 1
		var compact_run:Dictionary={"run_id":auto.get("run_id",null),"step_id":auto.get("step_id",null),"revision":auto.get("revision",null)}
		var compact_entry:Dictionary={}
		for key in ["step_id","budget_id","generation","revision","target_item_id","target_count","limit_ms","saved_used_ms","used_ms","existing_items","new_items","saved_battles"]:
			if entry.has(key):compact_entry[key]=entry[key]
		var compact_ledger:Dictionary={"present":event_profile.has("quest_loot"),"type":type_string(typeof(event_profile.get("quest_loot",null)))}
		if profile_event_ring.size()>=EVENT_RING_LIMIT:profile_event_ring.remove_at(0)
		profile_event_ring.append({"frame":Engine.get_process_frames(),"event_rev":message.get("rev",null),"event_profile_type":type_string(typeof(event_profile)),"event_profile_ledger":compact_ledger,"run_identity":compact_run,"running":auto.get("running",null),"budget_entry":compact_entry,"native_serial":quest_save_serial,"backend_revision":rev,"process_generation":_normal_process_generation,"battle_open":battle_open,"pending_battle_id":str(session._pending.get("battle_id",""))})

class HeldReplyServer:
	extends "res://server/ws_server.gd"
	var target_peer_id: int = 0
	var target_peer_armed := false
	var target_seq := -1
	var held_reply: Dictionary = {}
	var held_peer_id: int = 0
	var held_peer_id_valid := false
	var release_count := 0
	var hold_error := ""

	func arm_actual_ack(peer_id: int, sequence: int) -> bool:
		if sequence <= 0 or target_peer_armed or held_peer_id_valid or not held_reply.is_empty():
			hold_error = "invalid or duplicate hold request"
			return false
		target_peer_id = peer_id
		target_peer_armed = true
		target_seq = sequence
		return true

	func _send(peer: WebSocketPeer, message: Dictionary) -> void:
		if target_peer_armed and peer.get_instance_id()==target_peer_id and message.get("reply",false) is bool and message.get("reply",false) and message.get("seq",null) is int and int(message.seq)==target_seq:
			if not held_reply.is_empty():
				hold_error = "more than one reply matched the one-shot hold"
				return
			held_reply = message.duplicate(true) # The actual Backend reply; never synthesized.
			held_peer_id = peer.get_instance_id()
			held_peer_id_valid = true
			target_peer_armed = false
			target_seq = -1
			return
		super._send(peer,message)

	func release_actual_reply() -> bool:
		if held_reply.is_empty() or not held_peer_id_valid:
			return false
		for peer in clients():
			if peer.get_instance_id()!=held_peer_id or peer.get_ready_state()!=WebSocketPeer.STATE_OPEN:
				continue
			var actual := held_reply.duplicate(true)
			held_reply.clear()
			held_peer_id_valid = false
			release_count += 1
			super._send(peer,actual)
			return true
		return false

var host: PublicBackend
var server: HeldReplyServer
var pump: LinkPump
var world_a
var world_b
var link_a
var link_b
var client_peer_a_id: int = 0
var client_peer_a_id_found := false
var client_peer_b_id: int = 0
var client_peer_b_id_found := false
var server_peer_a_id: int = 0
var server_peer_a_id_found := false
var server_peer_b_id: int = 0
var server_peer_b_id_found := false
var server_peer_a_ref: WeakRef
var server_peer_b_ref: WeakRef
var server_peer_a_ref_captured := false
var reconnected_client_peer_a_id: int = 0
var reconnected_client_peer_a_id_found := false
var reconnected_server_peer_a_id: int = 0
var reconnected_server_peer_a_id_found := false
var reconnected_server_peer_a_ref: WeakRef
var binding_server_peer_a_ref: WeakRef
var binding_server_peer_b_ref: WeakRef
var binding_reconnected_server_peer_a_ref: WeakRef
var peer_mapping_trace: Array = []
var source_cell := Vector2i(-1,-1)
var frozen_before: Dictionary = {}
var pre_game_profile: Dictionary = {}
var startup_trace: Array = []
var projection_used_watermarks: Dictionary = {}
var failure_label := ""
var source_step: Dictionary = {}
var observed_ack: Dictionary = {}
var observed_ack_server_peer_id: int = 0
var observed_ack_server_peer_id_found := false
var late_ack_evidence: Dictionary = {}
var teardown_capture: Dictionary = {}

func check(value: bool, message: String) -> bool:
	if not value and failures == 0:
		failures = 1
		failure_label = message
		push_error(message)
	return value

func ready(condition: Callable, _message: String) -> bool:
	# Keep Wait.until's existing condition/deadline behavior, but let each caller
	# archive its first failure and run teardown before the SceneTree exits.
	return await Wait.until(self,condition)

func fresh(path: String) -> bool:
	var suffixes: Array[String] = ["",".tmp",".bak",".resume.json",".release-log.jsonl",".capture-log.jsonl",".stop-log.jsonl"]
	for suffix in suffixes:
		var candidate: String = path+suffix
		if FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(candidate)):
			return false
	return true

func safe_source_cell(b: PublicBackend) -> Vector2i:
	var map: Dictionary = MapFile.load_map(b.quest_helper.places.file(100))
	if map.is_empty() or not b.quest_loot.admission_terrain_valid(map):return Vector2i(-1,-1)
	var links: Dictionary = b.quest_helper.places.links(100)
	var occupied: Dictionary = {}
	for npc in b.quest_catalog.active_npcs():
		if int(npc.get("map_id",-1))==100:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
	for npc in b.quest_helper.places.residents:
		if int(npc.get("map_id",-1))==100:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
	for y in range(341,413):
		for x in range(621,646):
			var cell := Vector2i(x,y)
			if int(b.encounter_catalog.area_at(100,cell).get("id",-1))!=56:continue
			if b.quest_helper.safe(map,cell,occupied,links):return cell
	return Vector2i(-1,-1)

func prepare_backend() -> bool:
	if not fresh(SAVE_PATH) or not fresh(AUDIT_PATH) or not fresh("user://quest-loot-public-a-viewer.cfg") or not fresh("user://quest-loot-public-b-viewer.cfg"):
		return check(false,"All authoritative save, audit and per-client viewer paths are fresh before setup")
	host = PublicBackend.new()
	host.save_path = SAVE_PATH
	var source_catalog = host.encounter_catalog
	var idle_catalog = IdleEncounterCatalog.new(source_catalog.data)
	idle_catalog.pressure = source_catalog.pressure
	host.encounter_catalog = idle_catalog
	source_cell = safe_source_cell(host)
	if not check(idle_catalog.data==source_catalog.data,"Test-only idle catalog retains the complete real loaded encounter source data"):return false
	if not check(source_cell.x>=0,"Resolve an original map-100 area-56 safe-cell fixture using loaded source/map rules"):return false
	if not check(host.session.set_location(100,source_cell.x,source_cell.y),"Set only the isolated test profile's original server-side fixture location"):return false
	host.automation.position_changed(100,source_cell,true,"project")
	# Eligibility is a direct fixture convenience, not natural travel or a drop.
	host.session.OriginalEquipment.add(host.session._profile,2764)
	if not check(host.session._profile.get("no_random_encounters",null) is bool and not host.session._profile.no_random_encounters,"Public-start eligibility retains the original random-encounter-enabled profile"):return false
	if not check(host.save(),"Persist the isolated eligibility fixture with the original profile writer"):return false
	if not check(host.last_saved_payload==FileAccess.get_file_as_string(SAVE_PATH),"Fixture cache and primary bytes agree before GameScene startup"):return false
	return true

func create_remote_scene(tag: String):
	var server_profile_before:Dictionary=host.session._profile.duplicate(true)
	var cache_before:String=host.last_saved_payload
	var serial_before:int=host.quest_save_serial
	GameScene.server_url_override="ws://127.0.0.1:%d"%server.port
	var scene = load("res://scenes/main.tscn").instantiate()
	GameScene.server_url_override=""
	scene.profile_persistence=false
	scene.viewer_prefs_path="user://quest-loot-public-%s-viewer.cfg"%tag
	root.add_child(scene)
	# Retain/poll the real link before waiting for hello; otherwise this helper
	# would await a response before LinkPump had been given the link.
	if tag=="a":link_a=scene.link;pump.links=[link_a]
	else:link_b=scene.link;pump.links=[link_a,link_b]
	if not await ready(func():return scene.link.online and not scene.data.is_empty(),"Actual backend-null GameScene %s reaches its loaded map and WebSocket hello snapshot"%tag):return null
	if not check(scene.backend==null and not scene.link.is_local(),"Remote GameScene %s has no Backend and uses the real WsLink"%tag):return null
	if not check(await Wait.settle(self,scene),"Actual %s WsLink round trip settles startup commands"%tag):return null
	var peer: WebSocketPeer = scene.link._peer
	if not check(is_instance_valid(peer) and peer.get_ready_state()==WebSocketPeer.STATE_OPEN,"Actual %s socket remains open after startup"%tag):return null
	var client_profile: Dictionary = scene.state.profile.duplicate(true)
	startup_trace.append({"tag":tag,"client_peer_id":peer.get_instance_id(),"world_map":int(scene.data.get("map_id",-1)),"world_cell":[scene.cell.x,scene.cell.y],"profile_location":client_profile.get("location",{}).duplicate(true) if client_profile.get("location",{}) is Dictionary else {},"profile_pets_count":client_profile.get("pets",[]).size() if client_profile.get("pets",[]) is Array else -1,"default_companions_claimed":client_profile.get("default_companions_claimed",null),"authority_position":scene.state.automation.get("position",{}).duplicate(true),"server_profile_before":server_profile_before,"server_profile_after":host.session._profile.duplicate(true),"server_cache_before_sha256":cache_before.sha256_text(),"server_cache_after_sha256":host.last_saved_payload.sha256_text(),"serial_before":serial_before,"serial_after":host.quest_save_serial,"server_pets_count":host.session._profile.get("pets",[]).size(),"server_default_companions_claimed":host.session._profile.get("default_companions_claimed",null)})
	return scene

func capture_binding_ref(connection: int) -> WeakRef:
	var binding=host._fee_bindings.get(connection,null)
	var reference:WeakRef=weakref(binding) if binding is RefCounted and is_instance_valid(binding) else null
	if reference!=null:host.expect_binding(connection,reference)
	return reference

func binding_matches(connection: int, expected_ref: WeakRef) -> bool:
	if expected_ref==null or not is_instance_valid(expected_ref):return false
	var expected=expected_ref.get_ref()
	if not expected is RefCounted or not is_instance_valid(expected):return false
	var current=host._fee_bindings.get(connection,null)
	return current is RefCounted and is_instance_valid(current) and is_same(current,expected)

func binding_evidence(connection: int, expected_ref: WeakRef) -> Dictionary:
	var expected=expected_ref.get_ref() if expected_ref!=null and is_instance_valid(expected_ref) else null
	var current=host._fee_bindings.get(connection,null)
	var expected_valid=expected is RefCounted and is_instance_valid(expected)
	var current_valid=current is RefCounted and is_instance_valid(current)
	return {"connection_key":connection,"expected_type":type_string(typeof(expected)),"expected_valid":expected_valid,"expected_id":expected.get_instance_id() if expected_valid else null,"current_type":type_string(typeof(current)),"current_valid":current_valid,"current_id":current.get_instance_id() if current_valid else null,"same_object":expected_valid and current_valid and is_same(current,expected)}

func captured_binding_id(expected_ref: WeakRef) -> Variant:
	var expected=expected_ref.get_ref() if expected_ref!=null and is_instance_valid(expected_ref) else null
	return expected.get_instance_id() if expected is RefCounted and is_instance_valid(expected) else null

func weak_object_alive(reference: WeakRef) -> bool:
	return reference!=null and is_instance_valid(reference) and is_instance_valid(reference.get_ref())

func weak_objects_distinct(reference_a: WeakRef, reference_b: WeakRef, require_refcounted: bool = false) -> bool:
	if not weak_object_alive(reference_a) or not weak_object_alive(reference_b):return false
	var object_a=reference_a.get_ref()
	var object_b=reference_b.get_ref()
	var correct_types=not require_refcounted or (object_a is RefCounted and object_b is RefCounted)
	var result=correct_types and not is_same(object_a,object_b)
	object_a=null
	object_b=null
	return result

func peer_ref_is_current(reference: WeakRef, peer: WebSocketPeer) -> bool:
	if reference==null or not is_instance_valid(reference) or not is_instance_valid(peer):return false
	var expected=reference.get_ref()
	return is_instance_valid(expected) and is_same(expected,peer)

func weak_object_identity_evidence(reference: WeakRef) -> Dictionary:
	var object_value=reference.get_ref() if reference!=null and is_instance_valid(reference) else null
	var result=object_identity_evidence(object_value)
	object_value=null
	return result

func retired_peer_identity_evidence(old_ref: WeakRef, new_ref: WeakRef, old_capture_valid: bool, old_id: int, new_id: int) -> Dictionary:
	var old_ref_valid=old_capture_valid and old_ref!=null and is_instance_valid(old_ref)
	var new_ref_valid=new_ref!=null and is_instance_valid(new_ref)
	var old_peer=old_ref.get_ref() if old_ref_valid else null
	var new_peer=new_ref.get_ref() if new_ref_valid else null
	var old_alive=old_peer is WebSocketPeer and is_instance_valid(old_peer)
	var old_expired=old_ref_valid and old_peer==null
	var new_alive=new_peer is WebSocketPeer and is_instance_valid(new_peer)
	var same_check=old_alive and new_alive and not is_same(old_peer,new_peer)
	var expired_identity_check=old_expired and old_id!=new_id
	var distinct=old_ref_valid and new_alive and old_id!=new_id and ((old_alive and same_check) or expired_identity_check)
	var evidence:Dictionary={"old_weakref_captured":old_ref_valid,"old_peer_alive":old_alive,"old_peer_expired":old_expired,"old_peer_id":old_id if old_ref_valid else null,"new_peer_alive":new_alive,"new_peer_id":new_id if new_ref_valid else null,"old_and_new_ids_differ":old_id!=new_id,"old_and_new_objects_differ_if_old_alive":same_check,"new_peer_distinct_after_old_expiry":expired_identity_check,"new_peer_is_distinct":distinct}
	old_peer=null
	new_peer=null
	return evidence

func object_identity_evidence(value: Variant) -> Dictionary:
	var object_value=value is Object
	var valid=object_value and is_instance_valid(value)
	return {"type":type_string(typeof(value)),"valid":valid,"instance_id":value.get_instance_id() if valid else null}

func entry_on(world) -> Dictionary:
	var auto = world.state.derived.get("quest_auto",{})
	var budget = auto.get("budget",{}) if auto is Dictionary else {}
	var entry = budget.get("entry",null) if budget is Dictionary else null
	return entry if entry is Dictionary else {}

func public_entry_dto_from_expected(internal_entry:Dictionary)->Dictionary:
	# Independently map the State candidate plus the frozen selected source step
	# into the public projection contract. Never seed this oracle from a snapshot.
	var source_target:Variant=source_step.get("target",null)
	if source_step.get("id",null)!=STEP or not source_target is Dictionary:return {}
	var item_id:Variant=source_target.get("item_id",null)
	var item_count:Variant=source_target.get("count",null)
	if not item_id is int or item_id!=2760 or not item_count is int or item_count!=1:return {}
	for key in ["budget_id","generation","revision","limit_ms","used_ms","existing_items","new_items","saved_battles"]:
		if not internal_entry.has(key):return {}
	if not internal_entry.budget_id is String:return {}
	for key in ["generation","revision","limit_ms","used_ms","existing_items","new_items","saved_battles"]:
		if not internal_entry[key] is int:return {}
	return {"step_id":STEP,"budget_id":internal_entry.budget_id,"generation":internal_entry.generation,"revision":internal_entry.revision,"target_item_id":item_id,"target_count":item_count,"limit_ms":internal_entry.limit_ms,"saved_used_ms":internal_entry.used_ms,"existing_items":internal_entry.existing_items,"new_items":internal_entry.new_items,"saved_battles":internal_entry.saved_battles}

func real_open_projection(world,client_key:String,run_id:String,run_revision:int,budget_id:String,generation:int,expected_entry:Dictionary)->bool:
	if not is_instance_valid(world) or world.backend!=null or not world.state.quest_loot_enabled():return false
	if expected_entry.get("budget_id",null)!=budget_id or expected_entry.get("generation",null)!=generation:return false
	var auto = world.state.derived.get("quest_auto",{})
	if not auto is Dictionary or not auto.get("running",null) is bool or auto.get("running",false)!=true:return false
	var budget=auto.get("budget",null)
	if not budget is Dictionary or not budget.get("enabled",null) is bool or not budget.enabled or not budget.get("recovery_blocked",null) is bool or budget.recovery_blocked or not budget.get("can_start",null) is bool or budget.can_start:return false
	var entry := entry_on(world)
	if entry.is_empty():return false
	if auto.get("run_id",null)!=run_id or auto.get("step_id",null)!=STEP or not auto.get("revision",null) is int or int(auto.revision)<run_revision:return false
	if entry.get("budget_id",null)!=budget_id or not entry.get("generation",null) is int or entry.generation!=generation or not entry.get("revision",null) is int or int(entry.revision)<int(expected_entry.revision):return false
	for key in ["step_id","target_item_id","target_count","limit_ms","saved_used_ms","existing_items","new_items","saved_battles"]:
		if entry.get(key,null)!=expected_entry.get(key,null):return false
	var used=entry.get("used_ms",null)
	if not used is int or used<int(expected_entry.saved_used_ms) or used>int(expected_entry.limit_ms):return false
	if entry.get("limit_reached",null) is not bool or entry.limit_reached!=(used>=int(expected_entry.limit_ms)):return false
	var previous_used:Variant=projection_used_watermarks.get(client_key,expected_entry.saved_used_ms)
	if not previous_used is int or used<previous_used:return false
	projection_used_watermarks[client_key]=used
	return true

func real_closed_projection(world,client_key:String,run_id:String,run_revision:int,budget_id:String,generation:int,expected_entry:Dictionary)->bool:
	if not is_instance_valid(world) or world.backend!=null:return false
	if not world.state.quest_loot_enabled():return false
	if expected_entry.get("budget_id",null)!=budget_id or expected_entry.get("generation",null)!=generation:return false
	var auto=world.state.derived.get("quest_auto",{})
	if not auto is Dictionary or not auto.get("running",null) is bool or auto.running:return false
	if auto.get("run_id",null)!=run_id or auto.get("step_id",null)!=STEP or not auto.get("revision",null) is int or int(auto.revision)<run_revision:return false
	var budget=auto.get("budget",null)
	if not budget is Dictionary or not budget.get("enabled",null) is bool or not budget.enabled or not budget.get("recovery_blocked",null) is bool or budget.recovery_blocked or not budget.get("can_start",null) is bool or not budget.can_start or not budget.get("entry",null) is Dictionary:return false
	var entry:Dictionary=budget.entry
	if entry.get("budget_id",null)!=budget_id or not entry.get("budget_id",null) is String:return false
	if not entry.get("generation",null) is int or entry.generation!=generation or not entry.get("revision",null) is int or entry.revision!=expected_entry.get("revision",null):return false
	if not budget.get("activity",null) is String or budget.activity!="stopped":return false
	if not budget.get("can_start",null) is bool or not entry.get("step_id",null) is String or entry.step_id!=expected_entry.get("step_id",null):return false
	for key in ["target_item_id","target_count","limit_ms","saved_used_ms","existing_items","new_items","saved_battles"]:
		if not entry.get(key,null) is int or entry.get(key,null)!=expected_entry.get(key,null):return false
	var used:Variant=entry.get("used_ms",null)
	if not used is int or used<int(expected_entry.saved_used_ms) or used>int(entry.limit_ms):return false
	if entry.get("limit_reached",null) is not bool or entry.limit_reached!=(used>=int(entry.limit_ms)):return false
	var previous_used:Variant=projection_used_watermarks.get(client_key,expected_entry.saved_used_ms)
	if not previous_used is int or used<previous_used:return false
	projection_used_watermarks[client_key]=used
	return true

func independently_closed_candidate(open_profile:Dictionary,close_record:Dictionary)->Dictionary:
	if close_record.get("kind",null)!="loot_settlement_written" or not close_record.get("timer_before",null) is Dictionary:return {}
	var sample:Variant=close_record.timer_before.get("sample_used_ms",null)
	var open_ledger:Variant=open_profile.get("quest_loot",null)
	if not sample is int or not open_ledger is Dictionary or not open_ledger.get("entries",null) is Dictionary or not open_ledger.entries.get(STEP,null) is Dictionary:return {}
	var open_entry:Dictionary=open_ledger.entries[STEP]
	var transition:Dictionary=LootState.progress(open_ledger,STEP,LootState.identity(open_entry),sample,true)
	if not transition.get("ok",false):return {}
	var candidate:Dictionary=frozen_before.duplicate(true)
	candidate.quest_loot=transition.ledger
	var expected_internal:Dictionary=candidate.quest_loot.entries[STEP]
	var expected_dto:Dictionary=public_entry_dto_from_expected(expected_internal)
	if expected_dto.is_empty():return {}
	return {"profile":candidate,"entry":expected_dto,"sample_used_ms":sample}

func valid_identity(value: Variant, run: bool) -> bool:
	if not value is Dictionary:return false
	var expected := ["run_id","step_id","revision"] if run else ["budget_id","generation","revision"]
	if value.size()!=expected.size():return false
	for key in expected:
		if not value.has(key):return false
	var opaque: Variant = value.get("run_id" if run else "budget_id",null)
	if not opaque is String or opaque.length()!=32 or not opaque.is_valid_hex_number():return false
	if run and value.get("step_id",null)!=STEP:return false
	if not value.get("revision",null) is int or int(value.revision)<0:return false
	if not run and (not value.get("generation",null) is int or int(value.generation)<0):return false
	return true

func expected_e1_profiles(reply: Dictionary)->Array:
	if not check(reply.get("run_identity",null) is Dictionary and valid_identity(reply.run_identity,true),"Actual successful reply has exact typed run identity"):return []
	if not check(reply.get("budget_identity",null) is Dictionary and valid_identity(reply.budget_identity,false),"Actual successful reply has exact typed budget identity"):return []
	var run: Dictionary = reply.run_identity
	var budget: Dictionary = reply.budget_identity
	if not check(budget.generation==0 and budget.revision==1,"Fresh acquire/open contract advances the new entry to generation 0, revision 1"):return []
	var settings_override:Variant=frozen_before.get("automation_settings",{})
	var effective_settings:Dictionary={}
	if settings_override is Dictionary:effective_settings=Settings.effective(settings_override)
	var quest_settings:Variant=effective_settings.get("quest",null)
	var minutes_value:Variant=quest_settings.get("loot_minutes",null) if quest_settings is Dictionary else null
	var minutes_is_int:bool=minutes_value is int
	var minutes_valid:bool=settings_override is Dictionary and quest_settings is Dictionary and minutes_is_int and minutes_value>=1 and minutes_value<=180
	var has_quest_minutes:bool=quest_settings.has("loot_minutes") if quest_settings is Dictionary else false
	var ledger_value:Variant=frozen_before.get("quest_loot",null)
	var ledger_valid:bool=ledger_value is Dictionary and LootState.valid(ledger_value)
	var acquired:Dictionary={}
	var acquire_called:bool=false
	var acquire_reason:String="not called: frozen quest.loot_minutes must be a strict int in [1,180] and quest_loot must be valid"
	if minutes_valid and ledger_valid:
		acquired=LootState.acquire(ledger_value,STEP,budget.budget_id,run.run_id,minutes_value,0)
		acquire_called=true
		var raw_reason:Variant=acquired.get("reason","")
		acquire_reason=raw_reason.substr(0,96) if raw_reason is String else "non-string result reason"
	var logged_minutes:Variant=null
	if minutes_value is int or minutes_value is float:logged_minutes=minutes_value
	print("PUBLIC_LOOT_E1_ORACLE_DIAGNOSTIC "+JSON.stringify({"settings_override_type":type_string(typeof(settings_override)),"effective_has_quest":quest_settings is Dictionary,"has_quest_minutes":has_quest_minutes,"quest_minutes_type":type_string(typeof(minutes_value)),"quest_minutes":logged_minutes,"minutes_valid":minutes_valid,"quest_loot_valid":ledger_valid,"run_identity":run,"budget_identity":budget,"acquire_called":acquire_called,"acquire_ok":acquired.get("ok",false),"acquire_reason":acquire_reason}))
	if not check(ledger_valid,"Frozen pre-click quest_loot is a valid dictionary for independent E1 candidate construction"):return []
	if not check(minutes_valid,"Frozen pre-click effective quest.loot_minutes is a strict int in [1,180]"):return []
	var minutes:int=minutes_value
	if not check(acquire_called and acquired.get("ok",false),"Independent State.acquire derives the first candidate from the frozen pre-click ledger/settings and actual server-created IDs"):return []
	var acquired_entry: Dictionary = acquired.ledger.entries[STEP]
	if not check(acquired_entry.origin_run_id==run.run_id and acquired_entry.limit_ms==minutes*60000 and acquired_entry.existing_items==0,"Acquire values match only the original server contract and frozen settings"):return []
	var opened: Dictionary = LootState.open(acquired.ledger,STEP,LootState.identity(acquired_entry))
	if not check(opened.get("ok",false),"Independent State.open derives the second E1 candidate"):return []
	var first_profile: Dictionary = frozen_before.duplicate(true)
	first_profile.quest_loot = acquired.ledger
	var second_profile: Dictionary = frozen_before.duplicate(true)
	second_profile.quest_loot = opened.ledger
	return [first_profile,second_profile]

func validated_payload(payload: String, expected: Dictionary, label: String) -> bool:
	var parsed = JSON.parse_string(payload)
	if not check(parsed is Dictionary,"Persisted full-profile JSON parses at %s"%label):return false
	var validated: Dictionary = ProfileCompare.validated_copy(host.session,payload)
	if not check(validated.get("ok",false),"Complete saved profile passes the existing validator at %s"%label):return false
	# The existing ProfileCompare contract validates the complete raw profile,
	# then applies only GameSession's established JSON integer normalization.
	var normalized_expected:Dictionary=host.session._normalize_numbers(expected.duplicate(true))
	return check(validated.get("profile",{})==normalized_expected,"Every normalized JSON profile field matches the independently derived complete candidate at %s"%label)

func check_e1_writer_chain(expected: Array)->bool:
	if not check(host.writer_event_count==2 and host.writer_records.size()==2,"This explicitly encounter-suppressed idle fixture has exactly the original acquire/open E1 writer callbacks before stop; any extra writer is an idle-fixture boundary failure, not a general server-correctness verdict"):return false
	var first: Dictionary = host.writer_records[0]
	var second: Dictionary = host.writer_records[1]
	if not check(first.kind=="loot_settlement_written" and second.kind=="loot_settlement_written","Fresh E1 consists of the original acquire then open commit callbacks"):return false
	for index in range(2):
		var record: Dictionary = host.writer_records[index]
		if not check(record.ok and record.owner_is_current_session and record.path_is_current and record.serial_after==record.serial_before+1,"E1 writer callback %d is a successful same-owner/path single serial transition"%index):return false
		if not check(record.native_profile_after==expected[index],"E1 writer callback %d installed the exact independent native full-profile candidate"%index):return false
		if not check(record.cache_after==record.payload,"E1 writer callback %d installs its exact payload as the current serialized cache"%index):return false
		if not validated_payload(record.payload,expected[index],"E1 callback %d"%index):return false
		var disk: Dictionary = record.disk_after_full
		var primary: Dictionary = disk.primary
		if not check(primary.get("ok",false) and primary.bytes.get_string_from_utf8()==record.payload,"Actual primary matches callback payload at E1 callback %d"%index):return false
		if not check(not disk.tmp.get("exists",true),"No temporary residue after E1 callback %d"%index):return false
	var start_before:Dictionary=host.start_records[0].before
	if not check(first.disk_after_full.backup.get("ok",false) and first.disk_after_full.backup.bytes==start_before.disk.primary.bytes,"First writer preserves the actual pre-E1 primary captured at the Backend start boundary"):return false
	if not check(second.disk_after_full.backup.get("ok",false) and second.disk_after_full.backup.bytes==first.disk_after_full.primary.bytes,"Second writer backup is the actual immediately preceding acquire profile"):return false
	return check(second.disk_after_full.primary.bytes==second.payload.to_utf8_buffer(),"Final primary bytes are the exact opened E1 payload")

func check_stop_close_writer(expected_open_profile:Dictionary,expected_closed_profile:Dictionary)->bool:
	if not check(host.writer_event_count==3 and host.writer_records.size()==3,"In the explicit idle fixture, generic Stop adds exactly one durable close callback after E1; natural battle settlement is outside this oracle"):return false
	var record:Dictionary=host.writer_records[2]
	if not check(record.kind=="loot_settlement_written" and record.ok and record.owner_is_current_session and record.path_is_current and record.serial_after==record.serial_before+1,"Stop close is one successful original same-owner/path writer boundary"):return false
	var timer:Dictionary=record.timer_before
	var open_entry:Dictionary=expected_open_profile.quest_loot.entries[STEP]
	var sample_span:Dictionary=timer.get("sample_span",{})
	if not check(timer.get("frozen",false)==true and timer.get("storage_paused",false)==true and timer.get("sample_lifetime_is_current",false)==true and timer.get("sample_used_ms",null) is int,"Stop uses the real frozen current-lifetime sample captured before the writer"):return false
	if not check(sample_span=={"budget_id":open_entry.budget_id,"generation":open_entry.generation,"issued_seq":open_entry.issued_seq},"Stop sample remains bound to the opened E1 span"):return false
	var used_ms:int=timer.sample_used_ms
	if not check(used_ms>=open_entry.used_ms and used_ms<=open_entry.limit_ms,"Stop's real sample is monotonic and within the frozen full-profile budget"):return false
	var transition:Dictionary=LootState.progress(expected_open_profile.quest_loot,STEP,LootState.identity(open_entry),used_ms,true)
	if not check(transition.get("ok",false),"Pure State.progress independently derives the close from the E1 candidate and actual captured sample"):return false
	var expected:Dictionary=expected_open_profile.duplicate(true)
	expected.quest_loot=transition.ledger
	if not check(expected_closed_profile==expected,"Independently prepared closed full-profile candidate matches the original State.progress derivation"):return false
	if not check(record.native_profile_after==expected and record.cache_after==record.payload,"The complete native profile/cache after close equals the independent E1→close candidate"):return false
	if not validated_payload(record.payload,expected,"generic Stop close"):return false
	var disk:Dictionary=record.disk_after_full
	if not check(disk.primary.get("ok",false) and disk.primary.bytes.get_string_from_utf8()==record.payload,"Closed candidate is the exact actual primary payload"):return false
	var preceding_e1_primary:PackedByteArray=host.writer_records[1].disk_after_full.primary.bytes
	if not check(disk.backup.get("ok",false) and disk.backup.bytes==preceding_e1_primary,"Close preserves the immediately preceding E1-open primary as backup"):return false
	if not check(not disk.tmp.get("exists",true),"Close leaves no temporary writer file"):return false
	return true

func snapshot_record(world)->Dictionary:
	var auto=world.state.derived.get("quest_auto",{})
	if not auto is Dictionary:auto={}
	var budget=auto.get("budget",{})
	if not budget is Dictionary:budget={}
	return {"frame":Engine.get_process_frames(),"scene_id":world.get_instance_id(),"state_rev":world.state.rev,"capability":world.state.capabilities.get("quest_loot_enabled",null),"auto":auto.duplicate(true),"budget":budget.duplicate(true),"profile":world.state.profile.duplicate(true)}

func changed_keys(before:Dictionary,after:Dictionary)->Array:
	var keys:Dictionary={}
	for key in before:keys[key]=true
	for key in after:keys[key]=true
	var changed:Array=[]
	for key in keys:
		if not before.has(key) or not after.has(key) or before[key]!=after[key]:changed.append(str(key))
	changed.sort()
	return changed

func snapshot_identity(snapshot:Dictionary)->Dictionary:
	var auto_value:Variant=snapshot.get("auto",{})
	var auto:Dictionary=auto_value if auto_value is Dictionary else {}
	var budget_value:Variant=auto.get("budget",{})
	var budget:Dictionary=budget_value if budget_value is Dictionary else {}
	var entry_value:Variant=budget.get("entry",null)
	var entry:Dictionary=entry_value if entry_value is Dictionary else {}
	return {"run_id":auto.get("run_id",null),"step_id":auto.get("step_id",null),"run_revision":auto.get("revision",null),"budget_id":entry.get("budget_id",null),"generation":entry.get("generation",null),"budget_revision":entry.get("revision",null)}

func primary_bytes(disk:Dictionary)->Variant:
	var primary:Variant=disk.get("primary",null)
	if not primary is Dictionary or primary.get("ok",null) is not bool or not primary.ok:return null
	var bytes:Variant=primary.get("bytes",null)
	return bytes if bytes is PackedByteArray else null

func json_safe(value:Variant)->Variant:
	if value is PackedByteArray:return {"encoding":"base64","data":Marshalls.raw_to_base64(value)}
	if value is Array:
		var items:Array=[]
		for item in value:items.append(json_safe(item))
		return items
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[str(key)]=json_safe(value[key])
		return result
	if value is Object:
		return {"object_type":type_string(typeof(value)),"instance_id":value.get_instance_id() if is_instance_valid(value) else null}
	return value

func audit_snapshot(outcome: String) -> Dictionary:
	var final_a:Dictionary=snapshot_record(world_a) if is_instance_valid(world_a) else {}
	var final_b:Dictionary=snapshot_record(world_b) if is_instance_valid(world_b) else {}
	var failure_boundary:Dictionary={}
	if is_instance_valid(host):
		failure_boundary={"native_profile":host.session._profile.duplicate(true),"cache":host.last_saved_payload,"serial":host.quest_save_serial,"backend_revision":host.rev,"disk":host._disk_set(SAVE_PATH),"runner_identity":host.quest_auto.identity.checkpoint().duplicate(true),"runner_running":host.quest_auto.running,"runner_phase":host.quest_auto.phase,"runner_connection":host.quest_auto.connection,"runner_client":host.quest_auto.client,"timer":host._timer_evidence(),"server_peer_a_binding":binding_evidence(server_peer_a_id,binding_server_peer_a_ref) if server_peer_a_id_found else {},"server_peer_b_binding":binding_evidence(server_peer_b_id,binding_server_peer_b_ref) if server_peer_b_id_found else {},"reconnected_server_peer_a_binding":binding_evidence(reconnected_server_peer_a_id,binding_reconnected_server_peer_a_ref) if reconnected_server_peer_a_id_found else {}}
	return {"suite":"quest_auto_loot_public_remote_ui_test","outcome":outcome,"first_failure":failure_label,"union_head":"1743372391d70406639b819856915afc6ddacd04","core_original":"dbc14b0cfc15f433735a28745439de225a1bed6b","production_capability_constant":ProductionLootBackend.QUEST_LOOT_PUBLIC_ENABLED,"claim":"real WsServer transport peer binding, not account authentication; direct original-item eligibility fixture and test-only encounter-suppressed idle boundary prove no natural route/drop/battle","startup_before_first_scene":pre_game_profile.duplicate(true),"startup":startup_trace.duplicate(true),"prestart_profile":frozen_before.duplicate(true),"start_event_count":host.start_event_count if is_instance_valid(host) else 0,"starts":host.start_records.duplicate(true) if is_instance_valid(host) else [],"writers":host.writer_records.duplicate(true) if is_instance_valid(host) else [],"writer_event_count":host.writer_event_count if is_instance_valid(host) else 0,"writer_event_ring":host.writer_event_ring.duplicate(true) if is_instance_valid(host) else [],"profile_event_count":host.profile_event_count if is_instance_valid(host) else 0,"profile_event_ring":host.profile_event_ring.duplicate(true) if is_instance_valid(host) else [],"projection_used_watermarks":projection_used_watermarks.duplicate(true),"held_wire_envelope":observed_ack.duplicate(true),"held_server_peer_id_found":observed_ack_server_peer_id_found,"held_server_peer_id":observed_ack_server_peer_id if observed_ack_server_peer_id_found else null,"late_ack":late_ack_evidence.duplicate(true),"client_peer_a_id_found":client_peer_a_id_found,"client_peer_a_id":client_peer_a_id if client_peer_a_id_found else null,"client_peer_b_id_found":client_peer_b_id_found,"client_peer_b_id":client_peer_b_id if client_peer_b_id_found else null,"server_peer_a_id_found":server_peer_a_id_found,"server_peer_a_id":server_peer_a_id if server_peer_a_id_found else null,"server_peer_b_id_found":server_peer_b_id_found,"server_peer_b_id":server_peer_b_id if server_peer_b_id_found else null,"reconnected_client_peer_a_id_found":reconnected_client_peer_a_id_found,"reconnected_client_peer_a_id":reconnected_client_peer_a_id if reconnected_client_peer_a_id_found else null,"reconnected_server_peer_a_id_found":reconnected_server_peer_a_id_found,"reconnected_server_peer_a_id":reconnected_server_peer_a_id if reconnected_server_peer_a_id_found else null,"peer_mapping_trace":peer_mapping_trace.duplicate(true),"encounter_fixture":"test-only IdleEncounterCatalog.step always returns false; real Backend _process remains enabled; natural encounters/battles are outside scope","idle_encounter_step_calls":host.encounter_catalog.suppressed_step_calls if is_instance_valid(host) and host.encounter_catalog is IdleEncounterCatalog else -1,"final_a":final_a,"final_b":final_b,"failure_boundary":failure_boundary,"teardown_capture":teardown_capture.duplicate(true),"observation_error":host.observation_error if is_instance_valid(host) else "","server_hold_error":server.hold_error if is_instance_valid(server) else ""}

func write_audit(body: Dictionary) -> bool:
	if FileAccess.file_exists(AUDIT_PATH):
		return check(false,"Reserved audit sidecar remains unique")
	# Full copies are retained only for the fixed start/settlement boundaries;
	# event streams use a count plus bounded rings. This sidecar writes no save.
	var file := FileAccess.open(AUDIT_PATH,FileAccess.WRITE)
	if not check(file!=null,"Independent evidence sidecar opens without touching the save path"):return false
	var serialized:String=JSON.stringify(json_safe(body))
	file.store_string(serialized)
	var error := file.get_error()
	file.close()
	if not check(error==OK,"Independent evidence sidecar closes cleanly"):return false
	var readback:=FileAccess.open(AUDIT_PATH,FileAccess.READ)
	if not check(readback!=null,"Independent evidence sidecar can be reopened for byte verification"):return false
	var declared:=readback.get_length()
	readback.seek(0)
	var bytes:PackedByteArray=readback.get_buffer(declared)
	var read_error:=readback.get_error()
	readback.close()
	return check(read_error==OK and declared==bytes.size() and bytes==serialized.to_utf8_buffer(),"Sidecar readback exactly matches its archived UTF-8 evidence bytes")

func teardown() -> bool:
	if is_instance_valid(link_a):link_a.close()
	if is_instance_valid(link_b):link_b.close()
	if is_instance_valid(world_a):world_a.queue_free()
	if is_instance_valid(world_b):world_b.queue_free()
	var writer_start:=host.writer_records.size() if is_instance_valid(host) else 0
	var writer_event_start:=host.writer_event_count if is_instance_valid(host) else 0
	var event_start:=host.profile_event_count if is_instance_valid(host) else 0
	if is_instance_valid(server):server.stop()
	if is_instance_valid(host):
		teardown_capture={"native_profile":host.session._profile.duplicate(true),"cache":host.last_saved_payload,"serial":host.quest_save_serial,"backend_revision":host.rev,"disk":host._disk_set(SAVE_PATH),"runner_identity":host.quest_auto.identity.checkpoint().duplicate(true),"runner_running":host.quest_auto.running,"runner_phase":host.quest_auto.phase,"additional_critical_writers":host.writer_records.slice(writer_start),"additional_writer_event_count":host.writer_event_count-writer_event_start,"writer_event_ring":host.writer_event_ring.duplicate(true),"additional_profile_event_count":host.profile_event_count-event_start,"profile_event_ring":host.profile_event_ring.duplicate(true)}
	if is_instance_valid(server):server.queue_free()
	if is_instance_valid(host):host.queue_free()
	if is_instance_valid(pump):pump.queue_free()
	return await Wait.until(self,func():return (not is_instance_valid(world_a)) and (not is_instance_valid(world_b)) and (not is_instance_valid(server)) and (not is_instance_valid(host)) and (not is_instance_valid(pump)),60.0)

func abort(stage: String) -> void:
	if failure_label.is_empty():failure_label=stage
	var evidence:=audit_snapshot("FAIL")
	var teardown_ok:bool=await teardown()
	evidence.teardown_ok=teardown_ok
	evidence.teardown_capture=teardown_capture.duplicate(true)
	if not teardown_ok:push_error("Teardown did not release every owned test node")
	write_audit(evidence)
	print("QUEST AUTO LOOT PUBLIC REMOTE UI: 1 failure at %s; source-route proof=false; account-auth proof=false"%failure_label)
	quit(1)

func run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i.ZERO
	if not await prepare_backend():await abort("isolated backend/fixture preparation");return
	root.add_child(host)
	server=HeldReplyServer.new(host,0,"127.0.0.1")
	root.add_child(server)
	# Attach after the production WsServer handler so its fan-out keeps priority.
	# The observer neither alters, flushes nor publishes an event.
	host.event.connect(host.observe_event)
	if not check(server.start()==OK,"Real single-Backend WsServer listens on an ephemeral loopback port"):await abort("server start");return
	if not check(server.backend==host and server.hub==null,"Use actual single-profile Backend transport mode, not ProfileHub/login mode"):await abort("server mode");return
	host.reply_server_ref=weakref(server)
	pump=LinkPump.new();root.add_child(pump)
	if not check(host.is_processing(),"Direct Backend retains its normal production _process scheduler"):await abort("backend process disabled");return
	pre_game_profile=host.session._profile.duplicate(true)
	world_a=await create_remote_scene("a")
	if not is_instance_valid(world_a):await abort("client A startup");return
	client_peer_a_id=link_a._peer.get_instance_id()
	client_peer_a_id_found=true
	if not await ready(func():return server.clients().size()==1 and server.clients()[0].get_ready_state()==WebSocketPeer.STATE_OPEN,"A is the only promoted server transport peer before B connects"):await abort("server peer A promotion");return
	server_peer_a_id=server.clients()[0].get_instance_id()
	server_peer_a_id_found=true
	server_peer_a_ref=weakref(server.clients()[0])
	server_peer_a_ref_captured=server_peer_a_ref!=null and is_instance_valid(server_peer_a_ref) and server_peer_a_ref.get_ref() is WebSocketPeer and is_instance_valid(server_peer_a_ref.get_ref())
	binding_server_peer_a_ref=capture_binding_ref(server_peer_a_id)
	peer_mapping_trace.append({"tag":"a","client_peer_id":client_peer_a_id,"server_peer_id":server_peer_a_id,"server_clients_count":server.clients().size(),"binding_id":captured_binding_id(binding_server_peer_a_ref),"binding_evidence":binding_evidence(server_peer_a_id,binding_server_peer_a_ref),"mapping_basis":"A-only server.clients() after real A startup settle"})
	world_b=await create_remote_scene("b")
	if not is_instance_valid(world_b):await abort("client B startup");return
	client_peer_b_id=link_b._peer.get_instance_id()
	client_peer_b_id_found=true
	if not await ready(func():return server.clients().size()==2 and link_a.online and link_b.online,"Both real transport peers are promoted and online"):await abort("peer promotion");return
	var server_a_retained_first:=peer_ref_is_current(server_peer_a_ref,server.clients()[0])
	server_peer_b_id=server.clients()[1].get_instance_id()
	server_peer_b_id_found=true
	server_peer_b_ref=weakref(server.clients()[1])
	binding_server_peer_b_ref=capture_binding_ref(server_peer_b_id)
	var binding_a_evidence:=binding_evidence(server_peer_a_id,binding_server_peer_a_ref)
	var binding_b_evidence:=binding_evidence(server_peer_b_id,binding_server_peer_b_ref)
	var client_ids_distinct:=client_peer_a_id!=client_peer_b_id
	var client_peer_objects_valid:=link_a._peer is WebSocketPeer and is_instance_valid(link_a._peer) and link_b._peer is WebSocketPeer and is_instance_valid(link_b._peer)
	var server_ids_distinct:=server_peer_a_id!=server_peer_b_id
	var server_objects_distinct:=weak_objects_distinct(server_peer_a_ref,server_peer_b_ref)
	var binding_objects_distinct:=weak_objects_distinct(binding_server_peer_a_ref,binding_server_peer_b_ref,true)
	var binding_a_matches:=binding_matches(server_peer_a_id,binding_server_peer_a_ref)
	var binding_b_matches:=binding_matches(server_peer_b_id,binding_server_peer_b_ref)
	var peer_binding_parts:Dictionary={"client_a":object_identity_evidence(link_a._peer),"client_b":object_identity_evidence(link_b._peer),"server_a":weak_object_identity_evidence(server_peer_a_ref),"server_b":weak_object_identity_evidence(server_peer_b_ref),"binding_a":binding_a_evidence,"binding_b":binding_b_evidence,"checks":{"client_ids_distinct":client_ids_distinct,"client_peer_objects_valid":client_peer_objects_valid,"server_ids_distinct":server_ids_distinct,"server_peer_objects_distinct":server_objects_distinct,"server_a_retained_first":server_a_retained_first,"binding_objects_distinct":binding_objects_distinct,"binding_a_matches_current_map":binding_a_matches,"binding_b_matches_current_map":binding_b_matches}}
	print("PUBLIC_LOOT_PEER_BINDING_DIAGNOSTIC "+JSON.stringify(peer_binding_parts))
	peer_mapping_trace.append({"tag":"b","client_peer_id":client_peer_b_id,"server_peer_id":server_peer_b_id,"server_clients_count":server.clients().size(),"binding_id":captured_binding_id(binding_server_peer_b_ref),"binding_evidence":binding_b_evidence,"mapping_basis":"A retained in server.clients()[0], B newly appended at [1] after real promotion"})
	if not check(client_ids_distinct and client_peer_objects_valid and server_ids_distinct and server_objects_distinct and server_a_retained_first and binding_objects_distinct and binding_a_matches and binding_b_matches,"Distinct real client/server peer identities retain distinct RefCounted fee bindings in their own current server connection mappings"):await abort("transport peer binding");return
	if not check(world_a.backend==null and world_b.backend==null and server.backend==host and server.hub==null,"Both actual client scenes remain backend-null against one direct Backend server"):await abort("remote mode");return
	# Record actual GameScene initialization rather than assuming an empty/fresh
	# profile: startup may restore profile location and claim default companions.
	if not check(host.session._profile.get("location",{})=={"map_id":100,"x":source_cell.x,"y":source_cell.y},"Both scenes restored the fixture's persisted server location"):await abort("location restoration");return
	if not check(world_a.data.get("map_id",-1)==100 and world_a.cell==source_cell and world_b.data.get("map_id",-1)==100 and world_b.cell==source_cell,"Both real GameScenes finish startup at the authority's actual persisted cell"):await abort("scene restore");return
	if not check(host.session._profile.get("no_random_encounters",null) is bool and not host.session._profile.no_random_encounters and host.encounter_catalog is IdleEncounterCatalog,"Start admission sees the original encounter-enabled profile; only the isolated test catalog suppresses random step outcomes"):await abort("idle fixture boundary");return
	if not check(not host.quest_auto.running and host.session._pending.is_empty() and not host.battle_open,"No pre-existing run or battle is hidden by the fixture"):await abort("initial state");return
	frozen_before=host.session._profile.duplicate(true)
	if not check(host.session._valid_profile(frozen_before) and frozen_before.location=={"map_id":100,"x":source_cell.x,"y":source_cell.y},"Freeze the actual native, fully initialized profile without snapshot normalization"):await abort("frozen profile");return
	if not check(LootState.valid(frozen_before.get("quest_loot",null)) and frozen_before.quest_loot==LootState.empty(),"Public E1 begins from an actual empty, unlocked ledger rather than assuming a generic fresh profile"):await abort("empty ledger baseline");return
	if not check(host.session._valid_profile(frozen_before) and frozen_before.original_items.has(2764) and not frozen_before.original_items.has(2760),"Actual initialized profile is valid, contains only the eligibility source item, and has no target drop"):await abort("eligibility baseline");return
	var plan: Dictionary=JewelPlan.select(host,Sources.matches_backend)
	if not check(plan.get("status","")=="step" and Sources.same(plan.get("step",{}),Sources.step()),"Original source plan accepts the server-side setup fixture"):await abort("source plan");return
	source_step=plan.step.duplicate(true)
	if not check(host.automation.position_map==100 and host.automation.position_cell==source_cell and host.encounter_catalog.area_at(100,source_cell).get("id")==56,"Source area and server authority cell are the same original area-56 fixture"):await abort("source cell");return
	if not check(host.last_saved_payload==FileAccess.get_file_as_string(SAVE_PATH),"Post-GameScene startup full profile is durably saved before public input"):await abort("save baseline");return
	var initial_disk=host._disk_set(SAVE_PATH)
	if not check(initial_disk.primary.get("ok",false) and initial_disk.primary.bytes.get_string_from_utf8()==host.last_saved_payload and initial_disk.backup.get("exists",false) and initial_disk.backup.get("ok",false),"Freeze actual pre-click primary/backup/cache bytes after default-pet/location initialization"):await abort("disk baseline");return
	host.observe=true
	if not check(host.writer_event_count==0 and host.writer_records.is_empty() and host.start_event_count==0 and host.start_records.is_empty(),"No observed writer or public start precedes the real UI click"):await abort("pre-click observer baseline");return
	world_a.quest_helper_menu.open_menu()
	if not await ready(func():return world_a.quest_helper_menu.find_child("QuestLootStart",true,false) is Button and not world_a.quest_helper_menu.find_child("QuestLootStart",true,false).disabled,"Real enabled QuestLootStart button appears under the inherited production getter"):await abort("start button");return
	if not await click(world_a.quest_helper_menu.find_child("QuestLootStart",true,false)):await abort("real start click");return
	if not await ready(func():return not server.held_reply.is_empty(),"Capture only the actual persisted Backend ACK at the WsServer send boundary"):await abort("actual ACK hold");return
	if not check(server.held_reply.get("reply",null) is bool and server.held_reply.reply and server.held_reply.get("type",null)=="ack" and server.held_reply.get("ok",null) is bool and server.held_reply.ok and server.held_reply.get("persisted",null) is bool and server.held_reply.persisted and server.held_reply.get("seq",null) is int,"Actual WsServer wire envelope has reply=true and the original typed durable ACK fields"):await abort("held ACK shape");return
	if not check(host.observation_error.is_empty() and server.hold_error.is_empty(),"Writer/event/reply observers have no passive capture errors"):await abort("observer latch");return
	var held_ack: Dictionary=server.held_reply.duplicate(true)
	if not check(host.start_event_count==1 and host.start_records.size()==1 and host.start_records[0].type=="quest_loot_start","A's actual button caused exactly one observed public-start handler call"):await abort("single start call");return
	var start_record: Dictionary=host.start_records[0]
	if not check(start_record.before.profile==frozen_before and start_record.before.disk.primary.bytes==initial_disk.primary.bytes and start_record.before.disk.backup.bytes==initial_disk.backup.bytes,"The synchronous public-start boundary begins at the separately frozen fully initialized native profile and exact disk bytes"):await abort("click baseline identity");return
	if not check(start_record.seq is int and start_record.seq==held_ack.seq and start_record.server_peer_id==server_peer_a_id and start_record.binding_current and start_record.binding_evidence.same_object,"Backend received A's actual transport-generated sequence and the exact current binding object created for A's server-promoted peer"):await abort("start peer attribution");return
	if not check(start_record.keys.size()==3 and start_record.keys.has("type") and start_record.keys.has("seq") and start_record.keys.has("_quest_connection"),"Public start command contains only type, transport sequence and server-injected connection"):await abort("start command shape");return
	if not check(start_record.handler_result.get("ok",null) is bool and start_record.handler_result.ok and start_record.handler_result.get("persisted",null) is bool and start_record.handler_result.persisted and start_record.handler_result.get("type",null)=="ack" and start_record.handler_result.get("seq",null) is int and start_record.handler_result.seq==start_record.seq and not start_record.handler_result.has("reply") and held_ack.get("type",null)==start_record.handler_result.type and held_ack.get("seq",null)==start_record.handler_result.seq and held_ack.get("ok",null)==start_record.handler_result.ok and held_ack.get("persisted",null)==start_record.handler_result.persisted and held_ack.get("reply",null) is bool and held_ack.reply==true,"Raw Backend result is public_start's typed ACK; final wire envelope separately adds reply=true and preserves exact seq/type/result"):await abort("start reply layers");return
	if not check(start_record.handler_result.get("run_identity",null)==held_ack.get("run_identity",null) and start_record.handler_result.get("budget_identity",null)==held_ack.get("budget_identity",null),"Transport ACK preserves the exact run/budget identities returned by the real handler"):await abort("ACK identity correspondence");return
	if not check(host.writer_records.size()>=2,"Both durable acquire/open E1 writer callbacks were observed"):await abort("E1 writer callbacks");return
	var identities: Array=expected_e1_profiles(held_ack)
	if not check(identities.size()==2,"Independent full-profile E1 oracle is available"):await abort("E1 oracle");return
	if not check_e1_writer_chain(identities):await abort("E1 writer/disk chain");return
	if not check(host._quest_loot_public_enabled() and host._capabilities().get("quest_loot_enabled",null) is bool and host._capabilities().quest_loot_enabled,"Same inherited production getter feeds projection and admission"):await abort("capability source");return
	if not check(Backend.QUEST_LOOT_PUBLIC_ENABLED==true,"The production immutable capability constant is true; the test Backend inherits its shared getter"):await abort("production capability is open");return
	var run_id: String=held_ack.run_identity.run_id
	var budget_id: String=held_ack.budget_identity.budget_id
	var generation: int=held_ack.budget_identity.generation
	var run_revision: int=held_ack.run_identity.revision
	var expected_open_internal:Dictionary=identities[1].quest_loot.entries[STEP]
	var expected_open_entry:Dictionary=public_entry_dto_from_expected(expected_open_internal)
	if not check(not expected_open_entry.is_empty(),"Independent E1 ledger candidate plus frozen source plan maps into the exact public projection DTO"):await abort("public E1 DTO oracle");return
	projection_used_watermarks={"a":expected_open_entry.saved_used_ms,"b":expected_open_entry.saved_used_ms}
	print("PUBLIC_LOOT_PROJECTION_ORACLE_DIAGNOSTIC "+JSON.stringify({"source_step":source_step,"expected_open_internal":expected_open_internal,"expected_open_public_dto":expected_open_entry,"watermarks":projection_used_watermarks.duplicate(true)}))
	if not await ready(func():return real_open_projection(world_a,"a",run_id,run_revision,budget_id,generation,expected_open_entry) and real_open_projection(world_b,"b",run_id,run_revision,budget_id,generation,expected_open_entry),"Both real ClientState consumers receive the actual opened identity and independently derived complete public projection DTO"):await abort("two-client E1 projection");return
	if not await ready(func():
		var current=world_a.quest_helper_menu.find_child("QuestLootStart",true,false)
		return current is Button and current.disabled and world_a.quest_helper_menu.last_model==world_a.quest_helper_menu.refresh_key(),
		"Menu's normal refresh observes the open span and disables its current start node"):await abort("menu refresh after E1");return
	var button_a=world_a.quest_helper_menu.find_child("QuestLootStart",true,false)
	if not check(button_a is Button and button_a.disabled,"Reacquire the current disabled start node after natural menu rebuild"):await abort("current disabled button");return
	var starts_before_second_click:=host.start_event_count
	if not await click(button_a):await abort("pending second physical click");return
	if not check(host.start_event_count==starts_before_second_click and starts_before_second_click==1,"A second physical click while E1 ACK is pending creates no new server start call"):await abort("duplicate physical click");return
	var before_duplicate_count:=host.start_event_count
	var duplicate: Dictionary=await rpc(link_b,{"type":"quest_loot_start"})
	if not check(not duplicate.get("ok",true) and duplicate.get("persisted",null) is bool and not duplicate.persisted and duplicate.get("type","")=="rejected" and duplicate.get("seq",null) is int,"B's real second type-only WS start is explicitly refused before any write"):await abort("B duplicate start");return
	if not check(host.start_event_count==before_duplicate_count+1 and host.start_records.size()==host.start_event_count,"B duplicate is one actual Backend handler call and every bounded start record is retained"):await abort("B call count");return
	var duplicate_record: Dictionary=host.start_records.back()
	if not check(duplicate_record.server_peer_id==server_peer_b_id and duplicate_record.binding_current and duplicate_record.binding_evidence.same_object and duplicate_record.handler_result.get("persisted",null) is bool and not duplicate_record.handler_result.persisted,"B duplicate uses its distinct current binding object and receives the actual persisted=false refusal"):await abort("B refusal attribution");return
	if not check(host.writer_event_count==2 and host.writer_records.size()==2 and duplicate_record.before.profile==duplicate_record.after_profile and duplicate_record.before.cache==duplicate_record.after_cache and duplicate_record.before.serial==duplicate_record.after_serial and duplicate_record.before.disk==duplicate_record.after_disk,"The duplicate handler's own synchronous interval performs no writer callback/profile/cache/serial/primary/backup/tmp write"):await abort("B no-write refusal");return
	if not check(host.encounter_catalog is IdleEncounterCatalog and not host.session._profile.no_random_encounters and host.is_processing(),"Backend retains normal processing with the isolated test-only encounter-step boundary"):await abort("idle fixture process boundary");return
	if not check(not host.battle_open and host.session._pending.is_empty(),"The explicit idle encounter fixture has no legitimate battle/receipt settlement before generic Stop"):await abort("idle fixture battle boundary");return
	var profile_events_before_stop:=host.profile_event_count
	world_b.quest_helper_menu.open_menu()
	if not await ready(func():return world_b.quest_helper_menu.find_child("QuestAutoStop",true,false) is Button and not world_b.quest_helper_menu.find_child("QuestAutoStop",true,false).disabled,"B's existing generic Stop control is built from the real running projection"):await abort("Stop control");return
	if not await click(world_b.quest_helper_menu.find_child("QuestAutoStop",true,false)):await abort("generic Stop UI click");return
	if not await ready(func():
		var entry=host.session._profile.quest_loot.entries.get(STEP,{})
		return not host.quest_auto.running and not entry.get("open_span",true) and not host.session._pending.size() and not host.battle_open,
		"The original generic Stop completes the current owned run/battle and closes E1 through its original transaction"):await abort("generic Stop settlement");return
	var opened_profile:Dictionary=identities[1]
	if not check(host.writer_event_count==3 and host.writer_records.size()==3,"No unexpected writer boundary preceded the unique original idle-close commit"):await abort("close writer count");return
	var closed_candidate:Dictionary=independently_closed_candidate(opened_profile,host.writer_records[2])
	if not check(not closed_candidate.is_empty(),"Stop projection oracle comes from the independent E1 candidate and the actual captured frozen sample"):await abort("closed DTO oracle");return
	var final_expected:Dictionary=closed_candidate.profile
	var expected_closed_entry:Dictionary=closed_candidate.entry
	print("PUBLIC_LOOT_CLOSED_PROJECTION_ORACLE_DIAGNOSTIC "+JSON.stringify({"expected_closed_public_dto":expected_closed_entry,"used_sample_ms":closed_candidate.sample_used_ms,"identity":{"run_id":run_id,"step_id":STEP,"run_revision_floor":run_revision,"budget_id":budget_id,"generation":generation}}))
	if not await ready(func():return real_closed_projection(world_a,"a",run_id,run_revision,budget_id,generation,expected_closed_entry) and real_closed_projection(world_b,"b",run_id,run_revision,budget_id,generation,expected_closed_entry),"Both clients consume the stopped projection matching the independently derived closed public DTO and original identities"):await abort("two-client closed projection");return
	if not check(await Wait.settle(self,world_b),"A real B-side ping round trip drains commands preceding the stopped-projection baseline"):await abort("post-Stop round trip");return
	if not check(host.profile_event_count>profile_events_before_stop and host.observation_error.is_empty(),"Real stop/profile event boundaries were observed with no observer error"):await abort("profile event evidence");return
	var final_entry: Dictionary=host.session._profile.quest_loot.entries[STEP].duplicate(true)
	if not check(LootState.valid_profile(host.session._profile) and not final_entry.open_span and final_entry.settled_seq==final_entry.issued_seq,"Final original ledger is valid and durably closed after generic Stop"):await abort("closed ledger");return
	if not check_stop_close_writer(opened_profile,final_expected):await abort("independent full-profile Stop close oracle");return
	var final_disk: Dictionary=host._disk_set(SAVE_PATH)
	var final_validated: Dictionary=ProfileCompare.validated_copy(host.session,host.last_saved_payload)
	if not check(host.session._profile==final_expected and final_validated.get("ok",false) and final_validated.profile==host.session._normalize_numbers(final_expected.duplicate(true)) and final_disk.primary.get("ok",false) and final_disk.primary.bytes.get_string_from_utf8()==host.last_saved_payload and not final_disk.tmp.get("exists",true),"Full final native profile, validated cache, exact primary bytes and no temporary residue equal the independently derived closed candidate"):await abort("final saved profile");return
	var old_scene_ref: WeakRef=weakref(world_a)
	var old_travel_ref: WeakRef=weakref(world_a.quest_helper_travel)
	var held_server_peer_id:=server.held_peer_id
	world_a.queue_free()
	world_a=null
	if not await ready(func():return old_scene_ref.get_ref()==null and old_travel_ref.get_ref()==null,"Disposed A scene/travel owner is actually gone before the held real ACK is released"):await abort("late owner disposal");return
	if not check(link_a.online and link_a._peer!=null and link_a._peer.get_instance_id()==client_peer_a_id and held_server_peer_id==server_peer_a_id and server.clients().any(func(peer):return peer_ref_is_current(server_peer_a_ref,peer)),"Client-side A socket identity and independently captured server-side A peer identity remain live after UI-owner disposal"):await abort("late ACK socket retained");return
	var b_before_release: Dictionary=snapshot_record(world_b)
	var profile_before_release: Dictionary=host.session._profile.duplicate(true)
	var cache_before_release: String=host.last_saved_payload
	var serial_before_release: int=host.quest_save_serial
	var disk_before_release: Dictionary=host._disk_set(SAVE_PATH)
	var server_revision_before_release:int=host.rev
	var profile_events_before_release:int=host.profile_event_count
	var writer_events_before_release:int=host.writer_event_count
	var writer_records_before_release:int=host.writer_records.size()
	var a_peer_before_release:WebSocketPeer=link_a._peer
	var a_lifecycle_before_release:int=int(link_a.get("_lifecycle"))
	var a_messages_in_before_release:int=link_a.messages_in
	late_ack_evidence={"client_peer_id":a_peer_before_release.get_instance_id(),"server_peer_id":held_server_peer_id,"lifecycle_before":a_lifecycle_before_release,"messages_in_before":a_messages_in_before_release,"callbacks_before":link_a._callbacks.size(),"server_release_count_before":server.release_count}
	observed_ack=server.held_reply.duplicate(true)
	observed_ack_server_peer_id=server.held_peer_id
	observed_ack_server_peer_id_found=server.held_peer_id_valid
	if not check(server.release_actual_reply() and server.release_count==1,"Release the exact captured Backend reply through the original still-open server peer"):await abort("late reply release");return
	if not await ready(func():return link_a._callbacks.is_empty() and link_a.messages_in>a_messages_in_before_release,"Real WsLink consumes the released reply after the former UI callback owner was freed"):await abort("late reply delivered");return
	if not check(link_a._peer==a_peer_before_release and int(link_a.get("_lifecycle"))==a_lifecycle_before_release,"Held-reply delivery used A's same live peer and link lifecycle, not a fabricated cross-epoch dispatch"):await abort("late reply same epoch");return
	late_ack_evidence.merge({"messages_in_after":link_a.messages_in,"callbacks_after":link_a._callbacks.size(),"same_peer_after":link_a._peer==a_peer_before_release,"lifecycle_after":int(link_a.get("_lifecycle")),"server_release_count_after":server.release_count},true)
	if not check(await Wait.settle(self,world_b),"A real B-side ping round trip drains any server events queued before the late-ACK comparison"):await abort("late-ACK B round trip");return
	var profile_after_release:Dictionary=host.session._profile.duplicate(true)
	var cache_after_release:String=host.last_saved_payload
	var serial_after_release:int=host.quest_save_serial
	var disk_after_release:Dictionary=host._disk_set(SAVE_PATH)
	var b_after_release:Dictionary=snapshot_record(world_b)
	var server_revision_after_release:int=host.rev
	var profile_events_after_release:int=host.profile_event_count
	var writer_events_after_release:int=host.writer_event_count
	var writer_records_after_release:int=host.writer_records.size()
	var primary_before:Variant=primary_bytes(disk_before_release)
	var primary_after:Variant=primary_bytes(disk_after_release)
	var profile_unchanged:bool=profile_after_release==profile_before_release
	var cache_unchanged:bool=cache_after_release==cache_before_release
	var serial_unchanged:bool=serial_after_release==serial_before_release
	var primary_unchanged:bool=primary_before is PackedByteArray and primary_after is PackedByteArray and primary_after==primary_before
	var b_state_revision_monotonic:bool=b_before_release.get("state_rev",null) is int and b_after_release.get("state_rev",null) is int and int(b_after_release.state_rev)>=int(b_before_release.state_rev)
	var b_frame_advanced:bool=b_before_release.get("frame",null) is int and b_after_release.get("frame",null) is int and int(b_after_release.frame)>int(b_before_release.frame)
	var b_scene_unchanged:bool=b_before_release.get("scene_id",null)==b_after_release.get("scene_id",null)
	var b_semantic_before:Dictionary=b_before_release.duplicate(true)
	var b_semantic_after:Dictionary=b_after_release.duplicate(true)
	# frame is observation metadata, and state_rev may advance on a legitimate
	# same-state profile publication; the complete consumer data remains strict.
	b_semantic_before.erase("frame");b_semantic_before.erase("state_rev")
	b_semantic_after.erase("frame");b_semantic_after.erase("state_rev")
	var b_semantics_unchanged:bool=b_semantic_after==b_semantic_before
	var b_run_identity_before:Dictionary=snapshot_identity(b_before_release)
	var b_run_identity_after:Dictionary=snapshot_identity(b_after_release)
	var b_run_identity_unchanged:bool=b_run_identity_before==b_run_identity_after
	var b_identity_still_bound:bool=b_run_identity_before.run_id==run_id and b_run_identity_before.step_id==STEP and b_run_identity_before.budget_id==budget_id and b_run_identity_before.generation==generation
	var late_ack_parts:Dictionary={"checks":{"profile_unchanged":profile_unchanged,"cache_unchanged":cache_unchanged,"serial_unchanged":serial_unchanged,"primary_bytes_unchanged":primary_unchanged,"b_scene_unchanged":b_scene_unchanged,"b_state_revision_monotonic":b_state_revision_monotonic,"b_frame_advanced_during_real_wait":b_frame_advanced,"b_semantic_snapshot_unchanged":b_semantics_unchanged,"b_run_budget_identity_unchanged":b_run_identity_unchanged,"b_remains_bound_to_original_run_budget":b_identity_still_bound},"server":{"revision_before":server_revision_before_release,"revision_after":server_revision_after_release,"profile_events_before":profile_events_before_release,"profile_events_after":profile_events_after_release,"profile_event_count_unchanged":profile_events_before_release==profile_events_after_release,"writer_events_before":writer_events_before_release,"writer_events_after":writer_events_after_release,"writer_event_count_unchanged":writer_events_before_release==writer_events_after_release,"full_writer_records_before":writer_records_before_release,"full_writer_records_after":writer_records_after_release},"b":{"frame_before":b_before_release.frame,"frame_after":b_after_release.frame,"state_rev_before":b_before_release.state_rev,"state_rev_after":b_after_release.state_rev,"run_budget_identity_before":b_run_identity_before,"run_budget_identity_after":b_run_identity_after,"profile_changed_keys":changed_keys(b_before_release.profile,b_after_release.profile),"auto_changed_keys":changed_keys(b_before_release.auto,b_after_release.auto),"budget_changed_keys":changed_keys(b_before_release.budget,b_after_release.budget),"capability_before":b_before_release.capability,"capability_after":b_after_release.capability},"host":{"primary_before_bytes":primary_before.size() if primary_before is PackedByteArray else null,"primary_after_bytes":primary_after.size() if primary_after is PackedByteArray else null}}
	# This line is synchronous and precedes any check()/push_error so the
	# first-error monitor always preserves the individual no-op results.
	print("PUBLIC_LOOT_LATE_ACK_NOOP_DIAGNOSTIC "+JSON.stringify(late_ack_parts))
	if not check(profile_unchanged and cache_unchanged and serial_unchanged and primary_unchanged and b_scene_unchanged and b_state_revision_monotonic and b_frame_advanced and b_semantics_unchanged and b_run_identity_unchanged and b_identity_still_bound,"Late actual ACK has no surviving UI owner and cannot mutate the newer client/profile/cache/disk"):await abort("late ACK no-op");return
	var old_client_peer_id:int=client_peer_a_id
	var old_server_peer_id:int=server_peer_a_id
	link_a.connect_now()
	var reconnect_condition:Callable=func():return link_a.online and link_a._peer is WebSocketPeer and is_instance_valid(link_a._peer) and link_a._peer.get_instance_id()!=old_client_peer_id and server.clients().size()==2 and peer_ref_is_current(server_peer_b_ref,server.clients()[0])
	if not await ready(reconnect_condition,"A reconnects on a new client socket while B's same retained server peer object remains first"):
		var live_server_peers:Array=[]
		for peer in server.clients():live_server_peers.append(object_identity_evidence(peer))
		print("PUBLIC_LOOT_RECONNECT_WAIT_DIAGNOSTIC "+JSON.stringify({"link_online":link_a.online,"lifecycle_before":a_lifecycle_before_release,"lifecycle_after":int(link_a.get("_lifecycle")),"client_peer":object_identity_evidence(link_a._peer),"old_client_peer_id":old_client_peer_id,"server_clients_count":server.clients().size(),"server_peers":live_server_peers,"old_server_peer":weak_object_identity_evidence(server_peer_a_ref),"old_server_peer_id":old_server_peer_id,"b_server_peer_still_current_first":server.clients().size()>0 and peer_ref_is_current(server_peer_b_ref,server.clients()[0]),"old_binding_map_present":host._fee_bindings.has(old_server_peer_id),"old_binding":binding_evidence(old_server_peer_id,binding_server_peer_a_ref)}))
		await abort("real peer reconnect")
		return
	reconnected_client_peer_a_id=link_a._peer.get_instance_id()
	reconnected_client_peer_a_id_found=true
	reconnected_server_peer_a_id=server.clients()[1].get_instance_id()
	reconnected_server_peer_a_id_found=true
	reconnected_server_peer_a_ref=weakref(server.clients()[1])
	binding_reconnected_server_peer_a_ref=capture_binding_ref(reconnected_server_peer_a_id)
	peer_mapping_trace.append({"tag":"a-reconnected","client_peer_id":reconnected_client_peer_a_id,"server_peer_id":reconnected_server_peer_a_id,"server_clients_count":server.clients().size(),"binding_id":captured_binding_id(binding_reconnected_server_peer_a_ref),"binding_evidence":binding_evidence(reconnected_server_peer_a_id,binding_reconnected_server_peer_a_ref),"mapping_basis":"B retained by object in slot [0], reconnecting A newly promoted into [1]"})
	var old_binding_retired:bool=not host._fee_bindings.has(old_server_peer_id) and not weak_object_alive(binding_server_peer_a_ref)
	var old_server_peer_identity:Dictionary=retired_peer_identity_evidence(server_peer_a_ref,reconnected_server_peer_a_ref,server_peer_a_ref_captured,old_server_peer_id,reconnected_server_peer_a_id)
	var old_server_peer_membership_absent:bool=not server.clients().any(func(peer):return peer_ref_is_current(server_peer_a_ref,peer))
	var reconnect_binding_distinct_from_b:bool=weak_objects_distinct(binding_reconnected_server_peer_a_ref,binding_server_peer_b_ref,true)
	var reconnect_binding_current:bool=binding_matches(reconnected_server_peer_a_id,binding_reconnected_server_peer_a_ref)
	var reconnected_lifecycle:int=int(link_a.get("_lifecycle"))
	var reconnect_lifecycle_advanced:bool=reconnected_lifecycle>a_lifecycle_before_release
	print("PUBLIC_LOOT_RECONNECT_BINDING_DIAGNOSTIC "+JSON.stringify({"old_a_server_peer_id":old_server_peer_id,"reconnected_a_server_peer_id":reconnected_server_peer_a_id,"b_server_peer_id":server_peer_b_id,"client_lifecycle_before":a_lifecycle_before_release,"client_lifecycle_after":reconnected_lifecycle,"old_a_peer":weak_object_identity_evidence(server_peer_a_ref),"reconnected_a_peer":weak_object_identity_evidence(reconnected_server_peer_a_ref),"old_a_binding":binding_evidence(old_server_peer_id,binding_server_peer_a_ref),"b_binding":binding_evidence(server_peer_b_id,binding_server_peer_b_ref),"reconnected_a_binding":binding_evidence(reconnected_server_peer_a_id,binding_reconnected_server_peer_a_ref),"retired_peer_identity":old_server_peer_identity,"checks":{"client_lifecycle_advanced":reconnect_lifecycle_advanced,"old_binding_retired":old_binding_retired,"old_server_peer_membership_absent":old_server_peer_membership_absent,"new_binding_differs_from_b":reconnect_binding_distinct_from_b,"new_binding_matches_current_map":reconnect_binding_current}}))
	if not check(old_server_peer_identity.new_peer_is_distinct and reconnected_server_peer_a_id!=server_peer_b_id and reconnect_binding_distinct_from_b and reconnect_binding_current and reconnect_lifecycle_advanced,"Reconnected A maps to a new client lifecycle/server peer and its exact distinct newly attached current binding"):await abort("reconnected peer binding");return
	if not check(old_binding_retired and old_server_peer_membership_absent,"Old server-side peer object/binding has retired rather than being carried into the new socket"):await abort("old peer retirement");return
	var evidence:=audit_snapshot("PASS")
	var teardown_ok:bool=await teardown()
	evidence.teardown_ok=teardown_ok
	evidence.teardown_capture=teardown_capture.duplicate(true)
	if not teardown_ok:
		check(false,"Teardown releases every owned test node before natural completion")
		evidence.outcome="FAIL"
		evidence.first_failure=failure_label
	var audit_ok:=write_audit(evidence)
	if not audit_ok and failures==0:check(false,"Final evidence sidecar is written and read back exactly")
	print("QUEST AUTO LOOT PUBLIC REMOTE UI: %d failures; actual WsServer transport binding, backend-null A/B, real button, durable E1/ACK, duplicate refusal, generic Stop and late-owner ACK; test-only encounter-suppressed idle fixture; account authentication/source route/natural battle/2760/P3 acceptance=false"%failures)
	quit(1 if failures else 0)

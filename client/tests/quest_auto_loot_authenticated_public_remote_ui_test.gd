extends "res://tests/quest_auto_loot_public_remote_ui_test.gd"
## UNRUN authenticated extension of the accepted 392b remote UI oracle.
## Requires only the reviewed ProfileHub factory seam in profile-hub-factory.patch.
## Test-only capability override is immutable and shared by projection/admission.
const HubScript = preload("res://server/profile_hub.gd")
const PublicRemoteTest = preload("res://tests/quest_auto_loot_public_remote_ui_test.gd")
const BackendScript = preload("res://server/backend.gd")
const SaveLockType = preload("res://server/save_lock.gd")
const AUTH_ROOT = "user://authenticated-public-loot"
const AUTH_ACCOUNTS = AUTH_ROOT+"/accounts.json"
const AUTH_EVENT_RING_LIMIT = 16
const MAX_SAFE_WIRE_REVISION: int = 9007199254740991

class AuthLootBackend extends PublicRemoteTest.PublicBackend:
	var handler_writer_boundaries: Array = []
	var handler_stop_boundaries: Array = []
	const HANDLER_BOUNDARY_LIMIT := 4
	const CHECKPOINT_RECORD_LIMIT := 8
	var writer_kind_counts: Dictionary = {"loot_settlement_written":0,"save_profile_boundary":0}
	# Empty phase means only an independently proven no-op Hub checkpoint is allowed.
	var expected_profile_save_phase: String = ""
	var expected_profile_save_native: Dictionary = {}
	var ordinary_checkpoint_records: Array = []
	var ordinary_checkpoint_overflow := false
	var startup_request_observe: bool = false
	var startup_request_records: Array = []
	var startup_request_overflow: bool = false
	const STARTUP_REQUEST_RECORD_LIMIT := 8
	const STARTUP_NOOP_SAVE_RING_LIMIT := 8
	const STARTUP_SIDE_EFFECT_RING_LIMIT := 16
	var startup_noop_save_observe := false
	var startup_noop_save_ring: Array = []
	var startup_noop_save_total := 0
	var startup_noop_save_overflow := false
	var startup_noop_save_error := ""
	var startup_noop_session_ref: WeakRef
	var startup_noop_backend_ref: WeakRef
	var startup_noop_hub_ref: WeakRef
	var startup_noop_profile_id := ""
	var startup_noop_path := ""
	var startup_noop_native: Dictionary = {}
	var startup_noop_cache := ""
	var startup_noop_disk: Dictionary = {}
	var startup_noop_serial_baseline := -1
	var startup_noop_writer_baseline := -1
	var startup_noop_kind_baseline: Dictionary = {}
	var startup_noop_profile_event_baseline := -1
	var startup_noop_checkpoint_baseline := -1
	var startup_noop_resume_write_baseline := -1
	var startup_noop_start_event_baseline := -1
	var startup_noop_keep_resume_current := false
	var startup_noop_required_fee_call_count := 0
	var startup_settings_command_count := 0
	var startup_settings_pending_bypass_count := 0
	var startup_side_effect_ring: Array = []
	var startup_side_effect_total := 0
	var startup_side_effect_overflow := false
	var startup_side_effect_error := ""
	var startup_release_observe_calls := 0
	var startup_resume_path := ""
	var startup_resume_tmp_path := ""
	var startup_noop_summary: Dictionary = {}
	var post_startup_baseline_ready := false
	var post_startup_serial := -1
	var post_startup_writer_total := -1
	var post_startup_save_kind_total := -1
	var post_startup_settlement_kind_total := -1
	var post_startup_profile_event_total := -1
	var post_startup_checkpoint_total := -1
	var post_startup_resume_write_total := -1
	func arm_startup_noop_save_observer(expected_hub: Variant, expected_profile_id: String, expected_session: Variant, expected_path: String, expected_native: Dictionary, expected_cache: String, expected_disk: Dictionary) -> bool:
		if startup_noop_save_observe or observe or account_name!="AuthBob" or not is_instance_valid(expected_hub) or not is_instance_valid(expected_session):return false
		if not is_same(session,expected_session) or not session._pending.is_empty() or battle_open or expected_path.is_empty() or save_path!=expected_path or expected_native.is_empty() or expected_cache.is_empty() or expected_disk.is_empty() or not is_processing() or not keep_resume_current:return false
		startup_noop_backend_ref=weakref(self)
		startup_noop_hub_ref=weakref(expected_hub)
		startup_noop_profile_id=expected_profile_id
		startup_noop_session_ref=weakref(expected_session)
		startup_noop_path=expected_path
		if not _startup_hub_owns_backend():return false
		startup_noop_native=expected_native.duplicate(true)
		startup_noop_cache=expected_cache
		startup_noop_disk=expected_disk.duplicate(true)
		startup_noop_serial_baseline=quest_save_serial
		startup_noop_writer_baseline=writer_event_count
		startup_noop_kind_baseline=_writer_kind_snapshot()
		startup_noop_profile_event_baseline=profile_event_count
		startup_noop_checkpoint_baseline=ordinary_checkpoint_records.size()
		startup_noop_resume_write_baseline=resume_writes
		startup_noop_start_event_baseline=start_event_count
		startup_noop_keep_resume_current=keep_resume_current
		startup_resume_path=_resume_file()
		startup_resume_tmp_path=startup_resume_path+".tmp"
		if startup_resume_path.is_empty() or FileAccess.file_exists(startup_resume_path) or FileAccess.file_exists(startup_resume_tmp_path):return false
		observe=true
		startup_noop_save_observe=true
		return true
	func _startup_hub_owns_backend() -> bool:
		if startup_noop_hub_ref==null or not is_instance_valid(startup_noop_hub_ref):return false
		var owner_hub: Variant=startup_noop_hub_ref.get_ref()
		if not is_instance_valid(owner_hub):return false
		var registered_backend: Variant=owner_hub.backends.get(startup_noop_profile_id,null)
		return registered_backend is AuthLootBackend and is_instance_valid(registered_backend) and is_same(registered_backend,self)
	func _startup_side_effect(record: Dictionary) -> void:
		startup_side_effect_total+=1
		if startup_side_effect_ring.size()>=STARTUP_SIDE_EFFECT_RING_LIMIT:
			startup_side_effect_overflow=true
			startup_side_effect_error="replacement startup side-effect evidence overflowed its fixed ring"
			return
		startup_side_effect_ring.append(record)
	func _write_resume_file(path: String, state: Dictionary) -> void:
		var audit: bool=startup_noop_save_observe
		var path_matches: bool=path==startup_resume_path if audit else false
		var existed_before: bool=FileAccess.file_exists(path) if audit else false
		var tmp_existed_before: bool=FileAccess.file_exists(path+".tmp") if audit else false
		super._write_resume_file(path,state)
		if audit:
			var existed_after: bool=FileAccess.file_exists(path)
			var tmp_existed_after: bool=FileAccess.file_exists(path+".tmp")
			_startup_side_effect({"kind":"write_resume_file","path_matches":path_matches,"state_empty":state.is_empty(),"existed_before":existed_before,"tmp_before":tmp_existed_before,"existed_after":existed_after,"tmp_after":tmp_existed_after})
			startup_side_effect_error="unexpected replacement-startup resume write was observed"
	func _remove_resume_file(path: String) -> void:
		var audit: bool=startup_noop_save_observe
		var path_matches: bool=path==startup_resume_path if audit else false
		var existed_before: bool=FileAccess.file_exists(path) if audit else false
		super._remove_resume_file(path)
		if audit:
			var existed_after: bool=FileAccess.file_exists(path)
			_startup_side_effect({"kind":"remove_resume_file","path_matches":path_matches,"existed_before":existed_before,"existed_after":existed_after})
			if not path_matches or existed_before or existed_after:startup_side_effect_error="resume removal changed or targeted an unexpected replacement-startup file"
	func _save_required_fee(frame: Dictionary) -> bool:
		if startup_noop_save_observe:startup_noop_required_fee_call_count+=1
		return super._save_required_fee(frame)
	func _record_releases() -> void:
		var audit: bool=startup_noop_save_observe
		var release_count: int=session.release_events.size() if audit and is_instance_valid(session) else 0
		var capture_count: int=session.capture_events.size() if audit and is_instance_valid(session) else 0
		var stop_count: int=automation.stop_events.size() if audit and is_instance_valid(automation) else 0
		if audit:startup_release_observe_calls+=1
		super._record_releases()
		if audit and (release_count>0 or capture_count>0 or stop_count>0):
			_startup_side_effect({"kind":"release_log_input","release_events_before":release_count,"capture_events_before":capture_count,"stop_events_before":stop_count})
			startup_side_effect_error="unexpected release/capture/stop log input occurred during replacement startup"
	func _startup_parent_disk_slots_summary(writer_event: Variant) -> Dictionary:
		var result: Dictionary={"input_valid":false,"valid":false}
		if not writer_event is Dictionary:return result
		var before_value: Variant=writer_event.get("disk_before",null)
		var after_value: Variant=writer_event.get("disk_after",null)
		if not before_value is Dictionary or not after_value is Dictionary:return result
		var baseline: Dictionary=_disk_summary(startup_noop_disk)
		var all_valid: bool=true
		for slot in ["primary","backup","tmp"]:
			var before_row: Variant=before_value.get(slot,null)
			var after_row: Variant=after_value.get(slot,null)
			var baseline_row: Variant=baseline.get(slot,null)
			var row_valid: bool=before_row is Dictionary and after_row is Dictionary and baseline_row is Dictionary
			if row_valid:
				var before_exists: Variant=before_row.get("exists",null)
				var after_exists: Variant=after_row.get("exists",null)
				var before_ok: Variant=before_row.get("ok",null)
				var after_ok: Variant=after_row.get("ok",null)
				var before_length: Variant=before_row.get("actual",null)
				var after_length: Variant=after_row.get("actual",null)
				var before_hash: Variant=before_row.get("sha256",null)
				var after_hash: Variant=after_row.get("sha256",null)
				row_valid=before_exists is bool and after_exists is bool and before_ok is bool and after_ok is bool and before_hash is String and after_hash is String
				if before_exists is bool and before_exists:
					var before_declared: Variant=before_row.get("declared",null)
					var after_declared: Variant=after_row.get("declared",null)
					row_valid=row_valid and after_exists==true and before_ok==true and after_ok==true and before_declared is int and after_declared is int and before_length is int and after_length is int
					if before_hash is String and after_hash is String:
						row_valid=row_valid and before_hash.length()==64 and after_hash.length()==64
					else:
						row_valid=false
				elif before_exists is bool:
					var absent_hashes_valid: bool=before_hash is String and after_hash is String and before_hash.is_empty() and after_hash.is_empty()
					row_valid=row_valid and after_exists==false and before_ok==false and after_ok==false and before_length==null and after_length==null and absent_hashes_valid
			var before_frozen: bool=row_valid and before_row==baseline_row
			var after_frozen: bool=row_valid and after_row==baseline_row
			var row: Dictionary={"record_valid":row_valid,"before_exists":before_row.get("exists",null) if before_row is Dictionary else null,"after_exists":after_row.get("exists",null) if after_row is Dictionary else null,"before_ok":before_row.get("ok",null) if before_row is Dictionary else null,"after_ok":after_row.get("ok",null) if after_row is Dictionary else null,"before_length":before_row.get("actual",null) if before_row is Dictionary else null,"after_length":after_row.get("actual",null) if after_row is Dictionary else null,"before_sha256":before_row.get("sha256",null) if before_row is Dictionary else null,"after_sha256":after_row.get("sha256",null) if after_row is Dictionary else null,"before_frozen":before_frozen,"after_frozen":after_frozen,"bytes_equal":before_row==after_row if before_row is Dictionary and after_row is Dictionary else false}
			result[slot]=row
			all_valid=all_valid and row_valid and before_frozen and after_frozen and row.bytes_equal
		result.input_valid=true
		result.valid=all_valid
		return result
	func _startup_disk_slots_same(slots_value: Variant) -> bool:
		if not slots_value is Dictionary or not (slots_value.get("valid",null) is bool) or not slots_value.valid:return false
		for slot in ["primary","backup","tmp"]:
			var row: Variant=slots_value.get(slot,null)
			if not row is Dictionary or not (row.get("record_valid",null) is bool) or not row.record_valid:return false
			var before_exists: Variant=row.get("before_exists",null)
			var after_exists: Variant=row.get("after_exists",null)
			if not (before_exists is bool) or not (after_exists is bool) or before_exists!=after_exists:return false
			if before_exists:
				if not (row.get("before_ok",null) is bool) or not row.before_ok or not (row.get("after_ok",null) is bool) or not row.after_ok or not (row.get("before_frozen",null) is bool) or not row.before_frozen or not (row.get("after_frozen",null) is bool) or not row.after_frozen or not (row.get("bytes_equal",null) is bool) or not row.bytes_equal:return false
				if not (row.get("before_length",null) is int) or not (row.get("after_length",null) is int) or row.before_length!=row.after_length:return false
			else:
				if row.get("before_frozen",null)!=true or row.get("after_frozen",null)!=true or row.get("bytes_equal",null)!=true:return false
		return true
	func _startup_noop_record_valid(record: Variant, prior_serial: int) -> bool:
		if not record is Dictionary:return false
		for key in ["result_ok","backend_same","session_same_before","session_same_after","path_matches","nonempty_path","phase_empty","checkpoint_empty","native_before_frozen","native_after_frozen","cache_before_frozen","cache_after_frozen","cache_stable","disk_before_frozen","disk_after_frozen","disk_stable","disk_slots_same","parent_event_matches","hub_backend_same_before","hub_backend_same_after","fast_path_inferred","serial_step","revision_stable","profile_events_stable","writer_step","save_kind_step","pending_empty_before","pending_empty_after","battle_closed_before","battle_closed_after"]:
			if not (record.get(key,null) is bool) or not record[key]:return false
		var serial_before: Variant=record.get("serial_before",null)
		var serial_after: Variant=record.get("serial_after",null)
		var ordinal: Variant=record.get("ordinal",null)
		var save_kind_before: Variant=record.get("save_kind_before",null)
		var save_kind_after: Variant=record.get("save_kind_after",null)
		var save_kind_baseline: Variant=startup_noop_kind_baseline.get("save_profile_boundary",null)
		var save_kind_chain_valid: bool=ordinal is int and ordinal>0 and save_kind_baseline is int and save_kind_before is int and save_kind_after is int and save_kind_before==save_kind_baseline+ordinal-1 and save_kind_after==save_kind_before+1 and save_kind_after==save_kind_baseline+ordinal
		return serial_before is int and serial_after is int and serial_before==prior_serial and serial_after==serial_before+1 and save_kind_chain_valid
	func finish_startup_noop_save_observer(serial_after: int, writer_after: int, kinds_after: Dictionary, profile_events_after: int, checkpoints_after: int, resume_writes_after: int) -> Dictionary:
		startup_noop_save_observe=false
		var count: int=startup_noop_save_total
		var save_delta: int=_writer_kind_delta(startup_noop_kind_baseline,kinds_after,"save_profile_boundary")
		var settlement_delta: int=_writer_kind_delta(startup_noop_kind_baseline,kinds_after,"loot_settlement_written")
		var writer_delta: int=writer_after-startup_noop_writer_baseline
		var checkpoint_delta: int=checkpoints_after-startup_noop_checkpoint_baseline
		var expected_serial: int=startup_noop_serial_baseline+count
		var records_valid: bool=not startup_noop_save_overflow and startup_noop_save_ring.size()==count
		var prior_serial: int=startup_noop_serial_baseline
		for value in startup_noop_save_ring:
			if not _startup_noop_record_valid(value,prior_serial):records_valid=false
			if value is Dictionary and value.get("serial_after",null) is int:prior_serial=value.serial_after
		# No-op startup callbacks are represented only by the compact bounded ring;
		# retain no repeated full native/cache/disk snapshots in ordinary records.
		var checkpoint_records_valid: bool=checkpoint_delta==0 and _checkpoint_records_valid_from(startup_noop_checkpoint_baseline)
		var counters_valid: bool=count>=0 and writer_delta==count and save_delta==count and settlement_delta==0 and _writer_counts_reconcile() and _checkpoint_count_reconciles()
		var serial_valid: bool=serial_after==expected_serial and (count==0 or prior_serial==serial_after)
		var expected_backend_at_finish: Variant=startup_noop_backend_ref.get_ref() if startup_noop_backend_ref!=null and is_instance_valid(startup_noop_backend_ref) else null
		var expected_session_at_finish: Variant=startup_noop_session_ref.get_ref() if startup_noop_session_ref!=null and is_instance_valid(startup_noop_session_ref) else null
		var backend_still_hub_owned: bool=_startup_hub_owns_backend()
		var identity_valid: bool=is_instance_valid(expected_backend_at_finish) and is_same(expected_backend_at_finish,self) and is_instance_valid(expected_session_at_finish) and is_same(expected_session_at_finish,session) and backend_still_hub_owned and save_path==startup_noop_path
		var side_effects_valid: bool=not startup_side_effect_overflow and startup_side_effect_error.is_empty() and resume_writes_after==startup_noop_resume_write_baseline and keep_resume_current==startup_noop_keep_resume_current and keep_resume_current and _resume_file()==startup_resume_path and start_event_count==startup_noop_start_event_baseline
		var side_effect_ring_complete: bool=not startup_side_effect_overflow and startup_side_effect_total==startup_side_effect_ring.size()
		var valid: bool=records_valid and checkpoint_records_valid and counters_valid and serial_valid and identity_valid and side_effects_valid and side_effect_ring_complete and startup_noop_required_fee_call_count==0 and startup_settings_pending_bypass_count==0 and startup_noop_save_error.is_empty()
		startup_noop_summary={"valid":valid,"count":count,"ring_count":startup_noop_save_ring.size(),"ring_overflow":startup_noop_save_overflow,"observer_error":startup_noop_save_error,"serial_before":startup_noop_serial_baseline,"serial_after":serial_after,"serial_expected_from_verified_calls":expected_serial,"serial_chain_valid":serial_valid and records_valid,"writer_total_before":startup_noop_writer_baseline,"writer_total_after":writer_after,"writer_delta":writer_delta,"save_kind_delta":save_delta,"settlement_kind_delta":settlement_delta,"checkpoint_records_before":startup_noop_checkpoint_baseline,"checkpoint_records_after":checkpoints_after,"checkpoint_records_delta":checkpoint_delta,"checkpoint_records_valid":checkpoint_records_valid,"startup_save_callbacks_compact_only":count,"save_kind_equals_full_records_plus_compact_callbacks":counters_valid,"profile_events_before":startup_noop_profile_event_baseline,"profile_events_after":profile_events_after,"resume_writes_before":startup_noop_resume_write_baseline,"resume_writes_after":resume_writes_after,"keep_resume_current_stable":keep_resume_current==startup_noop_keep_resume_current and keep_resume_current,"resume_path_stable":_resume_file()==startup_resume_path,"start_event_count_before":startup_noop_start_event_baseline,"start_event_count_after":start_event_count,"resume_side_effect_total":startup_side_effect_total,"resume_side_effect_overflow":startup_side_effect_overflow,"resume_side_effect_error":startup_side_effect_error,"release_observer_calls":startup_release_observe_calls,"required_fee_calls":startup_noop_required_fee_call_count,"startup_settings_command_count":startup_settings_command_count,"startup_settings_pending_bypass_count":startup_settings_pending_bypass_count,"side_effect_ring_complete":side_effect_ring_complete,"side_effect_ring":startup_side_effect_ring.duplicate(true),"save_ring":startup_noop_save_ring.duplicate(true)}
		return startup_noop_summary.duplicate(true)
	func _record_startup_request(type_value: String, command: Dictionary, reply: Dictionary, rev_before: int, serial_before: int) -> void:
		if not startup_request_observe or account_name!="AuthBob":return
		var record: Dictionary={"type":type_value,"seq":command.get("seq",null) if command.get("seq",null) is int else null,"backend_rev_before":rev_before,"backend_rev_after":rev,"serial_before":serial_before,"serial_after":quest_save_serial,"reply_type":reply.get("type",null) if reply.get("type",null) is String else null,"reply_ok":reply.get("ok",null) if reply.get("ok",null) is bool else null,"frame":Engine.get_process_frames()}
		if startup_request_records.size()>=STARTUP_REQUEST_RECORD_LIMIT:
			startup_request_overflow=true
			return
		startup_request_records.append(record)
	func _profile_command(type: String, command: Dictionary) -> Dictionary:
		var rev_before: int=rev
		var serial_before: int=quest_save_serial
		var reply: Dictionary=super._profile_command(type,command)
		_record_startup_request(type,command,reply,rev_before,serial_before)
		return reply
	func _cmd_checkpoint(command: Dictionary) -> Dictionary:
		var rev_before: int=rev
		var serial_before: int=quest_save_serial
		var reply: Dictionary=super._cmd_checkpoint(command)
		_record_startup_request("checkpoint",command,reply,rev_before,serial_before)
		return reply
	func _cmd_report_position(command: Dictionary) -> Dictionary:
		var rev_before: int=rev
		var serial_before: int=quest_save_serial
		var reply: Dictionary=super._cmd_report_position(command)
		_record_startup_request("report_position",command,reply,rev_before,serial_before)
		return reply
	func _cmd_set_automation_settings(command: Dictionary) -> Dictionary:
		var rev_before: int=rev
		var serial_before: int=quest_save_serial
		var observing: bool=startup_noop_save_observe
		var pending_before: bool=is_instance_valid(session) and not session._pending.is_empty()
		if observing:
			startup_settings_command_count+=1
			if not save_path.is_empty() and pending_before:
				startup_settings_pending_bypass_count+=1
				startup_noop_save_error="pending automation-settings save bypassed _save_profile_boundary during Bob startup"
		var reply: Dictionary=super._cmd_set_automation_settings(command)
		_record_startup_request("set_automation_settings",command,reply,rev_before,serial_before)
		return reply
	func _writer_kind_total() -> int:
		var total: int = 0
		for kind in writer_kind_counts:
			var count: Variant = writer_kind_counts[kind]
			if not kind is String or not count is int or count < 0:
				observation_error = "writer kind counter has an invalid type or value"
				return -1
			total += count
		return total
	func _writer_kind_snapshot() -> Dictionary:
		return writer_kind_counts.duplicate(true)
	func _writer_kind_delta(before: Dictionary, after: Dictionary, kind: String) -> int:
		var before_value: Variant = before.get(kind, null)
		var after_value: Variant = after.get(kind, null)
		if not before_value is int or not after_value is int:
			return -1
		return after_value - before_value
	func _writer_counts_reconcile() -> bool:
		return writer_event_count >= 0 and _writer_kind_total() == writer_event_count and observation_error.is_empty()
	func _record_writer_kind(kind: String, total_before: int) -> void:
		if not observe:
			return
		var prior: Variant = writer_kind_counts.get(kind, null)
		if not prior is int or prior < 0 or writer_event_count != total_before + 1:
			observation_error = "writer callback classification did not reconcile with the observed event counter"
			return
		writer_kind_counts[kind] = prior + 1
	func _checkpoint_record_ok(record: Variant) -> bool:
		if not record is Dictionary:
			return false
		var native_before: Variant = record.get("native_before", null)
		var native_after: Variant = record.get("native_after", null)
		var expected_native: Variant = record.get("expected_native_after", null)
		var cache_before: Variant = record.get("cache_before", null)
		var cache_after: Variant = record.get("cache_after", null)
		var disk_before: Variant = record.get("disk_before", null)
		var disk_after: Variant = record.get("disk_after", null)
		var serial_before: Variant = record.get("serial_before", null)
		var serial_after: Variant = record.get("serial_after", null)
		var shared_ok: bool = record.get("kind", null) == "save_profile_boundary" and record.get("ok", null) is bool and record.get("ok", false) and record.get("owner_is_current_session", null) is bool and record.get("owner_is_current_session", false) and record.get("session_identity_unchanged", null) is bool and record.get("session_identity_unchanged", false) and record.get("production_snapshot_expression", null) is String and record.production_snapshot_expression == "JSON.stringify(session.snapshot())" and record.get("path_is_current", null) is bool and record.get("path_is_current", false) and record.get("path_nonempty", null) is bool and record.get("path_nonempty", false) and record.get("checkpoint_empty", null) is bool and record.get("checkpoint_empty", false) and native_before is Dictionary and native_after is Dictionary and cache_before is String and not cache_before.is_empty() and cache_after is String and disk_before is Dictionary and disk_after is Dictionary and serial_before is int and serial_after is int and serial_after == serial_before + 1 and record.get("revision_before", null) is int and record.get("revision_after", null) is int and record.revision_after == record.revision_before and record.get("profile_events_before", null) is int and record.get("profile_events_after", null) is int and record.profile_events_after == record.profile_events_before
		if not shared_ok:
			return false
		var classification: Variant = record.get("classification", null)
		if classification == "hub_same_payload_checkpoint":
			return native_before == native_after and cache_after == cache_before and disk_after == disk_before and record.get("production_snapshot_payload_matches_cache", null) is bool and record.production_snapshot_payload_matches_cache and record.get("same_payload_fast_path_inferred", null) is bool and record.same_payload_fast_path_inferred
		if classification == "gm_grant_points_commit":
			var payload: Variant = record.get("payload", null)
			var expected_payload_profile: Variant = expected_native
			var primary: Variant = disk_after.get("primary", null) if disk_after is Dictionary else null
			var primary_bytes: Variant = primary.get("bytes", null) if primary is Dictionary else null
			var backup: Variant = disk_after.get("backup", null) if disk_after is Dictionary else null
			var backup_before: Variant = disk_before.get("primary", null) if disk_before is Dictionary else null
			var temporary: Variant = disk_after.get("tmp", null) if disk_after is Dictionary else null
			var decoded_payload: Variant = JSON.parse_string(payload) if payload is String else null
			var decoded_valid: bool = is_instance_valid(session) and decoded_payload is Dictionary and session._valid_profile(decoded_payload)
			var decoded_normalized: Variant = session._normalize_numbers(decoded_payload.duplicate(true)) if decoded_valid else null
			var expected_normalized: Variant = session._normalize_numbers(expected_payload_profile.duplicate(true)) if is_instance_valid(session) and expected_payload_profile is Dictionary else null
			var payload_valid: bool = decoded_valid and decoded_normalized is Dictionary and expected_normalized is Dictionary and decoded_normalized == expected_normalized
			return expected_payload_profile is Dictionary and native_before == expected_payload_profile and native_after == expected_payload_profile and payload is String and payload_valid and cache_after == payload and primary is Dictionary and primary.get("ok", null) is bool and primary.ok and primary_bytes is PackedByteArray and primary_bytes == payload.to_utf8_buffer() and backup is Dictionary and backup.get("ok", null) is bool and backup.ok and backup.get("bytes", null) is PackedByteArray and backup_before is Dictionary and backup_before.get("bytes", null) is PackedByteArray and backup.bytes == backup_before.bytes and temporary is Dictionary and temporary.get("exists", null) is bool and not temporary.exists and record.get("production_snapshot_payload_matches_cache", null) is bool and not record.production_snapshot_payload_matches_cache and record.get("same_payload_fast_path_inferred", null) is bool and not record.same_payload_fast_path_inferred
		return false
	func _checkpoint_count_reconciles() -> bool:
		var count: Variant = writer_kind_counts.get("save_profile_boundary", null)
		# Full records cover ordinary/transactional saves. Startup no-op callbacks
		# are counted separately and proved by their compact, bounded per-call ring.
		return count is int and count == ordinary_checkpoint_records.size()+startup_noop_save_total and not ordinary_checkpoint_overflow
	func _checkpoint_records_valid_from(first_index: int) -> bool:
		if first_index < 0 or first_index > ordinary_checkpoint_records.size() or ordinary_checkpoint_overflow:
			return false
		for index in range(first_index, ordinary_checkpoint_records.size()):
			if not _checkpoint_record_ok(ordinary_checkpoint_records[index]):
				return false
		return true
	func _checkpoint_disk_slots_summary(before_value: Variant, after_value: Variant) -> Dictionary:
		var summary: Dictionary = {"input_valid":before_value is Dictionary and after_value is Dictionary}
		if not summary.input_valid:
			return summary
		var slots: Array[String] = ["primary","backup","tmp"]
		for slot_value in slots:
			var slot: String = slot_value
			var before_slot: Variant = before_value.get(slot,null)
			var after_slot: Variant = after_value.get(slot,null)
			if not before_slot is Dictionary or not after_slot is Dictionary:
				summary[slot]={"record_valid":false}
				continue
			var before_bytes: Variant = before_slot.get("bytes",null)
			var after_bytes: Variant = after_slot.get("bytes",null)
			var bytes_available: bool = before_bytes is PackedByteArray and after_bytes is PackedByteArray
			summary[slot]={"record_valid":true,"before_exists":before_slot.get("exists",null),"after_exists":after_slot.get("exists",null),"before_ok":before_slot.get("ok",null),"after_ok":after_slot.get("ok",null),"before_length":before_bytes.size() if before_bytes is PackedByteArray else null,"after_length":after_bytes.size() if after_bytes is PackedByteArray else null,"bytes_equal":before_bytes==after_bytes if bytes_available else null}
		return summary
	func _checkpoint_summary_from(first_index: int) -> Array:
		var result: Array = []
		if first_index < 0 or first_index > ordinary_checkpoint_records.size():
			return result
		for index in range(first_index, ordinary_checkpoint_records.size()):
			var record: Variant = ordinary_checkpoint_records[index]
			if record is Dictionary:
				var expected_value: Variant = record.get("expected_native_after", null)
				var native_value: Variant = record.get("native_after", null)
				var expected_nonempty: bool = expected_value is Dictionary and not expected_value.is_empty()
				result.append({"index":index,"classification":record.get("classification",null),"ok":record.get("ok",null),"frame_before":record.get("frame_before",null),"frame_after":record.get("frame_after",null),"serial_before":record.get("serial_before",null),"serial_after":record.get("serial_after",null),"revision_before":record.get("revision_before",null),"revision_after":record.get("revision_after",null),"profile_events_before":record.get("profile_events_before",null),"profile_events_after":record.get("profile_events_after",null),"native_equal":record.get("native_before",null)==native_value,"native_matches_expected":expected_nonempty and native_value==expected_value,"cache_equal":record.get("cache_before",null)==record.get("cache_after",null),"disk_slots":_checkpoint_disk_slots_summary(record.get("disk_before",null),record.get("disk_after",null)),"production_snapshot_payload_matches_cache":record.get("production_snapshot_payload_matches_cache",null),"same_payload_fast_path_inferred":record.get("same_payload_fast_path_inferred",false)})
		return result
	func _quest_loot_public_enabled() -> bool:
		return true
	func _cmd_quest_loot_start(command: Dictionary) -> Dictionary:
		var writer_count_before: int = writer_event_count
		var writer_records_before: int = writer_records.size()
		var writer_kinds_before: Dictionary = _writer_kind_snapshot()
		var frame_before: int = Engine.get_process_frames()
		var result: Dictionary = super._cmd_quest_loot_start(command)
		var frame_after: int = Engine.get_process_frames()
		if handler_writer_boundaries.size() < HANDLER_BOUNDARY_LIMIT:
			handler_writer_boundaries.append({"seq":command.get("seq",null),"type":command.get("type",null),"writer_count_before":writer_count_before,"writer_count_after":writer_event_count,"writer_records_before":writer_records_before,"writer_records_after":writer_records.size(),"writer_kinds_before":writer_kinds_before,"writer_kinds_after":_writer_kind_snapshot(),"frame_before":frame_before,"frame_after":frame_after})
		else:
			observation_error = "authenticated handler boundary reached its fixed record bound"
		return result
	func _cmd_quest_auto_stop(command: Dictionary) -> Dictionary:
		var writer_count_before: int = writer_event_count
		var writer_records_before: int = writer_records.size()
		var writer_kinds_before: Dictionary = _writer_kind_snapshot()
		var frame_before: int = Engine.get_process_frames()
		var result: Dictionary = super._cmd_quest_auto_stop(command)
		var frame_after: int = Engine.get_process_frames()
		if handler_stop_boundaries.size() < HANDLER_BOUNDARY_LIMIT:
			handler_stop_boundaries.append({"seq":command.get("seq",null),"type":command.get("type",null),"writer_count_before":writer_count_before,"writer_count_after":writer_event_count,"writer_records_before":writer_records_before,"writer_records_after":writer_records.size(),"writer_kinds_before":writer_kinds_before,"writer_kinds_after":_writer_kind_snapshot(),"frame_before":frame_before,"frame_after":frame_after,"quest_running_after":quest_auto.running,"revision_after":rev,"profile_event_count_after":profile_event_count})
		else:
			observation_error = "authenticated stop boundary reached its fixed record bound"
		return result
	func _loot_settlement_written(payload: String, owner, path: String) -> void:
		var total_before: int = writer_event_count
		super._loot_settlement_written(payload, owner, path)
		_record_writer_kind("loot_settlement_written", total_before)
	func _save_profile_boundary(checkpoint: Dictionary = {}) -> bool:
		var observe_before: bool = observe
		var session_before_valid: bool = is_instance_valid(session) if observe_before else false
		var session_before_ref: WeakRef = weakref(session) if session_before_valid else null
		var session_matches_frozen_at_entry: bool = observe_before and session_before_valid and startup_noop_session_ref!=null and is_instance_valid(startup_noop_session_ref) and is_same(session_before_ref.get_ref(),startup_noop_session_ref.get_ref())
		var backend_matches_frozen_at_entry: bool = observe_before and startup_noop_backend_ref!=null and is_instance_valid(startup_noop_backend_ref) and is_same(startup_noop_backend_ref.get_ref(),self)
		var hub_backend_same_at_entry: bool=observe_before and _startup_hub_owns_backend()
		var pending_empty_before: bool = session_before_valid and session._pending.is_empty()
		var battle_closed_before: bool = not battle_open
		var total_before: int = writer_event_count
		var save_kind_before: Variant = writer_kind_counts.get("save_profile_boundary",null) if startup_noop_save_observe else null
		var serial_before: int = quest_save_serial
		var revision_before: int = rev
		var profile_events_before: int = profile_event_count
		var frame_before: int = Engine.get_process_frames()
		var timer_before: Dictionary = _timer_evidence() if observe_before and not startup_noop_save_observe else {}
		var native_before: Dictionary = session._profile.duplicate(true) if session_before_valid and session._profile is Dictionary else {}
		var cache_before: String = last_saved_payload
		var disk_before: Dictionary = _disk_set(save_path) if observe_before and not startup_noop_save_observe else {}
		var path_before: String = save_path
		var checkpoint_empty_before: bool = checkpoint.is_empty()
		var classification_before: String = "gm_grant_points_commit" if expected_profile_save_phase == "gm_grant_points" else "hub_same_payload_checkpoint" if expected_profile_save_phase.is_empty() else "unknown_phase:" + expected_profile_save_phase
		var expected_native_before: Dictionary = expected_profile_save_native.duplicate(true) if classification_before == "gm_grant_points_commit" and not expected_profile_save_native.is_empty() else {}
		var result: bool = super._save_profile_boundary(checkpoint)
		var serial_after: int = quest_save_serial
		var revision_after: int = rev
		var profile_events_after: int = profile_event_count
		var frame_after: int = Engine.get_process_frames()
		var session_after_from_weak: Variant = session_before_ref.get_ref() if session_before_ref != null else null
		var session_after_valid: bool = is_instance_valid(session_after_from_weak)
		var current_session_valid: bool = is_instance_valid(session)
		var session_identity_unchanged: bool = session_before_valid and session_after_valid and current_session_valid and is_same(session_after_from_weak,session)
		var startup_session_identity_unchanged: bool = startup_noop_save_observe and session_matches_frozen_at_entry and session_identity_unchanged and startup_noop_session_ref!=null and is_instance_valid(startup_noop_session_ref) and is_same(session_after_from_weak,startup_noop_session_ref.get_ref())
		var hub_backend_same_after: bool=observe_before and _startup_hub_owns_backend()
		var pending_empty_after: bool = session_after_valid and session_after_from_weak._pending.is_empty()
		var battle_closed_after: bool = not battle_open
		var native_after: Dictionary = session_after_from_weak._profile.duplicate(true) if observe_before and session_after_valid and session_after_from_weak._profile is Dictionary else {}
		var cache_after: String = last_saved_payload
		var disk_after: Dictionary = _disk_set(path_before) if observe_before and not startup_noop_save_observe else {}
		var parent_writer_event: Variant=writer_event_ring.back() if startup_noop_save_observe and not writer_event_ring.is_empty() else null
		var parent_event_matches: bool=false
		if parent_writer_event is Dictionary:
			parent_event_matches=parent_writer_event.get("kind",null)=="save_profile_boundary" and parent_writer_event.get("ok",null) is bool and parent_writer_event.ok==result and parent_writer_event.get("owner_is_current_session",null) is bool and parent_writer_event.owner_is_current_session and parent_writer_event.get("path_is_current",null) is bool and parent_writer_event.path_is_current and parent_writer_event.get("serial_before",null) is int and parent_writer_event.serial_before==serial_before and parent_writer_event.get("serial_after",null) is int and parent_writer_event.serial_after==quest_save_serial and parent_writer_event.get("revision_before",null) is int and parent_writer_event.revision_before==revision_before and parent_writer_event.get("revision_after",null) is int and parent_writer_event.revision_after==revision_after and parent_writer_event.get("event_count_before",null) is int and parent_writer_event.event_count_before==profile_events_before and parent_writer_event.get("event_count_after",null) is int and parent_writer_event.event_count_after==profile_events_after and parent_writer_event.get("frame_before",null) is int and parent_writer_event.frame_before==frame_before and parent_writer_event.get("frame_after",null) is int and parent_writer_event.frame_after==frame_after
		_record_writer_kind("save_profile_boundary", total_before)
		if observe_before:
			# Production Backend.save serializes exactly JSON.stringify(session.snapshot()). A second snapshot here is unsafe: GameSession.snapshot migrates equipment/storage, assigns pet IDs, synchronizes stat points and refreshes loyalty. For a nonempty path, successful return + exactly one serial increment + unchanged cache implies the same-payload branch in Backend._save_profile_boundary: if the payload differed, the successful save branch would replace last_saved_payload with it. The production branch returns before GameSession.save_game and before primary/backup/tmp I/O.
			var production_payload_matches_cache: bool = result and not path_before.is_empty() and cache_after == cache_before and serial_after == serial_before + 1
			var fast_path_inferred: bool = production_payload_matches_cache
			var record: Dictionary = {"kind":"save_profile_boundary","classification":classification_before,"ok":result,"owner_is_current_session":session_identity_unchanged,"session_identity_unchanged":session_identity_unchanged,"session_before_valid":session_before_valid,"session_after_valid":session_after_valid,"current_session_valid_after":current_session_valid,"path_is_current":path_before == save_path,"path_nonempty":not path_before.is_empty(),"checkpoint_empty":checkpoint_empty_before,"native_before":native_before,"native_after":native_after,"expected_native_after":expected_native_before,"payload":last_saved_payload,"cache_before":cache_before,"cache_after":cache_after,"disk_before":disk_before,"disk_after":disk_after,"serial_before":serial_before,"serial_after":serial_after,"revision_before":revision_before,"revision_after":revision_after,"profile_events_before":profile_events_before,"profile_events_after":profile_events_after,"frame_before":frame_before,"frame_after":frame_after,"production_snapshot_expression":"JSON.stringify(session.snapshot())","production_snapshot_payload_matches_cache":production_payload_matches_cache,"same_payload_fast_path_inferred":fast_path_inferred}
			if not startup_noop_save_observe:
				if ordinary_checkpoint_records.size() < CHECKPOINT_RECORD_LIMIT:
					ordinary_checkpoint_records.append(record)
				else:
					ordinary_checkpoint_overflow = true
					observation_error = "ordinary save callback evidence reached its fixed full-record bound"
			if startup_noop_save_observe:
				startup_noop_save_total+=1
				var save_kind_after: Variant=writer_kind_counts.get("save_profile_boundary",null)
				var expected_backend: Variant=startup_noop_backend_ref.get_ref() if startup_noop_backend_ref!=null and is_instance_valid(startup_noop_backend_ref) else null
				var expected_session: Variant=startup_noop_session_ref.get_ref() if startup_noop_session_ref!=null and is_instance_valid(startup_noop_session_ref) else null
				var disk_slots: Dictionary=_startup_parent_disk_slots_summary(parent_writer_event)
				var save_kind_baseline: Variant=startup_noop_kind_baseline.get("save_profile_boundary",null)
				var save_kind_step: bool=save_kind_before is int and save_kind_after is int and save_kind_baseline is int and save_kind_before==save_kind_baseline+startup_noop_save_total-1 and save_kind_after==save_kind_before+1 and save_kind_after==save_kind_baseline+startup_noop_save_total
				var startup_record: Dictionary={"ordinal":startup_noop_save_total,"writer_before":total_before,"writer_after":writer_event_count,"writer_step":writer_event_count==total_before+1,"save_kind_before":save_kind_before,"save_kind_after":save_kind_after,"save_kind_step":save_kind_step,"result_ok":result,"backend_same":backend_matches_frozen_at_entry and is_instance_valid(expected_backend) and is_same(expected_backend,self),"hub_backend_same_before":hub_backend_same_at_entry,"hub_backend_same_after":hub_backend_same_after,"session_same_before":session_matches_frozen_at_entry and is_instance_valid(expected_session) and is_same(session_before_ref.get_ref(),expected_session),"session_same_after":startup_session_identity_unchanged and is_instance_valid(expected_session) and is_same(session_after_from_weak,expected_session),"path_matches":path_before==startup_noop_path and save_path==startup_noop_path,"nonempty_path":not path_before.is_empty(),"phase_empty":classification_before=="hub_same_payload_checkpoint","checkpoint_empty":checkpoint_empty_before,"native_before_frozen":native_before==startup_noop_native,"native_after_frozen":native_after==startup_noop_native,"cache_before_frozen":cache_before==startup_noop_cache,"cache_after_frozen":cache_after==startup_noop_cache,"cache_stable":cache_before==cache_after,"disk_before_frozen":disk_slots.get("valid",false) is bool and disk_slots.valid,"disk_after_frozen":disk_slots.get("valid",false) is bool and disk_slots.valid,"disk_stable":disk_slots.get("valid",false) is bool and disk_slots.valid,"disk_slots":disk_slots,"disk_slots_same":_startup_disk_slots_same(disk_slots),"parent_event_matches":parent_event_matches,"serial_before":serial_before,"serial_after":serial_after,"serial_step":serial_after==serial_before+1,"revision_stable":revision_before==revision_after,"profile_events_stable":profile_events_before==profile_events_after,"fast_path_inferred":fast_path_inferred,"profile_event_before":profile_events_before,"profile_event_after":profile_events_after,"pending_empty_before":pending_empty_before,"pending_empty_after":pending_empty_after,"battle_closed_before":battle_closed_before,"battle_closed_after":battle_closed_after,"cache_before_bytes":cache_before.to_utf8_buffer().size(),"cache_after_bytes":cache_after.to_utf8_buffer().size(),"frame_before":frame_before,"frame_after":frame_after}
				if startup_noop_save_ring.size()>=STARTUP_NOOP_SAVE_RING_LIMIT:
					startup_noop_save_overflow=true
					startup_noop_save_error="replacement startup no-op save ring overflowed its fixed bound"
				else:
					startup_noop_save_ring.append(startup_record)
		return result

class AuthLootHub extends HubScript:
	const BackendType = preload("res://server/backend.gd")
	func _new_profile_backend() -> BackendType:
		return AuthLootBackend.new()

var hub: Variant
var world_c: Variant
var link_c: Variant
var account_a := ""
var account_b := ""
var alice_backend: AuthLootBackend
var bob_backend: AuthLootBackend
var alice_save_path := ""
var bob_save_path := ""
var a1_server_peer_id: int = 0
var a1_server_peer_id_found := false
var a2_server_peer_id: int = 0
var a2_server_peer_id_found := false
var bob_server_peer_id: int = 0
var bob_server_peer_id_found := false
var bob_client_peer_id: Variant = null
var bob_client_peer_id_found := false
var a1_client_peer_id_found := false
var a2_client_peer_id_found := false
var replacement_bob_server_peer_id: int = 0
var replacement_bob_server_peer_id_found := false
var replacement_bob_client_peer_id: Variant = null
var replacement_bob_client_peer_id_found := false
var a2_reconnected_server_peer_id: int = 0
var a2_reconnected_server_peer_id_found := false
var a1_server_peer_ref: WeakRef
var a2_server_peer_ref: WeakRef
var bob_server_peer_ref: WeakRef
var a2_reconnected_server_peer_ref: WeakRef
var a1_binding_ref: WeakRef
var a2_binding_ref: WeakRef
var bob_binding_ref: WeakRef
var a2_reconnected_binding_ref: WeakRef
var a1_token_before_logout := ""
var a2_token_before_reconnect := ""
var profile_message_counts: Dictionary = {}
var profile_message_rings: Dictionary = {}
var client_message_counts: Dictionary = {}
var client_message_rings: Dictionary = {}
var profile_message_callbacks: Dictionary = {}
var profile_message_world_refs: Dictionary = {}
var profile_message_link_refs: Dictionary = {}
var profile_event_phase_baselines: Dictionary = {}
var bob_backend_profile_event_count: int = 0
var bob_backend_profile_event_ring: Array = []
var bob_backend_profile_event_overflow: bool = false
var auth_peer_trace: Array = []
var auth_failure := ""
var bob_profile_frozen: Dictionary = {}
var bob_cache_frozen := ""
var bob_serial_frozen := -1
var bob_disk_frozen: Dictionary = {}
var alice_closed_profile: Dictionary = {}
var alice_closed_cache := ""
var alice_closed_serial := -1
var alice_closed_checkpoint_count := -1
var alice_closed_disk: Dictionary = {}
var auth_teardown: Dictionary = {}
var auth_writer_baseline_before_e1: int = -1
var auth_writer_records_baseline_before_e1: int = -1
var auth_writer_count_before_stop: int = -1
var auth_writer_records_before_stop: int = -1
var auth_writer_kinds_before_stop: Dictionary = {}
var worlds: Array = []

func check_e1_writer_chain(expected: Array) -> bool:
	var records: Array = alice_backend.writer_records if is_instance_valid(alice_backend) else []
	var kind_counts: Dictionary = alice_backend._writer_kind_snapshot() if is_instance_valid(alice_backend) else {}
	var start_record: Dictionary = alice_backend.start_records[0] if is_instance_valid(alice_backend) and not alice_backend.start_records.is_empty() else {}
	var handler_match: Dictionary = _matching_handler_boundary(alice_backend.handler_writer_boundaries,start_record.get("seq",null),start_record.get("type",null)) if is_instance_valid(alice_backend) else {}
	var handler: Dictionary = handler_match.get("boundary",{}) if handler_match.get("boundary",{}) is Dictionary else {}
	var handler_exact: bool = handler_match.get("unique",false) is bool and handler_match.get("unique",false) and start_record.get("type",null) is String and start_record.get("type",null)=="quest_loot_start" and handler.get("seq",null) is int and start_record.get("seq",null) is int and handler.seq==start_record.seq and handler.get("writer_count_before",null) is int and handler.get("writer_count_after",null) is int and handler.writer_count_before==auth_writer_baseline_before_e1 and handler.writer_count_after==handler.writer_count_before+2 and handler.get("writer_records_before",null) is int and handler.get("writer_records_after",null) is int and handler.writer_records_before==auth_writer_records_baseline_before_e1 and handler.writer_records_after==handler.writer_records_before+2 and handler.get("writer_kinds_before",null) is Dictionary and handler.get("writer_kinds_after",null) is Dictionary and alice_backend._writer_kind_delta(handler.writer_kinds_before,handler.writer_kinds_after,"loot_settlement_written")==2 and alice_backend._writer_kind_delta(handler.writer_kinds_before,handler.writer_kinds_after,"save_profile_boundary")==0
	var count_ok: bool = is_instance_valid(alice_backend) and expected.size()==2 and records.size()==2 and kind_counts.get("loot_settlement_written",null) is int and kind_counts.loot_settlement_written==2 and alice_backend._writer_counts_reconcile() and alice_backend._checkpoint_count_reconciles() and alice_backend._checkpoint_records_valid_from(0)
	var rows: Array = []
	var record_checks: Array = []
	for index in range(mini(2,mini(records.size(),expected.size()))):
		var record: Variant = records[index]
		var expected_profile: Variant = expected[index]
		if not record is Dictionary or not expected_profile is Dictionary:
			record_checks.append(false)
			continue
		var disk: Variant = record.get("disk_after_full",{})
		var primary: Variant = disk.get("primary",{}) if disk is Dictionary else {}
		var temporary: Variant = disk.get("tmp",{}) if disk is Dictionary else {}
		var primary_bytes: Variant = primary.get("bytes",null) if primary is Dictionary else null
		var payload: Variant = record.get("payload",null)
		var item: Dictionary = {"index":index,"kind":record.get("kind",null),"ok":record.get("ok",null),"owner":record.get("owner_is_current_session",null),"path":record.get("path_is_current",null),"serial_plus_one":record.get("serial_before",null) is int and record.get("serial_after",null) is int and record.serial_after==record.serial_before+1,"native_full_profile":record.get("native_profile_after",null)==expected_profile,"native_diff":_bounded_profile_diff(expected_profile,record.get("native_profile_after",{})),"cache_payload":record.get("cache_after",null)==payload,"primary_payload":primary.get("ok",null) is bool and primary.get("ok",false) and primary_bytes is PackedByteArray and payload is String and primary_bytes.get_string_from_utf8()==payload,"tmp_absent":temporary.get("exists",null) is bool and not temporary.get("exists",true)}
		rows.append(item)
		var item_ok: bool = record.get("kind",null)=="loot_settlement_written" and record.get("ok",null) is bool and record.get("ok",false) and record.get("owner_is_current_session",null) is bool and record.get("owner_is_current_session",false) and record.get("path_is_current",null) is bool and record.get("path_is_current",false) and item.serial_plus_one and item.native_full_profile and item.cache_payload and validated_payload(payload,expected_profile,"authenticated E1 callback %d"%index) and item.primary_payload and item.tmp_absent
		if index==0:
			var start_before: Dictionary = alice_backend.start_records[0].before
			var start_disk: Variant = start_before.get("disk",{})
			var start_primary: Variant = start_disk.get("primary",{}) if start_disk is Dictionary else {}
			var start_bytes: Variant = start_primary.get("bytes",null) if start_primary is Dictionary else null
			var backup: Variant = disk.get("backup",{}) if disk is Dictionary else {}
			item_ok = item_ok and backup is Dictionary and backup.get("ok",null) is bool and backup.get("ok",false) and backup.get("bytes",null) is PackedByteArray and start_bytes is PackedByteArray and backup.bytes==start_bytes
		if index==1:
			var prior_disk: Variant = records[0].get("disk_after_full",{}) if records[0] is Dictionary else {}
			var prior_primary: Variant = prior_disk.get("primary",{}) if prior_disk is Dictionary else {}
			var prior_bytes: Variant = prior_primary.get("bytes",null) if prior_primary is Dictionary else null
			var backup: Variant = disk.get("backup",{}) if disk is Dictionary else {}
			item_ok = item_ok and backup is Dictionary and backup.get("ok",null) is bool and backup.get("ok",false) and backup.get("bytes",null) is PackedByteArray and prior_bytes is PackedByteArray and backup.bytes==prior_bytes
			item_ok = item_ok and primary_bytes is PackedByteArray and payload is String and primary_bytes==payload.to_utf8_buffer()
		record_checks.append(item_ok)
	if not (handler_exact and count_ok and record_checks.size()==2 and bool(record_checks[0]) and bool(record_checks[1])):
		print("AUTH_PUBLIC_LOOT_E1_WRITER_CHAIN_DIAGNOSTIC ",JSON.stringify({"handler_exact_0_to_2":handler_exact,"handler_boundary":handler,"kind_counts":kind_counts,"writer_event_count":alice_backend.writer_event_count if is_instance_valid(alice_backend) else null,"writer_counts_reconcile":alice_backend._writer_counts_reconcile() if is_instance_valid(alice_backend) else false,"checkpoint_records":alice_backend._checkpoint_summary_from(0) if is_instance_valid(alice_backend) else [],"checkpoint_records_all_valid":alice_backend._checkpoint_records_valid_from(0) if is_instance_valid(alice_backend) else false,"settlement_record_count":records.size(),"record_checks":record_checks,"record_rows":rows,"observation_error_present":not alice_backend.observation_error.is_empty() if is_instance_valid(alice_backend) else true}))
	if not check(handler_exact,"One real E1 handler call synchronously advances exactly two settlement callbacks and no ordinary save callback"):return false
	if not check(count_ok,"Authenticated E1 has exactly two settlement records; any ordinary Hub saves are separately proven same-payload no-op callbacks"):return false
	return check(record_checks.size()==2 and bool(record_checks[0]) and bool(record_checks[1]),"Both E1 acquire/open callbacks retain the complete independent native/cache/payload/primary/backup/tmp oracle")

func check_stop_close_writer(expected_open_profile: Dictionary, expected_closed_profile: Dictionary) -> bool:
	var records: Array=alice_backend.writer_records if is_instance_valid(alice_backend) else []
	var kind_counts: Dictionary=alice_backend._writer_kind_snapshot() if is_instance_valid(alice_backend) else {}
	var checkpoint_ok: bool=alice_backend._checkpoint_records_valid_from(0) if is_instance_valid(alice_backend) else false
	var count_ok: bool=is_instance_valid(alice_backend) and records.size()==3 and kind_counts.get("loot_settlement_written",null) is int and kind_counts.loot_settlement_written==3 and alice_backend._writer_counts_reconcile() and alice_backend._checkpoint_count_reconciles() and checkpoint_ok
	var record: Variant=records[2] if records.size()>2 else null
	var checks: Dictionary={"count_ok":count_ok,"has_record":record is Dictionary}
	if record is Dictionary:
		var timer_value: Variant=record.get("timer_before",{})
		var timer: Dictionary=timer_value if timer_value is Dictionary else {}
		var open_ledger: Variant=expected_open_profile.get("quest_loot",{})
		var entries: Variant=open_ledger.get("entries",{}) if open_ledger is Dictionary else {}
		var open_entry: Variant=entries.get(STEP,{}) if entries is Dictionary else {}
		var open_span: Variant=timer.get("sample_span",{})
		var sample_value: Variant=timer.get("sample_used_ms",null)
		var payload: Variant=record.get("payload",null)
		var disk: Variant=record.get("disk_after_full",{})
		var primary: Variant=disk.get("primary",{}) if disk is Dictionary else {}
		var backup: Variant=disk.get("backup",{}) if disk is Dictionary else {}
		var temporary: Variant=disk.get("tmp",{}) if disk is Dictionary else {}
		var primary_bytes: Variant=primary.get("bytes",null) if primary is Dictionary else null
		var backup_bytes: Variant=backup.get("bytes",null) if backup is Dictionary else null
		var prior_disk: Variant=records[1].get("disk_after_full",{}) if records.size()>1 and records[1] is Dictionary else {}
		var prior_primary: Variant=prior_disk.get("primary",{}) if prior_disk is Dictionary else {}
		var prior_bytes: Variant=prior_primary.get("bytes",null) if prior_primary is Dictionary else null
		checks["record_kind_ok"]=record.get("kind",null)=="loot_settlement_written"
		checks["writer_ok"]=record.get("ok",null) is bool and record.get("ok",false)
		checks["owner_current"]=record.get("owner_is_current_session",null) is bool and record.get("owner_is_current_session",false)
		checks["path_current"]=record.get("path_is_current",null) is bool and record.get("path_is_current",false)
		checks["serial_plus_one"]=record.get("serial_after",null) is int and record.get("serial_before",null) is int and record.serial_after==record.serial_before+1
		checks["native_matches_expected"]=record.get("native_profile_after",null)==expected_closed_profile
		checks["native_diff_paths_types"]=_bounded_profile_diff(expected_closed_profile,record.get("native_profile_after",{}))
		checks["cache_matches_payload"]=record.get("cache_after",null)==payload
		checks["payload_validated_full_profile"]=payload is String and validated_payload(payload,expected_closed_profile,"authenticated generic Stop close")
		checks["payload_bytes"]=payload.to_utf8_buffer().size() if payload is String else null
		checks["timer_frozen"]=timer.get("frozen",false)==true
		checks["timer_storage_paused"]=timer.get("storage_paused",false)==true
		checks["sample_lifetime_current"]=timer.get("sample_lifetime_is_current",false)==true
		checks["sample_is_int"]=sample_value is int
		var open_used_value: Variant=open_entry.get("used_ms",null) if open_entry is Dictionary else null
		var open_limit_value: Variant=open_entry.get("limit_ms",null) if open_entry is Dictionary else null
		checks["sample_in_open_budget"]=sample_value is int and open_used_value is int and open_limit_value is int and sample_value>=open_used_value and sample_value<=open_limit_value
		checks["sample_span_matches"]=open_entry is Dictionary and open_span=={"budget_id":open_entry.get("budget_id",null),"generation":open_entry.get("generation",null),"issued_seq":open_entry.get("issued_seq",null)}
		checks["primary_matches_payload"]=primary.get("ok",null) is bool and primary.get("ok",false) and primary_bytes is PackedByteArray and payload is String and primary_bytes.get_string_from_utf8()==payload
		checks["backup_matches_preceding_e1_primary"]=backup.get("ok",null) is bool and backup.get("ok",false) and backup_bytes is PackedByteArray and prior_bytes is PackedByteArray and backup_bytes==prior_bytes
		checks["tmp_absent"]=temporary.get("exists",null) is bool and not temporary.get("exists",true)
		var stop_boundary: Dictionary=alice_backend.handler_stop_boundaries.back() if is_instance_valid(alice_backend) and not alice_backend.handler_stop_boundaries.is_empty() else {}
		var stop_handler_count_ok: bool=stop_boundary.get("writer_count_before",null) is int and stop_boundary.get("writer_count_after",null) is int and stop_boundary.writer_count_after==stop_boundary.writer_count_before+1 and stop_boundary.get("writer_records_after",null) is int and stop_boundary.get("writer_records_before",null) is int and stop_boundary.writer_records_after==stop_boundary.writer_records_before+1 and stop_boundary.get("writer_kinds_before",null) is Dictionary and stop_boundary.get("writer_kinds_after",null) is Dictionary and alice_backend._writer_kind_delta(stop_boundary.writer_kinds_before,stop_boundary.writer_kinds_after,"loot_settlement_written")==1 and alice_backend._writer_kind_delta(stop_boundary.writer_kinds_before,stop_boundary.writer_kinds_after,"save_profile_boundary")==0 and alice_backend._writer_kind_delta(auth_writer_kinds_before_stop,stop_boundary.writer_kinds_before,"save_profile_boundary")>=0 and alice_backend._writer_kind_delta(auth_writer_kinds_before_stop,stop_boundary.writer_kinds_before,"loot_settlement_written")==0
		checks["stop_handler_single_writer"]=stop_handler_count_ok
		print("AUTH_PUBLIC_LOOT_STOP_WRITER_ORACLE_DIAGNOSTIC ",JSON.stringify({"writer_count_before_stop":auth_writer_count_before_stop,"writer_records_before_stop":auth_writer_records_before_stop,"writer_count_after_stop_wait":alice_backend.writer_event_count if is_instance_valid(alice_backend) else null,"writer_records_after_stop_wait":records.size(),"writer_delta_from_stop_baseline":alice_backend.writer_event_count-auth_writer_count_before_stop if is_instance_valid(alice_backend) and auth_writer_count_before_stop>=0 else null,"writer_record_delta_from_stop_baseline":records.size()-auth_writer_records_before_stop if auth_writer_records_before_stop>=0 else null,"stop_handler_boundary":stop_boundary,"stop_handler_single_writer":stop_handler_count_ok,"predicates":checks,"cache_before_bytes":_string_byte_length(record.get("cache_before",null)),"cache_after_bytes":_string_byte_length(record.get("cache_after",null)),"cache_before_after_equal":record.get("cache_before",null)==record.get("cache_after",null),"serial_before":record.get("serial_before",null),"serial_after":record.get("serial_after",null),"revision_before":record.get("revision_before",null),"revision_after":record.get("revision_after",null),"event_count_before":record.get("event_count_before",null),"event_count_after":record.get("event_count_after",null),"frame_before":record.get("frame_before",null),"frame_after":record.get("frame_after",null),"record_native_diff_from_previous":_bounded_profile_diff(records[1].get("native_profile_after",{}),record.get("native_profile_after",{})) if records.size()>1 and records[1] is Dictionary else [],"disk_slots":_disk_slots_evidence(record.get("disk_before_full",{}),disk),"writer_event_ring_tail":_writer_event_ring_diagnostic(alice_backend.writer_event_ring),"kind_counts":kind_counts,"checkpoint_records":alice_backend._checkpoint_summary_from(0) if is_instance_valid(alice_backend) else [],"checkpoint_records_all_valid":checkpoint_ok,"writer_counts_reconcile":alice_backend._writer_counts_reconcile() if is_instance_valid(alice_backend) else false}))
	else:
		print("AUTH_PUBLIC_LOOT_STOP_WRITER_ORACLE_DIAGNOSTIC ",JSON.stringify({"writer_count_before_stop":auth_writer_count_before_stop,"writer_records_before_stop":auth_writer_records_before_stop,"writer_count_after_stop_wait":alice_backend.writer_event_count if is_instance_valid(alice_backend) else null,"writer_records_after_stop_wait":records.size(),"record_missing":true}))
	var required_checks: Array=["count_ok","has_record","record_kind_ok","writer_ok","owner_current","path_current","serial_plus_one","native_matches_expected","cache_matches_payload","payload_validated_full_profile","timer_frozen","timer_storage_paused","sample_lifetime_current","sample_is_int","sample_in_open_budget","sample_span_matches","primary_matches_payload","backup_matches_preceding_e1_primary","tmp_absent","stop_handler_single_writer"]
	for key in required_checks:
		if not check(checks.get(key,null) is bool and checks.get(key,false),"Authenticated Stop writer oracle: %s"%key):return false
	return true

func check(value: bool, message: String) -> bool:
	if not value and failures == 0:
		failures = 1
		auth_failure = message
		failure_label = message
		push_error(message)
	return value

func _append_profile_diff(before: Variant, after: Variant, path: String, rows: Array, depth: int) -> void:
	if rows.size() >= 24:return
	if depth >= 6:
		var before_type: int=typeof(before)
		var after_type: int=typeof(after)
		if before_type!=after_type:
			rows.append({"path":path+".<depth-limit>","before_type":type_string(before_type),"after_type":type_string(after_type)})
		elif before is Dictionary or before is Array:
			rows.append({"path":path+".<depth-limit>","before_type":type_string(before_type),"after_type":type_string(after_type)})
		elif before is bool or before is int or before is float or before is String or before is StringName:
			if before!=after:rows.append({"path":path+".<depth-limit>","before_type":type_string(before_type),"after_type":type_string(after_type)})
		else:
			rows.append({"path":path+".<depth-limit-uncompared>","before_type":type_string(before_type),"after_type":type_string(after_type)})
		return
	if before is Dictionary and after is Dictionary:
		var keys: Dictionary = {}
		var key_walk_truncated: bool = false
		for key in before:
			if keys.size()>=24:key_walk_truncated=true;break
			keys[key]=true
		for key in after:
			if keys.size()>=24:key_walk_truncated=true;break
			keys[key]=true
		for key in keys.keys():
			if rows.size() >= 24:return
			var key_name: String = str(key) if (key is String or key is StringName) else "<non-string-key>"
			if key_name.length()>80:key_name=key_name.left(80)
			var child_path: String = path+"."+key_name
			var has_before: bool = before.has(key)
			var has_after: bool = after.has(key)
			if has_before and has_after:
				_append_profile_diff(before[key],after[key],child_path,rows,depth+1)
			else:
				rows.append({"path":child_path,"before_type":type_string(typeof(before[key])) if has_before else "<missing>","after_type":type_string(typeof(after[key])) if has_after else "<missing>"})
		if (key_walk_truncated or before.size()>keys.size() or after.size()>keys.size()) and rows.size()<24:rows.append({"path":path+".<truncated>","before_type":"Dictionary","after_type":"Dictionary"})
		return
	if before is Array and after is Array:
		var limit: int = mini(maxi(before.size(),after.size()),24)
		for index in range(limit):
			if rows.size() >= 24:return
			var has_before: bool = index < before.size()
			var has_after: bool = index < after.size()
			var child_path: String = path+"["+str(index)+"]"
			if has_before and has_after:
				_append_profile_diff(before[index],after[index],child_path,rows,depth+1)
			else:
				rows.append({"path":child_path,"before_type":type_string(typeof(before[index])) if has_before else "<missing>","after_type":type_string(typeof(after[index])) if has_after else "<missing>"})
		if maxi(before.size(),after.size())>limit and rows.size()<24:rows.append({"path":path+".<truncated>","before_type":"Array","after_type":"Array"})
		return
	var before_type: int=typeof(before)
	var after_type: int=typeof(after)
	if before_type!=after_type:
		rows.append({"path":path,"before_type":type_string(before_type),"after_type":type_string(after_type)})
	elif before is bool or before is int or before is float or before is String or before is StringName or typeof(before)==TYPE_NIL:
		if before!=after:rows.append({"path":path,"before_type":type_string(before_type),"after_type":type_string(after_type)})
	else:
		rows.append({"path":path+".<unsupported-value-uncompared>","before_type":type_string(before_type),"after_type":type_string(after_type)})

func _matching_handler_boundary(boundaries: Array, request_seq: Variant, request_type: Variant) -> Dictionary:
	var matching: Array = []
	if not request_seq is int or not request_type is String:return {"unique":false,"match_count":0,"boundary":{}}
	for item in boundaries:
		if not item is Dictionary:continue
		var boundary_seq: Variant=item.get("seq",null)
		var boundary_type: Variant=item.get("type",null)
		if boundary_seq is int and boundary_type is String and boundary_seq==request_seq and boundary_type==request_type:
			matching.append(item)
	return {"unique":matching.size()==1,"match_count":matching.size(),"boundary":matching[0] if matching.size()==1 else {}}

func _handler_boundary_index_diagnostic(boundaries: Array) -> Array:
	var rows: Array=[]
	var first_index: int=maxi(0,boundaries.size()-4)
	for index in range(first_index,boundaries.size()):
		var item: Variant=boundaries[index]
		if not item is Dictionary:continue
		var seq_value: Variant=item.get("seq",null)
		var type_value: Variant=item.get("type",null)
		rows.append({"seq":seq_value if seq_value is int else null,"type":type_value if type_value is String else null})
	return rows

func _bounded_profile_diff(before: Variant, after: Variant) -> Array:
	var rows: Array = []
	_append_profile_diff(before,after,"profile",rows,0)
	return rows

func _string_byte_length(value: Variant) -> Variant:
	if not value is String:return null
	return value.to_utf8_buffer().size()

func _disk_slots_evidence(before: Variant, after: Variant) -> Dictionary:
	var result: Dictionary = {}
	var before_set: Dictionary = before if before is Dictionary else {}
	var after_set: Dictionary = after if after is Dictionary else {}
	for slot in ["primary","backup","tmp"]:
		var before_item: Variant = before_set.get(slot,{})
		var after_item: Variant = after_set.get(slot,{})
		var before_bytes: Variant = before_item.get("bytes",null) if before_item is Dictionary else null
		var after_bytes: Variant = after_item.get("bytes",null) if after_item is Dictionary else null
		var byte_arrays_available: bool = before_bytes is PackedByteArray and after_bytes is PackedByteArray
		result[slot]={"before_exists":before_item.get("exists",null) if before_item is Dictionary else null,"after_exists":after_item.get("exists",null) if after_item is Dictionary else null,"before_ok":before_item.get("ok",null) if before_item is Dictionary else null,"after_ok":after_item.get("ok",null) if after_item is Dictionary else null,"before_len":before_bytes.size() if before_bytes is PackedByteArray else null,"after_len":after_bytes.size() if after_bytes is PackedByteArray else null,"bytes_equal":before_bytes==after_bytes if byte_arrays_available else null}
	return result

func _writer_record_diagnostic(records: Array) -> Array:
	var result: Array = []
	var first_index: int = maxi(0,records.size()-4)
	for index in range(first_index,records.size()):
		var value: Variant=records[index]
		if not value is Dictionary:continue
		var profile_value: Variant=value.get("native_profile_after",{})
		var previous_profile: Variant=records[index-1].get("native_profile_after",{}) if index>first_index and records[index-1] is Dictionary else {}
		result.append({"index":index,"kind":value.get("kind",null),"ok":value.get("ok",null),"owner_is_current_session":value.get("owner_is_current_session",null),"path_is_current":value.get("path_is_current",null),"serial_before":value.get("serial_before",null),"serial_after":value.get("serial_after",null),"revision_before":value.get("revision_before",null),"revision_after":value.get("revision_after",null),"event_count_before":value.get("event_count_before",null),"event_count_after":value.get("event_count_after",null),"frame_before":value.get("frame_before",null),"frame_after":value.get("frame_after",null),"profile_diff_paths_types":_bounded_profile_diff(previous_profile,profile_value) if index>first_index else [],"cache_before_bytes":_string_byte_length(value.get("cache_before",null)),"cache_after_bytes":_string_byte_length(value.get("cache_after",null)),"cache_boundary_unchanged":value.get("cache_before",null)==value.get("cache_after",null),"disk_slots":_disk_slots_evidence(value.get("disk_before_full",{}),value.get("disk_after_full",{}))})
	return result

func _writer_event_ring_diagnostic(ring: Array) -> Array:
	var result: Array = []
	var first_index: int = maxi(0,ring.size()-16)
	for index in range(first_index,ring.size()):
		var value: Variant=ring[index]
		if not value is Dictionary:continue
		var before_disk: Variant=value.get("disk_before",{})
		var after_disk: Variant=value.get("disk_after",{})
		var slots: Dictionary={}
		for slot in ["primary","backup","tmp"]:
			var before_slot: Variant=before_disk.get(slot,{}) if before_disk is Dictionary else {}
			var after_slot: Variant=after_disk.get(slot,{}) if after_disk is Dictionary else {}
			var before_hash: Variant=before_slot.get("sha256",null) if before_slot is Dictionary else null
			var after_hash: Variant=after_slot.get("sha256",null) if after_slot is Dictionary else null
			slots[slot]={"before_exists":before_slot.get("exists",null) if before_slot is Dictionary else null,"after_exists":after_slot.get("exists",null) if after_slot is Dictionary else null,"before_bytes":before_slot.get("actual",null) if before_slot is Dictionary else null,"after_bytes":after_slot.get("actual",null) if after_slot is Dictionary else null,"hash_equal":before_hash is String and after_hash is String and before_hash==after_hash}
		result.append({"index":index,"kind":value.get("kind",null),"owner_is_current_session":value.get("owner_is_current_session",null),"path_is_current":value.get("path_is_current",null),"serial_before":value.get("serial_before",null),"serial_after":value.get("serial_after",null),"revision_before":value.get("revision_before",null),"revision_after":value.get("revision_after",null),"event_count_before":value.get("event_count_before",null),"event_count_after":value.get("event_count_after",null),"frame_before":value.get("frame_before",null),"frame_after":value.get("frame_after",null),"payload_bytes":value.get("payload_bytes",null),"disk_slots":slots})
	return result

func auth_wait(condition: Callable, message: String) -> bool:
	if failures>0:return false
	var arrived: bool = await Wait.until(self,condition)
	return check(arrived,message)

func auth_click(button: Control) -> bool:
	if not check(is_instance_valid(button),"Actual UI click target exists"):return false
	if not await auth_wait(func():return button.is_visible_in_tree() and button.size.x>0 and button.size.y>0,"Actual UI target has visible layout"):return false
	var ancestor: Node=button.get_parent()
	var scroll: ScrollContainer
	while is_instance_valid(ancestor):
		if ancestor is ScrollContainer:scroll=ancestor;break
		ancestor=ancestor.get_parent()
	if is_instance_valid(scroll):scroll.ensure_control_visible(button)
	var point: Vector2=button.get_global_transform_with_canvas()*(button.size/2)
	var motion:=InputEventMouseMotion.new()
	motion.position=point;motion.global_position=point
	root.push_input(motion,true)
	if not await auth_wait(func():
		if is_instance_valid(scroll):scroll.ensure_control_visible(button)
		point=button.get_global_transform_with_canvas()*(button.size/2)
		motion.position=point
		root.push_input(motion,true)
		return root.gui_get_hovered_control()==button,
		"Actual UI click target receives pointer hover"):return false
	point=button.get_global_transform_with_canvas()*(button.size/2)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		event.position=point;event.global_position=point
		root.push_input(event,true)
	return true

func auth_rpc(link: Variant, command: Dictionary) -> Dictionary:
	if not check(is_instance_valid(link) and link.online,"Authenticated RPC uses a live current WsLink"):return {}
	var answers: Array=[]
	link.request(command,func(reply: Dictionary):answers.append(reply))
	if not await auth_wait(func():return not answers.is_empty(),"Actual authenticated Hub RPC replies: "+str(command.get("type",""))):return {}
	return answers[0]

func auth_account(name: String, pin: String, eligible: bool) -> String:
	var created: Dictionary = hub.accounts.create(name,pin,false)
	if not check(created.get("ok",null) is bool and created.ok,"Isolated %s account fixture is created through Accounts"%name):return ""
	var entry_value: Variant = created.get("entry",null)
	if not check(entry_value is Dictionary and entry_value.get("id",null) is String,"Accounts returns a typed profile identity for %s"%name):return ""
	var profile_id: String = entry_value.id
	var profile_path: String = hub.accounts.save_path(entry_value)
	if not check(fresh(profile_path) and fresh(SaveLockType.lock_path(profile_path)),"Profile primary/backup/tmp/resume and real SaveLock paths are fresh before Hub open: %s"%name):return ""
	if not check(hub.open_profile(profile_id).is_empty(),"Real Hub opens %s through its backend factory and existing SaveLock path"%name):return ""
	var backend_value: Variant = hub.backends.get(profile_id,null)
	if not check(backend_value is AuthLootBackend,"ProfileHub factory installs the immutable test subclass before ordinary initialization for %s"%name):return ""
	var backend: AuthLootBackend = backend_value
	if not check(backend.save_path==profile_path and backend.session!=null and backend.admin==bool(entry_value.admin),"Factory preserves original profile path/session/admin initialization for %s"%name):return ""
	if not check(SaveLockType.holder_pid(profile_path)==OS.get_process_id(),"ProfileHub owns the real per-profile SaveLock before backend setup for %s"%name):return ""
	var source_catalog: Variant = backend.encounter_catalog
	if eligible:
		var idle_catalog: Variant = IdleEncounterCatalog.new(source_catalog.data)
		idle_catalog.pressure = source_catalog.pressure
		backend.encounter_catalog = idle_catalog
		var cell: Vector2i = safe_source_cell(backend)
		source_cell=cell
		if not check(cell.x>=0,"Alice's audited real source/map eligibility fixture resolves a safe cell"):return ""
		if not check(backend.session.set_location(100,cell.x,cell.y),"Alice's isolated native profile accepts the source fixture location"):return ""
		backend.automation.position_changed(100,cell,true,"project")
		backend.session.OriginalEquipment.add(backend.session._profile,2764)
		if not check(backend.session._profile.get("no_random_encounters",null) is bool and not backend.session._profile.no_random_encounters,"Public-start source eligibility retains encounter-enabled profile semantics"):return ""
		if not check(backend.encounter_catalog is IdleEncounterCatalog and backend.is_processing(),"Only the test encounter step is bounded; normal Backend processing stays on"):return ""
	else:
		if not check(not backend.session._profile.get("original_items",[]).has(2764),"Bob starts without Alice's eligibility item"):return ""
	if not check(backend.save(),"Initial %s profile is saved through the ordinary Backend writer"%name):return ""
	return profile_id

func live_server_peer(peer_id: int) -> bool:
	if not is_instance_valid(server):return false
	for peer in server.clients():
		if is_instance_valid(peer) and peer.get_instance_id()==peer_id:return true
	return false

func logout_peer_retirement_diagnostic(old_peer_id: int, old_client_peer_ref: WeakRef, old_server_peer_ref: WeakRef, old_scene_ref: WeakRef, old_link_ref: WeakRef, old_link_lifecycle_before_release: Variant, logout_callbacks_empty_at_release: bool, old_logout_generation_before: Variant, old_logout_generation_after_switch: Variant) -> Dictionary:
	var clients: Array = server.clients() if is_instance_valid(server) else []
	var clients_examined: int = mini(clients.size(),16)
	var server_peer_in_clients: bool = false
	var server_peer_state: Variant = null
	var server_peer_packet_count: Variant = null
	for index in range(clients_examined):
		var peer: Variant = clients[index]
		if not is_instance_valid(peer) or peer.get_instance_id()!=old_peer_id:continue
		server_peer_in_clients=true
		server_peer_state=peer.get_ready_state()
		server_peer_packet_count=peer.get_available_packet_count()
	var old_server_weak_peer: Variant = old_server_peer_ref.get_ref() if old_server_peer_ref!=null and is_instance_valid(old_server_peer_ref) else null
	var old_client_weak_peer: Variant = old_client_peer_ref.get_ref() if old_client_peer_ref!=null and is_instance_valid(old_client_peer_ref) else null
	var old_server_weak_valid: bool = old_server_weak_peer is WebSocketPeer and is_instance_valid(old_server_weak_peer)
	var old_client_weak_valid: bool = old_client_weak_peer is WebSocketPeer and is_instance_valid(old_client_weak_peer)
	var old_server_weak_state: Variant = old_server_weak_peer.get_ready_state() if old_server_weak_valid else null
	var old_client_weak_state: Variant = old_client_weak_peer.get_ready_state() if old_client_weak_valid else null
	var old_link: Variant = old_link_ref.get_ref() if old_link_ref!=null and is_instance_valid(old_link_ref) else null
	var old_link_valid: bool = old_link is RefCounted and is_instance_valid(old_link)
	var old_link_peer: Variant = old_link.get("_peer") if old_link_valid else null
	var old_link_peer_valid: bool = old_link_peer is WebSocketPeer and is_instance_valid(old_link_peer)
	var old_link_lifecycle_at_failure: Variant = old_link.get("_lifecycle") if old_link_valid else null
	var old_link_closed: Variant = old_link.get("_closed") if old_link_valid else null
	var old_link_started: Variant = old_link.get("_started") if old_link_valid else null
	var old_link_online: Variant = old_link.online if old_link_valid else null
	var old_link_token_value: Variant = old_link.get("login_token") if old_link_valid else null
	var old_link_token_empty: bool = old_link_token_value is String and old_link_token_value.is_empty()
	var old_link_peer_state: Variant = old_link_peer.get_ready_state() if old_link_peer_valid else null
	var old_link_peer_packet_count: Variant = old_link_peer.get_available_packet_count() if old_link_peer_valid else null
	var old_scene_weak: Variant = old_scene_ref.get_ref() if old_scene_ref!=null and is_instance_valid(old_scene_ref) else null
	var old_scene_alive: bool = is_instance_valid(old_scene_weak)
	var current_scene_valid: bool = is_instance_valid(current_scene)
	var old_peer_in_hub: bool = is_instance_valid(hub) and hub._connections.has(old_peer_id)
	var old_binding_present: bool = is_instance_valid(alice_backend) and alice_backend._fee_bindings.has(old_peer_id)
	var old_binding_identity: Dictionary = auth_binding_evidence(alice_backend,old_peer_id,a1_binding_ref)
	var old_link_is_in_pump: bool = old_link_valid and is_instance_valid(pump) and pump.links.has(old_link)
	var pump_link_count: int = pump.links.size() if is_instance_valid(pump) else -1
	var lifecycle_delta: Variant = old_link_lifecycle_at_failure-old_link_lifecycle_before_release if old_link_lifecycle_at_failure is int and old_link_lifecycle_before_release is int else null
	var logout_generation_delta: Variant = old_logout_generation_after_switch-old_logout_generation_before if old_logout_generation_after_switch is int and old_logout_generation_before is int else null
	var result: Dictionary = {"old_server_peer_id":old_peer_id,"server_peer_in_clients":server_peer_in_clients,"server_clients_count":clients.size(),"server_clients_truncated":clients.size()>clients_examined,"server_peer_state":server_peer_state,"server_peer_state_type":type_string(typeof(server_peer_state)),"server_peer_packet_count":server_peer_packet_count,"server_weak_peer_alive":old_server_weak_valid,"server_weak_peer_state":old_server_weak_state,"client_weak_peer_alive":old_client_weak_valid,"client_weak_peer_state":old_client_weak_state,"old_link_weak_alive_at_failure":old_link_valid,"old_link_in_pump_at_failure":old_link_is_in_pump,"pump_link_count":pump_link_count,"pump_processing":is_instance_valid(pump) and pump.is_processing(),"old_link_online_at_failure":old_link_online,"old_link_closed_at_failure":old_link_closed,"old_link_started_at_failure":old_link_started,"old_link_token_empty":old_link_token_empty,"old_link_lifecycle_before_release":old_link_lifecycle_before_release,"old_link_lifecycle_at_failure":old_link_lifecycle_at_failure,"old_link_lifecycle_delta":lifecycle_delta,"old_link_peer_valid_at_failure":old_link_peer_valid,"old_link_peer_state":old_link_peer_state,"old_link_peer_state_type":type_string(typeof(old_link_peer_state)),"old_link_peer_packet_count":old_link_peer_packet_count,"scene_weak_alive":old_scene_alive,"current_scene_valid":current_scene_valid,"old_peer_in_hub_connections":old_peer_in_hub,"old_peer_binding_present":old_binding_present,"old_binding_identity":old_binding_identity,"logout_generation_before":old_logout_generation_before,"logout_generation_after_switch":old_logout_generation_after_switch,"logout_generation_delta":logout_generation_delta,"server_valid":is_instance_valid(server),"server_processing":is_instance_valid(server) and server.is_processing(),"server_listening":is_instance_valid(server) and server.is_listening(),"server_stopping":server.get("_stopping") if is_instance_valid(server) else null,"server_stopped":server.get("_stopped") if is_instance_valid(server) else null,"logout_callbacks_empty_at_release":logout_callbacks_empty_at_release}
	old_link_peer=null
	old_link=null
	return result

func capture_server_peer_ref(peer_id: int) -> WeakRef:
	if not is_instance_valid(server):return null
	for peer in server.clients():
		if is_instance_valid(peer) and peer.get_instance_id()==peer_id:return weakref(peer)
	return null

func captured_server_peer_is_live(reference: WeakRef) -> bool:
	if reference==null or not is_instance_valid(reference):return false
	var candidate: Variant=reference.get_ref()
	return candidate is WebSocketPeer and is_instance_valid(candidate)

func bounded_id_evidence(values: Array) -> Dictionary:
	var items: Array = []
	var count: int = mini(values.size(),16)
	for index in range(count):
		var value: Variant=values[index]
		items.append({"type":type_string(typeof(value)),"id":value if value is int else null})
	return {"total":values.size(),"truncated":values.size()>count,"items":items}

func profile_peer_probe(profile_id: String, before: Array, world: Variant, expected_backend: Variant) -> Dictionary:
	var result: Dictionary={"found":false,"peer_id":null,"before_ids":bounded_id_evidence(before),"current_hub_ids":{"total":0,"truncated":false,"items":[]},"all_hub_connections":{"total":0,"truncated":false,"items":[]},"added_integer_ids":{"total":0,"truncated":false,"items":[]},"added_count":0,"server_peers":{"total":0,"truncated":false,"items":[]},"candidate_server_peer":{"valid":false,"type":"NIL","id":null},"candidate_server_membership":false,"candidate_owner_profile_matches":false,"candidate_backend_matches":false,"candidate_binding_present":false,"candidate_binding_type":"NIL","candidate_binding_valid":false,"candidate_binding_current":false,"client_peer":{"valid":false,"type":"NIL","id":null},"client_online":false,"client_lifecycle":null}
	if not is_instance_valid(hub):return result
	var current_ids: Array=hub.connections_of(profile_id)
	result.current_hub_ids=bounded_id_evidence(current_ids)
	var all_connection_keys: Array=hub._connections.keys()
	var all_hub_items: Array=[]
	var all_hub_limit: int=mini(all_connection_keys.size(),16)
	for index in range(all_hub_limit):
		var connection_key: Variant=all_connection_keys[index]
		var owner_matches: bool=connection_key is int and hub.profile_of(connection_key)==profile_id
		all_hub_items.append({"type":type_string(typeof(connection_key)),"id":connection_key if connection_key is int else null,"owner_profile_matches":owner_matches})
	result.all_hub_connections={"total":all_connection_keys.size(),"truncated":all_connection_keys.size()>all_hub_limit,"items":all_hub_items}
	var added_ids: Array=[]
	for value in current_ids:
		if value is int and not before.has(value):added_ids.append(value)
	result.added_integer_ids=bounded_id_evidence(added_ids)
	result.added_count=added_ids.size()
	var server_peers: Array=[]
	var candidate_id: Variant=added_ids[0] if added_ids.size()==1 else null
	var server_matches: bool=false
	var candidate_peer_evidence: Dictionary={"valid":false,"type":"NIL","id":null}
	if is_instance_valid(server):
		var clients: Array=server.clients()
		var client_limit: int=mini(clients.size(),16)
		for index in range(clients.size()):
			var peer: Variant=clients[index]
			var evidence: Dictionary={"type":type_string(typeof(peer)),"valid":is_instance_valid(peer),"id":null,"matches_candidate":false,"hub_connection_present":false,"owner_profile_matches_expected":false,"backend_matches_expected":false,"binding_present":false,"binding_type":"NIL","binding_valid":false}
			if is_instance_valid(peer):
				var actual_peer_id: int=peer.get_instance_id()
				evidence.id=actual_peer_id
				evidence.matches_candidate=candidate_id is int and evidence.id==candidate_id
				if evidence.matches_candidate:server_matches=true
				if evidence.matches_candidate:candidate_peer_evidence={"valid":true,"type":type_string(typeof(peer)),"id":evidence.id}
				evidence.hub_connection_present=hub._connections.has(actual_peer_id)
				evidence.owner_profile_matches_expected=evidence.hub_connection_present and hub.profile_of(actual_peer_id)==profile_id
				var mapped_backend: Variant=hub.backend_of(actual_peer_id) if evidence.hub_connection_present else null
				evidence.backend_matches_expected=is_instance_valid(mapped_backend) and is_instance_valid(expected_backend) and is_same(mapped_backend,expected_backend)
				var mapped_binding: Variant=mapped_backend._fee_bindings.get(actual_peer_id,null) if is_instance_valid(mapped_backend) else null
				evidence.binding_present=is_instance_valid(mapped_backend) and mapped_backend._fee_bindings.has(actual_peer_id)
				evidence.binding_type=type_string(typeof(mapped_binding))
				evidence.binding_valid=mapped_binding is RefCounted and is_instance_valid(mapped_binding)
				mapped_backend=null;mapped_binding=null
			if index<client_limit:server_peers.append(evidence)
		result.server_peers={"total":clients.size(),"truncated":clients.size()>client_limit,"items":server_peers}
		result.candidate_server_peer=candidate_peer_evidence
		result.candidate_server_membership=server_matches
		if candidate_id is int:
			var candidate_server_id: int=int(candidate_id)
			var profile_owner: String=hub.profile_of(candidate_server_id)
			result.candidate_owner_profile_matches=profile_owner==profile_id
			var actual_backend: Variant=hub.backend_of(candidate_server_id)
			result.candidate_backend_matches=is_instance_valid(actual_backend) and is_instance_valid(expected_backend) and is_same(actual_backend,expected_backend)
			var binding: Variant=actual_backend._fee_bindings.get(candidate_server_id,null) if is_instance_valid(actual_backend) else null
			result.candidate_binding_present=is_instance_valid(actual_backend) and actual_backend._fee_bindings.has(candidate_server_id)
			result.candidate_binding_type=type_string(typeof(binding))
			result.candidate_binding_valid=binding is RefCounted and is_instance_valid(binding)
			result.candidate_binding_current=result.candidate_binding_present and result.candidate_binding_valid and result.candidate_backend_matches
			actual_backend=null;binding=null
	var peer_id_evidence: Dictionary={"valid":false,"type":"NIL","id":null}
	if is_instance_valid(world):
		var link_value: Variant=world.get("link")
		if is_instance_valid(link_value):
			var client_peer: Variant=link_value.get("_peer")
			peer_id_evidence={"valid":is_instance_valid(client_peer),"type":type_string(typeof(client_peer)),"id":client_peer.get_instance_id() if is_instance_valid(client_peer) else null}
			result.client_online=link_value.get("online")==true
			var lifecycle_value: Variant=link_value.get("_lifecycle")
			result.client_lifecycle=lifecycle_value if lifecycle_value is int else null
	result.client_peer=peer_id_evidence
	result.found=added_ids.size()==1 and server_matches and result.candidate_owner_profile_matches
	result.peer_id=candidate_id if result.found else null
	return result

func wait_for_profile_peer(profile_id: String, before: Array, world: Variant, expected_backend: Variant, message: String) -> Dictionary:
	var arrived: bool=await Wait.until(self,func():return bool(profile_peer_probe(profile_id,before,world,expected_backend).get("found",false)))
	var evidence: Dictionary=profile_peer_probe(profile_id,before,world,expected_backend)
	print("AUTH_PUBLIC_LOOT_PEER_MAPPING_DIAGNOSTIC ",JSON.stringify(evidence))
	if arrived and evidence.get("found",false) is bool and evidence.found:return evidence
	check(false,message)
	return {}

func capture_auth_binding_ref(backend: Variant, peer_id: int) -> WeakRef:
	if not is_instance_valid(backend):return null
	var binding: Variant=backend._fee_bindings.get(peer_id,null)
	var reference: WeakRef=weakref(binding) if binding is RefCounted and is_instance_valid(binding) else null
	binding=null
	return reference

func auth_binding_evidence(backend: Variant, peer_id: int, reference: WeakRef) -> Dictionary:
	var expected: Variant=reference.get_ref() if reference!=null and is_instance_valid(reference) else null
	var current: Variant=backend._fee_bindings.get(peer_id,null) if is_instance_valid(backend) else null
	var expected_valid: bool=expected is RefCounted and is_instance_valid(expected)
	var current_valid: bool=current is RefCounted and is_instance_valid(current)
	var result: Dictionary={"connection_key":peer_id,"expected_type":type_string(typeof(expected)),"expected_valid":expected_valid,"expected_id":expected.get_instance_id() if expected_valid else null,"current_type":type_string(typeof(current)),"current_valid":current_valid,"current_id":current.get_instance_id() if current_valid else null,"same_object":expected_valid and current_valid and is_same(current,expected)}
	expected=null;current=null
	return result

func binding_ref_is_current(backend, peer_id: int, reference: WeakRef) -> bool:
	if reference==null or not is_instance_valid(reference):return false
	var expected: Variant = reference.get_ref()
	var current: Variant = backend._fee_bindings.get(peer_id,null)
	return expected is RefCounted and is_instance_valid(expected) and current is RefCounted and is_instance_valid(current) and is_same(current,expected)

func record_peer_mapping(tag: String, world: Variant, server_peer_id: int, profile_id: String, backend: Variant, binding_ref: WeakRef) -> void:
	var client_peer_id: Variant=null
	if is_instance_valid(world) and is_instance_valid(world.link) and is_instance_valid(world.link._peer):client_peer_id=world.link._peer.get_instance_id()
	var record: Dictionary={"tag":tag,"client_peer_id_found":client_peer_id is int,"client_peer_id":client_peer_id,"server_peer_id":server_peer_id,"server_peer_id_found":true,"profile_id":profile_id,"hub_profile":hub.profile_of(server_peer_id) if is_instance_valid(hub) else "","backend_instance_id":backend.get_instance_id() if is_instance_valid(backend) else null,"binding":auth_binding_evidence(backend,server_peer_id,binding_ref)}
	auth_peer_trace.append(record)

func tap_profile_messages(world: Variant, stream_key: String) -> void:
	profile_message_counts[stream_key]=0
	profile_message_rings[stream_key]=[]
	client_message_counts[stream_key]=0
	client_message_rings[stream_key]=[]
	var callback: Callable=Callable(self,"_record_profile_message").bind(stream_key)
	profile_message_callbacks[stream_key]=callback
	profile_message_world_refs[stream_key]=weakref(world)
	profile_message_link_refs[stream_key]=weakref(world.link)
	world.link.message.connect(callback)

func _strict_wire_revision(value: Variant) -> Variant:
	if not (value is int) or value < 0 or value > MAX_SAFE_WIRE_REVISION:return null
	return value

func _strict_backend_revision(value: Variant) -> Variant:
	if not (value is int) or value < 0 or value > MAX_SAFE_WIRE_REVISION:return null
	return value

func profile_tap_is_same_link(world: Variant, stream_key: String) -> bool:
	if not is_instance_valid(world):return false
	var weak_value: Variant=profile_message_link_refs.get(stream_key,null)
	var callback_value: Variant=profile_message_callbacks.get(stream_key,null)
	if not (weak_value is WeakRef) or not is_instance_valid(weak_value):return false
	if not (callback_value is Callable) or not callback_value.is_valid():return false
	var tapped_link: Variant=weak_value.get_ref()
	if not is_instance_valid(tapped_link):return false
	var current_link: Variant=world.link
	var same_link: bool=is_instance_valid(current_link) and is_same(tapped_link,current_link)
	var listener_connected: bool=same_link and current_link.message.is_connected(callback_value)
	tapped_link=null
	return same_link and listener_connected

func _bob_profile_projection_matches_frozen(profile_value: Variant) -> bool:
	if not profile_value is Dictionary or bob_profile_frozen.is_empty() or not is_instance_valid(bob_backend) or not is_instance_valid(bob_backend.session):return false
	var expected_profile: Dictionary=bob_profile_frozen.duplicate(true)
	expected_profile.erase("pet_storage") # Backend._publish sends storage as its separate event.
	var expected_normalized: Variant=bob_backend.session._normalize_numbers(expected_profile)
	var actual_normalized: Variant=bob_backend.session._normalize_numbers(profile_value.duplicate(true))
	return expected_normalized is Dictionary and actual_normalized is Dictionary and actual_normalized==expected_normalized

func _record_bob_backend_profile_event(message: Dictionary) -> void:
	var event_type: Variant=message.get("type",null)
	if not (event_type is String) or event_type!="profile":return
	bob_backend_profile_event_count+=1
	var profile_value: Variant=message.get("profile",null)
	var backend_revision: Variant=_strict_backend_revision(message.get("rev",null))
	var record: Dictionary={"ordinal":bob_backend_profile_event_count,"backend_rev":backend_revision,"backend_rev_valid":backend_revision is int,"frame":Engine.get_process_frames(),"matches_frozen_profile":_bob_profile_projection_matches_frozen(profile_value)}
	if bob_backend_profile_event_ring.size()>=AUTH_EVENT_RING_LIMIT:
		bob_backend_profile_event_ring.remove_at(0)
		bob_backend_profile_event_overflow=true
	bob_backend_profile_event_ring.append(record)

func _profile_event_slice(stream_key: String, baseline: int) -> Dictionary:
	var current: Variant=profile_message_counts.get(stream_key,null)
	var ring_value: Variant=profile_message_rings.get(stream_key,null)
	if not current is int or not ring_value is Array or baseline<0:return {"complete":false,"delta":null,"wire_revisions":[],"all_match_frozen":false}
	var delta: int=current-baseline
	var wire_revisions: Array=[]
	var all_match_frozen: bool=true
	for event_value in ring_value:
		if not event_value is Dictionary:continue
		var ordinal: Variant=event_value.get("ordinal",null)
		if not ordinal is int or ordinal<=baseline:continue
		var revision: Variant=_strict_wire_revision(event_value.get("wire_rev",null))
		if not (revision is int):return {"complete":false,"delta":delta,"wire_revisions":wire_revisions,"all_match_frozen":false}
		wire_revisions.append(revision)
		if stream_key in ["bob_original","bob_replacement"] and not (event_value.get("matches_frozen_profile",null) is bool):
			all_match_frozen=false
		elif stream_key in ["bob_original","bob_replacement"] and not event_value.matches_frozen_profile:
			all_match_frozen=false
	var source_ring_complete: bool=delta>=0 and delta<=ring_value.size() and wire_revisions.size()==delta
	return {"complete":source_ring_complete,"delta":delta,"wire_revisions":wire_revisions,"all_match_frozen":all_match_frozen}

func _record_profile_message(message: Dictionary, stream_key: String) -> void:
	var message_count_value: Variant=client_message_counts.get(stream_key,null)
	var message_ring_value: Variant=client_message_rings.get(stream_key,null)
	if not message_count_value is int or not message_ring_value is Array:return
	var next_message_count: int=message_count_value+1
	client_message_counts[stream_key]=next_message_count
	var message_ring: Array=message_ring_value
	if message_ring.size()>=AUTH_EVENT_RING_LIMIT:message_ring.remove_at(0)
	var event_type: Variant=message.get("type",null)
	var event_seq: Variant=message.get("seq",null)
	var event_wire_rev: Variant=_strict_wire_revision(message.get("rev",null))
	message_ring.append({"ordinal":next_message_count,"type":event_type if event_type is String else null,"seq":event_seq if event_seq is int else null,"wire_rev":event_wire_rev if event_wire_rev is int else null,"frame":Engine.get_process_frames()})
	if not (event_type is String) or event_type!="profile":return
	var count_value: Variant=profile_message_counts.get(stream_key,null)
	var ring_value: Variant=profile_message_rings.get(stream_key,null)
	if not count_value is int or not ring_value is Array:return
	var next_count: int=count_value+1
	profile_message_counts[stream_key]=next_count
	var derived_value: Variant=message.get("derived",{})
	var auto_value: Variant=derived_value.get("quest_auto",{}) if derived_value is Dictionary else {}
	var auto: Dictionary=auto_value if auto_value is Dictionary else {}
	var budget_value: Variant=auto.get("budget",{})
	var budget: Dictionary=budget_value if budget_value is Dictionary else {}
	var entry_value: Variant=budget.get("entry",null)
	var entry: Dictionary=entry_value if entry_value is Dictionary else {}
	var frozen_match: Variant=null
	if stream_key in ["bob_original","bob_replacement"]:
		frozen_match=_bob_profile_projection_matches_frozen(message.get("profile",null))
	var ring: Array=ring_value
	if ring.size()>=AUTH_EVENT_RING_LIMIT:ring.remove_at(0)
	ring.append({"ordinal":next_count,"wire_rev":event_wire_rev if event_wire_rev is int else null,"frame":Engine.get_process_frames(),"has_profile":message.get("profile",null) is Dictionary,"matches_frozen_profile":frozen_match,"run_id":auto.get("run_id",null),"run_revision":auto.get("revision",null),"budget_id":entry.get("budget_id",null),"generation":entry.get("generation",null),"entry_revision":entry.get("revision",null)})

func capture_profile_event_baseline(phase: String) -> Dictionary:
	var baseline: Dictionary={}
	for stream_key in profile_message_counts:
		var count_value: Variant=profile_message_counts.get(stream_key,null)
		if count_value is int:baseline[stream_key]=count_value
	profile_event_phase_baselines[phase]=baseline.duplicate(true)
	return baseline

func profile_event_delta(baseline: Dictionary, stream_key: String) -> int:
	var before: Variant=baseline.get(stream_key,null)
	var current: Variant=profile_message_counts.get(stream_key,null)
	if not before is int or not current is int:return -1
	return current-before

func _profile_event_route_evidence(stream_key: String, baseline: Dictionary, profile_id: String, peer_id: int, peer_found: bool, expected_backend: Variant, owner_expected: bool) -> Dictionary:
	var world_ref_value: Variant=profile_message_world_refs.get(stream_key,null)
	var world_ref: WeakRef=world_ref_value if world_ref_value is WeakRef else null
	var link_ref_value: Variant=profile_message_link_refs.get(stream_key,null)
	var link_ref: WeakRef=link_ref_value if link_ref_value is WeakRef else null
	var callback_value: Variant=profile_message_callbacks.get(stream_key,null)
	var callback: Callable=callback_value if callback_value is Callable else Callable()
	var world_value: Variant=world_ref.get_ref() if world_ref!=null and is_instance_valid(world_ref) else null
	var link_value: Variant=link_ref.get_ref() if link_ref!=null and is_instance_valid(link_ref) else null
	var before_value: Variant=baseline.get(stream_key,null)
	var current_value: Variant=profile_message_counts.get(stream_key,null)
	var server_profile: String=hub.profile_of(peer_id) if peer_found and is_instance_valid(hub) else ""
	var mapped_backend: Variant=hub.backend_of(peer_id) if peer_found and is_instance_valid(hub) else null
	var hub_connection_present: bool=peer_found and is_instance_valid(hub) and hub._connections.has(peer_id)
	var server_peer_is_member: bool=peer_found and live_server_peer(peer_id)
	var link_valid: bool=link_value is RefCounted and is_instance_valid(link_value)
	var world_valid: bool=world_value is Node and is_instance_valid(world_value)
	var ring_value: Variant=client_message_rings.get(stream_key,[])
	var profile_ring_value: Variant=profile_message_rings.get(stream_key,[])
	var hub_profile_matches_expected: bool=server_profile==profile_id
	var hub_backend_matches_expected: bool=is_instance_valid(mapped_backend) and is_instance_valid(expected_backend) and is_same(mapped_backend,expected_backend)
	var hub_owner_state_matches_expected: bool=(hub_connection_present and server_peer_is_member and hub_profile_matches_expected and hub_backend_matches_expected) if owner_expected else (not hub_connection_present and not server_peer_is_member)
	return {"stream":stream_key,"baseline":before_value if before_value is int else null,"current":current_value if current_value is int else null,"delta":current_value-before_value if current_value is int and before_value is int else null,"world_alive":world_valid,"world_id":world_value.get_instance_id() if world_valid else null,"link_alive":link_valid,"link_id":link_value.get_instance_id() if link_valid else null,"link_lifecycle":link_value.get("_lifecycle") if link_valid else null,"link_online":link_value.online if link_valid else null,"listener_is_connected":link_value.message.is_connected(callback) if link_valid and callback.is_valid() else false,"server_peer_found":peer_found,"server_peer_id":peer_id if peer_found else null,"server_peer_is_member":server_peer_is_member,"hub_connection_present":hub_connection_present,"hub_profile_matches_expected":hub_profile_matches_expected,"hub_backend_matches_expected":hub_backend_matches_expected,"hub_owner_expected_present":owner_expected,"hub_owner_state_matches_expected":hub_owner_state_matches_expected,"client_message_count":client_message_counts.get(stream_key,null),"message_ring":ring_value.duplicate(true) if ring_value is Array else [],"profile_ring":profile_ring_value.duplicate(true) if profile_ring_value is Array else []}

func _alice_bob_profile_event_diagnostic(baseline: Dictionary, backend_profile_baseline: int, gm_reply: Dictionary) -> Dictionary:
	var streams: Array=[]
	streams.append(_profile_event_route_evidence("alice_a1",baseline,account_a,a1_server_peer_id,a1_server_peer_id_found,alice_backend,false))
	streams.append(_profile_event_route_evidence("alice_a2",baseline,account_a,a2_reconnected_server_peer_id,a2_reconnected_server_peer_id_found,alice_backend,true))
	streams.append(_profile_event_route_evidence("bob_original",baseline,account_b,bob_server_peer_id,bob_server_peer_id_found,bob_backend,true))
	streams.append(_profile_event_route_evidence("bob_replacement",baseline,account_b,replacement_bob_server_peer_id,replacement_bob_server_peer_id_found,bob_backend,true))
	var backend_profile_current: int=alice_backend.profile_event_count if is_instance_valid(alice_backend) else -1
	var backend_profile_ring: Array=alice_backend.profile_event_ring.duplicate(true) if is_instance_valid(alice_backend) else []
	return {"streams":streams,"gm_reply":{"type":gm_reply.get("type",null) if gm_reply.get("type",null) is String else null,"ok":gm_reply.get("ok",null) if gm_reply.get("ok",null) is bool else null,"seq":gm_reply.get("seq",null) if gm_reply.get("seq",null) is int else null},"alice_backend_profile_event_baseline":backend_profile_baseline,"alice_backend_profile_event_current":backend_profile_current,"alice_backend_profile_event_delta":backend_profile_current-backend_profile_baseline if backend_profile_current>=0 else null,"alice_backend_profile_event_ring":backend_profile_ring,"alice_backend_rev":alice_backend.rev if is_instance_valid(alice_backend) else null,"bob_backend_rev":bob_backend.rev if is_instance_valid(bob_backend) else null}

func login_with_real_screen(world: Variant, name: String, pin: String) -> bool:
	if not await auth_wait(func():return is_instance_valid(world.login_screen) and world.login_screen.visible and world.link.awaiting_login,"%s reaches the actual PIN LoginScreen"%name):return false
	var screen: Variant = world.login_screen
	var choice: Variant = screen.find_child("Profile_"+name,true,false)
	if not check(choice is Button and choice.is_visible_in_tree() and not choice.disabled,"Actual login list contains the selected profile button for %s"%name):return false
	if not await auth_click(choice):return false
	screen.pin.text = pin # The real PIN field is filled before its actual Login button is clicked.
	if not check(screen.login_button is Button and not screen.login_button.disabled,"Actual LoginScreen enables the selected profile's PIN submission"):return false
	if not await auth_click(screen.login_button):return false # LoginScreen -> WsLink.login -> Hub PIN verifier.
	if not await auth_wait(func():return world.link.online and not world.data.is_empty() and not world.area_transition_busy,"Real PIN login completes and the backend-null scene receives its snapshot for %s"%name):return false
	if not check(world.backend==null and not world.link.is_local() and world.link.account.get("name",null)==name and not world.link.login_token.is_empty(),"%s is authenticated over the actual remote scene/link with a device token and no client Backend"%name):return false
	var projected_capability: Variant=world.state.capabilities.get("quest_loot_enabled",null)
	return check(projected_capability is bool and projected_capability and world.state.quest_loot_enabled(),"Same immutable test Backend getter projects a strict true capability to %s"%name)

func login_and_map_peer(world: Variant, name: String, pin: String, profile_id: String) -> Dictionary:
	var before: Array = hub.connections_of(profile_id).duplicate()
	if not await login_with_real_screen(world,name,pin):return {}
	return await wait_for_profile_peer(profile_id,before,world,hub.backends.get(profile_id,null),"Hub has one new actual server-side connection after %s PIN login"%name)

func auth_scene(port: int, tag: String, primary: bool) -> Variant:
	# Mirror the shipped GameScene remote construction path; set the URL before
	# instantiate because GameScene._init builds its WsLink there.
	GameScene.server_url_override="ws://127.0.0.1:%d"%port
	var packed_value: Variant=load("res://scenes/main.tscn")
	if not check(packed_value is PackedScene,"Main scene resource loads for %s"%tag):
		GameScene.server_url_override=""
		return null
	var packed: PackedScene=packed_value
	var created: Variant=packed.instantiate()
	GameScene.server_url_override=""
	if not check(is_instance_valid(created),"Packed main GameScene instantiates for %s"%tag):return null
	created.profile_persistence=false
	created.viewer_prefs_path="user://authenticated-%s-viewer.cfg"%tag
	created.visible=primary
	root.add_child(created)
	if primary:current_scene=created
	worlds.append(created)
	if tag=="a1":world_a=created;link_a=created.link
	elif tag=="a2":world_b=created;link_b=created.link
	else:world_c=created;link_c=created.link
	if is_instance_valid(pump):
		pump.links.clear()
		for owned_world in worlds:
			if is_instance_valid(owned_world):pump.links.append(owned_world.link)
	return created

func auth_profile_cache_disk_matches(backend: Variant, profile_path: String, label: String) -> bool:
	if not check(is_instance_valid(backend) and backend.session._valid_profile(backend.session._profile),"%s has a complete valid native profile before its oracle is captured"%label):return false
	var native_profile: Dictionary=backend.session._profile.duplicate(true)
	var payload_value: Variant=backend.last_saved_payload
	if not check(payload_value is String and not payload_value.is_empty(),"%s has a typed nonempty serialized cache"%label):return false
	var validated: Dictionary=ProfileCompare.validated_copy(backend.session,payload_value)
	var disk: Dictionary=backend._disk_set(profile_path)
	var primary: Variant=disk.get("primary",null)
	var backup: Variant=disk.get("backup",null)
	var temporary: Variant=disk.get("tmp",null)
	var primary_matches: bool=primary is Dictionary and primary.get("ok",null) is bool and primary.get("ok",false) and primary.get("bytes",null) is PackedByteArray and primary.bytes.get_string_from_utf8()==payload_value
	var backup_bytes: Variant=backup.get("bytes",null) if backup is Dictionary else null
	var backup_validation: Dictionary=ProfileCompare.validated_copy(backend.session,backup_bytes.get_string_from_utf8()) if backup is Dictionary and backup.get("exists",null) is bool and backup.exists and backup.get("ok",null) is bool and backup.ok and backup_bytes is PackedByteArray else {}
	var backup_valid: bool=backup is Dictionary and backup.get("exists",null) is bool and (not backup.exists or (backup.get("ok",null) is bool and backup.ok and backup_validation.get("ok",null) is bool and backup_validation.ok))
	var tmp_absent: bool=temporary is Dictionary and temporary.get("exists",null) is bool and not temporary.exists
	var normalized_native: Dictionary=backend.session._normalize_numbers(native_profile.duplicate(true))
	var full_profile_matches: bool=validated.get("ok",null) is bool and validated.ok and validated.get("profile",null) is Dictionary and validated.profile==normalized_native
	return check(primary_matches and backup_valid and tmp_absent and full_profile_matches,"%s native full profile, independent validator, exact cache/primary bytes, semantically valid existing backup and absent tmp agree"%label)

func normalized_client_profile_oracle(session: Variant, native_profile: Dictionary) -> Dictionary:
	var validated: Dictionary=ProfileCompare.validated_copy(session,JSON.stringify(native_profile))
	if not (validated.get("ok",null) is bool) or not validated.ok:return {}
	var profile_value: Variant=validated.get("profile",null)
	return profile_value if profile_value is Dictionary else {}

func _bounded_state_diff(before: Variant, after: Variant, path: String = "profile", max_depth: int = 6, max_nodes: int = 4096, max_rows: int = 24) -> Dictionary:
	var rows: Array = []
	var budget: Dictionary = {"visited":0,"max_nodes":max_nodes,"max_rows":max_rows,"truncated":false}
	_append_bounded_state_diff(before,after,path,rows,budget,0,max_depth)
	return {"rows":rows,"visited_nodes":budget.visited,"max_depth":max_depth,"max_nodes":max_nodes,"max_rows":max_rows,"truncated":budget.truncated}

func _append_bounded_state_diff(before: Variant, after: Variant, path: String, rows: Array, budget: Dictionary, depth: int, max_depth: int) -> void:
	if rows.size() >= int(budget.max_rows):
		budget.truncated = true
		return
	if int(budget.visited) >= int(budget.max_nodes):
		budget.truncated = true
		return
	budget.visited = int(budget.visited) + 1
	var before_type: int = typeof(before)
	var after_type: int = typeof(after)
	if before_type != after_type:
		rows.append({"path":path,"before_type":type_string(before_type),"after_type":type_string(after_type)})
		return
	if before is Dictionary and after is Dictionary:
		if depth >= max_depth:
			budget.truncated = true
			if rows.size() < int(budget.max_rows):rows.append({"path":path,"kind":"depth_limit","before_type":"Dictionary","after_type":"Dictionary"})
			return
		var key_index: int = 0
		for key in before:
			if int(budget.visited) >= int(budget.max_nodes):
				budget.truncated = true
				return
			budget.visited = int(budget.visited) + 1
			var child_path: String = path + ".<key:%s#%d>" % [type_string(typeof(key)),key_index]
			key_index += 1
			if before.has(key) and after.has(key):
				_append_bounded_state_diff(before[key],after[key],child_path,rows,budget,depth+1,max_depth)
			else:
				rows.append({"path":child_path,"before_type":type_string(typeof(before[key])),"after_type":"<missing>"})
			if rows.size() >= int(budget.max_rows):budget.truncated = true;return
		for key in after:
			if int(budget.visited) >= int(budget.max_nodes):
				budget.truncated = true
				return
			budget.visited = int(budget.visited) + 1
			if not before.has(key):
				var child_path: String = path + ".<key:%s#%d>" % [type_string(typeof(key)),key_index]
				rows.append({"path":child_path,"before_type":"<missing>","after_type":type_string(typeof(after[key]))})
			key_index += 1
			if rows.size() >= int(budget.max_rows):budget.truncated = true;return
		return
	if before is Array and after is Array:
		if depth >= max_depth:
			budget.truncated = true
			if rows.size() < int(budget.max_rows):rows.append({"path":path,"kind":"depth_limit","before_type":"Array","after_type":"Array"})
			return
		var limit: int = mini(maxi(before.size(),after.size()),int(budget.max_nodes)-int(budget.visited))
		for index in range(maxi(0,limit)):
			var child_path: String = path + "[" + str(index) + "]"
			if index < before.size() and index < after.size():
				_append_bounded_state_diff(before[index],after[index],child_path,rows,budget,depth+1,max_depth)
			elif index < before.size():
				rows.append({"path":child_path,"before_type":type_string(typeof(before[index])),"after_type":"<missing>"})
			else:
				rows.append({"path":child_path,"before_type":"<missing>","after_type":type_string(typeof(after[index]))})
			if rows.size() >= int(budget.max_rows):budget.truncated = true;return
		if maxi(before.size(),after.size()) > limit:budget.truncated = true
		return
	if before is bool or before is int or before is float or before is String or before is StringName or before_type == TYPE_NIL:
		if before != after:rows.append({"path":path,"before_type":type_string(before_type),"after_type":type_string(after_type)})
	else:
		rows.append({"path":path,"kind":"unsupported_value_uncompared","before_type":type_string(before_type),"after_type":type_string(after_type)})

func capture_bob_disk() -> Dictionary:
	return bob_backend._disk_set(bob_save_path) if is_instance_valid(bob_backend) else {}

func bob_is_unchanged() -> bool:
	if not is_instance_valid(bob_backend) or not is_instance_valid(bob_backend.session):return false
	var expected_serial: int=bob_backend.post_startup_serial if bob_backend.post_startup_baseline_ready else bob_serial_frozen
	return expected_serial>=0 and bob_backend.session._profile==bob_profile_frozen and bob_backend.last_saved_payload==bob_cache_frozen and bob_backend.quest_save_serial==expected_serial and capture_bob_disk()==bob_disk_frozen

func capture_auth_audit(outcome: String) -> Dictionary:
	var alice_now: Dictionary = alice_backend.session._profile.duplicate(true) if is_instance_valid(alice_backend) else {}
	var bob_now: Dictionary = bob_backend.session._profile.duplicate(true) if is_instance_valid(bob_backend) else {}
	var a1_world: Dictionary = snapshot_record(world_a) if is_instance_valid(world_a) else {}
	var a2_world: Dictionary = snapshot_record(world_b) if is_instance_valid(world_b) else {}
	var b_world: Dictionary = snapshot_record(world_c) if is_instance_valid(world_c) else {}
	var alice_writer_kinds: Dictionary = alice_backend._writer_kind_snapshot() if is_instance_valid(alice_backend) else {}
	var alice_checkpoint_summaries: Array = alice_backend._checkpoint_summary_from(0) if is_instance_valid(alice_backend) else []
	var alice_writer_reconciled: bool = alice_backend._writer_counts_reconcile() if is_instance_valid(alice_backend) else false
	var alice_checkpoint_reconciled: bool = alice_backend._checkpoint_count_reconciles() if is_instance_valid(alice_backend) else false
	var alice_checkpoint_records_valid: bool = alice_backend._checkpoint_records_valid_from(0) if is_instance_valid(alice_backend) else false
	return {"suite":"quest_auto_loot_authenticated_public_remote_ui_test","outcome":outcome,"first_failure":auth_failure,"claim":"three backend-null GameScenes; real ProfileHub PIN/token transport binding; one test-only idle E1/Stop; not natural route/battle/drop/P3/2760 proof","production_capability_constant":BackendScript.QUEST_LOOT_PUBLIC_ENABLED,"test_backend_getter":alice_backend._quest_loot_public_enabled() if is_instance_valid(alice_backend) else null,"accounts":{"alice_profile_id":account_a,"bob_profile_id":account_b,"a1_client_peer_id_found":a1_client_peer_id_found,"a2_client_peer_id_found":a2_client_peer_id_found,"bob_client_peer_id_found":bob_client_peer_id_found,"replacement_bob_client_peer_id_found":replacement_bob_client_peer_id_found,"a1_server_peer_id_found":a1_server_peer_id_found,"a2_server_peer_id_found":a2_server_peer_id_found,"bob_server_peer_id_found":bob_server_peer_id_found,"replacement_bob_server_peer_id_found":replacement_bob_server_peer_id_found,"a2_reconnected_server_peer_id_found":a2_reconnected_server_peer_id_found,"bob_client_peer_id":bob_client_peer_id,"replacement_bob_client_peer_id":replacement_bob_client_peer_id,"replacement_bob_server_peer_id":replacement_bob_server_peer_id if replacement_bob_server_peer_id_found else null,"a1_server_peer_id":a1_server_peer_id if a1_server_peer_id_found else null,"a2_server_peer_id":a2_server_peer_id if a2_server_peer_id_found else null,"bob_server_peer_id":bob_server_peer_id if bob_server_peer_id_found else null,"a2_reconnected_server_peer_id":a2_reconnected_server_peer_id if a2_reconnected_server_peer_id_found else null,"a1_token_revoked":not a1_token_before_logout.is_empty() and not hub.accounts.verify_token("AuthAlice",a1_token_before_logout).get("ok",false) if is_instance_valid(hub) else null,"a2_token_remains_valid":not a2_token_before_reconnect.is_empty() and hub.accounts.verify_token("AuthAlice",a2_token_before_reconnect).get("ok",false) if is_instance_valid(hub) else null},"peer_trace":auth_peer_trace.duplicate(true),"alice_full_profile":alice_now,"alice_cache":alice_backend.last_saved_payload if is_instance_valid(alice_backend) else "","alice_serial":alice_backend.quest_save_serial if is_instance_valid(alice_backend) else null,"alice_disk":alice_backend._disk_set(alice_save_path) if is_instance_valid(alice_backend) else {},"bob_full_profile":bob_now,"bob_cache":bob_backend.last_saved_payload if is_instance_valid(bob_backend) else "","bob_serial":bob_backend.quest_save_serial if is_instance_valid(bob_backend) else null,"bob_disk":capture_bob_disk(),"bob_frozen_profile":bob_profile_frozen,"bob_frozen_cache":bob_cache_frozen,"bob_frozen_serial":bob_serial_frozen,"bob_startup_noop_save_summary":bob_backend.startup_noop_summary.duplicate(true) if is_instance_valid(bob_backend) else {},"bob_post_startup_baseline_ready":bob_backend.post_startup_baseline_ready if is_instance_valid(bob_backend) else false,"bob_post_startup_serial":bob_backend.post_startup_serial if is_instance_valid(bob_backend) else null,"bob_post_startup_writer_total":bob_backend.post_startup_writer_total if is_instance_valid(bob_backend) else null,"bob_post_startup_save_kind_total":bob_backend.post_startup_save_kind_total if is_instance_valid(bob_backend) else null,"bob_post_startup_profile_event_total":bob_backend.post_startup_profile_event_total if is_instance_valid(bob_backend) else null,"bob_unchanged":bob_is_unchanged(),"client_profile_message_counts":profile_message_counts.duplicate(true),"client_profile_message_rings":profile_message_rings.duplicate(true),"client_message_counts":client_message_counts.duplicate(true),"client_message_rings":client_message_rings.duplicate(true),"client_event_phase_baselines":profile_event_phase_baselines.duplicate(true),"alice_start_records":alice_backend.start_records.duplicate(true) if is_instance_valid(alice_backend) else [],"alice_writer_records":alice_backend.writer_records.duplicate(true) if is_instance_valid(alice_backend) else [],"alice_writer_kind_counts":alice_writer_kinds,"alice_writer_counts_reconciled":alice_writer_reconciled,"alice_ordinary_save_callback_count":alice_checkpoint_summaries.size(),"alice_ordinary_save_callback_summaries":alice_checkpoint_summaries,"alice_ordinary_save_count_reconciled":alice_checkpoint_reconciled,"alice_ordinary_save_records_valid":alice_checkpoint_records_valid,"alice_checkpoint_overflow":alice_backend.ordinary_checkpoint_overflow if is_instance_valid(alice_backend) else null,"alice_profile_event_ring":alice_backend.profile_event_ring.duplicate(true) if is_instance_valid(alice_backend) else [],"snapshots":{"a1":a1_world,"a2":a2_world,"bob":b_world},"teardown":auth_teardown.duplicate(true)}

func authenticate_and_start_stop() -> bool:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i.ZERO
	root.gui_embed_subwindows=true
	if not check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(AUTH_ROOT)),"Dedicated authenticated account directory is fresh; no prior evidence is deleted"):return false
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUTH_ROOT))==OK and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(AUTH_ROOT)),"Dedicated account/evidence directory is created only after freshness checks"):return false
	for reserved_path in [AUTH_ACCOUNTS,AUDIT_PATH,"user://authenticated-a1-viewer.cfg","user://authenticated-a2-viewer.cfg","user://authenticated-bob-viewer.cfg"]:
		if not check(fresh(reserved_path),"Reserved account/evidence/viewer path is fresh: "+reserved_path):return false
	hub=AuthLootHub.new(AUTH_ACCOUNTS)
	hub.share_dir=""
	hub.tick=true
	root.add_child(hub)
	if not check(hub.start(),"Real ProfileHub loads a fresh isolated account database"):return false
	account_a=auth_account("AuthAlice","1111",true)
	if failures>0 or account_a.is_empty():return false
	account_b=auth_account("AuthBob","2222",false)
	if failures>0 or account_b.is_empty():return false
	alice_save_path=hub.accounts.save_path(hub.accounts.by_id(account_a))
	bob_save_path=hub.accounts.save_path(hub.accounts.by_id(account_b))
	alice_backend=hub.backends[account_a]
	bob_backend=hub.backends[account_b]
	if not check(alice_backend is AuthLootBackend and bob_backend is AuthLootBackend and not is_same(alice_backend,bob_backend) and alice_backend.admin and not bob_backend.admin and alice_save_path!=bob_save_path,"Hub factory owns distinct Alice-admin and Bob-ordinary profile backends with separate save paths while production constant remains false"):return false
	if not check(BackendScript.QUEST_LOOT_PUBLIC_ENABLED==false and alice_backend._quest_loot_public_enabled() and bob_backend._quest_loot_public_enabled(),"Only the test subclass's one immutable getter enables its snapshot and admission"):return false
	host=alice_backend
	server=HeldReplyServer.new(hub,0,"127.0.0.1")
	root.add_child(server)
	pump=LinkPump.new()
	root.add_child(pump)
	if not check(server.start()==OK and server.hub==hub and server.backend==null,"One real ProfileHub WebSocket server listens on ephemeral port 0"):return false
	var a1: Variant = auth_scene(server.port,"a1",true)
	if not is_instance_valid(a1):return false
	var a1_mapping: Dictionary=await login_and_map_peer(a1,"AuthAlice","1111",account_a)
	if failures>0:return false
	var a1_peer_value: Variant=a1_mapping.get("peer_id",null)
	if not check(a1_mapping.get("found",false) is bool and a1_mapping.found and a1_peer_value is int,"A1 actual Hub peer mapping is attributable after sequential real login"):return false
	a1_server_peer_id=int(a1_peer_value);a1_server_peer_id_found=true
	a1_server_peer_ref=capture_server_peer_ref(a1_server_peer_id)
	if not check(captured_server_peer_is_live(a1_server_peer_ref),"A1 mapped Hub ID resolves to the actual server-side WebSocketPeer"):return false
	server_peer_a_id=a1_server_peer_id;server_peer_a_id_found=true;server_peer_a_ref=a1_server_peer_ref;server_peer_a_ref_captured=true
	client_peer_a_id=a1.link._peer.get_instance_id()
	client_peer_a_id_found=true
	a1_client_peer_id_found=true
	a1_binding_ref=capture_binding_ref(a1_server_peer_id)
	binding_server_peer_a_ref=a1_binding_ref
	if not check(hub.backend_of(a1_server_peer_id)==alice_backend and binding_ref_is_current(alice_backend,a1_server_peer_id,a1_binding_ref),"A1's server-injected peer maps to Alice's exact Hub Backend and Hub-created fee binding"):return false
	record_peer_mapping("A1 PIN login",a1,a1_server_peer_id,account_a,alice_backend,a1_binding_ref)
	var a2: Variant = auth_scene(server.port,"a2",false)
	if not is_instance_valid(a2):return false
	a1.visible=false;a2.visible=true
	var a2_mapping: Dictionary=await login_and_map_peer(a2,"AuthAlice","1111",account_a)
	if failures>0:return false
	var a2_peer_value: Variant=a2_mapping.get("peer_id",null)
	if not check(a2_mapping.get("found",false) is bool and a2_mapping.found and a2_peer_value is int,"A2 actual Hub peer mapping is attributable independently of client peer IDs"):return false
	a2_server_peer_id=int(a2_peer_value);a2_server_peer_id_found=true
	a2_server_peer_ref=capture_server_peer_ref(a2_server_peer_id)
	if not check(captured_server_peer_is_live(a2_server_peer_ref),"A2 mapped Hub ID resolves to its distinct actual server peer"):return false
	server_peer_b_id=a2_server_peer_id;server_peer_b_id_found=true;server_peer_b_ref=a2_server_peer_ref
	client_peer_b_id=a2.link._peer.get_instance_id()
	client_peer_b_id_found=true
	a2_client_peer_id_found=true
	a2_binding_ref=capture_binding_ref(a2_server_peer_id)
	binding_server_peer_b_ref=a2_binding_ref
	var a1_binding_value: Variant=a1_binding_ref.get_ref() if a1_binding_ref!=null and is_instance_valid(a1_binding_ref) else null
	var a2_binding_value: Variant=a2_binding_ref.get_ref() if a2_binding_ref!=null and is_instance_valid(a2_binding_ref) else null
	var distinct_bindings: bool=a1_server_peer_id!=a2_server_peer_id and hub.backend_of(a2_server_peer_id)==alice_backend and binding_ref_is_current(alice_backend,a2_server_peer_id,a2_binding_ref) and a1_binding_value is RefCounted and is_instance_valid(a1_binding_value) and a2_binding_value is RefCounted and is_instance_valid(a2_binding_value) and not is_same(a1_binding_value,a2_binding_value)
	a1_binding_value=null;a2_binding_value=null # Do not keep retired connection epochs alive across later awaits.
	if not check(distinct_bindings,"A1/A2 use distinct actual server peers and distinct current Hub-created bindings over one shared Alice Backend"):return false
	record_peer_mapping("A2 PIN login",a2,a2_server_peer_id,account_a,alice_backend,a2_binding_ref)
	a2.visible=false;a1.visible=true
	var bob: Variant = auth_scene(server.port,"bob",false)
	if not is_instance_valid(bob):return false
	a1.visible=false;bob.visible=true
	var bob_mapping: Dictionary=await login_and_map_peer(bob,"AuthBob","2222",account_b)
	if failures>0:return false
	var bob_peer_value: Variant=bob_mapping.get("peer_id",null)
	if not check(bob_mapping.get("found",false) is bool and bob_mapping.found and bob_peer_value is int,"Bob actual Hub peer mapping is attributable independently of A peers"):return false
	bob_server_peer_id=int(bob_peer_value);bob_server_peer_id_found=true
	bob.visible=false;a1.visible=true
	bob_server_peer_ref=capture_server_peer_ref(bob_server_peer_id)
	if not check(captured_server_peer_is_live(bob_server_peer_ref),"Bob mapped Hub ID resolves to an actual server peer"):return false
	bob_binding_ref=capture_auth_binding_ref(bob_backend,bob_server_peer_id)
	if not check(hub.backend_of(bob_server_peer_id)==bob_backend and bob_binding_ref!=null and binding_ref_is_current(bob_backend,bob_server_peer_id,bob_binding_ref),"Bob is independently mapped to his own Hub Backend and real current connection binding"):return false
	bob_client_peer_id=bob.link._peer.get_instance_id() if is_instance_valid(bob.link._peer) else null
	bob_client_peer_id_found=bob_client_peer_id is int
	record_peer_mapping("Bob PIN login",bob,bob_server_peer_id,account_b,bob_backend,bob_binding_ref)
	if not check(a1.backend==null and a2.backend==null and bob.backend==null and not is_same(alice_backend,bob_backend),"All three authenticated client scenes remain backend-null and account Backend ownership is isolated"):return false
	for world in [a1,a2,bob]:
		if not check(await Wait.settle(self,world),"Actual authenticated scene startup round trip settles before the frozen baseline"):return false
	if not auth_profile_cache_disk_matches(alice_backend,alice_save_path,"Alice after real PIN login and scene initialization"):return false
	if not auth_profile_cache_disk_matches(bob_backend,bob_save_path,"Bob after real PIN login and scene initialization"):return false
	bob_profile_frozen=bob_backend.session._profile.duplicate(true)
	var alice_login_native: Dictionary=alice_backend.session._profile.duplicate(true)
	var bob_login_native: Dictionary=bob_backend.session._profile.duplicate(true)
	var alice_login_profile: Dictionary=normalized_client_profile_oracle(alice_backend.session,alice_login_native)
	var bob_login_profile: Dictionary=normalized_client_profile_oracle(bob_backend.session,bob_login_native)
	if not check(not alice_login_profile.is_empty() and not bob_login_profile.is_empty() and a1.state.full_profile()==alice_login_profile and a2.state.full_profile()==alice_login_profile and bob.state.full_profile()==bob_login_profile and not bob_backend.session._profile.original_items.has(2764),"All three real login snapshots match independently validated/normalized complete native profiles; Bob has no Alice eligibility item"):return false
	bob_cache_frozen=bob_backend.last_saved_payload
	bob_serial_frozen=bob_backend.quest_save_serial
	bob_disk_frozen=capture_bob_disk()
	if not check(bob_disk_frozen.primary.get("ok",false) and bob_disk_frozen.primary.bytes.get_string_from_utf8()==bob_cache_frozen,"Bob's full native/cache/primary baseline is internally consistent before Alice acts"):return false
	tap_profile_messages(a1,"alice_a1")
	tap_profile_messages(a2,"alice_a2")
	tap_profile_messages(bob,"bob_original")
	if not await Wait.settle(self,a1):return check(false,"A1's authenticated startup stream settles before E1")
	if not await Wait.settle(self,a2):return check(false,"A2's authenticated startup stream settles before E1")
	if not await Wait.settle(self,bob):return check(false,"Bob's authenticated startup stream settles before E1")
	var e1_event_baseline: Dictionary=capture_profile_event_baseline("before_alice_e1")
	frozen_before=alice_backend.session._profile.duplicate(true)
	pre_game_profile=frozen_before.duplicate(true)
	if not check(alice_backend.session._valid_profile(frozen_before) and LootState.valid(frozen_before.get("quest_loot",null)) and frozen_before.quest_loot==LootState.empty(),"Alice E1 oracle freezes the fully initialized native profile with an empty valid ledger"):return false
	if not check(frozen_before.original_items.has(2764) and not frozen_before.original_items.has(2760) and frozen_before.location=={"map_id":100,"x":source_cell.x,"y":source_cell.y},"Alice has only the audited direct eligibility fixture and the actual saved source location"):return false
	var plan: Dictionary=JewelPlan.select(alice_backend,Sources.matches_backend)
	if not check(plan.get("status",null)=="step" and Sources.same(plan.get("step",{}),Sources.step()),"Source plan accepts only the actual original server-side test fixture"):return false
	source_step=plan.step.duplicate(true)
	if not check(captured_server_peer_is_live(a1_server_peer_ref) and captured_server_peer_is_live(a2_server_peer_ref) and hub.profile_of(a1_server_peer_id)==account_a and hub.profile_of(a2_server_peer_id)==account_a,"Both real server peers are still authenticated to Alice before start"):return false
	if not check(alice_backend._fee_bindings.has(a1_server_peer_id) and alice_backend._fee_bindings.has(a2_server_peer_id) and bob_backend._fee_bindings.has(bob_server_peer_id),"Actual per-profile Backend binding maps contain the server-side IDs installed by Hub login"):return false
	alice_backend.event.connect(alice_backend.observe_event)
	alice_backend.reply_server_ref=weakref(server)
	alice_backend.observe=true
	auth_writer_baseline_before_e1=alice_backend.writer_event_count
	auth_writer_records_baseline_before_e1=alice_backend.writer_records.size()
	if not check(alice_backend.start_event_count==0 and auth_writer_baseline_before_e1==0,"Bounded passive observer starts only after all three authentications and frozen baselines"):return false
	a1.quest_helper_menu.open_menu()
	if not await auth_wait(func():
		var candidate: Variant=a1.quest_helper_menu.find_child("QuestLootStart",true,false)
		return candidate is Button and not candidate.disabled,
		"A1's real public start control reflects the test-only immutable capability"):return false
	a1.visible=true;a2.visible=false;bob.visible=false
	var start_button: Button=a1.quest_helper_menu.find_child("QuestLootStart",true,false)
	if not await auth_click(start_button):return false
	if not await auth_wait(func():return not server.held_reply.is_empty(),"Actual persisted E1 ACK is held only at the real WsServer send boundary"):return false
	if not check(server.held_reply.get("reply",null) is bool and server.held_reply.reply and server.held_reply.get("type",null)=="ack" and server.held_reply.get("ok",null) is bool and server.held_reply.ok and server.held_reply.get("persisted",null) is bool and server.held_reply.persisted and server.held_reply.get("seq",null) is int,"Held item is the real final wire ACK with server envelope, generated seq and durable result"):return false
	if not check(alice_backend.start_event_count==1 and alice_backend.start_records.size()==1 and alice_backend.start_records[0].type=="quest_loot_start","One actual A1 button dispatch reaches one Hub-routed Backend handler call"):return false
	var start_record: Dictionary=alice_backend.start_records[0]
	if not check(start_record.server_peer_id==a1_server_peer_id and start_record.binding_current and start_record.binding_evidence.same_object and start_record.seq is int and start_record.seq==server.held_reply.seq,"E1 is attributed to A1's actual server peer/current weakly captured Hub binding and transport sequence"):return false
	if not check(start_record.keys.size()==3 and start_record.keys.has("type") and start_record.keys.has("seq") and start_record.keys.has("_quest_connection") and not start_record.keys.has("_fee_binding"),"Hub strips client binding data and injects only the trusted server-side connection into the type+seq command"):return false
	if not check(start_record.handler_result.get("ok",null) is bool and start_record.handler_result.ok and start_record.handler_result.get("persisted",null) is bool and start_record.handler_result.persisted and start_record.handler_result.get("type",null)=="ack" and not start_record.handler_result.has("reply") and server.held_reply.get("run_identity",null)==start_record.handler_result.get("run_identity",null) and server.held_reply.get("budget_identity",null)==start_record.handler_result.get("budget_identity",null),"Raw Hub/Backend ACK and final wire envelope preserve the actual returned run/budget identities at distinct layers"):return false
	if not check(alice_backend.observation_error.is_empty() and server.hold_error.is_empty(),"Writer, event and ACK observers have no diagnostic latch"):return false
	var actual_ack: Dictionary=server.held_reply.duplicate(true)
	var e1_candidates: Array=expected_e1_profiles(actual_ack)
	if not check(e1_candidates.size()==2 and check_e1_writer_chain(e1_candidates),"Independent acquire/open oracle matches the two durable full-profile E1 commits, cache and primary/backup chain"):return false
	var run_identity: Dictionary=actual_ack.run_identity
	var budget_identity: Dictionary=actual_ack.budget_identity
	var open_entry: Dictionary=public_entry_dto_from_expected(e1_candidates[1].quest_loot.entries[STEP])
	if not check(not open_entry.is_empty(),"The independently derived native ledger maps to the frozen public DTO without reading either client's snapshot"):return false
	projection_used_watermarks={"a1":open_entry.saved_used_ms,"a2":open_entry.saved_used_ms}
	if not await auth_wait(func():return real_open_projection(a1,"a1",run_identity.run_id,run_identity.revision,budget_identity.budget_id,budget_identity.generation,open_entry) and real_open_projection(a2,"a2",run_identity.run_id,run_identity.revision,budget_identity.budget_id,budget_identity.generation,open_entry),"Both Alice backend-null devices consume the same actual opened E1 identity and independent DTO"):return false
	if not await Wait.settle(self,a2):return check(false,"A2's authenticated stream drains Alice's E1 event")
	if not await Wait.settle(self,bob):return check(false,"Bob's authenticated stream drains its account-scoped queue")
	if not check(profile_event_delta(e1_event_baseline,"alice_a1")>0 and profile_event_delta(e1_event_baseline,"alice_a2")>0 and profile_event_delta(e1_event_baseline,"bob_original")==0,"E1 profile-event counters advance on both Alice streams and remain unchanged on Bob"):return false
	if not check(bob_is_unchanged() and entry_on(bob).is_empty(),"Alice E1 leaves Bob's complete native profile, cache, serial, primary/backup/tmp and public entry unchanged"):return false
	if not check(await server.release_actual_reply() and server.release_count==1,"The actual durable E1 ACK is released once after independent writer/profile/DTO checks"):return false
	var actual_start_seq: int=start_record.seq
	if not await auth_wait(func():
		var travel: Variant=a1.quest_helper_travel
		return not link_a._callbacks.has(actual_start_seq) and not travel.loot_start_pending and not travel.loot_snapshot_pending and not travel.loot_start_waiting_snapshot,
		"A1's real callback consumes the matching ACK and retires only its completed start wait"):return false
	if not await Wait.settle(self,a1):return check(false,"A1's stream drains the released E1 ACK")
	if not check(alice_backend.session._profile==e1_candidates[1] and bob_is_unchanged(),"Delivering the real ACK changes neither the durable Alice candidate nor Bob"):return false
	var current_start: Variant=a1.quest_helper_menu.find_child("QuestLootStart",true,false)
	if not await auth_wait(func():return current_start is Button and current_start.disabled and a1.quest_helper_menu.last_model==a1.quest_helper_menu.refresh_key(),"A1's normal menu refresh disables the real start control after E1"):return false
	var duplicate_start_count: int=alice_backend.start_event_count
	if not await auth_click(current_start):return false
	if not check(alice_backend.start_event_count==duplicate_start_count,"Physical second press on the disabled A1 control dispatches no duplicate start"):return false
	var alice_before_a2_duplicate: Dictionary=alice_backend.session._profile.duplicate(true)
	var alice_cache_before_a2_duplicate: String=alice_backend.last_saved_payload
	var alice_serial_before_a2_duplicate: int=alice_backend.quest_save_serial
	var alice_disk_before_a2_duplicate: Dictionary=alice_backend._disk_set(alice_save_path)
	var pre_duplicate_writer_count: int = alice_backend.writer_event_count
	var pre_duplicate_writer_record_count: int = alice_backend.writer_records.size()
	var pre_duplicate_writer_kinds: Dictionary = alice_backend._writer_kind_snapshot()
	var pre_duplicate_settlement_eq_two: bool = pre_duplicate_writer_kinds.get("loot_settlement_written",null) is int and pre_duplicate_writer_kinds.loot_settlement_written==2
	var pre_duplicate_records_eq_two: bool = pre_duplicate_writer_record_count == 2
	var pre_duplicate_checkpoints_valid: bool = alice_backend._checkpoint_records_valid_from(0)
	var pre_duplicate_writer_counts_reconcile: bool = alice_backend._writer_counts_reconcile() and alice_backend._checkpoint_count_reconciles()
	var pre_duplicate_handler_boundaries: Array = alice_backend.handler_writer_boundaries.duplicate(true)
	var pre_duplicate_e1_boundary_match: Dictionary = _matching_handler_boundary(pre_duplicate_handler_boundaries,start_record.get("seq",null),start_record.get("type",null))
	var pre_duplicate_e1_boundary: Dictionary = pre_duplicate_e1_boundary_match.get("boundary",{}) if pre_duplicate_e1_boundary_match.get("boundary",{}) is Dictionary else {}
	var pre_duplicate_writer_ring: Array = _writer_event_ring_diagnostic(alice_backend.writer_event_ring)
	var pre_duplicate_writer_diagnostic: Dictionary = {
		"writer_event_count":pre_duplicate_writer_count,
		"writer_records_size":pre_duplicate_writer_record_count,
		"writer_kind_counts":pre_duplicate_writer_kinds,
		"settlement_records_size_eq_2":pre_duplicate_records_eq_two,
		"settlement_kind_eq_2":pre_duplicate_settlement_eq_two,
		"writer_counts_reconcile":pre_duplicate_writer_counts_reconcile,
		"ordinary_checkpoint_callbacks":alice_backend._checkpoint_summary_from(0),
		"ordinary_checkpoint_callbacks_all_valid":pre_duplicate_checkpoints_valid,
		"writer_event_baseline_before_e1":auth_writer_baseline_before_e1,
		"writer_event_delta_from_pre_e1":pre_duplicate_writer_count-auth_writer_baseline_before_e1 if auth_writer_baseline_before_e1 >= 0 else null,
		"writer_records_baseline_before_e1":auth_writer_records_baseline_before_e1,
		"writer_records_delta_from_pre_e1":pre_duplicate_writer_record_count-auth_writer_records_baseline_before_e1 if auth_writer_records_baseline_before_e1 >= 0 else null,
		"frame":Engine.get_process_frames(),
		"backend_revision":alice_backend.rev,
		"quest_save_serial":alice_backend.quest_save_serial,
		"profile_event_count":alice_backend.profile_event_count,
		"normal_process_generation":alice_backend._normal_process_generation,
		"quest_auto_running":alice_backend.quest_auto.running,
		"quest_auto_phase":alice_backend.quest_auto.phase,
		"initial_e2_active":not alice_backend.quest_loot.initial_e2.is_empty(),
		"e1_handler_boundary_unique":pre_duplicate_e1_boundary_match.get("unique",false),
		"e1_handler_boundary_match_count":pre_duplicate_e1_boundary_match.get("match_count",0),
		"e1_handler_boundary":pre_duplicate_e1_boundary,
		"writer_count_after_e1_handler":pre_duplicate_e1_boundary.get("writer_count_after",null),
		"writer_events_after_e1_handler":pre_duplicate_writer_count-pre_duplicate_e1_boundary.writer_count_after if pre_duplicate_e1_boundary.get("writer_count_after",null) is int else null,
		"writer_records_after_e1_handler":pre_duplicate_writer_record_count-pre_duplicate_e1_boundary.writer_records_after if pre_duplicate_e1_boundary.get("writer_records_after",null) is int else null,
		"writer_event_ring_tail":pre_duplicate_writer_ring
	}
	print("AUTH_PUBLIC_LOOT_PRE_DUPLICATE_WRITER_DIAGNOSTIC ",JSON.stringify(pre_duplicate_writer_diagnostic))
	if not check(pre_duplicate_settlement_eq_two and pre_duplicate_records_eq_two and pre_duplicate_checkpoints_valid and pre_duplicate_writer_counts_reconcile,"Exactly two E1 settlement callbacks remain; every ordinary Hub checkpoint callback is independently proven same-payload/no-disk-change") :return false
	var writer_count_before_duplicate_rpc: int=alice_backend.writer_event_count
	var writer_records_before_duplicate_rpc: int=alice_backend.writer_records.size()
	var writer_kinds_before_duplicate_rpc: Dictionary=alice_backend._writer_kind_snapshot()
	var checkpoint_count_before_duplicate_rpc: int=alice_backend.ordinary_checkpoint_records.size()
	var profile_events_before_duplicate_rpc: int=alice_backend.profile_event_count
	var duplicate_frame_before_rpc: int=Engine.get_process_frames()
	var duplicate_reply: Dictionary=await auth_rpc(link_b,{"type":"quest_loot_start"})
	var duplicate_frame_after_rpc: int=Engine.get_process_frames()
	if not check(not duplicate_reply.get("ok",true) and duplicate_reply.get("persisted",null) is bool and not duplicate_reply.persisted and duplicate_reply.get("type",null)=="rejected" and duplicate_reply.get("seq",null) is int,"A2's actual authenticated duplicate start is refused without manufacturing a successful reply"):return false
	if not check(alice_backend.start_event_count==duplicate_start_count+1 and alice_backend.start_records.size()==alice_backend.start_event_count,"The authenticated A2 duplicate is exactly one additional real handler call"):return false
	var duplicate_record: Dictionary=alice_backend.start_records.back()
	if not check(duplicate_record.server_peer_id==a2_server_peer_id and duplicate_record.binding_current and duplicate_record.binding_evidence.same_object and duplicate_record.handler_result.get("persisted",null) is bool and not duplicate_record.handler_result.persisted,"Duplicate refusal is attributed to A2's own current Hub binding"):return false
	var duplicate_boundary_match: Dictionary=_matching_handler_boundary(alice_backend.handler_writer_boundaries,duplicate_record.get("seq",null),duplicate_record.get("type",null))
	var duplicate_boundary: Dictionary=duplicate_boundary_match.get("boundary",{}) if duplicate_boundary_match.get("boundary",{}) is Dictionary else {}
	var alice_disk_after_a2_duplicate: Dictionary=alice_backend._disk_set(alice_save_path)
	var handler_writer_before: Variant=duplicate_boundary.get("writer_count_before",null)
	var handler_writer_after: Variant=duplicate_boundary.get("writer_count_after",null)
	var handler_record_count_before: Variant=duplicate_boundary.get("writer_records_before",null)
	var handler_record_count_after: Variant=duplicate_boundary.get("writer_records_after",null)
	var handler_writer_interval_unchanged: bool=duplicate_boundary_match.get("unique",false) is bool and duplicate_boundary_match.unique and duplicate_boundary.get("seq",null) is int and duplicate_record.get("seq",null) is int and duplicate_reply.get("seq",null) is int and duplicate_boundary.seq==duplicate_record.seq and duplicate_record.seq==duplicate_reply.seq and duplicate_boundary.get("type",null) is String and duplicate_record.get("type",null) is String and duplicate_boundary.type==duplicate_record.type and duplicate_boundary.type=="quest_loot_start" and handler_writer_before is int and handler_writer_after is int and handler_record_count_before is int and handler_record_count_after is int and handler_writer_after==handler_writer_before and handler_record_count_after==handler_record_count_before and duplicate_boundary.get("writer_kinds_before",null) is Dictionary and duplicate_boundary.get("writer_kinds_after",null) is Dictionary and duplicate_boundary.writer_kinds_before==duplicate_boundary.writer_kinds_after
	var handler_profile_unchanged: bool=duplicate_record.before.profile==duplicate_record.after_profile
	var handler_cache_unchanged: bool=duplicate_record.before.cache==duplicate_record.after_cache
	var handler_serial_unchanged: bool=duplicate_record.before.serial==duplicate_record.after_serial
	var handler_disk_unchanged: bool=duplicate_record.before.disk==duplicate_record.after_disk
	var await_profile_unchanged: bool=alice_backend.session._profile==alice_before_a2_duplicate
	var await_cache_unchanged: bool=alice_backend.last_saved_payload==alice_cache_before_a2_duplicate
	var await_serial_unchanged: bool=alice_backend.quest_save_serial==alice_serial_before_a2_duplicate
	var await_disk_unchanged: bool=alice_disk_after_a2_duplicate==alice_disk_before_a2_duplicate
	var writer_kinds_after_duplicate_rpc: Dictionary=alice_backend._writer_kind_snapshot()
	var new_checkpoint_count: int=alice_backend.ordinary_checkpoint_records.size()-checkpoint_count_before_duplicate_rpc
	var duplicate_settlement_unchanged: bool=writer_kinds_after_duplicate_rpc.get("loot_settlement_written",null) is int and writer_kinds_before_duplicate_rpc.get("loot_settlement_written",null) is int and writer_kinds_after_duplicate_rpc.loot_settlement_written==writer_kinds_before_duplicate_rpc.loot_settlement_written
	var duplicate_checkpoint_delta_matches: bool=new_checkpoint_count>=0 and writer_kinds_after_duplicate_rpc.get("save_profile_boundary",null) is int and writer_kinds_before_duplicate_rpc.get("save_profile_boundary",null) is int and writer_kinds_after_duplicate_rpc.save_profile_boundary-writer_kinds_before_duplicate_rpc.save_profile_boundary==new_checkpoint_count and alice_backend._checkpoint_count_reconciles() and alice_backend._checkpoint_records_valid_from(checkpoint_count_before_duplicate_rpc)
	var duplicate_writer_delta_reconciles: bool=alice_backend._writer_counts_reconcile() and alice_backend.writer_event_count-writer_count_before_duplicate_rpc==new_checkpoint_count
	var await_serial_matches_validated_checkpoints: bool=alice_backend.quest_save_serial==alice_serial_before_a2_duplicate+new_checkpoint_count
	var duplicate_no_write: bool=handler_writer_interval_unchanged and handler_profile_unchanged and handler_cache_unchanged and handler_serial_unchanged and handler_disk_unchanged and duplicate_settlement_unchanged and duplicate_checkpoint_delta_matches and duplicate_writer_delta_reconciles and await_profile_unchanged and await_cache_unchanged and await_serial_matches_validated_checkpoints and await_disk_unchanged
	if not duplicate_no_write:
		print("AUTH_PUBLIC_LOOT_DUPLICATE_BOUNDARY_DIAGNOSTIC ",JSON.stringify({"e1_expected_writer_count_at_chain":2,"writer_count_before_duplicate_await":writer_count_before_duplicate_rpc,"writer_records_before_duplicate_await":writer_records_before_duplicate_rpc,"profile_events_before_duplicate_await":profile_events_before_duplicate_rpc,"profile_events_after_await":alice_backend.profile_event_count,"profile_event_delta":alice_backend.profile_event_count-profile_events_before_duplicate_rpc,"backend_revision_at_handler":duplicate_record.get("backend_revision",null),"backend_revision_after_await":alice_backend.rev,"frame_before_rpc":duplicate_frame_before_rpc,"frame_after_rpc":duplicate_frame_after_rpc,"frame_delta":duplicate_frame_after_rpc-duplicate_frame_before_rpc,"writer_count_after_await":alice_backend.writer_event_count,"writer_records_after_await":alice_backend.writer_records.size(),"handler_boundary_unique_match":duplicate_boundary_match.get("unique",false),"handler_boundary_match_count":duplicate_boundary_match.get("match_count",0),"handler_boundary_seq_type_candidates":_handler_boundary_index_diagnostic(alice_backend.handler_writer_boundaries),"duplicate_reply_seq":duplicate_reply.get("seq",null),"duplicate_request_seq":duplicate_record.get("seq",null),"duplicate_request_type":duplicate_record.get("type",null),"handler_writer_boundary":duplicate_boundary,"writer_delta_before_handler":handler_writer_before-writer_count_before_duplicate_rpc if handler_writer_before is int else null,"writer_records_delta_before_handler":handler_record_count_before-writer_records_before_duplicate_rpc if handler_record_count_before is int else null,"handler_frame_before":duplicate_boundary.get("frame_before",null),"handler_frame_after":duplicate_boundary.get("frame_after",null),"handler_writer_interval_unchanged":handler_writer_interval_unchanged,"writer_kind_counts_before":writer_kinds_before_duplicate_rpc,"writer_kind_counts_after":writer_kinds_after_duplicate_rpc,"duplicate_settlement_unchanged":duplicate_settlement_unchanged,"new_checkpoint_count":new_checkpoint_count,"new_checkpoint_records":alice_backend._checkpoint_summary_from(checkpoint_count_before_duplicate_rpc),"new_checkpoints_valid":duplicate_checkpoint_delta_matches,"writer_delta_reconciles":duplicate_writer_delta_reconciles,"await_serial_matches_validated_checkpoints":await_serial_matches_validated_checkpoints,"handler_profile_unchanged":handler_profile_unchanged,"handler_profile_diff_paths_types":_bounded_profile_diff(duplicate_record.before.get("profile",{}),duplicate_record.get("after_profile",{})),"handler_cache_unchanged":handler_cache_unchanged,"handler_cache_before_bytes":duplicate_record.before.get("cache","").to_utf8_buffer().size() if duplicate_record.before.get("cache","") is String else null,"handler_cache_after_bytes":duplicate_record.get("after_cache","").to_utf8_buffer().size() if duplicate_record.get("after_cache","") is String else null,"handler_serial_unchanged":handler_serial_unchanged,"handler_serial_before":duplicate_record.before.get("serial",null),"handler_serial_after":duplicate_record.get("after_serial",null),"handler_disk_unchanged":handler_disk_unchanged,"handler_disk_slots":_disk_slots_evidence(duplicate_record.before.get("disk",{}),duplicate_record.get("after_disk",{})),"await_profile_unchanged":await_profile_unchanged,"await_profile_diff_paths_types":_bounded_profile_diff(alice_before_a2_duplicate,alice_backend.session._profile),"await_cache_unchanged":await_cache_unchanged,"await_cache_before_bytes":alice_cache_before_a2_duplicate.to_utf8_buffer().size(),"await_cache_after_bytes":alice_backend.last_saved_payload.to_utf8_buffer().size(),"await_serial_unchanged_without_checkpoint_allowance":await_serial_unchanged,"await_serial_before":alice_serial_before_a2_duplicate,"await_serial_after":alice_backend.quest_save_serial,"await_disk_unchanged":await_disk_unchanged,"await_disk_slots":_disk_slots_evidence(alice_disk_before_a2_duplicate,alice_disk_after_a2_duplicate),"writer_records_tail":_writer_record_diagnostic(alice_backend.writer_records),"writer_event_ring_tail":_writer_event_ring_diagnostic(alice_backend.writer_event_ring)}))
	if not check(duplicate_settlement_unchanged and alice_backend.writer_records.size()==2 and duplicate_checkpoint_delta_matches and duplicate_writer_delta_reconciles,"Duplicate RPC has no new settlement; only fully validated same-payload Hub checkpoints may advance the test-local callback/serial totals"):return false
	if not check(duplicate_no_write,"A2 duplicate performs no native/cache/serial/primary/backup/tmp writer mutation"):return false
	if not check(alice_backend.is_processing() and not alice_backend.battle_open and alice_backend.session._pending.is_empty(),"Idle encounter fixture keeps real Backend processing but reaches generic Stop without a battle or receipt"):return false
	var profile_events_before_stop: int=alice_backend.profile_event_count
	var writer_count_before_stop: int=alice_backend.writer_event_count
	var writer_records_before_stop: int=alice_backend.writer_records.size()
	auth_writer_count_before_stop=writer_count_before_stop
	auth_writer_records_before_stop=writer_records_before_stop
	auth_writer_kinds_before_stop=alice_backend._writer_kind_snapshot()
	var stop_frame_before_click: int=Engine.get_process_frames()
	var stop_event_baseline: Dictionary=capture_profile_event_baseline("before_alice_stop")
	a1.visible=false;a2.visible=true;bob.visible=false
	a2.quest_helper_menu.open_menu()
	if not await auth_wait(func():
		var stop: Variant=a2.quest_helper_menu.find_child("QuestAutoStop",true,false)
		return stop is Button and not stop.disabled,
		"A2 sees the original generic Stop control for Alice's authoritative run"):return false
	if not await auth_click(a2.quest_helper_menu.find_child("QuestAutoStop",true,false)):return false
	if not await auth_wait(func():
		var native_ledger: Variant=alice_backend.session._profile.get("quest_loot",null)
		var entries: Dictionary=native_ledger.get("entries",{}) if native_ledger is Dictionary else {}
		var entry: Variant=entries.get(STEP,null)
		return not alice_backend.quest_auto.running and entry is Dictionary and not entry.get("open_span",true) and alice_backend.session._pending.is_empty() and not alice_backend.battle_open,
		"The real generic Stop closes the same idle E1 through its original transaction"):return false
	var stop_writer_count_after_wait: int=alice_backend.writer_event_count
	var stop_writer_records_after_wait: int=alice_backend.writer_records.size()
	var stop_frame_after_wait: int=Engine.get_process_frames()
	var stop_kind_counts_after_wait: Dictionary=alice_backend._writer_kind_snapshot()
	var stop_settlement_exact: bool=stop_kind_counts_after_wait.get("loot_settlement_written",null) is int and stop_kind_counts_after_wait.loot_settlement_written==3 and stop_writer_records_after_wait==3
	var stop_checkpoint_chain_valid: bool=alice_backend._checkpoint_records_valid_from(0)
	var stop_counts_reconcile: bool=alice_backend._writer_counts_reconcile() and alice_backend._checkpoint_count_reconciles()
	if not (stop_settlement_exact and stop_checkpoint_chain_valid and stop_counts_reconcile):
		print("AUTH_PUBLIC_LOOT_STOP_WRITER_DIAGNOSTIC ",JSON.stringify({"e1_writer_count":2,"writer_count_before_stop":writer_count_before_stop,"writer_records_before_stop":writer_records_before_stop,"writer_count_after_stop_wait":stop_writer_count_after_wait,"writer_count_delta":stop_writer_count_after_wait-writer_count_before_stop,"writer_records_after_stop_wait":stop_writer_records_after_wait,"writer_records_delta":stop_writer_records_after_wait-writer_records_before_stop,"profile_event_count_before_stop":profile_events_before_stop,"profile_event_count_after_stop_wait":alice_backend.profile_event_count,"frame_before_stop_click":stop_frame_before_click,"frame_after_stop_wait":stop_frame_after_wait,"frame_delta":stop_frame_after_wait-stop_frame_before_click,"stop_handler_boundary":alice_backend.handler_stop_boundaries.back() if not alice_backend.handler_stop_boundaries.is_empty() else {},"observation_error_present":not alice_backend.observation_error.is_empty(),"writer_kind_counts":stop_kind_counts_after_wait,"ordinary_checkpoint_records":alice_backend._checkpoint_summary_from(0),"ordinary_checkpoint_records_all_valid":stop_checkpoint_chain_valid,"ordinary_checkpoint_count_reconciles":alice_backend._checkpoint_count_reconciles(),"writer_counts_reconcile":stop_counts_reconcile,"writer_records_tail":_writer_record_diagnostic(alice_backend.writer_records),"writer_event_ring_tail":_writer_event_ring_diagnostic(alice_backend.writer_event_ring)}))
	if not check(stop_settlement_exact and stop_checkpoint_chain_valid and stop_counts_reconcile,"Explicit idle fixture observed two E1 and one Stop settlement callback; ordinary Hub save callbacks are separately validated"):return false
	var closed_candidate: Dictionary=independently_closed_candidate(e1_candidates[1],alice_backend.writer_records[2])
	if not check(not closed_candidate.is_empty(),"Closed full-profile and DTO oracle comes from independent State.progress plus the actual captured stop sample"):return false
	var closed_entry: Dictionary=closed_candidate.entry
	var closed_profile: Dictionary=closed_candidate.profile
	if not await auth_wait(func():return real_closed_projection(a1,"a1",run_identity.run_id,run_identity.revision,budget_identity.budget_id,budget_identity.generation,closed_entry) and real_closed_projection(a2,"a2",run_identity.run_id,run_identity.revision,budget_identity.budget_id,budget_identity.generation,closed_entry),"Both Alice devices consume the independently derived closed DTO and same run/budget identities"):return false
	if not check(alice_backend.profile_event_count>profile_events_before_stop and alice_backend.observation_error.is_empty(),"The actual Stop event reached Hub fan-out and passive observers remain clean"):return false
	if not check_stop_close_writer(e1_candidates[1],closed_profile):return false
	var final_disk: Dictionary=alice_backend._disk_set(alice_save_path)
	var final_validated: Dictionary=ProfileCompare.validated_copy(alice_backend.session,alice_backend.last_saved_payload)
	if not check(alice_backend.session._profile==closed_profile and final_validated.get("ok",false) and final_validated.profile==alice_backend.session._normalize_numbers(closed_profile.duplicate(true)) and final_disk.primary.get("ok",false) and final_disk.primary.bytes.get_string_from_utf8()==alice_backend.last_saved_payload and not final_disk.tmp.get("exists",true),"Alice's stopped native full profile, independently validated cache and exact durable primary bytes agree"):return false
	if not check(bob_is_unchanged(),"Stop remains scoped to Alice and leaves Bob's full saved state untouched"):return false
	alice_closed_profile=alice_backend.session._profile.duplicate(true)
	alice_closed_cache=alice_backend.last_saved_payload
	alice_closed_serial=alice_backend.quest_save_serial
	alice_closed_checkpoint_count=alice_backend.ordinary_checkpoint_records.size()
	alice_closed_disk=final_disk.duplicate(true)
	if not await Wait.settle(self,a2):return check(false,"A2's stream settles after generic Stop")
	if not await Wait.settle(self,bob):return check(false,"Bob's stream settles after generic Stop")
	if not check(profile_event_delta(stop_event_baseline,"alice_a1")>0 and profile_event_delta(stop_event_baseline,"alice_a2")>0 and profile_event_delta(stop_event_baseline,"bob_original")==0,"Stop event counters advance on both Alice streams and remain unchanged on Bob"):return false
	var stop_settle_profile_matches: bool=alice_backend.session._profile==alice_closed_profile
	var stop_settle_cache_matches: bool=alice_backend.last_saved_payload==alice_closed_cache
	var stop_settle_disk_after: Dictionary=alice_backend._disk_set(alice_save_path)
	var stop_settle_disk_matches: bool=stop_settle_disk_after==alice_closed_disk
	var stop_settle_new_checkpoint_count: int=alice_backend.ordinary_checkpoint_records.size()-alice_closed_checkpoint_count
	var stop_settle_kind_counts: Dictionary=alice_backend._writer_kind_snapshot()
	var stop_settle_callbacks_valid: bool=stop_settle_new_checkpoint_count>=0 and stop_settle_kind_counts.get("loot_settlement_written",null) is int and stop_settle_kind_counts.loot_settlement_written==3 and stop_settle_kind_counts.get("save_profile_boundary",null) is int and stop_settle_kind_counts.save_profile_boundary-alice_closed_checkpoint_count==stop_settle_new_checkpoint_count and alice_backend.quest_save_serial==alice_closed_serial+stop_settle_new_checkpoint_count and alice_backend._checkpoint_count_reconciles() and alice_backend._checkpoint_records_valid_from(alice_closed_checkpoint_count) and alice_backend._writer_counts_reconcile()
	var stop_settle_bob_matches: bool=bob_is_unchanged()
	if not (stop_settle_profile_matches and stop_settle_cache_matches and stop_settle_disk_matches and stop_settle_callbacks_valid and stop_settle_bob_matches):
		var bob_disk_after_stop_settle: Dictionary=capture_bob_disk()
		var bob_profile_matches: bool=is_instance_valid(bob_backend) and bob_backend.session._profile==bob_profile_frozen
		var bob_cache_matches: bool=is_instance_valid(bob_backend) and bob_backend.last_saved_payload==bob_cache_frozen
		var bob_serial_matches: bool=is_instance_valid(bob_backend) and bob_backend.quest_save_serial==bob_serial_frozen
		print("AUTH_PUBLIC_LOOT_STOP_SETTLE_DIAGNOSTIC ",JSON.stringify({"alice_profile_matches_closed_writer":stop_settle_profile_matches,"alice_cache_matches_closed_writer":stop_settle_cache_matches,"alice_disk_matches_closed_writer":stop_settle_disk_matches,"alice_new_checkpoint_count":stop_settle_new_checkpoint_count,"alice_checkpoint_callbacks_valid":stop_settle_callbacks_valid,"alice_writer_kind_counts":stop_settle_kind_counts,"alice_checkpoint_records":alice_backend._checkpoint_summary_from(alice_closed_checkpoint_count),"alice_profile_diff_paths_types":_bounded_profile_diff(alice_closed_profile,alice_backend.session._profile),"alice_cache_bytes":alice_backend.last_saved_payload.to_utf8_buffer().size(),"alice_serial_before":alice_closed_serial,"alice_serial_after":alice_backend.quest_save_serial,"alice_profile_event_count":alice_backend.profile_event_count,"alice_disk_slots_since_close":_disk_slots_evidence(alice_closed_disk,stop_settle_disk_after),"bob_matches_frozen":stop_settle_bob_matches,"bob_profile_matches_frozen":bob_profile_matches,"bob_profile_diff_paths_types":_bounded_profile_diff(bob_profile_frozen,bob_backend.session._profile if is_instance_valid(bob_backend) else {}),"bob_cache_matches_frozen":bob_cache_matches,"bob_cache_before_bytes":_string_byte_length(bob_cache_frozen),"bob_cache_after_bytes":_string_byte_length(bob_backend.last_saved_payload if is_instance_valid(bob_backend) else null),"bob_serial_matches_frozen":bob_serial_matches,"bob_serial_before":bob_serial_frozen,"bob_serial_after":bob_backend.quest_save_serial if is_instance_valid(bob_backend) else null,"bob_disk_slots":_disk_slots_evidence(bob_disk_frozen,bob_disk_after_stop_settle),"bob_profile_event_counts":profile_message_counts.duplicate(true)}))
	if not check(stop_settle_profile_matches and stop_settle_cache_matches and stop_settle_disk_matches and stop_settle_callbacks_valid and stop_settle_bob_matches,"Stop remains one committed settlement; only individually validated same-payload checkpoints may advance serial while the complete close profile/cache/disk remain identical"):return false
	return await authenticated_reconnect_then_logout(run_identity,budget_identity,closed_entry)

func authenticated_reconnect_then_logout(run_identity: Dictionary, budget_identity: Dictionary, closed_entry: Dictionary) -> bool:
	a2_token_before_reconnect=link_b.login_token
	var old_client_peer_id: Variant=link_b._peer.get_instance_id() if is_instance_valid(link_b._peer) else null
	var old_lifecycle: int=int(link_b.get("_lifecycle"))
	var old_peer_id: int=a2_server_peer_id
	var old_binding_before: Dictionary=binding_evidence(old_peer_id,a2_binding_ref)
	if not check(not a2_token_before_reconnect.is_empty() and hub.accounts.verify_token("AuthAlice",a2_token_before_reconnect).get("ok",false),"A2 reconnect begins before any explicit logout while its real device token remains valid"):return false
	link_b.close() # Real local transport close; unlike logout this preserves login_token.
	if not await auth_wait(func():return not link_b.online and not hub._connections.has(old_peer_id) and not alice_backend._fee_bindings.has(old_peer_id) and not live_server_peer(old_peer_id),"Real A2 socket close retires its Hub connection, server membership and exact fee binding"):return false
	var a2_old_peer_expired: bool=a2_server_peer_ref!=null and is_instance_valid(a2_server_peer_ref) and a2_server_peer_ref.get_ref()==null
	var a2_old_binding_expired: bool=a2_binding_ref!=null and is_instance_valid(a2_binding_ref) and a2_binding_ref.get_ref()==null
	var alice_profile_before_reconnect: Dictionary=alice_backend.session._profile.duplicate(true)
	var alice_cache_before_reconnect: String=alice_backend.last_saved_payload
	var alice_serial_before_reconnect: int=alice_backend.quest_save_serial
	var alice_disk_before_reconnect: Dictionary=alice_backend._disk_set(alice_save_path)
	var starts_before_reconnect: int=alice_backend.start_event_count
	var writers_before_reconnect: int=alice_backend.writer_event_count
	var writer_kinds_before_reconnect: Dictionary=alice_backend._writer_kind_snapshot()
	var checkpoint_count_before_reconnect: int=alice_backend.ordinary_checkpoint_records.size()
	var writer_records_before_reconnect: int=alice_backend.writer_records.size()
	var profile_events_before_reconnect: int=alice_backend.profile_event_count
	var reconnect_frame_before: int=Engine.get_process_frames()
	var connections_before: Array=hub.connections_of(account_a).duplicate()
	link_b.connect_now()
	if not await auth_wait(func():return link_b.online and not link_b.login_token.is_empty() and hub.connections_of(account_a).size()==2,"A2's new socket completes the real token hello and Hub re-entry"):return false
	if not await Wait.settle(self,world_b):return check(false,"A2 reconnect's real round trip settles")
	var reconnect_mapping: Dictionary=profile_peer_probe(account_a,connections_before,world_b,alice_backend)
	var new_peer_value: Variant=reconnect_mapping.get("peer_id",null)
	print("AUTH_PUBLIC_LOOT_PEER_MAPPING_DIAGNOSTIC ",JSON.stringify(reconnect_mapping))
	if not check(reconnect_mapping.get("found",false) is bool and reconnect_mapping.found and new_peer_value is int and int(new_peer_value)!=old_peer_id and hub.backend_of(int(new_peer_value))==alice_backend and hub.profile_of(int(new_peer_value))==account_a and not hub._connections.has(old_peer_id),"A2 reconnect creates a new server-side Alice membership on the same Hub Backend"):return false
	var new_peer_id: int=int(new_peer_value)
	a2_reconnected_server_peer_id=new_peer_id
	a2_reconnected_server_peer_id_found=true
	a2_reconnected_server_peer_ref=capture_server_peer_ref(new_peer_id)
	if not check(captured_server_peer_is_live(a2_reconnected_server_peer_ref),"Reconnect connection maps to the actual replacement server peer"):return false
	reconnected_server_peer_a_id=new_peer_id;reconnected_server_peer_a_ref=a2_reconnected_server_peer_ref
	if is_instance_valid(link_b._peer):reconnected_client_peer_a_id=link_b._peer.get_instance_id()
	reconnected_client_peer_a_id_found=is_instance_valid(link_b._peer)
	reconnected_server_peer_a_id_found=true
	a2_reconnected_binding_ref=capture_binding_ref(new_peer_id)
	binding_reconnected_server_peer_a_ref=a2_reconnected_binding_ref
	if not check(a2_reconnected_server_peer_ref!=null and binding_ref_is_current(alice_backend,new_peer_id,a2_reconnected_binding_ref) and not is_same(alice_backend._fee_bindings[new_peer_id],alice_backend._fee_bindings.get(a1_server_peer_id,null)),"The real Hub token entry creates a fresh current binding distinct from A1's binding"):return false
	record_peer_mapping("A2 valid-token reconnect",world_b,new_peer_id,account_a,alice_backend,a2_reconnected_binding_ref)
	var old_new_peer_evidence: Dictionary=retired_peer_identity_evidence(a2_server_peer_ref,a2_reconnected_server_peer_ref,true,old_peer_id,new_peer_id)
	var old_peer_absent: bool=not live_server_peer(old_peer_id)
	var old_binding_absent: bool=not alice_backend._fee_bindings.has(old_peer_id) and a2_old_binding_expired
	var lifecycle_advanced: bool=int(link_b.get("_lifecycle"))>old_lifecycle
	print("AUTH_PUBLIC_LOOT_RECONNECT_DIAGNOSTIC ",JSON.stringify({"old_server_peer_id":old_peer_id,"new_server_peer_id":new_peer_id,"old_peer_expired":a2_old_peer_expired,"old_binding_expired":a2_old_binding_expired,"old_peer_absent_from_clients":old_peer_absent,"old_binding_absent":old_binding_absent,"retired_peer_identity":old_new_peer_evidence,"lifecycle_before":old_lifecycle,"lifecycle_after":int(link_b.get("_lifecycle")),"lifecycle_advanced":lifecycle_advanced,"old_binding_before":old_binding_before,"old_client_peer_id":old_client_peer_id}))
	if not check(old_new_peer_evidence.get("new_peer_is_distinct",false) and old_peer_absent and old_binding_absent and lifecycle_advanced and link_b.login_token==a2_token_before_reconnect and hub.accounts.verify_token("AuthAlice",a2_token_before_reconnect).get("ok",false),"Token reconnect retires the old peer/binding and authenticates only a new current peer with the still-valid token"):return false
	var alice_disk_after_reconnect: Dictionary=alice_backend._disk_set(alice_save_path)
	var reconnect_disk_unchanged: bool=alice_disk_after_reconnect==alice_disk_before_reconnect
	var reconnect_profile_unchanged: bool=alice_backend.session._profile==alice_profile_before_reconnect
	var reconnect_cache_unchanged: bool=alice_backend.last_saved_payload==alice_cache_before_reconnect
	var writer_kinds_after_reconnect: Dictionary=alice_backend._writer_kind_snapshot()
	var reconnect_checkpoint_count: int=alice_backend.ordinary_checkpoint_records.size()-checkpoint_count_before_reconnect
	var reconnect_settlement_unchanged: bool=writer_kinds_after_reconnect.get("loot_settlement_written",null) is int and writer_kinds_before_reconnect.get("loot_settlement_written",null) is int and writer_kinds_after_reconnect.loot_settlement_written==writer_kinds_before_reconnect.loot_settlement_written
	var reconnect_checkpoints_valid: bool=reconnect_checkpoint_count>=0 and writer_kinds_after_reconnect.get("save_profile_boundary",null) is int and writer_kinds_before_reconnect.get("save_profile_boundary",null) is int and writer_kinds_after_reconnect.save_profile_boundary-writer_kinds_before_reconnect.save_profile_boundary==reconnect_checkpoint_count and alice_backend.quest_save_serial==alice_serial_before_reconnect+reconnect_checkpoint_count and alice_backend._checkpoint_count_reconciles() and alice_backend._checkpoint_records_valid_from(checkpoint_count_before_reconnect)
	var reconnect_writer_delta_reconciles: bool=alice_backend._writer_counts_reconcile() and alice_backend.writer_event_count-writers_before_reconnect==reconnect_checkpoint_count
	var reconnect_start_count_unchanged: bool=alice_backend.start_event_count==starts_before_reconnect
	var reconnect_mutation_check: bool=reconnect_profile_unchanged and reconnect_cache_unchanged and reconnect_disk_unchanged and reconnect_start_count_unchanged and reconnect_settlement_unchanged and reconnect_checkpoints_valid and reconnect_writer_delta_reconciles
	if not reconnect_mutation_check:
		print("AUTH_PUBLIC_LOOT_RECONNECT_STATE_DIAGNOSTIC ",JSON.stringify({"writer_count_before_disconnect":writers_before_reconnect,"writer_count_after_reconnect_wait":alice_backend.writer_event_count,"writer_count_delta":alice_backend.writer_event_count-writers_before_reconnect,"writer_kind_counts_before":writer_kinds_before_reconnect,"writer_kind_counts_after":writer_kinds_after_reconnect,"checkpoint_count":reconnect_checkpoint_count,"checkpoint_records":alice_backend._checkpoint_summary_from(checkpoint_count_before_reconnect),"checkpoint_records_valid":reconnect_checkpoints_valid,"writer_delta_reconciles":reconnect_writer_delta_reconciles,"writer_records_before_disconnect":writer_records_before_reconnect,"writer_records_after_reconnect_wait":alice_backend.writer_records.size(),"writer_records_delta":alice_backend.writer_records.size()-writer_records_before_reconnect,"profile_events_before_disconnect":profile_events_before_reconnect,"profile_events_after_reconnect_wait":alice_backend.profile_event_count,"profile_event_delta":alice_backend.profile_event_count-profile_events_before_reconnect,"frame_before_disconnect":reconnect_frame_before,"frame_after_reconnect_wait":Engine.get_process_frames(),"frame_delta":Engine.get_process_frames()-reconnect_frame_before,"start_count_before_disconnect":starts_before_reconnect,"start_count_after_reconnect_wait":alice_backend.start_event_count,"profile_unchanged":reconnect_profile_unchanged,"profile_diff_paths_types":_bounded_profile_diff(alice_profile_before_reconnect,alice_backend.session._profile),"cache_unchanged":reconnect_cache_unchanged,"cache_before_bytes":alice_cache_before_reconnect.to_utf8_buffer().size(),"cache_after_bytes":alice_backend.last_saved_payload.to_utf8_buffer().size(),"settlement_unchanged":reconnect_settlement_unchanged,"serial_matches_validated_checkpoints":reconnect_checkpoints_valid,"serial_before":alice_serial_before_reconnect,"serial_after":alice_backend.quest_save_serial,"disk_unchanged":reconnect_disk_unchanged,"disk_slots":_disk_slots_evidence(alice_disk_before_reconnect,alice_disk_after_reconnect),"writer_records_tail":_writer_record_diagnostic(alice_backend.writer_records),"writer_event_ring_tail":_writer_event_ring_diagnostic(alice_backend.writer_event_ring)}))
	if not check(reconnect_mutation_check,"Reconnect creates no settlement or state change; only individually validated same-payload checkpoints may advance serial"):return false
	if not check(real_closed_projection(world_b,"a2-reconnected",run_identity.run_id,run_identity.revision,budget_identity.budget_id,budget_identity.generation,closed_entry) and bob_is_unchanged(),"A2 token snapshot preserves Alice's stopped closed ledger and does not touch Bob"):return false
	a1_token_before_logout=link_a.login_token
	if not check(not a1_token_before_logout.is_empty() and hub.accounts.verify_token("AuthAlice",a1_token_before_logout).get("ok",false),"A1 begins explicit switch with its own still-valid token after A2 reconnect has completed"):return false
	var old_scene_id: int=world_a.get_instance_id()
	var old_scene_ref: WeakRef=weakref(world_a)
	var old_a1_peer_id: int=a1_server_peer_id
	var old_a1_client_peer_ref: WeakRef=weakref(link_a._peer) if is_instance_valid(link_a) and is_instance_valid(link_a._peer) else null
	var old_a1_link_ref: WeakRef=weakref(link_a) if is_instance_valid(link_a) else null
	var old_a1_link_lifecycle_before: Variant=link_a.get("_lifecycle") if is_instance_valid(link_a) else null
	var old_a1_logout_generation_before: Variant=world_a._remote.logout_generation
	GameScene.server_url_override="ws://127.0.0.1:%d"%server.port
	world_a._remote.switch_profile() # Actual settings hook, local revoke then real logout request.
	var old_a1_logout_generation_after_switch: Variant=world_a._remote.logout_generation
	var old_a1_logout_generation_advanced_once: bool=old_a1_logout_generation_before is int and old_a1_logout_generation_after_switch is int and old_a1_logout_generation_after_switch==old_a1_logout_generation_before+1
	if not check(link_a.login_token.is_empty() and old_a1_logout_generation_advanced_once,"Explicit A1 switch_profile increments its local generation once and synchronously forgets only A1's local token"):return false
	if not await auth_wait(func():return not is_instance_id_valid(old_scene_id) and is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_scene_id,"Actual LogoutReply reload retires A1's old scene and creates a new main scene"):return false
	var replacement: Variant=current_scene
	GameScene.server_url_override=""
	if not check(is_instance_valid(replacement) and replacement!=world_a,"SceneTree reload creates a replacement main GameScene after real LogoutReply"):return false
	var replacement_link_is_new: bool=is_instance_valid(link_a) and is_instance_valid(replacement.link) and not is_same(link_a,replacement.link)
	if not check(replacement_link_is_new,"The picker reload owns a distinct newly constructed WsLink; no old-link transfer is assumed"):return false
	worlds.append(replacement)
	replacement.visible=true
	var bob_original_profile_count_before_replacement_login: int=int(profile_message_counts.get("bob_original",-1))
	var bob_backend_profile_count_before_replacement_login: int=bob_backend_profile_event_count
	var bob_startup_native_before: Dictionary=bob_backend.session._profile.duplicate(true)
	var bob_startup_cache_before: String=bob_backend.last_saved_payload
	var bob_startup_serial_before: int=bob_backend.quest_save_serial
	var bob_startup_disk_before: Dictionary=capture_bob_disk()
	var bob_startup_resume_path_before: String=bob_backend._resume_file()
	var bob_startup_backend_is_reused: bool=hub.backends.get(account_b,null) is AuthLootBackend and is_same(hub.backends.get(account_b,null),bob_backend)
	var bob_startup_before_matches_original: bool=bob_startup_backend_is_reused and bob_backend.is_processing() and bob_backend.keep_resume_current and bob_backend.battle_open==false and bob_backend.session._pending.is_empty() and bob_backend.session.release_events.is_empty() and bob_backend.session.capture_events.is_empty() and bob_backend.automation.stop_events.is_empty() and bob_startup_native_before==bob_profile_frozen and bob_startup_cache_before==bob_cache_frozen and bob_startup_serial_before==bob_serial_frozen and bob_startup_disk_before==bob_disk_frozen and not bob_startup_resume_path_before.is_empty() and not FileAccess.file_exists(bob_startup_resume_path_before) and not FileAccess.file_exists(bob_startup_resume_path_before+".tmp")
	if not check(bob_startup_before_matches_original,"Before replacement startup, the original Hub Backend instance is reused and Bob still matches the original full native/cache/serial/primary-backup-tmp baseline with no resume sidecar"):return false
	bob_backend.event.connect(_record_bob_backend_profile_event)
	var bob_startup_save_observer_armed: bool=bob_backend.arm_startup_noop_save_observer(hub,account_b,bob_backend.session,bob_save_path,bob_profile_frozen,bob_cache_frozen,bob_disk_frozen)
	if not check(bob_startup_save_observer_armed,"Arm a bounded Bob-only no-op save observer without resetting the original serial or writer counters"):return false
	bob_backend.startup_request_observe=true
	tap_profile_messages(replacement,"bob_replacement") # Observe from before the replacement's actual PIN login and GameScene._ready requests.
	pump.links.clear()
	for owned_world in worlds:
		if is_instance_valid(owned_world):pump.links.append(owned_world.link)
	var old_a1_binding_after_logout: Dictionary=auth_binding_evidence(alice_backend,old_a1_peer_id,a1_binding_ref)
	var old_a1_scene_hub_binding_retired: bool=old_scene_ref.get_ref()==null and not hub._connections.has(old_a1_peer_id) and not alice_backend._fee_bindings.has(old_a1_peer_id) and not old_a1_binding_after_logout.get("same_object",true)
	var a1_server_token_revoked_before_release: bool=not hub.accounts.verify_token("AuthAlice",a1_token_before_logout).get("ok",false)
	var a2_server_token_valid_before_release: bool=hub.accounts.verify_token("AuthAlice",a2_token_before_reconnect).get("ok",false)
	var alice_connections_before_release: Array=hub.connections_of(account_a)
	var alice_only_a2_before_release: bool=alice_connections_before_release.size()==1 and alice_connections_before_release.has(a2_reconnected_server_peer_id) and not alice_connections_before_release.has(old_a1_peer_id)
	var old_a1_client_peer_after_logout: Variant=old_a1_client_peer_ref.get_ref() if old_a1_client_peer_ref!=null and is_instance_valid(old_a1_client_peer_ref) else null
	var old_a1_client_peer_open_after_logout: bool=old_a1_client_peer_after_logout is WebSocketPeer and is_instance_valid(old_a1_client_peer_after_logout) and old_a1_client_peer_after_logout.get_ready_state()==WebSocketPeer.STATE_OPEN
	var old_a1_link_still_owns_open_peer: bool=is_instance_valid(link_a) and link_a.online and link_a.get("_peer") is WebSocketPeer and is_instance_valid(link_a.get("_peer")) and old_a1_client_peer_open_after_logout and is_same(link_a.get("_peer"),old_a1_client_peer_after_logout) and live_server_peer(old_a1_peer_id)
	var old_a1_logout_callbacks_empty: bool=is_instance_valid(link_a) and link_a._callbacks.is_empty()
	var old_a1_link_absent_from_pump: bool=is_instance_valid(pump) and not pump.links.has(link_a)
	old_a1_client_peer_after_logout=null
	print("AUTH_LOGOUT_PRE_REFERENCE_RELEASE_EVIDENCE ",JSON.stringify({"old_scene_destroyed":old_scene_ref.get_ref()==null,"hub_connection_absent":not hub._connections.has(old_a1_peer_id),"fee_binding_absent":not alice_backend._fee_bindings.has(old_a1_peer_id),"old_binding_evidence":old_a1_binding_after_logout,"a1_local_token_empty":link_a.login_token.is_empty(),"a1_server_token_revoked":a1_server_token_revoked_before_release,"a2_server_token_valid":a2_server_token_valid_before_release,"alice_has_only_a2":alice_only_a2_before_release,"old_client_peer_open_after_logout":old_a1_client_peer_open_after_logout,"old_link_owns_open_peer":old_a1_link_still_owns_open_peer,"logout_generation_advanced_once":old_a1_logout_generation_advanced_once,"logout_callbacks_empty":old_a1_logout_callbacks_empty,"old_link_absent_from_pump":old_a1_link_absent_from_pump,"old_server_peer_member":live_server_peer(old_a1_peer_id)}))
	if not check(old_a1_scene_hub_binding_retired and a1_server_token_revoked_before_release and a2_server_token_valid_before_release and alice_only_a2_before_release and old_a1_link_still_owns_open_peer and old_a1_logout_generation_advanced_once and old_a1_logout_callbacks_empty and old_a1_link_absent_from_pump,"Real logout/reload revokes A1 auth and retires scene/Hub/binding while preserving A2; the old socket is still open before the test drops its remaining owner references"):return false
	if failures>0:return false
	var old_a1_link_lifecycle_before_release: Variant=link_a.get("_lifecycle") if is_instance_valid(link_a) else null
	var old_a1_link_online_before_release: bool=is_instance_valid(link_a) and link_a.online
	var old_a1_link_closed_before_release: bool=is_instance_valid(link_a) and link_a.get("_closed")==true
	var old_a1_link_peer_matches_captured: bool=is_instance_valid(link_a) and is_instance_valid(link_a.get("_peer")) and old_a1_client_peer_ref!=null and is_instance_valid(old_a1_client_peer_ref.get_ref()) and is_same(link_a.get("_peer"),old_a1_client_peer_ref.get_ref())
	print("AUTH_LOGOUT_TEST_REFERENCE_RELEASE ",JSON.stringify({"link_weakref_created":old_a1_link_ref is WeakRef,"world_was_old_scene":not is_instance_valid(world_a),"callbacks_empty":old_a1_logout_callbacks_empty,"pump_omits_link":old_a1_link_absent_from_pump,"link_online_before_release":old_a1_link_online_before_release,"link_closed_before_release":old_a1_link_closed_before_release,"link_peer_matches_captured":old_a1_link_peer_matches_captured,"lifecycle_before_release":old_a1_link_lifecycle_before_release,"release_action":"clear test globals; no close/poll/server-set mutation"}))
	if not check(old_a1_link_ref is WeakRef and not is_instance_valid(world_a) and old_a1_logout_callbacks_empty and old_a1_link_absent_from_pump and old_a1_link_online_before_release and not old_a1_link_closed_before_release and old_a1_link_peer_matches_captured,"Only the test's stale globals remain as old-link owners after logout assertions; no callback or LinkPump entry retains it"):return false
	link_a=null
	world_a=null
	var old_a1_link_released_and_peer_retired: bool=await Wait.until(self,func():return not is_instance_valid(old_a1_link_ref.get_ref()) and not live_server_peer(old_a1_peer_id))
	if not old_a1_link_released_and_peer_retired:
		print("AUTH_LOGOUT_NATURAL_PEER_RETIREMENT_DIAGNOSTIC ",JSON.stringify(logout_peer_retirement_diagnostic(old_a1_peer_id,old_a1_client_peer_ref,a1_server_peer_ref,old_scene_ref,old_a1_link_ref,old_a1_link_lifecycle_before_release,old_a1_logout_callbacks_empty,old_a1_logout_generation_before,old_a1_logout_generation_after_switch)))
	var old_a1_binding_after_natural_retirement: Dictionary=auth_binding_evidence(alice_backend,old_a1_peer_id,a1_binding_ref)
	var old_a1_binding_stays_retired: bool=not hub._connections.has(old_a1_peer_id) and not alice_backend._fee_bindings.has(old_a1_peer_id) and not old_a1_binding_after_natural_retirement.get("current_valid",true) and not old_a1_binding_after_natural_retirement.get("same_object",true)
	if not check(old_a1_link_released_and_peer_retired and old_a1_binding_stays_retired,"After the test releases old-scene/link references, normal SceneTree/WebSocketServer processing observes the old peer retire while logout's retired Hub/binding identity stays absent"):return false
	world_a=replacement
	link_a=replacement.link
	var bob_connections_before: Array=hub.connections_of(account_b).duplicate()
	if not await login_with_real_screen(replacement,"AuthBob","2222"):return false
	var replacement_mapping: Dictionary=await wait_for_profile_peer(account_b,bob_connections_before,replacement,bob_backend,"Replacement A1 scene logs into Bob with the real PIN UI and a newly injected server peer")
	if failures>0:return false
	var replacement_peer_value: Variant=replacement_mapping.get("peer_id",null)
	if not check(replacement_mapping.get("found",false) is bool and replacement_mapping.found and replacement_peer_value is int,"Replacement A1 has an attributable server-side Bob connection"):return false
	var replacement_peer_id: int=int(replacement_peer_value)
	replacement_bob_server_peer_id=replacement_peer_id
	replacement_bob_server_peer_id_found=true
	var bob_replacement_binding: WeakRef=capture_auth_binding_ref(bob_backend,replacement_peer_id)
	replacement_bob_client_peer_id=replacement.link._peer.get_instance_id() if is_instance_valid(replacement.link._peer) else null
	replacement_bob_client_peer_id_found=replacement_bob_client_peer_id is int
	if not check(replacement.backend==null and hub.backend_of(replacement_peer_id)==bob_backend and replacement.link.account.get("name",null)=="AuthBob" and binding_ref_is_current(bob_backend,replacement_peer_id,bob_replacement_binding),"Replacement remains backend-null and is bound only to Bob's real Hub Backend/connection"):return false
	var replacement_link_lifecycle_after_login: Variant=replacement.link.get("_lifecycle")
	var replacement_tap_same_link_after_login: bool=profile_tap_is_same_link(replacement,"bob_replacement")
	if not check(replacement_tap_same_link_after_login and replacement_link_lifecycle_after_login is int,"Replacement PIN login keeps the pre-login observer on the same live WsLink instance"):return false
	record_peer_mapping("A1 explicit switch then Bob PIN login",replacement,replacement_peer_id,account_b,bob_backend,bob_replacement_binding)
	var alice_connections_after_bob: Array=hub.connections_of(account_a)
	var alice_only_a2_after_bob: bool=alice_connections_after_bob.size()==1 and alice_connections_after_bob.has(a2_reconnected_server_peer_id) and not alice_connections_after_bob.has(old_a1_peer_id)
	print("AUTH_LOGOUT_POST_BOB_ACCOUNT_EVIDENCE ",JSON.stringify({"alice_connection_count":alice_connections_after_bob.size(),"alice_connection_ids":bounded_id_evidence(alice_connections_after_bob),"only_a2_remains":alice_only_a2_after_bob}))
	if not check(alice_only_a2_after_bob,"Bob's real login leaves exactly Alice's independent A2 connection and cannot restore old A1 ownership"):return false
	if not await Wait.settle(self,replacement):
		print("AUTH_BOB_STARTUP_SETTLE_FAILURE ",JSON.stringify({"link":"replacement","original_profile_count":profile_message_counts.get("bob_original",null),"replacement_profile_count":profile_message_counts.get("bob_replacement",null),"backend_source_count":bob_backend_profile_event_count,"backend_source_ring":bob_backend_profile_event_ring.duplicate(true),"startup_request_records":bob_backend.startup_request_records.duplicate(true),"native_cache_serial_disk_unchanged":bob_is_unchanged()}))
		return check(false,"Replacement Bob startup requests settle before the Alice-event isolation baseline")
	if not await Wait.settle(self,world_c):
		print("AUTH_BOB_STARTUP_SETTLE_FAILURE ",JSON.stringify({"link":"original","original_profile_count":profile_message_counts.get("bob_original",null),"replacement_profile_count":profile_message_counts.get("bob_replacement",null),"backend_source_count":bob_backend_profile_event_count,"backend_source_ring":bob_backend_profile_event_ring.duplicate(true),"startup_request_records":bob_backend.startup_request_records.duplicate(true),"native_cache_serial_disk_unchanged":bob_is_unchanged()}))
		return check(false,"Original Bob stream receives replacement startup publications before the Alice-event isolation baseline")
	var replacement_tap_same_link_after_settle: bool=profile_tap_is_same_link(replacement,"bob_replacement")
	var replacement_lifecycle_after_settle: Variant=replacement.link.get("_lifecycle") if is_instance_valid(replacement) and is_instance_valid(replacement.link) else null
	var replacement_link_lifecycle_stable: bool=replacement_tap_same_link_after_settle and replacement_lifecycle_after_settle is int and replacement_link_lifecycle_after_login is int and replacement_lifecycle_after_settle==replacement_link_lifecycle_after_login
	var bob_original_startup_slice: Dictionary=_profile_event_slice("bob_original",bob_original_profile_count_before_replacement_login)
	var bob_replacement_startup_slice: Dictionary=_profile_event_slice("bob_replacement",0)
	var bob_source_ring: Array=[]
	for source_value in bob_backend_profile_event_ring:
		if source_value is Dictionary and source_value.get("ordinal",null) is int and source_value.ordinal>bob_backend_profile_count_before_replacement_login:bob_source_ring.append(source_value)
	var bob_source_revisions: Array=[]
	var bob_source_profiles_match_frozen: bool=true
	for source_value in bob_source_ring:
		var source_revision: Variant=_strict_backend_revision(source_value.get("backend_rev",null))
		if not (source_revision is int):bob_source_profiles_match_frozen=false
		else:bob_source_revisions.append(source_revision)
		if not (source_value.get("matches_frozen_profile",null) is bool) or not source_value.matches_frozen_profile:bob_source_profiles_match_frozen=false
	var bob_startup_source_complete: bool=not bob_backend_profile_event_overflow and bob_source_ring.size()==bob_backend_profile_event_count-bob_backend_profile_count_before_replacement_login
	var bob_startup_request_records_complete: bool=not bob_backend.startup_request_overflow
	var bob_startup_streams_match_source: bool=bob_startup_source_complete and bob_startup_request_records_complete and bob_original_startup_slice.get("complete",false) and bob_replacement_startup_slice.get("complete",false) and bob_original_startup_slice.get("wire_revisions",[])==bob_source_revisions and bob_replacement_startup_slice.get("wire_revisions",[])==bob_source_revisions and bob_original_startup_slice.get("all_match_frozen",false) and bob_replacement_startup_slice.get("all_match_frozen",false) and bob_source_profiles_match_frozen
	# Read every original full-state predicate once, then reuse those captures for
	# both the strict gate and bounded diagnostics. No snapshot/save is invoked.
	var bob_startup_backend_valid: bool=is_instance_valid(bob_backend)
	var bob_startup_session: Variant=bob_backend.session if bob_startup_backend_valid else null
	var bob_startup_session_valid: bool=is_instance_valid(bob_startup_session)
	var bob_startup_native_source: Variant=bob_startup_session._profile if bob_startup_session_valid else null
	var bob_startup_native: Variant=bob_startup_native_source.duplicate(true) if bob_startup_native_source is Dictionary else null
	var bob_startup_cache: Variant=bob_backend.last_saved_payload if bob_startup_backend_valid else null
	var bob_startup_serial: Variant=bob_backend.quest_save_serial if bob_startup_backend_valid else null
	var bob_startup_backend_revision: Variant=bob_backend.rev if bob_startup_backend_valid else null
	var bob_startup_disk: Variant=capture_bob_disk() if bob_startup_backend_valid else null
	var bob_startup_expected_client: Dictionary=normalized_client_profile_oracle(bob_startup_session,bob_profile_frozen) if bob_startup_session_valid else {}
	var bob_startup_world_state: Variant=world_c.state if is_instance_valid(world_c) else null
	var bob_startup_replacement_state: Variant=replacement.state if is_instance_valid(replacement) else null
	var bob_startup_world_client: Variant=bob_startup_world_state.full_profile() if is_instance_valid(bob_startup_world_state) else null
	var bob_startup_replacement_client: Variant=bob_startup_replacement_state.full_profile() if is_instance_valid(bob_startup_replacement_state) else null
	var bob_startup_world_rev: Variant=bob_startup_world_state.rev if is_instance_valid(bob_startup_world_state) else null
	var bob_startup_replacement_rev: Variant=bob_startup_replacement_state.rev if is_instance_valid(bob_startup_replacement_state) else null
	var bob_startup_link: Variant=replacement.link if is_instance_valid(replacement) else null
	var bob_startup_link_lifecycle: Variant=bob_startup_link.get("_lifecycle") if is_instance_valid(bob_startup_link) else null
	var bob_startup_original_client_ok: bool=bob_startup_world_client is Dictionary and bob_startup_expected_client is Dictionary and bob_startup_world_client==bob_startup_expected_client
	var bob_startup_replacement_client_ok: bool=bob_startup_replacement_client is Dictionary and bob_startup_expected_client is Dictionary and bob_startup_replacement_client==bob_startup_expected_client
	var bob_startup_native_ok: bool=bob_startup_backend_valid and bob_startup_session_valid and bob_startup_native is Dictionary and bob_startup_native==bob_profile_frozen
	var bob_startup_cache_ok: bool=bob_startup_cache is String and bob_startup_cache==bob_cache_frozen
	var bob_startup_noop_save_summary: Dictionary=bob_backend.finish_startup_noop_save_observer(bob_startup_serial if bob_startup_serial is int else -1,bob_backend.writer_event_count,bob_backend._writer_kind_snapshot(),bob_backend.profile_event_count,bob_backend.ordinary_checkpoint_records.size(),bob_backend.resume_writes) if bob_startup_backend_valid else {}
	bob_backend.startup_request_observe=false
	var bob_startup_serial_expected: Variant=bob_startup_noop_save_summary.get("serial_expected_from_verified_calls",null)
	var bob_startup_serial_ok: bool=bob_startup_serial is int and bob_startup_serial_expected is int and bob_startup_serial==bob_startup_serial_expected and bob_startup_noop_save_summary.get("valid",false) is bool and bob_startup_noop_save_summary.get("valid",false)
	var bob_startup_disk_ok: bool=bob_startup_disk is Dictionary and bob_startup_disk==bob_disk_frozen
	var bob_startup_backend_still_registered: bool=is_instance_valid(hub) and hub.backends.get(account_b,null) is AuthLootBackend and is_same(hub.backends.get(account_b,null),bob_backend)
	var bob_startup_state_unchanged: bool=bob_startup_backend_still_registered and replacement_link_lifecycle_stable and bob_startup_original_client_ok and bob_startup_replacement_client_ok and bob_startup_native_ok and bob_startup_cache_ok and bob_startup_serial_ok and bob_startup_disk_ok
	var bob_startup_native_diff: Dictionary=_bounded_state_diff(bob_profile_frozen,bob_startup_native,"native_profile",6,1365,8)
	var bob_startup_original_client_diff: Dictionary=_bounded_state_diff(bob_startup_expected_client,bob_startup_world_client,"client_original",6,1365,8)
	var bob_startup_replacement_client_diff: Dictionary=_bounded_state_diff(bob_startup_expected_client,bob_startup_replacement_client,"client_replacement",6,1365,8)
	var bob_startup_disk_slots: Dictionary=_disk_slots_evidence(bob_disk_frozen,bob_startup_disk)
	print("AUTH_BOB_REPLACEMENT_STARTUP_PROFILE_DETAIL ",JSON.stringify({"link_same_as_login_tap":replacement_tap_same_link_after_login and replacement_tap_same_link_after_settle,"lifecycle_stable":replacement_link_lifecycle_stable,"lifecycle_after_login":replacement_link_lifecycle_after_login,"lifecycle_after_settle":replacement_lifecycle_after_settle,"current_link_type":type_string(typeof(bob_startup_link)),"current_link_lifecycle_type":type_string(typeof(bob_startup_link_lifecycle)),"current_link_lifecycle":bob_startup_link_lifecycle,"client_state_original_valid":is_instance_valid(bob_startup_world_state),"client_state_replacement_valid":is_instance_valid(bob_startup_replacement_state),"client_original_profile_type":type_string(typeof(bob_startup_world_client)),"client_original_profile_matches_normalized_frozen":bob_startup_original_client_ok,"client_original_profile_diff":bob_startup_original_client_diff,"client_replacement_profile_type":type_string(typeof(bob_startup_replacement_client)),"client_replacement_profile_matches_normalized_frozen":bob_startup_replacement_client_ok,"client_replacement_profile_diff":bob_startup_replacement_client_diff,"expected_client_profile_type":type_string(typeof(bob_startup_expected_client)),"client_original_state_rev_type":type_string(typeof(bob_startup_world_rev)),"client_original_state_rev":bob_startup_world_rev if bob_startup_world_rev is int else null,"client_replacement_state_rev_type":type_string(typeof(bob_startup_replacement_rev)),"client_replacement_state_rev":bob_startup_replacement_rev if bob_startup_replacement_rev is int else null,"backend_valid":bob_startup_backend_valid,"backend_still_registered":bob_startup_backend_still_registered,"session_valid":bob_startup_session_valid,"native_source_type":type_string(typeof(bob_startup_native_source)),"native_profile_type":type_string(typeof(bob_startup_native)),"native_profile_matches_frozen":bob_startup_native_ok,"native_profile_diff":bob_startup_native_diff,"cache_type":type_string(typeof(bob_startup_cache)),"cache_matches_frozen":bob_startup_cache_ok,"cache_current_bytes":_string_byte_length(bob_startup_cache),"cache_frozen_bytes":_string_byte_length(bob_cache_frozen),"save_serial_type":type_string(typeof(bob_startup_serial)),"save_serial_current":bob_startup_serial if bob_startup_serial is int else null,"save_serial_original_frozen":bob_serial_frozen,"save_serial_expected_from_verified_startup_calls":bob_startup_serial_expected,"save_serial_matches_verified_chain":bob_startup_serial_ok,"startup_noop_save_summary":bob_startup_noop_save_summary,"backend_revision_type":type_string(typeof(bob_startup_backend_revision)),"backend_revision_current":bob_startup_backend_revision if bob_startup_backend_revision is int else null,"disk_capture_type":type_string(typeof(bob_startup_disk)),"disk_matches_frozen":bob_startup_disk_ok,"disk_slots":bob_startup_disk_slots,"full_state_unchanged":bob_startup_state_unchanged}))
	print("AUTH_BOB_REPLACEMENT_STARTUP_PROFILE_EVIDENCE ",JSON.stringify({"original_stream":bob_original_startup_slice,"replacement_stream":bob_replacement_startup_slice,"backend_source_count_before":bob_backend_profile_count_before_replacement_login,"backend_source_count_after":bob_backend_profile_event_count,"backend_source_revisions":bob_source_revisions,"backend_source_profiles_match_frozen":bob_source_profiles_match_frozen,"backend_source_ring_complete":bob_startup_source_complete,"startup_request_records":bob_backend.startup_request_records.duplicate(true),"startup_request_overflow":bob_backend.startup_request_overflow,"startup_request_records_complete":bob_startup_request_records_complete,"startup_noop_save_summary":bob_startup_noop_save_summary,"replacement_tap_same_link_after_login":replacement_tap_same_link_after_login,"replacement_tap_same_link_after_settle":replacement_tap_same_link_after_settle,"replacement_link_lifecycle_after_login":replacement_link_lifecycle_after_login,"replacement_link_lifecycle_after_settle":replacement_lifecycle_after_settle,"replacement_link_lifecycle_stable":replacement_link_lifecycle_stable,"hub_bob_peer_count":hub.connections_of(account_b).size(),"startup_streams_match_source":bob_startup_streams_match_source,"full_state_unchanged":bob_startup_state_unchanged}))
	if not check(bob_startup_streams_match_source and bob_startup_state_unchanged,"Replacement startup profile events match Bob Backend source revisions and both frozen streams; every startup save is individually verified as a same-payload no-op, while both Bob clients plus native/cache/disk remain unchanged"):return false
	var post_startup_save_kind_value: Variant=bob_backend.writer_kind_counts.get("save_profile_boundary",null)
	var post_startup_settlement_kind_value: Variant=bob_backend.writer_kind_counts.get("loot_settlement_written",null)
	if not check(post_startup_save_kind_value is int and post_startup_settlement_kind_value is int,"Freeze the Bob post-startup window only after both writer-kind counters remain strict integers"):return false
	bob_backend.post_startup_serial=bob_startup_serial
	bob_backend.post_startup_writer_total=bob_backend.writer_event_count
	bob_backend.post_startup_save_kind_total=post_startup_save_kind_value
	bob_backend.post_startup_settlement_kind_total=post_startup_settlement_kind_value
	bob_backend.post_startup_profile_event_total=bob_backend_profile_event_count
	bob_backend.post_startup_checkpoint_total=bob_backend.ordinary_checkpoint_records.size()
	bob_backend.post_startup_resume_write_total=bob_backend.resume_writes
	bob_backend.startup_noop_summary=bob_startup_noop_save_summary.duplicate(true)
	bob_backend.post_startup_baseline_ready=true
	var a1_server_token_revoked_after_bob: bool=not hub.accounts.verify_token("AuthAlice",a1_token_before_logout).get("ok",false)
	var a2_server_token_valid_after_bob: bool=hub.accounts.verify_token("AuthAlice",a2_token_before_reconnect).get("ok",false)
	print("AUTH_LOGOUT_POST_BOB_TOKEN_EVIDENCE ",JSON.stringify({"a1_revoked":a1_server_token_revoked_after_bob,"a2_valid":a2_server_token_valid_after_bob}))
	if not check(a1_server_token_revoked_after_bob and a2_server_token_valid_after_bob,"After Bob's login A1 remains revoked and A2's independent Alice token remains valid"):return false
	var replacement_bob_server_peer_ref: WeakRef=capture_server_peer_ref(replacement_peer_id)
	var logout_old_new_peer_evidence: Dictionary=retired_peer_identity_evidence(a1_server_peer_ref,replacement_bob_server_peer_ref,true,old_a1_peer_id,replacement_peer_id)
	var retired_old_binding_value: Variant=a1_binding_ref.get_ref() if a1_binding_ref!=null and is_instance_valid(a1_binding_ref) else null
	var replacement_bob_binding_value: Variant=bob_backend._fee_bindings.get(replacement_peer_id,null) if is_instance_valid(bob_backend) else null
	var logout_binding_not_reused: bool=not is_instance_valid(retired_old_binding_value) or (replacement_bob_binding_value is RefCounted and is_instance_valid(replacement_bob_binding_value) and not is_same(retired_old_binding_value,replacement_bob_binding_value))
	var replacement_bob_binding_current: bool=binding_ref_is_current(bob_backend,replacement_peer_id,bob_replacement_binding)
	retired_old_binding_value=null;replacement_bob_binding_value=null
	if not check(logout_old_new_peer_evidence.get("new_peer_is_distinct",false) and logout_binding_not_reused and replacement_bob_binding_current,"Bob's PIN login uses a new server peer/current binding distinct from the explicitly retired A1 peer and binding"):return false
	var bob_frozen_client_oracle: Dictionary=normalized_client_profile_oracle(bob_backend.session,bob_profile_frozen)
	if not check(not bob_frozen_client_oracle.is_empty() and replacement.state.full_profile()==bob_frozen_client_oracle and world_c.state.full_profile()==bob_frozen_client_oracle and bob_is_unchanged(),"Both Bob devices match the validated/normalized full native profile after the real account switch and startup barrier"):return false
	var bob_profile_before_alice_event: Dictionary=bob_backend.session._profile.duplicate(true)
	var bob_cache_before_alice_event: String=bob_backend.last_saved_payload
	var bob_serial_before_alice_event: int=bob_backend.quest_save_serial
	var bob_disk_before_alice_event: Dictionary=capture_bob_disk()
	var bob_writer_before_alice_event: int=bob_backend.writer_event_count
	var bob_writer_kinds_before_alice_event: Dictionary=bob_backend._writer_kind_snapshot()
	var bob_checkpoint_count_before_alice_event: int=bob_backend.ordinary_checkpoint_records.size()
	var bob_backend_profile_count_before_alice_event: int=bob_backend_profile_event_count
	var bob_resume_writes_before_alice_event: int=bob_backend.resume_writes
	var bob_event_client_oracle: Dictionary=normalized_client_profile_oracle(bob_backend.session,bob_profile_before_alice_event)
	var alice_event_baseline: Dictionary=capture_profile_event_baseline("before_alice_event_after_switch")
	var alice_backend_profile_event_baseline: int=alice_backend.profile_event_count
	var alice_points_before: int=int(alice_backend.session._profile.player.get("stat_points",0))
	var gm_profile_before: Dictionary=alice_backend.session._profile.duplicate(true)
	var gm_profile_expected: Dictionary=gm_profile_before.duplicate(true)
	var gm_old_bonus: Variant=gm_profile_expected.get("gm_bonus_points",0)
	var gm_player_value: Variant=gm_profile_expected.get("player",null)
	var gm_player: Dictionary=gm_player_value if gm_player_value is Dictionary else {}
	var gm_allocated_value: Variant=gm_player.get("allocated_stats",null)
	var gm_allocated: Dictionary=gm_allocated_value if gm_allocated_value is Dictionary else {}
	var gm_rebirth_value: Variant=gm_profile_expected.get("rebirth",{})
	var gm_rebirth: Dictionary=gm_rebirth_value if gm_rebirth_value is Dictionary else {}
	var gm_bonus_int: int=int(gm_old_bonus)+1 if gm_old_bonus is int else -1
	var gm_assigned: int=0
	for stat_value in gm_allocated.values():
		if stat_value is int:gm_assigned+=int(stat_value)
		else:gm_assigned=-1000000000;break
	var gm_round_points_value: Variant=gm_rebirth.get("round_points",0)
	var gm_rebirth_valid: bool=gm_rebirth_value is Dictionary and (gm_rebirth.get("history",null)!="natural" or gm_round_points_value is int)
	var gm_round_points: int=int(gm_round_points_value) if gm_rebirth.get("history",null)=="natural" and gm_round_points_value is int else 0
	var gm_expected_points: int=maxi(0,3*(int(gm_player.get("level",0))-1)+gm_bonus_int+gm_round_points-gm_assigned) if gm_player.get("level",null) is int and gm_bonus_int>=0 and gm_assigned>=0 else -1
	var gm_expected_valid: bool=gm_player_value is Dictionary and gm_allocated_value is Dictionary and gm_rebirth_valid and gm_old_bonus is int and gm_expected_points>=0
	if gm_expected_valid:
		gm_profile_expected["gm_bonus_points"]=gm_bonus_int
		gm_profile_expected["gm_modified"]=true
		gm_player["gm_modified"]=true
		gm_player["stat_points"]=gm_expected_points
		gm_profile_expected["player"]=gm_player
		gm_expected_valid=alice_backend.session._valid_profile(gm_profile_expected)
	var gm_cache_before: String=alice_backend.last_saved_payload
	var gm_serial_before: int=alice_backend.quest_save_serial
	var gm_disk_before: Dictionary=alice_backend._disk_set(alice_save_path)
	var gm_disk_primary: Variant=gm_disk_before.get("primary",null)
	var gm_disk_primary_bytes: Variant=gm_disk_primary.get("bytes",null) if gm_disk_primary is Dictionary else null
	var gm_precommit_disk_matches_cache: bool=gm_disk_primary is Dictionary and gm_disk_primary.get("ok",null) is bool and gm_disk_primary.ok and gm_disk_primary_bytes is PackedByteArray and gm_disk_primary_bytes==gm_cache_before.to_utf8_buffer()
	var gm_precommit_cache_matches_native: bool=gm_expected_valid and validated_payload(gm_cache_before,gm_profile_before,"authenticated pre-GM full profile/cache baseline")
	if not check(gm_precommit_disk_matches_cache and gm_precommit_cache_matches_native,"GM save oracle starts from the independently expected native profile and exact validated cache/primary bytes"):return false
	var gm_checkpoint_baseline: int=alice_backend.ordinary_checkpoint_records.size()
	alice_backend.expected_profile_save_phase="gm_grant_points"
	alice_backend.expected_profile_save_native=gm_profile_expected.duplicate(true) if gm_expected_valid else {}
	var alice_event_reply: Dictionary=await auth_rpc(link_b,{"type":"gm_grant_points","amount":1})
	alice_backend.expected_profile_save_phase=""
	alice_backend.expected_profile_save_native.clear()
	var gm_checkpoint_count: int=alice_backend.ordinary_checkpoint_records.size()-gm_checkpoint_baseline
	var gm_checkpoint_record: Variant=alice_backend.ordinary_checkpoint_records.back() if gm_checkpoint_count==1 and not alice_backend.ordinary_checkpoint_records.is_empty() else null
	var gm_checkpoint_valid: bool=gm_expected_valid and gm_checkpoint_record is Dictionary and alice_backend._checkpoint_record_ok(gm_checkpoint_record) and gm_checkpoint_record.get("classification",null)=="gm_grant_points_commit" and gm_checkpoint_record.get("native_before",null)==gm_profile_expected and gm_checkpoint_record.get("expected_native_after",null)==gm_profile_expected and gm_checkpoint_record.get("native_after",null)==gm_profile_expected and gm_checkpoint_record.get("cache_before",null)==gm_cache_before and gm_checkpoint_record.get("serial_before",null)==gm_serial_before and gm_checkpoint_record.get("disk_before",null)==gm_disk_before and validated_payload(gm_checkpoint_record.get("payload",null),gm_profile_expected,"authenticated GM points command commit")
	if not check(gm_checkpoint_count==1 and gm_checkpoint_valid,"The independently derived GM points command is exactly one separately classified durable profile mutation"):return false
	if not check(alice_event_reply.get("ok",false) and alice_backend.session._profile==gm_profile_expected and int(alice_backend.session._profile.player.stat_points)==alice_points_before+1,"Alice A2 performs a real Alice-only backend command after A1 has switched to Bob"):return false
	if not await Wait.settle(self,world_b):return check(false,"Alice A2 settles after its own-profile event")
	if not await Wait.settle(self,world_a):return check(false,"Replacement Bob scene settles after the unrelated Alice event")
	if not await Wait.settle(self,world_c):return check(false,"Bob's original scene settles after the unrelated Alice event")
	var alice_bob_profile_event_diagnostic: Dictionary=_alice_bob_profile_event_diagnostic(alice_event_baseline,alice_backend_profile_event_baseline,alice_event_reply)
	print("AUTH_ALICE_BOB_PROFILE_EVENT_DIAGNOSTIC ",JSON.stringify(alice_bob_profile_event_diagnostic))
	if not check(profile_event_delta(alice_event_baseline,"alice_a2")>0 and profile_event_delta(alice_event_baseline,"bob_original")==0 and profile_event_delta(alice_event_baseline,"bob_replacement")==0,"Alice's profile-event counter advances only on Alice A2, not either Bob connection"):return false
	var bob_zero_write_delta_after_startup: bool=bob_backend.writer_event_count==bob_writer_before_alice_event and bob_backend.writer_event_count==bob_backend.post_startup_writer_total and bob_backend._writer_kind_snapshot()==bob_writer_kinds_before_alice_event and bob_backend.writer_kind_counts.get("save_profile_boundary",null)==bob_backend.post_startup_save_kind_total and bob_backend.writer_kind_counts.get("loot_settlement_written",null)==bob_backend.post_startup_settlement_kind_total and bob_backend.ordinary_checkpoint_records.size()==bob_checkpoint_count_before_alice_event and bob_backend.ordinary_checkpoint_records.size()==bob_backend.post_startup_checkpoint_total and bob_backend_profile_event_count==bob_backend_profile_count_before_alice_event and bob_backend_profile_event_count==bob_backend.post_startup_profile_event_total and bob_backend.resume_writes==bob_resume_writes_before_alice_event and bob_backend.resume_writes==bob_backend.post_startup_resume_write_total and not bob_backend.ordinary_checkpoint_overflow and not bob_backend.startup_side_effect_overflow and bob_backend.startup_side_effect_error.is_empty()
	if not check(not bob_event_client_oracle.is_empty() and world_a.state.full_profile()==bob_event_client_oracle and world_c.state.full_profile()==bob_event_client_oracle and bob_backend.session._profile==bob_profile_before_alice_event and bob_backend.last_saved_payload==bob_cache_before_alice_event and bob_backend.quest_save_serial==bob_serial_before_alice_event and bob_backend.quest_save_serial==bob_backend.post_startup_serial and capture_bob_disk()==bob_disk_before_alice_event and bob_zero_write_delta_after_startup,"Cross-account event routing leaves both Bob ClientState DTOs/native/cache/serial/primary/backup/tmp unchanged and adds zero Bob profile, settlement, resume or release-log writes after the verified startup baseline"):return false
	if not check(hub.backend_of(a2_reconnected_server_peer_id)==alice_backend and hub.backend_of(replacement_peer_id)==bob_backend and hub.backend_of(bob_server_peer_id)==bob_backend,"Hub connection ownership remains Alice/Alice→Alice Backend and Bob/Bob→Bob Backend"):return false
	var final_writer_oracle_ok: bool=alice_backend._writer_counts_reconcile() and alice_backend._checkpoint_count_reconciles() and alice_backend._checkpoint_records_valid_from(0) and alice_backend.writer_kind_counts.get("loot_settlement_written",null) is int and alice_backend.writer_kind_counts.loot_settlement_written==3
	if not final_writer_oracle_ok:
		print("AUTH_PUBLIC_LOOT_FINAL_WRITER_DIAGNOSTIC ",JSON.stringify({"writer_event_count":alice_backend.writer_event_count,"writer_records_count":alice_backend.writer_records.size(),"writer_kind_counts":alice_backend._writer_kind_snapshot(),"settlement_records":alice_backend.writer_records.size(),"checkpoint_records":alice_backend._checkpoint_summary_from(0),"checkpoint_records_reconciled":alice_backend._checkpoint_count_reconciles(),"writer_counts_reconciled":alice_backend._writer_counts_reconcile(),"all_checkpoint_records_valid":alice_backend._checkpoint_records_valid_from(0)}))
	return check(final_writer_oracle_ok,"Every observed writer callback through account-switch cleanup has one independently validated settlement or profile-save classification")

func auth_teardown_all() -> bool:
	var worlds_before_free: Array = []
	for world in worlds:
		if is_instance_valid(world):
			worlds_before_free.append(world.get_instance_id())
			if is_instance_valid(world.link) and world.link.get("_closed")!=true:world.link.close()
			world.stop_sounds()
			world.queue_free()
	# Failure cleanup closes still-owned live worlds only after the business
	# assertions have returned. It is not evidence for old A1 natural retirement.
	if is_instance_valid(link_a) and link_a.get("_closed")!=true:link_a.close()
	if is_instance_valid(server) and is_instance_valid(hub):
		var peers_retired: bool=await Wait.until(self,func():return server.clients().is_empty() and hub._connections.is_empty(),60.0)
		auth_teardown["peer_retirement_wait"]=peers_retired
	if is_instance_valid(hub):
		for profile_id in hub.backends:
			var backend_value: Variant=hub.backends.get(profile_id,null)
			if backend_value is AuthLootBackend and is_instance_valid(backend_value):backend_value.observe=false
	if is_instance_valid(server):server.stop()
	if is_instance_valid(hub):
		hub.shut_down()
		var final_profiles: Dictionary={}
		var all_profiles_saved: bool=true
		var all_profile_locks_released: bool=true
		var all_profile_paths_preserved: bool=true
		for profile_id in hub.backends:
			var backend_value: Variant=hub.backends.get(profile_id,null)
			if not backend_value is AuthLootBackend or not is_instance_valid(backend_value):
				all_profiles_saved=false
				all_profile_locks_released=false
				all_profile_paths_preserved=false
				continue
			var backend: Variant=backend_value
			var backend_path: String=backend.save_path
			var disk: Dictionary=backend._disk_set(backend_path)
			var validated: Dictionary=ProfileCompare.validated_copy(backend.session,backend.last_saved_payload)
			var native_profile: Dictionary=backend.session._profile.duplicate(true)
			var primary: Variant=disk.get("primary",{})
			var temporary: Variant=disk.get("tmp",{})
			var primary_matches: bool=primary is Dictionary and primary.get("ok",null) is bool and primary.get("ok",false) and primary.get("bytes",null) is PackedByteArray and primary.bytes.get_string_from_utf8()==backend.last_saved_payload
			var native_matches: bool=validated.get("ok",null) is bool and validated.get("ok",false) and validated.get("profile",null) is Dictionary and validated.profile==backend.session._normalize_numbers(native_profile.duplicate(true))
			var tmp_absent: bool=temporary is Dictionary and temporary.get("exists",null) is bool and not temporary.get("exists",true)
			var saved: bool=not backend_path.is_empty() and native_matches and primary_matches and tmp_absent
			var lock_released: bool=not backend_path.is_empty() and SaveLockType.holder_pid(backend_path)==0
			var path_preserved: bool=not backend_path.is_empty() and FileAccess.file_exists(backend_path)
			all_profiles_saved=all_profiles_saved and saved
			all_profile_locks_released=all_profile_locks_released and lock_released
			all_profile_paths_preserved=all_profile_paths_preserved and path_preserved
			final_profiles[str(profile_id)]={"path":backend_path,"native_profile":native_profile,"cache":backend.last_saved_payload,"serial":backend.quest_save_serial,"disk":disk,"validated":validated,"native_matches":native_matches,"primary_matches_cache":primary_matches,"tmp_absent":tmp_absent,"saved":saved,"save_lock_released":lock_released,"save_path_preserved":path_preserved}
		auth_teardown["profiles"]=final_profiles
		auth_teardown["both_native_cache_primary_valid"]=all_profiles_saved
		auth_teardown["save_locks_released"]=all_profile_locks_released
		auth_teardown["save_paths_preserved"]=all_profile_paths_preserved
		var shutdown_state_ok: bool=check(all_profiles_saved and all_profile_locks_released and all_profile_paths_preserved,"Graceful Hub shutdown leaves every opened native profile validated against its exact primary/cache, preserves saves and releases every real SaveLock")
		auth_teardown["shutdown_state_ok"]=shutdown_state_ok
	if is_instance_valid(server):server.queue_free()
	if is_instance_valid(hub):hub.queue_free()
	var nodes_retired: bool=await Wait.until(self,func():
		if is_instance_valid(server) or is_instance_valid(hub):return false
		for world_id in worlds_before_free:
			if is_instance_id_valid(world_id):return false
		return true,60.0)
	auth_teardown["nodes_retired"]=nodes_retired
	return check(nodes_retired and auth_teardown.get("peer_retirement_wait",false) and auth_teardown.get("save_paths_preserved",false) and auth_teardown.get("both_native_cache_primary_valid",false) and auth_teardown.get("save_locks_released",false) and auth_teardown.get("shutdown_state_ok",false),"All scene/link owners and Hub/server retire while every opened full-profile save remains valid and its SaveLock is released")

func run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i.ZERO
	var scenario_ok: bool=await authenticate_and_start_stop()
	if not scenario_ok and failures==0:check(false,"Authenticated public-loot scenario stopped before a named assertion")
	var before_teardown: Dictionary=capture_auth_audit("PASS" if scenario_ok else "FAIL")
	var teardown_ok: bool=await auth_teardown_all()
	var after_teardown: Dictionary=capture_auth_audit("PASS" if scenario_ok and teardown_ok else "FAIL")
	before_teardown["teardown_result"]=auth_teardown.duplicate(true)
	before_teardown["after_teardown"]=after_teardown
	if not teardown_ok:scenario_ok=false
	var audit_ok: bool=write_audit(before_teardown)
	print("AUTHENTICATED PUBLIC LOOT REMOTE UI: %d failures; real PIN/Hub/server peer bindings, A1/A2 shared Alice Backend, Bob isolation, E1/Stop full-profile+DTO+disk oracle, token reconnect before explicit logout; natural route/battle/drop/P3/2760 proof=false"%failures)
	quit(0 if scenario_ok and teardown_ok and audit_ok and failures==0 else 1)

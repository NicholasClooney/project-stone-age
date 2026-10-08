extends "res://tests/support/fee_loaded_baseline_fault_session.gd"
var snapshot_mode := ""
var armed := false
var snapshot_faults := 0
var nested_loaded := true
var wrong_denied := false
var original_receipt: Dictionary = {}
var loaded_value: Dictionary = {}
func load_game(path: String) -> bool:
	var ok: bool = super.load_game(path)
	if ok:
		armed = true
		original_receipt = _fee_loaded_receipt
		loaded_value = _profile.duplicate(true)
	return ok
func snapshot() -> Dictionary:
	var result: Dictionary = super.snapshot()
	if not armed:return result
	armed = false
	snapshot_faults += 1
	var b = host.get_ref()
	match snapshot_mode:
		"wrong_handle":wrong_denied = not _finish_fee_loaded_storage_normalization(RefCounted.new(), b) and _begin_fee_loaded_storage_normalization(_fee_loaded_receipt, b) == null
		"gold":_profile.player.gold += 1
		"gold_type":_profile.player.gold = float(_profile.player.gold)
		"revision_type":_profile.item_storage_revision = 0.0
		"ref":_profile = _profile.duplicate(true)
		"receipt_copy":_fee_loaded_receipt = _fee_loaded_receipt.duplicate(false)
		"token":_fee_loaded_receipt.token = RefCounted.new()
		"used":_fee_loaded_receipt.used = true
		"serial":b.quest_save_serial += 1
		"path":b.save_path += ".next"
		"timer":b.quest_loot = preload("res://server/quest_auto_loot.gd").new()
		"nested_failure":nested_loaded = b.load_profile(b.resume_path + ".missing")
		"drop_item":_profile.erase("item_storage")
		"drop_legacy":_profile.erase("legacy_item_storage")
		"drop_revision":_profile.erase("item_storage_revision")
	return _profile.duplicate(true)

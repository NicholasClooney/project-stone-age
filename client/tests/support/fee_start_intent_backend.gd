extends "res://server/backend.gd"
## Test-only true gate. No field scheduler or protected source stubs.
var mode := ""
var enabled := true
var installs := 0
var candidates: Array = []
var inner_result: Dictionary = {}
var nested_result: Dictionary = {}
var forged_take: Dictionary = {}
var entry_identity: RefCounted
func _fee_start_intent_enabled()->bool:return enabled
func _begin_fee_start_journal_frame(candidate:Variant)->Dictionary:
 candidates.append(candidate.duplicate(true))
 if mode=="candidate_drift":candidate.player.gold+=1
 return super._begin_fee_start_journal_frame(candidate)
func _persist_fee_start_journal_pair(handle:Variant)->Dictionary:
 if mode=="public_ok_only":return {"ok":true,"pair_verified":true,"installed":true}
 if mode=="nested":nested_result=handle_command_again()
 inner_result=super._persist_fee_start_journal_pair(handle)
 if mode=="after_persist_binding":fee_attach(71)
 if mode=="after_persist_profile_ref":session._profile=session._profile.duplicate(true)
 if mode=="wrong_take":forged_take=_fee_start_journal_writer.take_start(self,RefCounted.new(),RefCounted.new())
 if mode=="wrapper_false":return {"ok":false,"pair_verified":false}
 if mode=="wrapper_true":return {"ok":true,"pair_verified":true,"installed":true}
 return inner_result
func handle_command_again()->Dictionary:
 return handle({"type":"quest_auto_start","seq":92,"quest_id":2,"client":"nested","_quest_connection":71})
func publish()->void:
 if _fee_start_intent.has_call() and quest_auto.running:
  installs+=1
  if mode=="publish_binding":fee_attach(71)
 super.publish()

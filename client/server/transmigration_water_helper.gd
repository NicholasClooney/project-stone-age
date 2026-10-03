extends RefCounted
## Stage-two ownership slot. This chain is not active yet.
func stage_key(_helper, _backend) -> Array:
 return []
func steps(_helper, _backend, _profile:Dictionary, quest:Dictionary) -> void:
 quest.blocked_reason="转生主线尚未开放"
func can_visit(_helper, _backend, _step:Dictionary) -> bool:
 return false

extends "res://tests/quest_auto_munde_request9_keyword_route_test.gd"
## Codec-only entry: overrides the suite lifecycle and invokes only the pure
## synthetic codec contract. codec_check() never calls write_trace().
func _initialize() -> void:
	var ok: bool = native_variant_trace_contract_checks()
	print("MUNDE CODEC ONLY: %d assertions, %d failures" % [assertions,failures])
	quit(0 if ok and failures == 0 else 1)

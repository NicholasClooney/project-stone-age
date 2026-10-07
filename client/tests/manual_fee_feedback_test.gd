extends SceneTree
## Standalone presentation regression; no server, save, transport or art import.
## This suite does not claim a real authenticated broadcast or rendered pixels.
const Feedback = preload("res://scripts/game/manual_fee_feedback.gd")
const Game = preload("res://scripts/game.gd")
class FixtureGame extends "res://scripts/game.gd":
	# Keep the real constructor and GameRemote dispatcher; omit only unrelated
	# map/UI startup, movement and profile-driven panel refresh in this fixture.
	func _ready() -> void:
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
	func _exit_tree() -> void:pass
	func _mark_ui_stale() -> void:pass
	func _on_automation_settings() -> void:pass
class FixtureLink extends RefCounted:
	signal message(event: Dictionary)
	var local := true
	func is_local() -> bool:return local

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func permit() -> Dictionary:
	return {"schema": 1, "scope": "profile", "origin": "manual", "owner": {"profile_id": "p", "character_id": "c"}, "transaction_id": "0123456789abcdef0123456789abcdef", "fee_kind": "undersea_permit200", "phase": "permit_purchase", "source_id": "genout/ss_1100_86_107", "currency": "stone", "amount": 200, "balance_before": 500, "balance_after": 300, "status": "committed", "durability": "disk", "save_serial": 1, "candidate_sha256": "a".repeat(64), "entitlement": "travel_pass"}

func gate() -> Dictionary:
	var fact := permit()
	fact.erase("entitlement")
	fact.merge({"fee_kind": "seimu300", "phase": "gate_crossing", "source_id": "genout/wpm_40_13_1@40:13:1", "amount": 300, "balance_after": 200, "destination": {"map_id": 31301, "cell": [10, 104]}}, true)
	return fact

func event(fact: Variant, text: String = "") -> Dictionary:
	return {"type": "quest_result", "v": 1, "text": text, "fee_fact": fact}

func run() -> void:
	for fact in [permit(), gate()]:
		check(Feedback.valid(fact, false), "native tagged fact")
		var wire = JSON.parse_string(JSON.stringify(fact))
		check(Feedback.valid(wire, true), "actual JSON round trip accepts integral doubles")
		check(not Feedback.valid(wire, false), "native rejects JSON doubles")
		for field in ["schema", "amount", "balance_before", "balance_after", "save_serial"]:
			for bad in [true, false, "1", null, -1, 0.5, NAN, INF, -INF, 9223372036854775808.0]:
				var broken: Dictionary = fact.duplicate(true)
				broken[field] = bad
				check(not Feedback.valid(broken, true), "reject malformed JSON number: " + field)
				check(not Feedback.valid(broken, false), "reject malformed native number: " + field)
			var floating: Dictionary = fact.duplicate(true)
			floating[field] = float(floating[field])
			check(not Feedback.valid(floating, false), "native float shape: " + field)
		for key in fact.keys():
			var missing: Dictionary = fact.duplicate(true)
			missing.erase(key)
			check(not Feedback.valid(missing, false), "missing " + key)
		for extra in ["run_id", "step_id", "revision", "attempt_id", "ticket_uid", "consumed_ticket_uid", "item_id", "connection", "open_id", "token"]:
			var extended: Dictionary = fact.duplicate(true)
			extended[extra] = ""
			check(not Feedback.valid(extended, false), "extra tag " + extra)
	for pair in [["status", "unknown"], ["status", "failed"], ["origin", "automatic"], ["fee_kind", "ticket_purchase"], ["phase", "gate_crossing"], ["source_id", "unknown"], ["scope", "connection"], ["currency", "gold"], ["durability", "fsync"], ["balance_after", 301], ["balance_before", 1000000001], ["transaction_id", "A".repeat(32)], ["candidate_sha256", "a".repeat(63)], ["entitlement", 2422]]:
		var broken := permit()
		broken[pair[0]] = pair[1]
		check(not Feedback.valid(broken, true), "bad tagged field " + str(pair))
	for bad_owner in [{}, {"profile_id": "p", "character_id": ""}, {"profile_id": "p", "character_id": 1}, {"profile_id": "p", "character_id": "c", "extra": "x"}, {"profile_id": "x".repeat(129), "character_id": "c"}]:
		var broken := permit()
		broken.owner = bad_owner
		check(not Feedback.valid(broken, false), "strict owner")
	for target in [{"map_id": 31301, "cell": [10.5, 104]}, {"map_id": true, "cell": [10, 104]}, {"map_id": 31301, "cell": [10, 104, 0]}, {"map_id": 31301, "cell": [10, 104], "extra": 0}, {"map_id": 31301, "cell": [10, 105]}]:
		var broken := gate()
		broken.destination = target
		check(not Feedback.valid(broken, true), "strict destination")
	var limit := permit()
	limit.save_serial = 9223372036854775807
	check(Feedback.valid(limit, false), "native exact int64 maximum")
	check(not Feedback.valid(JSON.parse_string(JSON.stringify(limit)), true), "rounded JSON int64 overflow fails closed")
	limit.save_serial = 9223372036854774784.0
	check(Feedback.valid(limit, true), "largest double integer below int64 boundary")
	limit.save_serial = 0
	limit.balance_before = 200
	limit.balance_after = 0
	limit.source_id = "genout/ss_4000_99_85"
	check(Feedback.valid(limit, false), "second merchant and zero lower bounds")
	var ui := Feedback.new()
	var owner := {"profile_id": "p", "character_id": "c", "player": {"gold": 999}}
	var original := "原售证：永久海底通行资格已生效，扣除200石币，提交后余额300。"
	var input := event(permit(), original)
	var preserved: Dictionary = input.duplicate(true)
	var profile_before: Dictionary = owner.duplicate(true)
	var shown: Dictionary = ui.consume(input, owner, false)
	check(shown.text == original + "\n本次提交已写入存档。", "preserve original amount exactly once and disk distinction")
	check(input == preserved and owner == profile_before, "never mutate event or current snapshot")
	check(ui.consume(input, owner, false).is_empty(), "same transaction delivered twice is silent")
	check(not Feedback.new().consume(input, owner, false).is_empty(), "another device independently displays broadcast")
	check(ui.consume(input, {"profile_id": "p", "character_id": "next"}, false).is_empty(), "late previous owner cannot label current character")
	check(ui.consume(input, owner, false).is_empty(), "owner switch does not discard recent dedupe")
	check(ui.stale_text(owner).is_empty(), "same owner snapshot retains hint")
	check(ui.stale_text({"profile_id": "p", "character_id": "next"}) == shown.text, "owner change retires exactly the prior fee text")
	check(ui.stale_text(owner).is_empty(), "retirement is consumed once")
	check(ui.consume(input, owner, false).is_empty(), "retirement keeps recent dedupe")
	var next := permit()
	next.transaction_id = "b".repeat(32)
	next.durability = "memory"
	shown = ui.consume(event(next), owner, false)
	check(shown.text.contains("扣除200石币") and shown.text.contains("尚未保存到磁盘") and not shown.text.contains("已写入存档"), "new transaction same amount displays memory only")
	shown = ui.consume(event(gate()), owner, false)
	check(shown.text.contains("扣除300石币") and shown.text.contains("提交后余额200"), "phase participates in dedupe and gate amount remains original")
	for invalid in [null, {}, true, {"status": "unknown"}]:
		check(ui.consume(event(invalid, "旧文本"), owner, false) == {"text": "旧文本"}, "malformed fact adds no committed feedback")
	check(ui.consume({"text": "旧服务器"}, owner, false) == {"text": "旧服务器"}, "old server text compatibility")
	var collision := Feedback.new()
	for ids in [["a:b", "c"], ["a", "b:c"]]:
		var fact := permit()
		fact.owner = {"profile_id": ids[0], "character_id": ids[1]}
		check(not collision.consume(event(fact), fact.owner, false).is_empty(), "structured owner tuple avoids delimiter collision")
	var bounded := Feedback.new()
	for index in range(Feedback.MAX_SEEN + 1):
		var fact := permit()
		fact.transaction_id = "%032x" % index
		bounded.consume(event(fact), owner, false)
	check(bounded.seen.size() == Feedback.MAX_SEEN, "bounded per-scene dedupe memory")
	var evicted := permit()
	evicted.transaction_id = "%032x" % 0
	check(not bounded.consume(event(evicted), owner, false).is_empty(), "explicit FIFO horizon, no durable exactly-once claim")
	dispatcher_cases()
	print("MANUAL FEE FEEDBACK: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

## Handwritten frozen-contract events: no real charge, socket or authentication.
func dispatcher_cases() -> void:
	for local in [true, false]:
		# The real constructor chooses WsLink without connecting; _ready is stubbed.
		var previous_url: String = Game.server_url_override
		Game.server_url_override = "ws://127.0.0.1:1"
		var game := FixtureGame.new()
		Game.server_url_override = previous_url
		var link := FixtureLink.new()
		link.local = local
		game.link = link
		# Same ordering as GameScene._init: state.apply connects before dispatcher.
		# State is the real ClientState, and both wrapper and GameRemote are real.
		link.message.connect(game.state.apply)
		link.message.connect(game._on_backend_message)
		game.data = {"map_id": 1100}
		game.message = Label.new()
		game.battle_view = Control.new()
		game.add_child(game.message)
		game.add_child(game.battle_view)
		root.add_child(game)
		check(game.backend == null, "fixture has no backend or real payment")
		var profile := {"profile_id": "p", "character_id": "c", "player": {"gold": 999}}
		link.message.emit(profile_event(profile, "snapshot"))
		check(game.state.profile == profile, "real snapshot state applied before event callback")
		var fact := permit()
		var delivered: Dictionary = event(fact)
		if not local:delivered = JSON.parse_string(JSON.stringify(delivered))
		link.message.emit(delivered)
		var fee_text: String = game.message.text
		check(fee_text.contains("扣除200石币") and fee_text.contains("本次提交已写入存档") and game.last_adventure_message == fee_text, "real dispatcher updates both text targets: " + str(local))
		check(game.state.profile == profile, "dispatcher does not replace authoritative profile")
		game.message.text = "后来消息"
		game.last_adventure_message = "后来任务消息"
		link.message.emit(delivered)
		check(game.message.text == "后来消息" and game.last_adventure_message == "后来任务消息", "repeated fact leaves later messages untouched")
		var changed := {"profile_id": "p", "character_id": "next", "player": {"gold": 777}}
		link.message.emit(profile_event(changed, "profile"))
		check(game.state.profile == changed and game.message.text == "后来消息" and game.last_adventure_message == "后来任务消息", "profile owner switch preserves unrelated later text")
		link.message.emit(delivered)
		check(game.message.text == "后来消息" and game.last_adventure_message == "后来任务消息", "late original owner cannot overwrite current messages")
		# Return to owner c; a new transaction can display, old transaction stays seen.
		link.message.emit(profile_event(profile, "snapshot"))
		link.message.emit(delivered)
		check(game.message.text == "后来消息", "switch back retains tuple dedupe")
		for kind in ["profile", "snapshot"]:
			fact.transaction_id = ("c" if kind == "profile" else "d").repeat(32)
			delivered = event(fact.duplicate(true))
			if not local:delivered = JSON.parse_string(JSON.stringify(delivered))
			link.message.emit(delivered)
			check(game.message.text.contains("扣除200石币") and game.message.text == game.last_adventure_message, "fresh transaction displays before owner switch")
			link.message.emit(profile_event(changed, kind))
			check(game.message.text.is_empty() and game.last_adventure_message.is_empty(), "real " + kind + " callback sees new owner and clears only fee text")
			link.message.emit(delivered)
			check(game.message.text.is_empty() and game.last_adventure_message.is_empty(), "late old-owner fact stays silent after " + kind)
			link.message.emit(profile_event(profile, "snapshot"))
		var numeric := permit()
		numeric.transaction_id = "e".repeat(32)
		numeric.amount = 200.0
		link.message.emit(event(numeric, "保留原文"))
		check(game.message.text == "保留原文" if local else game.message.text.contains("本次提交已写入存档"), "is_local selects strict native versus validated JSON numeric policy")
		game.free()

func profile_event(profile: Dictionary, kind: String) -> Dictionary:
	return {"type": kind, "rev": 1, "profile": profile.duplicate(true), "derived": {}, "options": {}, "battle": {}, "battle_open": false, "automation": {"running": false}}

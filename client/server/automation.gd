extends RefCounted
## Backend automation: auto battles (attack, capture, pet training), hunt
## scanning and the find-pet workflow. These run on the backend tick whether or
## not a client is attached. Settings come from the character profile
## (scripts/automation_settings.gd); clients start runs and present status and
## events. Ported from the former client loops without rule changes.
const GameSession = preload("res://server/game_session.gd")
const Policy = preload("res://scripts/battle_auto_policy.gd")
const Progression = preload("res://server/progression.gd")
const HuntRules = preload("res://scripts/pet_hunt_rules.gd")
const StatFilter = preload("res://scripts/pet_stat_filter.gd")
const KeepRule = preload("res://scripts/keep_rule.gd")
const EncounterCatalog = preload("res://server/encounter_catalog.gd")
const TroopArt = preload("res://server/troop_art.gd")
const AutomationSettings = preload("res://scripts/automation_settings.gd")
const FastHunt = preload("res://server/fast_hunt.gd")
const ServerSettings = preload("res://server/server_settings.gd")
const FastHuntShare = preload("res://server/fast_hunt_share.gd")
const Rarity = preload("res://scripts/showcase_rarity.gd")
const ReleaseLog = preload("res://server/release_log.gd")
const BattleForecast = preload("res://server/battle_forecast.gd")
## A presenting client may slow automation to its animation, never stall it.
const PRESENT_TIMEOUT_MSEC := 5000
const HUNT_FRAME_BUDGET_USEC := 12000
const COMPACT_BUDGET_USEC := 12000
const HUNT_MAX_BACKLOG_SECONDS := 0.1
## Pace of an uncompacted run when the starting device names no playback speed.
const DEFAULT_SPEED := 8.0

var backend
## How many backends share this process's main thread for automation work
## now (server/profile_hub.gd sets it every frame). Compact battles and
## GDScript hunt scans each get 1/budget_share of their frame budget, so five
## busy profiles still spend about 12 ms per frame in total, not 60.
var budget_share := 1

## This frame's slice of `full` microseconds.
func frame_budget(full: int) -> int:
	return maxi(1000,full/maxi(1,budget_share))

## The server log, prefixed with the account on a multi-profile server.
func log_line(text: String) -> void:
	var account := str(backend.get("account_name")) if backend!=null and backend.get("account_name")!=null else ""
	print(("[%s] " % account if not account.is_empty() else "")+text)

## Whether this backend spends a frame budget now: compact battles, or a hunt
## scanning in GDScript (the native helper scans on its own threads).
func busy() -> bool:
	return (running and bool(settings.get("compact",false)) and not party_waiting()) or (hunt_running and not fast_hunt.running())

## A party leader's run (LAN phase 4c) has sent its command for the party
## battle's turn (or its player is down) and waits for the others: a member
## commanding by hand, or the 45 s turn timer. Nothing to do until then.
func party_waiting() -> bool:
	return backend.battle_open and backend.party_battle() and backend.battle.waiting_for_others()

## Tests drive step() themselves when false.
var auto_tick := true
## False when no client presents battles; paced waits are then skipped.
var client_attached := true
var position_map := -1
var position_cell := Vector2i.ZERO

# ---- battle runner ---------------------------------------------------------
var running := false
## The current run's flat settings: the profile's effective training and
## capture settings, the starting device's playback speed and run-only forcing.
var settings: Dictionary = {"speed":DEFAULT_SPEED}
var single_battle := false
var capture_target := -1
var training_pet_id := ""
var training_pet_level := 120
var finish_after_capture := false
## Times in a row the pet being trained fell without gaining a level, and the
## level it had then; at TRAINING_FALL_LIMIT the run stops instead of looping.
var training_falls := 0
var training_fall_level := 0
const TRAINING_FALL_LIMIT := 20
var clone_override_active := false
var previous_clone_enabled := false
var compact_active := false
var battles := 0
var skipped := 0
var unavailable_streak := 0
var earned_xp := 0
var earned_pet_xp := 0
var turns := 0
var cooldown := 0.0
var origin_map := -1
var origin_cell := Vector2i.ZERO
var initial_level := 1
var stop_reason := ""
var starting_ride := -1
var turn_text := ""
var _presented_key := ""
var _shown_key := ""
var _shown_msec := 0

# ---- hunt scanning ---------------------------------------------------------
var hunt_running := false
var hunt_filter: Dictionary = {}
var hunt_catalog
var hunt_map := -1
var hunt_cell := Vector2i.ZERO
var hunt_rolls := 0
var hunt_inspected := 0
var hunt_best := -9
## Pets that met the hunt's conditions in a troop with stronger enemies and
## were passed over (只进无其他敌人的遇敌).
var hunt_mixed_skips := 0
var hunt_elapsed := 0.0
var hunt_credit := 0.0
var hunt_started_usec := 0
var hunt_last_hit: Dictionary = {}
var hunt_status := ""
## Every roll of a run has its own seed (FastHunt.roll_seed(hunt_run_seed, i)),
## so the native helper can scan rolls in parallel and a roll can be replayed.
var hunt_run_seed := 0
var hunt_rng := RandomNumberGenerator.new()
## 本机极速模式: wanted by the hunt settings (hunt.fast), and whether the helper
## is scanning now. hunt_fast_note says why it is not, when wanted.
var fast_hunt := FastHunt.new()
var hunt_fast_wanted := false
var hunt_fast_note := ""
var _fast_base: Dictionary = {}
## Why this backend cannot run the helper ("" when it can), for the hunt window.
var fast_unavailable := FastHunt.unavailable_reason()
## 线程数 for the helper, the server's own setting (server_settings.gd; 0 = auto).
var fast_threads := ServerSettings.fast_hunt_threads()
## The computer's shared thread budget (server/fast_hunt_share.gd): set by a
## server (server_main.gd) or the desktop game; null keeps the helper on the
## whole budget, as tests and a lone backend expect.
var fast_share = null
## The share the running helper was started with, and when (share clock).
var _fast_launched_threads := 0
var _fast_launched_at := 0.0

# ---- find-pet workflow -----------------------------------------------------
var flow_phase := "idle"
var flow_reason := ""
var flow_pet_id := ""
var flow_map := -1
var flow_cell := Vector2i.ZERO
var flow_known_ids: Dictionary = {}
var flow_matched_actor: Dictionary = {}
var flow_matched_index := -1
## Where the matched pet came from ({run_seed, index, slot}), so a capture cut
## short by a server restart can roll the same troop again.
var flow_matched_roll: Dictionary = {}
var flow_capture_battle_id := ""
var flow_stat_filters: Dictionary = {}
## Profile overrides when the cycle started, for species not in flow_stat_filters.
var flow_settings_overrides: Dictionary = {}
var flow_target_filter: Dictionary = {}
var flow_hunt_request: Dictionary = {}
var flow_stored_count := 0
var flow_last_result := ""
var flow_last_stored_id := ""
var flow_last_stored_total := 0
# With hunt.stop_after other than 1 (run_stop_after), kept pets are stored and
# the hunt goes on until this run keeps that many (0 = until stopped manually).
var flow_kept_count := 0
var flow_collected_count := 0
var flow_pruned_count := 0
# Rejects stored by this run; rolling keep only ever prunes among these.
var flow_run_reject_ids: Array = []
# 保留规则 with 找宠时自动整理 (the filter's keep_rule.auto): pets it released
# this run, and how many of the species remain after the last tidy.
var flow_released_count := 0
var flow_held_count := 0
var flow_predicted_rejects := 0
## 抓宠记录 groups captures by find-pet run: set when a new (not continuing)
## cycle starts and kept across its restarts.
var flow_run_id := ""
## 后台搜宠 (hunt.showcase, default on; the name players see is
## AutomationSettings.SHOWCASE_NAME): the find-pet cycle keeps searching while
## the player watches a found pet's capture and 自动练级 to Lv.120; hits wait in
## `showcase_queue`, one queue per species (hunt.queue long each). Off, the
## cycle runs as before.
const SHOWCASE_QUEUE_MAX := 10
const SHOWCASE_LOG_MAX := 8
## A watching device plays a shown battle at its own speed; the runner waits
## for its turn to finish playing up to this long (a 1x group turn is long).
const SHOWN_PRESENT_TIMEOUT_MSEC := 60000
var flow_showcase := false
## Found hits waiting for their turn: {index, slot, run_seed, actor, troop,
## prediction, quality}. Every species has its own queue: kept as one array
## grouped by species (template id, ascending), each group best first by the
## species' ranking (_sort_queue), so the resume file keeps one list.
var showcase_queue: Array = []
## The species whose hit was taken last: the next capture takes the best hit
## of the next species with hits (round-robin, _take_queued).
var showcase_last_template := -1
var showcase_current: Dictionary = {}
## The battle now open is one the player watches (not compact).
var showcase_show_battle := false
## The info block's lines: {id, kind, text}, newest last.
var showcase_log: Array = []
var _showcase_log_serial := 0
var _flow_run_serial := 0
## 停止记录: every stop, pause and skip of the hunt and the find-pet cycle,
## drained by the backend into <save>.stop-log.jsonl (server/release_log.gd).
var stop_events: Array = []
## A failure the cycle can step past (see _skip_hit) skips the current hit;
## the same kind SKIP_LIMIT times in a row stops the cycle instead.
const SKIP_LIMIT := 3
## Why a capture battle ended without its pet when the cycle may simply try
## the next hit; any other runner stop needs the player.
const SKIPPABLE_BATTLE_STOPS := ["捕捉目标已倒下，已停止；不会改抓其他敌人","当前战斗不可继续捕捉，可能已达捕获数量上限","战斗未获胜","单场超过200回合，请手动处理","找不到可攻击目标"]
var flow_skip_kind := ""
var flow_skip_streak := 0
var flow_skipped_count := 0
var flow_skip_note := ""
var _stopping_cycle := false
var flow_best_predicted: Dictionary = {}
## 最高 − x thresholds (pet_stat_filter.gd resolve): per species, the best Lv120
## values among the player's own pets, recomputed when pet_signature changes;
## pets a survey picked and the cycle is about to catch count as well.
var _owned_maxima: Dictionary = {}
var _pets_key := ""
## The resolved thresholds the native helper was launched with; a change (a
## better pet arrived, or the player edited 属性条件) restarts it with the new ones.
var _fast_thresholds := ""
var _fast_held_items: Array = []
## Set by request_stop_cycle: the cycle stops once this pet is trained.
var flow_stop_pending := ""
## 摸底: a species with enabled 最高 − x conditions (relative mode) and no pet
## of its own has no 最高 to count from (fixed values, absolute mode, never
## survey). The cycle then scans that species with no threshold for
## survey_seconds of wall time, collecting candidates (pool kept by the
## species' 保留规则, as the helper does), replays them, and catches what the
## keep rule would keep of them. After that the thresholds roll as usual.
var survey_seconds: int = AutomationSettings.SURVEY_SECONDS
var survey_clock: Callable = Time.get_ticks_msec
## {} or {templates: [ids], started: msec, candidates: key -> candidate,
## runs: [run seeds in order]}; a candidate is {run_seed, index, slot,
## template_id, prediction, serial}.
var survey: Dictionary = {}
## Survey picks waiting for their capture when 后台搜宠 is off (with it on
## they wait in showcase_queue, marked survey).
var survey_picks: Array = []
## The last survey's result for the status: {candidates, picked, text}.
var survey_last: Dictionary = {}
## The pet the cycle is catching was picked by a survey: it counts as found.
var flow_target_survey := false
var timer_clock: Callable = Time.get_ticks_msec
var timer_started_msec := 0
var timer_frozen_seconds := 0.0
var timer_running := false

func _init(owner) -> void:
	backend = owner

# ---- commands --------------------------------------------------------------

func start(command: Dictionary) -> Dictionary:
	_set_position(command)
	match str(command.get("kind","")):
		"battle":return _start_battle_runner(command)
		"capture_battle":
			_set_speed(command)
			return _reply(start_capture_battle(int(command.get("target",-1)),bool(command.get("finish_battle",false)),command.get("settings",{})),stop_reason)
		"pet_train":
			_set_speed(command)
			return _reply(start_pet_training(str(command.get("pet_id","")),int(command.get("target_level",120)),command.get("settings",{})),stop_reason)
		"hunt":
			if hunt_running or running or flow_active():return _reply(false,"自动流程进行中")
			_load_settings(command)
			return _reply(start_hunt(hunt_request(command)),hunt_status)
		"find_pet":
			if flow_active():return _reply(false,"找宠流程进行中")
			# The cycle takes the profile's stat conditions (and follows the
			# player's later edits: apply_stat_filters). Older clients may still
			# send their own.
			flow_settings_overrides = backend.session.automation_settings()
			flow_stat_filters = AutomationSettings.stat_filters(flow_settings_overrides)
			flow_stat_filters.merge(_int_keys(command.get("stat_filters",{})),true)
			flow_hunt_request = hunt_request(command)
			_load_settings(command)
			return _reply(start_cycle(false),flow_reason)
	return {"ok":false,"reason":"unknown automation"}

## The run's settings from the profile, the device's playback speed and any
## run-only `settings` a command still carries (older clients, tests).
func _load_settings(command: Dictionary = {}) -> void:
	var speed := float(settings.get("speed",DEFAULT_SPEED))
	settings = profile_settings()
	settings.speed = speed
	_set_speed(command)
	if command.get("settings") is Dictionary:settings.merge(command.settings,true)

func profile_settings() -> Dictionary:
	return AutomationSettings.runner_settings(backend.session.automation_settings(),int(backend.session.snapshot().player.level))

func _set_speed(command: Dictionary) -> void:
	if command.has("speed"):settings.speed = clampf(float(command.speed),1.0,8.0)

## Hunt filter from the profile plus the templates this backend can present
## here; a command's own `filter` (older clients, tests) overrides fields.
func hunt_request(command: Dictionary = {}) -> Dictionary:
	var filter: Dictionary = AutomationSettings.hunt_filter(backend.session.automation_settings())
	var given = command.get("filter",{})
	if given is Dictionary:filter.merge(given,true)
	if not filter.has("usable"):filter.usable = usable_templates(bool(filter.level_one))
	return filter

## Capturable templates at the reported position whose art this backend has.
func usable_templates(level_one: bool) -> Array:
	var usable := []
	for item in HuntRules.candidates(backend.encounter_catalog,position_map,position_cell,level_one):
		var definition: Dictionary = backend.encounter_catalog.data.get("templates",{}).get(str(item.id),{})
		if TroopArt.can_render([{"sprite":int(definition.get("sprite",-1))}]):usable.append(int(item.id))
	return usable

## The profile's automation settings changed: a running capture follows the
## new capture settings at once (training settings apply from the next start),
## and a running find-pet cycle its new 属性条件 (apply_stat_filters).
func profile_settings_changed() -> void:
	if not (running or hunt_running or flow_active()):return
	var fresh := profile_settings()
	for key in ["capture_hp","capture_pet","capture_pet_id","capture_pet_max_level","capture_fallback_attempts","capture_fallback_rate","capture_fallback_hp"]:settings[key] = fresh[key]
	if flow_active():apply_stat_filters(backend.session.automation_settings())
	_emit_status()

## A running cycle takes the species' 属性条件 the player just changed
## (threshold mode, x, fixed values, 任一/全部, 保留规则 …): the hunt judges
## with them at once (the native helper restarts, since threshold_key
## changes), queued hits now below them are let go, and a 摸底 of a species
## that no longer needs one (switched to fixed values) ends without picks.
## Species the player did not touch keep what the cycle has (an older
## client's own filters too). The pet being caught or trained keeps the
## filter it was found with.
func apply_stat_filters(overrides: Dictionary) -> void:
	var before := flow_settings_overrides
	flow_settings_overrides = overrides.duplicate(true)
	var ids := {}
	for id in _dict_keys(before.get("stat_filters",{}))+_dict_keys(overrides.get("stat_filters",{})):ids[int(id)] = true
	var changed: Array = []
	for id in ids:
		var now := AutomationSettings.stat_filter(overrides,id)
		if JSON.stringify(now)==JSON.stringify(AutomationSettings.stat_filter(before,id)):continue
		flow_stat_filters[id] = now
		changed.append(id)
	if changed.is_empty():return
	refresh_maxima()
	if not survey.is_empty():
		var still: Array = survey.templates.filter(func(id):return StatFilter.needs_survey(raw_filter_for(int(id)),species_maxima(int(id))))
		if still.is_empty():
			survey = {}
			_showcase_line("survey","摸底取消：属性条件改后不再需要摸底（固定数值或未启用条件），直接按门槛找。")
		else:survey.templates = still
	var lines: Array = []
	for id in changed:
		var raw := raw_filter_for(id)
		lines.append("%s：%s" % [_template_name(id),StatFilter.describe_thresholds(raw,species_maxima(id)) if StatFilter.enabled(raw) else "未启用条件"])
	_showcase_line("settings","属性条件已更新，正在进行的找宠立即改用（%s）" % "；".join(lines))
	if not showcase_queue.is_empty():_prune_below_threshold()

static func _dict_keys(value: Variant) -> Array:
	return value.keys() if value is Dictionary else []

func update(command: Dictionary) -> Dictionary:
	if command.has("settings"):settings.merge(command.settings,true)
	if command.has("stat_filters"):flow_stat_filters = _int_keys(command.stat_filters)
	_emit_status()
	return {"ok":true}

func stop_request(reason: String) -> Dictionary:
	if flow_active():stop_cycle(reason)
	elif running:stop(reason)
	if hunt_running:stop_hunt(reason)
	return {"ok":true}

func command(name: String, arguments: Dictionary) -> Dictionary:
	match name:
		"stop_battle":
			if running:stop(str(arguments.get("reason","已手动停止")))
		"stop_hunt":
			if hunt_running:stop_hunt(str(arguments.get("reason","已停止")))
		"stop_flow":
			if bool(arguments.get("now",false)):stop_cycle(str(arguments.get("reason","已手动停止")))
			else:request_stop_cycle(str(arguments.get("reason","已手动停止")))
		"acquire_clone":acquire_clone_override()
		"release_clone":release_clone_override()
		"flow_step":flow_step()
		"hunt_scan":scan_once()
		"tick_battle":tick_battle(float(arguments.get("delta",0.0)))
		"complete_trained_pet":complete_trained_pet(arguments.get("found",{}))
		"scene_reload":return {"ok":true,"paused":position_changed(position_map,position_cell,true)}
		"hunt_process":
			if hunt_running:_hunt_process(float(arguments.get("delta",0.0)))
			else:_share_idle()
		"set":
			for key in arguments.get("fields",{}):set(key,arguments.fields[key])
			_emit_status()
	return {"ok":true}

func presented(battle_id: String, turn: int) -> void:
	_presented_key = "%s:%d" % [battle_id,turn]

func position_changed(map_id: int, cell: Vector2i, map_changed: bool = false) -> String:
	position_map = map_id
	position_cell = cell
	if not map_changed:return ""
	# A new map ends the current run; a defeat or travel pauses the workflow.
	var pause := ""
	if flow_active():
		pause = "战斗失败，流程已暂停。" if str(backend.battle.snapshot().get("outcome",""))=="defeat" else "地图发生变化，流程已暂停。"
		_record_stop("flow","暂停",pause,_involved_pet())
		freeze_timer()
		flow_phase = "paused"
		flow_reason = pause
	if hunt_running and pause.is_empty():_record_stop("hunt","停止","地图发生变化，筛选已停止。")
	hunt_running = false
	_share_idle()
	release_clone_override()
	running = false
	compact_active = false
	backend.set_capture_assist(false)
	_emit_status()
	return pause

# ---- tick ------------------------------------------------------------------

## Standalone backend tick. An in-process client drives the same three parts
## from its frame loop instead (tick_battle, hunt_process, flow_step).
func tick(delta: float) -> void:
	if not auto_tick:return
	try_resume()
	tick_battle(delta)
	if hunt_running:_hunt_process(delta)
	else:_share_idle()
	if flow_active():flow_step()

func tick_battle(delta: float) -> void:
	if not running:return
	# Compact battles have nothing to watch: run steps back to back within a frame budget.
	if bool(settings.compact) and (compact_active or not backend.battle_open):
		var until := Time.get_ticks_usec()+frame_budget(COMPACT_BUDGET_USEC)
		while running and (compact_active or not backend.battle_open) and Time.get_ticks_usec()<until and not party_waiting():step()
		return
	cooldown -= delta
	if cooldown > 0:return
	cooldown = 0.25/float(settings.speed)
	step()

## One battle-runner step.
func step() -> void:
	if not running:return
	if position_map!=origin_map or position_cell!=origin_cell:
		stop("位置发生变化");return
	var state: Dictionary = backend.battle.snapshot()
	if backend.battle_open:
		if not compact_active and not _presentation_done(state):return
		if not state.active:
			battles += 1
			turns = 0
			var outcome: String = state.outcome
			# A party battle settled when its last turn resolved, maybe after
			# this run's own command (LAN phase 4c).
			if backend.party_battle() and bool(backend.battle_state.get("settled",false)):record_result(backend.battle_state)
			_close_battle()
			if outcome=="defeat":
				# Defeat returns the player to the village and ends the run. An
				# attached client reports that arrival itself.
				if not client_attached:
					var pause := position_changed(backend.VILLAGE.map_id,Vector2i(backend.VILLAGE.x,backend.VILLAGE.y),true)
					if not pause.is_empty():_emit_event({"kind":"flow_paused","reason":pause})
				release_clone_override()
				running = false
				stop_reason = "战斗失败"
				_emit_status()
				return
			_emit_status()
			var clear_caught := int(state.get("clear_capture_target",-1))>=0 and bool(state.enemies[int(state.clear_capture_target)].get("captured",false))
			# A capture run leaves after the catch (no experience for the weaken
			# pet): escaping with the target caught is a finished capture.
			var target_caught: bool = capture_target>=0 and capture_target<state.enemies.size() and bool(state.enemies[capture_target].get("captured",false))
			if outcome not in ["win","captured"] and not (outcome=="escaped" and (clear_caught or target_caught)):stop("战斗未获胜");return
			if single_battle:stop("本场自动战斗已完成");return
			return
		if party_waiting():return
		# Reset before healing too, matching the forecast turn for turn.
		backend.set_capture_assist(str(settings.preset)=="capture")
		# The 恢复护符 heals the battle pet for free (no 气力): before any 精灵,
		# and before the 停机线 could stop the run.
		if not backend.party_battle() and bool(state.get("healing_available",false)) and int(state.get("pet_hp",0))>0 and int(state.get("pet_hp",0))*100<=int(state.get("pet_max_hp",1))*maxi(50,int(settings.hp)):
			backend.battle.set_pet_command("defend")
			var charmed: Dictionary = backend.battle_command({"action":"heal_pet","target":-1})
			turns += 1
			if charmed.get("settled",false):record_result(charmed)
			turn_text = "第 %d 回合 · 恢复护符治疗宠物" % turns
			_emit_status()
			return
		# 用精灵补血: a healing 精灵 while the 气力 lasts, before a 回复药 or a
		# stop (the player, its pet or mount at the line; in a party battle a
		# teammate too, or a fallen one with 复活精灵).
		if bool(settings.get("spirit",true)):
			var cast: Dictionary = Policy.spirit_choice(state,int(settings.hp),backend.party_battle(),int(settings.get("side_heal",50)))
			if not cast.is_empty():
				backend.battle.set_pet_command("defend")
				var healed: Dictionary = backend.battle_command({"action":str(cast.action),"target":int(cast.target)})
				turns += 1
				if healed.get("settled",false) and not backend.party_battle():record_result(healed)
				turn_text = "第 %d 回合 · 用精灵补血 · 气力 %d" % [turns,int(healed.get("player_mp",0))]
				_emit_status()
				return
		var reason := health_reason(state)
		if not reason.is_empty() and backend.party_battle():
			# A party leader heals instead of stopping the whole party: a
			# 回复药 for itself, the 恢复护符 for its pet (LAN phase 4c).
			var heal := party_heal(state)
			if not heal.is_empty():
				backend.battle.set_pet_command("defend")
				backend.battle_command({"action":heal,"target":-1})
				turns += 1
				turn_text = "第 %d 回合 · %s" % [turns,"喝回复药" if heal=="item" else "恢复护符治疗宠物"]
				_emit_status()
				return
			reason += heal_note(reason,bool(state.get("healing_available",false)))
		if not reason.is_empty() and bool(settings.get("spirit",true)):reason += spirit_note(reason,state)
		if not reason.is_empty():stop(reason);return
		if turns >= 200:stop("单场超过200回合，请手动处理");return
		if str(settings.preset)=="capture" and backend.session.snapshot().pets.size()>=GameSession.PET_CAPACITY:
			stop("宠物栏已满，请先腾出位置");return
		var decision: Dictionary
		# After the catch the run leaves: no enemy is defeated, so the weaken
		# pet earns no experience and stays under its level cap. A failed
		# escape guards and tries again next turn.
		if str(settings.preset)=="capture" and finish_after_capture and capture_target>=0 and capture_target<state.enemies.size() and state.enemies[capture_target].get("captured",false) and int(state.get("clear_capture_target",-1))<0:
			decision = {"action":"escape","pet":"defend","target":capture_target,"assist":true}
		else:decision = Policy.decide(state,settings,capture_target)
		if decision.has("stop"):stop(str(decision.stop));return
		backend.set_capture_assist(bool(decision.get("assist",str(settings.preset)=="capture")))
		# A disobeying pet only skips its action in a run (battle_session.gd).
		backend.battle.automated = true
		backend.battle.set_pet_command(str(decision.pet))
		var next: Dictionary = backend.battle_command({"action":str(decision.action),"target":int(decision.target),"pet_target":int(decision.target),"switch_pet":int(decision.get("switch",-2))})
		turns += 1
		if next.get("settled",false) and not backend.party_battle():record_result(next)
		turn_text = "第 %d 回合 · 体力 %d/%d · 气力 %d\n%s" % [turns,next.player_hp,next.player_max_hp,int(next.get("player_mp",0))," / ".join(next.events)]
		_emit_status()
		return
	# 练级保护 brings every carried pet back to full between battles.
	if (backend.session.restore_carried_pets() if bool(settings.get("protect",true)) else backend.session.heal_carried_pets()):
		backend.save()
		backend.publish()
	var p: Dictionary = backend.session.snapshot()
	if not training_pet_id.is_empty():
		var selected := -1
		for i in range(p.pets.size()):
			if str(p.pets[i].get("pet_id",""))==training_pet_id:selected = i;break
		if selected < 0:stop("目标宠物不在随身队伍");return
		if selected!=int(p.active_pet):stop("目标宠物不再出战");return
		if int(p.pets[selected].level)>=training_pet_level:stop("目标宠物已达到等级目标");return
		# A fallen pet earns no experience: training it on would loop forever.
		# 后台搜宠 revives its own pet between battles (a project convenience);
		# a stop asked for meanwhile ends the cycle here instead of after Lv.120.
		if int(p.pets[selected].get("hp",0))<=0:
			training_falls += 1
			if training_falls>=TRAINING_FALL_LIMIT:stop("目标宠物连续倒下%d次，这里的敌人对它太强，请换个地方练级" % TRAINING_FALL_LIMIT);return
			if flow_active() and flow_phase=="train" and flow_stop_pending.is_empty() and backend.session.revive_carried_pet(training_pet_id):
				backend.save()
				backend.publish()
				_showcase_line("retry","%s 倒下了，已救回，继续练级（第%d次）。" % [str(p.pets[selected].get("name","")),training_falls])
			else:stop("目标宠物已倒下");return
		elif int(p.pets[selected].level)>training_fall_level:
			training_falls = 0
			training_fall_level = int(p.pets[selected].level)
	if flow_active() and flow_phase=="train" and not flow_stop_pending.is_empty():stop_cycle("已停止：%s" % flow_stop_pending);return
	if int(settings.level) > 0 and int(p.player.level)>=int(settings.level):stop("已达到目标等级");return
	if battles>=int(settings.limit):stop("已达到战斗场次上限");return
	# A party leader (LAN phase 4c): the leader and every member are healed
	# (恢复护符, 回复药) and checked at their own 停机线 first.
	if backend.party_guard.is_valid():
		var why := str(backend.party_guard.call())
		if not why.is_empty():stop(why);return
	# 用精灵补血 between battles too: 治愈 / 滋润 are FIELD_ALL spells.
	if bool(settings.get("spirit",true)) and backend.session.spirit_heal_to_line(int(settings.hp),[int(backend.session._profile.active_pet),int(backend.session._profile.get("ride_pet",-1))]):
		backend.save()
		backend.publish()
	var reason := profile_health_reason()
	if not reason.is_empty():stop(reason);return

	compact_active = bool(settings.compact)
	_emit_status()
	backend.session.protect_pets = bool(settings.get("protect",true))
	var opened: Dictionary = backend.wild_encounter(origin_map,origin_cell) if backend.session.world_catalog.field(origin_map) else {"ok":false,"skipped":""}
	if not opened.ok:
		compact_active = false
		if str(opened.get("skipped",""))=="art":
			skipped += 1
			unavailable_streak += 1
			turn_text = "该敌群原版素材不可用，已跳过，无奖励。"
			if unavailable_streak >= 100:stop("连续100组缺素材，请更换区域")
			else:_emit_status()
			return
		stop("当前位置遇敌数据或条件不可用，请换个位置");return
	unavailable_streak = 0
	var battle_state: Dictionary = backend.battle.snapshot()
	starting_ride = int(battle_state.get("ride_pet",-1))
	capture_target = -1
	if str(settings.preset)=="capture":
		for i in range(battle_state.enemies.size()):
			if battle_state.enemies[i].get("can_capture",false) and int(battle_state.enemies[i].hp) > 0:capture_target = i;break
	backend.set_capture_assist(str(settings.preset)=="capture")
	_emit_status()

func _presentation_done(state: Dictionary) -> bool:
	if not client_attached:return true
	var key := "%s:%d" % [str(state.get("battle_id","")),int(state.get("turn",0))]
	if key==_presented_key:return true
	if key!=_shown_key:
		_shown_key = key
		_shown_msec = Time.get_ticks_msec()
	return Time.get_ticks_msec()-_shown_msec >= (SHOWN_PRESENT_TIMEOUT_MSEC if showcase_show_battle else PRESENT_TIMEOUT_MSEC)

func _close_battle() -> void:
	compact_active = false
	if backend.battle_open:backend.close_battle()

# ---- battle runner lifecycle -----------------------------------------------

func _start_battle_runner(command: Dictionary) -> Dictionary:
	_set_position(command)
	_load_settings(command)
	if command.has("capture_target"):capture_target = int(command.capture_target)
	start_training()
	return _reply(running,stop_reason)

func start_training() -> void:
	training_pet_id = ""
	finish_after_capture = false
	backend.session.experience_multiplier = int(settings.xp)
	single_battle = bool(backend.battle.snapshot().active) and backend.battle_open
	if not single_battle and not backend.session.world_catalog.field(position_map):
		stop_reason = "请先到野外再开始自动练级。"
		_emit_event({"kind":"battle_refused","reason":stop_reason})
		return
	origin_map = position_map
	origin_cell = position_cell
	initial_level = int(backend.session.snapshot().player.level)
	battles = 0;skipped = 0;unavailable_streak = 0;earned_xp = 0;earned_pet_xp = 0;turns = 0;cooldown = 0;stop_reason = "";starting_ride = -1;turn_text = ""
	if str(settings.preset)=="train_pet":
		if single_battle and backend.battle.snapshot().get("allies",[]).is_empty():
			stop_reason = "带宠升级请在遇敌前开启，以生成完整镜像队。"
			_emit_event({"kind":"battle_refused","reason":stop_reason})
			return
		acquire_clone_override()
	backend.set_capture_assist(str(settings.preset)=="capture")
	running = true
	backend.publish()
	_emit_status()

func start_capture_battle(target: int, finish_battle: bool = false, extra: Dictionary = {}) -> bool:
	if not backend.battle.snapshot().active:return false
	_load_settings({"settings":extra})
	capture_target = target
	settings.preset = "capture"
	start_training()
	finish_after_capture = finish_battle
	_emit_status()
	return running

## `overrides` replace the preset's defaults before the first battle opens.
func start_pet_training(pet_id: String, target_level_value: int = 120, extra: Dictionary = {}, overrides: Dictionary = {}) -> bool:
	if running or backend.battle.snapshot().active:return false
	var profile: Dictionary = backend.session.snapshot()
	var chosen := -1
	for i in range(profile.pets.size()):
		if str(profile.pets[i].get("pet_id",""))==pet_id:chosen = i;break
	if chosen < 0:stop_reason = "目标宠物不在随身队伍";return false
	if int(profile.get("ride_pet",-1))==chosen:stop_reason = "目标宠物正在骑乘，请先下骑";return false
	if not backend.session.select_pet(chosen):stop_reason = "无法让目标宠物出战";return false
	backend.publish()
	_load_settings({"settings":extra})
	settings.merge({"preset":"train_pet","speed":8.0,"xp":10,"compact":true,"level":0,"level_explicit":true},true)
	settings.merge(overrides,true)
	start_training()
	if not running:return false
	if training_pet_id!=pet_id:
		training_falls = 0
		training_fall_level = int(profile.pets[chosen].get("level",1))
	training_pet_id = pet_id
	training_pet_level = clampi(target_level_value,1,120)
	_emit_status()
	return true

## `line`: the 停机线 in percent; -1 is this run's (settings.hp), and then
## the mount the run started on counts too.
## 练级保护: a carried pet may fall (it still earns its experience and is
## brought back between battles), so only the player and the mount stop a run.
func health_reason(state: Dictionary, line: int = -1) -> String:
	var watched := state
	if bool(settings.get("protect",true)) and not backend.party_battle():
		watched = state.duplicate();watched.active_pet = -1
	return Policy.health_stop(watched,int(settings.hp) if line<0 else line,starting_ride if line<0 else -1)

## In a party battle, what heals this run's player at its 停机线: "item" (a
## 回复药) for the player, "heal_pet" (the 恢复护符, never used up) for the
## battle pet, or "" when nothing can (no potion left, no charm, the mount).
func party_heal(state: Dictionary) -> String:
	var line := int(settings.hp)
	var hp := int(state.player_hp)
	var max_hp := maxi(1,int(state.player_max_hp))
	if hp*100<=max_hp*line:
		return "item" if int(state.get("potions",0))>0 and hp<max_hp else ""
	var pet_hp := int(state.get("pet_hp",0))
	var pet_max := maxi(1,int(state.get("pet_max_hp",1)))
	if pet_hp>0 and pet_hp*100<=pet_max*line and bool(state.get("healing_available",false)):return "heal_pet"
	return ""

## After a health_reason with 用精灵补血 on: "，气力不足以用精灵" when a worn
## healing 精灵 could have healed that one (the player: any; a pet: 滋润 or
## 恩惠) but the 气力 is short; "" otherwise.
static func spirit_note(reason: String, state: Dictionary) -> String:
	var targets: Array = [0,1,8] if reason=="玩家体力达到停机线" else [1,8]
	for spirit in state.get("spirits",{}).values():
		if str(spirit.get("kind",""))=="recovery" and int(spirit.get("target",-1)) in targets:return "，气力不足以用精灵"
	return ""

## Why healing could not help, after a health_reason in a party.
static func heal_note(reason: String, charm: bool) -> String:
	if reason=="玩家体力达到停机线":return "，回复药已用完"
	return "，恢复护符只能治疗出战宠物" if charm else "，没有恢复护符"

func profile_health_reason(line: int = -1) -> String:
	var p: Dictionary = backend.session._profile
	return health_reason({"player_hp":p.player.hp,"player_max_hp":p.player.max_hp,"pets":p.pets,"active_pet":p.active_pet,"ride_pet":p.get("ride_pet",-1)},line)

## 练级保护 (training.protect) for the battle about to open (game_session.gd).
func _protect_pets() -> void:
	backend.session.protect_pets = bool(profile_settings().get("protect",true))

func stop(reason: String) -> void:
	release_clone_override()
	backend.session.protect_pets = false
	running = false
	stop_reason = reason
	backend.set_capture_assist(false)
	# A battle the player takes over obeys the full loyalty rules again.
	backend.battle.automated = false
	var takeover := false
	if compact_active and not backend.battle.snapshot().active:
		battles += 1
		_close_battle()
	if compact_active:
		# The battle continues under manual control in the full battle view.
		compact_active = false
		takeover = true
	_emit_status()
	_emit_event({"kind":"battle_stopped","reason":reason,"battles":battles,"takeover":takeover})

func record_result(state: Dictionary) -> void:
	earned_xp += int(state.get("xp",0))
	for amount in state.get("pet_reward_xp",[]):earned_pet_xp += int(amount)

func acquire_clone_override() -> void:
	if not clone_override_active:
		previous_clone_enabled = backend.session.clone_squad_enabled
		clone_override_active = true
	backend.session.clone_squad_enabled = true
	backend.publish()

func release_clone_override() -> void:
	backend.session.clone_best_others = false
	if not clone_override_active:return
	clone_override_active = false
	backend.session.clone_squad_enabled = previous_clone_enabled
	backend.publish()

# ---- hunt scanning ---------------------------------------------------------

## Validates and starts a scan at the reported position. The filter carries the
## client's chosen species set, thresholds, rate and limit.
func start_hunt(filter: Dictionary) -> bool:
	if hunt_running or backend.battle_open:return false
	if not backend.session.world_catalog.field(position_map):return false
	var profile: Dictionary = backend.session.snapshot()
	if profile.pets.size()>=GameSession.PET_CAPACITY:
		hunt_status = "宠物栏已满，请先腾出位置再寻找新伙伴。";return false
	if int(settings.get("capture_hp",100))<100 and bool(filter.get("level_one",true)) and (bool(filter.get("auto_capture",false)) or flow_phase=="hunt"):
		var choice: Dictionary = Policy.capture_pet_choice(profile,settings,1)
		if choice.has("stop"):
			hunt_status = str(choice.stop)
			if int(settings.get("capture_pet",-1))<0 and str(settings.get("capture_pet_id","")).is_empty():hunt_status = "缺少可用削血宠：请从仓库取出存活、非骑乘的Lv.1宠物，或手选符合等级上限的削血宠。"
			_emit_event({"kind":"hunt_refused","reason":hunt_status})
			return false
	if HuntRules.tail_probability(int(filter.get("total",-8)),filter.get("offsets",[-2,-2,-2,-2]))<=0:
		hunt_status = "这些条件无法同时满足，请降低门槛。";return false
	if HuntRules.candidates(backend.encounter_catalog,position_map,position_cell,bool(filter.get("level_one",true))).is_empty():
		hunt_status = "当前区域不会出现符合种类／等级条件的宠物。";return false
	var usable: Array = filter.get("usable",[])
	if usable.is_empty() or (int(filter.get("template",-1))>=0 and not int(filter.template) in usable):
		hunt_status = "当前没有素材齐全的目标宠物。";return false
	_prepare_catalog(filter)
	hunt_rolls = 0;hunt_inspected = 0;hunt_best = -9;hunt_mixed_skips = 0;hunt_elapsed = 0;hunt_credit = 0;hunt_last_hit = {}
	# Two draws from the walking encounter stream seed this run's rolls.
	hunt_run_seed = (backend.encounter_rng.randi() << 32) | backend.encounter_rng.randi()
	hunt_fast_wanted = bool(filter.get("fast",false))
	fast_unavailable = FastHunt.unavailable_reason()
	hunt_fast_note = fast_unavailable if hunt_fast_wanted else ""
	hunt_started_usec = Time.get_ticks_usec()
	hunt_running = true
	hunt_status = ""
	_emit_status()
	return true

## The run's filter, place and encounter source at the reported position.
func _prepare_catalog(filter: Dictionary) -> void:
	hunt_filter = filter.duplicate(true)
	hunt_map = position_map
	hunt_cell = position_cell
	# Freeze the validated location for this run. Only trim the spatial lookup;
	# retain original groups/enemies/templates and all roll checks/RNG calls.
	var hunt_data: Dictionary = backend.encounter_catalog.data.duplicate()
	hunt_data.areas = [backend.encounter_catalog.area_at(hunt_map,hunt_cell)]
	hunt_catalog = EncounterCatalog.new(hunt_data)

func stop_hunt(reason: String) -> void:
	fast_hunt.stop()
	_share_leave()
	# The find-pet cycle records its own stops; a hit it goes on to capture is none.
	if hunt_running and not flow_active() and not _stopping_cycle:
		_record_stop("hunt","找到" if reason.begins_with("找到达标个体") else "停止",reason)
	hunt_running = false
	hunt_status = reason
	_emit_status()
	_emit_event({"kind":"hunt_stopped","reason":reason})

func _hunt_process(delta: float) -> void:
	var background := flow_showcase and flow_active()
	if (backend.battle_open and not background) or position_map!=hunt_map or position_cell!=hunt_cell:
		stop_hunt("场景状态变化，筛选已停止。");return
	hunt_elapsed = (Time.get_ticks_usec()-hunt_started_usec)/1000000.0
	if _predicting():
		refresh_maxima()
		_survey_process()
		if not hunt_running:return
		if not flow_showcase and not survey_picks.is_empty():
			_take_survey_pick();return
	# Discard old backlog after a stall; never catch up with an unbounded burst.
	# A rate of 0 or less is unlimited: scan for the whole frame budget.
	if _fast_process():
		hunt_elapsed = (Time.get_ticks_usec()-hunt_started_usec)/1000000.0
		if hunt_running:_emit_status()
		return
	var unlimited := int(hunt_filter.rate)<=0
	if not unlimited:hunt_credit = minf(hunt_credit+delta*float(hunt_filter.rate),maxf(1.0,float(hunt_filter.rate)*HUNT_MAX_BACKLOG_SECONDS))
	var until := Time.get_ticks_usec()+frame_budget(HUNT_FRAME_BUDGET_USEC)
	while hunt_running and (unlimited or hunt_credit>=1) and Time.get_ticks_usec()<until:
		if not unlimited:hunt_credit -= 1
		scan_once()
	hunt_elapsed = (Time.get_ticks_usec()-hunt_started_usec)/1000000.0
	if hunt_running:_emit_status()

## One GDScript scan step: the next roll of this run.
func scan_once() -> void:
	if not hunt_running:return
	# A direct step (tests, or after the helper) continues from the counters.
	if fast_hunt.running():fast_hunt.stop()
	_scan_index(hunt_rolls)

## Scans roll `index` of this run. `expected` is what the native helper
## reported for it: -1 when called by the GDScript scan, else the enemy slot of
## its hit, or -2 for an empty troop. The helper only searches; this replay
## decides, and a different outcome stops the hunt.
func _scan_index(index: int, expected := -1) -> void:
	hunt_rolls = index+1
	var troop := roll_at(index)
	if troop.is_empty():
		stop_hunt("原版遇敌数据或条件不完整，已停止；没有替换敌群。");return
	if expected==-2:
		stop_hunt(_fast_mismatch(index));return
	var i := first_match(troop)
	# The helper judged with the thresholds it was started with; a hit queued
	# since may have raised them, so a report the replay now rejects is not a
	# mismatch (the helper restarts with the new thresholds next frame).
	var raised := expected>=0 and not _fast_thresholds.is_empty() and threshold_key()!=_fast_thresholds
	if i<0:
		if expected>=0 and not raised:
			stop_hunt(_fast_mismatch(index));return
		if int(hunt_filter.limit)>0 and hunt_rolls>=int(hunt_filter.limit):stop_hunt("达到本轮遇敌上限，已暂停；可以再次开始。")
		return
	if expected>=0 and i!=expected and not raised:
		stop_hunt(_fast_mismatch(index));return
	var actor: Dictionary = troop.enemies[i]
	var quality: Dictionary = HuntRules.quality(actor,backend.encounter_catalog.data)
	if flow_showcase and flow_active():
		hunt_last_hit = {"actor":actor.duplicate(true),"index":i,"quality":quality,"troop":troop.duplicate(true)}
		# 展示模式: queue the hit and keep searching; flow_step takes it in turn.
		if TroopArt.can_render(troop.enemies):_showcase_enqueue(index,i,troop,quality)
		return
	_open_hit(troop,i,quality,{"run_seed":hunt_run_seed,"index":index,"slot":i})

## A hit (or a survey pick) becomes a battle: the hunt stops, the battle opens
## and a find-pet cycle catches the pet (or 自动捕捉 does, if on).
func _open_hit(troop: Dictionary, i: int, quality: Dictionary, roll: Dictionary = {}) -> void:
	var filter := hunt_filter
	var actor: Dictionary = troop.enemies[i]
	hunt_last_hit = {"actor":actor.duplicate(true),"index":i,"quality":quality,"troop":troop.duplicate(true)}
	var found := "找到达标个体：%s Lv.%d，总成长档 %+d。" % [actor.name,actor.level,quality.total_offset]
	if not TroopArt.can_render(troop.enemies):
		stop_hunt(found+"\n敌群原版素材不可用，保留本次结果并停止，未进入战斗。");return
	_protect_pets()
	var config: Dictionary = backend.session.start_wild_battle_config(troop,_mixed_clear_target(troop,i))
	if config.is_empty():
		stop_hunt(found+"\n战斗校验未通过，已停止。");return
	var refusal := mixed_refusal(troop,i,config)
	if not refusal.is_empty():
		stop_hunt(found+"\n"+refusal);return
	stop_hunt(found)
	# The workflow resolves its capture fight without animation, like compact training.
	var workflow_capture := flow_phase=="hunt"
	if workflow_capture:
		compact_active = true
		_emit_status()
	backend.open_battle(config)
	var automatic: bool = workflow_capture or bool(filter.get("auto_capture",false))
	_emit_event({"kind":"hunt_hit","index":i,"actor":actor.duplicate(true),"quality":quality,"rolls":hunt_rolls,"automatic":automatic,"workflow":workflow_capture})
	if flow_phase=="hunt":
		matched(i,actor)
		flow_matched_roll = roll.duplicate()
	elif bool(filter.get("auto_capture",false)):start_capture_battle(i)

## Roll `index` of this run, from its own seed (FastHunt.roll_seed).
func roll_at(index: int) -> Dictionary:
	hunt_rng.seed = FastHunt.roll_seed(hunt_run_seed,index)
	return hunt_catalog.roll(hunt_map,hunt_cell,hunt_rng,backend.session._profile.get("original_items",[]))

## The first enemy slot of a rolled troop the hunt takes, or -1. Counts what it
## inspects (hunt_inspected, hunt_best, and during a find-pet cycle the
## predictions); the native helper implements the same rules.
func first_match(troop: Dictionary) -> int:
	var filter := hunt_filter
	# 只进无其他敌人的遇敌: decided per troop, counted per pet it costs.
	var mixed := HuntRules.wants_clean(filter) and not HuntRules.clean_troop(troop)
	for i in range(troop.enemies.size()):
		var actor: Dictionary = troop.enemies[i]
		if not actor.get("can_capture",false):continue
		if not int(actor.template_id) in filter.usable:continue
		if int(filter.template)>=0 and int(actor.template_id)!=int(filter.template):continue
		if filter.level_one and int(actor.level)!=1:continue
		hunt_inspected += 1
		var quality: Dictionary = HuntRules.quality(actor,backend.encounter_catalog.data)
		if quality.valid:hunt_best = maxi(hunt_best,int(quality.total_offset))
		if HuntRules.matches(actor,int(filter.template),bool(filter.level_one),int(filter.total),filter.offsets,backend.encounter_catalog.data):
			if _predicting() and surveying(int(actor.template_id)):
				# 摸底: a candidate, not a hit (the helper does the same). With
				# no threshold yet, a mixed troop's pet is never one.
				if mixed:
					hunt_mixed_skips += 1;continue
				var projected: Dictionary = Progression.project_pet(actor,120)
				_note_best(projected)
				survey_add(hunt_run_seed,hunt_rolls-1,i,int(actor.template_id),_prediction(projected))
				continue
			if mixed and not mixed_allowed(int(actor.template_id)):
				hunt_mixed_skips += 1;continue
			if _predicting() and not accepts_prediction(actor):continue
			return i
	return -1

func _mixed_clear_target(troop: Dictionary, slot: int) -> int:
	if slot<0 or slot>=troop.enemies.size():return -1
	return slot if HuntRules.wants_clean(hunt_filter) and not HuntRules.clean_troop(troop) and mixed_allowed(int(troop.enemies[slot].template_id)) else -1

## Before a troop with enemies above Lv.1 is entered under mixed_if_stats:
## "" when the capture battle forecast (server/battle_forecast.gd, from this
## battle's own seed) says the run can plausibly win, else the reason to
## pause, and the battle config built for it is dropped.
func mixed_refusal(troop: Dictionary, slot: int, config: Dictionary) -> String:
	if not HuntRules.wants_clean(hunt_filter) or HuntRules.clean_troop(troop):return ""
	var run := profile_settings()
	var result := BattleForecast.forecast(config,run,slot,42+backend.encounter_serial+1)
	if bool(result.ok):return ""
	backend.session.cancel_pending_battle(str(config.get("battle_id","")))
	var actor: Dictionary = troop.enemies[slot]
	return "%s Lv.1 达到属性条件，但同组还有 %s。按五人先清场、难抓再换削血宠的策略模拟这场捕捉 %d 次只赢 %d 次（%s），为免战败扣魅力和宠物忠诚，已暂停，没有进入战斗。可以提升人物战力、准备合适削血宠后再开始，或在「抓宠设置」关掉「属性达标仍进混合遇敌」。" % [
		str(actor.get("name","")),BattleForecast.stronger_enemies(troop),int(result.trials),int(result.wins),str(result.reason)]

## A Lv.1 pet in a troop with stronger enemies is still taken (after a battle
## forecast before entering: mixed_refusal) only in a find-pet cycle with
## mixed_if_stats on and enabled 属性条件 for its species, which it must meet.
func mixed_allowed(template_id: int) -> bool:
	return _predicting() and bool(hunt_filter.get("mixed_if_stats",false)) and StatFilter.enabled(filter_for(template_id))

func _fast_mismatch(index: int) -> String:
	return "本机极速模式的结果与游戏复核不一致（第 %d 组），已停止，没有进入战斗。请关闭本机极速模式后再试，并报告这个问题。" % (index+1)

## 本机极速模式 for this frame: starts the helper when wanted and possible,
## and applies its reports. False when the GDScript scan should run instead:
## also while a 每秒遇敌 rate is set, since that asks for a throttled scan.
func _fast_process() -> bool:
	if not hunt_fast_wanted or not hunt_fast_note.is_empty() or int(hunt_filter.get("rate",0))>0:
		if fast_hunt.running():fast_hunt.stop()
		_share_leave()
		return false
	if not hunt_catalog is EncounterCatalog:return false
	_share_rebalance()
	# A better pet arrived (or a survey began or ended): the helper starts
	# again from the rolls already committed, with the new thresholds or item gates.
	if fast_hunt.running() and ((_predicting() and threshold_key()!=_fast_thresholds) or _fast_held_items!=backend.session._profile.get("original_items",[])):
		_survey_merge(fast_hunt.peek().get("candidates",[]))
		fast_hunt.stop()
	if not fast_hunt.running():
		_fast_base = {"inspected":hunt_inspected,"best":hunt_best,"rejects":flow_predicted_rejects,"mixed":hunt_mixed_skips,"start":hunt_rolls}
		var area: Dictionary = hunt_catalog.area_at(hunt_map,hunt_cell)
		_fast_thresholds = threshold_key() if _predicting() else ""
		_fast_held_items = backend.session._profile.get("original_items",[]).duplicate()
		var rules := {}
		if _predicting():
			for id in survey.get("templates",[]):rules[int(id)] = raw_filter_for(int(id)).get("keep_rule",{})
		_fast_launched_threads = fast_threads_now()
		if fast_share!=null:_fast_launched_at = float(fast_share.clock.call())
		if not fast_hunt.launch(hunt_catalog.data,area,hunt_filter,_predicting(),filter_for,hunt_run_seed,hunt_rolls,_fast_launched_threads,rules,backend.session._profile.get("original_items",[])):
			hunt_fast_note = "本机辅助程序无法启动，已改用普通筛选。"
			_share_leave()
			return false
		return true
	var report: Dictionary = fast_hunt.poll()
	if report.is_empty():return true
	_survey_merge(report.get("candidates",[]))
	if str(report.kind)=="exited":
		hunt_fast_note = "本机辅助程序意外结束，已改用普通筛选。"
		_share_leave()
		return false
	hunt_rolls = int(report.index)
	hunt_inspected = int(_fast_base.inspected)+int(report.inspected)
	hunt_best = maxi(int(_fast_base.best),int(report.best))
	hunt_mixed_skips = int(_fast_base.mixed)+int(report.get("mixed",0))
	flow_predicted_rejects = int(_fast_base.rejects)+int(report.predicted_rejects)
	if int(report.best_sum)>=0 and (flow_best_predicted.is_empty() or int(report.best_sum)>int(flow_best_predicted.sum) or (int(report.best_sum)==int(flow_best_predicted.sum) and int(report.best_attack)>int(flow_best_predicted.attack))):
		flow_best_predicted = {"sum":int(report.best_sum),"attack":int(report.best_attack)}
	match str(report.kind):
		"hit":_scan_index(int(report.index),int(report.slot))
		"stop":_scan_index(int(report.index),-2)
		"limit":stop_hunt("达到本轮遇敌上限，已暂停；可以再次开始。")
	return true

## Sets 线程数 (0 = auto) on this server; "" or the refusal reason. A running
## helper is stopped and the next frame starts it again from the rolls already
## committed (the helper reports them in order), so the change applies at once
## and no roll is skipped or repeated in the results.
func set_fast_threads(value: Variant) -> String:
	var error := ServerSettings.set_fast_hunt_threads(value)
	if not error.is_empty():return error
	fast_threads = ServerSettings.fast_hunt_threads()
	if fast_hunt.running():
		_survey_merge(fast_hunt.peek().get("candidates",[]))
		fast_hunt.stop()
	_emit_status()
	return ""

## The thread count to start the helper with: this hunt's share of the
## computer's budget when shared, else 线程数 itself (0 lets the helper pick).
func fast_threads_now() -> int:
	return int(fast_share.threads) if fast_share!=null and fast_share.joined() else fast_threads

## The budget every hunt on this computer shares: 线程数, re-read so a change
## made on another server applies here too, or all cores but one.
func _share_budget() -> int:
	fast_threads = ServerSettings.fast_hunt_threads()
	return threads_used(fast_threads)

## Registers this scanning hunt (once a second) and restarts a running helper
## whose share changed, at most every REBALANCE_SECONDS. The restart merges
## the survey pool first and goes on from the committed rolls, as a 线程数
## change does, so results do not change.
func _share_rebalance() -> void:
	if fast_share==null:return
	if fast_share.due():fast_share.beat(_share_budget())
	if not fast_hunt.running() or int(fast_share.threads)==_fast_launched_threads:return
	if float(fast_share.clock.call())-_fast_launched_at < FastHuntShare.REBALANCE_SECONDS:return
	_survey_merge(fast_hunt.peek().get("candidates",[]))
	fast_hunt.stop()

## This hunt stopped scanning: its threads go to the others.
func _share_leave() -> void:
	if fast_share!=null and fast_share.joined():
		fast_share.leave()

## Nothing scans: no helper left running, no registration left behind.
func _share_idle() -> void:
	if fast_hunt.running():fast_hunt.stop()
	_share_leave()

## How many hunts share the computer's threads now (1 when alone, or when
## this hunt does not use the helper).
func fast_hunters() -> int:
	return int(fast_share.hunters) if fast_share!=null and fast_share.joined() else 1

## Threads the helper uses for a setting: all cores but one when automatic.
static func threads_used(setting: int) -> int:
	var cores := ServerSettings.cores()
	return setting if setting > 0 else (cores-1 if cores > 2 else 1)

# ---- find-pet workflow -----------------------------------------------------

func flow_active() -> bool:
	return flow_phase in ["hunt","reveal","capture","train","restart"]

## Whether hunt hits must also meet the Lv.120 stat conditions.
func _predicting() -> bool:
	return flow_phase=="hunt" or (flow_showcase and flow_active())

func elapsed_seconds() -> float:
	return maxf(0.0,(int(timer_clock.call())-timer_started_msec)/1000.0) if timer_running else timer_frozen_seconds

func start_timer() -> void:
	timer_started_msec = int(timer_clock.call());timer_frozen_seconds = 0.0;timer_running = true

func freeze_timer() -> void:
	timer_frozen_seconds = elapsed_seconds();timer_running = false

## 找到N只后停止 (hunt.stop_after) for the whole run, every species alike:
## pets this run keeps (qualifiers, or with no 属性条件 every pet trained to
## Lv.120) before it stops; 0 never stops, 1 stops at the first to compare.
## Read from the run's settings snapshot, which follows the player's edits.
func run_stop_after() -> int:
	return int(AutomationSettings.effective(flow_settings_overrides).hunt.get("stop_after",1))

func collect_target_text() -> String:
	var stop_after := run_stop_after()
	return "不限" if stop_after<=0 else str(stop_after)

## The cycle's stat filter for a species as saved (最高 − x or fixed values, unresolved).
func raw_filter_for(template_id: int) -> Dictionary:
	if flow_stat_filters.has(template_id):return flow_stat_filters[template_id]
	return AutomationSettings.stat_filter(flow_settings_overrides,template_id)

## The filter the hunt applies now: 最高 − x resolved against the species'
## best pets (species_maxima), or the fixed values in absolute mode.
func filter_for(template_id: int) -> Dictionary:
	return StatFilter.resolve(raw_filter_for(template_id),species_maxima(template_id))

## Hunt-time gate: compute the exact Lv.120 stats from the wild pet's own seed and
## only let pets that will meet the conditions through to capture.
func accepts_prediction(actor: Dictionary) -> bool:
	var chosen := filter_for(int(actor.get("template_id",-1)))
	if not StatFilter.enabled(chosen):return true
	var projected: Dictionary = Progression.project_pet(actor,120)
	_note_best(projected)
	if StatFilter.evaluate(projected,chosen):return true
	flow_predicted_rejects += 1
	return false

func _note_best(projected: Dictionary) -> void:
	var total := int(projected.attack)+int(projected.defence)+int(projected.speed)
	if flow_best_predicted.is_empty() or total>int(flow_best_predicted.sum) or (total==int(flow_best_predicted.sum) and int(projected.attack)>int(flow_best_predicted.attack)):
		flow_best_predicted = {"sum":total,"attack":int(projected.attack)}

static func _prediction(projected: Dictionary) -> Dictionary:
	return {"attack":int(projected.attack),"defence":int(projected.defence),"speed":int(projected.speed),"max_hp":int(projected.max_hp)}

# ---- 最高 − x and 摸底 -------------------------------------------------------

## Clears the cached maxima when the player's pets changed.
func refresh_maxima() -> void:
	var key: String = backend.session.pet_signature()
	if key==_pets_key:return
	_pets_key = key
	_owned_maxima = {}
	_pets_profile = {}

var _pets_profile: Dictionary = {}

## The best Lv120 values among the player's own pets of a species (carried
## and warehouse, under Lv120 by exact projection), {} when there are none.
func owned_maxima(template_id: int) -> Dictionary:
	if not _owned_maxima.has(template_id):
		if _pets_profile.is_empty():_pets_profile = backend.session.snapshot()
		_owned_maxima[template_id] = StatFilter.maxima(KeepRule.species_pets(_pets_profile,template_id).map(KeepRule.stats_of))
	return _owned_maxima[template_id]

## owned_maxima raised by the pets the cycle is about to catch: survey picks
## and, with 后台搜宠, the queued hits and the one being caught. A hit is only
## worth queueing if it could beat what is already waiting.
func species_maxima(template_id: int) -> Dictionary:
	return _maxima_with(template_id,_pending_picks()+_queued_hits())

## owned_maxima raised by the given pending entries of the species.
func _maxima_with(template_id: int, entries: Array) -> Dictionary:
	var pending: Array = []
	for entry in entries:
		if int(entry.actor.get("template_id",-1))==template_id:pending.append(entry.prediction)
	return StatFilter.maxima(pending,owned_maxima(template_id))

## What an already pending hit is judged against: never itself. With
## 最高 + n (a negative x) the best hit could never beat its own value, so it
## would be let go the moment it raised 最高. It counts owned pets, survey
## picks (always caught), the hit being caught, and the queued hits ranked
## above it by _showcase_better that are themselves kept (`kept_above`). Hits
## ranked below it never raise its threshold, so of two equal best hits with
## 最高 + 1 the earlier roll stays and the other goes, never both.
func entry_maxima(entry: Dictionary, kept_above: Array) -> Dictionary:
	return _maxima_with(int(entry.actor.get("template_id",-1)),_entry_others(entry,kept_above))

## The pending entries entry_maxima counts for `entry`, of every species.
func _entry_others(entry: Dictionary, kept_above: Array) -> Array:
	var others: Array = _pending_picks().filter(func(e):return not is_same(e,entry))
	if flow_phase=="capture" and not showcase_current.is_empty() and not bool(showcase_current.get("survey",false)) and not is_same(showcase_current,entry):
		others.append(showcase_current)
	return kept_above+others

## The filter a pending hit must still pass (entry_maxima).
func filter_excluding(entry: Dictionary, kept_above: Array) -> Dictionary:
	return StatFilter.resolve(raw_filter_for(int(entry.actor.get("template_id",-1))),entry_maxima(entry,kept_above))

func _queued_hits() -> Array:
	var result: Array = showcase_queue.filter(func(entry):return not bool(entry.get("survey",false)))
	if not showcase_current.is_empty() and not bool(showcase_current.get("survey",false)) and flow_phase=="capture":result.append(showcase_current)
	return result

func _pending_picks() -> Array:
	var result: Array = survey_picks.duplicate()
	for entry in showcase_queue:
		if bool(entry.get("survey",false)):result.append(entry)
	if bool(showcase_current.get("survey",false)) and flow_phase=="capture":result.append(showcase_current)
	return result

## The species this hunt may take: its usable ones, or the one chosen.
func _hunt_templates() -> Array:
	var result: Array = []
	for id in hunt_filter.get("usable",[]):
		if int(hunt_filter.get("template",-1))<0 or int(id)==int(hunt_filter.template):result.append(int(id))
	return result

## The resolved thresholds of every species the hunt may take, and which are
## being surveyed: when this changes the native helper restarts.
func threshold_key() -> String:
	var parts: Array = []
	for id in _hunt_templates():
		var chosen := filter_for(id)
		parts.append([id,surveying(id),chosen.get("mode",""),chosen.get("conditions",{}).values().map(func(c):return [c.get("enabled",false),c.get("value",null)])])
	return JSON.stringify(parts)

func surveying(template_id: int) -> bool:
	return not survey.is_empty() and survey.templates.has(template_id)

## Species of this hunt whose enabled 最高 − x conditions have nothing to
## count from (no pet of theirs, and no survey pick on the way).
func _survey_wanted() -> Array:
	var result: Array = []
	for id in _hunt_templates():
		if StatFilter.needs_survey(raw_filter_for(id),species_maxima(id)):result.append(id)
	return result

## Full-CPU seconds the survey still needs (摸底 lasts survey_seconds of the
## whole computer: with N hunts sharing it, each wall second counts 1/N).
func survey_remaining() -> float:
	if survey.is_empty():return 0.0
	return maxf(0.0,float(survey_seconds)-_survey_credit())

## Full-CPU seconds counted so far, including the time since the last update
## at the current share.
func _survey_credit() -> float:
	return float(survey.credit)+(int(survey_clock.call())-int(survey.clock))/1000.0/float(fast_hunters())

## Books the time since the last update at the share it ran with.
func _survey_advance() -> void:
	survey.credit = _survey_credit()
	survey.clock = int(survey_clock.call())

## Wall time the survey still takes at the current share.
func survey_wall_remaining() -> float:
	return survey_remaining()*fast_hunters()

func _template_name(template_id: int) -> String:
	return str(backend.encounter_catalog.data.get("templates",{}).get(str(template_id),{}).get("name","#%d" % template_id))

## Starts a survey when a species needs one; ends it when its time is up.
func _survey_process() -> void:
	if survey.is_empty():
		var wanted := _survey_wanted()
		if wanted.is_empty():return
		survey = {"templates":wanted,"started":int(survey_clock.call()),"clock":int(survey_clock.call()),"credit":0.0,"candidates":{},"runs":[]}
		var names: Array = wanted.map(_template_name)
		var shared := "（%d 人共享本机，约%s）" % [fast_hunters(),_duration(survey_seconds*fast_hunters())] if fast_hunters()>1 else ""
		_showcase_line("survey","摸底：还没有%s，先不设门槛找%s%s，再按保留规则挑最好的抓。" % ["、".join(names),_duration(survey_seconds),shared])
		_emit_status()
	else:
		_survey_advance()
		if survey_remaining()<=0.0:_finish_survey()

static func _duration(seconds: float) -> String:
	var s := int(seconds)
	return "%d分钟" % (s/60) if s>=60 and s%60==0 else ("%d分%02d秒" % [s/60,s%60] if s>=60 else "%d秒" % s)

## One survey candidate (from the GDScript scan or the helper's pool).
func survey_add(run_seed: int, index: int, slot: int, template_id: int, prediction: Dictionary) -> void:
	if not surveying(template_id):return
	var key := "%d:%d:%d" % [run_seed,index,slot]
	if survey.candidates.has(key):return
	if not survey.runs.has(run_seed):survey.runs.append(run_seed)
	# Ties resolve to the earlier roll, as the helper's pool (and 保留规则's
	# older pet id) does.
	var serial: int = (survey.runs.find(run_seed) << 40) | (index*16+slot)
	survey.candidates[key] = {"run_seed":run_seed,"index":index,"slot":slot,"template_id":template_id,"prediction":prediction.duplicate(),"serial":serial}
	if survey.candidates.size()>512:
		var kept := {}
		for pick in survey_choose(survey.candidates.values()):kept["%d:%d:%d" % [int(pick.run_seed),int(pick.index),int(pick.slot)]] = true
		for k in survey.candidates.keys():
			if not kept.has(k):survey.candidates.erase(k)

func _survey_merge(candidates: Array) -> void:
	for c in candidates:survey_add(hunt_run_seed,int(c.index),int(c.slot),int(c.template_id),c.prediction)

## What each species' 保留规则 would keep of these candidates (the functional
## core of the survey): the top tiers of 三围合, the best per tier by the
## rule's order, and the single-stat champions. Best first.
func survey_choose(candidates: Array) -> Array:
	var by_template := {}
	for c in candidates:
		if not by_template.has(int(c.template_id)):by_template[int(c.template_id)] = []
		by_template[int(c.template_id)].append(c)
	var result: Array = []
	for id in by_template:
		var rule: Dictionary = raw_filter_for(int(id)).get("keep_rule",{})
		result.append_array(choose_by_rule(by_template[id],rule))
	return result

## choose_by_rule on plain candidates {serial, prediction, ...}, best first.
static func choose_by_rule(candidates: Array, rule: Dictionary) -> Array:
	var pets: Array = []
	var by_id := {}
	for c in candidates:
		var p: Dictionary = c.prediction
		var id := "pet-%d" % int(c.serial)
		by_id[id] = c
		pets.append({"pet_id":id,"level":120,"attack":int(p.attack),"defence":int(p.defence),"speed":int(p.speed),"max_hp":int(p.max_hp)})
	var verdict: Dictionary = KeepRule.evaluate(pets,rule)
	var kept: Array = pets.filter(func(pet):return not verdict.reasons[str(pet.pet_id)].is_empty())
	kept = StatFilter.ranked(kept,["sum"]+Array(rule.get("order",["attack","speed","max_hp"])))
	return kept.map(func(pet):
		var c: Dictionary = by_id[str(pet.pet_id)].duplicate()
		c.reasons = verdict.reasons[str(pet.pet_id)]
		return c)

## Time is up: take the helper's last pool, replay every candidate from its
## own seed (a mismatch is left out), choose by the keep rule and queue the
## picks for capture. Picks count toward 最高 until caught, so the hunt goes
## on with thresholds at once.
func _finish_survey() -> void:
	if fast_hunt.running():
		_survey_merge(fast_hunt.peek().get("candidates",[]))
		fast_hunt.stop()
	var finished := survey
	survey = {}
	var verified: Array = []
	var mismatched := 0
	for c in finished.candidates.values():
		var entry := _replay_candidate(c)
		if entry.is_empty():mismatched += 1
		else:verified.append(entry)
	var picks := survey_choose(verified)
	var names: Array = finished.templates.map(_template_name)
	var text := "摸底结束（%s）：候选 %d 只%s，按保留规则选中 %d 只" % ["、".join(names),verified.size(),"（复核不一致 %d 只，已略过）" % mismatched if mismatched>0 else "",picks.size()]
	var shown: Array = picks.slice(0,3).map(func(p):return "第%d组 %s（%s）" % [int(p.index)+1,_stat_text(p.prediction),"、".join(p.reasons)])
	if not shown.is_empty():text += "：" + "；".join(shown) + ("……" if picks.size()>3 else "")
	if picks.is_empty():text += "，重新摸底。"
	survey_last = {"candidates":verified.size(),"picked":picks.size(),"text":text}
	_showcase_line("survey",text)
	log_line("[找宠流程] "+text)
	for p in picks:
		p.survey = true
		if flow_showcase:_showcase_add(p)
		else:survey_picks.append(p)
	_emit_status()

## A candidate replayed from its own seed: the queue entry {index, slot,
## run_seed, actor, troop, quality, prediction}, or {} when it differs.
func _replay_candidate(c: Dictionary) -> Dictionary:
	if hunt_catalog==null:return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = FastHunt.roll_seed(int(c.run_seed),int(c.index))
	var troop: Dictionary = hunt_catalog.roll(hunt_map,hunt_cell,rng,backend.session._profile.get("original_items",[]))
	var enemies: Array = troop.get("enemies",[])
	if int(c.slot)<0 or int(c.slot)>=enemies.size():return {}
	var actor: Dictionary = enemies[int(c.slot)]
	if int(actor.get("template_id",-1))!=int(c.template_id) or not actor.get("can_capture",false):return {}
	if not HuntRules.matches(actor,int(hunt_filter.template),bool(hunt_filter.level_one),int(hunt_filter.total),hunt_filter.offsets,backend.encounter_catalog.data):return {}
	var prediction := _prediction(Progression.project_pet(actor,120))
	if prediction!=c.prediction or not TroopArt.can_render(enemies):return {}
	return {"index":int(c.index),"slot":int(c.slot),"run_seed":int(c.run_seed),"serial":int(c.serial),"template_id":int(c.template_id),"actor":actor.duplicate(true),
		"troop":troop.duplicate(true),"quality":HuntRules.quality(actor,backend.encounter_catalog.data),"prediction":prediction}

## 后台搜宠 off: the next survey pick is caught like a hit (replayed again
## from its seed first; a different troop is skipped).
func _take_survey_pick() -> void:
	var entry: Dictionary = survey_picks.pop_front()
	var replayed := _replay_candidate(entry)
	if replayed.is_empty() or JSON.stringify(replayed.troop)!=JSON.stringify(entry.troop):
		_showcase_line("skipped","摸底选中的第 %d 组复核不一致，已略过。" % (int(entry.index)+1))
		return
	_open_hit(replayed.troop,int(replayed.slot),replayed.quality,{"run_seed":int(entry.run_seed),"index":int(entry.index),"slot":int(entry.slot)})
	if flow_phase=="capture":flow_target_survey = true

func start_cycle(continuing: bool) -> bool:
	if flow_active():return false
	if backend.battle.snapshot().get("active",false) or backend.battle_open:
		flow_reason = "请先结束战斗或移动，再开始一轮找宠。";return false
	if backend.session.snapshot().pets.size()>=GameSession.PET_CAPACITY:
		flow_reason = "宠物栏已满，请自行存放伙伴后再开始。";return false
	if not continuing or flow_run_id.is_empty():
		_flow_run_serial += 1
		flow_run_id = "%d-%d" % [int(Time.get_unix_time_from_system()),_flow_run_serial]
	if not continuing:
		flow_stored_count = 0;flow_pruned_count = 0;flow_kept_count = 0;flow_collected_count = 0;flow_predicted_rejects = 0;flow_best_predicted = {};flow_last_result = "";flow_last_stored_id = "";flow_run_reject_ids = [];flow_released_count = 0;flow_held_count = 0
		flow_skip_kind = "";flow_skip_streak = 0;flow_skipped_count = 0;flow_skip_note = ""
		survey = {};survey_picks = [];survey_last = {};flow_target_survey = false;_pets_key = ""
		start_timer()
	flow_map = position_map
	flow_cell = position_cell
	flow_known_ids.clear();flow_pet_id = "";flow_matched_actor = {};flow_matched_index = -1;flow_matched_roll = {};flow_capture_battle_id = "";flow_reason = ""
	# Warehouse pets too: one withdrawn during the capture battle is not new.
	for pet in backend.session.snapshot().pets+backend.session.snapshot().get("pet_storage",[]):flow_known_ids[str(pet.pet_id)] = true
	flow_phase = "hunt"
	if not continuing:
		flow_showcase = bool(flow_hunt_request.get("showcase",false))
		showcase_queue = [];showcase_current = {};showcase_log = [];showcase_last_template = -1
	_emit_event({"kind":"flow_hunt"})
	if not start_hunt(flow_hunt_request):
		stop_cycle(hunt_status);return false
	_emit_status()
	return true

func matched(index: int, actor: Dictionary) -> void:
	if flow_phase!="hunt":return
	refresh_maxima()
	flow_target_survey = false
	flow_target_filter = filter_for(int(actor.get("template_id",-1))).duplicate(true)
	flow_matched_index = index
	flow_matched_actor = actor.duplicate(true)
	flow_capture_battle_id = str(backend.battle.snapshot().get("battle_id",""))
	flow_phase = "capture"
	start_capture_battle(index,true)
	if not running:stop_cycle("无法开始自动捕捉，请手动处理当前战斗。")

## 停止 from the player: a pet being caught or trained is finished first (the
## search stops and the queue is let go now); the cycle then stops where it
## would start the next one. Asked again while waiting, it stops at once.
func request_stop_cycle(message: String) -> void:
	if not flow_active() or flow_phase not in ["capture","train"] or not flow_stop_pending.is_empty():
		stop_cycle(message);return
	flow_stop_pending = message
	if not showcase_queue.is_empty():
		_showcase_line("dropped","停止：排队的 %d 只已放弃，本只练完后停止" % showcase_queue.size())
		showcase_queue = []
	else:_showcase_line("dropped","停止：本只练完后停止（再按一次立即停止）")
	if hunt_running:
		_stopping_cycle = true
		stop_hunt(message)
		_stopping_cycle = false
	_emit_status()

func stop_cycle(message: String = "已手动停止") -> void:
	flow_stop_pending = ""
	if message.is_empty():message = "找宠流程已停止（没有写明原因）。"
	if flow_active():_record_stop("flow","停止",message,_involved_pet())
	_stopping_cycle = true
	if not showcase_queue.is_empty():
		_showcase_line("dropped","排队的 %d 只已放弃：%s" % [showcase_queue.size(),message])
		message += "（排队的 %d 只已放弃）" % showcase_queue.size()
	if not survey_picks.is_empty():_showcase_line("dropped","摸底选中的 %d 只未捕获：%s" % [survey_picks.size(),message])
	showcase_queue = []
	survey = {}
	survey_picks = []
	_showcase_restore()
	freeze_timer()
	flow_phase = "paused"
	flow_reason = message
	if hunt_running:stop_hunt(message)
	if running:stop(message)
	_stopping_cycle = false
	_emit_status()
	_emit_event({"kind":"flow_paused","reason":message})

func flow_step() -> void:
	if not flow_active():return
	if position_map!=flow_map or position_cell!=flow_cell:
		stop_cycle("位置发生变化；请在当前位置重新开始。");return
	if flow_showcase:
		_showcase_step()
		return
	if not flow_stop_pending.is_empty() and flow_phase in ["restart","hunt"]:
		stop_cycle("本只练完，已停止：%s" % flow_stop_pending);return
	if flow_phase=="restart":
		flow_phase = "idle"
		if not start_cycle(true):stop_cycle(flow_reason)
		return
	if flow_phase=="hunt":
		if not hunt_running:stop_cycle(hunt_status)
		return
	if running:return
	if flow_phase=="capture":
		# Only the normal single-battle completion continues with this pet; a
		# failed capture skips it (_capture_failed), a manual Stop is final.
		if _capture_failed():return
		var fresh: Array = []
		var pets: Array = backend.session.snapshot().pets
		for i in range(pets.size()):
			if not flow_known_ids.has(str(pets[i].get("pet_id",""))):fresh.append(i)
		if fresh.size()!=1 or not same_capture(pets[fresh[0]],flow_matched_actor):
			stop_cycle("无法唯一确认新捕获伙伴，请手动检查宠物栏。");return
		flow_pet_id = str(pets[fresh[0]].pet_id)
		_capture_succeeded()
		if not backend.session.select_pet(int(fresh[0])):stop_cycle("新伙伴无法出战。");return
		backend.save()
		backend.publish()
		_level_to_120()
		return
	if flow_phase=="train":
		if stop_reason!="目标宠物已达到等级目标":stop_cycle(stop_reason);return
		var found: Dictionary = {}
		for pet in backend.session.snapshot().pets:
			if str(pet.get("pet_id",""))==flow_pet_id:found = pet
		if found.is_empty() or int(found.level)<120:stop_cycle("目标宠物未达到120级，请手动检查。");return
		complete_trained_pet(found)

## The full-speed cycle's training: straight to Lv.120, then compared.
## Growth is seeded per pet and level, so instant levelling equals battle training.
func _level_to_120() -> void:
	flow_phase = "train"
	backend.session.last_error = ""
	if not backend.session.level_pet_to(flow_pet_id,120):stop_cycle("无法升至120级："+str(backend.session.last_error));return
	backend.save()
	backend.publish()
	complete_trained_pet(_flow_pet())

func _store_hunt_pet(pet_id: String, prunable: bool, qualified: bool = false) -> bool:
	var index := -1
	var pets: Array = backend.session.snapshot().pets
	for i in range(pets.size()):
		if str(pets[i].get("pet_id",""))==pet_id:index = i;break
	backend.session.last_error = ""
	return index>=0 and backend.session.store_pet(index,prunable,qualified)

func complete_trained_pet(found: Dictionary) -> void:
	if flow_phase!="train":return
	# Use settled actual attributes, never the forecast or a different pet's ID.
	if str(found.get("pet_id",""))!=flow_pet_id or int(found.get("level",0))<120:
		stop_cycle("目标宠物未达到120级，请手动检查。");return
	var filtered := StatFilter.enabled(flow_target_filter)
	# A survey pick is what the survey found best: it counts as found.
	var passed := flow_target_survey or StatFilter.evaluate(found,flow_target_filter)
	flow_last_result = "%s · %s" % [flow_pet_id,"摸底选中" if flow_target_survey else StatFilter.describe(found,flow_target_filter)] if filtered else "新伙伴已达到120级"
	if filtered and not passed:
		if not _store_hunt_pet(flow_pet_id,true):
			stop_cycle("未达标但无法存仓："+str(backend.session.last_error));return
		flow_stored_count += 1
		flow_run_reject_ids.append(flow_pet_id)
		flow_last_stored_id = flow_pet_id
		flow_last_stored_total = int(found.attack)+int(found.defence)+int(found.speed)
		flow_last_result = "未达标已存仓 · "+flow_last_result
		flow_pruned_count += backend.session.prune_hunt_pets(int(found.get("template_id",-1)),StatFilter.keep_counts(flow_target_filter),flow_run_reject_ids)
		if _tidy_species(found).has(flow_pet_id):flow_last_result = "未达标已存仓，按保留规则放生 · "+flow_last_result.trim_prefix("未达标已存仓 · ")
		backend.save()
		backend.publish()
		# A separate step leaves cancellation/reload a boundary before restarting.
		flow_phase = "restart"
		flow_reason = flow_last_result
		_emit_status()
		_emit_event({"kind":"flow_stored","result":flow_last_result})
		return
	var stop_after := run_stop_after()
	if stop_after!=1:
		# Keep the pet in the warehouse (never pruned as a reject) and continue.
		if not _store_hunt_pet(flow_pet_id,false,filtered):
			stop_cycle(("达标" if filtered else "新伙伴")+"但无法存仓："+str(backend.session.last_error));return
		flow_kept_count += 1
		flow_collected_count += 1
		var released := _tidy_species(found)
		backend.save()
		backend.publish()
		var kept := "达标" if filtered else "已满120级"
		if released.has(flow_pet_id):flow_last_result = kept+"但不在保留规则内，已放生 · "+flow_last_result
		else:flow_last_result = kept+"已存仓 · "+flow_last_result
		if stop_after>0 and flow_collected_count>=stop_after:
			freeze_timer()
			var done := "收集完成：本轮找到%d只%s宠物" % [flow_collected_count,"达标" if filtered else ""]
			_record_stop("flow","完成",done,_involved_pet())
			flow_phase = "compare"
			flow_reason = "%s · %s" % [done,flow_last_result]
			_emit_status()
			_emit_event({"kind":"flow_compare","pet_id":flow_pet_id,"reason":flow_reason})
			return
		flow_phase = "restart"
		flow_reason = flow_last_result
		_emit_status()
		_emit_event({"kind":"flow_stored","result":flow_last_result})
		return
	freeze_timer()
	_record_stop("flow","完成","已达标，停下来比较" if filtered else "新伙伴已达到120级，停下来比较",_involved_pet())
	flow_phase = "compare"
	flow_reason = ("已达标 · "+flow_last_result) if filtered else "新伙伴已达到120级，请对比后自行决定去留。"
	_emit_status()
	_emit_event({"kind":"flow_compare","pet_id":flow_pet_id,"reason":flow_reason})

## 保留规则 with 找宠时自动整理 on: after a stored pet, the whole species
## (carried and warehouse) is tidied; favourites, the active pet, the mount and
## the capture helper stay. Returns the released ids.
func _tidy_species(found: Dictionary) -> Array:
	var rule: Dictionary = flow_target_filter.get("keep_rule",{})
	if not bool(rule.get("auto",false)):return []
	var template := int(found.get("template_id",-1))
	var released: Array = backend.session.apply_keep_rule(template,rule,capture_helpers())
	flow_released_count += released.size()
	flow_held_count = KeepRule.species_pets(backend.session.snapshot(),template).size()
	return released

## Carried pets the capture step may use (the chosen helper, or with automatic
## choice every one at or under the level cap): the tidy never releases them.
func capture_helpers() -> Dictionary:
	var capture: Dictionary = AutomationSettings.effective(backend.session.automation_settings()).get("capture",{})
	return KeepRule.capture_helpers(backend.session.snapshot(),capture)

static func same_capture(pet: Dictionary, actor: Dictionary) -> bool:
	for key in ["template_id","species","level","growth_weights","growth_seed","growth_rank","base_stats"]:
		if actor.has(key) and pet.get(key)!=actor[key]:return false
	return true

# ---- stops and skips (停止记录) --------------------------------------------

## One 停止记录 entry and a line on the server's output. scope: hunt (a scan on
## its own) or flow (the find-pet cycle); outcome: 停止, 暂停, 已跳过, 已重试,
## 完成 or 找到 (a scan on its own found its pet). Counts are the run's so far.
func _record_stop(scope: String, outcome: String, reason: String, pet: Dictionary = {}) -> void:
	var entry := {"time":int(Time.get_unix_time_from_system()),"scope":scope,"outcome":outcome,"reason":reason,
		"phase":flow_phase if scope=="flow" else "hunt","run":flow_run_id if scope=="flow" else "",
		"rolls":hunt_rolls,"collected":flow_collected_count,"stored":flow_stored_count,"skipped":flow_skipped_count,"released":flow_released_count,
		"map_id":position_map,"map_name":backend.map_name(position_map) if position_map>=0 else "","cell":[position_cell.x,position_cell.y],"pet_id":str(pet.get("pet_id","")),"name":str(pet.get("name",""))}
	stop_events.append(entry)
	var who := ""
	if not str(entry.name).is_empty():who = " · %s%s" % [entry.name," "+str(entry.pet_id) if not str(entry.pet_id).is_empty() else ""]
	log_line("[%s] %s：%s%s · 已遇敌 %d 组 · 达标 %d · 存仓 %d · 跳过 %d" % ["找宠流程" if scope=="flow" else "自动抓极品",outcome,reason.replace("\n"," "),who,hunt_rolls,flow_collected_count,flow_stored_count,flow_skipped_count])

func take_stop_events() -> Array:
	var result := stop_events
	stop_events = []
	return result

## The server is shutting down (a restart or quit) while a hunt, cycle or
## 自动练级 runs. With 重启后自动恢复 on, returns what try_resume needs to go
## on after the restart (backend.record_shutdown keeps it next to the save);
## {} otherwise. A battle the automation has open is given up (no rewards, as
## a skipped capture) so the save goes through; the restart fights it again.
func record_shutdown() -> Dictionary:
	var state := resume_state() if resume_wanted() else {}
	var reason := "服务器关闭（重启或退出）；已记下进度，重启后在原地自动恢复。" if not state.is_empty() else "服务器关闭（重启或退出），自动抓极品中断；重新打开后需要再次开始。"
	if flow_active():_record_stop("flow","暂停" if not state.is_empty() else "停止",reason,_involved_pet())
	elif hunt_running:_record_stop("hunt","暂停" if not state.is_empty() else "停止",reason)
	elif str(state.get("kind",""))=="training":log_line("[自动练级] 服务器关闭；重启后在原地自动恢复。")
	if backend.battle_open and (running or flow_active()):
		release_clone_override()
		backend.abandon_battle()
	# The save puts the character where the run was, so a page loaded after the
	# restart stands there too.
	if not state.is_empty():backend.session.set_location(int(state.map_id),int(state.cell[0]),int(state.cell[1]))
	return state

# ---- 重启后自动恢复 ---------------------------------------------------------
# A running find-pet cycle, hunt or 自动练级 is written down when the server
# shuts down (record_shutdown) and goes on after it starts again, once the
# character stands where it ran and no battle is open. The file lives next to
# the save (backend.gd resume file). The cycle keeps its run, counters, settings
# snapshot and 后台搜宠 queue (each hit with its roll seed, replayed and
# checked again before its capture); the hunt goes on from the same roll of the
# same run. A 摸底 in progress starts again. A capture battle cut short is
# fought again from the pet's own roll (or, if the pet was already caught, its
# training goes on); a training battle cut short is fought again.

const RESUME_VERSION := 1
const RESUME_KINDS := ["flow","hunt","training"]
## Find-pet cycle fields kept over a restart (restored with set()).
const RESUME_FLOW_FIELDS := ["flow_phase","flow_reason","flow_pet_id","flow_known_ids","flow_matched_actor","flow_matched_index","flow_matched_roll",
	"flow_stat_filters","flow_settings_overrides","flow_target_filter","flow_hunt_request","flow_stored_count","flow_last_result","flow_last_stored_id",
	"flow_last_stored_total","flow_kept_count","flow_collected_count","flow_pruned_count","flow_run_reject_ids","flow_released_count","flow_held_count",
	"flow_predicted_rejects","flow_run_id","flow_showcase","showcase_queue","showcase_last_template","showcase_current","showcase_log","_showcase_log_serial","flow_skip_kind",
	"flow_skip_streak","flow_skipped_count","flow_skip_note","flow_best_predicted","survey_picks","survey_last","flow_target_survey"]
const RESUMED := "服务器重启后已恢复"
## Read back at startup (load_resume) and applied by try_resume.
var pending_resume: Dictionary = {}

## 重启后自动恢复 (hunt.resume, default on).
func resume_wanted() -> bool:
	return bool(AutomationSettings.effective(backend.session.automation_settings()).hunt.get("resume",true))

## What must be kept for try_resume, or {} when nothing runs that can go on:
## a single manual battle's 自动战斗 or capture, and a cycle asked to stop, end here.
func resume_state() -> Dictionary:
	var kind := ""
	var at := Vector2i(-1,-1)
	var map := -1
	if flow_active() and flow_stop_pending.is_empty():
		kind = "flow";map = flow_map;at = flow_cell
	elif hunt_running and not flow_active():
		kind = "hunt";map = hunt_map;at = hunt_cell
	elif running and not flow_active() and not single_battle and str(settings.get("preset",""))!="capture":
		kind = "training";map = origin_map;at = origin_cell
	elif not pending_resume.is_empty() and not (running or hunt_running or flow_active()):
		# Restarted again before it could resume: keep what was waiting.
		return pending_resume.duplicate(true)
	if kind.is_empty() or map<0:return {}
	var state := {"version":RESUME_VERSION,"kind":kind,"time":int(Time.get_unix_time_from_system()),"map_id":map,"cell":[at.x,at.y],"settings":settings.duplicate(true)}
	if hunt_running:
		state.hunt = {"filter":hunt_filter.duplicate(true),"run_seed":hunt_run_seed,"rolls":hunt_rolls,"inspected":hunt_inspected,"best":hunt_best,"mixed":hunt_mixed_skips,"elapsed":hunt_elapsed}
	if kind=="flow":
		var flow := {"elapsed":elapsed_seconds(),"survey":not survey.is_empty()}
		for field in RESUME_FLOW_FIELDS:
			var value = get(field)
			flow[field] = value.duplicate(true) if value is Dictionary or value is Array else value
		state.flow = flow
	elif kind=="training":
		state.training = {"pet_id":training_pet_id,"level":training_pet_level,"battles":battles,"skipped":skipped,"earned_xp":earned_xp,"earned_pet_xp":earned_pet_xp,"initial_level":initial_level}
	return state

## Changes whenever the run moves on in a way the resume file must follow at
## once (backend.gd keep_resume_file): what runs, its phase, the pet worked
## on, the 后台搜宠 queue and the cycle's counts. Counters that only grow
## (rolls, battles, time) are left to the periodic write.
func resume_key() -> String:
	var queued := PackedInt64Array()
	for entry in showcase_queue:queued.append(int(entry.get("index",-1)))
	return str([flow_phase,flow_stop_pending.is_empty(),hunt_running,running,single_battle,pending_resume.is_empty(),flow_pet_id,
		flow_stored_count,flow_kept_count,flow_collected_count,flow_skipped_count,flow_released_count,queued,showcase_current.get("index",-1),training_pet_id])

## A state written by record_shutdown, read at startup. The character is taken
## to be where the run was until a client says otherwise.
func load_resume(state: Dictionary) -> void:
	if int(state.get("version",0))!=RESUME_VERSION or not str(state.get("kind","")) in RESUME_KINDS:return
	if not state.get("cell") is Array or state.cell.size()!=2:return
	pending_resume = state.duplicate(true)
	if position_map<0:
		position_map = int(state.map_id)
		position_cell = Vector2i(int(state.cell[0]),int(state.cell[1]))

## Goes on with the pending run once it is safe: the character stands where it
## ran and no battle is open. Standing elsewhere drops it (and says so).
func try_resume() -> void:
	if pending_resume.is_empty():return
	if running or hunt_running or flow_active():
		pending_resume = {};return
	var state := pending_resume
	var at := Vector2i(int(state.cell[0]),int(state.cell[1]))
	if position_map!=int(state.map_id) or position_cell!=at:
		pending_resume = {}
		var why := "服务器重启后没有恢复：角色已不在原来的位置（%s (%d, %d)）。" % [backend.map_name(int(state.map_id)),at.x,at.y]
		if str(state.kind)!="training":_record_stop("flow" if str(state.kind)=="flow" else "hunt","停止",why)
		log_line("[重启后自动恢复] "+why)
		return
	if backend.battle_open or bool(backend.battle.snapshot().get("active",false)):return
	pending_resume = {}
	settings = state.get("settings",{}).duplicate(true)
	if not settings.has("speed"):settings.speed = DEFAULT_SPEED
	match str(state.kind):
		"flow":_resume_flow(state)
		"hunt":_resume_hunt(state)
		"training":_resume_training(state)

## Starts the hunt with the saved filter and continues the same run from the
## same roll (every roll has its own seed, so nothing is skipped or repeated).
func _restore_hunt(saved: Dictionary) -> bool:
	if not start_hunt(saved.get("filter",{})):return false
	hunt_run_seed = int(saved.run_seed)
	hunt_rolls = int(saved.rolls)
	hunt_inspected = int(saved.inspected)
	hunt_best = int(saved.best)
	hunt_mixed_skips = int(saved.get("mixed",0))
	hunt_started_usec = Time.get_ticks_usec()-int(float(saved.get("elapsed",0.0))*1000000.0)
	_emit_status()
	return true

func _resume_hunt(state: Dictionary) -> void:
	if not _restore_hunt(state.get("hunt",{})):
		_record_stop("hunt","停止","服务器重启后无法恢复筛选：%s" % hunt_status)
		return
	_record_stop("hunt","已恢复","%s：从第 %d 组接着筛选。" % [RESUMED,hunt_rolls+1])
	log_line("[自动抓极品] %s" % RESUMED)

func _resume_training(state: Dictionary) -> void:
	var saved: Dictionary = state.get("training",{})
	var pet_id := str(saved.get("pet_id",""))
	if not pet_id.is_empty():start_pet_training(pet_id,int(saved.get("level",120)),{},settings.duplicate(true))
	else:
		var kept := settings.duplicate(true)
		start_training()
		settings = kept
	if not running:
		log_line("[自动练级] 服务器重启后无法恢复：%s" % stop_reason);return
	battles = int(saved.get("battles",0));skipped = int(saved.get("skipped",0))
	earned_xp = int(saved.get("earned_xp",0));earned_pet_xp = int(saved.get("earned_pet_xp",0));initial_level = int(saved.get("initial_level",initial_level))
	turn_text = RESUMED
	log_line("[自动练级] %s（已打 %d 场）" % [RESUMED,battles])
	_emit_status()

func _resume_flow(state: Dictionary) -> void:
	var saved: Dictionary = state.get("flow",{})
	for field in RESUME_FLOW_FIELDS:
		if saved.has(field):set(field,saved[field])
	showcase_last_template = int(showcase_last_template)
	# A file from before per-species queues holds one shared queue: grouping
	# splits it into each species' queue, in the same order within a species.
	_sort_queue()
	flow_map = int(state.map_id)
	flow_cell = Vector2i(int(state.cell[0]),int(state.cell[1]))
	flow_stat_filters = _int_keys(flow_stat_filters)
	flow_stop_pending = ""
	survey = {}
	_pets_key = ""
	timer_started_msec = int(timer_clock.call())-int(float(saved.get("elapsed",0.0))*1000.0)
	timer_running = true
	var phase := flow_phase
	var notes: PackedStringArray = []
	# start_hunt checks the capture helper as the cycle's hunt does.
	flow_phase = "hunt"
	if state.has("hunt") and (flow_showcase or phase=="hunt"):
		if not _restore_hunt(state.hunt):
			stop_cycle("服务器重启后无法恢复筛选：%s" % hunt_status);return
		notes.append("从第 %d 组接着筛选" % (hunt_rolls+1))
	else:
		# Queued hits and survey picks replay from this place's encounters.
		_prepare_catalog(flow_hunt_request)
		if phase=="hunt" and not flow_showcase:phase = "restart"
	if bool(saved.get("survey",false)):notes.append("摸底进度没有保存，重新摸底")
	match phase:
		"hunt":pass
		"capture":
			var note := _resume_capture()
			if flow_phase=="paused":return
			notes.append(note)
		"train":
			var note := _resume_train()
			if flow_phase=="paused":return
			notes.append(note)
		_:flow_phase = "restart"
	if not showcase_queue.is_empty():notes.append("排队 %d 只" % showcase_queue.size())
	var text := RESUMED+("：" + "，".join(notes) if not notes.is_empty() else "")+"。"
	_record_stop("flow","已恢复",text,_involved_pet())
	_showcase_line("resumed",text)
	if not flow_showcase:flow_reason = text
	_emit_status()
	_emit_event({"kind":"flow_hunt"})

## The index in the party of the pet the interrupted capture caught (new
## since the capture began and the same individual), or -1.
func _caught_index() -> int:
	if flow_matched_actor.is_empty():return -1
	var pets: Array = backend.session.snapshot().pets
	for i in range(pets.size()):
		if not flow_known_ids.has(str(pets[i].get("pet_id",""))) and same_capture(pets[i],flow_matched_actor):return i
	return -1

## The capture was cut short. Caught already (settled before the restart):
## the training goes on. Otherwise the same pet is fought for again: with
## 后台搜宠 its queued hit goes back to the front of the queue (replayed and
## checked before the battle), else its roll is replayed here.
func _resume_capture() -> String:
	var caught := _caught_index()
	var name := str(flow_matched_actor.get("name",""))
	if caught>=0:
		flow_pet_id = str(backend.session.snapshot().pets[caught].pet_id)
		_capture_succeeded()
		if not backend.session.select_pet(caught):stop_cycle("新伙伴无法出战。");return ""
		if flow_showcase:
			flow_phase = "train"
			_showcase_train()
		else:_level_to_120()
		return "%s 已在重启前抓到，接着练到120级" % name
	if flow_showcase:
		if not showcase_current.is_empty():
			showcase_queue.append(showcase_current)
			_sort_queue()
			# Its species is served next (the smallest species after this).
			showcase_last_template = _template_of(showcase_current)-1
		showcase_current = {}
		flow_matched_actor = {};flow_matched_index = -1;flow_matched_roll = {}
		flow_phase = "hunt"
		return "重启时正在抓的 %s 放回排队，按原种子复核后重新开战" % name
	var roll := flow_matched_roll
	var survey_pick := flow_target_survey
	flow_phase = "hunt"
	if roll.is_empty() or not start_hunt(flow_hunt_request):
		flow_phase = "restart"
		return "重启时正在抓的 %s 无法重新开战，已跳过" % name
	var rng := RandomNumberGenerator.new()
	rng.seed = FastHunt.roll_seed(int(roll.run_seed),int(roll.index))
	var troop: Dictionary = hunt_catalog.roll(hunt_map,hunt_cell,rng,backend.session._profile.get("original_items",[]))
	var slot := int(roll.slot)
	var enemies: Array = troop.get("enemies",[])
	if slot<0 or slot>=enemies.size() or not same_capture(enemies[slot],flow_matched_actor):
		_stopping_cycle = true
		stop_hunt("重启后复核不一致。")
		_stopping_cycle = false
		flow_phase = "restart"
		return "重启时正在抓的 %s 按原种子复核不一致，已跳过" % name
	_open_hit(troop,slot,HuntRules.quality(enemies[slot],backend.encounter_catalog.data),roll)
	if flow_phase=="capture":flow_target_survey = survey_pick
	return "按原种子重新开战抓 %s" % name

## The training was cut short: it goes on from the level the pet has.
func _resume_train() -> String:
	var pets: Array = backend.session.snapshot().pets
	var index := -1
	for i in range(pets.size()):
		if str(pets[i].get("pet_id",""))==flow_pet_id:index = i
	if index<0:
		stop_cycle("服务器重启后找不到正在练级的宠物 %s，请手动检查。" % flow_pet_id);return ""
	var pet: Dictionary = pets[index]
	flow_phase = "train"
	if flow_showcase:
		if int(pet.level)>=120:_showcase_finished()
		else:
			backend.session.select_pet(index)
			_showcase_train()
	else:_level_to_120()
	return "%s %s 从 %d 级接着练" % [str(pet.get("name","")),flow_pet_id,int(pet.level)]

## The pet the cycle is working on, for the log: the captured pet once there
## is one, else the matched or revealed wild pet (name only).
func _involved_pet() -> Dictionary:
	if not flow_pet_id.is_empty():
		var pet := _flow_pet()
		return {"pet_id":flow_pet_id,"name":str(pet.get("name",flow_matched_actor.get("name","")))}
	if not flow_matched_actor.is_empty():return {"name":str(flow_matched_actor.get("name",""))}
	if not showcase_current.is_empty():return {"name":str(showcase_current.get("actor",{}).get("name",""))}
	return {}

static func skippable_battle_stop(reason: String) -> bool:
	return reason in SKIPPABLE_BATTLE_STOPS or reason.ends_with("体力达到停机线")

## After the capture battle: true (and the hit skipped or the cycle stopped)
## when it ended without the matched pet. A manual stop, a full party or
## anything else that needs the player stops; the target going down, a lost or
## overlong battle, or a closed battle without the pet skip it.
func _capture_failed() -> bool:
	if stop_reason!="本场自动战斗已完成":
		if skippable_battle_stop(stop_reason):_skip_hit("捕捉失败",stop_reason)
		else:stop_cycle(stop_reason)
		return true
	var battle: Dictionary = backend.battle.snapshot()
	if battle.get("active",false) or str(battle.get("battle_id",""))!=flow_capture_battle_id:
		# Another battle is open (say, from another device): leave it to the player.
		if backend.battle_open:stop_cycle("捕捉战斗状态已改变。")
		else:_skip_hit("捕捉失败","捕捉战斗状态已改变。")
		return true
	var enemies: Array = battle.get("enemies",[])
	if flow_matched_index<0 or flow_matched_index>=enemies.size() or not enemies[flow_matched_index].get("captured",false):
		_skip_hit("捕捉失败","目标未捕获；未改抓其他敌人。")
		return true
	return false

func _capture_succeeded() -> void:
	flow_skip_kind = ""
	flow_skip_streak = 0

## Steps past a hit the cycle cannot finish: logs 已跳过, ends a capture battle
## still open (no rewards), and goes back to searching (展示模式: the next
## queued hit). The same kind SKIP_LIMIT times in a row stops the cycle.
func _skip_hit(kind: String, reason: String) -> void:
	if kind==flow_skip_kind:flow_skip_streak += 1
	else:
		flow_skip_kind = kind
		flow_skip_streak = 1
	if flow_skip_streak>=SKIP_LIMIT:
		stop_cycle("连续%d次%s，已停止：%s" % [SKIP_LIMIT,kind,reason]);return
	var pet := _involved_pet()
	if running:
		release_clone_override()
		running = false
	compact_active = false
	backend.set_capture_assist(false)
	backend.abandon_battle()
	flow_skipped_count += 1
	flow_skip_note = "%s · %s" % [kind,reason]
	_record_stop("flow","已跳过",reason,pet)
	if flow_showcase:
		_showcase_restore()
		_showcase_line("skipped","已跳过：%s" % flow_skip_note)
	else:flow_reason = flow_skip_note
	flow_phase = "restart"
	_emit_status()
	_emit_event({"kind":"flow_skipped","reason":reason,"note":"已跳过一只 · "+flow_skip_note})

# ---- 后台搜宠 (showcase) ---------------------------------------------------
# The cycle keeps searching with the native helper while the player watches
# the normal game: a found pet's capture battle as any capture is shown, then
# 自动练级 to Lv.120 with the player's own 经验倍率 and 战斗速度, every battle
# played in full. Hits found meanwhile wait in showcase_queue. The name the
# player sees is AutomationSettings.SHOWCASE_NAME.

## Two hits of one species, best first by the species' 保留规则 order (第一/第二/第三,
## default 攻击 → 敏捷 → 血), then the other keys (三围合 first), then the
## earlier roll. A full queue lets the last one go.
func _showcase_better(a: Dictionary, b: Dictionary) -> bool:
	var rule: Dictionary = raw_filter_for(int(a.actor.get("template_id",-1))).get("keep_rule",{})
	for key in StatFilter.rank_order(Array(rule.get("order",["attack","speed","max_hp"]))):
		var va := StatFilter.rank_value(a.prediction,key)
		var vb := StatFilter.rank_value(b.prediction,key)
		if va!=vb:return va>vb
	return int(a.index)<int(b.index)

func queue_limit() -> int:
	return clampi(int(flow_hunt_request.get("queue",SHOWCASE_QUEUE_MAX)),1,50)

## A hit found while the player watches (or idle). When its species' queue is
## over the limit the lowest ranked hit of that species, possibly this one, is
## dropped and written to 放生记录 as 未捕获·排队已满; other species' queues
## are never touched.
func _showcase_enqueue(index: int, slot: int, troop: Dictionary, quality: Dictionary) -> void:
	var actor: Dictionary = troop.enemies[slot]
	var projected: Dictionary = Progression.project_pet(actor,120)
	_showcase_add({"index":index,"slot":slot,"run_seed":hunt_run_seed,"actor":actor.duplicate(true),"troop":troop.duplicate(true),"quality":quality.duplicate(true),
		"prediction":_prediction(projected)})

## Queues an entry (a hit, or a survey pick marked survey) in its species'
## queue, best first; each species' queue keeps at most queue_limit().
func _showcase_add(entry: Dictionary) -> void:
	showcase_queue.append(entry)
	_sort_queue()
	_prune_below_threshold()
	for id in _queue_templates():
		while _species_queue(id).size()>queue_limit():
			var last: Dictionary = _species_queue(id).back()
			showcase_queue.erase(last)
			_drop_queued(last)
	_emit_status()

static func _template_of(entry: Dictionary) -> int:
	return int(entry.get("actor",{}).get("template_id",-1))

## Groups the queue by species (template id), each species best first.
func _sort_queue() -> void:
	showcase_queue.sort_custom(func(a,b):
		if _template_of(a)!=_template_of(b):return _template_of(a)<_template_of(b)
		return _showcase_better(a,b))

## The species with queued hits, in queue order.
func _queue_templates() -> Array:
	var result: Array = []
	for entry in showcase_queue:
		if not result.has(_template_of(entry)):result.append(_template_of(entry))
	return result

## One species' queue, best first.
func _species_queue(template_id: int) -> Array:
	return showcase_queue.filter(func(e):return _template_of(e)==template_id)

## The next hit to catch: the best of the species after the one taken last
## (round-robin over the species with hits), so no species waits behind
## another's. A survey pick is ranked in its species' queue like any hit.
func _take_queued() -> Dictionary:
	var templates := _queue_templates()
	if templates.is_empty():return {}
	var chosen: int = templates[0]
	for id in templates:
		if int(id)>showcase_last_template:
			chosen = int(id);break
	var entry: Dictionary = _species_queue(chosen)[0]
	showcase_queue.erase(entry)
	showcase_last_template = chosen
	return entry

## Queued hits a better one (queued or owned) has put below the thresholds are
## let go at once, instead of each when its turn comes. Each species' queue is
## best first, so each hit is judged against owned pets, picks, the hit being
## caught and the kept hits ranked above it (entry_maxima), never itself: the
## best hit always survives. Each one let go is written to 放生记录. With fixed
## values (absolute mode) better hits raise nothing: only the values count,
## so this lets hits go only after the player raised them.
func _prune_below_threshold() -> void:
	var kept: Array = []
	var kept_hits: Array = []
	var dropped: Array = []
	for entry in showcase_queue:
		if bool(entry.get("survey",false)):
			kept.append(entry);continue
		var id := int(entry.actor.get("template_id",-1))
		var best := entry_maxima(entry,kept_hits)
		var chosen := StatFilter.resolve(raw_filter_for(id),best)
		if not StatFilter.enabled(chosen) or StatFilter.evaluate(entry.prediction,chosen):
			kept.append(entry);kept_hits.append(entry);continue
		dropped.append(entry)
		_log_uncaught(entry,"门槛已提高","门槛已提高（%s）" % StatFilter.describe_thresholds(raw_filter_for(id),best),_same_species(_entry_others(entry,kept_hits),id))
	if dropped.is_empty():return
	showcase_queue = kept
	var names: Array = dropped.map(func(e):return "第%d组 %s（预测%s）" % [int(e.index)+1,str(e.actor.get("name","")),_stat_text(e.prediction)])
	var id0 := int(dropped[0].actor.get("template_id",-1))
	_showcase_line("dropped","门槛已提高（%s），排队中的%s不再够格，已放弃" % [_template_name(id0)+"："+StatFilter.describe_thresholds(raw_filter_for(id0),species_maxima(id0)),"、".join(names)])

## A hit its species' full queue let go (already taken out of the queue).
func _drop_queued(entry: Dictionary) -> void:
	var limit := queue_limit()
	var p: Dictionary = entry.prediction
	# The hits of its species just above it, closest first.
	var same := _species_queue(_template_of(entry))
	var above: Array = same.slice(maxi(0,same.size()-3))
	above.reverse()
	var reason := "%s的排队已满（每个品种上限%d），排在第%d" % [_template_name(_template_of(entry)),limit,limit+1]
	_log_uncaught(entry,"排队已满",reason,above)
	_showcase_line("dropped","排队已满：放弃第%d组 %s（预测三围合%d），%s" % [int(entry.index)+1,str(entry.actor.get("name","")),int(p.attack)+int(p.defence)+int(p.speed),reason])

## The first three pending entries of a species (the ones that beat a hit).
static func _same_species(entries: Array, template_id: int) -> Array:
	return entries.filter(func(e):return int(e.actor.get("template_id",-1))==template_id).slice(0,3)

## A found hit let go before its capture, in 放生记录 as 未捕获, with its roll,
## run seed and slot so the pet can be replayed later (FastHunt.roll_seed).
## The seed is kept as text: it is 64-bit and JSON numbers are doubles.
func _log_uncaught(entry: Dictionary, source: String, reason: String, beaten_by: Array) -> void:
	var pet: Dictionary = entry.actor.duplicate(true)
	pet.pet_id = "第%d组" % (int(entry.index)+1)
	var beaters: Array = beaten_by.map(func(e):return ReleaseLog.beater({"pet_id":"第%d组" % (int(e.index)+1),"name":str(e.actor.get("name",""))},e.prediction))
	var logged := ReleaseLog.entry(pet,"未捕获",source,reason,beaters,entry.prediction)
	logged.uncaught = true
	logged.roll = int(entry.index)+1
	logged.run_seed = str(int(entry.get("run_seed",hunt_run_seed)))
	logged.slot = int(entry.slot)
	backend.session.release_events.append(logged)

func _queue_summary() -> Array:
	var result: Array = []
	for entry in showcase_queue:
		var p: Dictionary = entry.prediction
		result.append({"roll":int(entry.index)+1,"name":str(entry.actor.get("name","")),"sum":int(p.attack)+int(p.defence)+int(p.speed),"attack":int(p.attack),"defence":int(p.defence),"speed":int(p.speed),"max_hp":int(p.max_hp)})
	return result

## 宠物记录's 排队 tab (backend hunt_queue): the hit being caught or trained
## (current, phase capture/train/restart) and every species' queue (groups:
## template_id, name, count; limit is per species) best first, each hit with
## its rank in its species' queue (1-based, 0 for current), Lv, 成长档 and predicted Lv.120
## stats. active: a find-pet cycle is running with 后台搜宠.
func queue_view() -> Dictionary:
	var entries: Array = []
	if not showcase_current.is_empty() and flow_phase in ["capture","train","restart"]:
		var row := _queue_row(showcase_current,0)
		row.current = true
		row.phase = flow_phase
		# Training: the caught pet's level now.
		var pet := _flow_pet() if not flow_pet_id.is_empty() else {}
		if not pet.is_empty():
			row.level = int(pet.get("level",row.level))
			row.pet_id = flow_pet_id
		entries.append(row)
	var groups: Array = []
	for id in _queue_templates():
		var queued := _species_queue(id)
		groups.append({"template_id":id,"name":_template_name(id),"count":queued.size()})
		for i in range(queued.size()):entries.append(_queue_row(queued[i],i+1))
	return {"active":flow_active() and flow_showcase,"showcase":flow_showcase,"phase":flow_phase,"limit":queue_limit(),"size":showcase_queue.size(),"groups":groups,"entries":entries}

static func _queue_row(entry: Dictionary, rank: int) -> Dictionary:
	var actor: Dictionary = entry.get("actor",{})
	var p: Dictionary = entry.get("prediction",{})
	var quality: Dictionary = entry.get("quality",{})
	var offsets: Array = quality.get("offsets",[]) if bool(quality.get("valid",false)) else []
	return {"rank":rank,"roll":int(entry.get("index",-1))+1,"name":str(actor.get("name","")),"template_id":int(actor.get("template_id",-1)),"level":int(actor.get("level",1)),
		"offsets":offsets.duplicate(),"total_offset":int(quality.get("total_offset",0)),"full":offsets.size()==4 and int(quality.get("total_offset",0))==8,"survey":bool(entry.get("survey",false)),"current":false,
		"attack":int(p.get("attack",0)),"defence":int(p.get("defence",0)),"speed":int(p.get("speed",0)),"max_hp":int(p.get("max_hp",0)),"sum":int(p.get("attack",0))+int(p.get("defence",0))+int(p.get("speed",0))}

## One line of the scrolling info block every watching device shows at the top
## left: found, captured, Lv.120, 留下 / 放生, skips and queue drops.
func _showcase_line(kind: String, text: String) -> void:
	_showcase_log_serial += 1
	showcase_log.append({"id":_showcase_log_serial,"kind":kind,"text":text})
	while showcase_log.size()>SHOWCASE_LOG_MAX:showcase_log.pop_front()
	_emit_status()

func _flow_pet() -> Dictionary:
	for pet in backend.session.snapshot().pets:
		if str(pet.get("pet_id",""))==flow_pet_id:return pet
	return {}

static func _stat_text(stats: Dictionary) -> String:
	return "攻%d 防%d 敏%d 血%d · 三围合%d" % [int(stats.attack),int(stats.defence),int(stats.speed),int(stats.max_hp),int(stats.attack)+int(stats.defence)+int(stats.speed)]

## One find-pet step while searching in the background.
func _showcase_step() -> void:
	if not flow_stop_pending.is_empty() and flow_phase in ["restart","hunt"]:
		stop_cycle("本只练完，已停止：%s" % flow_stop_pending);return
	match flow_phase:
		"hunt":
			if not showcase_queue.is_empty():_showcase_capture()
			elif not hunt_running:stop_cycle(hunt_status if not hunt_status.is_empty() else "筛选已停止。")
		"capture":
			if not running:_showcase_captured()
		"train":
			if running:return
			if stop_reason=="目标宠物已达到等级目标":_showcase_finished();return
			# A lost or overlong training battle: fight on (the pet keeps its
			# levels); the same failure SKIP_LIMIT times in a row stops the cycle.
			if skippable_battle_stop(stop_reason):
				if stop_reason==flow_skip_kind:flow_skip_streak += 1
				else:
					flow_skip_kind = stop_reason
					flow_skip_streak = 1
				if flow_skip_streak>=SKIP_LIMIT:stop_cycle("连续%d次%s，已停止。" % [SKIP_LIMIT,stop_reason]);return
				_record_stop("flow","已重试",stop_reason,_involved_pet())
				_showcase_line("retry","练级战斗没打完（%s），继续练级。" % stop_reason)
				backend.abandon_battle()
				_showcase_train()
				return
			stop_cycle(stop_reason)
		"restart":_showcase_resume()

## Takes the best queued hit, replays its roll from its own seed, checks it is
## the same troop, and opens its capture battle, presented like any capture.
func _showcase_capture() -> void:
	refresh_maxima()
	showcase_current = _take_queued()
	var entry := showcase_current
	var actor: Dictionary = entry.actor
	flow_target_survey = bool(entry.get("survey",false))
	# Judged without itself: it is the best queued hit, so only owned pets and
	# picks count (entry_maxima).
	flow_target_filter = filter_excluding(entry,[]).duplicate(true)
	var p: Dictionary = entry.prediction
	# The thresholds may have risen since this hit was queued (a better pet
	# arrived): one no longer good enough is let go. Survey picks are caught.
	if not flow_target_survey and StatFilter.enabled(flow_target_filter) and not StatFilter.evaluate(p,flow_target_filter):
		var thresholds := StatFilter.describe_thresholds(raw_filter_for(int(actor.get("template_id",-1))),entry_maxima(entry,[]))
		_log_uncaught(entry,"门槛已提高","门槛已提高（%s）" % thresholds,_same_species(_entry_others(entry,[]),int(actor.get("template_id",-1))))
		_showcase_line("dropped","门槛已提高（%s），放弃第%d组 %s（预测%s）" % [thresholds,int(entry.index)+1,str(actor.get("name","")),_stat_text(p)])
		showcase_current = {}
		return
	var full := int(entry.quality.get("total_offset",0))==8
	var rarity: Array = Rarity.describe(int(actor.get("template_id",-1)),p,full)
	_showcase_line("found","%s%s%s · 预测120级 %s%s · 排队%d" % ["摸底选中" if flow_target_survey else "找到","满档" if full else "",str(actor.get("name","")),_stat_text(p),"（"+str(rarity[0]).get_slice("：",1)+"）" if full and rarity.size()>0 and str(rarity[0]).contains("1/") else "",showcase_queue.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = FastHunt.roll_seed(int(entry.run_seed),int(entry.index))
	var troop: Dictionary = hunt_catalog.roll(flow_map,flow_cell,rng,backend.session._profile.get("original_items",[])) if hunt_catalog!=null else {}
	if troop.is_empty() or JSON.stringify(troop)!=JSON.stringify(entry.troop):
		_skip_hit("复核不一致","排队的第 %d 组复核不一致，没有进入战斗。" % (int(entry.index)+1));return
	if backend.session.snapshot().pets.size()>=GameSession.PET_CAPACITY:
		stop_cycle("宠物栏已满，请自行存放伙伴后再开始。");return
	_protect_pets()
	var config: Dictionary = backend.session.start_wild_battle_config(troop,_mixed_clear_target(troop,int(entry.slot)))
	if config.is_empty():stop_cycle("战斗校验未通过，已停止。");return
	var refusal := mixed_refusal(troop,int(entry.slot),config)
	if not refusal.is_empty():
		_showcase_line("dropped","第%d组 %s 没有进入战斗：%s" % [int(entry.index)+1,str(actor.get("name","")),refusal])
		stop_cycle(refusal);return
	flow_known_ids.clear()
	# Warehouse pets too: one withdrawn during the capture battle is not new.
	for pet in backend.session.snapshot().pets+backend.session.snapshot().get("pet_storage",[]):flow_known_ids[str(pet.pet_id)] = true
	flow_matched_index = int(entry.slot)
	flow_matched_actor = actor.duplicate(true)
	compact_active = false
	showcase_show_battle = true
	backend.open_battle(config)
	flow_capture_battle_id = str(backend.battle.snapshot().get("battle_id",""))
	flow_phase = "capture"
	start_capture_battle(flow_matched_index,true)
	if not running:stop_cycle("无法开始自动捕捉，请手动处理当前战斗。");return
	_emit_status()
	# Devices clear the stage for the battle (the hunt window folds away).
	_emit_event({"kind":"flow_reveal"})

## After the capture battle: the same checks as the full-speed cycle, then
## 自动练级 to Lv.120.
func _showcase_captured() -> void:
	showcase_show_battle = false
	if _capture_failed():return
	var fresh: Array = []
	var pets: Array = backend.session.snapshot().pets
	for i in range(pets.size()):
		if not flow_known_ids.has(str(pets[i].get("pet_id",""))):fresh.append(i)
	if fresh.size()!=1 or not same_capture(pets[fresh[0]],flow_matched_actor):
		stop_cycle("无法唯一确认新捕获伙伴，请手动检查宠物栏。");return
	flow_pet_id = str(pets[fresh[0]].pet_id)
	_capture_succeeded()
	if not backend.session.select_pet(int(fresh[0])):stop_cycle("新伙伴无法出战。");return
	backend.save()
	backend.publish()
	_showcase_line("captured","捕获成功：%s %s，开始练到120级。" % [str(pets[fresh[0]].get("name","")),flow_pet_id])
	flow_phase = "train"
	_showcase_train()

## 自动练级 for the caught pet: the player's own 经验倍率 (training.xp), every
## battle shown at this device's 战斗速度, the pet active and the 五人镜像队 made
## of the player's other best pets. The runner stops only between battles,
## once the pet reaches Lv.120.
func _showcase_train() -> void:
	if _flow_pet().is_empty():stop_cycle("目标宠物不在随身队伍");return
	# Set before the first battle opens: with a high 经验倍率 that battle may
	# be the only one, and it must be shown, not resolved compactly.
	# A Lv1 pet is easily hurt: no HP stop line (carried pets are healed
	# between battles; a defeat is fought again, see _showcase_step).
	backend.session.clone_best_others = true
	showcase_show_battle = true
	if not start_pet_training(flow_pet_id,120,{},{"xp":int(profile_settings().xp),"compact":false,"hp":-1,"limit":1000000}):
		showcase_show_battle = false
		backend.session.clone_best_others = false
		stop_cycle("无法开始练级："+stop_reason);return
	_emit_status()

## Lv.120 reached: store and tidy as the full-speed cycle does, then say what
## became of the pet.
func _showcase_finished() -> void:
	showcase_show_battle = false
	backend.session.clone_best_others = false
	release_clone_override()
	var found := _flow_pet()
	if found.is_empty() or int(found.level)<120:stop_cycle("目标宠物未达到120级，请手动检查。");return
	var pet_id := flow_pet_id
	var template := int(found.get("template_id",-1))
	var actual := {"attack":int(found.attack),"defence":int(found.defence),"speed":int(found.speed),"max_hp":int(found.max_hp)}
	var predicted: Dictionary = showcase_current.get("prediction",{})
	_showcase_line("level","%s %s 练到120级：%s%s" % [str(found.get("name","")),pet_id,_stat_text(actual)," · 与预测一致" if actual==predicted else ""])
	complete_trained_pet(found)
	var outcome := ""
	for event in backend.session.release_events:
		if str(event.get("pet_id",""))==pet_id:outcome = "放生：%s" % str(event.get("reason",""))
	if outcome.is_empty():
		var reasons: Array = KeepRule.evaluate(KeepRule.species_pets(backend.session.snapshot(),template),flow_target_filter.get("keep_rule",{}),KeepRule.always_kept(backend.session.snapshot())).get("reasons",{}).get(pet_id,[])
		outcome = "留下：%s" % ("、".join(reasons) if not reasons.is_empty() else "已存入仓库")
		if flow_last_result.begins_with("未达标"):outcome = "未达标，"+outcome
	_showcase_line("released" if outcome.begins_with("放生") else "kept","%s %s %s" % [str(found.get("name","")),pet_id,outcome])
	if flow_phase=="compare":
		if hunt_running:stop_hunt(flow_reason)
		if not showcase_queue.is_empty():_showcase_line("dropped","收集完成，排队的 %d 只已放弃。" % showcase_queue.size())
		showcase_queue = []
		_emit_status()

## Settings the run changed for its training go back: 五人镜像队 and its
## composition.
func _showcase_restore() -> void:
	showcase_show_battle = false
	backend.session.clone_best_others = false
	release_clone_override()

## Back to searching: the next queued hit is taken on the following step.
func _showcase_resume() -> void:
	if not flow_stop_pending.is_empty():
		stop_cycle("本只练完，已停止：%s" % flow_stop_pending);return
	showcase_current = {}
	flow_pet_id = "";flow_matched_actor = {};flow_matched_index = -1;flow_capture_battle_id = ""
	flow_phase = "hunt"
	flow_reason = ""
	if not hunt_running and showcase_queue.is_empty() and not start_hunt(flow_hunt_request):
		stop_cycle(hunt_status);return
	_emit_status()

# ---- status ----------------------------------------------------------------

func status() -> Dictionary:
	return {
		"running":running,"compact":compact_active,"single_battle":single_battle,"capture_target":capture_target,
		"stop_reason":stop_reason,"battles":battles,"skipped":skipped,"earned_xp":earned_xp,"earned_pet_xp":earned_pet_xp,
		"turns":turns,"initial_level":initial_level,"settings":settings.duplicate(true),"training_pet_id":training_pet_id,
		"clone_override":clone_override_active,"previous_clone":previous_clone_enabled,"turn_text":turn_text,
		"finish_after_capture":finish_after_capture,"origin_map":origin_map,"origin_cell":[origin_cell.x,origin_cell.y],
		# Where the character is now (map -1 until a client has reported it).
		"position":{"map_id":position_map,"cell":[position_cell.x,position_cell.y]},
		"hunt":{"running":hunt_running,"rolls":hunt_rolls,"inspected":hunt_inspected,"best":hunt_best,"mixed":hunt_mixed_skips,"elapsed":hunt_elapsed,
			"filter":hunt_filter.duplicate(true),"status":hunt_status,"credit":hunt_credit,"last_hit":hunt_last_hit.duplicate(true),"map_id":hunt_map,"cell":[hunt_cell.x,hunt_cell.y],
			"fast":fast_hunt.running(),"fast_wanted":hunt_fast_wanted,"fast_note":hunt_fast_note,"fast_unavailable":fast_unavailable,
			"threads":fast_threads,"threads_used":fast_threads_now() if fast_share!=null and fast_share.joined() else threads_used(fast_threads),"cores":ServerSettings.cores(),
			"budget":threads_used(fast_threads),"hunters":fast_hunters()},
		"flow":{"phase":flow_phase,"reason":flow_reason,"pet_id":flow_pet_id,"stored_count":flow_stored_count,"last_result":flow_last_result,
			"last_stored_id":flow_last_stored_id,"last_stored_total":flow_last_stored_total,"map_id":flow_map,"cell":[flow_cell.x,flow_cell.y],
			"kept_count":flow_kept_count,"collected_count":flow_collected_count,"pruned_count":flow_pruned_count,"released_count":flow_released_count,"held_count":flow_held_count,"keep_auto":bool(flow_target_filter.get("keep_rule",{}).get("auto",false)),"predicted_rejects":flow_predicted_rejects,
			"best_predicted":flow_best_predicted.duplicate(),"skipped_count":flow_skipped_count,"skip_note":flow_skip_note,"showcase":flow_showcase,"queue":_queue_summary(),"queue_size":showcase_queue.size(),"current_roll":int(showcase_current.get("index",-1))+1 if not showcase_current.is_empty() else 0,
			"survey":survey_status(),"thresholds":thresholds_text(),
			"log":showcase_log.duplicate(true),"stop_pending":flow_stop_pending,"queue_limit":queue_limit(),"show_battle":showcase_show_battle and backend.battle_open,"collect_target":collect_target_text(),"elapsed":elapsed_seconds(),"timer_running":timer_running},
	}

## 摸底 for the hunt window and the minimized bar: {active, remaining,
## seconds, candidates, names, pending (picks not yet caught), last}.
func survey_status() -> Dictionary:
	return {"active":not survey.is_empty(),"remaining":survey_wall_remaining(),"seconds":survey_seconds,"hunters":fast_hunters(),"candidates":survey.get("candidates",{}).size(),
		"names":survey.get("templates",[]).map(_template_name),"pending":_pending_picks().size(),"last":str(survey_last.get("text",""))}

## The cycle's thresholds as the player reads them, one species per line:
## 「扬奇洛斯：三围合 ≥ 最高 627 − 1 = 626，或 攻击 ≥ 最高 301 − 1 = 300」.
func thresholds_text() -> String:
	if not flow_active() or hunt_filter.is_empty():return ""
	var lines: PackedStringArray = []
	for id in _hunt_templates():
		var chosen := raw_filter_for(id)
		if not StatFilter.enabled(chosen):continue
		lines.append("%s：%s" % [_template_name(id),StatFilter.describe_thresholds(chosen,species_maxima(id))])
		if lines.size()>=3:break
	return "\n".join(lines)

func _emit_status() -> void:
	backend.emit_event({"type":"auto_status","status":status()})

func _emit_event(detail: Dictionary) -> void:
	backend.emit_event({"type":"auto_event","detail":detail})

func _set_position(command: Dictionary) -> void:
	if command.has("map_id"):
		position_map = int(command.map_id)
		var cell: Array = command.get("cell",[0,0])
		position_cell = Vector2i(int(cell[0]),int(cell[1]))

func _reply(ok: bool, reason: String) -> Dictionary:
	return {"ok":ok,"reason":"" if ok else reason}

## JSON object keys arrive as strings; stat filters are keyed by template id.
static func _int_keys(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:result[int(key)] = source[key]
	return result

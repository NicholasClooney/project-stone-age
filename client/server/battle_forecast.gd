extends RefCounted
## Can the player plausibly win a troop before the hunt enters it? Used for
## 只进无其他敌人的遇敌's exception (hunt.mixed_if_stats): a find-pet cycle
## may take a Lv.1 pet meeting its 属性条件 from a troop with stronger
## enemies, and a lost battle costs charm and the pets' loyalty.
##
## The capture battle is fought out in advance with the real battle core
## (battle_session.gd, squad_battle_session.gd with a 五人镜像队) and the same
## turn choices as automation.gd step() makes for a capture that finishes the
## battle: 用精灵补血, the 停机线, the capture policy (battle_auto_policy.gd)
## and the shared clear-before-capture decision when configured. Other Lv.1
## pets are protected; after the target is caught the player escapes normally.
## A killed target is a failure even if the squad wins. The battle's own
## seed comes first, then the next ones, so the forecast does not hang on one
## lucky or unlucky roll. Nothing here touches the profile or the backend.
const BattleSession = preload("res://server/battle_session.gd")
const SquadBattleSession = preload("res://server/squad_battle_session.gd")
const Policy = preload("res://scripts/battle_auto_policy.gd")
const TRIALS := 5
## Battles of TRIALS that may go wrong and still count as a plausible win.
const ALLOWED_LOSSES := 1
const TURN_LIMIT := 200

## {ok, wins, trials, reason}: ok when at most ALLOWED_LOSSES of `trials`
## battles from seeds first_seed, first_seed + 1 … are not won; reason is
## why the first one that was not won ended.
static func forecast(config: Dictionary, settings: Dictionary, target: int, first_seed: int, trials: int = TRIALS) -> Dictionary:
	var wins := 0
	var reason := ""
	for k in range(trials):
		var result := simulate(config,settings,target,first_seed+k)
		if bool(result.won):wins += 1
		elif reason.is_empty():reason = str(result.reason)
	return {"ok":trials-wins<=ALLOWED_LOSSES,"wins":wins,"trials":trials,"reason":reason}

## One capture battle with `seed`: {won, reason}. Won means the troop was
## beaten (or the last enemy caught) before the run would stop.
static func simulate(config: Dictionary, settings: Dictionary, target: int, seed: int) -> Dictionary:
	var battle = SquadBattleSession.new() if not config.get("allies",[]).is_empty() else BattleSession.new()
	battle.rng_seed = seed
	battle.start_battle(config)
	battle.automated = true
	var run: Dictionary = settings.duplicate(true)
	run.preset = "capture"
	var line := int(run.get("hp",10))
	var starting_ride := int(battle.snapshot().get("ride_pet",-1))
	for turn in range(TURN_LIMIT+1):
		var state: Dictionary = battle.snapshot()
		if not bool(state.active):
			var outcome := str(state.outcome)
			var caught: bool = target>=0 and target<state.enemies.size() and bool(state.enemies[target].get("captured",false))
			var won: bool = (outcome in ["win","captured"] or (outcome=="escaped" and caught)) and (int(state.get("clear_capture_target",-1))<0 or caught)
			return {"won":won,"reason":"战败" if outcome=="defeat" else "目标未捕获" if not caught and int(state.get("clear_capture_target",-1))>=0 else outcome}
		if turn>=TURN_LIMIT:return {"won":false,"reason":"超过%d回合" % TURN_LIMIT}
		battle.set_capture_assist(str(run.preset)=="capture")
		if bool(run.get("spirit",true)):
			var cast: Dictionary = Policy.spirit_choice(state,line,false,int(run.get("side_heal",50)))
			if not cast.is_empty():
				battle.set_pet_command("defend")
				battle.submit_action(str(cast.action),int(cast.target))
				continue
		var low := Policy.health_stop(state,line,starting_ride)
		if not low.is_empty():return {"won":false,"reason":low}
		if str(run.preset)=="capture" and target>=0 and target<state.enemies.size() and bool(state.enemies[target].get("captured",false)) and int(state.get("clear_capture_target",-1))<0:
			run.preset = "attack"
		var decision: Dictionary = Policy.decide(state,run,target)
		if decision.has("stop"):return {"won":false,"reason":str(decision.stop)}
		battle.set_capture_assist(bool(decision.get("assist",str(run.preset)=="capture")))
		battle.set_pet_command(str(decision.pet))
		battle.set_pet_target(int(decision.target))
		battle.submit_action(str(decision.action),int(decision.target),int(decision.get("switch",-2)))
	return {"won":false,"reason":"超过%d回合" % TURN_LIMIT}

## 「巴朵兰恩 Lv.92、巴朵兰恩 Lv.95」: the troop's enemies above Lv.1.
static func stronger_enemies(troop: Dictionary) -> String:
	var names: PackedStringArray = []
	for enemy in troop.get("enemies",[]):
		if int(enemy.get("level",0))!=1:names.append("%s Lv.%d" % [str(enemy.get("name","")),int(enemy.level)])
	return "、".join(names)

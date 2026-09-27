extends RefCounted
## Local battle authority: presentation submits commands and receives copied state.
## Prototype balance, NOT reconstructed StoneAge damage/speed/stat formulas.
## Source cues: gmsv/battle/battle_command.c BattleCommandDispach;
## battle_event.c BATTLE_GuardAdjust and BATTLE_EscapeCheck (guard and escape).
## The original probabilistic guard and luck/level escape formulas are deferred.

const PLAYER_MAX_HP := 48
const ENEMY_MAX_HP := 32

var rng_seed: int = 42
var _rng := RandomNumberGenerator.new()
var _active := false
var _outcome := ""
var _player_hp := PLAYER_MAX_HP
var _enemy_hp := ENEMY_MAX_HP
var _turn := 0
var _escape_attempts := 0
var _events: Array[String] = []

func start_battle() -> Dictionary:
	# Repeated starts during combat cannot reset health or reroll the encounter.
	if _active:
		return snapshot()
	_rng.seed = rng_seed
	_active = true
	_outcome = ""
	_player_hp = PLAYER_MAX_HP
	_enemy_hp = ENEMY_MAX_HP
	_turn = 0
	_escape_attempts = 0
	_events = ["遭遇野生石器伙伴！"]
	return snapshot()

func submit_action(action: String) -> Dictionary:
	if not _active or action not in ["attack", "defend", "escape"]:
		return snapshot()
	_turn += 1
	_events.clear()
	var guarding := action == "defend"
	match action:
		"attack":
			var damage := mini(_enemy_hp, _rng.randi_range(8, 12))
			_enemy_hp -= damage
			_events.append("你发动攻击，造成 %d 点伤害。" % damage)
			if _enemy_hp == 0:
				_finish("win", "战斗胜利！")
				return snapshot()
		"defend":
			_events.append("你做好防御，减少本回合受到的伤害。")
		"escape":
			_escape_attempts += 1
			var chance := mini(100, 40 + 20 * _escape_attempts)
			if _rng.randi_range(1, 100) <= chance:
				_finish("escaped", "成功逃离战斗。")
				return snapshot()
			_events.append("逃跑失败！下次逃跑的机会增加了。")
	var enemy_damage := _rng.randi_range(5, 9)
	if guarding:
		enemy_damage = maxi(1, int(enemy_damage / 2.0))
	enemy_damage = mini(_player_hp, enemy_damage)
	_player_hp -= enemy_damage
	_events.append("对手发动攻击，造成 %d 点伤害。" % enemy_damage)
	if _player_hp == 0:
		_finish("defeat", "你暂时落败了，回村休息一下吧。")
	return snapshot()

func snapshot() -> Dictionary:
	# Never expose the internal mutable message array to the client.
	return {
		"active": _active, "outcome": _outcome,
		"player_hp": _player_hp, "player_max_hp": PLAYER_MAX_HP,
		"enemy_hp": _enemy_hp, "enemy_max_hp": ENEMY_MAX_HP,
		"turn": _turn, "events": _events.duplicate(),
	}

func _finish(outcome: String, message: String) -> void:
	_active = false
	_outcome = outcome
	_events.append(message)

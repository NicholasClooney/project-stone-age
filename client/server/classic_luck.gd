extends RefCounted
## char.c CHAR_setLuck: refresh at login only when native day/year changes.
## handletime.c constants (implementation, not its stale9000-second comment).
const ERA := 912771809
const DAY_SECONDS := 5400
static func day_at(timestamp: int) -> int:
	return int((timestamp-ERA)/DAY_SECONDS)
static func from_roll(roll: int) -> int:
	for pair in [[60,1],[30,2],[10,3],[3,4],[0,5]]:
		if roll>=pair[0]:return pair[1]
	return 5
static func login(player: Dictionary, timestamp: int, rng: RandomNumberGenerator) -> bool:
	if not player.has("charm"):player.charm=60
	if player.has("luck") and player.has("last_luck_time") and day_at(int(player.last_luck_time))==day_at(timestamp):return false
	player.luck=from_roll(rng.randi_range(0,99))
	player.last_luck_time=timestamp
	return true

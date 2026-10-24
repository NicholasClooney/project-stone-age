extends RefCounted
## Waiting in suites that drive clients over a real localhost WebSocket.
## Suites wait for a condition, never for a number of frames or seconds: on a
## loaded machine (parallel suites, other checkouts, a running hunt) a map load
## or a round trip can take many seconds. A wait that succeeds returns at once,
## so the deadline is generous and only bounds a real failure.
##
## Deadlines are game-clock seconds (client/scripts/clock.gd): under
## scripts/run.sh every frame counts as 1/60 s, so a suite never waits for wall
## time and a deadline is a number of frames. A far larger wall-clock ceiling
## only stops a suite that would otherwise loop forever.
const Clock=preload("res://scripts/clock.gd")
const DEADLINE := 60.0
## Wall-clock seconds a single wait may take at most, whatever the game clock
## says (frames can crawl while the machine is overloaded).
const WALL_CEILING := 600.0

## Waits physics frames until `condition` holds; false after `seconds`.
static func until(tree: SceneTree, condition: Callable, seconds: float = DEADLINE) -> bool:
	var deadline := Clock.ticks_msec()+int(seconds*1000)
	var wall_deadline := Time.get_ticks_msec()+int(maxf(WALL_CEILING,seconds)*1000)
	while Clock.ticks_msec() < deadline and Time.get_ticks_msec() < wall_deadline:
		if condition.call():return true
		await tree.physics_frame
	return bool(condition.call())

## One round trip over `game`'s link. The backend handles one connection's
## commands in order, so once the ping is answered it has handled everything
## this client sent before, such as the position report every client sends as
## it starts. Without this a later move by another device can arrive first and
## be undone by the stale report.
static func settle(tree: SceneTree, game) -> bool:
	var answered := [false]
	game.link.request({"type":"ping"},func(_reply):answered[0] = true)
	return await until(tree,func():return answered[0])

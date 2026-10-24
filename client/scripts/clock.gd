extends Node
## The game's clock. Scripts preload it (const Clock=preload(...)) and call
## its static functions; the ClockDriver autoload is one instance of it whose
## _process advances the virtual clock. (Suites run with --script, where an
## autoload cannot be referenced by name: scripts compile before it exists.)
## Elapsed-time checks in the game (throttles, timeouts, cooldowns,
## timestamps) read this instead of Time, so the game can run on a
## frame-driven virtual clock and a test never waits for wall time.
##
## scripts/run.sh starts every suite with STONE_AGE_TEST_CLOCK=virtual and
## --fixed-fps 60: the engine then treats each frame as 1/60 s however long it
## really took, and this clock advances by that delta (Engine.time_scale
## included). The game and the server never set the variable and read the real
## clocks.
##
## What keeps reading Time directly, on purpose: CPU budgets inside one frame
## (how much work fits before the frame ends), unique tokens made from
## get_ticks_usec, and performance measurements. They measure the machine,
## not the game.
static var virtual := false
static var _virtual_usec: int = 0
static var _unix_origin: float = 0.0

func _init() -> void:
	virtual = OS.get_environment("STONE_AGE_TEST_CLOCK") == "virtual"
	_unix_origin = Time.get_unix_time_from_system()
	# Advance before any other node sees this frame.
	process_priority = -1000

func _process(delta: float) -> void:
	if virtual:_virtual_usec += int(round(delta*1000000.0))

## Microseconds since the process (virtual: the suite) started.
static func ticks_usec() -> int:
	return _virtual_usec if virtual else Time.get_ticks_usec()

## Milliseconds since the process (virtual: the suite) started.
static func ticks_msec() -> int:
	@warning_ignore("integer_division")
	return _virtual_usec/1000 if virtual else Time.get_ticks_msec()

## Seconds since the Unix epoch; virtual time starts at the real time the
## suite began and then advances with the frames.
static func unix_time() -> float:
	return _unix_origin+_virtual_usec/1000000.0 if virtual else Time.get_unix_time_from_system()

## Tests only: jump the virtual clock ahead instead of waiting frames. Does
## nothing on the real clock.
static func advance(seconds: float) -> void:
	if virtual:_virtual_usec += int(round(seconds*1000000.0))

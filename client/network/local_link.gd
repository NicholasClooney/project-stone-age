extends RefCounted
## In-process delivery to a backend running in the same app. Both directions
## are deep-copied so neither side can hold the other's mutable state. Replies
## complete synchronously; events raised while handling a command arrive first.
signal message(event: Dictionary)

var backend
var _seq := 0

func _init(target) -> void:
	backend = target
	backend.event.connect(func(event: Dictionary): message.emit(event.duplicate(true)))

func is_local() -> bool:
	return true

## Sends one command. The reply is returned and also passed to done, so callers
## written against done work unchanged over an asynchronous link.
func request(command: Dictionary, done: Callable = Callable()) -> Dictionary:
	_seq += 1
	var sent: Dictionary = command.duplicate(true)
	sent.seq = _seq
	var reply: Dictionary = backend.handle(sent).duplicate(true)
	if done.is_valid():done.call(reply)
	return reply

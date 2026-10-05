extends RefCounted
## In-process delivery to a backend running in the same app. Both directions
## are deep-copied so neither side can hold the other's mutable state. Replies
## complete synchronously; events raised while handling a command arrive first.
signal message(event: Dictionary)

var backend
var _seq := 0
var _fee_binding:RefCounted
## Message counters for 开发者性能面板 (stats()); nothing is serialized here.
var messages_in := 0
var messages_out := 0

func _init(target) -> void:
	backend = target
	_fee_binding=backend.fee_attach(get_instance_id())
	backend.event.connect(func(event: Dictionary):
		messages_in += 1
		message.emit(event.duplicate(true)))

func is_local() -> bool:
	return true

func stats() -> Dictionary:
	return {"kind":"local","messages_in":messages_in,"messages_out":messages_out}

## Sends one command. The reply is returned and also passed to done, so callers
## written against done work unchanged over an asynchronous link.
func request(command: Dictionary, done: Callable = Callable()) -> Dictionary:
	_seq += 1
	messages_out += 1
	messages_in += 1
	var sent: Dictionary = command.duplicate(true)
	sent.seq = _seq
	sent.erase("_fee_binding")
	if str(sent.get("type","")) in ["permit_shop_open","permit_shop_choose","permit_shop_cancel"] or (str(sent.get("type",""))=="quest_close" and backend.original_quests.pending.get("phase","")=="permit_shop"):
		sent["_quest_connection"]=get_instance_id()
		sent["_fee_binding"]=_fee_binding
	var reply: Dictionary = backend.handle(sent).duplicate(true)
	if done.is_valid():done.call(reply)
	return reply

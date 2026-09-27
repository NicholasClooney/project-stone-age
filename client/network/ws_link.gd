extends RefCounted
## Delivery to a backend over WebSocket. Same surface as LocalLink, but replies
## are asynchronous: request() returns {"pending":true} and passes the real
## reply to done later. Commands are never queued while offline, so a
## purchase or battle action cannot replay after reconnecting. Call poll()
## every frame.
signal message(event: Dictionary)
signal connected
signal disconnected

const Codec = preload("res://network/codec.gd")
const PROTOCOL := 1
const MAX_BACKOFF := 10.0

var url := ""
var backend = null
var online := false
var superseded := false
var _peer: WebSocketPeer
var _seq := 0
var _callbacks: Dictionary = {}
var _retry_in := 0.0
var _backoff := 1.0
var _hello_seq := -1

func _init(server_url: String) -> void:
	url = server_url

func is_local() -> bool:
	return false

func connect_now() -> void:
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = 8 << 20
	_peer.outbound_buffer_size = 1 << 20
	if _peer.connect_to_url(url)!=OK:
		_peer = null
		_schedule_retry()

func request(command: Dictionary, done: Callable = Callable()) -> Dictionary:
	if not online:
		var offline := {"ok":false,"reason":"offline","type":"rejected"}
		if done.is_valid():done.call(offline)
		return offline
	_seq += 1
	var sent: Dictionary = command.duplicate(true)
	sent.seq = _seq
	if done.is_valid():_callbacks[_seq] = done
	_peer.send_text(Codec.encode(sent))
	return {"ok":false,"pending":true}

func poll(delta: float) -> void:
	if _peer==null:
		if superseded or url.is_empty():return
		_retry_in -= delta
		if _retry_in <= 0:connect_now()
		return
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if _hello_seq < 0:_send_hello()
			_drain()
		WebSocketPeer.STATE_CLOSING:
			_drain()
		WebSocketPeer.STATE_CLOSED:
			_drain()
			if _peer.get_close_code()==4000:superseded = true
			var was_online := online
			online = false
			_peer = null
			_hello_seq = -1
			for seq in _callbacks:_callbacks[seq].call({"ok":false,"reason":"offline","type":"rejected"})
			_callbacks.clear()
			if was_online:disconnected.emit()
			_schedule_retry()

func _drain() -> void:
	while _peer!=null and _peer.get_available_packet_count() > 0:
		_receive(_peer.get_packet().get_string_from_utf8())

func close() -> void:
	superseded = true
	if _peer!=null:_peer.close()

func _send_hello() -> void:
	_seq += 1
	_hello_seq = _seq
	_peer.send_text(Codec.encode({"type":"hello","protocol":PROTOCOL,"client_kind":OS.get_name(),"seq":_seq}))

func _receive(text: String) -> void:
	var incoming := Codec.decode(text)
	if incoming.is_empty():return
	if bool(incoming.get("reply",false)):
		var seq := int(incoming.get("seq",0))
		if seq==_hello_seq and incoming.has("snapshot"):
			online = true
			_backoff = 1.0
			message.emit(incoming.snapshot)
			connected.emit()
			return
		if _callbacks.has(seq):
			var done: Callable = _callbacks[seq]
			_callbacks.erase(seq)
			done.call(incoming)
		if not bool(incoming.get("ok",false)) and not str(incoming.get("reason","")).is_empty():
			message.emit({"type":"rejected","reason":incoming.reason,"seq":seq})
		return
	if str(incoming.get("type",""))=="superseded":
		superseded = true
	message.emit(incoming)

func _schedule_retry() -> void:
	if superseded:return
	_retry_in = _backoff
	_backoff = minf(_backoff*2.0,MAX_BACKOFF)

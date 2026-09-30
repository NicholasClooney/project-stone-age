extends RefCounted
## Delivery to a backend over WebSocket. Same surface as LocalLink, but replies
## are asynchronous: request() returns {"pending":true} and passes the real
## reply to done later. Commands are never queued while offline, so a
## purchase or battle action cannot replay after reconnecting. Call poll()
## every frame. A connection that goes silent (server killed without a close,
## Wi-Fi dropped, Mac asleep) is dropped after SILENCE_LIMIT seconds of
## missed heartbeats, so the client always learns it is offline.
signal message(event: Dictionary)
signal connected
signal disconnected

const Codec = preload("res://network/codec.gd")
const PROTOCOL := 1
const MAX_BACKOFF := 10.0
const PING_INTERVAL := 3.0
const SILENCE_LIMIT := 10.0

var url := ""
var backend = null
var online := false
var _closed := false
var _peer: WebSocketPeer
var _seq := 0
var _callbacks: Dictionary = {}
var _retry_in := 0.0
var _backoff := 1.0
var _hello_seq := -1
var _last_state := -1
var _started := false
var silence_limit := SILENCE_LIMIT
var _since_heard := 0.0
var _since_ping := 0.0
## Traffic counters for 开发者性能面板 (stats()); latency is the last
## heartbeat's round trip, -1 before the first.
var messages_in := 0
var messages_out := 0
var bytes_in := 0
var bytes_out := 0
var latency_ms := -1
var _ping_seq := -1
var _ping_msec := 0

func _init(server_url: String) -> void:
	url = server_url

func is_local() -> bool:
	return false

## Starts (or restarts) the connection; the link stays idle until called.
func connect_now() -> void:
	_started = true
	if _peer!=null:_peer.close()
	_hello_seq = -1
	_last_state = -1
	_since_heard = 0.0
	_since_ping = 0.0
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = 8 << 20
	_peer.outbound_buffer_size = 1 << 20
	var error := _peer.connect_to_url(url)
	print("[link] connecting to %s: error %d" % [url,error])
	if error!=OK:
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
	_send(Codec.encode(sent))
	return {"ok":false,"pending":true}

func _send(text: String) -> void:
	messages_out += 1
	bytes_out += text.to_utf8_buffer().size()
	_peer.send_text(text)

func stats() -> Dictionary:
	return {"kind":"remote","messages_in":messages_in,"messages_out":messages_out,"bytes_in":bytes_in,"bytes_out":bytes_out,"latency_ms":latency_ms}

func poll(delta: float) -> void:
	if _peer==null:
		if not _started or _closed or url.is_empty():return
		_retry_in -= delta
		if _retry_in <= 0:connect_now()
		return
	_peer.poll()
	var ready_state := _peer.get_ready_state()
	if ready_state!=_last_state:
		print("[link] %s state %d" % [url,ready_state])
		_last_state = ready_state
	match ready_state:
		WebSocketPeer.STATE_OPEN:
			if _hello_seq < 0:_send_hello()
			_drain()
			_heartbeat(delta)
		WebSocketPeer.STATE_CONNECTING:
			_heartbeat(delta)
		WebSocketPeer.STATE_CLOSING:
			_drain()
		WebSocketPeer.STATE_CLOSED:
			_drain()
			_drop()

## Counts frame time rather than wall time, so a browser tab that was hidden
## (and not polling) is not mistaken for a dead server when it comes back.
func _heartbeat(delta: float) -> void:
	if _peer==null:return
	_since_heard += delta
	if _since_heard > silence_limit:
		print("[link] %s silent for %.0f s, dropping" % [url,_since_heard])
		_peer.close()
		_drop()
		return
	_since_ping += delta
	if online and _since_ping >= PING_INTERVAL:
		_since_ping = 0.0
		_seq += 1
		_ping_seq = _seq
		_ping_msec = Time.get_ticks_msec()
		_send(Codec.encode({"type":"ping","seq":_seq}))

func _drop() -> void:
	var was_online := online
	online = false
	_peer = null
	_hello_seq = -1
	var pending := _callbacks
	_callbacks = {}
	for seq in pending:pending[seq].call({"ok":false,"reason":"offline","type":"rejected"})
	if was_online:disconnected.emit()
	_schedule_retry()

## Seconds until the next reconnection attempt; 0 while one is in progress.
func retry_seconds() -> int:
	return ceili(maxf(_retry_in,0.0)) if _peer==null else 0

func _drain() -> void:
	while _peer!=null and _peer.get_available_packet_count() > 0:
		_since_heard = 0.0
		var packet := _peer.get_packet()
		messages_in += 1
		bytes_in += packet.size()
		_receive(packet.get_string_from_utf8())

func close() -> void:
	_closed = true
	if _peer!=null:_peer.close()

func _send_hello() -> void:
	_seq += 1
	_hello_seq = _seq
	_send(Codec.encode({"type":"hello","protocol":PROTOCOL,"client_kind":OS.get_name(),"seq":_seq}))

func _receive(text: String) -> void:
	var incoming := Codec.decode(text)
	if incoming.is_empty():return
	if bool(incoming.get("reply",false)):
		var seq := int(incoming.get("seq",0))
		if seq==_ping_seq:latency_ms = Time.get_ticks_msec()-_ping_msec
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
		# Skipped encounters are ordinary outcomes the caller explains itself;
		# stale commands lost a race with another device and need no notice.
		if not bool(incoming.get("ok",false)) and not incoming.has("skipped") and not incoming.has("stale") and not str(incoming.get("reason","")).is_empty():
			message.emit({"type":"rejected","reason":incoming.reason,"seq":seq})
		return
	message.emit(incoming)

func _schedule_retry() -> void:
	if _closed:return
	_retry_in = _backoff
	_backoff = minf(_backoff*2.0,MAX_BACKOFF)

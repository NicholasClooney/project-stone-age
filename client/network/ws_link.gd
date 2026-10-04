extends RefCounted
## Delivery to a backend over WebSocket. Same surface as LocalLink, but replies
## are asynchronous: request() returns {"pending":true} and passes the real
## reply to done later. Commands are never queued while offline, so a
## purchase or battle action cannot replay after reconnecting. Call poll()
## every frame. A connection that goes silent (server killed without a close,
## Wi-Fi dropped, Mac asleep) is dropped after SILENCE_LIMIT seconds of
## missed heartbeats, so the client always learns it is offline.
##
## A server hosting several profiles (server/profile_hub.gd) answers hello
## with login_required instead of a snapshot: login_needed carries its
## profile list, and login() sends the name and PIN (or creates a character).
## The login's token is kept and sent with every later hello, so a reconnect
## logs in again by itself.
signal message(event: Dictionary)
signal connected
signal disconnected
signal login_needed(info: Dictionary)

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
var _lifecycle := 0 # Local callback ownership only; never a wire revision.
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
## Multi-profile servers: the profile this device logs into and its token
## (the game keeps them in viewer.cfg), the server's answer about the
## account ({name, admin}), and whether the server waits for a login now.
var login_name := ""
var login_token := ""
var account: Dictionary = {}
var awaiting_login := false
var _login_seq := -1
var _login_done: Callable

func _init(server_url: String) -> void:
	url = server_url

func is_local() -> bool:
	return false

## Starts (or restarts) the connection; the link stays idle until called.
func connect_now() -> void:
	var retired := _lifecycle+1
	close() # Revoke the old online capability and finish its callbacks first.
	if _lifecycle!=retired:return # A cancellation callback already changed owner.
	_closed = false
	_started = true
	_hello_seq = -1
	awaiting_login = false
	_login_seq = -1
	_last_state = -1
	_since_heard = 0.0
	_since_ping = 0.0
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = 32 << 20
	_peer.outbound_buffer_size = 1 << 20
	var error := _peer.connect_to_url(url)
	print("[link] connecting to %s: error %d" % [url,error])
	if error!=OK:
		_drop()

func request(command: Dictionary, done: Callable = Callable()) -> Dictionary:
	if not online or not _open_peer():
		if online:_drop()
		var offline := {"ok":false,"reason":"offline","type":"rejected"}
		if done.is_valid():done.call(offline)
		return offline
	_seq += 1
	var sent: Dictionary = command.duplicate(true)
	sent.seq = _seq
	if done.is_valid():_callbacks[_seq] = done
	if not _send(Codec.encode(sent)):return {"ok":false,"reason":"offline","type":"rejected"}
	return {"ok":false,"pending":true}

func _open_peer() -> bool:
	return not _closed and _peer!=null and _peer.get_ready_state()==WebSocketPeer.STATE_OPEN

func _same_owner(peer:WebSocketPeer,lifecycle:int)->bool:
	return _peer==peer and _lifecycle==lifecycle and not _closed

func _send(text: String) -> bool:
	if not _open_peer():
		_drop() # Any already registered callback receives one offline rejection.
		return false
	messages_out += 1
	bytes_out += text.to_utf8_buffer().size()
	if _peer.send_text(text)!=OK:
		_drop()
		return false
	return true

func stats() -> Dictionary:
	return {"kind":"remote","messages_in":messages_in,"messages_out":messages_out,"bytes_in":bytes_in,"bytes_out":bytes_out,"latency_ms":latency_ms}

func poll(delta: float) -> void:
	if _peer==null:
		if not _started or _closed or url.is_empty():return
		_retry_in -= delta
		if _retry_in <= 0:connect_now()
		return
	var polled_peer := _peer
	var lifecycle := _lifecycle
	_peer.poll()
	var ready_state := _peer.get_ready_state()
	if ready_state!=_last_state:
		print("[link] %s state %d" % [url,ready_state])
		_last_state = ready_state
	match ready_state:
		WebSocketPeer.STATE_OPEN:
			if _hello_seq < 0:_send_hello()
			if not _same_owner(polled_peer,lifecycle):return
			_drain()
			if _same_owner(polled_peer,lifecycle):_heartbeat(delta)
		WebSocketPeer.STATE_CONNECTING:
			_heartbeat(delta)
		WebSocketPeer.STATE_CLOSING:
			_drain()
		WebSocketPeer.STATE_CLOSED:
			_drain()
			if _same_owner(polled_peer,lifecycle):_drop()

## Counts frame time rather than wall time, so a browser tab that was hidden
## (and not polling) is not mistaken for a dead server when it comes back.
func _heartbeat(delta: float) -> void:
	if _peer==null:return
	_since_heard += delta
	if _since_heard > silence_limit:
		print("[link] %s silent for %.0f s, dropping" % [url,_since_heard])
		_drop()
		return
	_since_ping += delta
	if (online or awaiting_login) and _since_ping >= PING_INTERVAL:
		_since_ping = 0.0
		_seq += 1
		_ping_seq = _seq
		_ping_msec = Time.get_ticks_msec()
		_send(Codec.encode({"type":"ping","seq":_seq}))

func _drop() -> void:
	_lifecycle += 1
	var lifecycle := _lifecycle
	var was_online := online
	var retired_peer := _peer
	online = false
	_peer = null
	_hello_seq = -1
	awaiting_login = false
	_login_seq = -1
	_ping_seq = -1
	_ping_msec = 0
	var pending := _callbacks
	_callbacks = {}
	# Release only the captured old transport, before user callbacks may replace it.
	if retired_peer!=null:retired_peer.close()
	for seq in pending:pending[seq].call({"ok":false,"reason":"offline","type":"rejected"})
	if lifecycle!=_lifecycle:return
	if was_online:disconnected.emit()
	if lifecycle==_lifecycle:_schedule_retry()

## Seconds until the next reconnection attempt; 0 while one is in progress.
func retry_seconds() -> int:
	return ceili(maxf(_retry_in,0.0)) if _peer==null else 0

func _drain() -> void:
	var peer := _peer
	var lifecycle := _lifecycle
	while peer!=null and _same_owner(peer,lifecycle) and peer.get_available_packet_count() > 0:
		_since_heard = 0.0
		var packet := _peer.get_packet()
		messages_in += 1
		bytes_in += packet.size()
		_receive(packet.get_string_from_utf8())

func close() -> void:
	_closed = true
	_drop() # Synchronous capability revocation, not a later poll side effect.

func _send_hello() -> void:
	_seq += 1
	_hello_seq = _seq
	var hello := {"type":"hello","protocol":PROTOCOL,"client_kind":OS.get_name(),"seq":_seq}
	if not login_token.is_empty():hello.login = {"name":login_name,"token":login_token}
	_send(Codec.encode(hello))

## Logs into a multi-profile server while it waits for a login:
## {"type":"login", name, pin} or {"type":"create_profile", name, pin}. On
## success the link goes online as after a hello, and keeps the token for
## reconnects. `done` gets the reply either way.
func login(command: Dictionary, done: Callable = Callable()) -> void:
	if not _open_peer() or not awaiting_login:
		if done.is_valid():done.call({"ok":false,"reason":"offline","type":"rejected"})
		return
	_lifecycle += 1 # A new accepted login supersedes an older auth callback.
	_seq += 1
	_login_seq = _seq
	var sent := command.duplicate(true)
	sent.seq = _seq
	if done.is_valid():_callbacks[_seq] = done
	_send(Codec.encode(sent))

## Forgets this device's login on the server and here (切换角色).
func logout(done: Callable = Callable()) -> void:
	login_token = ""
	request({"type":"logout"},done)

func _logged_in(incoming: Dictionary) -> void:
	var peer := _peer
	var lifecycle := _lifecycle
	if not _open_peer():return
	account = incoming.get("account",{})
	if account.has("name"):login_name = str(account.name)
	if incoming.has("token"):login_token = str(incoming.token)
	awaiting_login = false
	online = true
	_backoff = 1.0
	message.emit(incoming.snapshot)
	if _same_owner(peer,lifecycle) and online and _open_peer():connected.emit()

func _receive(text: String) -> void:
	var peer := _peer
	var lifecycle := _lifecycle
	var incoming := Codec.decode(text)
	if incoming.is_empty():return
	if bool(incoming.get("reply",false)):
		var seq := int(incoming.get("seq",0))
		if seq==_ping_seq:latency_ms = Time.get_ticks_msec()-_ping_msec
		if seq==_hello_seq and incoming.has("snapshot"):
			_logged_in(incoming)
			return
		if seq==_hello_seq and bool(incoming.get("login_required",false)):
			# A remembered token that no longer works is dropped.
			if incoming.has("reason"):login_token = ""
			awaiting_login = true
			_backoff = 1.0
			login_needed.emit(incoming)
			return
		if seq==_login_seq:
			_login_seq = -1
			# The caller hears first, then the game sees the snapshot.
			if _callbacks.has(seq):
				var answer: Callable = _callbacks[seq]
				_callbacks.erase(seq)
				answer.call(incoming)
			if not _same_owner(peer,lifecycle):return
			if bool(incoming.get("ok",false)) and incoming.has("snapshot"):_logged_in(incoming)
			return
		if _callbacks.has(seq):
			var done: Callable = _callbacks[seq]
			_callbacks.erase(seq)
			done.call(incoming)
		if not _same_owner(peer,lifecycle):return
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

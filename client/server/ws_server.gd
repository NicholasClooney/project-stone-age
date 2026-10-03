extends Node
## WebSocket front for one Backend, or for a ProfileHub (one server, many
## profiles: server/profile_hub.gd). Each text frame is one JSON command; the
## reply goes back to the sender and backend events to every connection (with
## a hub: to every connection logged into that event's profile). Any number
## of devices watch and drive one session; commands are handled one at a
## time, so the first of two conflicting commands wins and the other is
## rejected by the rules (or as stale). Automation keeps running with no
## connection.
const Codec = preload("res://network/codec.gd")
const MAX_MESSAGE_BYTES := 1 << 20

var backend
var hub
var port := 8781
var bind_address := "*"
## Set for wss://: TLS is negotiated on each connection before the WebSocket.
var tls_options: TLSOptions
var _server := TCPServer.new()
var _handshakes: Array[StreamPeerTLS] = []
var _pending: Array[WebSocketPeer] = []
var _clients: Array[WebSocketPeer] = []

## `target` is a Backend, or a ProfileHub (it has the `outgoing` signal).
func _init(target, listen_port: int = 8781, address: String = "*") -> void:
	if target.has_signal("outgoing"):hub = target
	else:backend = target
	port = listen_port
	bind_address = address

func _ready() -> void:
	if hub!=null:
		hub.outgoing.connect(_on_outgoing)
		return
	backend.event.connect(_on_event)
	backend.automation.client_attached = false

## Port 0 picks any free port (tests); `port` then holds the one chosen.
func start() -> Error:
	var error := _server.listen(port,bind_address)
	if error==OK:port = _server.get_local_port()
	return error

func stop() -> void:
	if backend!=null:backend.quest_auto.suspend(backend)
	if hub!=null:
		for profile_backend in hub.backends.values():profile_backend.quest_auto.suspend(profile_backend)
	for peer in _pending:peer.close()
	for peer in _clients:peer.close()
	_server.stop()

func is_listening() -> bool:
	return _server.is_listening()

func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var connection := _server.take_connection()
		if tls_options==null:
			_accept(connection)
		else:
			var tls := StreamPeerTLS.new()
			if tls.accept_stream(connection,tls_options)==OK:_handshakes.append(tls)
	for tls in _handshakes.duplicate():
		tls.poll()
		match tls.get_status():
			StreamPeerTLS.STATUS_CONNECTED:
				_handshakes.erase(tls)
				_accept(tls)
			StreamPeerTLS.STATUS_HANDSHAKING:
				pass
			_:
				_handshakes.erase(tls)
	for peer in _pending.duplicate():
		peer.poll()
		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_pending.erase(peer)
				_promote(peer)
			WebSocketPeer.STATE_CLOSED:
				_pending.erase(peer)
	for peer in _clients.duplicate():
		peer.poll()
		var state: int = peer.get_ready_state()
		if state==WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count() > 0 and peer in _clients:
				_receive(peer,peer.get_packet().get_string_from_utf8())
		elif state==WebSocketPeer.STATE_CLOSED:
			_clients.erase(peer)
			if hub!=null:hub.disconnect_connection(peer.get_instance_id())
			else:
				backend.quest_auto.detach(backend,peer.get_instance_id())
				backend.automation.client_attached = not _clients.is_empty()

## Connected clients, for tests and diagnostics.
func clients() -> Array[WebSocketPeer]:
	return _clients

func _accept(stream: StreamPeer) -> void:
	var peer := WebSocketPeer.new()
	peer.inbound_buffer_size = MAX_MESSAGE_BYTES
	peer.outbound_buffer_size = 32 << 20
	if peer.accept_stream(stream)==OK:_pending.append(peer)

func _promote(peer: WebSocketPeer) -> void:
	_clients.append(peer)
	if hub==null:backend.automation.client_attached = true

func _receive(peer: WebSocketPeer, text: String) -> void:
	var command := Codec.decode(text)
	if command.is_empty():
		_send(peer,{"type":"rejected","seq":0,"ok":false,"reason":"malformed command","v":1})
		return
	# Connection ownership is transport identity, never a client-provided tag.
	command["_quest_connection"]=peer.get_instance_id()
	# Events raised by the command reach every client before this reply.
	var reply: Dictionary = hub.handle(peer.get_instance_id(),command) if hub!=null else backend.handle(command)
	reply.reply = true
	if peer.get_ready_state()==WebSocketPeer.STATE_OPEN:_send(peer,reply)

func _on_event(message: Dictionary) -> void:
	for peer in _clients:
		if peer.get_ready_state()==WebSocketPeer.STATE_OPEN:_send(peer,message)

## A hub's event for one connection (a device logged into that profile).
func _on_outgoing(connection: int, message: Dictionary) -> void:
	for peer in _clients:
		if peer.get_instance_id()==connection and peer.get_ready_state()==WebSocketPeer.STATE_OPEN:_send(peer,message)

## A client that stopped reading (a suspended page) fills its 32 MB outbound
## queue; later messages would be dropped and its view would silently fall
## behind. Close it instead: the client reconnects and resyncs from a snapshot.
func _send(peer: WebSocketPeer, message: Dictionary) -> void:
	if peer.send_text(Codec.encode(message))!=OK and peer.get_ready_state()==WebSocketPeer.STATE_OPEN:
		push_warning("closing a client whose outbound queue is full")
		peer.close(1013,"backlog")

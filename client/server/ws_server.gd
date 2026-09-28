extends Node
## WebSocket front for one Backend. Each text frame is one JSON command; the
## reply goes back to the sender and backend events to every connection. Any
## number of devices watch and drive the one session; commands are handled
## one at a time, so the first of two conflicting commands wins and the
## other is rejected by the rules (or as stale). Automation keeps running
## with no connection.
const Codec = preload("res://network/codec.gd")
const MAX_MESSAGE_BYTES := 1 << 20

var backend
var port := 8781
var bind_address := "*"
## Set for wss://: TLS is negotiated on each connection before the WebSocket.
var tls_options: TLSOptions
var _server := TCPServer.new()
var _handshakes: Array[StreamPeerTLS] = []
var _pending: Array[WebSocketPeer] = []
var _clients: Array[WebSocketPeer] = []

func _init(target, listen_port: int = 8781, address: String = "*") -> void:
	backend = target
	port = listen_port
	bind_address = address

func _ready() -> void:
	backend.event.connect(_on_event)
	backend.automation.client_attached = false

func start() -> Error:
	return _server.listen(port,bind_address)

func stop() -> void:
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
			backend.automation.client_attached = not _clients.is_empty()

## Connected clients, for tests and diagnostics.
func clients() -> Array[WebSocketPeer]:
	return _clients

func _accept(stream: StreamPeer) -> void:
	var peer := WebSocketPeer.new()
	peer.inbound_buffer_size = MAX_MESSAGE_BYTES
	peer.outbound_buffer_size = 8 << 20
	if peer.accept_stream(stream)==OK:_pending.append(peer)

func _promote(peer: WebSocketPeer) -> void:
	_clients.append(peer)
	backend.automation.client_attached = true

func _receive(peer: WebSocketPeer, text: String) -> void:
	var command := Codec.decode(text)
	if command.is_empty():
		_send(peer,{"type":"rejected","seq":0,"ok":false,"reason":"malformed command","v":backend.PROTOCOL})
		return
	# Events raised by the command reach every client before this reply.
	var reply: Dictionary = backend.handle(command)
	reply.reply = true
	if peer.get_ready_state()==WebSocketPeer.STATE_OPEN:_send(peer,reply)

func _on_event(message: Dictionary) -> void:
	for peer in _clients:
		if peer.get_ready_state()==WebSocketPeer.STATE_OPEN:_send(peer,message)

func _send(peer: WebSocketPeer, message: Dictionary) -> void:
	peer.send_text(Codec.encode(message))

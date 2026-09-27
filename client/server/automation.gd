extends RefCounted
## Backend automation runners. Replaced by the full runner once the client
## loops move behind the backend.
var backend

func _init(owner) -> void:
	backend = owner

func tick(_delta: float) -> void:
	pass

func step() -> void:
	pass

func status() -> Dictionary:
	return {"running":false}

func start(_command: Dictionary) -> Dictionary:
	return {"ok":false,"reason":"automation unavailable"}

func update(_command: Dictionary) -> Dictionary:
	return {"ok":false,"reason":"automation unavailable"}

func stop_request(_reason: String) -> Dictionary:
	return {"ok":true}

func presented(_battle_id: String, _turn: int) -> void:
	pass

func position_changed(_map_id: int, _cell: Vector2i) -> void:
	pass

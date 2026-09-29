extends Control
## A looping battle-manifest animation anchored like the original MakeAnimDisp
## (menu.cpp:1865): the node sits at the sprite anchor and each frame is drawn
## at its bitmap and frame offsets. Frames follow a global clock, so a rebuilt
## window keeps the loop where it was instead of restarting at frame 0.
## Clicking turns the sprite one facing, like AnimDisp ANIM_DISP_PET (menu.cpp:1177).
const BattleArt = preload("res://scripts/battle_art.gd")
const STAND := 3
static var _textures: Dictionary = {}

var sprite := ""
var facing := 1
var action := STAND
var current_image := -1
var turned: Callable
var _offset := Vector2.ZERO
var _texture: Texture2D

static func manifest() -> Dictionary:
	return BattleArt.data()

static func animation_for(ident: String, action_id: int, direction: int) -> Dictionary:
	BattleArt.ensure(ident)
	var animations: Dictionary = manifest().get("characters",{}).get(ident,{})
	return animations.get("%d_%d" % [action_id,direction],animations.get("%d_0" % action_id,{}))

## The frame shown at `msec` on the shared clock (battle_view.gd / pet_follower.gd
## spread duration_ms evenly over the frames and loop).
static func frame_at(animation: Dictionary, msec: int) -> Dictionary:
	var frames: Array = animation.get("frames",[])
	if frames.is_empty():return {}
	var duration := maxf(0.1,float(animation.get("duration_ms",1000))/1000.0)
	var seconds := float(msec)/1000.0
	return frames[int(fmod(seconds,duration)/duration*frames.size())%frames.size()]

func setup(ident: String, direction: int, on_turn: Callable = Callable()) -> void:
	sprite = ident
	facing = direction
	turned = on_turn
	mouse_filter = Control.MOUSE_FILTER_STOP if on_turn.is_valid() else Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_update(Time.get_ticks_msec())

func _process(_delta: float) -> void:
	_update(Time.get_ticks_msec())

func _update(msec: int) -> void:
	var frame := frame_at(animation_for(sprite,action,facing),msec)
	if frame.is_empty():return
	var image := int(frame.image)
	if image == current_image:return
	var metadata: Dictionary = manifest().images.get(str(image),{})
	if not _textures.has(image):
		# A web client may not hold this sprite's pack yet; keep the last frame.
		var texture: Texture2D = preload("res://scripts/sheet_frames.gd").texture("res://assets/legacy/battle/",manifest().get("sheets",{}),str(sprite),image)
		if texture==null:return
		if _textures.size() >= 512:_textures.clear()
		_textures[image] = texture
	current_image = image
	_texture = _textures[image]
	_offset = Vector2(float(metadata.get("x",0))+float(frame.get("x",0)),float(metadata.get("y",0))+float(frame.get("y",0)))
	queue_redraw()

func _draw() -> void:
	if _texture != null:draw_texture(_texture,_offset)

func _has_point(point: Vector2) -> bool:
	return _texture != null and Rect2(_offset,_texture.get_size()).has_point(point)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and turned.is_valid():
		facing = (facing+1)%8
		current_image = -1
		_update(Time.get_ticks_msec())
		turned.call(facing)
		accept_event()

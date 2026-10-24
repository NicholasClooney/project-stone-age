extends Control
const Clock=preload("res://scripts/clock.gd")
## A looping battle-manifest animation anchored like the original MakeAnimDisp
## (menu.cpp:1865): the node sits at the sprite anchor and each frame is drawn
## at its bitmap and frame offsets. Frames follow a global clock, so a rebuilt
## window keeps the loop where it was instead of restarting at frame 0.
## Clicking turns the sprite one facing, like AnimDisp ANIM_DISP_PET (menu.cpp:1177).
const BattleArt = preload("res://scripts/battle_art.gd")
const SpriteArt = preload("res://scripts/sprite_art.gd")
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
const STAND := 3

var sprite := ""
var facing := 1
var action := STAND
var current_image := -1
var turned: Callable
var _offset := Vector2.ZERO
var _texture: Texture2D
## The sprite's entry (scripts/sprite_art.gd), held while the portrait shows it.
var _art: Dictionary = {}

static func animation_for(ident: String, action_id: int, direction: int) -> Dictionary:
	var animations: Dictionary = BattleArt.animations(ident)
	return animations.get("%d_%d" % [action_id,direction],animations.get("%d_0" % action_id,{}))

## The frame index shown at `msec` on the shared clock (battle_view.gd /
## pet_follower.gd spread duration_ms evenly over the frames and loop), or -1.
static func frame_index(animation: Dictionary, msec: int) -> int:
	var count := SpriteArt.frame_count(animation)
	if count == 0:return -1
	var duration := maxf(0.1,float(animation.get("duration_ms",1000))/1000.0)
	var seconds := float(msec)/1000.0
	return int(fmod(seconds,duration)/duration*count)%count

## The frame shown at `msec` as {image, x, y, sound}, or {}.
static func frame_at(animation: Dictionary, msec: int) -> Dictionary:
	var index := frame_index(animation,msec)
	return SpriteArt.frame(animation,index) if index >= 0 else {}

func setup(ident: String, direction: int, on_turn: Callable = Callable()) -> void:
	sprite = ident
	facing = direction
	turned = on_turn
	mouse_filter = Control.MOUSE_FILTER_STOP if on_turn.is_valid() else Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_update(Clock.ticks_msec())

func _process(_delta: float) -> void:
	_update(Clock.ticks_msec())

func _update(msec: int) -> void:
	if _art.is_empty() or str(_art.key) != sprite:_art = BattleArt.art(sprite)
	if _art.is_empty():return
	var animations: Dictionary = _art.animations
	var animation: Dictionary = animations.get("%d_%d" % [action,facing],animations.get("%d_0" % action,{}))
	var index := frame_index(animation,msec)
	if index < 0:return
	var image := SpriteArt.image(animation,index)
	if image == current_image:return
	# A web client may not hold this sprite's pack yet; keep the last frame.
	var texture := SpriteArt.texture(_art,image)
	if texture==null:return
	current_image = image
	_texture = texture
	PaletteSheet.apply(self,texture)
	_offset = SpriteArt.offset(_art,animation,index)
	queue_redraw()

func _draw() -> void:
	if _texture != null:draw_texture(_texture,_offset)

func _has_point(point: Vector2) -> bool:
	return _texture != null and Rect2(_offset,_texture.get_size()).has_point(point)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and turned.is_valid():
		facing = (facing+1)%8
		current_image = -1
		_update(Clock.ticks_msec())
		turned.call(facing)
		accept_event()

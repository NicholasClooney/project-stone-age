extends CanvasLayer
## Historical map change: compress vertically to the center, then expand.
## process.cpp cases201/204 -> PRODUCE_CENTER_PRESSIN/OUT;
## produce.cpp1003 ProduceCenterPress: 240 scanlines, 8 per update.
## This reference fork disables DrawProduce via `no = -1`; we deliberately
## restore its documented effect. Timing is configurable, not a frame-rate claim.
## Screen sampling avoids a flash when capturing the new map under an overlay.
var busy := false
var enabled := true
var half_duration := 0.30
var surface: ColorRect
var effect: ShaderMaterial

func _ready() -> void:
	layer = 100
	surface = ColorRect.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float opening = 1.0;
void fragment() {
    float rows = floor(clamp(opening, 0.0, 1.0) * 30.0 + 0.5) / 30.0;
    vec2 source = SCREEN_UV;
    source.y = (source.y - 0.5) / max(rows, 0.0001) + 0.5;
    if (rows <= 0.0 || source.y < 0.0 || source.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        COLOR = texture(screen_texture, source);
    }
}
"""
	effect = ShaderMaterial.new()
	effect.shader = shader
	surface.material = effect
	add_child(surface)
	surface.hide()

func transition(change_map: Callable) -> bool:
	if busy or not change_map.is_valid():return false
	if not enabled:return bool(change_map.call())
	busy = true
	effect.set_shader_parameter("opening",1.0)
	surface.show()
	var closing := create_tween()
	closing.tween_method(_set_opening,1.0,0.0,maxf(0.01,half_duration))
	await closing.finished
	var changed := bool(change_map.call())
	# A failed map load expands the unchanged map and always releases input.
	await get_tree().process_frame
	var opening := create_tween()
	opening.tween_method(_set_opening,0.0,1.0,maxf(0.01,half_duration))
	await opening.finished
	surface.hide()
	busy = false
	return changed

func _set_opening(value: float) -> void:
	effect.set_shader_parameter("opening",value)

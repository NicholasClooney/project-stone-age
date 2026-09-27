extends RefCounted
## SA_MOUSE1 is shared by the original game and talk windows. Native OS cursor
## rendering keeps its 32px bitmap and (0,0) hotspot independent of world/UI zoom.
const MANIFEST := "res://assets/legacy/cursor/manifest.json"
static var installed := false
static var bitmap: Image
static var hotspot := Vector2.ZERO

static func install() -> bool:
	if installed:
		return true
	if not FileAccess.file_exists(MANIFEST):
		return false
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary or not manifest.has("path") or not manifest.has("hotspot"):
		return false
	var image := Image.load_from_file(MANIFEST.get_base_dir().path_join(str(manifest.path)))
	if image == null or image.is_empty():
		return false
	hotspot = Vector2(manifest.hotspot[0],manifest.hotspot[1])
	bitmap = image
	var texture := ImageTexture.create_from_image(image)
	# Controls may request pointing hands, I-beams, resize arrows, etc. The legacy
	# client always used SA_MOUSE1; assigning every shape preserves that behavior.
	if DisplayServer.get_name() != "headless":
		for shape in range(Input.CURSOR_HELP + 1):
			Input.set_custom_mouse_cursor(texture,shape,hotspot)
	installed = true
	return true

static func uninstall() -> void:
	if DisplayServer.get_name() != "headless":
		for shape in range(Input.CURSOR_HELP + 1):
			Input.set_custom_mouse_cursor(null,shape)
	bitmap = null
	installed = false

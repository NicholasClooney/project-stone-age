extends Control
## Original MAGIC_EFFECT_USER100600 and SPR_difence100610 sprite sequences.
var sequence: Dictionary = {}
var metadata: Dictionary = {}
var root_path := ""
var age := 0.0
var sprite := TextureRect.new()
var frame_index := -1
func setup(ident: int, point: Vector2) -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	z_index=20
	position=point
	sprite.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(sprite)
	var path := "res://assets/legacy/mvp/mirror-effects.json"
	if not FileAccess.file_exists(path): queue_free(); return
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	sequence=data.characters.get(str(ident),{}).get("0_0",{})
	metadata=data.images
	root_path=data.image_root
	advance(0)
func advance(delta: float) -> void:
	age+=delta
	var frames: Array=sequence.get("frames",[])
	var duration:=float(sequence.get("duration_ms",1))/1000.0
	if frames.is_empty() or age>=duration: queue_free(); return
	var index:=mini(frames.size()-1,int(age/duration*frames.size()))
	if index==frame_index:return
	frame_index=index
	var frame:Dictionary=frames[index]
	var info:Dictionary=metadata.get(str(int(frame.image)),{})
	sprite.texture=load(root_path+str(int(frame.image))+".png")
	sprite.position=Vector2(float(info.get("x",0))+float(frame.x),float(info.get("y",0))+float(frame.y))

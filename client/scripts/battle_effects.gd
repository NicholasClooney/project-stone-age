extends Control
## oft.cpp set_hit_mark (1245+) and damage_num (348+)/set_damage_num (968+).
## Legacy tick motion is expressed at 60Hz here; source logic is not FPS-independent.
const TICK_RATE := 60.0
var clock := 0.0
var active: Array[Dictionary] = []
var frames: Dictionary = {}
var metadata: Dictionary = {}
func setup(manifest: Dictionary) -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 z_index = 10
 metadata = manifest.ui
 for id in range(25500,25508):frames[id] = load("res://assets/legacy/battle/ui/%d.png" % id)
func reset() -> void:
 for entry in active:entry.node.queue_free()
 active.clear()
func impact(point: Vector2, amount: int, guarded: bool = false, critical: bool = false, knockout: bool = false) -> void:
 if amount<=0:return
 if critical:
  for i in range(5):
   var star := TextureRect.new()
   star.mouse_filter = Control.MOUSE_FILTER_IGNORE
   add_child(star)
   var angle := float((5-i)*6)/32.0*TAU
   active.append({"node":star,"born":clock,"origin":point+Vector2(0,-32),"kind":"critical","velocity":Vector2(sin(angle),-cos(angle))*(4+i%4),"duration":32 if knockout else 8})
  number(point,amount,false)
  _update_effects()
  return
 var flash := TextureRect.new()
 flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(flash)
 active.append({"node":flash,"born":clock,"origin":point+Vector2(0,-32),"kind":"flash","ids":[25504,25503,25502] if guarded else [25507,25506,25505]})
 number(point,amount,false)
 _update_effects()
func heal(point: Vector2, amount: int) -> void:
 if amount>0:number(point,amount,true)
func word(point: Vector2, ident: int, seconds: float = 1.0) -> void:
 if not metadata.has(str(ident)):return
 var image := TextureRect.new()
 image.texture = load("res://assets/legacy/battle/ui/%d.png" % ident)
 var info: Dictionary = metadata[str(ident)]
 image.position = point+Vector2(0,-80)+Vector2(info.x,info.y)
 image.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(image)
 active.append({"node":image,"born":clock,"origin":image.position,"kind":"word","duration":int(seconds*TICK_RATE)})
func number(point: Vector2, amount: int, recovery: bool) -> void:
 var label := Label.new()
 label.text = str(amount)
 label.position = point+Vector2(-40,-64)
 label.size = Vector2(80,20)
 label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
 label.add_theme_font_size_override("font_size",14)
 label.add_theme_color_override("font_color",Color("a0f43a" if recovery else "b53817"))
 label.add_theme_color_override("font_shadow_color",Color.BLACK)
 label.add_theme_constant_override("shadow_offset_x",1)
 label.add_theme_constant_override("shadow_offset_y",1)
 add_child(label)
 active.append({"node":label,"born":clock,"origin":label.position,"kind":"number"})
func number_offset(ticks: int) -> float:
 var speed := 24
 var phase := 0
 var offset := 0.0
 for i in range(mini(ticks,25)):
  offset += float(speed)/4.0*(-1.0 if phase==0 else 1.0)
  if phase==0:
   speed-=2
   if speed==0:phase=1
  elif phase==1:
   speed+=2
   if speed>=24:phase=2
  else:speed=0
 return offset
func _process(delta: float) -> void:
 clock+=delta
 _update_effects()
func _update_effects() -> void:
 for i in range(active.size()-1,-1,-1):
  var entry := active[i]
  var ticks := int((clock-float(entry.born))*TICK_RATE)
  if ticks>=int(entry.get("duration",8 if entry.kind=="flash" else 85)):
   entry.node.queue_free()
   active.remove_at(i)
  elif entry.kind=="flash":
   var id: int = entry.ids[mini(2,int(ticks*3/8))]
   entry.node.texture = frames[id]
   var info: Dictionary = metadata[str(id)]
   entry.node.position = entry.origin+Vector2(info.x,info.y)
  elif entry.kind=="critical":
   var id := 25501 if ticks<int(entry.duration)/2 else 25500
   entry.node.texture = frames[id]
   var info: Dictionary = metadata[str(id)]
   entry.node.position = entry.origin+entry.velocity*ticks+Vector2(info.x,info.y)
  elif entry.kind=="number":entry.node.position = entry.origin+Vector2(0,number_offset(ticks))

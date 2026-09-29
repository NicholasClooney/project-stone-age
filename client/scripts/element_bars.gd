extends RefCounted
## The status and pet windows' 属性 bars (menu.cpp:11877-11906, 15215): one
## bar per element, value × 0.8 px wide and 8 px tall, in the system palette's
## bright colour over two 1 px shadows in its dark twin.
const COLORS := [Color8(0,255,0),Color8(0,255,255),Color8(255,0,0),Color8(255,255,0)]
const SHADOWS := [Color8(0,128,0),Color8(0,128,128),Color8(128,0,0),Color8(128,128,0)]

static func add(parent: Control, elements: Array, origin: Vector2, spacing: float) -> void:
	for i in range(4):
		var width := int(int(elements[i])*0.8)
		if width<=0:continue
		var top := origin+Vector2(0,spacing*i)
		for offset in [2,1]:
			var shadow := ColorRect.new()
			shadow.color = SHADOWS[i]
			shadow.position = top+Vector2(offset,offset)
			shadow.size = Vector2(width+1,9)
			shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(shadow)
		var bar := ColorRect.new()
		bar.name = "ElementBar%d" % i
		bar.color = COLORS[i]
		bar.position = top
		bar.size = Vector2(width+1,9)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(bar)

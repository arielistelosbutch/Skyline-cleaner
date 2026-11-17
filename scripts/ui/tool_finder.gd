class_name ToolFinder
extends Node3D
## [R] Najít nářadí: na pár vteřin ukáže modré šipky nad žebříky, židlí a kbelíkem
## (vidět i přes zdi, se vzdáleností) a modré značky na kompasu nahoře.

const SHOW_TIME := 8.0

var player: Player
var nav: NavArrow
var _labels: Array[Label3D] = []
var _targets: Array[Node3D] = []
var _t := 0.0


## Nářadí, které hráč vlastní a které právě nenese.
func find_tools() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for l in get_tree().get_nodes_in_group("ladders"):
		var lad := l as Ladder
		if lad and lad.is_owned() and not lad.is_carried() and lad.visible:
			out.append(lad)
	for b in get_tree().get_nodes_in_group("buckets"):
		var bk := b as Bucket
		if bk and bk.is_owned() and not bk.is_carried() and bk.visible:
			out.append(bk)
	for c in get_tree().get_nodes_in_group("chairs"):
		var ch := c as Node3D
		if ch and ch.visible and player and player.carried != ch:
			out.append(ch)
	return out


func show_tools() -> void:
	_clear()
	_targets = find_tools()
	if _targets.is_empty():
		Events.toast("Žádné položené nářadí nemáš – židli nebo žebřík neseš u sebe.", "info")
		return
	for n in _targets:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font_size = 30
		l.outline_size = 10
		l.render_priority = 11
		l.modulate = Color(0.4, 0.7, 1.0)
		l.outline_modulate = Color(0.05, 0.1, 0.2, 0.85)
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		add_child(l)
		_labels.append(l)
	_t = SHOW_TIME
	Audio.play("click", -6.0, 1.4)
	_update()


func _clear() -> void:
	for l in _labels:
		l.queue_free()
	_labels.clear()
	_targets.clear()
	if nav:
		nav.tool_marks = []


func _process(delta: float) -> void:
	if _t <= 0.0:
		return
	_t -= delta
	if _t <= 0.0:
		_clear()
		return
	_update()


func _update() -> void:
	var marks: Array = []
	for i in _targets.size():
		var n := _targets[i]
		var l := _labels[i]
		if not is_instance_valid(n) or not n.visible:
			l.visible = false
			continue
		var top := n.global_position + Vector3(0, 1.4, 0)
		var name := "KBELÍK" if n is Bucket else "ŽIDLE"
		if n is Bucket:
			top = n.global_position + Vector3(0, 0.8, 0)
		if n is Ladder:
			var lad := n as Ladder
			top = n.global_position + Vector3(0, 0.6 if lad.lying else lad.top_height() + 0.4, 0)
			name = "DLOUHÝ ŽEBŘÍK" if lad.length > 5.0 else "ŽEBŘÍK"
		l.global_position = top
		var d := player.global_position.distance_to(n.global_position) if player else 0.0
		l.text = "%s · %d m\n▼" % [name, int(d)]
		l.modulate.a = clampf(_t / 1.0, 0.0, 1.0)
		l.visible = true
		marks.append(n.global_position)
	if nav:
		nav.tool_marks = marks

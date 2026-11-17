class_name WindowMarkers
extends Node3D
## Značky nad okny aktivní zakázky, která ještě nejsou hotová. Jsou vidět i přes zdi,
## ať hráč najde i okno vzadu nebo v patře. Okno, na které hráč se svým vybavením
## zatím nedosáhne, má oranžovou značku s tím, co je potřeba (žebřík, lano…).

## Šipky nad okny se rozsvítí, až hráč k budově dojde (navádí ho kompas).
const SHOW_DIST := 30.0

var player: Player
var _marks := {}     # window_id -> Label3D
var _dirty := true
var _t := 0.0


func _ready() -> void:
	Events.contract_changed.connect(func() -> void: _dirty = true)
	Events.window_completed.connect(func(_id: String) -> void: _dirty = true)
	Events.inventory_changed.connect(func() -> void: _dirty = true)


func remaining() -> Array[String]:
	var out: Array[String] = []
	var c := ContractManager.active()
	if c == null:
		return out
	for wid in c.window_ids:
		var w := WindowRegistry.find_window(wid)
		if w and not w.completed and not out.has(wid):
			out.append(wid)
	return out


func _rebuild() -> void:
	_dirty = false
	for k in _marks:
		_marks[k].queue_free()
	_marks.clear()
	for wid in remaining():
		var w := WindowRegistry.find_window(wid)
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font_size = 30
		l.outline_size = 10
		l.render_priority = 10
		var ok := WindowAccess.can_reach(w)
		var need := WindowAccess.need_short(w)
		l.text = "▼" if ok or need == "" else "▼\n" + need
		l.modulate = Color(1.0, 0.9, 0.35) if ok else Color(1.0, 0.55, 0.25)
		l.outline_modulate = Color(0.1, 0.1, 0.1, 0.8)
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		add_child(l)
		l.global_position = w.plane_to_world(Vector2(w.glass_size.x * 0.5, w.glass_size.y), 0.25) + Vector3(0, 0.35, 0)
		_marks[wid] = l


func _process(delta: float) -> void:
	if _dirty:
		_rebuild()
	_t += delta
	if _t < 0.2 or player == null:
		return
	_t = 0.0
	var cleaning := player.mode == Player.Mode.CLEANING
	for wid in _marks:
		var l: Label3D = _marks[wid]
		l.visible = not cleaning and l.global_position.distance_to(player.global_position) < SHOW_DIST

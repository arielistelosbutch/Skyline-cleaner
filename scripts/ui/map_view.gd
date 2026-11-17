class_name MapView
extends Control
## (Nepoužívá se – mapu nahradil kompas NavArrow. Ponecháno pro případ návratu.)
## Vykreslení mapy z dat WorldMap: silnice, budovy, pole, značky a hráč.

var player: Node3D


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


var _b := Rect2()


func _to_map(p: Vector2, scale_f: float, offset: Vector2) -> Vector2:
	return (p - _b.position) * scale_f + offset


func _draw() -> void:
	var area := WorldMap.DEFAULT_AREA
	if player:
		area = WorldMap.area_at(Vector2(player.global_position.x, player.global_position.z))
	_b = WorldMap.area_bounds(area)
	var b := _b
	var view := b.grow(30.0)
	var scale_f := minf(size.x / b.size.x, size.y / b.size.y)
	var offset := (size - b.size * scale_f) * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.62, 0.78, 0.55))
	draw_rect(Rect2(offset, b.size * scale_f), Color(0.66, 0.82, 0.58))
	var font := get_theme_default_font()
	var placed: Array[Rect2] = []  # už nakreslené popisky – další se jim vyhnou
	for s in WorldMap.shapes:
		var r: Rect2 = s["rect"]
		if not view.intersects(r):
			continue
		var mr := Rect2(_to_map(r.position, scale_f, offset), r.size * scale_f)
		draw_rect(mr, s["color"])
	for s in WorldMap.shapes:
		if s["label"] != "" and b.intersects(s["rect"]):
			var r: Rect2 = s["rect"]
			var p := _to_map(r.get_center(), scale_f, offset)
			var lp := p + Vector2(-100, -r.size.y * scale_f * 0.5 - 6)
			draw_string(font, lp, s["label"], HORIZONTAL_ALIGNMENT_CENTER, 200, 12, Color(0.15, 0.18, 0.2))
			var lw := font.get_string_size(s["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			placed.append(Rect2(lp + Vector2(100 - lw * 0.5, -12), Vector2(lw, 15)))
	var markers := WorldMap.markers.duplicate()
	var c := ContractManager.active()
	for id in ContractManager.order:
		var con := ContractManager.get_contract(id)
		var st: String = ContractManager.state.get(id, "")
		var col := Color(0.95, 0.75, 0.3)
		var label := "Nabídka: " + con.title
		if c and c.id == id:
			col = Color(0.95, 0.5, 0.15)
			label = "Zakázka: " + con.title
		elif ContractManager.is_locked(id):
			col = Color(0.6, 0.62, 0.64)
			label = "%s (od úrovně %d)" % [con.title, con.required_level]
		elif ContractManager.is_offer(id) and st == "available":
			col = Color(0.55, 0.75, 0.95)
			label = "Poptávka: " + con.title
		elif st == "completed":
			col = Color(0.35, 0.7, 0.45)
			label = "Pravidelný úklid: " + con.title
		elif st == "paused":
			label = "Rozpracováno: " + con.title
		markers.append({"pos": con.map_position, "label": label, "color": col})
	var t := Time.get_ticks_msec() / 1000.0
	var pins := []
	for m in markers:
		if not view.has_point(m["pos"]):
			continue
		var p := _to_map(m["pos"], scale_f, offset)
		draw_circle(p, 9.0 + sin(t * 3.0) * 1.0, Color(1, 1, 1, 0.9))
		draw_circle(p, 7.0, m["color"])
		pins.append([p, m])
	# popisky až po všech značkách; když se překrývají, posuneme je pod sebe
	for pm in pins:
		var p: Vector2 = pm[0]
		var m: Dictionary = pm[1]
		var sz := font.get_string_size(m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var lx := 12.0 if p.x + 16.0 + sz.x < size.x else -16.0 - sz.x  # u pravého okraje popisek vlevo
		var lp := p + Vector2(lx, 5)
		var steps := [0.0, 17.0, -17.0, 34.0, -34.0, 51.0, -51.0, 68.0, -68.0, 85.0, -85.0]
		for dy: float in steps:
			var r := Rect2(p + Vector2(lx - 1, 5 + dy - 14), Vector2(sz.x + 4, 17))
			var hit := false
			for q in placed:
				if q.intersects(r):
					hit = true
					break
			if not hit:
				lp = p + Vector2(lx, 5 + dy)
				break
		var lr := Rect2(lp + Vector2(-1, -14), Vector2(sz.x + 4, 17))
		placed.append(lr)
		if absf(lp.y - (p.y + 5)) > 1.0:
			draw_line(p, lp + Vector2(-2 if lx > 0 else sz.x + 2, -5), Color(0.1, 0.12, 0.14, 0.5), 1.0)
		draw_rect(lr, Color(1, 1, 1, 0.55))
		draw_string(font, lp, m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.12, 0.14))
	if player:
		var pp := _to_map(Vector2(player.global_position.x, player.global_position.z), scale_f, offset)
		var yaw: float = player.yaw if "yaw" in player else 0.0
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(-fwd.y, fwd.x)
		var pts := PackedVector2Array([pp + fwd * 12.0, pp - fwd * 7.0 + right * 7.0, pp - fwd * 3.0, pp - fwd * 7.0 - right * 7.0])
		draw_colored_polygon(pts, Color(0.95, 0.25, 0.25))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color.WHITE, 1.5)
	draw_string(font, Vector2(14, size.y - 14), WorldMap.area_name(area), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.1, 0.12, 0.14))

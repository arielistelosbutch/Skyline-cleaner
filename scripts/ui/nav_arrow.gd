class_name NavArrow
extends Control
## Kompas nahoře uprostřed obrazovky (ve stylu Skyrimu): pás se světovými
## stranami, na kterém zlatá značka ukazuje k přijaté zakázce. Jakmile hráč
## dojde k budově, značka ukazuje k nejbližšímu neumytému oknu a nad okny se
## rozsvítí šipky ▼ (WindowMarkers). Modré značky = nářadí, které hráč hledá [R].
## Zakázka v jiné oblasti = rada, čím tam dojet.

## Vzdálenost od nejbližšího okna, od které hráč „dorazil" (zapnou se šipky nad okny).
const ARRIVE_DIST := 28.0
const WIDTH := 560.0
const HEIGHT := 34.0
## Zorný úhel kompasu (celá šířka pásu).
const SPAN := PI * 0.75

var player: Player
var target := Vector3.ZERO
var has_target := false
var arrived := false
var dist := 0.0
## Modré značky nářadí (žebříky, židle) – pozice ve světě, ukazují se po stisku [R].
var tool_marks: Array = []
## Zvláštní cíl (např. obchod v tutoriálu) – zelená značka.
static var poi_on := false
static var poi_pos := Vector3.ZERO
var _label: Label
var _t := 0.0
var _pulse := 0.0
var _yaw := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	_font = ThemeDB.fallback_font
	_label = UITheme.shadow_label("", 16, Color(1.0, 0.93, 0.6))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-120, HEIGHT + 4.0)
	_label.size = Vector2(WIDTH + 240, 24)
	add_child(_label)


## Cíl navigace z pozice hráče: nejbližší neumyté okno aktivní zakázky.
static func find_target(from: Vector3) -> Dictionary:
	var c := ContractManager.active()
	if c == null:
		return {}
	var best := INF
	var out := {}
	for wid in c.window_ids:
		var w := WindowRegistry.find_window(wid)
		if w == null or w.completed:
			continue
		var p := w.plane_to_world(w.glass_size * 0.5)
		var d := p.distance_to(from)
		if d < best:
			best = d
			out = {"pos": p, "dist": d, "title": c.title}
	return out


func _process(delta: float) -> void:
	_pulse += delta
	_t -= delta
	if player == null:
		visible = false
		return
	if _t <= 0.0:
		_t = 0.2
		var info := find_target(player.global_position)
		has_target = not info.is_empty()
		_label.text = ""
		if has_target:
			target = info["pos"]
			dist = info["dist"]
			arrived = dist < ARRIVE_DIST
			var here := WorldMap.area_at(Vector2(player.global_position.x, player.global_position.z))
			var there := WorldMap.area_at(Vector2(target.x, target.z))
			if here != there and there != "":
				_label.text = "Zakázka je v oblasti %s – dojeď tam autobusem nebo dodávkou" % WorldMap.area_name(there)
			elif not arrived:
				_label.text = "%s · %d m" % [info["title"], int(dist)]
		else:
			arrived = false
	visible = player.mode != Player.Mode.CLEANING and not player.ui_open
	if not visible:
		return
	var fwd := -player.camera.global_basis.z
	_yaw = atan2(fwd.x, -fwd.z)
	queue_redraw()


## Vodorovná poloha (px) směru `ang` (0 = sever / -Z) na pásu, nebo NAN mimo pás.
func _x_of(ang: float) -> float:
	var d := wrapf(ang - _yaw, -PI, PI)
	if absf(d) > SPAN * 0.5:
		return NAN
	return WIDTH * 0.5 + d / (SPAN * 0.5) * WIDTH * 0.5


func _dir_to(p: Vector3) -> float:
	var to := p - player.camera.global_position
	return atan2(to.x, -to.z)


func _draw() -> void:
	draw_rect(Rect2(0, 6, WIDTH, HEIGHT - 12), Color(0.06, 0.08, 0.1, 0.42))
	draw_line(Vector2(0, 6), Vector2(WIDTH, 6), Color(1, 1, 1, 0.25), 1.0)
	draw_line(Vector2(0, HEIGHT - 6), Vector2(WIDTH, HEIGHT - 6), Color(1, 1, 1, 0.25), 1.0)
	# světové strany a dílky po 15°
	var names := {0: "S", 2: "SV", 4: "V", 6: "JV", 8: "J", 10: "JZ", 12: "Z", 14: "SZ"}
	for k in 24:
		var x := _x_of(k * TAU / 24.0)
		if is_nan(x):
			continue
		var fade := 1.0 - absf(x - WIDTH * 0.5) / (WIDTH * 0.5) * 0.7
		var idx := k * 2 / 3 if k % 3 == 0 else -1
		if k % 3 == 0 and names.has(idx):
			var txt: String = names[idx]
			var fs := 17 if txt.length() == 1 else 13
			var sz := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			draw_string(_font, Vector2(x - sz.x * 0.5, HEIGHT * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9 * fade))
		else:
			draw_line(Vector2(x, HEIGHT * 0.5 - 3), Vector2(x, HEIGHT * 0.5 + 3), Color(1, 1, 1, 0.45 * fade), 1.0)
	# modré značky nářadí
	for p: Vector3 in tool_marks:
		_marker(_dir_to(p), Color(0.35, 0.65, 1.0), false)
	if poi_on:
		_marker(_dir_to(poi_pos), Color(0.35, 0.85, 0.4), true)
	# zlatá značka zakázky
	if has_target:
		_marker(_dir_to(target), Color(1.0, 0.82, 0.25), true)
	# střed pásu
	draw_line(Vector2(WIDTH * 0.5, 2), Vector2(WIDTH * 0.5, 7), Color(1, 1, 1, 0.8), 2.0)


func _marker(ang: float, col: Color, pulse: bool) -> void:
	var x := _x_of(ang)
	var edge := false
	if is_nan(x):
		# mimo pás: značka „přilepená" na okraji, ať hráč ví, kam se otočit
		var d := wrapf(ang - _yaw, -PI, PI)
		x = 8.0 if d < 0.0 else WIDTH - 8.0
		edge = true
	var a := 1.0 if not pulse else 0.8 + 0.2 * sin(_pulse * 4.0)
	var c := Color(col, a)
	var y := HEIGHT * 0.5
	if edge:
		var s := -1.0 if x < WIDTH * 0.5 else 1.0
		draw_colored_polygon(PackedVector2Array([Vector2(x + s * 7, y), Vector2(x - s * 5, y - 9), Vector2(x - s * 5, y + 9)]), c)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(x, y + 11), Vector2(x - 8, y - 4), Vector2(x, y - 11), Vector2(x + 8, y - 4)]), c)
		draw_polyline(PackedVector2Array([Vector2(x, y + 11), Vector2(x - 8, y - 4), Vector2(x, y - 11), Vector2(x + 8, y - 4), Vector2(x, y + 11)]), Color(0.1, 0.08, 0.02, 0.8), 1.5, true)

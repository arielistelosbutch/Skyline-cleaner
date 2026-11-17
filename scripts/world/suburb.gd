class_name Suburb
extends Node3D
## Oblast II – Předměstí Javorov. Leží daleko od vesnice (posun ORIGIN),
## jezdí se sem autobusem z návsi. Patrové rodinné domy, moderní vila,
## kavárna, obchody, bytový dům a škola. Větší budovy nemají interiér
## (za okny je jen jednoduchá „místnost"), aby svět nebyl zbytečně těžký.
## Lokální souřadnice: hlavní ulice vede podél X v pásu z ∈ [-4, 4].

const ORIGIN := Vector3(2000, 0, 0)
const AREA_ID := "predmesti"
const AREA_NAME := "Oblast II – Předměstí · Javorov"
const UNLOCK_LEVEL := 4
const GROUND_SHADER := preload("res://shaders/ground.gdshader")
const STOREY := 2.8

## Kde hráč vystoupí z autobusu (lokálně) a kam se postaví žebříky, které jedou s ním.
const ARRIVE := Vector3(-64.0, 0.0, -5.3)
const ARRIVE_YAW := -PI * 0.5
const LADDER_SPOT := Vector3(-71.0, 0.0, -11.2)

## Zákazníci na Předměstí (poptávky): [jméno do titulku, kdo píše, typ budovy].
const CLIENTS := {
	"pr_dum_b": ["Dům Svobodových", "Paní Svobodová", "Patrový rodinný dům"],
	"pr_dum_c": ["Dům Kratochvílových", "Pan Kratochvíl", "Patrový rodinný dům"],
	"pr_obchody": ["Obchody na Javorové", "Pan Vlk z pekárny", "Obchody s byty v patře"],
	"pr_byty_prizemi": ["Bytový dům – přízemí", "Správce domu pan Dušek", "Bytový dům"],
}

var _static: StaticBody3D
var _deco: MeshBuilder
var _rng := RandomNumberGenerator.new()
var _exclude: Array[Rect2] = []
var anchors: Array[RopeAnchor] = []


func _ready() -> void:
	_rng.seed = 7331
	position = ORIGIN
	_static = StaticBody3D.new()
	_static.name = "StaticCollision"
	add_child(_static)
	_deco = MeshBuilder.new(501)
	WorldMap.add_area(AREA_ID, AREA_NAME, Rect2(ORIGIN.x - 115, -62, 230, 124))

	_ground()
	_street()
	_family_house_a()
	_family_houses_bc()
	_villa()
	_cafe()
	_shops()
	_apartment_block()
	_school()
	_door_paths()
	_parking(29.0, 7.0, 43.0, 18.0, 1.0)
	_parking(34.0, -7.0, 48.0, -18.0, -1.0)
	_greenery()
	_hills()
	_bounds()
	_deco.to_instance(self, "SuburbDecor")


func gpos(local: Vector3) -> Vector3:
	return ORIGIN + local


func _map_rect(x: float, z: float, w: float, d: float, color: Color, label: String = "") -> void:
	WorldMap.add_rect(Rect2(ORIGIN.x + x - w * 0.5, z - d * 0.5, w, d), color, label)


func _exclude_rect(x0: float, z0: float, x1: float, z1: float) -> void:
	_exclude.append(Rect2(Vector2(minf(x0, x1), minf(z0, z1)), Vector2(absf(x1 - x0), absf(z1 - z0))))


func _excluded(p: Vector2, margin: float = 0.0) -> bool:
	for r in _exclude:
		if r.grow(margin).has_point(p):
			return true
	return false


func _col_box(size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	_static.add_child(cs)


func _strip(b: MeshBuilder, x0: float, z0: float, x1: float, z1: float, y: float, color: Color, thick: float = 0.04) -> void:
	b.add_box(Vector3(absf(x1 - x0), thick, absf(z1 - z0)), Vector3((x0 + x1) * 0.5, y - thick * 0.5, (z0 + z1) * 0.5), color, Basis.IDENTITY, 0.0)


func _label(text: String, pos: Vector3, size: int = 56, color: Color = Color(1, 1, 1), outline: Color = Color(0.15, 0.2, 0.25), yaw: float = 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = outline
	l.position = pos
	l.rotation.y = yaw
	add_child(l)
	# názvy na cedulích (ne jen text ve vzduchu); velké nápisy na střeše a „P" mají vlastní
	if size < 150 and text != "P":
		# deska kousek před zdí, ať se nekryje s římsami a pásy fasády
		l.position += l.basis * Vector3(0, 0, 0.012)
		Props.board_behind(l, outline)


# ------------------------------------------------------------------ terén a ulice

func _ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = mat
	add_child(mi)
	# Vlastní kolize země: WorldBoundaryShape3D z vesnice je v Jolt fyzice jen
	# konečná rovina (výchozí velikost 2 km) a sem už nesahá.
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(600, 2, 600)
	cs.shape = bs
	cs.position = Vector3(0, -1, 0)
	_static.add_child(cs)


func _street() -> void:
	var b := MeshBuilder.new(511)
	var asphalt := Color(0.31, 0.32, 0.34)
	var walk := Color(0.7, 0.69, 0.66)
	var curb := Color(0.8, 0.79, 0.76)
	_strip(b, -120, -4, 120, 4, 0.03, asphalt)
	for x in range(-118, 118, 6):
		_strip(b, x, -0.07, x + 3.0, 0.07, 0.035, Color(0.95, 0.95, 0.92), 0.01)
	for s: float in [-1.0, 1.0]:
		_strip(b, -120, s * 4.0, 120, s * 4.2, 0.08, curb, 0.09)
		_strip(b, -110, s * 4.2, 110, s * 6.6, 0.07, walk, 0.07)
	_exclude_rect(-125, -7.2, 125, 7.2)
	WorldMap.add_rect(Rect2(ORIGIN.x - 120, -4, 240, 8), Color(0.45, 0.46, 0.5))
	# přechod pro chodce u kavárny
	for k in 8:
		_strip(b, -36.0 + k * 0.0, -3.9 + k * 1.0, -32.0, -3.4 + k * 1.0, 0.036, Color(0.96, 0.96, 0.94), 0.01)
	# lampy
	var lamps := []
	for x: float in [-90.0, -60.0, -30.0, 0.0, 30.0, 60.0, 90.0]:
		Props.lamp_post(b, Vector3(x, 0, -5.9), -PI * 0.5, lamps)
		Props.lamp_post(b, Vector3(x + 15.0, 0, 5.9), PI * 0.5, lamps)
	Props.lamp_lights(self, lamps)
	# zaparkovaná auta
	var car_cols := [Color(0.8, 0.82, 0.85), Color(0.2, 0.3, 0.5), Color(0.7, 0.2, 0.18), Color(0.15, 0.15, 0.17), Color(0.85, 0.7, 0.3)]
	var cars := [[-40.0, 2.6, 0.0], [-8.0, 2.6, 0.0], [18.0, -2.6, PI], [44.0, 2.6, 0.0], [75.0, -2.6, PI]]
	for i in cars.size():
		var c: Array = cars[i]
		var xf := Transform3D(Basis(Vector3.UP, PI * 0.5 + c[2]), Vector3(c[0], 0, c[1]))
		Props.car(b, xf, car_cols[i % car_cols.size()])
		_col_box(Vector3(4.0, 1.4, 1.8), Transform3D(Basis.IDENTITY, Vector3(c[0], 0.7, c[1])))
	# autobusová zastávka (sever, u vjezdu do čtvrti)
	var sx := -70.0
	b.add_box(Vector3(3.4, 0.1, 1.6), Vector3(sx, 2.45, -7.6), Color(0.25, 0.4, 0.55))
	for px: float in [sx - 1.6, sx + 1.6]:
		b.add_box(Vector3(0.08, 2.45, 0.08), Vector3(px, 1.22, -8.2), Color(0.25, 0.4, 0.55))
		b.add_box(Vector3(0.08, 2.45, 0.08), Vector3(px, 1.22, -7.0), Color(0.25, 0.4, 0.55))
	b.add_box(Vector3(3.3, 2.2, 0.04), Vector3(sx, 1.2, -8.3), Color(0.65, 0.8, 0.85), Basis.IDENTITY, 0.0)
	Props.bench(b, Transform3D(Basis.IDENTITY, Vector3(sx, 0, -7.8)))
	_col_box(Vector3(3.4, 2.4, 0.2), Transform3D(Basis.IDENTITY, Vector3(sx, 1.2, -8.3)))
	# sloupek s jízdním řádem
	b.add_box(Vector3(0.08, 2.2, 0.08), Vector3(sx + 2.6, 1.1, -6.9), Color(0.5, 0.5, 0.52))
	b.add_box(Vector3(0.5, 0.65, 0.05), Vector3(sx + 2.6, 1.7, -6.85), Color(0.95, 0.85, 0.2))
	b.to_instance(self, "Street")
	_exclude_rect(sx - 2.5, -9.5, sx + 4.5, -6.5)
	_exclude_rect(LADDER_SPOT.x - 7.0, LADDER_SPOT.z - 2.0, LADDER_SPOT.x + 1.0, LADDER_SPOT.z + 1.5)
	_label("Javorov, Lipová", Vector3(sx, 2.7, -6.78), 40)
	var bus := SimpleInteractable.create("[E] Autobus do Lipové Lhoty (náves)", func(p): get_tree().call_group("world", "bus_travel", "venkov", p), Vector3(0.6, 2.2, 0.4), Vector3(sx + 2.6, 1.1, -6.9))
	add_child(bus)
	# druhý jízdní řád: do města Brodec
	var bm := MeshBuilder.new(578)
	bm.add_box(Vector3(0.08, 2.2, 0.08), Vector3(sx + 3.8, 1.1, -6.9), Color(0.5, 0.5, 0.52))
	bm.add_box(Vector3(0.5, 0.65, 0.05), Vector3(sx + 3.8, 1.7, -6.85), Color(0.85, 0.3, 0.25))
	bm.to_instance(self, "BusCityPost")
	var bus_city := SimpleInteractable.create("[E] Autobus do Brodce – Město (zakázky od úrovně %d)" % City.UNLOCK_LEVEL, func(p): get_tree().call_group("world", "bus_travel", City.AREA_ID, p), Vector3(0.6, 2.2, 0.4), Vector3(sx + 3.8, 1.1, -6.9))
	add_child(bus_city)
	_label("Lipová Lhota", Vector3(sx + 2.6, 2.15, -6.8), 22, Color(0.1, 0.1, 0.1), Color(1, 1, 1))
	_label("Brodec", Vector3(sx + 3.8, 2.15, -6.8), 22, Color(0.1, 0.1, 0.1), Color(1, 1, 1))
	WorldMap.add_marker("bus_pr", Vector2(ORIGIN.x + sx, -9.0), "Autobus – Lipová Lhota, Brodec", Color(0.95, 0.8, 0.2))
	# pobočka obchodu s vybavením hned u zastávky (nákup bez cesty na náves)
	ShopKiosk.build(self, Vector3(-55.0, 0, -8.4), 0.0, "Úklid & Výšky – Javorov", Vector2(ORIGIN.x - 55.0, -8.4), 571)
	_exclude_rect(-58.0, -10.5, -52.0, -6.6)
	# cedule čtvrti
	for x: float in [-108.0, 108.0]:
		_deco.add_box(Vector3(0.08, 2.0, 0.08), Vector3(x, 1.0, -7.0), Color(0.5, 0.5, 0.5))
		_deco.add_box(Vector3(0.06, 0.7, 1.9), Vector3(x, 2.0, -7.0), Color(0.98, 0.98, 0.95))
		for side: float in [-1.0, 1.0]:
			var l := Label3D.new()
			l.text = "Javorov"
			l.font_size = 48
			l.pixel_size = 0.005
			l.modulate = Color(0.1, 0.1, 0.12)
			l.outline_size = 0
			l.position = Vector3(x + side * 0.035, 2.0, -7.0)
			l.rotation.y = side * PI * 0.5
			add_child(l)
	# kohoutek s vodou na chodníku (u kavárny)
	# sudy s vodou u budov se zakázkami (vymáchání nástroje, doplnění rozprašovače)
	# (méně zdrojů než domů – vodu k domu doneseš v kbelíku)
	for wp: Vector3 in [Vector3(-41.0, 0, 7.0), Vector3(30.0, 0, -7.0), Vector3(-3.4, 0, -7.6),
			Vector3(46.0, 0, 7.6), Vector3(26.5, 0, 7.6)]:
		_water_point(wp)


func _water_point(pos: Vector3) -> void:
	var b := MeshBuilder.new(int(absf(pos.x) * 7.0 + 3.0))
	Props.water_barrel(b, pos)
	b.to_instance(self, "Water")
	var it := SimpleInteractable.create("[E] Vymáchat nástroj a doplnit rozprašovač (sud s vodou)", func(p): p.cleaning.rinse(), Vector3(0.65, 0.95, 0.65), pos + Vector3(0, 0.47, 0))
	it.add_to_group("water_source")
	add_child(it)


## Předzahrádka u domu: chodník ke dveřím a plot podél chodníku.
func _front_yard(x: float, w: float, front: float, door_x: float, fence_c: Color) -> void:
	var fz := -6.9 if front > 0 else 6.9
	Props.picket_fence(_deco, _static, Vector3(x - w * 0.5 - 2.5, 0, fz), Vector3(x + w * 0.5 + 2.5, 0, fz), fence_c, door_x - (x - w * 0.5 - 2.5), 1.4)


# ------------------------------------------------------------------ budovy

## Okna jednoho patra: list sloupců u, šířka, výška, parapet nad podlahou patra.
func _floor_windows(side: String, us: Array, floor_i: int, w: float, h: float, sill: float, prefix: String, storey: float = STOREY, extra: Dictionary = {}) -> Array:
	var out := []
	for k in us.size():
		var o := {"side": side, "u": us[k], "width": w, "height": h, "sill": floor_i * storey + sill}
		if prefix != "":
			o["id"] = "%s_p%d_%d" % [prefix, floor_i, k + 1]
		for key in extra:
			o[key] = extra[key]
		out.append(o)
	return out


## Rodinný dům Malých – první patrový dům (příběhová zakázka, malý žebřík).
func _family_house_a() -> void:
	var x := -45.0
	var w := 9.0
	var d := 8.0
	var z := -6.6 - 5.0 - d * 0.5
	var ops := [
		{"side": "front", "type": "door", "u": -2.8, "width": 1.1, "height": 2.2, "sill": 0.0, "color": Color(0.55, 0.3, 0.2)},
		{"side": "front", "u": 0.2, "width": 1.3, "height": 1.3, "sill": 0.85, "id": "pr_maly_w1", "flowerbox": true},
		{"side": "front", "u": 2.8, "width": 1.3, "height": 1.3, "sill": 0.85, "id": "pr_maly_w2"},
		{"side": "front", "u": -2.8, "width": 1.1, "height": 1.2, "sill": STOREY + 0.85, "id": "pr_maly_w3"},
		{"side": "front", "u": 0.2, "width": 1.3, "height": 1.2, "sill": STOREY + 0.85, "id": "pr_maly_w4", "shutters": true},
		{"side": "front", "u": 2.8, "width": 1.3, "height": 1.2, "sill": STOREY + 0.85, "id": "pr_maly_w5", "shutters": true},
		{"side": "left", "u": 0.0, "width": 1.1, "height": 1.2, "sill": 0.9, "id": "pr_maly_w6"},
		{"side": "left", "u": 0.0, "width": 1.1, "height": 1.2, "sill": STOREY + 0.85, "id": "pr_maly_w7"},
		{"side": "back", "u": 0.0, "width": 1.4, "height": 1.2, "sill": 0.9},
		{"side": "back", "u": 0.0, "width": 1.4, "height": 1.2, "sill": STOREY + 0.85},
		{"side": "right", "u": 1.0, "width": 1.0, "height": 1.0, "sill": STOREY + 1.0},
	]
	HouseBuilder.build(self, {
		"name": "HouseMaly", "position": Vector3(x, 0, z), "width": w, "depth": d,
		"found_h": 0.3, "wall_h": STOREY * 2.0, "roof_h": 2.3, "seed": 520,
		"wall_color": Color(0.95, 0.88, 0.7), "roof_color": Color(0.55, 0.28, 0.22), "trim_color": Color(0.98, 0.97, 0.94),
		"shutter_color": Color(0.35, 0.45, 0.55), "bands": [STOREY], "band_color": Color(0.85, 0.78, 0.62),
		"dirt_profile": "venkov_bezne", "openings": ops, "chimney_x": 2.4,
		"interior": true, "levels": [0.0, STOREY], "styles": ["house", "house"],
		"interior_color": Color(0.95, 0.92, 0.85), "floor_color": Color(0.68, 0.5, 0.34),
	})
	_front_yard(x, w, 1.0, x - 2.8, Color(0.97, 0.97, 0.94))
	Props.mailbox(_deco, Vector3(x - 1.4, 0, -7.1), 0.0, Color(0.85, 0.25, 0.2))
	_exclude_rect(x - w * 0.5 - 1.5, z - d * 0.5 - 1.5, x + w * 0.5 + 1.5, -6.6)
	_map_rect(x, z, w, d, Color(0.8, 0.55, 0.5))


## Další dva patrové domy – zákazníci, kteří posílají poptávky.
func _family_houses_bc() -> void:
	var defs := [
		["pr_dum_b", Vector3(58.0, 0, -15.5), 0.0, 9.5, 8.0, Color(0.78, 0.86, 0.92), Color(0.3, 0.32, 0.36), Color(0.95, 0.95, 0.95)],
		["pr_dum_c", Vector3(52.0, 0, 15.5), PI, 9.0, 8.0, Color(0.93, 0.8, 0.72), Color(0.62, 0.3, 0.22), Color(0.4, 0.5, 0.35)],
	]
	for i in defs.size():
		var df: Array = defs[i]
		var cid: String = df[0]
		var pos: Vector3 = df[1]
		var w: float = df[3]
		var d: float = df[4]
		var ops := [
			{"side": "front", "type": "door", "u": w * 0.3, "width": 1.0, "height": 2.2, "sill": 0.0},
			{"side": "front", "u": -w * 0.25, "width": 1.6, "height": 1.3, "sill": 0.85, "id": cid + "_w1"},
			{"side": "front", "u": -w * 0.25, "width": 1.6, "height": 1.2, "sill": STOREY + 0.85, "id": cid + "_w2"},
			{"side": "front", "u": w * 0.3, "width": 1.0, "height": 1.2, "sill": STOREY + 0.85, "id": cid + "_w3"},
			{"side": "right", "u": 0.0, "width": 1.2, "height": 1.2, "sill": 0.9, "id": cid + "_w4"},
			{"side": "right", "u": 0.0, "width": 1.2, "height": 1.2, "sill": STOREY + 0.85, "id": cid + "_w5"},
			{"side": "back", "u": 0.0, "width": 1.4, "height": 1.2, "sill": 0.9},
			{"side": "left", "u": 0.0, "width": 1.0, "height": 1.0, "sill": STOREY + 1.0},
		]
		HouseBuilder.build(self, {
			"name": "House_" + cid, "position": pos, "rotation_y": df[2], "width": w, "depth": d,
			"found_h": 0.3, "wall_h": STOREY * 2.0, "roof_h": 2.1 + i * 0.3, "seed": 530 + i,
			"wall_color": df[5], "roof_color": df[6], "trim_color": df[7], "bands": [STOREY],
			"openings": ops, "chimney_x": -w * 0.3,
			"interior": true, "levels": [0.0, STOREY], "styles": ["house", "house"],
			"interior_color": [Color(0.92, 0.95, 0.97), Color(0.97, 0.92, 0.86)][i], "floor_color": Color(0.62, 0.46, 0.32),
		})
		var front := 1.0 if df[2] == 0.0 else -1.0
		var door_x := pos.x + w * 0.3 * front
		_front_yard(pos.x, w, front, door_x, [Color(0.6, 0.62, 0.6), Color(0.62, 0.45, 0.3)][i])
		var fz := -6.9 if front > 0 else 6.9
		_exclude_rect(pos.x - w * 0.5 - 1.5, pos.z - d * 0.5 - 1.5, pos.x + w * 0.5 + 1.5, pos.z + d * 0.5 + 1.5)
		_map_rect(pos.x, pos.z, w, d, (df[6] as Color).lightened(0.3))
		var cl: Array = CLIENTS[cid]
		ContractManager.register_client({
			"id": cid, "name": cl[0], "who": cl[1], "area": AREA_ID, "building": cl[2],
			"pos": Vector2(ORIGIN.x + door_x, pos.z + front * (d * 0.5 + 2.0)),
			"front": [cid + "_w1", cid + "_w2", cid + "_w3"],
			"all": [cid + "_w1", cid + "_w2", cid + "_w3", cid + "_w4", cid + "_w5"],
			"tree": i == 1, "pay": 1.25,
		})


## Moderní vila – bílá kostka s plochou střechou a velkými okny (výsuvný žebřík).
func _villa() -> void:
	var x := -12.0
	var w := 13.0
	var d := 10.0
	var z := -6.6 - 7.0 - d * 0.5
	var st := 3.1
	var ops := [
		{"side": "front", "type": "door", "u": -4.6, "width": 1.2, "height": 2.4, "sill": 0.0, "color": Color(0.2, 0.2, 0.22)},
		{"side": "front", "u": -1.4, "width": 2.6, "height": 2.1, "sill": 0.3, "id": "pr_vila_w1", "cross": false},
		{"side": "front", "u": 2.4, "width": 2.6, "height": 2.1, "sill": 0.3, "id": "pr_vila_w2", "cross": false},
		{"side": "front", "u": -4.6, "width": 1.2, "height": 1.9, "sill": st + 0.4, "id": "pr_vila_w3"},
		{"side": "front", "u": -1.4, "width": 2.6, "height": 1.9, "sill": st + 0.4, "id": "pr_vila_w4"},
		{"side": "front", "u": 2.4, "width": 2.6, "height": 1.9, "sill": st + 0.4, "id": "pr_vila_w5"},
		{"side": "right", "u": 0.0, "width": 2.2, "height": 1.9, "sill": st + 0.4, "id": "pr_vila_w6"},
		{"side": "right", "u": 0.0, "width": 2.2, "height": 2.1, "sill": 0.3, "id": "pr_vila_w7"},
		{"side": "back", "u": -2.0, "width": 3.0, "height": 2.1, "sill": 0.3},
		{"side": "back", "u": 2.5, "width": 2.0, "height": 1.6, "sill": st + 0.6},
		{"side": "left", "u": 0.0, "width": 1.0, "height": 1.6, "sill": st + 0.5},
	]
	HouseBuilder.build(self, {
		"name": "VillaHorvat", "position": Vector3(x, 0, z), "width": w, "depth": d,
		"found_h": 0.2, "wall_h": st * 2.0, "roof": "flat", "parapet_h": 0.35, "seed": 540,
		"wall_color": Color(0.96, 0.96, 0.95), "roof_color": Color(0.38, 0.39, 0.4), "trim_color": Color(0.22, 0.23, 0.25),
		"bands": [st], "band_color": Color(0.55, 0.42, 0.3), "blinds": true, "curtain_color": Color(0.85, 0.85, 0.83),
		"dirt_profile": "mesto_prach", "openings": ops, "door_step": true,
		"interior": true, "levels": [0.0, st], "styles": ["villa", "villa_up"],
		"interior_color": Color(0.97, 0.97, 0.96), "floor_color": Color(0.78, 0.72, 0.62),
	})
	# dřevěný obklad u vstupu a nízká zídka místo plotu
	# (obklad má výřezy pro dveře i okno nad nimi – dřív okno w3 zakrýval)
	var wood := Color(0.62, 0.45, 0.3)
	var fz := z + d * 0.5 + 0.03
	var top := 0.2 + st * 2.0
	for sx: float in [-1.0, 1.0]:
		_deco.add_box(Vector3(0.3, st * 2.0, 0.06), Vector3(x - 4.6 + sx * 0.85, 0.2 + st, fz), wood)
	var y0 := 0.2 + 2.4 + 0.12
	var y1 := 0.2 + st + 0.4 - 0.12
	_deco.add_box(Vector3(1.4, y1 - y0, 0.06), Vector3(x - 4.6, (y0 + y1) * 0.5, fz), wood)
	var y2 := 0.2 + st + 0.4 + 1.9 + 0.12
	if top - y2 > 0.05:
		_deco.add_box(Vector3(1.4, top - y2, 0.06), Vector3(x - 4.6, (y2 + top) * 0.5, fz), wood)
	for s: float in [-1.0, 1.0]:
		var zx := x + s * (w * 0.5 + 1.0)
		_deco.add_box(Vector3(0.3, 0.8, 7.0), Vector3(zx, 0.4, -6.9 - 3.5), Color(0.75, 0.75, 0.73))
		_col_box(Vector3(0.3, 0.8, 7.0), Transform3D(Basis.IDENTITY, Vector3(zx, 0.4, -6.9 - 3.5)))
	_exclude_rect(x - w * 0.5 - 2.0, z - d * 0.5 - 2.0, x + w * 0.5 + 2.0, -6.6)
	_map_rect(x, z, w, d, Color(0.85, 0.85, 0.88))


## Kavárna U Lípy – velké výlohy v přízemí, byt v patře, markýza.
func _cafe() -> void:
	var x := -46.0
	var w := 12.0
	var d := 9.0
	var z := 6.6 + 3.5 + d * 0.5
	var ops := [
		{"side": "front", "type": "door", "u": 0.0, "width": 1.4, "height": 2.4, "sill": 0.0, "color": Color(0.3, 0.2, 0.15)},
		{"side": "front", "u": -3.6, "width": 3.4, "height": 2.0, "sill": 0.4, "id": "pr_kavarna_w1", "cross": false, "profile": "kuchyn_mastnota"},
		{"side": "front", "u": 3.6, "width": 3.4, "height": 2.0, "sill": 0.4, "id": "pr_kavarna_w2", "cross": false, "profile": "kuchyn_mastnota"},
		{"side": "front", "u": -3.6, "width": 1.4, "height": 1.3, "sill": 3.3 + 0.8, "id": "pr_kavarna_w3", "flowerbox": true},
		{"side": "front", "u": 0.0, "width": 1.4, "height": 1.3, "sill": 3.3 + 0.8, "id": "pr_kavarna_w4"},
		{"side": "front", "u": 3.6, "width": 1.4, "height": 1.3, "sill": 3.3 + 0.8, "id": "pr_kavarna_w5", "flowerbox": true},
		{"side": "left", "u": 1.0, "width": 1.6, "height": 1.6, "sill": 0.8, "id": "pr_kavarna_w6", "profile": "kuchyn_mastnota"},
		{"side": "right", "u": 0.0, "width": 1.2, "height": 1.2, "sill": 3.3 + 0.8},
		{"side": "back", "u": 0.0, "width": 1.2, "height": 1.0, "sill": 1.2},
	]
	HouseBuilder.build(self, {
		"name": "CafeLipa", "position": Vector3(x, 0, z), "rotation_y": PI, "width": w, "depth": d,
		"found_h": 0.2, "wall_h": 3.3 + STOREY, "roof_h": 2.2, "seed": 550,
		"wall_color": Color(0.98, 0.93, 0.82), "roof_color": Color(0.3, 0.33, 0.38), "trim_color": Color(0.35, 0.22, 0.15),
		"bands": [3.3], "band_color": Color(0.35, 0.22, 0.15), "chimney_x": 3.0,
		"room_color": Color(0.55, 0.4, 0.28), "curtain_color": Color(0.95, 0.9, 0.8),
		"dirt_profile": "venkov_bezne", "openings": ops,
		"interior": true, "levels": [0.0, 3.3], "styles": ["cafe", "flat"],
		"interior_color": Color(0.96, 0.9, 0.8), "floor_color": Color(0.5, 0.35, 0.24),
	})
	# markýza nad výlohami (dům je otočený čelem k ulici, -Z)
	var awn := Color(0.75, 0.2, 0.18)
	for k in 9:
		var c := awn if k % 2 == 0 else Color(0.97, 0.95, 0.9)
		_deco.add_box(Vector3(w * 0.9 / 9.0, 0.05, 1.3), Vector3(x - w * 0.45 + (k + 0.5) * w * 0.9 / 9.0, 2.95, z - d * 0.5 - 0.6), c, Basis(Vector3.RIGHT, -0.3))
	# venkovní posezení
	for k in 3:
		var tx := x - 4.0 + k * 4.0
		_deco.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.7, 0.04, 0.7)), Vector3(tx, 0.74, 7.6)), Color(0.9, 0.9, 0.88))
		_deco.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.06, 0.72, 0.06)), Vector3(tx, 0.37, 7.6)), Color(0.25, 0.25, 0.27))
		for s: float in [-1.0, 1.0]:
			_deco.add_box(Vector3(0.42, 0.05, 0.42), Vector3(tx + s * 0.6, 0.45, 7.6), Color(0.35, 0.25, 0.18))
	_label("KAVÁRNA U LÍPY", Vector3(x, 3.75, z - d * 0.5 - 0.14), 60, Color(1, 0.97, 0.88), Color(0.35, 0.2, 0.12), PI)
	_exclude_rect(x - w * 0.5 - 1.5, 6.6, x + w * 0.5 + 1.5, z + d * 0.5 + 1.5)
	_map_rect(x, z, w, d, Color(0.85, 0.6, 0.45), "Kavárna")


## Obchody (pekárna, květinářství) s byty v patře – zákazník poptávek.
func _shops() -> void:
	var x := -16.0
	var w := 15.0
	var d := 9.0
	var z := 6.6 + 1.0 + d * 0.5
	var cid := "pr_obchody"
	var ops := [
		{"side": "front", "type": "door", "u": -3.8, "width": 1.2, "height": 2.3, "sill": 0.0, "color": Color(0.55, 0.35, 0.2)},
		{"side": "front", "type": "door", "u": 3.8, "width": 1.2, "height": 2.3, "sill": 0.0, "color": Color(0.3, 0.5, 0.35)},
		{"side": "front", "u": -5.9, "width": 2.4, "height": 1.8, "sill": 0.5, "id": cid + "_w1", "cross": false},
		{"side": "front", "u": -1.6, "width": 2.4, "height": 1.8, "sill": 0.5, "id": cid + "_w2", "cross": false},
		{"side": "front", "u": 1.6, "width": 2.4, "height": 1.8, "sill": 0.5, "id": cid + "_w3", "cross": false, "style": "flowers"},
		{"side": "front", "u": 5.9, "width": 2.4, "height": 1.8, "sill": 0.5, "id": cid + "_w4", "cross": false, "style": "flowers"},
		{"side": "front", "u": -5.9, "width": 1.3, "height": 1.3, "sill": 3.2 + 0.8, "id": cid + "_w5"},
		{"side": "front", "u": -1.6, "width": 1.3, "height": 1.3, "sill": 3.2 + 0.8, "id": cid + "_w6"},
		{"side": "front", "u": 1.6, "width": 1.3, "height": 1.3, "sill": 3.2 + 0.8},
		{"side": "front", "u": 5.9, "width": 1.3, "height": 1.3, "sill": 3.2 + 0.8},
		{"side": "left", "u": 0.0, "width": 1.2, "height": 1.2, "sill": 3.2 + 0.8},
	]
	HouseBuilder.build(self, {
		"name": "Shops", "position": Vector3(x, 0, z), "rotation_y": PI, "width": w, "depth": d,
		"found_h": 0.2, "wall_h": 3.2 + STOREY, "roof_h": 2.0, "seed": 560,
		"wall_color": Color(0.85, 0.9, 0.82), "roof_color": Color(0.6, 0.3, 0.22), "trim_color": Color(0.96, 0.96, 0.94),
		"bands": [3.2], "chimney": false, "room_color": Color(0.7, 0.6, 0.45),
		"openings": ops,
		"interior": true, "levels": [0.0, 3.2], "styles": ["bakery", "flat"],
		"interior_color": Color(0.96, 0.94, 0.88), "floor_color": Color(0.6, 0.58, 0.55),
	})
	_label("PEKÁRNA", Vector3(x + 3.8, 3.6, z - d * 0.5 - 0.14), 52, Color(1, 0.95, 0.85), Color(0.45, 0.28, 0.12), PI)
	_label("KVĚTINY", Vector3(x - 3.8, 3.6, z - d * 0.5 - 0.14), 52, Color(1, 1, 1), Color(0.2, 0.45, 0.25), PI)
	# květiny před květinářstvím
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var fc := [Color(0.92, 0.3, 0.35), Color(0.98, 0.75, 0.25), Color(0.85, 0.45, 0.8), Color(1, 1, 1)]
	for k in 4:
		var px := x - 6.0 + k * 0.9
		_deco.add_box(Vector3(0.7, 0.35, 0.5), Vector3(px, 0.25, 7.3), Color(0.5, 0.35, 0.22))
		for j in 6:
			_deco.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.11), Vector3(px + rng.randf_range(-0.28, 0.28), 0.5, 7.3 + rng.randf_range(-0.18, 0.18))), fc[rng.randi() % fc.size()], 0.05)
	_exclude_rect(x - w * 0.5 - 1.0, 6.6, x + w * 0.5 + 1.0, z + d * 0.5 + 1.5)
	_map_rect(x, z, w, d, Color(0.7, 0.8, 0.65), "Obchody")
	var cl: Array = CLIENTS[cid]
	ContractManager.register_client({
		"id": cid, "name": cl[0], "who": cl[1], "area": AREA_ID, "building": cl[2],
		"pos": Vector2(ORIGIN.x + x, 6.0),
		"front": [cid + "_w1", cid + "_w2", cid + "_w3", cid + "_w4"],
		"all": [cid + "_w1", cid + "_w2", cid + "_w3", cid + "_w4", cid + "_w5", cid + "_w6"],
		"tree": false, "pay": 1.2,
	})


## Bytový dům Javorová 12 – čtyři podlaží, plochá střecha s atikou a kotvicími body.
func _apartment_block() -> void:
	var x := 22.0
	var w := 16.0
	var d := 10.0
	var z := -6.6 - 6.0 - d * 0.5
	var st := 2.9
	var floors := 4
	var cols := [-6.0, -3.0, 3.0, 6.0]
	var ops := [{"side": "front", "type": "door", "u": 0.0, "width": 1.3, "height": 2.3, "sill": 0.0, "color": Color(0.3, 0.45, 0.6)}]
	for f in range(1, floors):
		ops.append({"side": "front", "u": 0.0, "width": 1.3, "height": 0.8, "sill": f * st + 1.6, "cross": false, "style": "stair"})
	for f in floors:
		for k in cols.size():
			var o := {"side": "front", "u": cols[k], "width": 1.3, "height": 1.45, "sill": f * st + 0.9, "id": "pr_byty_p%d_%d" % [f, k + 1]}
			if f == 0:
				o["id"] = "pr_byty_prizemi_w%d" % (k + 1)
			ops.append(o)
	for f in floors:
		for u: float in [-4.5, 0.0, 4.5]:
			ops.append({"side": "back", "u": u, "width": 1.3, "height": 1.4, "sill": f * st + 0.9})
		for side in ["left", "right"]:
			ops.append({"side": side, "u": 0.0, "width": 1.1, "height": 1.3, "sill": f * st + 0.95})
	var bands := []
	for f in range(1, floors):
		bands.append(f * st)
	var fh := 0.3
	var wh := st * floors + 0.2
	HouseBuilder.build(self, {
		"name": "ApartmentBlock", "position": Vector3(x, 0, z), "width": w, "depth": d,
		"found_h": fh, "wall_h": wh, "roof": "flat", "parapet_h": 0.95, "seed": 570,
		"wall_color": Color(0.93, 0.84, 0.62), "roof_color": Color(0.36, 0.37, 0.39), "trim_color": Color(0.96, 0.96, 0.94),
		"bands": bands, "band_color": Color(0.82, 0.7, 0.5), "dirt_profile": "fasada_vyska",
		"curtain_color": Color(0.92, 0.9, 0.84), "openings": ops,
		"interior": true, "levels": [0.0, st, st * 2.0, st * 3.0], "styles": ["flat", "flat", "flat", "flat"],
		"interior_color": Color(0.95, 0.93, 0.88), "floor_color": Color(0.66, 0.5, 0.36),
	})
	var roof_y := fh + wh + 0.25
	_label("JAVOROVÁ 12", Vector3(x, 2.75, z + d * 0.5 + 0.03), 40, Color(1, 1, 1), Color(0.25, 0.3, 0.4))
	# vchod: schodiště na střechu (zjednodušeně – přenese hráče nahoru a zpět)
	var door_out := Vector3(x, 0.05, z + d * 0.5 + 1.0)
	var roof_in := Vector3(x, roof_y + 0.05, z - 1.8)
	var up := SimpleInteractable.create("[E] Vyjít schodištěm na střechu (kotvicí body pro slaňování)", func(p): _to_roof(p, roof_in, PI), Vector3(1.3, 2.3, 0.3), Vector3(x, 0.3 + 1.15, z + d * 0.5 + 0.1))
	add_child(up)
	# nástavba schodiště na střeše – dveřmi zpátky dolů
	RoofExit.build(self, _static, _deco, Vector3(x, roof_y, z - 3.6), 0.0, func(p): _teleport(p, door_out, PI))
	# kotvicí body nad sloupci oken
	for i in 2:
		var a := RopeAnchor.new()
		a.anchor_id = "byty_%d" % (i + 1)
		a.position = Vector3(x + (-4.5 if i == 0 else 4.5), roof_y, z + d * 0.5 - 0.6)
		a.wall_out = 0.6
		a.edge_h = 0.95
		a.roof_y = ORIGIN.y + roof_y
		a.ground_y = 0.0
		add_child(a)
		anchors.append(a)
	_exclude_rect(x - w * 0.5 - 2.0, z - d * 0.5 - 2.0, x + w * 0.5 + 2.0, -6.6)
	_map_rect(x, z, w, d, Color(0.85, 0.75, 0.55), "Bytový dům")
	var cl: Array = CLIENTS["pr_byty_prizemi"]
	ContractManager.register_client({
		"id": "pr_byty_prizemi", "name": cl[0], "who": cl[1], "area": AREA_ID, "building": cl[2],
		"pos": Vector2(ORIGIN.x + x + 3.0, z + d * 0.5 + 2.0),
		"front": ["pr_byty_prizemi_w1", "pr_byty_prizemi_w2", "pr_byty_prizemi_w3", "pr_byty_prizemi_w4"],
		"all": ["pr_byty_prizemi_w1", "pr_byty_prizemi_w2", "pr_byty_prizemi_w3", "pr_byty_prizemi_w4"],
		"tree": false, "pay": 1.15,
	})


## Základní škola – tři podlaží, pásová okna, kotvy na střeše.
func _school() -> void:
	var x := 14.0
	var w := 22.0
	var d := 12.0
	var z := 6.6 + 8.0 + d * 0.5
	var st := 3.2
	var floors := 3
	var cols := [-8.0, -4.0, 0.0, 4.0, 8.0]
	var ops := []
	for f in floors:
		for k in cols.size():
			var o := {"side": "front", "u": cols[k], "width": 2.6, "height": 1.6, "sill": f * st + 0.9, "cross": false}
			if f > 0:
				o["id"] = "pr_skola_p%d_%d" % [f, k + 1]
			ops.append(o)
		for u: float in [-6.0, 0.0, 6.0]:
			ops.append({"side": "back", "u": u, "width": 2.6, "height": 1.6, "sill": f * st + 0.9})
		ops.append({"side": "left", "u": 0.0, "width": 2.0, "height": 1.6, "sill": f * st + 0.9})
	ops.append({"side": "right", "type": "door", "u": 0.0, "width": 1.6, "height": 2.5, "sill": 0.0, "color": Color(0.2, 0.45, 0.65)})
	ops.append({"side": "right", "u": 0.0, "width": 1.6, "height": 1.6, "sill": st + 0.9})
	ops.append({"side": "right", "u": 0.0, "width": 1.6, "height": 1.6, "sill": 2.0 * st + 0.9})
	var fh := 0.3
	var wh := st * floors + 0.2
	HouseBuilder.build(self, {
		"name": "School", "position": Vector3(x, 0, z), "rotation_y": PI, "width": w, "depth": d,
		"found_h": fh, "wall_h": wh, "roof": "flat", "parapet_h": 0.95, "seed": 580,
		"wall_color": Color(0.97, 0.94, 0.88), "roof_color": Color(0.36, 0.37, 0.39), "trim_color": Color(0.2, 0.45, 0.65),
		"bands": [st, st * 2.0], "band_color": Color(0.95, 0.65, 0.3), "blinds": true, "curtain_color": Color(0.9, 0.9, 0.86),
		"room_color": Color(0.75, 0.72, 0.62), "dirt_profile": "skola_okna", "openings": ops,
		"interior": true, "levels": [0.0, st, st * 2.0], "styles": ["office", "classroom", "classroom"],
		"interior_color": Color(0.96, 0.95, 0.9), "floor_color": Color(0.55, 0.6, 0.55),
	})
	var roof_y := fh + wh + 0.25
	_label("ZÁKLADNÍ ŠKOLA JAVOROV", Vector3(x, st * 3.0 - 0.1, z - d * 0.5 - 0.14), 64, Color(0.2, 0.45, 0.65), Color(1, 1, 1), PI)
	# hřiště za plotem
	_strip(_deco, x - 13.0, 7.2, x + 13.0, 7.6 + 2.0, 0.03, Color(0.6, 0.6, 0.6))
	# vstup na střechu: boční dveře (vpravo z ulice = -X lokálně otočené budovy)
	var side_x := x - w * 0.5 - 1.0
	var door_out := Vector3(side_x, 0.05, z)
	var roof_in := Vector3(x - w * 0.5 + 2.2, roof_y + 0.05, z)
	var up := SimpleInteractable.create("[E] Vyjít schodištěm na střechu školy", func(p): _to_roof(p, roof_in, -PI * 0.5), Vector3(0.3, 2.5, 1.6), Vector3(x - w * 0.5 - 0.1, 0.3 + 1.25, z))
	add_child(up)
	# nástavba schodiště na střeše (dveře míří k místu, kam hráč vyjde)
	RoofExit.build(self, _static, _deco, Vector3(x - w * 0.5 + 1.3, roof_y, z + 2.4), PI * 0.5, func(p): _teleport(p, door_out, PI * 0.5))
	# kotva nad každým sloupcem oken (široká okna 2,6 m – z kotvy mezi nimi by se nedalo dosáhnout na okraj)
	for i in 5:
		var a := RopeAnchor.new()
		a.anchor_id = "skola_%d" % (i + 1)
		# budova je otočená čelem do ulice (-Z), kotva míří ven = -Z
		a.position = Vector3(x + [-8.0, -4.0, 0.0, 4.0, 8.0][i], roof_y, z - d * 0.5 + 0.6)
		a.rotation.y = PI
		a.wall_out = 0.6
		a.edge_h = 0.95
		a.roof_y = roof_y
		a.ground_y = 0.0
		add_child(a)
		anchors.append(a)
	_exclude_rect(x - w * 0.5 - 2.5, 6.6, x + w * 0.5 + 2.5, z + d * 0.5 + 2.0)
	_map_rect(x, z, w, d, Color(0.75, 0.82, 0.9), "Škola")


## Chodníčky z dlažby od všech vstupních dveří k chodníku podél ulice
## (dveře do boku domu dostanou cestičku do L: kousek od dveří a pak k ulici).
func _door_paths() -> void:
	var b := MeshBuilder.new(590)
	var pave := Color(0.76, 0.73, 0.68)
	for c in get_children():
		if not c.has_meta("doors"):
			continue
		for dr: Dictionary in c.get_meta("doors"):
			var p: Vector3 = dr["pos"]
			var n: Vector3 = dr["normal"]
			var walk := 6.6 if p.z > 0.0 else -6.6
			var hw := maxf(0.6, float(dr["width"]) * 0.5 + 0.1)
			if absf(n.z) > 0.7:
				if signf(n.z) == signf(p.z):
					continue   # dveře do zahrady (od ulice) – bez cestičky
				_path_rect(b, p.x - hw, p.z, p.x + hw, walk, pave)
			else:
				var out := p + n * 1.4
				_path_rect(b, p.x, p.z - hw, out.x, p.z + hw, pave)
				_path_rect(b, out.x - hw, p.z, out.x + hw, walk, pave)
	b.to_instance(self, "DoorPaths", false)


func _path_rect(b: MeshBuilder, xa: float, za: float, xb: float, zb: float, color: Color) -> void:
	var x0 := minf(xa, xb)
	var x1 := maxf(xa, xb)
	var z0 := minf(za, zb)
	var z1 := maxf(za, zb)
	if x1 - x0 < 0.05 or z1 - z0 < 0.05:
		return
	_strip(b, x0, z0, x1, z1, 0.022, color, 0.03)
	# spáry mezi dlaždicemi
	var along_z := z1 - z0 > x1 - x0
	var n := int((z1 - z0 if along_z else x1 - x0) / 0.6)
	for k in range(1, n):
		if along_z:
			_strip(b, x0, z0 + k * 0.6 - 0.015, x1, z0 + k * 0.6 + 0.015, 0.028, color.darkened(0.18), 0.005)
		else:
			_strip(b, x0 + k * 0.6 - 0.015, z0, x0 + k * 0.6 + 0.015, z1, 0.028, color.darkened(0.18), 0.005)
	_exclude_rect(x0 - 0.3, z0 - 0.3, x1 + 0.3, z1 + 0.3)


## Parkoviště u ulice: asfalt, bílé čáry stání kolmo k ulici a pár aut (s kolizí).
## `side` = +1 jižně od ulice, -1 severně.
func _parking(xa: float, za: float, xb: float, zb: float, side: float) -> void:
	var b := MeshBuilder.new(int(absf(xa) * 13.0 + 591.0))
	var x0 := minf(xa, xb)
	var x1 := maxf(xa, xb)
	var z0 := minf(za, zb)
	var z1 := maxf(za, zb)
	_strip(b, x0, z0, x1, z1, 0.035, Color(0.33, 0.34, 0.36), 0.04)
	# obrubník kolem (kromě strany k ulici)
	var curb := Color(0.8, 0.79, 0.76)
	var far_z := z1 if side > 0 else z0
	_strip(b, x0 - 0.15, far_z - 0.08, x1 + 0.15, far_z + 0.08, 0.1, curb, 0.12)
	for ex: float in [x0, x1]:
		_strip(b, ex - 0.08, z0, ex + 0.08, z1, 0.1, curb, 0.12)
	# stání: řada u vzdálené strany, šířka 2,6 m, hloubka 5 m
	var spot_w := 2.6
	var n := int((x1 - x0 - 0.4) / spot_w)
	var sx0 := (x0 + x1) * 0.5 - n * spot_w * 0.5
	var zs0 := far_z - side * 5.0
	for k in n + 1:
		var lx := sx0 + k * spot_w
		_strip(b, lx - 0.06, minf(zs0, far_z), lx + 0.06, maxf(zs0, far_z), 0.041, Color(0.95, 0.95, 0.92), 0.005)
	var cols := [Color(0.75, 0.2, 0.18), Color(0.85, 0.85, 0.88), Color(0.2, 0.32, 0.55), Color(0.2, 0.2, 0.22), Color(0.4, 0.55, 0.4)]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(xa) * 17.0)
	for k in n:
		if rng.randf() < 0.4:
			continue
		var cx := sx0 + (k + 0.5) * spot_w
		var cz := far_z - side * 2.5
		Props.car(b, Transform3D(Basis(Vector3.UP, 0.0 if side > 0 else PI), Vector3(cx, 0, cz)), cols[rng.randi() % cols.size()])
		_col_box(Vector3(1.8, 1.4, 4.0), Transform3D(Basis.IDENTITY, Vector3(cx, 0.7, cz)))
	b.add_box(Vector3(0.08, 2.2, 0.08), Vector3(x0 + 0.4, 1.1, z0 + (z1 - z0) * 0.5), Color(0.5, 0.5, 0.52))
	b.add_box(Vector3(0.05, 0.6, 0.6), Vector3(x0 + 0.4, 2.0, z0 + (z1 - z0) * 0.5), Color(0.2, 0.4, 0.75))
	b.to_instance(self, "Parking")
	_label("P", Vector3(x0 + 0.44, 2.0, z0 + (z1 - z0) * 0.5), 60, Color(1, 1, 1), Color(0.2, 0.4, 0.75), PI * 0.5)
	_exclude_rect(x0 - 0.5, z0 - 0.5, x1 + 0.5, z1 + 0.5)
	_map_rect((x0 + x1) * 0.5, (z0 + z1) * 0.5, x1 - x0, z1 - z0, Color(0.5, 0.5, 0.53), "P")


func _to_roof(player, pos: Vector3, yaw: float) -> void:
	_teleport(player, pos, yaw)
	Events.toast("Jsi na střeše. Dolů vedou dveře nástavby se šipkou ↓ SCHODIŠTĚ.", "info")


func _teleport(player, pos: Vector3, yaw: float) -> void:
	player.global_position = gpos(pos)
	player.yaw = yaw
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player._safe_hist.clear()
	player._air_top = player.global_position.y
	Audio.play("step", -6.0, 0.8)


# ------------------------------------------------------------------ zeleň a okolí

func _greenery() -> void:
	# stromořadí podél chodníků
	var trees := [[], [], [], []]
	for x in range(-100, 101, 14):
		for s: float in [-1.0, 1.0]:
			var p := Vector2(x + s * 3.5, s * 7.3)
			if _excluded(p, 0.3):
				continue
			trees[0 if (x / 14) % 2 == 0 else 2].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.85, 1.1)), Vector3(p.x, 0, p.y)))
			_tree_collider(Vector3(p.x, 0, p.y))
	# zahrady a okraj čtvrti
	var area := Rect2(-115, -62, 230, 124)
	var placed := 0
	var tries := 0
	while placed < 120 and tries < 4000:
		tries += 1
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if _excluded(p, 2.5) or absf(p.y) < 9.0:
			continue
		var kind := _rng.randi() % 4
		trees[kind].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.3)), Vector3(p.x, 0, p.y)))
		_exclude.append(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)))
		_tree_collider(Vector3(p.x, 0, p.y))
		placed += 1
	for k in 4:
		if not trees[k].is_empty():
			Nature.multimesh(self, Nature.tree_mesh(k), trees[k], true, [], 0)
	for kind in 3:
		var xfs := []
		for i in 40:
			var p := Vector2(_rng.randf_range(-100, 100), _rng.randf_range(-45, 45))
			if _excluded(p, 0.8) or absf(p.y) < 7.5:
				continue
			xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.3)), Vector3(p.x, 0, p.y)))
		Nature.multimesh(self, Nature.bush_mesh(kind), xfs, true, [], 0)
	var grass := []
	for i in 1800:
		var p := Vector2(_rng.randf_range(-100, 100), _rng.randf_range(-45, 45))
		if _excluded(p, 0.2) or absf(p.y) < 7.0:
			continue
		grass.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.3)), Vector3(p.x, 0, p.y)))
	Nature.multimesh(self, Nature.grass_mesh(), grass, false).material_override = Nature.grass_mat()


func _tree_collider(p: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.25
	cyl.height = 3.0
	cs.shape = cyl
	cs.position = p + Vector3(0, 1.5, 0)
	_static.add_child(cs)


func _hills() -> void:
	var b := MeshBuilder.new(599)
	var greens := [Color(0.38, 0.58, 0.32), Color(0.32, 0.52, 0.3), Color(0.45, 0.62, 0.35), Color(0.28, 0.45, 0.32)]
	for k in 30:
		var a := k * TAU / 30.0 + _rng.randf_range(-0.05, 0.05)
		var dist := _rng.randf_range(190.0, 270.0)
		var p := Vector3(cos(a) * dist * 1.2, -6.0, sin(a) * dist)
		var s := Vector3(_rng.randf_range(90, 150), _rng.randf_range(30, 65), _rng.randf_range(70, 110))
		b.add("sphere_hi", Transform3D(Basis(Vector3.UP, a).scaled(s), p), greens[k % greens.size()], 0.06)
	# vzdálené město na obzoru (jednoduché kvádry)
	for k in 18:
		var a := -0.6 + k * 0.07
		var dist := 300.0 + _rng.randf_range(0, 40)
		var hgt := _rng.randf_range(18, 55)
		b.add_box(Vector3(_rng.randf_range(14, 26), hgt, _rng.randf_range(14, 26)), Vector3(cos(a) * dist, hgt * 0.5 - 2.0, sin(a) * dist), Color(0.62, 0.68, 0.74))
	var mi := b.to_instance(self, "Hills", false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _bounds() -> void:
	for d in [[Vector3(0, 5, -66), Vector3(250, 10, 2)], [Vector3(0, 5, 66), Vector3(250, 10, 2)], [Vector3(-122, 5, 0), Vector3(2, 10, 134)], [Vector3(122, 5, 0), Vector3(2, 10, 134)]]:
		_col_box(d[1], Transform3D(Basis.IDENTITY, d[0]))

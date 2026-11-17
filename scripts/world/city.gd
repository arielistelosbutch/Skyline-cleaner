class_name City
extends Node3D
## Oblast III – Město Brodec (Etapa 4). Leží daleko od ostatních oblastí (posun ORIGIN),
## jezdí se sem autobusem z návsi i z Předměstí. Široká třída s tramvají, kancelářská
## budova Meridian (8 podlaží), Hotel Grand (6 podlaží), obchodní dům a činžovní dům.
## Výškové budovy mají na střeše závěsnou plošinu, obchodní a činžovní dům kotvy pro lano.
## Lokální souřadnice: třída vede podél X v pásu z ∈ [-6, 6], chodníky do |z| = 9,5.

const ORIGIN := Vector3(-2200, 0, 0)
const AREA_ID := "mesto"
const AREA_NAME := "Oblast III – Město · Brodec"
const UNLOCK_LEVEL := 8
const GROUND_SHADER := preload("res://shaders/ground.gdshader")

## Kde hráč vystoupí z autobusu (lokálně) a kam se postaví žebříky, které jedou s ním.
const ARRIVE := Vector3(-4.0, 0.0, -7.6)
const ARRIVE_YAW := -PI * 0.5
## y = výška chodníku (chodník je jen vizuálně o 8 cm výš než kolize země).
const LADDER_SPOT := Vector3(-14.0, 0.08, -8.6)
const WALK_Z := 9.5

## Zákazníci ve městě (poptávky): [jméno do titulku, kdo píše, typ budovy].
const CLIENTS := {
	"me_meridian_lobby": ["Meridian – vstupní hala", "Recepce budovy Meridian", "Kancelářská budova"],
	"me_hotel_lobby": ["Hotel Grand – přízemí", "Paní Říhová, provozní hotelu", "Hotel"],
	"me_cinzak": ["Činžovní dům Palackého 18", "Společenství vlastníků", "Činžovní dům (5 podlaží)"],
	"me_od_vylohy": ["Obchodní dům – výlohy", "Vedoucí obchodního domu", "Obchodní dům"],
}

var _static: StaticBody3D
var _deco: MeshBuilder
var _rng := RandomNumberGenerator.new()
var _exclude: Array[Rect2] = []
var anchors: Array[RopeAnchor] = []
var platforms: Array[SuspendedPlatform] = []
## Místa u chodníku, kde nesmí stát strom (vchody, pobočka obchodu): Vector2(x, strana z).
var _clear: Array[Vector2] = [Vector2(6.0, -1.0), Vector2(-30.0, 1.0)]


func _ready() -> void:
	_rng.seed = 4242
	position = ORIGIN
	_static = StaticBody3D.new()
	_static.name = "StaticCollision"
	add_child(_static)
	_deco = MeshBuilder.new(801)
	WorldMap.add_area(AREA_ID, AREA_NAME, Rect2(ORIGIN.x - 115, -62, 230, 124))

	_ground()
	_street()
	_office_meridian()
	_hotel()
	_department_store()
	_tenement()
	_square()
	_filler_blocks()
	_greenery()
	_skyline()
	_bounds()
	_deco.to_instance(self, "CityDecor")


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


func _water_point(pos: Vector3) -> void:
	var b := MeshBuilder.new(int(absf(pos.x) * 7.0 + 5.0))
	Props.water_barrel(b, pos)
	b.to_instance(self, "Water")
	var it := SimpleInteractable.create("[E] Vymáchat nástroj a doplnit rozprašovač (sud s vodou)", func(p): p.cleaning.rinse(), Vector3(0.65, 0.95, 0.65), pos + Vector3(0, 0.47, 0))
	it.add_to_group("water_source")
	add_child(it)


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


## Okna jednoho patra (sloupce u) – volitelně s id.
func _floor_windows(side: String, us: Array, f: int, st: float, w: float, h: float, sill: float, prefix: String, extra: Dictionary = {}) -> Array:
	var out := []
	for k in us.size():
		var o := {"side": side, "u": us[k], "width": w, "height": h, "sill": f * st + sill}
		if prefix != "":
			o["id"] = "%s_p%d_%d" % [prefix, f, k + 1]
		for key in extra:
			o[key] = extra[key]
		out.append(o)
	return out


## Vstup na střechu (zjednodušené schodiště) – dveře v přízemí a výlez na střeše.
func _roof_access(door_pos: Vector3, door_size: Vector3, door_out: Vector3, out_yaw: float, roof_in: Vector3, in_yaw: float, hatch: Vector3, name_txt: String) -> void:
	_clear.append(Vector2(door_pos.x, signf(door_pos.z)))
	var up := SimpleInteractable.create("[E] Vyjít schodištěm na střechu (%s)" % name_txt, func(p): _to_roof(p, roof_in, in_yaw), door_size, door_pos)
	add_child(up)
	# nástavba schodiště, dveřmi k místu, kam hráč na střeše vyjde
	var dir := roof_in - hatch
	RoofExit.build(self, _static, _deco, hatch, atan2(dir.x, dir.z), func(p): _teleport(p, door_out, out_yaw))


func _register(cid: String, pos: Vector2, front: Array, all: Array, pay: float, tree: bool = false) -> void:
	var cl: Array = CLIENTS[cid]
	ContractManager.register_client({
		"id": cid, "name": cl[0], "who": cl[1], "area": AREA_ID, "building": cl[2],
		"pos": Vector2(ORIGIN.x + pos.x, pos.y), "front": front, "all": all, "tree": tree, "pay": pay,
	})


# ------------------------------------------------------------------ terén a třída

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
	# vlastní kolize země (WorldBoundaryShape3D z vesnice sem v Jolt fyzice nesahá)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(600, 2, 600)
	cs.shape = bs
	cs.position = Vector3(0, -1, 0)
	_static.add_child(cs)
	# zpevněná plocha centra (dlažba místo trávy)
	var b := MeshBuilder.new(802)
	_strip(b, -112, -60, 112, 60, 0.02, Color(0.62, 0.61, 0.58), 0.02)
	b.to_instance(self, "Pavement")


func _street() -> void:
	var b := MeshBuilder.new(811)
	var asphalt := Color(0.29, 0.3, 0.32)
	var walk := Color(0.72, 0.71, 0.68)
	var curb := Color(0.82, 0.81, 0.78)
	_strip(b, -115, -6, 115, 6, 0.04, asphalt)
	# tramvajový pás uprostřed
	_strip(b, -115, -1.5, 115, 1.5, 0.045, Color(0.42, 0.4, 0.36), 0.01)
	for s: float in [-0.72, 0.72]:
		_strip(b, -115, s - 0.04, 115, s + 0.04, 0.06, Color(0.55, 0.56, 0.58), 0.02)
	for x in range(-112, 112, 6):
		for s: float in [-3.75, 3.75]:
			_strip(b, x, s - 0.07, x + 3.0, s + 0.07, 0.046, Color(0.95, 0.95, 0.92), 0.01)
	for s: float in [-1.0, 1.0]:
		_strip(b, -115, s * 6.0, 115, s * 6.2, 0.09, curb, 0.1)
		_strip(b, -112, s * 6.2, 112, s * WALK_Z, 0.08, walk, 0.08)
	_exclude_rect(-120, -WALK_Z - 0.5, 120, WALK_Z + 0.5)
	WorldMap.add_rect(Rect2(ORIGIN.x - 115, -6, 230, 12), Color(0.42, 0.43, 0.47))
	# přechody
	for px: float in [-48.0, 12.0, 48.0]:
		for k in 10:
			_strip(b, px - 2.0, -5.8 + k * 1.2, px + 2.0, -5.3 + k * 1.2, 0.053, Color(0.96, 0.96, 0.94), 0.01)
	# lampy a trolejové sloupy
	var lamps := []
	for x: float in [-96.0, -72.0, -48.0, -24.0, 0.0, 24.0, 48.0, 72.0, 96.0]:
		Props.lamp_post(b, Vector3(x, 0, -6.9), -PI * 0.5, lamps)
		Props.lamp_post(b, Vector3(x + 12.0, 0, 6.9), PI * 0.5, lamps)
	Props.lamp_lights(self, lamps)
	# zaparkovaná auta
	var car_cols := [Color(0.8, 0.82, 0.85), Color(0.2, 0.3, 0.5), Color(0.7, 0.2, 0.18), Color(0.15, 0.15, 0.17), Color(0.85, 0.7, 0.3), Color(0.3, 0.5, 0.35)]
	var cars := [[-70.0, 4.9, 0.0], [-58.0, -4.9, PI], [-19.0, 4.9, 0.0], [34.0, -4.9, PI], [61.0, 4.9, 0.0], [84.0, -4.9, PI]]
	for i in cars.size():
		var c: Array = cars[i]
		Props.car(b, Transform3D(Basis(Vector3.UP, PI * 0.5 + c[2]), Vector3(c[0], 0, c[1])), car_cols[i % car_cols.size()])
		_col_box(Vector3(4.0, 1.4, 1.8), Transform3D(Basis.IDENTITY, Vector3(c[0], 0.7, c[1])))
	# autobusová zastávka (sever) – dva jízdní řády
	var sx := -6.0
	b.add_box(Vector3(4.4, 0.1, 1.6), Vector3(sx, 2.45, -8.4), Color(0.2, 0.3, 0.45))
	for px: float in [sx - 2.1, sx + 2.1]:
		b.add_box(Vector3(0.08, 2.45, 0.08), Vector3(px, 1.22, -9.0), Color(0.2, 0.3, 0.45))
	b.add_box(Vector3(4.3, 2.2, 0.04), Vector3(sx, 1.2, -9.1), Color(0.65, 0.8, 0.85), Basis.IDENTITY, 0.0)
	Props.bench(b, Transform3D(Basis.IDENTITY, Vector3(sx, 0, -8.7)))
	_col_box(Vector3(4.4, 2.4, 0.2), Transform3D(Basis.IDENTITY, Vector3(sx, 1.2, -9.1)))
	for k in 2:
		var px: float = sx + 3.0 + k * 1.2
		b.add_box(Vector3(0.08, 2.2, 0.08), Vector3(px, 1.1, -7.0), Color(0.5, 0.5, 0.52))
		b.add_box(Vector3(0.5, 0.65, 0.05), Vector3(px, 1.7, -6.95), Color(0.95, 0.85, 0.2))
	b.to_instance(self, "Street")
	# projíždějící doprava (Etapa 7): pravostranný provoz, tramvaj staví u zastávky
	Traffic.create(self, [
		{"z": 2.75, "dir": 1.0, "x0": -118.0, "x1": 118.0, "kind": "car", "count": 4, "speed": 9.0},
		{"z": -2.75, "dir": -1.0, "x0": -118.0, "x1": 118.0, "kind": "car", "count": 4, "speed": 8.5},
		{"z": 0.0, "dir": 1.0, "x0": -130.0, "x1": 130.0, "kind": "tram", "count": 1, "speed": 7.0, "stop_x": 26.0},
	], 707)
	_label("Brodec, Hlavní třída", Vector3(sx, 2.7, -7.58), 40)
	var to_village := SimpleInteractable.create("[E] Autobus do Lipové Lhoty (náves)", func(p): get_tree().call_group("world", "bus_travel", "venkov", p), Vector3(0.6, 2.2, 0.4), Vector3(sx + 3.0, 1.1, -7.0))
	add_child(to_village)
	var to_suburb := SimpleInteractable.create("[E] Autobus do Javorova (Předměstí)", func(p): get_tree().call_group("world", "bus_travel", Suburb.AREA_ID, p), Vector3(0.6, 2.2, 0.4), Vector3(sx + 4.2, 1.1, -7.0))
	add_child(to_suburb)
	var to_metro := SimpleInteractable.create("[E] Autobus do Velkoměsta Horizont (zakázky od úrovně %d)" % Metropolis.UNLOCK_LEVEL, func(p): get_tree().call_group("world", "bus_travel", Metropolis.AREA_ID, p), Vector3(0.6, 2.2, 0.4), Vector3(sx + 5.4, 1.1, -7.0))
	add_child(to_metro)
	var mb := MeshBuilder.new(812)
	mb.add_box(Vector3(0.08, 2.2, 0.08), Vector3(sx + 5.4, 1.1, -7.0), Color(0.5, 0.5, 0.52))
	mb.add_box(Vector3(0.5, 0.65, 0.05), Vector3(sx + 5.4, 1.7, -6.95), Color(0.2, 0.45, 0.75))
	mb.to_instance(self, "BusPostMetro")
	_label("Horizont", Vector3(sx + 5.4, 2.15, -6.9), 22, Color(0.1, 0.1, 0.1), Color(1, 1, 1))
	_label("Lipová Lhota", Vector3(sx + 3.0, 2.15, -6.9), 22, Color(0.1, 0.1, 0.1), Color(1, 1, 1))
	_label("Javorov", Vector3(sx + 4.2, 2.15, -6.9), 22, Color(0.1, 0.1, 0.1), Color(1, 1, 1))
	WorldMap.add_marker("bus_me", Vector2(ORIGIN.x + sx, -9.5), "Autobus – Lipová Lhota, Javorov", Color(0.95, 0.8, 0.2))
	_exclude_rect(sx - 3.0, -10.0, sx + 6.5, -6.5)
	# pobočka obchodu s vybavením kousek od zastávky
	ShopKiosk.build(self, Vector3(6.0, 0, -11.4), 0.0, "Úklid & Výšky – Brodec", Vector2(ORIGIN.x + 6.0, -11.4), 881)
	_exclude_rect(3.0, -13.5, 9.0, -9.5)
	_exclude_rect(LADDER_SPOT.x - 7.0, LADDER_SPOT.z - 1.5, LADDER_SPOT.x + 1.0, LADDER_SPOT.z + 1.0)
	# sudy s vodou u budov se zakázkami
	for wp: Vector3 in [Vector3(-21.0, 0, -8.8), Vector3(15.0, 0, -8.8), Vector3(40.0, 0, 8.8), Vector3(-47.0, 0, 8.8)]:
		_water_point(wp)


# ------------------------------------------------------------------ budovy

## Kancelářská budova Meridian – 8 podlaží, pásová okna, závěsná plošina na střeše.
func _office_meridian() -> void:
	var x := -34.0
	var w := 20.0
	var d := 14.0
	var z := -WALK_Z - 0.6 - d * 0.5
	var st := 3.4
	var floors := 8
	# sloupce oken nechávají uprostřed místo pro vchod (okno přes dveře rozbíjelo zeď)
	var cols := [-7.7, -2.9, 2.9, 7.7]
	var ops := [{"side": "front", "type": "door", "u": 0.0, "width": 1.6, "height": 2.6, "sill": 0.0, "color": Color(0.2, 0.25, 0.3)}]
	for k in cols.size():
		ops.append({"side": "front", "u": cols[k], "width": 3.6, "height": 2.8, "sill": 0.2, "id": "me_meridian_lobby_w%d" % (k + 1), "cross": false})
	for f in range(1, floors):
		ops.append_array(_floor_windows("front", cols, f, st, 3.6, 2.2, 0.6, "me_meridian", {"cross": false}))
	for f in floors:
		for u: float in [-7.5, -2.5, 2.5, 7.5]:
			ops.append({"side": "back", "u": u, "width": 4.2, "height": 2.2, "sill": f * st + 0.6, "cross": false})
		for side in ["left", "right"]:
			for u: float in [-3.5, 3.5]:
				ops.append({"side": side, "u": u, "width": 3.6, "height": 2.2, "sill": f * st + 0.6, "cross": false})
	var bands := []
	var levels := []
	var styles := []
	for f in floors:
		levels.append(f * st)
		styles.append("lobby" if f == 0 else "openspace")
		if f > 0:
			bands.append(f * st)
	var fh := 0.3
	var wh := st * floors + 0.3
	HouseBuilder.build(self, {
		"name": "OfficeMeridian", "position": Vector3(x, 0, z), "width": w, "depth": d,
		"found_h": fh, "wall_h": wh, "roof": "flat", "parapet_h": 1.0, "seed": 820,
		"wall_color": Color(0.36, 0.43, 0.5), "roof_color": Color(0.33, 0.34, 0.36), "trim_color": Color(0.85, 0.87, 0.9),
		"bands": bands, "band_color": Color(0.8, 0.82, 0.85), "blinds": true, "curtain_color": Color(0.85, 0.86, 0.86),
		"room_color": Color(0.7, 0.72, 0.74), "dirt_profile": "mesto_smog", "openings": ops,
		"interior": true, "levels": levels, "styles": styles,
		"interior_color": Color(0.94, 0.95, 0.96), "floor_color": Color(0.5, 0.52, 0.55),
	})
	var roof_y := fh + wh + 0.25
	_label("MERIDIAN", Vector3(x, roof_y + 1.6, z + d * 0.5 - 0.3), 160, Color(0.95, 0.97, 1.0), Color(0.15, 0.2, 0.3))
	# markýza nad vchodem
	_deco.add_box(Vector3(4.0, 0.15, 2.2), Vector3(x, 3.0, z + d * 0.5 + 1.1), Color(0.85, 0.87, 0.9))
	_roof_access(Vector3(x, 1.6, z + d * 0.5 + 0.1), Vector3(1.6, 2.6, 0.3), Vector3(x, 0.05, z + d * 0.5 + 1.2), 0.0,
		Vector3(x - 5.0, roof_y + 0.05, z - 2.0), PI, Vector3(x - 5.0, roof_y, z - 4.2), "závěsná plošina")
	var pl := SuspendedPlatform.new()
	pl.anchor_id = "meridian"
	pl.position = Vector3(x, roof_y, z + d * 0.5 - 0.7)
	pl.wall_out = 0.7
	pl.edge_h = 1.0
	pl.roof_y = roof_y
	pl.ground_y = 0.0
	pl.rail_half = w * 0.5 - 0.6
	add_child(pl)
	platforms.append(pl)
	anchors.append(pl)
	_exclude_rect(x - w * 0.5 - 1.5, z - d * 0.5 - 1.5, x + w * 0.5 + 1.5, -WALK_Z)
	_map_rect(x, z, w, d, Color(0.55, 0.65, 0.78), "Meridian")
	var lobby := ["me_meridian_lobby_w1", "me_meridian_lobby_w2", "me_meridian_lobby_w3", "me_meridian_lobby_w4"]
	_register("me_meridian_lobby", Vector2(x + 4.0, -WALK_Z + 0.5), lobby, lobby, 1.35)


## Hotel Grand – 6 podlaží, okna pokojů, prosklená vstupní hala, plošina na střeše.
func _hotel() -> void:
	var x := 30.0
	var w := 24.0
	var d := 12.0
	var z := -WALK_Z - 0.6 - d * 0.5
	var st := 3.1
	var floors := 6
	var cols := [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]
	var ops := [{"side": "front", "type": "door", "u": 0.0, "width": 2.4, "height": 2.6, "sill": 0.0, "color": Color(0.35, 0.25, 0.15)}]
	var lobby_cols := [-10.0, -5.5, 5.5, 10.0]
	for k in lobby_cols.size():
		ops.append({"side": "front", "u": lobby_cols[k], "width": 3.2, "height": 2.4, "sill": 0.3, "id": "me_hotel_lobby_w%d" % (k + 1), "cross": false})
	for f in range(1, floors):
		ops.append_array(_floor_windows("front", cols, f, st, 1.5, 1.7, 0.8, "me_hotel", {"shutters": false}))
	for f in floors:
		for u: float in [-8.0, -3.0, 3.0, 8.0]:
			ops.append({"side": "back", "u": u, "width": 1.4, "height": 1.6, "sill": f * st + 0.8})
		for side in ["left", "right"]:
			ops.append({"side": side, "u": 0.0, "width": 1.4, "height": 1.6, "sill": f * st + 0.8})
	var bands := []
	var levels := []
	var styles := []
	for f in floors:
		levels.append(f * st)
		styles.append("lobby" if f == 0 else "hotel")
		if f > 0:
			bands.append(f * st)
	var fh := 0.3
	var wh := st * floors + 0.3
	HouseBuilder.build(self, {
		"name": "HotelGrand", "position": Vector3(x, 0, z), "width": w, "depth": d,
		"found_h": fh, "wall_h": wh, "roof": "flat", "parapet_h": 1.0, "seed": 830,
		"wall_color": Color(0.93, 0.87, 0.76), "roof_color": Color(0.35, 0.33, 0.32), "trim_color": Color(0.55, 0.38, 0.22),
		"bands": bands, "band_color": Color(0.82, 0.74, 0.6), "curtain_color": Color(0.95, 0.88, 0.75),
		"room_color": Color(0.65, 0.5, 0.38), "dirt_profile": "hotel_okna", "openings": ops,
		"interior": true, "levels": levels, "styles": styles,
		"interior_color": Color(0.97, 0.93, 0.86), "floor_color": Color(0.55, 0.32, 0.25),
	})
	var roof_y := fh + wh + 0.25
	_label("HOTEL GRAND", Vector3(x, 3.4, z + d * 0.5 + 0.06), 120, Color(1.0, 0.85, 0.45), Color(0.3, 0.2, 0.1))
	# stříška nad vchodem a květináče
	_deco.add_box(Vector3(5.0, 0.18, 2.6), Vector3(x, 2.95, z + d * 0.5 + 1.3), Color(0.55, 0.38, 0.22))
	for s: float in [-1.0, 1.0]:
		_deco.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.08, 2.9, 0.08)), Vector3(x + s * 2.3, 1.45, z + d * 0.5 + 2.4)), Color(0.75, 0.6, 0.3))
		_deco.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.7, 0.6, 0.7)), Vector3(x + s * 3.4, 0.3, z + d * 0.5 + 0.9)), Color(0.35, 0.35, 0.37))
		_deco.add("sphere", Transform3D(Basis.from_scale(Vector3(0.9, 1.1, 0.9)), Vector3(x + s * 3.4, 1.1, z + d * 0.5 + 0.9)), Color(0.3, 0.55, 0.3), 0.06)
	_roof_access(Vector3(x, 1.6, z + d * 0.5 + 0.1), Vector3(2.4, 2.6, 0.3), Vector3(x, 0.05, z + d * 0.5 + 1.4), 0.0,
		Vector3(x + 7.0, roof_y + 0.05, z - 1.5), PI, Vector3(x + 7.0, roof_y, z - 3.6), "závěsná plošina")
	var pl := SuspendedPlatform.new()
	pl.anchor_id = "hotel"
	pl.position = Vector3(x, roof_y, z + d * 0.5 - 0.7)
	pl.wall_out = 0.7
	pl.edge_h = 1.0
	pl.roof_y = roof_y
	pl.ground_y = 0.0
	pl.rail_half = w * 0.5 - 0.6
	add_child(pl)
	platforms.append(pl)
	anchors.append(pl)
	_exclude_rect(x - w * 0.5 - 1.5, z - d * 0.5 - 1.5, x + w * 0.5 + 1.5, -WALK_Z)
	_map_rect(x, z, w, d, Color(0.85, 0.72, 0.5), "Hotel Grand")
	var lobby := ["me_hotel_lobby_w1", "me_hotel_lobby_w2", "me_hotel_lobby_w3", "me_hotel_lobby_w4"]
	_register("me_hotel_lobby", Vector2(x - 4.0, -WALK_Z + 0.5), lobby, lobby, 1.3)


## Obchodní dům Brodec – 3 vysoká podlaží, velké výlohy, kotvy pro lano na střeše.
func _department_store() -> void:
	var x := -30.0
	var w := 26.0
	var d := 16.0
	var z := WALK_Z + 0.6 + d * 0.5
	var st := 4.0
	var floors := 3
	var ops := [{"side": "front", "type": "door", "u": 0.0, "width": 3.0, "height": 2.8, "sill": 0.0, "color": Color(0.25, 0.3, 0.35)}]
	var vcols := [-10.5, -5.5, 5.5, 10.5]
	for k in vcols.size():
		ops.append({"side": "front", "u": vcols[k], "width": 4.2, "height": 2.8, "sill": 0.3, "id": "me_od_vyloha_w%d" % (k + 1), "cross": false, "profile": "vyloha_mesto"})
	var cols := [-10.0, -5.0, 0.0, 5.0, 10.0]
	for f in range(1, floors):
		ops.append_array(_floor_windows("front", cols, f, st, 3.6, 1.6, 1.0, "me_od", {"cross": false}))
	for f in floors:
		for side in ["left", "right"]:
			ops.append({"side": side, "u": 0.0, "width": 3.0, "height": 1.6, "sill": f * st + 1.0, "cross": false})
	var fh := 0.3
	var wh := st * floors + 0.3
	HouseBuilder.build(self, {
		"name": "DepartmentStore", "position": Vector3(x, 0, z), "rotation_y": PI, "width": w, "depth": d,
		"found_h": fh, "wall_h": wh, "roof": "flat", "parapet_h": 0.95, "seed": 840,
		"wall_color": Color(0.88, 0.86, 0.82), "roof_color": Color(0.35, 0.35, 0.37), "trim_color": Color(0.2, 0.22, 0.25),
		"bands": [st, st * 2.0], "band_color": Color(0.75, 0.2, 0.2), "blinds": true, "curtain_color": Color(0.9, 0.9, 0.88),
		"room_color": Color(0.8, 0.78, 0.74), "dirt_profile": "mesto_smog", "openings": ops,
		"interior": true, "levels": [0.0, st, st * 2.0], "styles": ["store", "store", "openspace"],
		"interior_color": Color(0.97, 0.97, 0.96), "floor_color": Color(0.75, 0.74, 0.72),
	})
	var roof_y := fh + wh + 0.25
	_label("OBCHODNÍ DŮM BRODEC", Vector3(x, st * 2.0 + 3.4, z - d * 0.5 - 0.14), 110, Color(0.75, 0.15, 0.15), Color(1, 1, 1), PI)
	# vstup na střechu bočními dveřmi (vlevo z ulice = +X lokálně otočené budovy)
	var side_x := x + w * 0.5 + 1.0
	_roof_access(Vector3(x + w * 0.5 + 0.1, 1.55, z + 3.0), Vector3(0.3, 2.5, 1.6), Vector3(side_x, 0.05, z + 3.0), -PI * 0.5,
		Vector3(x + w * 0.5 - 2.2, roof_y + 0.05, z + 3.0), PI * 0.5, Vector3(x + w * 0.5 - 1.0, roof_y, z + 5.2), "kotvicí body")
	_deco.add_box(Vector3(0.1, 2.6, 1.6), Vector3(x + w * 0.5 + 0.05, 1.6, z + 3.0), Color(0.3, 0.32, 0.35))
	for i in cols.size():
		var a := RopeAnchor.new()
		a.anchor_id = "od_%d" % (i + 1)
		a.position = Vector3(x - float(cols[i]), roof_y, z - d * 0.5 + 0.6)
		a.rotation.y = PI
		a.wall_out = 0.6
		a.edge_h = 0.95
		a.roof_y = roof_y
		a.ground_y = 0.0
		add_child(a)
		anchors.append(a)
	_exclude_rect(x - w * 0.5 - 2.0, WALK_Z, x + w * 0.5 + 2.0, z + d * 0.5 + 1.5)
	_map_rect(x, z, w, d, Color(0.85, 0.55, 0.5), "Obchodní dům")
	var vy := ["me_od_vyloha_w1", "me_od_vyloha_w2", "me_od_vyloha_w3", "me_od_vyloha_w4"]
	_register("me_od_vylohy", Vector2(x + 3.0, WALK_Z - 0.5), vy, vy, 1.3)


## Činžovní dům Palackého 18 – 5 podlaží, klasická okna, lékárna v přízemí, kotvy.
func _tenement() -> void:
	var x := 28.0
	var w := 18.0
	var d := 11.0
	var z := WALK_Z + 0.6 + d * 0.5
	var st := 3.2
	var floors := 5
	var cols := [-6.0, -3.0, 0.0, 3.0, 6.0]
	var ops := [
		{"side": "front", "type": "door", "u": 0.0, "width": 1.4, "height": 2.5, "sill": 0.0, "color": Color(0.35, 0.22, 0.15)},
		{"side": "front", "u": -5.4, "width": 2.6, "height": 2.0, "sill": 0.4, "id": "me_cinzak_p0_1", "cross": false, "style": "store"},
		{"side": "front", "u": 5.4, "width": 2.6, "height": 2.0, "sill": 0.4, "id": "me_cinzak_p0_2", "cross": false, "style": "store"},
	]
	for f in range(1, floors):
		ops.append_array(_floor_windows("front", cols, f, st, 1.2, 1.6, 0.9, "me_cinzak"))
	for f in floors:
		for side in ["left", "right"]:
			ops.append({"side": side, "u": 0.0, "width": 1.1, "height": 1.5, "sill": f * st + 0.95})
		for u: float in [-5.0, 0.0, 5.0]:
			ops.append({"side": "back", "u": u, "width": 1.2, "height": 1.5, "sill": f * st + 0.9})
	var bands := []
	var levels := []
	var styles := []
	for f in floors:
		levels.append(f * st)
		styles.append("flat")
		if f > 0:
			bands.append(f * st)
	var fh := 0.3
	var wh := st * floors + 0.3
	HouseBuilder.build(self, {
		"name": "Tenement", "position": Vector3(x, 0, z), "rotation_y": PI, "width": w, "depth": d,
		"found_h": fh, "wall_h": wh, "roof": "flat", "parapet_h": 0.95, "seed": 850,
		"wall_color": Color(0.82, 0.74, 0.62), "roof_color": Color(0.4, 0.3, 0.27), "trim_color": Color(0.97, 0.95, 0.9),
		"bands": bands, "band_color": Color(0.9, 0.85, 0.75), "curtain_color": Color(0.95, 0.92, 0.85),
		"room_color": Color(0.7, 0.55, 0.42), "dirt_profile": "mesto_smog", "openings": ops,
		"interior": true, "levels": levels, "styles": styles,
		"interior_color": Color(0.96, 0.92, 0.85), "floor_color": Color(0.6, 0.42, 0.3),
	})
	var roof_y := fh + wh + 0.25
	_label("LÉKÁRNA", Vector3(x + 5.4, 2.9, z - d * 0.5 - 0.14), 44, Color(0.2, 0.65, 0.35), Color(1, 1, 1), PI)
	_label("TRAFIKA", Vector3(x - 5.4, 2.9, z - d * 0.5 - 0.14), 44, Color(0.2, 0.35, 0.6), Color(1, 1, 1), PI)
	_label("PALACKÉHO 18", Vector3(x, 3.0, z - d * 0.5 - 0.14), 32, Color(1, 1, 1), Color(0.25, 0.3, 0.4), PI)
	_roof_access(Vector3(x, 1.5, z - d * 0.5 - 0.1), Vector3(1.4, 2.5, 0.3), Vector3(x, 0.05, z - d * 0.5 - 1.2), PI,
		Vector3(x + 4.0, roof_y + 0.05, z + 1.5), 0.0, Vector3(x + 4.0, roof_y, z + 3.6), "kotvicí body")
	for i in cols.size():
		var a := RopeAnchor.new()
		a.anchor_id = "cinzak_%d" % (i + 1)
		a.position = Vector3(x - float(cols[i]), roof_y, z - d * 0.5 + 0.6)
		a.rotation.y = PI
		a.wall_out = 0.6
		a.edge_h = 0.95
		a.roof_y = roof_y
		a.ground_y = 0.0
		add_child(a)
		anchors.append(a)
	_exclude_rect(x - w * 0.5 - 1.5, WALK_Z, x + w * 0.5 + 1.5, z + d * 0.5 + 1.5)
	_map_rect(x, z, w, d, Color(0.8, 0.7, 0.55), "Činžovní dům")
	var front := ["me_cinzak_p0_1", "me_cinzak_p0_2", "me_cinzak_p1_1", "me_cinzak_p1_2", "me_cinzak_p1_3", "me_cinzak_p1_4", "me_cinzak_p1_5"]
	var all := front.duplicate()
	for k in 5:
		all.append("me_cinzak_p2_%d" % (k + 1))
	_register("me_cinzak", Vector2(x, WALK_Z - 0.5), front, all, 1.25)


# ------------------------------------------------------------------ náměstí, okolní bloky, zeleň

func _square() -> void:
	var b := MeshBuilder.new(860)
	# malé náměstí s kašnou mezi obchodním domem a činžákem
	var c := Vector3(0.0, 0.0, 22.0)
	_strip(b, -14, 10, 15, 34, 0.05, Color(0.78, 0.74, 0.66), 0.03)
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(5.0, 0.6, 5.0)), c + Vector3(0, 0.3, 0)), Color(0.7, 0.7, 0.72))
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(4.4, 0.1, 4.4)), c + Vector3(0, 0.58, 0)), Color(0.35, 0.55, 0.7), 0.0)
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.5, 1.8, 0.5)), c + Vector3(0, 0.9, 0)), Color(0.7, 0.7, 0.72))
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(1.4, 0.15, 1.4)), c + Vector3(0, 1.8, 0)), Color(0.7, 0.7, 0.72))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.5
	cyl.height = 0.7
	cs.shape = cyl
	cs.position = c + Vector3(0, 0.35, 0)
	_static.add_child(cs)
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		Props.bench(b, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), c + Vector3(cos(a), 0, sin(a)) * 6.5))
	b.to_instance(self, "Square")
	var it := SimpleInteractable.create("[E] Vymáchat nástroj a doplnit rozprašovač (kašna)", func(p): p.cleaning.rinse(), Vector3(5.2, 0.8, 5.2), c + Vector3(0, 0.4, 0))
	add_child(it)
	_exclude_rect(-6, 16, 6, 28)
	_map_rect(0.0, 22.0, 29.0, 24.0, Color(0.75, 0.72, 0.65), "Náměstí")


## Okolní bloky bez zakázek – jednoduché kvádry s mřížkou oken (kulisa města).
func _filler_blocks() -> void:
	var b := MeshBuilder.new(870)
	var wb := MeshBuilder.new(871)
	var blocks := [
		[-80.0, -1, 24.0, 16.0, 22.0], [-56.0, -1, 16.0, 14.0, 15.0], [62.0, -1, 22.0, 14.0, 26.0], [88.0, -1, 20.0, 16.0, 17.0],
		[-62.0, 1, 18.0, 14.0, 14.0], [-86.0, 1, 22.0, 16.0, 24.0], [58.0, 1, 20.0, 12.0, 18.0], [84.0, 1, 22.0, 16.0, 13.0],
	]
	var cols := [Color(0.78, 0.72, 0.65), Color(0.62, 0.66, 0.72), Color(0.85, 0.8, 0.7), Color(0.55, 0.6, 0.62), Color(0.88, 0.84, 0.78)]
	for i in blocks.size():
		var bl: Array = blocks[i]
		var bx: float = bl[0]
		var s: float = bl[1]
		var bw: float = bl[2]
		var bd: float = bl[3]
		var bh: float = bl[4]
		var bz := s * (WALK_Z + 0.6 + bd * 0.5)
		var col: Color = cols[i % cols.size()]
		b.add_box(Vector3(bw, bh, bd), Vector3(bx, bh * 0.5, bz), col)
		b.add_box(Vector3(bw + 0.3, 0.6, bd + 0.3), Vector3(bx, bh + 0.3, bz), col.darkened(0.2))
		_col_box(Vector3(bw, bh, bd), Transform3D(Basis.IDENTITY, Vector3(bx, bh * 0.5, bz)))
		var face := bz - s * (bd * 0.5 + 0.02)
		var rows := int((bh - 1.5) / 3.2)
		var ncol := int(bw / 2.6)
		for r in rows:
			for k in ncol:
				var wx := bx - bw * 0.5 + (k + 0.5) * bw / ncol
				wb.add_box(Vector3(1.3, 1.6, 0.04), Vector3(wx, 1.6 + r * 3.2 + 0.8, face), Color(0.25, 0.32, 0.4).lightened(_rng.randf() * 0.1), Basis.IDENTITY, 0.0)
		_exclude_rect(bx - bw * 0.5 - 1.0, bz - bd * 0.5 - 1.0, bx + bw * 0.5 + 1.0, bz + bd * 0.5 + 1.0)
		_map_rect(bx, bz, bw, bd, Color(0.68, 0.68, 0.7))
	var mi := b.to_instance(self, "Blocks")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# okna bloků zvlášť – v noci se rozsvítí
	var wmi := MeshInstance3D.new()
	wmi.name = "BlocksWindows"
	wmi.mesh = wb.commit(Mats.facade_glass())
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wmi)


func _greenery() -> void:
	# stromořadí v chodníku
	var trees := [[], [], [], []]
	for x in range(-100, 101, 12):
		for s: float in [-1.0, 1.0]:
			var p := Vector2(x + s * 4.0, s * 8.2)
			if _excluded(p, 0.3) and absf(p.y) < 7.0:
				continue
			var hit := false
			for r in _exclude:
				if r.has_point(p) and r.size.y < 15.0 and absf(r.position.y) > 5.0:
					hit = true
			for c in _clear:
				if absf(p.x - c.x) < 3.6 and signf(p.y) == c.y:
					hit = true
			if hit:
				continue
			trees[1 if (x / 12) % 2 == 0 else 3].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.75, 0.95)), Vector3(p.x, 0, p.y)))
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.25
			cyl.height = 3.0
			cs.shape = cyl
			cs.position = Vector3(p.x, 1.5, p.y)
			_static.add_child(cs)
	# stromy na náměstí
	for p: Vector2 in [Vector2(-11, 13), Vector2(12, 13), Vector2(-11, 31), Vector2(12, 31)]:
		trees[0].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(p.x, 0, p.y)))
	for k in 4:
		if not trees[k].is_empty():
			Nature.multimesh(self, Nature.tree_mesh(k), trees[k], true, [], 0)


func _skyline() -> void:
	var b := MeshBuilder.new(899)
	for k in 40:
		var a := k * TAU / 40.0 + _rng.randf_range(-0.04, 0.04)
		var dist := _rng.randf_range(170.0, 240.0)
		var hgt := _rng.randf_range(20.0, 70.0)
		var s := _rng.randf_range(14.0, 30.0)
		b.add_box(Vector3(s, hgt, s * _rng.randf_range(0.7, 1.3)), Vector3(cos(a) * dist * 1.2, hgt * 0.5 - 1.0, sin(a) * dist), Color(0.6, 0.65, 0.72).lerp(Color(0.75, 0.75, 0.78), _rng.randf()))
	var mi := b.to_instance(self, "Skyline", false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _bounds() -> void:
	for d in [[Vector3(0, 5, -64), Vector3(250, 10, 2)], [Vector3(0, 5, 64), Vector3(250, 10, 2)], [Vector3(-118, 5, 0), Vector3(2, 10, 130)], [Vector3(118, 5, 0), Vector3(2, 10, 130)]]:
		_col_box(d[1], Transform3D(Basis.IDENTITY, d[0]))

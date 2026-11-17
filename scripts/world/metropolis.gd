class_name Metropolis
extends Node3D
## Oblast IV – Velkoměsto Horizont (Etapa 6, finále). Opravdové mrakodrapy s prosklenými
## fasádami, obchodní centrum a rezidence. Na vysoká patra jezdí závěsné plošiny, ale hlavně
## se tu vyplatí drony z depa na náměstí – samy létají k oknům v horních patrech.
## Jezdí se sem autobusem z Brodce a z návsi nebo firemní dodávkou.
## Lokální souřadnice: třída vede podél X v pásu z ∈ [-7, 7], chodníky do |z| = WALK_Z.
## Mrakodrapy se staví vlastním lehkým stavitelem (_tower): jeden kvádr s kolizí,
## na přední fasádě omyvatelná okna zakázek, ostatní okna jsou jen v meshi (výkon).

const ORIGIN := Vector3(0, 0, 2600)
const AREA_ID := "velkomesto"
const AREA_NAME := "Oblast IV – Velkoměsto · Horizont"
const UNLOCK_LEVEL := 14
const GROUND_SHADER := preload("res://shaders/ground.gdshader")

## Kde hráč vystoupí z autobusu (lokálně) a kam se položí žebříky, které jedou s ním.
const ARRIVE := Vector3(-6.0, 0.0, -9.6)
const ARRIVE_YAW := -PI * 0.5
## y = výška chodníku (chodník je jen vizuálně výš než kolize země).
const LADDER_SPOT := Vector3(-20.0, 0.08, -10.4)
## Firemní dodávka parkuje u chodníku kousek od zastávky.
const VAN_SPOT := Vector3(-14.0, 0.0, -5.6)
const WALK_Z := 11.0
## Depo dronů na náměstí (jižní strana třídy).
const DEPOT_POS := Vector3(0.0, 0.0, 17.0)

## Zákazníci ve Velkoměstě (poptávky): [jméno do titulku, kdo píše, typ budovy].
const CLIENTS := {
	"vm_aurora_lobby": ["Věž Aurora – vstupní hala", "Správa budovy Aurora", "Mrakodrap (18 podlaží)"],
	"vm_horizont_lobby": ["Horizont Tower – přízemí", "Recepce Horizont Tower", "Mrakodrap (28 podlaží)"],
	"vm_panorama_prizemi": ["Rezidence Panorama – přízemí", "Společenství Panorama", "Bytový dům (14 podlaží)"],
}

var _static: StaticBody3D
var _deco: MeshBuilder
var _rng := RandomNumberGenerator.new()
var _exclude: Array[Rect2] = []
var platforms: Array[SuspendedPlatform] = []
var towers := {}
var depot: Node3D


func _ready() -> void:
	_rng.seed = 6060
	position = ORIGIN
	_static = StaticBody3D.new()
	_static.name = "StaticCollision"
	add_child(_static)
	_deco = MeshBuilder.new(901)
	WorldMap.add_area(AREA_ID, AREA_NAME, Rect2(ORIGIN.x - 80, ORIGIN.z - 34, 160, 68))
	_ground()
	_street()
	_buildings()
	_plaza()
	_filler_blocks()
	_greenery()
	_skyline()
	_bounds()
	# ptáci kolem vysokých věží (Etapa 7)
	Birds.create(self, [
		{"center": Vector3(-40.0, 0, -20.4), "radius": 19.0, "h0": 34.0, "h1": 62.0, "count": 7},
		{"center": Vector3(34.0, 0, -21.4), "radius": 22.0, "h0": 55.0, "h1": 98.0, "count": 8},
		{"center": Vector3(36.0, 0, 19.4), "radius": 17.0, "h0": 24.0, "h1": 44.0, "count": 6},
	], 4242)
	_deco.to_instance(self, "MetroDecor")
	Events.contract_completed.connect(_on_contract_completed)


## Finále kariéry: Horizont Tower je umytá.
func _on_contract_completed(cid: String, _money: int, _xp: int) -> void:
	if cid != "vm_horizont_finale":
		return
	GameState.stats["career_finale"] = 1
	Events.toast("Horizont Tower září až po anténu! Clear View je jednička v oboru – od kýblu a starého hadru až k mrakodrapům. Děkujeme za hraní; další zakázky a pravidelný úklid tu na tebe dál čekají.", "success")


func gpos(local: Vector3) -> Vector3:
	return ORIGIN + local


func _map_rect(x: float, z: float, w: float, d: float, color: Color, label: String = "") -> void:
	WorldMap.add_rect(Rect2(ORIGIN.x + x - w * 0.5, ORIGIN.z + z - d * 0.5, w, d), color, label)


func _exclude_rect(x0: float, z0: float, x1: float, z1: float) -> void:
	_exclude.append(Rect2(Vector2(minf(x0, x1), minf(z0, z1)), Vector2(absf(x1 - x0), absf(z1 - z0))))


func _excluded(p: Vector2, margin: float = 0.0) -> bool:
	for r in _exclude:
		if r.grow(margin).has_point(p):
			return true
	return false


func _col_box(body: StaticBody3D, size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	body.add_child(cs)


func _strip(b: MeshBuilder, x0: float, z0: float, x1: float, z1: float, y: float, color: Color, thick: float = 0.04) -> void:
	b.add_box(Vector3(absf(x1 - x0), thick, absf(z1 - z0)), Vector3((x0 + x1) * 0.5, y - thick * 0.5, (z0 + z1) * 0.5), color, Basis.IDENTITY, 0.0)


func _label(parent: Node3D, text: String, pos: Vector3, size: int = 56, color: Color = Color(1, 1, 1), outline: Color = Color(0.15, 0.2, 0.25), yaw: float = 0.0, px: float = 0.006) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = outline
	l.position = pos
	l.rotation.y = yaw
	parent.add_child(l)
	if size < 150:
		# deska kousek před zdí, ať se nekryje s římsami a pásy fasády
		l.position += l.basis * Vector3(0, 0, 0.012)
		Props.board_behind(l, outline)
	return l


## Přenese hráče na místo ve světě (výtah, schodiště).
func _teleport(player, world_pos: Vector3, yaw: float) -> void:
	player.global_position = world_pos
	player.yaw = yaw
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player._safe_hist.clear()
	player._air_top = world_pos.y
	Audio.play("step", -6.0, 0.8)


func _register(cid: String, pos: Vector2, front: Array, pay: float) -> void:
	var cl: Array = CLIENTS[cid]
	ContractManager.register_client({
		"id": cid, "name": cl[0], "who": cl[1], "area": AREA_ID, "building": cl[2],
		"pos": Vector2(ORIGIN.x + pos.x, ORIGIN.z + pos.y), "front": front, "all": front, "tree": false, "pay": pay,
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
	_col_box(_static, Vector3(600, 2, 600), Transform3D(Basis.IDENTITY, Vector3(0, -1, 0)))
	var b := MeshBuilder.new(902)
	_strip(b, -118, -68, 118, 68, 0.02, Color(0.6, 0.6, 0.6), 0.02)
	b.to_instance(self, "Pavement")


func _street() -> void:
	var b := MeshBuilder.new(911)
	var asphalt := Color(0.27, 0.28, 0.3)
	var walk := Color(0.74, 0.73, 0.71)
	var curb := Color(0.84, 0.83, 0.8)
	_strip(b, -118, -7, 118, 7, 0.04, asphalt)
	# středový pás se zelení
	_strip(b, -118, -0.9, 118, 0.9, 0.12, Color(0.75, 0.74, 0.7), 0.12)
	_strip(b, -117, -0.7, 117, 0.7, 0.14, Color(0.35, 0.55, 0.3), 0.02)
	for x in range(-114, 114, 6):
		for s: float in [-3.9, 3.9]:
			_strip(b, x, s - 0.07, x + 3.0, s + 0.07, 0.046, Color(0.95, 0.95, 0.92), 0.01)
	for s: float in [-1.0, 1.0]:
		_strip(b, -118, s * 7.0, 118, s * 7.2, 0.09, curb, 0.1)
		_strip(b, -116, s * 7.2, 116, s * WALK_Z, 0.08, walk, 0.08)
	_col_box(_static, Vector3(236, 0.12, 1.8), Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0)))
	_exclude_rect(-120, -WALK_Z - 0.5, 120, WALK_Z + 0.5)
	WorldMap.add_rect(Rect2(ORIGIN.x - 118, ORIGIN.z - 7, 236, 14), Color(0.42, 0.43, 0.47))
	# přechody
	for px: float in [-60.0, 0.0, 60.0]:
		for k in 11:
			_strip(b, px - 2.0, -6.8 + k * 1.25, px + 2.0, -6.3 + k * 1.25, 0.053, Color(0.96, 0.96, 0.94), 0.01)
	# lampy
	var lamps := []
	for x: float in [-96.0, -72.0, -48.0, -24.0, 24.0, 48.0, 72.0, 96.0]:
		Props.lamp_post(b, Vector3(x, 0, -7.9), -PI * 0.5, lamps)
		Props.lamp_post(b, Vector3(x + 12.0, 0, 7.9), PI * 0.5, lamps)
	Props.lamp_lights(self, lamps)
	# zaparkovaná auta a taxíky
	var car_cols := [Color(0.95, 0.8, 0.15), Color(0.2, 0.22, 0.25), Color(0.85, 0.85, 0.88), Color(0.6, 0.12, 0.12), Color(0.95, 0.8, 0.15), Color(0.25, 0.35, 0.55)]
	var cars := [[-74.0, 5.4, 0.0], [-52.0, -5.4, PI], [8.0, 5.4, 0.0], [44.0, -5.4, PI], [70.0, 5.4, 0.0], [92.0, -5.4, PI]]
	for i in cars.size():
		var c: Array = cars[i]
		Props.car(b, Transform3D(Basis(Vector3.UP, PI * 0.5 + c[2]), Vector3(c[0], 0, c[1])), car_cols[i % car_cols.size()])
		_col_box(_static, Vector3(4.0, 1.4, 1.8), Transform3D(Basis.IDENTITY, Vector3(c[0], 0.7, c[1])))
	# autobusová zastávka (sever)
	var sx := -10.0
	b.add_box(Vector3(3.6, 0.1, 1.6), Vector3(sx, 2.45, -9.0), Color(0.18, 0.2, 0.24))
	for px: float in [sx - 1.7, sx + 1.7]:
		b.add_box(Vector3(0.08, 2.45, 0.08), Vector3(px, 1.22, -9.6), Color(0.18, 0.2, 0.24))
		b.add_box(Vector3(0.08, 2.45, 0.08), Vector3(px, 1.22, -8.4), Color(0.18, 0.2, 0.24))
	b.add_box(Vector3(3.5, 2.2, 0.04), Vector3(sx, 1.2, -9.7), Color(0.65, 0.8, 0.85), Basis.IDENTITY, 0.0)
	Props.bench(b, Transform3D(Basis.IDENTITY, Vector3(sx, 0, -9.2)))
	_col_box(_static, Vector3(3.6, 2.4, 0.2), Transform3D(Basis.IDENTITY, Vector3(sx, 1.2, -9.7)))
	for k in 2:
		var px := sx + 3.0 + k * 1.2
		b.add_box(Vector3(0.08, 2.2, 0.08), Vector3(px, 1.1, -8.3), Color(0.5, 0.5, 0.52))
		b.add_box(Vector3(0.5, 0.65, 0.05), Vector3(px, 1.7, -8.25), Color(0.95, 0.85, 0.2))
	b.to_instance(self, "Street")
	# projíždějící doprava (Etapa 7)
	Traffic.create(self, [
		{"z": 2.4, "dir": 1.0, "x0": -120.0, "x1": 120.0, "kind": "car", "count": 5, "speed": 10.0},
		{"z": -2.4, "dir": -1.0, "x0": -120.0, "x1": 120.0, "kind": "car", "count": 5, "speed": 9.5},
	], 909)
	_label(self, "Horizont, Hlavní bulvár", Vector3(sx, 2.7, -8.18), 40)
	var to_city := SimpleInteractable.create("[E] Autobus do Brodce – Město", func(p): get_tree().call_group("world", "bus_travel", City.AREA_ID, p), Vector3(0.6, 2.2, 0.4), Vector3(sx + 3.0, 1.1, -8.1))
	add_child(to_city)
	var to_village := SimpleInteractable.create("[E] Autobus do Lipové Lhoty (náves)", func(p): get_tree().call_group("world", "bus_travel", "venkov", p), Vector3(0.6, 2.2, 0.4), Vector3(sx + 4.2, 1.1, -8.1))
	add_child(to_village)
	_label(self, "Brodec", Vector3(sx + 3.0, 2.15, -8.2), 22, Color(0.1, 0.1, 0.1), Color(1, 1, 1))
	_label(self, "Lipová Lhota", Vector3(sx + 4.2, 2.15, -8.2), 22, Color(0.1, 0.1, 0.1), Color(1, 1, 1))
	WorldMap.add_marker("bus_vm", Vector2(ORIGIN.x + sx, ORIGIN.z - 9.6), "Autobus – Brodec, Lipová Lhota", Color(0.95, 0.8, 0.2))
	_exclude_rect(sx - 3.0, -11.0, sx + 6.0, -7.5)
	_exclude_rect(LADDER_SPOT.x - 7.0, LADDER_SPOT.z - 1.0, LADDER_SPOT.x + 1.0, LADDER_SPOT.z + 1.0)
	# pobočka obchodu s vybavením u zastávky
	ShopKiosk.build(self, Vector3(8.0, 0, -13.2), 0.0, "Úklid & Výšky – Horizont", Vector2(ORIGIN.x + 8.0, ORIGIN.z - 13.2), 991)
	_exclude_rect(5.0, -15.5, 11.0, -11.0)
	for wp: Vector3 in [Vector3(-26.0, 0, -10.6), Vector3(46.0, 0, -10.6), Vector3(-20.0, 0, 10.6), Vector3(46.0, 0, 10.6)]:
		_water_point(wp)


func _water_point(pos: Vector3) -> void:
	var b := MeshBuilder.new(int(absf(pos.x) * 7.0 + 9.0))
	Props.water_barrel(b, pos)
	b.to_instance(self, "Water")
	var it := SimpleInteractable.create("[E] Vymáchat nástroj a doplnit rozprašovač (sud s vodou)", func(p): p.cleaning.rinse(), Vector3(0.65, 0.95, 0.65), pos + Vector3(0, 0.47, 0))
	it.add_to_group("water_source")
	add_child(it)


# ------------------------------------------------------------------ mrakodrapy

func _buildings() -> void:
	# Věž Aurora – modrozelená skleněná věž (sever, vlevo)
	_tower({
		"key": "aurora", "name": "VĚŽ AURORA", "x": -40.0, "side": -1, "w": 20.0, "d": 18.0, "floors": 18, "st": 3.6,
		"frame": Color(0.78, 0.82, 0.86), "glass": Color(0.36, 0.6, 0.68), "mirror": 0.9, "room": Color(0.42, 0.48, 0.52),
		"cols": [-7.5, -2.5, 2.5, 7.5], "win": Vector2(3.6, 2.6), "sill": 0.5, "profile": "mesto_smog",
		"lobby_cols": [-7.5, -3.6, 3.6, 7.5], "lobby_w": 3.0, "lobby_id": "vm_aurora_lobby_w%d",
		"id_floors": [1, 2, 3, 4, 12, 13, 14, 15, 16, 17], "prefix": "vm_aurora", "crown": "fin",
	})
	# Horizont Tower – nejvyšší budova ve městě, art-deco koruna se stupni a anténou (sever, vpravo)
	_tower({
		"key": "horizont", "name": "HORIZONT TOWER", "x": 34.0, "side": -1, "w": 24.0, "d": 20.0, "floors": 28, "st": 3.6,
		"frame": Color(0.86, 0.83, 0.76), "glass": Color(0.72, 0.58, 0.36), "mirror": 0.9, "room": Color(0.5, 0.48, 0.44),
		"cols": [-9.0, -4.5, 0.0, 4.5, 9.0], "win": Vector2(3.5, 2.6), "sill": 0.5, "profile": "fasada_vyska",
		"lobby_cols": [-9.0, -4.5, 4.5, 9.0], "lobby_w": 3.4, "lobby_id": "vm_horizont_lobby_w%d",
		"id_floors": [22, 23, 24, 25, 26, 27], "prefix": "vm_horizont", "crown": "deco",
	})
	# Obchodní centrum Horizont – široké výlohy a pásová okna (jih, vlevo)
	_tower({
		"key": "oc", "name": "OC HORIZONT", "x": -38.0, "side": 1, "w": 40.0, "d": 22.0, "floors": 4, "st": 4.5,
		"frame": Color(0.9, 0.9, 0.88), "glass": Color(0.42, 0.56, 0.6), "mirror": 0.45, "room": Color(0.75, 0.72, 0.65),
		"cols": [-15.0, -9.0, -3.0, 3.0, 9.0, 15.0], "win": Vector2(5.0, 2.8), "sill": 0.7, "profile": "mesto_prach",
		"lobby_cols": [-17.0, -11.5, -6.0, 6.0, 11.5, 17.0], "lobby_w": 4.6, "lobby_h": 3.2, "lobby_id": "vm_oc_vyloha_w%d", "lobby_profile": "vyloha_mesto",
		"id_floors": [1, 2, 3], "prefix": "vm_oc", "crown": "flat",
	})
	# Rezidence Panorama – bytová věž s menšími okny (jih, vpravo)
	_tower({
		"key": "panorama", "name": "REZIDENCE PANORAMA", "x": 36.0, "side": 1, "w": 18.0, "d": 16.0, "floors": 14, "st": 3.2,
		"frame": Color(0.93, 0.9, 0.84), "glass": Color(0.55, 0.62, 0.64), "mirror": 0.6, "room": Color(0.68, 0.6, 0.5),
		"cols": [-6.0, -2.0, 2.0, 6.0], "win": Vector2(2.6, 1.8), "sill": 0.8, "profile": "hotel_okna",
		"lobby_cols": [-6.0, -3.2, 3.2, 6.0], "lobby_w": 2.2, "lobby_id": "vm_panorama_prizemi_w%d",
		"id_floors": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13], "prefix": "vm_panorama", "crown": "flat",
		# celá budova kolem dokola (zakázka vm_panorama_cela): okna i na bocích a vzadu, plošina na každé straně
		"all_sides": true, "side_cols": [-5.0, 0.0, 5.0],
	})
	_register("vm_aurora_lobby", Vector2(-36.0, -WALK_Z + 0.5), _ids("vm_aurora_lobby_w%d", 4), 1.5)
	_register("vm_horizont_lobby", Vector2(38.0, -WALK_Z + 0.5), _ids("vm_horizont_lobby_w%d", 4), 1.6)
	_register("vm_panorama_prizemi", Vector2(36.0, WALK_Z - 0.5), _ids("vm_panorama_prizemi_w%d", 4), 1.45)


func _ids(fmt: String, n: int) -> Array:
	var out := []
	for k in n:
		out.append(fmt % (k + 1))
	return out


## Mrakodrap z jednoho kvádru. Lokálně (uzel věže): přední fasáda míří do +Z (k třídě).
## side = -1 → budova na severu třídy (čelem do +Z), 1 → na jihu (otočená o 180°).
func _tower(s: Dictionary) -> void:
	var w: float = s["w"]
	var d: float = s["d"]
	var floors: int = s["floors"]
	var st: float = s["st"]
	var side: int = s["side"]
	var x: float = s["x"]
	var z := side * (WALK_Z + 0.4 + d * 0.5)
	var root := Node3D.new()
	root.name = "Tower_" + str(s["key"])
	root.position = Vector3(x, 0, z)
	root.rotation.y = 0.0 if side < 0 else PI
	add_child(root)
	towers[s["key"]] = root
	var body := StaticBody3D.new()
	body.name = "Collision"
	root.add_child(body)
	var b := MeshBuilder.new(920 + int(absf(x)))
	var frame: Color = s["frame"]
	var glass: Color = s["glass"]
	# zrcadlová skla: dekorativní okna mají vlastní lesklý mesh, omyvatelná okna zrcadlí shaderem
	var gb := MeshBuilder.new(930 + int(absf(x)))
	_cur_mirror = float(s.get("mirror", 0.0))
	_cur_tint = glass
	var room: Color = s["room"]
	## sokl (přízemí začíná ve výšce BASE)
	var base := 0.3
	var h := floors * st + base
	var fz := d * 0.5
	# hlavní kvádr
	b.add_box(Vector3(w, h, d), Vector3(0, h * 0.5, 0), frame.darkened(0.08))
	_col_box(body, Vector3(w, h, d), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)))
	# atika na střeše (kolize, ať se z ní nedá spadnout)
	var par := 1.0
	for e in [[Vector3(w, par, 0.3), Vector3(0, h + par * 0.5, fz - 0.15)], [Vector3(w, par, 0.3), Vector3(0, h + par * 0.5, -fz + 0.15)],
			[Vector3(0.3, par, d), Vector3(w * 0.5 - 0.15, h + par * 0.5, 0)], [Vector3(0.3, par, d), Vector3(-w * 0.5 + 0.15, h + par * 0.5, 0)]]:
		b.add_box(e[0], e[1], frame.darkened(0.15))
		_col_box(body, e[0], Transform3D(Basis.IDENTITY, e[1]))
	b.add_box(Vector3(w - 0.6, 0.05, d - 0.6), Vector3(0, h + 0.025, 0), Color(0.42, 0.43, 0.45), Basis.IDENTITY, 0.0)
	var cols: Array = s["cols"]
	var win: Vector2 = s["win"]
	var sill: float = s["sill"]
	var id_floors: Array = s["id_floors"]
	var prefix: String = s["prefix"]
	var profile: String = s["profile"]
	# --- přední fasáda: pásy pater a sloupky mezi okny
	for f in range(1, floors + 1):
		b.add_box(Vector3(w + 0.08, 0.28, 0.12), Vector3(0, f * st + base - 0.14, fz + 0.06), frame)
	var edges := [-w * 0.5 + 0.2]
	for k in cols.size() - 1:
		edges.append((float(cols[k]) + float(cols[k + 1])) * 0.5)
	edges.append(w * 0.5 - 0.2)
	for ex: float in edges:
		# sloupky až od 1. patra (v přízemí jsou široké výlohy haly)
		b.add_box(Vector3(0.3, h - st - base, 0.14), Vector3(ex, (h + st + base) * 0.5, fz + 0.07), frame)
	for f in range(1, floors):
		var y0 := f * st + base + sill
		for k in cols.size():
			var u: float = cols[k]
			var c := Vector3(u, y0 + win.y * 0.5, fz)
			if id_floors.has(f):
				_clean_window(root, b, "%s_p%d_%d" % [prefix, f, k + 1], c, win, room, frame, profile)
			else:
				var lit := _rng.randf() < 0.12
				if lit:
					b.add_box(Vector3(win.x, win.y, 0.05), c + Vector3(0, 0, 0.025), Color(0.95, 0.86, 0.6), Basis.IDENTITY, 0.0)
				else:
					gb.add_box(Vector3(win.x, win.y, 0.05), c + Vector3(0, 0, 0.025), _glass_shade(glass), Basis.IDENTITY, 0.0)
	# --- přízemí: vstup s výtahem a prosklená hala
	var lobby_h: float = s.get("lobby_h", 3.0)
	var lobby_w: float = s.get("lobby_w", 3.0)
	var lobby_cols: Array = s.get("lobby_cols", [])
	var mir_keep := _cur_mirror
	_cur_mirror = 0.0  # vstupní haly a výlohy zůstávají průhledné
	for k in lobby_cols.size():
		var c := Vector3(float(lobby_cols[k]), base + 0.2 + lobby_h * 0.5, fz)
		var lid: String = str(s.get("lobby_id", ""))
		if lid != "":
			_clean_window(root, b, lid % (k + 1), c, Vector2(lobby_w, lobby_h), room.lightened(0.15), frame, str(s.get("lobby_profile", profile)))
	_cur_mirror = mir_keep
	b.add_box(Vector3(w + 0.4, base, d + 0.4), Vector3(0, base * 0.5, 0), frame.darkened(0.25))
	_col_box(body, Vector3(w + 0.4, base, d + 0.4), Transform3D(Basis.IDENTITY, Vector3(0, base * 0.5, 0)))
	b.add_box(Vector3(2.0, 2.6, 0.06), Vector3(0, base + 1.3, fz + 0.03), Color(0.2, 0.24, 0.3))
	b.add_box(Vector3(2.3, 0.15, 0.1), Vector3(0, base + 2.68, fz + 0.06), frame.darkened(0.3))
	b.add_box(Vector3(4.4, 0.18, 2.0), Vector3(0, base + 3.3, fz + 1.0), frame)
	var roof_y := h
	var exit_pos := Vector3(-w * 0.5 + 2.0, roof_y, fz - 4.2)
	var roof_spot := root.transform * Vector3(-w * 0.5 + 4.2, roof_y + 0.05, fz - 2.6)
	var door_out := root.transform * Vector3(0, 0.05, fz + 1.6)
	var face_yaw := root.rotation.y
	var up := SimpleInteractable.create("[E] Výtahem na střechu (závěsná plošina) – %s" % str(s["name"]).capitalize(), func(p): _teleport(p, ORIGIN + roof_spot, face_yaw + PI), Vector3(2.0, 2.6, 0.3), Vector3(0, base + 1.3, fz + 0.15))
	root.add_child(up)
	# výtahová nástavba na střeše – dveřmi zpět dolů
	RoofExit.build(root, body, b, exit_pos, 0.0, func(p): _teleport(p, ORIGIN + door_out, face_yaw))
	# --- boky a zadní strana: u budov „kolem dokola" omyvatelná okna, jinak jen mřížka v meshi
	var all_sides := bool(s.get("all_sides", false))
	for sd in [[Vector3(1, 0, 0), d, w * 0.5, "r"], [Vector3(-1, 0, 0), d, w * 0.5, "l"], [Vector3(0, 0, -1), w, d * 0.5, "z"]]:
		var n: Vector3 = sd[0]
		var length: float = sd[1]
		var off: float = sd[2]
		var ncol := maxi(2, int(length / 4.6))
		var basis := Basis(Vector3.UP, atan2(n.x, n.z))
		if all_sides:
			var scols: Array = cols if sd[3] == "z" else s.get("side_cols", [])
			for f in range(1, floors):
				for k in scols.size():
					var c := basis * Vector3(float(scols[k]), f * st + base + sill + win.y * 0.5, off)
					_clean_window(root, b, "%s_%s%d_%d" % [prefix, sd[3], f, k + 1], c, win, room, frame, profile, basis)
			for f in range(1, floors + 1):
				b.add_box(Vector3(length + 0.08, 0.28, 0.12), basis * Vector3(0, f * st + base - 0.14, off + 0.06), frame, basis)
			var pls := SuspendedPlatform.new()
			pls.anchor_id = "vm_%s_%s" % [s["key"], sd[3]]
			pls.position = basis * Vector3(0, h, off - 0.7)
			pls.rotation.y = atan2(n.x, n.z)
			pls.wall_out = 0.7
			pls.edge_h = 1.0
			pls.roof_y = h
			pls.ground_y = 0.0
			pls.rail_half = length * 0.5 - 1.2
			root.add_child(pls)
			platforms.append(pls)
			continue
		for f in range(1, floors):
			for k in ncol:
				var u := -length * 0.5 + (k + 0.5) * length / ncol
				var lit := _rng.randf() < 0.1
				var p := basis * Vector3(u, f * st + base + sill + win.y * 0.5, off + 0.02)
				if lit:
					b.add_box(Vector3(length / ncol - 0.9, win.y, 0.05), p, Color(0.95, 0.86, 0.6), basis, 0.0)
				else:
					gb.add_box(Vector3(length / ncol - 0.9, win.y, 0.05), p, _glass_shade(glass), basis, 0.0)
		for f in range(1, floors + 1):
			b.add_box(Vector3(length + 0.08, 0.28, 0.1), basis * Vector3(0, f * st + base - 0.14, off + 0.05), frame, basis)
	# --- koruna
	match str(s["crown"]):
		"deco":
			# stupňovitá art-deco koruna s anténou (mrakodrap ze 30. let)
			var y := roof_y
			for step in [[0.62, 5.0], [0.42, 4.5], [0.26, 4.0]]:
				var sw: float = w * float(step[0])
				var sh: float = step[1]
				b.add_box(Vector3(sw, sh, sw * d / w), Vector3(0, y + sh * 0.5, -1.5), frame.lightened(0.05))
				_col_box(body, Vector3(sw, sh, sw * d / w), Transform3D(Basis.IDENTITY, Vector3(0, y + sh * 0.5, -1.5)))
				for k in 3:
					b.add_box(Vector3(0.6, sh - 1.0, 0.06), Vector3((k - 1) * sw * 0.28, y + sh * 0.5, -1.5 + sw * d / w * 0.5 + 0.03), glass.darkened(0.2), Basis.IDENTITY, 0.0)
				y += sh
			b.add("cyl10", Transform3D(Basis.from_scale(Vector3(1.2, 4.0, 1.2)), Vector3(0, y + 2.0, -1.5)), frame.lightened(0.1))
			b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.35, 14.0, 0.35)), Vector3(0, y + 11.0, -1.5)), Color(0.75, 0.76, 0.78))
		"fin":
			b.add_box(Vector3(0.6, 9.0, d * 0.7), Vector3(w * 0.5 - 1.0, roof_y + 4.5, -1.0), glass.lightened(0.15))
			_col_box(body, Vector3(0.6, 9.0, d * 0.7), Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - 1.0, roof_y + 4.5, -1.0)))
			b.add_box(Vector3(4.0, 2.4, 4.0), Vector3(4.0, roof_y + 1.2, -4.0), Color(0.6, 0.62, 0.64))
			_col_box(body, Vector3(4.0, 2.4, 4.0), Transform3D(Basis.IDENTITY, Vector3(4.0, roof_y + 1.2, -4.0)))
		_:
			b.add_box(Vector3(5.0, 2.2, 3.0), Vector3(4.0, roof_y + 1.1, -d * 0.25), Color(0.62, 0.63, 0.65))
			_col_box(body, Vector3(5.0, 2.2, 3.0), Transform3D(Basis.IDENTITY, Vector3(4.0, roof_y + 1.1, -d * 0.25)))
	var mi := b.to_instance(root, "TowerMesh")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not gb.is_empty():
		var gmi := MeshInstance3D.new()
		gmi.name = "TowerGlass"
		gmi.mesh = gb.commit(Mats.mirror_glass() if _cur_mirror > 0.0 else Mats.facade_glass())
		gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gmi)
	_cur_mirror = 0.0
	# název budovy na čele markýzy nad vchodem
	_label(root, str(s["name"]), Vector3(0, base + 3.3, fz + 2.03), 56, Color(0.97, 0.97, 1.0), Color(0.15, 0.2, 0.3), 0.0, 0.0045)
	# závěsná plošina na přední hraně střechy
	var pl := SuspendedPlatform.new()
	pl.anchor_id = "vm_" + str(s["key"])
	pl.position = Vector3(0, roof_y, fz - 0.7)
	pl.wall_out = 0.7
	pl.edge_h = par
	pl.roof_y = roof_y
	pl.ground_y = 0.0
	pl.rail_half = w * 0.5 - 0.6
	root.add_child(pl)
	platforms.append(pl)
	_exclude_rect(x - w * 0.5 - 1.5, z - d * 0.5 - 1.5, x + w * 0.5 + 1.5, z + d * 0.5 + 1.5)
	_map_rect(x, z, w, d, Color(0.55, 0.62, 0.72), str(s["name"]).capitalize())


## Omyvatelné okno na fasádě: tmavá „místnost" za sklem, rámeček a sklo zakázky.
var _cur_mirror := 0.0
var _cur_tint := Color(0.45, 0.6, 0.7)


## Odstín zrcadlového skla: jednotlivé tabule se lehce liší (jako ve skutečnosti).
func _glass_shade(glass: Color) -> Color:
	return glass.lerp(Color(0.62, 0.7, 0.76), _rng.randf() * 0.18).darkened(_rng.randf() * 0.12)


func _clean_window(root: Node3D, b: MeshBuilder, id: String, c: Vector3, size: Vector2, room: Color, frame: Color, profile: String, basis := Basis.IDENTITY) -> void:
	b.add_box(Vector3(size.x + 0.04, size.y + 0.04, 0.02), c + basis * Vector3(0, 0, 0.01), room, basis, 0.0)
	# žaluzie nahoře a světlejší strop místnosti (ať je za čistým sklem co vidět)
	b.add_box(Vector3(size.x - 0.1, size.y * 0.18, 0.01), c + basis * Vector3(0, size.y * 0.38, 0.022), room.lightened(0.35), basis, 0.0)
	b.add_box(Vector3(size.x * 0.3, size.y * 0.35, 0.01), c + basis * Vector3(-size.x * 0.22, -size.y * 0.3, 0.022), room.darkened(0.25), basis, 0.0)
	for e: float in [-1.0, 1.0]:
		b.add_box(Vector3(0.07, size.y + 0.14, 0.09), c + basis * Vector3(e * (size.x * 0.5 + 0.035), 0, 0.045), frame.lightened(0.05), basis)
		b.add_box(Vector3(size.x + 0.14, 0.07, 0.09), c + basis * Vector3(0, e * (size.y * 0.5 + 0.035), 0.045), frame.lightened(0.05), basis)
	var cw := CleanableWindow.new()
	cw.name = "Window_" + id
	cw.window_id = id
	cw.glass_size = size
	cw.dirt_level = 1.0
	cw.dirt_profile = profile
	cw.mirror = _cur_mirror
	cw.mirror_tint = _cur_tint
	cw.transform = Transform3D(basis, c + basis * Vector3(0, 0, 0.04))
	root.add_child(cw)


# ------------------------------------------------------------------ náměstí s depem dronů

func _plaza() -> void:
	var b := MeshBuilder.new(960)
	_strip(b, -14, WALK_Z, 14, 32, 0.05, Color(0.8, 0.77, 0.7), 0.03)
	var c := Vector3(0, 0, 26.0)
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(5.0, 0.6, 5.0)), c + Vector3(0, 0.3, 0)), Color(0.72, 0.72, 0.74))
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(4.4, 0.1, 4.4)), c + Vector3(0, 0.58, 0)), Color(0.35, 0.55, 0.7), 0.0)
	b.add_box(Vector3(0.6, 3.0, 0.6), c + Vector3(0, 1.5, 0), Color(0.75, 0.75, 0.78))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.5
	cyl.height = 0.7
	cs.shape = cyl
	cs.position = c + Vector3(0, 0.35, 0)
	_static.add_child(cs)
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		Props.bench(b, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), c + Vector3(cos(a), 0, sin(a)) * 6.2))
	b.to_instance(self, "Plaza")
	var it := SimpleInteractable.create("[E] Vymáchat nástroj a doplnit rozprašovač (kašna)", func(p): p.cleaning.rinse(), Vector3(5.2, 0.8, 5.2), c + Vector3(0, 0.4, 0))
	add_child(it)
	depot = DroneDepot.build(self, DEPOT_POS, PI, "horizont")
	_exclude_rect(-15, WALK_Z, 15, 33)
	_map_rect(0.0, 21.5, 28.0, 21.0, Color(0.78, 0.75, 0.68), "Náměstí – depo dronů")


## Kulisa: další věže okolo (bez zakázek).
## Barvy zrcadlových skel (modrá, zelená, bronzová, stříbrná, tyrkysová).
const GLASS_TINTS := [Color(0.4, 0.55, 0.72), Color(0.42, 0.62, 0.52), Color(0.7, 0.56, 0.38), Color(0.66, 0.7, 0.74), Color(0.34, 0.62, 0.66)]


func _filler_blocks() -> void:
	var b := MeshBuilder.new(970)
	var fgb := MeshBuilder.new(971)
	var blocks := [
		[-86.0, -1, 22.0, 18.0, 46.0], [-66.0, -1, 14.0, 14.0, 30.0], [-1.0, -1, 10.0, 16.0, 38.0], [68.0, -1, 18.0, 16.0, 54.0], [94.0, -1, 18.0, 16.0, 34.0],
		[-86.0, 1, 22.0, 16.0, 40.0], [-66.0, 1, 12.0, 14.0, 24.0], [64.0, 1, 18.0, 16.0, 62.0], [92.0, 1, 20.0, 16.0, 30.0],
	]
	var cols := [Color(0.62, 0.68, 0.74), Color(0.78, 0.76, 0.72), Color(0.5, 0.56, 0.62), Color(0.84, 0.82, 0.78), Color(0.6, 0.64, 0.66)]
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
		_col_box(_static, Vector3(bw, bh, bd), Transform3D(Basis.IDENTITY, Vector3(bx, bh * 0.5, bz)))
		var face := bz - s * (bd * 0.5 + 0.02)
		var tint: Color = GLASS_TINTS[i % GLASS_TINTS.size()]
		var rows := int((bh - 2.0) / 3.4)
		var ncol := int(bw / 2.8)
		for r in rows:
			for k in ncol:
				var wx := bx - bw * 0.5 + (k + 0.5) * bw / ncol
				var lit := _rng.randf() < 0.2
				if lit:
					b.add_box(Vector3(1.8, 2.0, 0.04), Vector3(wx, 2.2 + r * 3.4 + 1.0, face), Color(0.95, 0.85, 0.55), Basis.IDENTITY, 0.0)
				else:
					fgb.add_box(Vector3(1.8, 2.0, 0.04), Vector3(wx, 2.2 + r * 3.4 + 1.0, face), _glass_shade(tint), Basis.IDENTITY, 0.0)
		_exclude_rect(bx - bw * 0.5 - 1.0, bz - bd * 0.5 - 1.0, bx + bw * 0.5 + 1.0, bz + bd * 0.5 + 1.0)
		_map_rect(bx, bz, bw, bd, Color(0.68, 0.68, 0.7))
	var mi := b.to_instance(self, "Blocks")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var gmi := MeshInstance3D.new()
	gmi.name = "BlocksGlass"
	gmi.mesh = fgb.commit(Mats.mirror_glass())
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gmi)


func _greenery() -> void:
	var trees: Array = []
	for x in range(-108, 109, 12):
		for s: float in [-1.0, 1.0]:
			var p := Vector2(x + s * 4.0, s * 9.6)
			if absf(p.x - LADDER_SPOT.x) < 8.0 or absf(p.x - (-10.0)) < 5.0 or absf(p.x - 8.0) < 4.0 or absf(p.x) < 15.0 and s > 0.0:
				continue
			if absf(p.x - VAN_SPOT.x) < 4.0:
				continue
			var near_door := false
			for t in towers.values():
				if absf(p.x - (t as Node3D).position.x) < 3.5:
					near_door = true
			if near_door:
				continue
			trees.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 0.9)), Vector3(p.x, 0, p.y)))
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.25
			cyl.height = 3.0
			cs.shape = cyl
			cs.position = Vector3(p.x, 1.5, p.y)
			_static.add_child(cs)
	if not trees.is_empty():
		Nature.multimesh(self, Nature.tree_mesh(1), trees, true, [], 0)
	var plaza := []
	for p: Vector2 in [Vector2(-11, 14), Vector2(11, 14), Vector2(-11, 30), Vector2(11, 30)]:
		plaza.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(p.x, 0, p.y)))
	Nature.multimesh(self, Nature.tree_mesh(0), plaza, true, [], 0)


## Panorama velkoměsta v pozadí (bez přístupu): dva prstence věží – zrcadlové skleněné
## i kamenné s pásy oken, některé se stupňovitou korunou nebo anténou. Mlha je zahalí do dálky.
func _skyline() -> void:
	var b := MeshBuilder.new(999)
	var gb := MeshBuilder.new(998)
	for ring in [[64, 165.0, 235.0, 40.0, 150.0], [70, 250.0, 420.0, 70.0, 240.0]]:
		var count: int = ring[0]
		for k in count:
			var a := k * TAU / count + _rng.randf_range(-0.03, 0.03)
			var dist := _rng.randf_range(float(ring[1]), float(ring[2]))
			var hgt := _rng.randf_range(float(ring[3]), float(ring[4]))
			var sx := _rng.randf_range(14.0, 32.0)
			var sz := sx * _rng.randf_range(0.7, 1.3)
			var p := Vector3(cos(a) * dist * 1.25, 0.0, sin(a) * dist)
			var bas := Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3))
			if _rng.randf() < 0.45:
				# celoskleněná věž se zrcadlovou fasádou
				var tint: Color = GLASS_TINTS[_rng.randi() % GLASS_TINTS.size()]
				gb.add_box(Vector3(sx, hgt, sz), p + Vector3(0, hgt * 0.5 - 1.0, 0), _glass_shade(tint), bas, 0.0)
				b.add_box(Vector3(sx + 0.4, 1.2, sz + 0.4), p + Vector3(0, hgt - 0.4, 0), Color(0.82, 0.84, 0.86), bas, 0.0)
			else:
				var stone := Color(0.62, 0.64, 0.68).lerp(Color(0.82, 0.78, 0.72), _rng.randf())
				b.add_box(Vector3(sx, hgt, sz), p + Vector3(0, hgt * 0.5 - 1.0, 0), stone, bas)
				var band := Color(0.3, 0.38, 0.46).lerp(Color(0.5, 0.56, 0.6), _rng.randf())
				# pásy každé věže v jiné výšce – sousední věže se překrývají a stejné výšky by blikaly
				var y := 6.0 + _rng.randf_range(0.0, 2.5)
				while y < hgt - 3.0:
					b.add_box(Vector3(sx + 0.1, 2.0, sz + 0.1), p + Vector3(0, y, 0), band, bas, 0.0)
					y += 7.0
			var crown := _rng.randf()
			if crown < 0.25:
				# stupňovitá koruna
				var cy := hgt - 1.0
				var cs := 0.7
				for st in 3:
					var ch := _rng.randf_range(4.0, 8.0)
					b.add_box(Vector3(sx * cs, ch, sz * cs), p + Vector3(0, cy + ch * 0.5, 0), Color(0.78, 0.76, 0.72), bas)
					cy += ch
					cs *= 0.7
				if _rng.randf() < 0.6:
					b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.6, 18.0, 0.6)), p + Vector3(0, cy + 9.0, 0)), Color(0.72, 0.74, 0.76))
			elif crown < 0.4:
				b.add_box(Vector3(sx * 0.4, 5.0, sz * 0.4), p + Vector3(0, hgt + 1.5, 0), Color(0.6, 0.62, 0.64), bas)
	var mi := b.to_instance(self, "Skyline", false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gmi := MeshInstance3D.new()
	gmi.name = "SkylineGlass"
	gmi.mesh = gb.commit(Mats.mirror_glass())
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gmi)
	# odrazová sonda: zrcadlová skla odrážejí i budovy kolem (ve Forward+ i Compatibility)
	var probe := ReflectionProbe.new()
	probe.name = "CityReflections"
	probe.size = Vector3(300.0, 200.0, 180.0)
	probe.position = Vector3(0.0, 60.0, 0.0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.max_distance = 600.0
	probe.intensity = 1.0
	add_child(probe)


func _bounds() -> void:
	for d in [[Vector3(0, 5, -70), Vector3(260, 10, 2)], [Vector3(0, 5, 70), Vector3(260, 10, 2)], [Vector3(-122, 5, 0), Vector3(2, 10, 142)], [Vector3(122, 5, 0), Vector3(2, 10, 142)]]:
		_col_box(_static, d[1], Transform3D(Basis.IDENTITY, d[0]))

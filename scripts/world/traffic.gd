class_name Traffic
extends Node3D
## Projíždějící doprava (Etapa 7): auta, autobusy a tramvaj jezdí po pruzích ulice.
## Čistě dekorace – vozidla nemají kolizi, ale před hráčem v pruhu zastaví a počkají,
## takže ho nikdy nepřejedou. Tramvaj staví na zastávce.
##
## Pruh: {"z": lokální z, "dir": +1/-1 (směr po ose X), "x0", "x1", "kind": "car"/"tram",
##        "count": počet vozidel, "speed": m/s, "stop_x": zastávka (jen tramvaj)}

const CAR_COLORS := [Color(0.85, 0.85, 0.88), Color(0.2, 0.22, 0.25), Color(0.62, 0.12, 0.12), Color(0.95, 0.8, 0.15),
		Color(0.25, 0.35, 0.55), Color(0.3, 0.5, 0.35), Color(0.75, 0.75, 0.7), Color(0.9, 0.45, 0.15)]
const STOP_DIST := 7.0
const GAP := 9.0

static var _mesh_cache := {}

var lanes: Array = []
var vehicles: Array = []   # {"node", "lane", "x", "speed", "len", "wait"}
var _rng := RandomNumberGenerator.new()


static func create(parent: Node3D, lane_list: Array, seed_value: int) -> Traffic:
	var t := Traffic.new()
	t.name = "Traffic"
	t.lanes = lane_list
	t._rng.seed = seed_value
	parent.add_child(t)
	return t


func _ready() -> void:
	add_to_group("traffic")
	for li in lanes.size():
		var ln: Dictionary = lanes[li]
		var count: int = ln.get("count", 3)
		var span: float = float(ln["x1"]) - float(ln["x0"])
		for k in count:
			var kind: String = ln.get("kind", "car")
			if kind == "car" and _rng.randf() < 0.15:
				kind = "bus"
			var node := MeshInstance3D.new()
			node.mesh = _vehicle_mesh(kind, _rng.randi() % CAR_COLORS.size())
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(node)
			var length := 4.0 if kind == "car" else (11.0 if kind == "bus" else 22.0)
			var v := {"node": node, "lane": li, "x": float(ln["x0"]) + span * (k + _rng.randf() * 0.5) / count,
				"speed": float(ln.get("speed", 9.0)) * _rng.randf_range(0.85, 1.1), "len": length, "wait": 0.0, "kind": kind}
			vehicles.append(v)
			_place(v)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var pl := to_local(player.global_position) if player else Vector3(1e9, 0, 1e9)
	for v in vehicles:
		step(v, delta, pl)


## Jeden krok vozidla (veřejné kvůli testu).
func step(v: Dictionary, delta: float, player_local: Vector3) -> void:
	var ln: Dictionary = lanes[v["lane"]]
	var dir: float = ln["dir"]
	var x: float = v["x"]
	if float(v["wait"]) > 0.0:
		v["wait"] = float(v["wait"]) - delta
		return
	var front := x + dir * float(v["len"]) * 0.5
	# hráč v pruhu před vozidlem → stát
	if absf(player_local.z - float(ln["z"])) < 1.8 and player_local.y < 4.0:
		var ahead := (player_local.x - front) * dir
		if ahead > -0.5 and ahead < STOP_DIST:
			return
	# odstup od vozidla vpředu
	for o in vehicles:
		if o == v or o["lane"] != v["lane"]:
			continue
		var gap := (float(o["x"]) - x) * dir - (float(o["len"]) + float(v["len"])) * 0.5
		if gap > -0.1 and gap < GAP * 0.5:
			return
	var nx := x + dir * float(v["speed"]) * delta
	# tramvaj zastaví na zastávce
	if ln.has("stop_x"):
		var sx: float = ln["stop_x"]
		if (x - sx) * dir < 0.0 and (nx - sx) * dir >= 0.0:
			nx = sx
			v["wait"] = 8.0
	# na konci ulice zmizí a vrátí se na začátek
	var x0: float = ln["x0"]
	var x1: float = ln["x1"]
	if (dir > 0.0 and nx > x1) or (dir < 0.0 and nx < x0):
		var start := x0 if dir > 0.0 else x1
		if not _start_clear(v, start):
			v["node"].visible = false
			v["wait"] = 0.5
			return
		nx = start
	v["node"].visible = true
	v["x"] = nx
	_place(v)


## Je začátek pruhu volný (aby se vozidlo po návratu neobjevilo v jiném)?
func _start_clear(v: Dictionary, start: float) -> bool:
	for o in vehicles:
		if o == v or o["lane"] != v["lane"]:
			continue
		if absf(float(o["x"]) - start) < (float(o["len"]) + float(v["len"])) * 0.5 + GAP:
			return false
	return true


func _place(v: Dictionary) -> void:
	var ln: Dictionary = lanes[v["lane"]]
	var node: MeshInstance3D = v["node"]
	node.position = Vector3(float(v["x"]), 0.0, float(ln["z"]))
	# auto má předek v +Z → natočit podle směru po X
	node.rotation.y = PI * 0.5 if float(ln["dir"]) > 0.0 else -PI * 0.5


static func _vehicle_mesh(kind: String, color_idx: int) -> ArrayMesh:
	var key := "%s_%d" % [kind, color_idx if kind == "car" else 0]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var b := MeshBuilder.new(500 + color_idx)
	match kind:
		"bus":
			_bus(b)
		"tram":
			_tram(b)
		_:
			Props.car(b, Transform3D.IDENTITY, CAR_COLORS[color_idx])
	var m := b.commit()
	_mesh_cache[key] = m
	return m


## Městský autobus (předek v +Z).
static func _bus(b: MeshBuilder) -> void:
	var body := Color(0.2, 0.55, 0.75)
	var glass := Color(0.18, 0.24, 0.3)
	var dark := Color(0.12, 0.12, 0.13)
	b.add_box(Vector3(2.5, 2.6, 11.0), Vector3(0, 1.75, 0), body)
	# okna: o kousek užší pás než karoserie (bez z-fightingu na koncích)
	for s: float in [-1.0, 1.0]:
		b.add_box(Vector3(0.04, 1.0, 9.6), Vector3(s * 1.26, 2.3, -0.4), glass, Basis.IDENTITY, 0.0)
	b.add_box(Vector3(2.2, 1.2, 0.04), Vector3(0, 2.2, 5.51), glass, Basis.IDENTITY, 0.0)
	b.add_box(Vector3(2.52, 0.12, 11.02), Vector3(0, 3.0, 0), Color(0.95, 0.95, 0.93))
	b.add_box(Vector3(1.6, 0.3, 0.05), Vector3(0, 2.9, 5.53), Color(0.1, 0.1, 0.1), Basis.IDENTITY, 0.0)
	for z: float in [-3.6, 3.4]:
		for sx: float in [-1.14, 1.14]:
			b.add("cyl10", Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.9, 0.3, 0.9)), Vector3(sx, 0.45, z)), dark, 0.0)
			b.add("cyl10", Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.45, 0.015, 0.45)), Vector3(sx + signf(sx) * 0.16, 0.45, z)), Color(0.7, 0.7, 0.72), 0.0)
	for sx: float in [-0.9, 0.9]:
		b.add_box(Vector3(0.35, 0.15, 0.05), Vector3(sx, 0.8, 5.52), Color(1.0, 0.97, 0.85), Basis.IDENTITY, 0.0)


## Dvoučlánková tramvaj (předek v +Z): okna jako samostatné tabule, ne pás přes celou délku.
static func _tram(b: MeshBuilder) -> void:
	var red := Color(0.82, 0.14, 0.14)
	var cream := Color(0.95, 0.93, 0.86)
	var glass := Color(0.2, 0.27, 0.32)
	var dark := Color(0.14, 0.14, 0.15)
	for seg: float in [-5.6, 5.6]:
		b.add_box(Vector3(2.4, 2.5, 10.6), Vector3(0, 1.65, seg), red)
		b.add_box(Vector3(2.42, 0.5, 10.4), Vector3(0, 0.6, seg), cream)
		b.add_box(Vector3(2.3, 0.18, 10.4), Vector3(0, 2.98, seg), cream)
		for s: float in [-1.0, 1.0]:
			for k in 5:
				b.add_box(Vector3(0.04, 0.95, 1.55), Vector3(s * 1.215, 2.0, seg - 4.0 + k * 2.0), glass, Basis.IDENTITY, 0.0)
	# kloub mezi články
	b.add_box(Vector3(2.2, 2.3, 0.7), Vector3(0, 1.6, 0), dark)
	for e: float in [-1.0, 1.0]:
		b.add_box(Vector3(2.0, 1.2, 0.04), Vector3(0, 2.0, e * 10.92), glass, Basis.IDENTITY, 0.0)
		b.add_box(Vector3(0.35, 0.15, 0.05), Vector3(-0.8, 0.95, e * 10.93), Color(1.0, 0.97, 0.85), Basis.IDENTITY, 0.0)
		b.add_box(Vector3(0.35, 0.15, 0.05), Vector3(0.8, 0.95, e * 10.93), Color(1.0, 0.97, 0.85), Basis.IDENTITY, 0.0)
	# sběrač proudu
	b.add_box(Vector3(1.6, 0.06, 0.06), Vector3(0, 3.6, -3.0), dark)
	b.add_box(Vector3(0.06, 0.6, 0.06), Vector3(0, 3.3, -3.0), dark)

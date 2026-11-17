class_name HouseBuilder
extends RefCounted
## Procedurální stavitel domů z datového popisu (slovník spec).
## Stěny se skládají kolem otvorů, takže okna jsou skutečně zapuštěná do zdi.
## Okna s klíčem "id" se stanou omyvatelnými (CleanableWindow), ostatní
## dostanou levný sdílený materiál skla.
##
## Lokální souřadnice domu: šířka podél X, hloubka podél Z, přední strana = +Z.

const T := 0.22          # tloušťka zdi
const FRAME := 0.07      # šířka rámu okna
const FRAME_D := 0.11    # hloubka rámu

const SIDE_ANGLE := {"front": 0.0, "right": PI * 0.5, "back": PI, "left": -PI * 0.5}

var spec: Dictionary
var root: Node3D
var mb: MeshBuilder
var body: StaticBody3D
var W := 8.0
var D := 6.0
var FH := 0.3
var WH := 2.7
var RH := 1.6
## Sloupce otvorů na každé straně (pro automatické místnosti v interiéru).
var _side_groups := {}


static func build(parent: Node, s: Dictionary) -> Node3D:
	var hb := HouseBuilder.new()
	return hb._build(parent, s)


func _build(parent: Node, s: Dictionary) -> Node3D:
	spec = s
	W = s.get("width", 8.0)
	D = s.get("depth", 6.0)
	FH = s.get("found_h", 0.3)
	WH = s.get("wall_h", 2.7)
	RH = s.get("roof_h", 1.6)
	root = Node3D.new()
	root.name = s.get("name", "House")
	root.position = s.get("position", Vector3.ZERO)
	root.rotation.y = s.get("rotation_y", 0.0)
	parent.add_child(root)
	mb = MeshBuilder.new(int(s.get("seed", 7)))
	body = StaticBody3D.new()
	body.name = "Collision"
	root.add_child(body)

	var wall_c: Color = s.get("wall_color", Color(0.94, 0.89, 0.78))
	var found_c: Color = s.get("found_color", Color(0.55, 0.54, 0.52))

	# základ (sokl)
	_box(Vector3(W + 0.1, FH, D + 0.1), Vector3(0, FH * 0.5, 0), found_c, true)

	var openings: Array = s.get("openings", [])
	for side in ["front", "back", "left", "right"]:
		var ops := []
		for o in openings:
			if o.get("side", "front") == side:
				ops.append(o)
		_wall(side, ops, wall_c)

	if s.get("roof", "gable") == "flat":
		_flat_roof()
	else:
		_roof()
	if s.get("chimney", true) and s.get("roof", "gable") != "flat":
		_chimney()
	if s.get("interior", false):
		_interior()

	# vstupní dveře (v souřadnicích rodiče) – pro chodníčky od dveří k ulici
	var doors := []
	for o in openings:
		if o.get("type", "window") == "door":
			var sx := _side_xf(str(o.get("side", "front")))
			var p: Vector3 = root.transform * (sx * Vector3(float(o.get("u", 0.0)), 0.0, 0.0))
			var n: Vector3 = (root.transform.basis * (sx.basis * Vector3(0, 0, 1))).normalized()
			doors.append({"pos": Vector3(p.x, 0.0, p.z), "normal": n, "width": float(o.get("width", 1.0))})
	root.set_meta("doors", doors)

	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mb.commit(Mats.vc_snow())
	root.add_child(mi)
	return root


# ------------------------------------------------------------------ pomocné

func _side_xf(side: String) -> Transform3D:
	var ang: float = SIDE_ANGLE[side]
	var origin := Vector3.ZERO
	match side:
		"front":
			origin = Vector3(0, FH, D * 0.5)
		"back":
			origin = Vector3(0, FH, -D * 0.5)
		"right":
			origin = Vector3(W * 0.5, FH, 0)
		"left":
			origin = Vector3(-W * 0.5, FH, 0)
	return Transform3D(Basis(Vector3.UP, ang), origin)


func _side_len(side: String) -> float:
	return W if side == "front" or side == "back" else D - 2.0 * T


func _box(size: Vector3, pos: Vector3, color: Color, collide: bool = false, basis: Basis = Basis.IDENTITY) -> void:
	mb.add_box(size, pos, color, basis)
	if collide:
		_col(size, Transform3D(basis, pos))


func _col(size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	body.add_child(cs)


## Krabice v lokálních souřadnicích dané strany (u podél zdi, v výška, z ven).
func _sbox(sx: Transform3D, size: Vector3, local: Vector3, color: Color, collide: bool = false) -> void:
	var p := sx * local
	mb.add_box(size, p, color, sx.basis)
	if collide:
		_col(size, Transform3D(sx.basis, p))


# ------------------------------------------------------------------ stěny

func _wall(side: String, ops: Array, wall_c: Color) -> void:
	var sx := _side_xf(side)
	var length := _side_len(side)
	var interior: bool = spec.get("interior", false)
	var in_c: Color = spec.get("interior_color", Color(0.93, 0.9, 0.84))
	# Otvory se seskupí do sloupců podle překryvu v ose u – patrové domy mají okna
	# nad sebou (i různě široká, např. výloha a nad ní užší okno bytu).
	# Mezi otvory ve sloupci se doplní zeď, vedle užších otvorů boční výplň.
	var sorted_ops := ops.duplicate()
	sorted_ops.sort_custom(func(a, b): return a["u"] - a["width"] * 0.5 < b["u"] - b["width"] * 0.5)
	var groups := []   # [g0, g1, [openings]]
	for o in sorted_ops:
		var ou0: float = o["u"] - o["width"] * 0.5
		var ou1: float = o["u"] + o["width"] * 0.5
		if not groups.is_empty() and ou0 < groups[-1][1] - 0.001:
			groups[-1][1] = maxf(groups[-1][1], ou1)
			groups[-1][2].append(o)
		else:
			groups.append([ou0, ou1, [o]])
	_side_groups[side] = groups
	var cursor := -length * 0.5
	var pieces := []
	for g in groups:
		var g0: float = g[0]
		var g1: float = g[1]
		var col: Array = g[2]
		col.sort_custom(func(a, b): return a.get("sill", 0.9) < b.get("sill", 0.9))
		if g0 > cursor + 0.001:
			pieces.append([cursor, g0, 0.0, WH])
		var vcur := 0.0
		for o in col:
			var u0: float = o["u"] - o["width"] * 0.5
			var u1: float = o["u"] + o["width"] * 0.5
			var v0: float = o.get("sill", 0.9)
			var v1: float = v0 + o["height"]
			if v0 > vcur + 0.001:
				pieces.append([g0, g1, vcur, v0])
			if u0 > g0 + 0.001:
				pieces.append([g0, u0, v0, v1])
			if u1 < g1 - 0.001:
				pieces.append([u1, g1, v0, v1])
			vcur = v1
			_opening(side, sx, o, u0, u1, v0, v1)
		if vcur < WH - 0.001:
			pieces.append([g0, g1, vcur, WH])
		cursor = g1
	if cursor < length * 0.5 - 0.001:
		pieces.append([cursor, length * 0.5, 0.0, WH])
	for p in pieces:
		var size := Vector3(p[1] - p[0], p[3] - p[2], T)
		var c := Vector3((p[0] + p[1]) * 0.5, (p[2] + p[3]) * 0.5, -T * 0.5)
		if interior:
			_sbox(sx, Vector3(size.x, size.y, T - 0.03), c + Vector3(0, 0, 0.015), wall_c, true)
			_sbox(sx, Vector3(size.x, size.y, 0.03), Vector3(c.x, c.y, -T + 0.015), in_c)
		else:
			_sbox(sx, size, c, wall_c, true)
	# rohové lišty
	var trim: Color = spec.get("trim_color", Color(0.97, 0.96, 0.93))
	for bh in spec.get("bands", []):
		_sbox(sx, Vector3(length + (0.0 if side == "front" or side == "back" else 2.0 * T), 0.12, 0.08), Vector3(0, bh, 0.04), spec.get("band_color", trim))
	if side == "front" or side == "back":
		for e: float in [-1.0, 1.0]:
			# o 1 cm přes roh, ať se čelo lišty nekryje s konci pásů (bands)
			_sbox(sx, Vector3(0.12, WH, 0.04), Vector3(e * (W * 0.5 - 0.05), WH * 0.5, 0.02), trim)


func _opening(side: String, sx: Transform3D, o: Dictionary, u0: float, u1: float, v0: float, v1: float) -> void:
	var trim: Color = spec.get("trim_color", Color(0.97, 0.96, 0.93))
	var w := u1 - u0
	var h := v1 - v0
	var uc := (u0 + u1) * 0.5
	var vc := (v0 + v1) * 0.5
	var kind: String = o.get("type", "window")
	var reveal: Color = spec.get("interior_color", Color(0.9, 0.87, 0.8)).darkened(0.08)
	# ostění (vnitřní boky otvoru)
	_sbox(sx, Vector3(0.02, h, T), Vector3(u0 + 0.01, vc, -T * 0.5), reveal)
	_sbox(sx, Vector3(0.02, h, T), Vector3(u1 - 0.01, vc, -T * 0.5), reveal)
	if v0 > 0.01:
		_sbox(sx, Vector3(w, 0.02, T), Vector3(uc, v0 + 0.01, -T * 0.5), reveal)
	_sbox(sx, Vector3(w, 0.02, T), Vector3(uc, v1 - 0.01, -T * 0.5), reveal)
	# volný průchod (vrata garáže, hala) – jen ostění, žádné sklo ani rám
	if kind == "opening":
		return

	if kind == "door":
		var door_c: Color = o.get("color", spec.get("door_color", Color(0.24, 0.48, 0.55)))
		_sbox(sx, Vector3(w, 0.06, FRAME_D), Vector3(uc, v1 - 0.03, -FRAME_D * 0.5 + 0.02), trim)
		_sbox(sx, Vector3(0.06, h, FRAME_D), Vector3(u0 + 0.03, vc, -FRAME_D * 0.5 + 0.02), trim)
		_sbox(sx, Vector3(0.06, h, FRAME_D), Vector3(u1 - 0.03, vc, -FRAME_D * 0.5 + 0.02), trim)
		_sbox(sx, Vector3(w - 0.12, h - 0.06, 0.05), Vector3(uc, vc - 0.03, -0.07), door_c, true)
		# výplně dveří a klika
		for k in 2:
			var py := v0 + h * (0.3 + k * 0.4)
			_sbox(sx, Vector3(w * 0.55, h * 0.28, 0.02), Vector3(uc, py, -0.04), door_c.lightened(0.08))
		_sbox(sx, Vector3(0.1, 0.025, 0.04), Vector3(u1 - 0.17, v0 + 1.0, -0.02), Color(0.85, 0.72, 0.35))
		# schod před dveřmi
		if spec.get("door_step", true):
			# o 2 cm níž než sokl – jinak horní plochy schodu a soklu blikají přes sebe
			_sbox(sx, Vector3(w + 0.5, FH - 0.02, 0.5), Vector3(uc, -FH * 0.5 - 0.01, 0.25), spec.get("found_color", Color(0.55, 0.54, 0.52)).lightened(0.1), true)
		return

	# rám okna
	_sbox(sx, Vector3(w, FRAME, FRAME_D), Vector3(uc, v1 - FRAME * 0.5, -FRAME_D * 0.5 + 0.02), trim)
	_sbox(sx, Vector3(w, FRAME, FRAME_D), Vector3(uc, v0 + FRAME * 0.5, -FRAME_D * 0.5 + 0.02), trim)
	_sbox(sx, Vector3(FRAME, h - 2 * FRAME, FRAME_D), Vector3(u0 + FRAME * 0.5, vc, -FRAME_D * 0.5 + 0.02), trim)
	_sbox(sx, Vector3(FRAME, h - 2 * FRAME, FRAME_D), Vector3(u1 - FRAME * 0.5, vc, -FRAME_D * 0.5 + 0.02), trim)
	# parapet a nadpraží
	if v0 > 0.05:
		_sbox(sx, Vector3(w + 0.12, 0.05, 0.16), Vector3(uc, v0 - 0.02, 0.05), trim.darkened(0.06))
	_sbox(sx, Vector3(w + 0.14, 0.07, 0.04), Vector3(uc, v1 + 0.035, 0.02), trim)

	var gw := w - 2 * FRAME
	var gh := h - 2 * FRAME
	var glass_local := Vector3(uc, vc, -0.06)
	var glass_xf := sx * Transform3D(Basis.IDENTITY, glass_local)
	if o.has("id"):
		var cw := CleanableWindow.new()
		cw.name = "Window_" + str(o["id"])
		cw.window_id = o["id"]
		cw.glass_size = Vector2(gw, gh)
		cw.dirt_level = o.get("dirt", 1.0)
		cw.dirt_profile = o.get("profile", spec.get("dirt_profile", ""))
		cw.transform = glass_xf
		root.add_child(cw)
		# Velké budovy nemají interiér – za omyvatelné sklo dáme jen levnou „místnost".
		if not spec.get("interior", false):
			_backdrop(sx, o, u0, u1, uc, vc, gw, gh)
	else:
		# dekorativní sklo + jednoduchý „interiér" se záclonami za ním
		var q := QuadMesh.new()
		q.size = Vector2(gw, gh)
		var gmi := MeshInstance3D.new()
		gmi.mesh = q
		gmi.material_override = Mats.glass_static()
		gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gmi.transform = glass_xf
		root.add_child(gmi)
		_col(Vector3(gw, gh, 0.05), glass_xf)
		_backdrop(sx, o, u0, u1, uc, vc, gw, gh)
		if o.get("cross", true):
			_sbox(sx, Vector3(0.04, gh, 0.04), Vector3(uc, vc, -0.04), trim)
			_sbox(sx, Vector3(gw, 0.04, 0.04), Vector3(uc, vc + gh * 0.12, -0.04), trim)

	if o.get("shutters", false):
		var sc: Color = o.get("shutter_color", spec.get("shutter_color", Color(0.3, 0.52, 0.4)))
		for e: float in [-1.0, 1.0]:
			var cu := uc + e * (w * 0.5 + 0.2)
			_sbox(sx, Vector3(0.36, h, 0.04), Vector3(cu, vc, 0.03), sc)
			for k in 6:
				_sbox(sx, Vector3(0.3, 0.025, 0.02), Vector3(cu, v0 + 0.12 + k * (h - 0.24) / 5.0, 0.055), sc.darkened(0.15))
	if o.get("flowerbox", false):
		_sbox(sx, Vector3(w * 0.9, 0.17, 0.2), Vector3(uc, v0 - 0.16, 0.14), Color(0.55, 0.33, 0.2))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(uc * 100.0) + side.length()
		var flower_cols := [Color(0.92, 0.3, 0.35), Color(0.98, 0.75, 0.25), Color(0.85, 0.45, 0.8), Color(1, 1, 1)]
		for k in int(w * 7.0):
			var fu := u0 + 0.1 + rng.randf() * (w - 0.2)
			var fp := sx * Vector3(fu, v0 - 0.04 + rng.randf() * 0.06, 0.14 + rng.randf_range(-0.05, 0.05))
			mb.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.05, 0.08)), fp), flower_cols[rng.randi() % flower_cols.size()], 0.05)
			mb.add("sphere", Transform3D(Basis.from_scale(Vector3(0.09, 0.05, 0.09)), fp + Vector3(0, -0.035, 0)), Color(0.3, 0.55, 0.25), 0.05)


## Jednoduchý pohled do místnosti za sklem: zadní stěna a záclony.
func _backdrop(sx: Transform3D, o: Dictionary, u0: float, u1: float, uc: float, vc: float, gw: float, gh: float) -> void:
	var room_c: Color = o.get("room_color", spec.get("room_color", Color(0.42, 0.36, 0.3)))
	if not spec.get("interior", false):
		_sbox(sx, Vector3(gw + 0.1, gh + 0.1, 0.02), Vector3(uc, vc, -T - 0.25), room_c)
		_sbox(sx, Vector3(gw + 0.1, 0.02, 0.3), Vector3(uc, vc - gh * 0.5 - 0.04, -T - 0.1), room_c.darkened(0.25))
	var cur_c: Color = o.get("curtain", spec.get("curtain_color", Color(0.95, 0.93, 0.86)))
	if o.get("blinds", spec.get("blinds", false)):
		for k in int(gh * 0.45 / 0.09):
			_sbox(sx, Vector3(gw, 0.07, 0.01), Vector3(uc, vc + gh * 0.5 - 0.05 - k * 0.09, -0.16), cur_c)
		return
	_sbox(sx, Vector3(gw * 0.26, gh, 0.03), Vector3(u0 + FRAME + gw * 0.13, vc, -0.14), cur_c)
	_sbox(sx, Vector3(gw * 0.26, gh, 0.03), Vector3(u1 - FRAME - gw * 0.13, vc, -0.14), cur_c)


# ------------------------------------------------------------------ střecha

func _roof() -> void:
	var roof_c: Color = spec.get("roof_color", Color(0.75, 0.35, 0.25))
	var wall_c: Color = spec.get("wall_color", Color(0.94, 0.89, 0.78))
	var trim: Color = spec.get("trim_color", Color(0.97, 0.96, 0.93))
	var top := FH + WH
	var ov := 0.45
	var th := 0.14
	# štít (trojúhelníkové čelo) – hřeben podél osy X
	var prism_basis := Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(D, RH, W))
	mb.add("prism", Transform3D(prism_basis, Vector3(0, top + RH * 0.5, 0)), wall_c, 0.02)
	_col(Vector3(W, RH * 0.5, D * 0.7), Transform3D(Basis.IDENTITY, Vector3(0, top + RH * 0.25, 0)))
	var half := D * 0.5
	var slope := atan2(RH, half)
	var slen := sqrt(half * half + RH * RH)
	for e: float in [1.0, -1.0]:
		var eave := Vector3(0, top, e * half)
		var ridge := Vector3(0, top + RH, 0)
		var d := (ridge - eave).normalized()
		var nrm := Vector3(0, half, e * RH).normalized()
		var a := eave - d * ov
		var b := ridge + d * 0.04
		var c := (a + b) * 0.5 + nrm * th * 0.5
		var basis := Basis(Vector3.RIGHT, slope if e > 0 else PI - slope)
		var length := slen + ov + 0.04
		mb.add_box(Vector3(W + ov * 2.0, th, length), c, roof_c, basis, 0.025)
		# řady tašek
		var rows := int(length / 0.32)
		for r in rows:
			var t := (float(r) + 0.5) / rows
			var p := a.lerp(b, t) + nrm * (th + 0.012)
			mb.add_box(Vector3(W + ov * 2.0, 0.035, 0.08), p, roof_c.darkened(0.12), basis, 0.04)
		# okap
		mb.add_box(Vector3(W + ov * 2.0 + 0.02, 0.1, 0.1), a + nrm * 0.02 - d * 0.03 + Vector3(0, -0.04, 0), trim.darkened(0.1), Basis.IDENTITY, 0.02)
	mb.add_box(Vector3(W + ov * 2.0 + 0.05, 0.14, 0.24), Vector3(0, top + RH + th * 0.7, 0), roof_c.darkened(0.2), Basis.IDENTITY, 0.02)
	# štítová lišta
	for side: float in [-1.0, 1.0]:
		var x := side * (W * 0.5 + ov)
		for e: float in [1.0, -1.0]:
			var eave := Vector3(x, top, e * half)
			var ridge := Vector3(x, top + RH, 0)
			var basis := Basis(Vector3.RIGHT, slope if e > 0 else PI - slope)
			var nrm := Vector3(0, half, e * RH).normalized()
			mb.add_box(Vector3(0.06, 0.2, slen + ov), (eave + ridge) * 0.5 - (ridge - eave).normalized() * ov * 0.5 + nrm * 0.05, trim, basis, 0.02)


## Plochá pochozí střecha s atikou (bytové domy – kotvicí body pro lano).
func _flat_roof() -> void:
	var roof_c: Color = spec.get("roof_color", Color(0.45, 0.46, 0.48))
	var wall_c: Color = spec.get("wall_color", Color(0.94, 0.89, 0.78))
	var top := FH + WH
	var th := 0.25
	_box(Vector3(W, th, D), Vector3(0, top + th * 0.5, 0), roof_c, true)
	var ph: float = spec.get("parapet_h", 0.55)
	var pt := 0.2
	for e: float in [-1.0, 1.0]:
		_box(Vector3(W + 0.04, ph, pt), Vector3(0, top + th + ph * 0.5, e * (D * 0.5 - pt * 0.5)), wall_c, true)
		_box(Vector3(pt, ph, D - 2 * pt), Vector3(e * (W * 0.5 - pt * 0.5), top + th + ph * 0.5, 0), wall_c, true)
	var cap_c: Color = spec.get("trim_color", Color(0.97, 0.96, 0.93))
	mb.add_box(Vector3(W + 0.12, 0.06, 0.3), Vector3(0, top + th + ph + 0.03, D * 0.5 - 0.1), cap_c)
	mb.add_box(Vector3(W + 0.12, 0.06, 0.3), Vector3(0, top + th + ph + 0.03, -D * 0.5 + 0.1), cap_c)
	mb.add_box(Vector3(0.3, 0.06, D), Vector3(W * 0.5 - 0.1, top + th + ph + 0.03, 0), cap_c)
	mb.add_box(Vector3(0.3, 0.06, D), Vector3(-W * 0.5 + 0.1, top + th + ph + 0.03, 0), cap_c)


func _chimney() -> void:
	var c: Color = spec.get("chimney_color", Color(0.62, 0.36, 0.3))
	var top := FH + WH
	var cx: float = spec.get("chimney_x", W * 0.25)
	var cz := -D * 0.18
	var h := RH + 0.9
	mb.add_box(Vector3(0.5, h, 0.5), Vector3(cx, top + h * 0.5 - 0.1, cz), c)
	mb.add_box(Vector3(0.62, 0.1, 0.62), Vector3(cx, top + h - 0.1, cz), c.darkened(0.25))


# ------------------------------------------------------------------ interiér

func _interior() -> void:
	var floor_c: Color = spec.get("floor_color", Color(0.72, 0.55, 0.38))
	var in_c: Color = spec.get("interior_color", Color(0.93, 0.9, 0.84))
	mb.add_box(Vector3(W - 2 * T, 0.04, D - 2 * T), Vector3(0, FH + 0.02, 0), floor_c)
	mb.add_box(Vector3(W - 2 * T, 0.04, D - 2 * T), Vector3(0, FH + WH - 0.02, 0), in_c.lightened(0.05))
	if spec.has("styles"):
		_auto_interior(floor_c, in_c)
	for f in spec.get("furniture", []):
		var color: Color = f.get("color", Color(0.6, 0.5, 0.4))
		var kind: String = f.get("kind", "box")
		var p: Vector3 = f["pos"] + Vector3(0, FH + 0.04, 0)
		var size: Vector3 = f.get("size", Vector3.ONE * 0.5)
		match kind:
			"box":
				mb.add_box(size, p + Vector3(0, size.y * 0.5, 0), color)
			"sofa":
				mb.add_box(Vector3(size.x, 0.42, size.z), p + Vector3(0, 0.21, 0), color)
				# opěradlo o kousek užší a zapuštěné, područky o kousek přečnívají (žádné plochy v jedné rovině)
				mb.add_box(Vector3(size.x - 0.02, 0.45, 0.2), p + Vector3(0, 0.62, -size.z * 0.5 + 0.11), color.darkened(0.08))
				mb.add_box(Vector3(0.21, 0.25, size.z + 0.02), p + Vector3(-size.x * 0.5 + 0.095, 0.55, 0), color.darkened(0.05))
				mb.add_box(Vector3(0.21, 0.25, size.z + 0.02), p + Vector3(size.x * 0.5 - 0.095, 0.55, 0), color.darkened(0.05))
				for k in 3:
					mb.add_box(Vector3(size.x / 3.2, 0.1, size.z - 0.3), p + Vector3((k - 1) * size.x / 3.1, 0.47, 0.05), color.lightened(0.08))
			"table":
				mb.add_box(Vector3(size.x, 0.05, size.z), p + Vector3(0, size.y, 0), color)
				for sx2: int in [-1, 1]:
					for sz: int in [-1, 1]:
						mb.add_box(Vector3(0.05, size.y, 0.05), p + Vector3(sx2 * (size.x * 0.5 - 0.06), size.y * 0.5, sz * (size.z * 0.5 - 0.06)), color.darkened(0.15))
			"plant":
				mb.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.3, 0.32, 0.3)), p + Vector3(0, 0.16, 0)), Color(0.75, 0.42, 0.3))
				mb.add("sphere", Transform3D(Basis.from_scale(Vector3(0.6, 0.7, 0.6)), p + Vector3(0, 0.65, 0)), Color(0.3, 0.6, 0.3), 0.08)
			"lamp":
				mb.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.04, 1.5, 0.04)), p + Vector3(0, 0.75, 0)), Color(0.2, 0.2, 0.2))
				mb.add("cone7", Transform3D(Basis.from_scale(Vector3(0.45, 0.35, 0.45)), p + Vector3(0, 1.6, 0)), Color(0.98, 0.92, 0.75))
			"rug":
				mb.add_box(Vector3(size.x, 0.015, size.z), p + Vector3(0, 0.008, 0), color, Basis.IDENTITY, 0.0)
			"bed":
				mb.add_box(Vector3(size.x, 0.35, size.z), p + Vector3(0, 0.175, 0), Color(0.55, 0.38, 0.25))
				mb.add_box(Vector3(size.x - 0.06, 0.18, size.z - 0.06), p + Vector3(0, 0.44, 0), Color(0.96, 0.96, 0.94))
				mb.add_box(Vector3(size.x - 0.04, 0.06, size.z * 0.6), p + Vector3(0, 0.55, size.z * 0.18), color)
				mb.add_box(Vector3(size.x + 0.04, 0.8, 0.08), p + Vector3(0, 0.4, -size.z * 0.5), Color(0.5, 0.34, 0.22))
			"shelf":
				_shelf(p, size, color)
	if spec.has("interior_light"):
		var l := OmniLight3D.new()
		l.position = spec["interior_light"] + Vector3(0, FH, 0)
		l.light_color = Color(1.0, 0.86, 0.68)
		l.light_energy = 0.5
		l.omni_range = 7.0
		l.shadow_enabled = false
		root.add_child(l)


## Otevřený regál: zadní deska, boky, police a zboží stojící na policích
## (dřív plný kvádr se zbožím uvnitř – jeho boky blikaly přes konce regálu).
## Regál je otočený čelem do středu místnosti (úzký a hluboký, size.x < size.z, stojí bokem).
func _shelf(p: Vector3, size: Vector3, color: Color) -> void:
	var turned := size.x < size.z
	var bas := Basis.IDENTITY
	if turned:
		bas = Basis(Vector3.UP, -PI * 0.5 if p.x > 0.0 else PI * 0.5)
	elif p.z > 0.0:
		bas = Basis(Vector3.UP, PI)
	var L := size.z if turned else size.x
	var Dp := size.x if turned else size.z
	var Hh := size.y
	var board := 0.03
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(p.x) * 10.0 + absf(p.z) * 7.0)
	var at := func(local: Vector3) -> Vector3: return p + bas * local
	# zadní deska, boky, horní deska
	mb.add_box(Vector3(L, Hh, board), at.call(Vector3(0, Hh * 0.5, -Dp * 0.5 + board * 0.5)), color.darkened(0.12), bas)
	for e: float in [-1.0, 1.0]:
		mb.add_box(Vector3(board, Hh, Dp - 0.012), at.call(Vector3(e * (L * 0.5 - board * 0.5), Hh * 0.5, 0.006)), color, bas)
	var inner := L - 2.0 * board
	var levels := maxi(2, int(Hh / 0.42) + 1)
	var step := (Hh - board) / float(levels - 1)
	for k in levels:
		var y := board * 0.5 + k * step
		mb.add_box(Vector3(inner, board, Dp - board - 0.004), at.call(Vector3(0, y, board * 0.5 + 0.002)), color.lightened(0.05), bas)
		if k == levels - 1:
			break
		# zboží na polici: krabice, lahve, sklenice – kratší než mezera a s odstupem od boků
		var x := -inner * 0.5 + 0.05
		while x < inner * 0.5 - 0.1:
			var gw := rng.randf_range(0.07, 0.16)
			if x + gw > inner * 0.5 - 0.03:
				break
			if rng.randf() < 0.78:
				var gh := minf(rng.randf_range(0.12, 0.3), step - board - 0.05)
				var gd := rng.randf_range(0.5, 0.8) * (Dp - board)
				var gc := Color.from_hsv(rng.randf(), rng.randf_range(0.35, 0.7), rng.randf_range(0.6, 0.9))
				var gp := Vector3(x + gw * 0.5, y + board * 0.5 + gh * 0.5 + 0.001, Dp * 0.5 - gd * 0.5 - 0.03)
				if rng.randf() < 0.35:
					mb.add("cyl10", Transform3D(bas * Basis.from_scale(Vector3(gw, gh, gw)), at.call(gp + Vector3(0, 0, gd * 0.5 - gw * 0.5))), gc, 0.03)
				else:
					mb.add_box(Vector3(gw, gh, gd), at.call(gp), gc, bas)
			x += gw + rng.randf_range(0.015, 0.05)


# ------------------------------------------------------------------ automatický interiér (Etapa 3)
# Patra ("levels" = výšky podlah nad soklem), styl každého patra ("styles") a místnosti
# za okny: příčky mezi sloupci oken, zadní stěna místnosti a nábytek podle stylu.
# Do budov se nevchází – vše je jen vizuální (bez kolizí), aby to bylo levné.

func _levels() -> Array:
	return spec.get("levels", [0.0])


func _level_of(v: float) -> int:
	var lv := _levels()
	var k := 0
	for i in lv.size():
		if v >= float(lv[i]) - 0.05:
			k = i
	return k


func _level_h(k: int) -> float:
	var lv := _levels()
	return (float(lv[k + 1]) if k + 1 < lv.size() else WH) - float(lv[k])


## Styly místností, které jsou otevřené do sousední místnosti stejného stylu (bez příčky).
const OPEN_STYLES := ["cafe", "villa", "bakery", "flowers", "lobby", "store", "openspace"]
const BAND_MAX := 3.6      # max. hloubka místnosti od fasády
const BAND_MIN := 2.2
const CORRIDOR := 1.3      # šířka chodby mezi přední a zadní řadou místností
const DOOR_W := 0.9


## Dispozice každého patra: přední a zadní řada místností (za okny), mezi nimi chodba.
## Místnosti mají dveře do chodby (úzké místnosti dveře do sousední místnosti),
## boční okna vedou na konec chodby. Ve vícepatrových budovách je v chodbě schodiště.
func _auto_interior(floor_c: Color, in_c: Color) -> void:
	var lv := _levels()
	var styles: Array = spec.get("styles", [])
	var wall_in := in_c.darkened(0.04)
	var rooms := {}   # id okna -> styl místnosti za ním (pro testy a ladění)
	var plan := []    # popis dispozice po patrech (ladění)
	var holes := {}   # patro -> Rect2 (x, z) otvoru pro schodiště z patra pod ním
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 7)) * 31 + 5
	var x0 := -W * 0.5 + T
	var x1 := W * 0.5 - T
	var z0 := -D * 0.5 + T
	var z1 := D * 0.5 - T
	var di := z1 - z0
	var has_stairwell := false
	for side in _side_groups:
		for g in _side_groups[side]:
			for o in g[2]:
				if str(o.get("style", "")) == "stair":
					has_stairwell = true
	for k in lv.size():
		var base: float = float(lv[k])
		var h := _level_h(k)
		var lvl_style: String = str(styles[mini(k, styles.size() - 1)]) if not styles.is_empty() else "house"
		# okna tohoto patra po stranách, seskupená do sloupců
		var per := {}
		for side in _side_groups:
			var arr := []
			for g in _side_groups[side]:
				var here := []
				for o in g[2]:
					if o.get("type", "window") == "window" and _level_of(float(o.get("sill", 0.9))) == k:
						here.append(o)
				if not here.is_empty():
					arr.append([float(g[0]), float(g[1]), here])
			per[side] = arr
		var has_f: bool = not per.get("front", []).is_empty()
		var has_b: bool = not per.get("back", []).is_empty()
		# kde jsou boční okna (z v souřadnicích budovy) – chodba vede k nim
		var smin := INF
		var smax := -INF
		for side in ["left", "right"]:
			for g in per.get(side, []):
				for o in g[2]:
					var zc: float = float(o["u"]) if side == "left" else -float(o["u"])
					var hw: float = float(o["width"]) * 0.5 + 0.15
					smin = minf(smin, zc - hw)
					smax = maxf(smax, zc + hw)
		var df := 0.0
		var db := 0.0
		if has_f and has_b:
			if smin < smax:
				var m := (smin + smax) * 0.5
				var c0 := m - CORRIDOR * 0.5
				var c1 := m + CORRIDOR * 0.5
				df = clampf(z1 - c1, BAND_MIN, BAND_MAX)
				db = clampf(c0 - z0, BAND_MIN, BAND_MAX)
			else:
				df = minf(BAND_MAX, (di - CORRIDOR) * 0.5)
				db = df
			var over := df + db + 1.0 - di
			if over > 0.0:
				df -= over * 0.5
				db -= over * 0.5
		elif has_f:
			df = minf(BAND_MAX, di - 1.2)
			if smin < smax and z1 - smax >= BAND_MIN:
				df = minf(df, z1 - smax)
		elif has_b:
			db = minf(BAND_MAX, di - 1.2)
			if smin < smax and smin - z0 >= BAND_MIN:
				db = minf(db, smin - z0)
		var zf := z1 - df
		var zb := z0 + db
		# stěna řady místností nesmí narazit do bočního okna – posunout ji na zeď mezi okny
		var spans := []
		for side in ["left", "right"]:
			for g in per.get(side, []):
				for o in g[2]:
					var zc2: float = float(o["u"]) if side == "left" else -float(o["u"])
					var hw2: float = float(o["width"]) * 0.5 + FRAME + 0.1
					spans.append(Vector2(zc2 - hw2, zc2 + hw2))
		if has_f and df > 0.0:
			zf = _off_windows(zf, spans, zb + 0.9 if has_b else z0 + 0.6, z1 - 1.2)
			df = z1 - zf
		if has_b and db > 0.0:
			zb = _off_windows(zb, spans, z0 + 1.2, zf - 0.9 if has_f else z1 - 0.6)
			db = zb - z0
		plan.append({"level": k, "front": df, "back": db, "corridor": [zb, zf]})
		# --- řady místností
		for side in ["front", "back"]:
			var groups: Array = per.get(side, [])
			if groups.is_empty():
				continue
			var depth := df if side == "front" else db
			var sx := _side_xf(side)
			var bounds: Array[float] = [x0]
			for gi in range(1, groups.size()):
				bounds.append((float(groups[gi - 1][1]) + float(groups[gi][0])) * 0.5)
			bounds.append(x1)
			var rstyles := []
			for g in groups:
				rstyles.append(str(g[2][0].get("style", lvl_style)))
			var band_doors: Array[float] = []
			var room_door := []
			for gi in groups.size():
				var ra: float = bounds[gi]
				var rb: float = bounds[gi + 1]
				var du := INF
				if rb - ra >= 2.4:
					du = rb - 0.75
					band_doors.append(du)
				room_door.append(du)
			for gi in groups.size():
				var ra: float = bounds[gi]
				var rb: float = bounds[gi + 1]
				# příčka k další místnosti (otevřené styly bez příčky); úzká místnost má dveře do sousední
				if gi < groups.size() - 1:
					var open_plan: bool = rstyles[gi] == rstyles[gi + 1] and OPEN_STYLES.has(rstyles[gi])
					if not open_plan:
						var narrow: bool = room_door[gi] == INF or room_door[gi + 1] == INF
						_divider(sx, rb, depth, base, h, narrow, wall_in)
				var style: String = rstyles[gi]
				for o in groups[gi][2]:
					var uc: float = o["u"]
					_sbox(sx, Vector3(0.36, 0.05, 0.36), Vector3(uc, base + h - 0.05, -T - depth * 0.5), Color(0.98, 0.96, 0.88))
					_furnish(sx, style, uc, float(o["width"]), ra, rb, base, h, depth, rng, room_door[gi])
					if o.has("id"):
						rooms[str(o["id"])] = style
			# stěna řady do chodby s dveřmi
			if depth < di - 0.3:
				_door_wall(sx, x0, x1, -T - depth - 0.05, base, h, band_doors, wall_in.darkened(0.03))
		# --- chodba: běhoun, rostlina pod bočním oknem, schodiště
		var cz0 := zb if has_b else z0
		var cz1 := zf if has_f else z1
		if cz1 - cz0 > 0.8:
			var runner := Color.from_hsv(rng.randf(), 0.35, 0.5)
			mb.add_box(Vector3(x1 - x0 - 0.8, 0.012, minf(0.7, cz1 - cz0 - 0.3)), Vector3(0, FH + base + 0.006, (cz0 + cz1) * 0.5), runner, Basis.IDENTITY, 0.0)
		for side in ["left", "right"]:
			var sx := _side_xf(side)
			for g in per.get(side, []):
				for o in g[2]:
					var zc: float = float(o["u"]) if side == "left" else -float(o["u"])
					var in_corr := zc > cz0 and zc < cz1
					if in_corr:
						_plant(sx, float(o["u"]), base, -T - 0.4, 0.9)
					if o.has("id"):
						rooms[str(o["id"])] = "chodba" if in_corr else (lvl_style if (zc > zf and has_f) or (zc < zb and has_b) else "chodba")
		# schodiště jen do patra nad (z nejvyššího patra už nikam nevede); míří do otvoru ve stropě
		if k < lv.size() - 1 and not has_stairwell and cz1 - cz0 >= 1.0:
			var st_rect := _stair_spot(x0, x1, cz0, cz1, per)
			if st_rect.size.x > 0.0:
				var sw := st_rect.size.y
				var steps := 12
				var rise := h / steps
				var run := st_rect.size.x / steps
				# otevřené schodiště: stupně a podstupnice, šikmé schodnice a zábradlí
				# (plné kvádry vypadaly z okna na konci chodby jako stěna)
				var tread_c := Color(0.62, 0.46, 0.32)
				var zc := st_rect.position.y + sw * 0.5
				for j in steps:
					var sxc := st_rect.position.x + (j + 0.5) * run
					var top_y := FH + base + rise * (j + 1)
					mb.add_box(Vector3(run + 0.02, 0.05, sw), Vector3(sxc, top_y - 0.025, zc), tread_c)
					mb.add_box(Vector3(0.025, rise - 0.05, sw - 0.04), Vector3(sxc - run * 0.5 + 0.0125, top_y - 0.05 - (rise - 0.05) * 0.5, zc), Color(0.9, 0.89, 0.86))
				var slope := atan2(h, st_rect.size.x)
				var slen := sqrt(h * h + st_rect.size.x * st_rect.size.x)
				var mid := Vector3(st_rect.position.x + st_rect.size.x * 0.5, FH + base + h * 0.5, 0.0)
				var open_z := st_rect.end.y if st_rect.position.y < (cz0 + cz1) * 0.5 else st_rect.position.y
				var wall_z := st_rect.position.y if open_z == st_rect.end.y else st_rect.end.y
				var rb := Basis(Vector3.BACK, slope)
				for zz: float in [open_z, wall_z]:
					mb.add_box(Vector3(slen, 0.22, 0.05), Vector3(mid.x, mid.y - 0.12, zz), tread_c.darkened(0.2), rb)
				mb.add_box(Vector3(slen, 0.05, 0.05), Vector3(mid.x, mid.y + 0.85, open_z), tread_c.darkened(0.2), rb)
				for j in range(1, steps, 3):
					var px := st_rect.position.x + (j + 0.5) * run
					mb.add_box(Vector3(0.03, 0.85, 0.03), Vector3(px, FH + base + rise * (j + 1) + 0.42, open_z), tread_c.darkened(0.2))
				# otvor ve stropě nad horní polovinou schodů
				holes[k + 1] = Rect2(st_rect.position.x + st_rect.size.x * 0.45, st_rect.position.y, st_rect.size.x * 0.55, sw)
				plan[plan.size() - 1]["stairs"] = st_rect
	# stropy / podlahy pater (s otvorem pro schodiště a zábradlím kolem něj)
	for k in range(1, lv.size()):
		var y: float = FH + float(lv[k])
		var full := Rect2(-W * 0.5 + T, -D * 0.5 + T, W - 2 * T, D - 2 * T)
		var parts: Array[Rect2] = [full]
		if holes.has(k):
			var hr: Rect2 = holes[k]
			parts = [
				Rect2(full.position.x, full.position.y, hr.position.x - full.position.x, full.size.y),
				Rect2(hr.end.x, full.position.y, full.end.x - hr.end.x, full.size.y),
				Rect2(hr.position.x, full.position.y, hr.size.x, hr.position.y - full.position.y),
				Rect2(hr.position.x, hr.end.y, hr.size.x, full.end.y - hr.end.y),
			]
			var rail := Color(0.55, 0.4, 0.28)
			var rz := hr.end.y + 0.03 if hr.end.y < full.end.y - 0.05 else hr.position.y - 0.03
			mb.add_box(Vector3(hr.size.x, 0.05, 0.05), Vector3(hr.get_center().x, y + 0.95, rz), rail)
			mb.add_box(Vector3(0.05, 0.05, hr.size.y), Vector3(hr.position.x - 0.03, y + 0.95, hr.get_center().y), rail)
			for t in 5:
				mb.add_box(Vector3(0.035, 0.95, 0.035), Vector3(hr.position.x + hr.size.x * t / 4.0, y + 0.475, rz), rail)
			for t in 3:
				mb.add_box(Vector3(0.035, 0.95, 0.035), Vector3(hr.position.x - 0.03, y + 0.475, hr.position.y + hr.size.y * t / 2.0), rail)
		for r in parts:
			if r.size.x < 0.01 or r.size.y < 0.01:
				continue
			mb.add_box(Vector3(r.size.x, 0.2, r.size.y), Vector3(r.get_center().x, y - 0.1, r.get_center().y), in_c.lightened(0.04))
			mb.add_box(Vector3(r.size.x, 0.02, r.size.y), Vector3(r.get_center().x, y + 0.01, r.get_center().y), floor_c, Basis.IDENTITY, 0.0)
	root.set_meta("rooms", rooms)
	root.set_meta("plan", plan)
	if OS.get_environment("CLEARVIEW_PLAN") != "":
		print("PLAN ", spec.get("name", "?"), " W=", W, " D=", D, " ", plan)
	# světlo v každém patře (bez stínů – je to jen nádech teplého světla v oknech)
	if spec.get("level_lights", true):
		for k in lv.size():
			var l := OmniLight3D.new()
			l.position = Vector3(0, FH + float(lv[k]) + _level_h(k) * 0.8, 0)
			l.light_color = Color(1.0, 0.88, 0.7)
			l.light_energy = 0.45
			l.omni_range = maxf(W, D) * 0.75
			l.shadow_enabled = false
			root.add_child(l)


## Posune polohu příčky z tak, aby neležela v žádném rozpětí bočního okna
## (spans: Vector2(od, do)); zůstane v mezích lo..hi. Když to nejde, vrátí původní z.
func _off_windows(z: float, spans: Array, lo: float, hi: float) -> float:
	var hit := false
	for sp in spans:
		if z > sp.x and z < sp.y:
			hit = true
	if not hit:
		return z
	var cands: Array[float] = []
	for sp in spans:
		cands.append(sp.x - 0.01)
		cands.append(sp.y + 0.01)
	var best := z
	var best_d := INF
	for c in cands:
		if c < lo or c > hi:
			continue
		var inside := false
		for sp in spans:
			if c > sp.x and c < sp.y:
				inside = true
		if inside:
			continue
		if absf(c - z) < best_d:
			best_d = absf(c - z)
			best = c
	return best


## Kde v chodbě stojí schodiště: podél stěny chodby, mimo dveře místností a mimo
## boční okna (aby nezakrývalo výhled oknem na konci chodby). Vrací Rect2(x, z, délka, šířka),
## prázdný Rect2, když se nikam nevejde.
func _stair_spot(x0: float, x1: float, cz0: float, cz1: float, per: Dictionary) -> Rect2:
	var length := 3.1
	var sw := minf(0.95, cz1 - cz0 - 0.35)
	if sw < 0.6 or x1 - x0 < length + 1.6:
		return Rect2()
	# dveře do chodby: přední řada je v souřadnicích strany "front" (u = x), zadní "back" (u = -x)
	var doors_b: Array[float] = []
	var doors_f: Array[float] = []
	for side in ["front", "back"]:
		var groups: Array = per.get(side, [])
		if groups.is_empty():
			continue
		var bounds: Array[float] = [x0]
		for gi in range(1, groups.size()):
			bounds.append((float(groups[gi - 1][1]) + float(groups[gi][0])) * 0.5)
		bounds.append(x1)
		for gi in groups.size():
			if bounds[gi + 1] - bounds[gi] >= 2.4:
				var du: float = bounds[gi + 1] - 0.75
				if side == "front":
					doors_f.append(du)
				else:
					doors_b.append(-du)
	for wall in [0, 1]:
		var doors := doors_b if wall == 0 else doors_f
		var z := cz0 + 0.05 if wall == 0 else cz1 - 0.05 - sw
		# kandidáti od středu ven
		var cands: Array[float] = []
		var span := x1 - x0 - 1.2 - length
		for i in 9:
			var t := 0.5 + ceilf(i / 2.0) * (0.12 if i % 2 == 1 else -0.12)
			cands.append(x0 + 0.6 + span * clampf(t, 0.0, 1.0))
		for sx0: float in cands:
			var ok := true
			for du: float in doors:
				if du > sx0 - DOOR_W * 0.5 - 0.2 and du < sx0 + length + DOOR_W * 0.5 + 0.2:
					ok = false
			if ok:
				return Rect2(sx0, z, length, sw)
	return Rect2()


## Stěna v lokálních souřadnicích strany (u0..u1, ve vzdálenosti z) s otvory pro dveře.
func _door_wall(sx: Transform3D, u0: float, u1: float, z: float, base: float, h: float, doors: Array[float], color: Color) -> void:
	var dh := minf(2.1, h - 0.25)
	var cur := u0
	var ds := doors.duplicate()
	ds.sort()
	for du: float in ds:
		var a := du - DOOR_W * 0.5
		if a > cur + 0.01:
			_sbox(sx, Vector3(a - cur, h, 0.1), Vector3((cur + a) * 0.5, base + h * 0.5, z), color)
		_sbox(sx, Vector3(DOOR_W, h - dh, 0.1), Vector3(du, base + dh + (h - dh) * 0.5, z), color)
		for e: float in [-1.0, 1.0]:
			_sbox(sx, Vector3(0.06, dh, 0.14), Vector3(du + e * (DOOR_W * 0.5 - 0.03), base + dh * 0.5, z), Color(0.55, 0.4, 0.28))
		_sbox(sx, Vector3(DOOR_W, 0.06, 0.14), Vector3(du, base + dh - 0.03, z), Color(0.55, 0.4, 0.28))
		cur = du + DOOR_W * 0.5
	if u1 > cur + 0.01:
		_sbox(sx, Vector3(u1 - cur, h, 0.1), Vector3((cur + u1) * 0.5, base + h * 0.5, z), color)


## Příčka mezi místnostmi (kolmo k fasádě), volitelně s dveřmi u chodby.
func _divider(sx: Transform3D, u: float, depth: float, base: float, h: float, door: bool, color: Color) -> void:
	var za := -T
	var zb := -T - depth
	if not door or depth < 1.6:
		_sbox(sx, Vector3(0.1, h, depth), Vector3(u, base + h * 0.5, (za + zb) * 0.5), color)
		return
	var dh := minf(2.1, h - 0.25)
	var dc := zb + 0.7
	var d0 := dc - DOOR_W * 0.5
	var d1 := dc + DOOR_W * 0.5
	_sbox(sx, Vector3(0.1, h, za - d1), Vector3(u, base + h * 0.5, (za + d1) * 0.5), color)
	if d0 - zb > 0.01:
		_sbox(sx, Vector3(0.1, h, d0 - zb), Vector3(u, base + h * 0.5, (d0 + zb) * 0.5), color)
	_sbox(sx, Vector3(0.1, h - dh, DOOR_W), Vector3(u, base + dh + (h - dh) * 0.5, dc), color)
	_sbox(sx, Vector3(0.14, 0.06, DOOR_W), Vector3(u, base + dh - 0.03, dc), Color(0.55, 0.4, 0.28))


## Střed předmětu šířky w co nejblíž u, aby se vešel do volného úseku a..b.
func _cb(u: float, w: float, a: float, b: float) -> float:
	if b - a <= w:
		return (a + b) * 0.5
	return clampf(u, a + w * 0.5, b - w * 0.5)


## Bod v lokálních souřadnicích strany (u podél zdi, v výška, z dovnitř = záporné).
func _sp(sx: Transform3D, u: float, v: float, z: float) -> Vector3:
	return sx * Vector3(u, v, z)


func _prim(sx: Transform3D, kind: String, scale: Vector3, local: Vector3, color: Color) -> void:
	mb.add(kind, Transform3D(sx.basis * Basis.from_scale(scale), sx * local), color, 0.03)


## Židle; `face` = směr (u, z), kam sedící kouká (ke stolu). Opěradlo je na opačné straně.
func _chair(sx: Transform3D, u: float, base: float, z: float, face: Vector2, color: Color) -> void:
	_sbox(sx, Vector3(0.42, 0.05, 0.42), Vector3(u, base + 0.45, z), color)
	var bsize := Vector3(0.04, 0.45, 0.42) if absf(face.x) > absf(face.y) else Vector3(0.42, 0.45, 0.04)
	_sbox(sx, bsize, Vector3(u - face.x * 0.19, base + 0.7, z - face.y * 0.19), color.darkened(0.1))
	for a: float in [-0.17, 0.17]:
		for b: float in [-0.17, 0.17]:
			_sbox(sx, Vector3(0.04, 0.45, 0.04), Vector3(u + a, base + 0.22, z + b), color.darkened(0.2))


func _table(sx: Transform3D, u: float, base: float, z: float, size: Vector3, color: Color) -> void:
	_sbox(sx, Vector3(size.x, 0.05, size.z), Vector3(u, base + size.y, z), color)
	for a: float in [-1.0, 1.0]:
		for b: float in [-1.0, 1.0]:
			_sbox(sx, Vector3(0.05, size.y, 0.05), Vector3(u + a * (size.x * 0.5 - 0.06), base + size.y * 0.5, z + b * (size.z * 0.5 - 0.06)), color.darkened(0.2))


func _plant(sx: Transform3D, u: float, base: float, z: float, s: float = 1.0) -> void:
	_prim(sx, "cyl10", Vector3(0.3, 0.3, 0.3) * s, Vector3(u, base + 0.15 * s, z), Color(0.75, 0.42, 0.3))
	_prim(sx, "sphere", Vector3(0.55, 0.7, 0.55) * s, Vector3(u, base + 0.65 * s, z), Color(0.3, 0.58, 0.3))


func _picture(sx: Transform3D, u: float, v: float, z: float, rng: RandomNumberGenerator) -> void:
	_sbox(sx, Vector3(0.7, 0.5, 0.03), Vector3(u, v, z), Color(0.35, 0.25, 0.18))
	_sbox(sx, Vector3(0.6, 0.4, 0.01), Vector3(u, v, z + 0.02), Color.from_hsv(rng.randf(), 0.35, 0.85), false)


## Nábytek za oknem podle stylu místnosti.
func _furnish(sx: Transform3D, style: String, uc: float, w: float, ra: float, rb: float, base: float, h: float, depth: float, rng: RandomNumberGenerator, door_u: float = INF) -> void:
	var fz := -T - 0.02                 # u vnější zdi (pod oknem)
	var back := -T - depth + 0.08       # u zadní stěny místnosti
	var wood := Color(0.6, 0.42, 0.28)
	var room_w := rb - ra
	# u zadní stěny musí zůstat volno u dveří do chodby
	var bra := ra
	var brb := rb
	if door_u != INF:
		if door_u > (ra + rb) * 0.5:
			brb = door_u - DOOR_W * 0.5 - 0.1
		else:
			bra = door_u + DOOR_W * 0.5 + 0.1
	var bw := brb - bra
	var bm := (bra + brb) * 0.5
	if room_w < 2.4 and depth < 2.3 and (style == "house" or style == "flat"):
		style = "study_small"
	# podlahová lišta / koberec dodá místnosti barvu
	match style:
		"house", "flat":
			var pick := rng.randi() % 4
			if pick == 1 and depth < 2.4:
				pick = 0   # postel by se do mělké místnosti nevešla
			if pick == 0:   # obývák
				var sofa := Color.from_hsv(rng.randf(), 0.35, 0.6)
				var sw := minf(2.0, bw - 0.2)
				var sc := _cb(uc, sw, bra, brb)
				_sbox(sx, Vector3(sw, 0.42, 0.85), Vector3(sc, base + 0.21, back + 0.45), sofa)
				_sbox(sx, Vector3(sw, 0.45, 0.2), Vector3(sc, base + 0.62, back + 0.1), sofa.darkened(0.1))
				_sbox(sx, Vector3(0.9, 0.38, 0.5), Vector3(sc, base + 0.19, back + 1.45), wood)
				_sbox(sx, Vector3(minf(2.2, room_w - 0.3), 0.015, 1.6), Vector3(sc, base + 0.05, back + 1.1), Color.from_hsv(rng.randf(), 0.4, 0.55))
				_picture(sx, sc, base + 1.6, back - 0.02, rng)
				_prim(sx, "cyl6", Vector3(0.04, 1.4, 0.04), Vector3(ra + 0.35, base + 0.7, fz - 0.35), Color(0.2, 0.2, 0.2))
				_prim(sx, "cone7", Vector3(0.4, 0.3, 0.4), Vector3(ra + 0.35, base + 1.5, fz - 0.35), Color(0.98, 0.92, 0.75))
			elif pick == 1: # ložnice
				var bed := Color.from_hsv(rng.randf(), 0.4, 0.7)
				var bc := _cb(uc, 1.5, bra, brb)
				_sbox(sx, Vector3(1.5, 0.4, 2.0), Vector3(bc, base + 0.2, back + 1.0), Color(0.55, 0.38, 0.25))
				_sbox(sx, Vector3(1.44, 0.16, 1.94), Vector3(bc, base + 0.48, back + 1.0), Color(0.96, 0.96, 0.94))
				_sbox(sx, Vector3(1.48, 0.07, 1.2), Vector3(bc, base + 0.58, back + 1.35), bed)
				_sbox(sx, Vector3(1.5, 0.9, 0.08), Vector3(bc, base + 0.45, back + 0.0), Color(0.5, 0.34, 0.22))
				_sbox(sx, Vector3(0.9, 1.9, 0.55), Vector3(ra + 0.55, base + 0.95, fz - 0.35), wood.lightened(0.1))
				_picture(sx, bc, base + 1.55, back - 0.02, rng)
			elif pick == 2: # kuchyň
				_sbox(sx, Vector3(bw - 0.85, 0.9, 0.6), Vector3(bm - 0.35, base + 0.45, back + 0.3), Color(0.92, 0.92, 0.9))
				_sbox(sx, Vector3(bw - 0.85, 0.04, 0.62), Vector3(bm - 0.35, base + 0.92, back + 0.3), Color(0.3, 0.3, 0.32))
				_sbox(sx, Vector3(bw - 0.85, 0.7, 0.35), Vector3(bm - 0.35, base + 1.75, back + 0.18), Color(0.85, 0.85, 0.83))
				_sbox(sx, Vector3(0.65, 1.85, 0.65), Vector3(brb - 0.37, base + 0.92, back + 0.34), Color(0.95, 0.95, 0.96))
				_table(sx, uc, base, back + 1.6, Vector3(1.1, 0.74, 0.8), wood)
				_chair(sx, uc - 0.8, base, back + 1.6, Vector2(1, 0), wood.darkened(0.1))
				_chair(sx, uc + 0.8, base, back + 1.6, Vector2(-1, 0), wood.darkened(0.1))
			else:           # pracovna
				_table(sx, uc, base, fz - 0.45, Vector3(1.3, 0.74, 0.65), wood.lightened(0.15))
				_sbox(sx, Vector3(0.55, 0.36, 0.04), Vector3(uc, base + 0.98, fz - 0.6), Color(0.12, 0.12, 0.14))
				_chair(sx, uc, base, fz - 1.1, Vector2(0, 1), Color(0.2, 0.22, 0.25))
				var shc := _cb(uc, minf(1.8, bw - 0.2), bra, brb)
				_sbox(sx, Vector3(minf(1.8, bw - 0.2), 1.9, 0.35), Vector3(shc, base + 0.95, back + 0.18), wood)
				for j in 10:
					_sbox(sx, Vector3(0.08, rng.randf_range(0.18, 0.3), 0.26), Vector3(shc - 0.7 + j * 0.15, base + 1.25, back + 0.2), Color.from_hsv(rng.randf(), 0.45, 0.75))
				_plant(sx, ra + 0.4, base, fz - 0.4, 0.8)
		"openspace":
			# kancelář: dva pracovní stoly u okna, skříňky a květina
			var desk := Color(0.92, 0.92, 0.9)
			for t2 in 2:
				var du := uc + (t2 - 0.5) * minf(w * 0.5, 1.7)
				_table(sx, du, base, fz - 0.55, Vector3(1.4, 0.74, 0.7), desk)
				_sbox(sx, Vector3(0.55, 0.36, 0.04), Vector3(du, base + 1.0, fz - 0.75), Color(0.1, 0.1, 0.12))
				_chair(sx, du, base, fz - 1.25, Vector2(0, 1), Color(0.2, 0.3, 0.45))
			_sbox(sx, Vector3(minf(2.4, bw - 0.3), 1.2, 0.45), Vector3(bm, base + 0.6, back + 0.23), Color(0.62, 0.64, 0.66))
			_plant(sx, bra + 0.4, base + 1.2, back + 0.25, 0.7)
			_sbox(sx, Vector3(1.2, 0.8, 0.03), Vector3(_cb(uc, 1.2, bra, brb), base + 1.75, back - 0.02), Color(0.95, 0.95, 0.97))
		"lobby":
			# vstupní hala: recepční pult, pohovky, velké květiny
			_sbox(sx, Vector3(minf(3.0, bw - 0.4), 1.1, 0.7), Vector3(bm, base + 0.55, back + 0.9), Color(0.35, 0.28, 0.22))
			_sbox(sx, Vector3(minf(3.0, bw - 0.4), 0.06, 0.78), Vector3(bm, base + 1.12, back + 0.9), Color(0.9, 0.88, 0.84))
			_sbox(sx, Vector3(1.8, 0.4, 0.8), Vector3(uc, base + 0.2, fz - 0.9), Color(0.2, 0.35, 0.45))
			_sbox(sx, Vector3(1.8, 0.4, 0.18), Vector3(uc, base + 0.55, fz - 1.25), Color(0.18, 0.3, 0.4))
			_plant(sx, ra + 0.5, base, fz - 0.5, 1.6)
			_plant(sx, rb - 0.5, base, fz - 0.5, 1.6)
			_sbox(sx, Vector3(2.4, 0.015, 1.6), Vector3(uc, base + 0.05, fz - 1.4), Color(0.75, 0.6, 0.35))
		"hotel":
			# hotelový pokoj: postel u zdi, noční stolek, stolek s televizí a křeslo u okna
			var bedc := Color.from_hsv(rng.randf(), 0.25, 0.85)
			var hb := _cb(uc, 1.6, bra, brb)
			_sbox(sx, Vector3(1.6, 0.4, 2.0), Vector3(hb, base + 0.2, back + 1.0), Color(0.45, 0.32, 0.22))
			_sbox(sx, Vector3(1.54, 0.16, 1.94), Vector3(hb, base + 0.48, back + 1.0), Color(0.97, 0.97, 0.96))
			_sbox(sx, Vector3(1.58, 0.06, 1.0), Vector3(hb, base + 0.58, back + 1.45), bedc)
			_sbox(sx, Vector3(1.8, 1.0, 0.08), Vector3(hb, base + 0.6, back), Color(0.4, 0.28, 0.2))
			_sbox(sx, Vector3(0.45, 0.5, 0.4), Vector3(hb + 1.1, base + 0.25, back + 0.25), Color(0.45, 0.32, 0.22))
			_prim(sx, "cone7", Vector3(0.25, 0.25, 0.25), Vector3(hb + 1.1, base + 0.62, back + 0.25), Color(0.98, 0.92, 0.75))
			_sbox(sx, Vector3(0.75, 0.42, 0.75), Vector3(ra + 0.6, base + 0.21, fz - 0.6), Color(0.55, 0.3, 0.28))
			_sbox(sx, Vector3(0.75, 0.4, 0.15), Vector3(ra + 0.6, base + 0.6, fz - 0.95), Color(0.5, 0.27, 0.25))
		"store":
			# obchodní dům: figuríny a stojany s oblečením ve výloze, regály vzadu
			for k in 3:
				var mu := uc + (k - 1) * minf(w * 0.3, 1.1)
				var col := Color.from_hsv(rng.randf(), 0.5, 0.75)
				_prim(sx, "cyl10", Vector3(0.3, 0.04, 0.3), Vector3(mu, base + 0.035, fz - 0.6), Color(0.3, 0.3, 0.32))
				_prim(sx, "cyl6", Vector3(0.03, 0.9, 0.03), Vector3(mu, base + 0.45, fz - 0.6), Color(0.3, 0.3, 0.32))
				_sbox(sx, Vector3(0.38, 0.6, 0.22), Vector3(mu, base + 1.2, fz - 0.6), col)
				_prim(sx, "sphere", Vector3(0.2, 0.24, 0.2), Vector3(mu, base + 1.65, fz - 0.6), Color(0.92, 0.9, 0.86))
			_sbox(sx, Vector3(bw - 0.3, 1.9, 0.45), Vector3(bm, base + 0.95, back + 0.23), Color(0.85, 0.85, 0.83))
			for j in int((bw - 0.6) / 0.35):
				_sbox(sx, Vector3(0.28, 0.4, 0.3), Vector3(bra + 0.4 + j * 0.35, base + 1.3, back + 0.3), Color.from_hsv(rng.randf(), 0.45, 0.8))
				_sbox(sx, Vector3(0.28, 0.4, 0.3), Vector3(bra + 0.4 + j * 0.35, base + 0.6, back + 0.3), Color.from_hsv(rng.randf(), 0.45, 0.8))
			_prim(sx, "cyl6", Vector3(0.03, 1.4, 0.03), Vector3(uc, base + 0.7, fz - 1.8), Color(0.6, 0.6, 0.62))
			_sbox(sx, Vector3(1.2, 0.03, 0.03), Vector3(uc, base + 1.4, fz - 1.8), Color(0.6, 0.6, 0.62))
			for j in 6:
				_sbox(sx, Vector3(0.12, 0.7, 0.35), Vector3(uc - 0.5 + j * 0.2, base + 1.02, fz - 1.8), Color.from_hsv(rng.randf(), 0.4, 0.7))
		"study_small":
			_table(sx, uc, base, fz - 0.45, Vector3(minf(1.2, room_w - 0.4), 0.74, 0.6), wood.lightened(0.15))
			_chair(sx, uc, base, fz - 1.0, Vector2(0, 1), Color(0.2, 0.22, 0.25))
			_plant(sx, ra + 0.3, base, fz - 0.3, 0.8)
		"villa":
			var vc := _cb(uc, 2.4, bra, brb)
			_sbox(sx, Vector3(2.4, 0.38, 0.9), Vector3(vc, base + 0.19, back + 0.5), Color(0.55, 0.56, 0.58))
			_sbox(sx, Vector3(2.4, 0.4, 0.18), Vector3(vc, base + 0.58, back + 0.09), Color(0.5, 0.51, 0.53))
			_sbox(sx, Vector3(1.0, 0.3, 0.6), Vector3(vc, base + 0.15, back + 1.6), Color(0.15, 0.15, 0.16))
			_sbox(sx, Vector3(2.8, 0.015, 2.0), Vector3(vc, base + 0.05, back + 1.2), Color(0.85, 0.83, 0.78))
			_plant(sx, rb - 0.5, base, fz - 0.5, 1.4)
			_prim(sx, "cyl6", Vector3(0.03, 1.7, 0.03), Vector3(bra + 0.4, base + 0.85, back + 0.4), Color(0.1, 0.1, 0.1))
			_prim(sx, "sphere", Vector3(0.35, 0.35, 0.35), Vector3(bra + 0.4, base + 1.75, back + 0.4), Color(1.0, 0.95, 0.82))
			_sbox(sx, Vector3(1.4, 0.8, 0.04), Vector3(vc, base + 1.5, back - 0.02), Color(0.2, 0.35, 0.5))
		"villa_up":
			var vu := _cb(uc, 2.0, bra, brb)
			_sbox(sx, Vector3(1.8, 0.35, 2.1), Vector3(vu, base + 0.18, back + 1.05), Color(0.25, 0.25, 0.27))
			_sbox(sx, Vector3(1.74, 0.16, 2.04), Vector3(vu, base + 0.43, back + 1.05), Color(0.97, 0.97, 0.96))
			_sbox(sx, Vector3(1.78, 0.06, 1.1), Vector3(vu, base + 0.53, back + 1.5), Color(0.75, 0.68, 0.58))
			_sbox(sx, Vector3(2.0, 1.0, 0.08), Vector3(vu, base + 0.6, back), Color(0.62, 0.45, 0.3))
			_plant(sx, rb - 0.45, base, fz - 0.45, 1.0)
		"cafe":
			for t in 2:
				var tu := uc + (t - 0.5) * minf(w * 0.55, 1.6)
				_prim(sx, "cyl10", Vector3(0.7, 0.04, 0.7), Vector3(tu, base + 0.75, fz - 0.7), Color(0.95, 0.93, 0.88))
				_prim(sx, "cyl6", Vector3(0.06, 0.74, 0.06), Vector3(tu, base + 0.37, fz - 0.7), Color(0.2, 0.2, 0.22))
				_chair(sx, tu - 0.55, base, fz - 0.7, Vector2(1, 0), Color(0.35, 0.22, 0.15))
				_chair(sx, tu + 0.55, base, fz - 0.7, Vector2(-1, 0), Color(0.35, 0.22, 0.15))
				_prim(sx, "cyl6", Vector3(0.015, 0.8, 0.015), Vector3(tu, base + h - 0.4, fz - 0.7), Color(0.15, 0.15, 0.15))
				_prim(sx, "cone7", Vector3(0.35, 0.25, 0.35), Vector3(tu, base + h - 0.85, fz - 0.7), Color(0.95, 0.75, 0.35))
			_sbox(sx, Vector3(bw - 0.3, 1.05, 0.7), Vector3(bm, base + 0.52, back + 0.9), Color(0.45, 0.3, 0.2))
			_sbox(sx, Vector3(bw - 0.3, 0.05, 0.74), Vector3(bm, base + 1.07, back + 0.9), Color(0.85, 0.82, 0.76))
			_sbox(sx, Vector3(0.45, 0.45, 0.35), Vector3(bm + 0.4, base + 1.32, back + 0.9), Color(0.7, 0.72, 0.75))
			_sbox(sx, Vector3(1.6, 0.9, 0.04), Vector3(_cb(uc, 1.6, bra, brb), base + 1.9, back - 0.02), Color(0.12, 0.14, 0.13))
			for j in 4:
				_sbox(sx, Vector3(1.1, 0.04, 0.01), Vector3(_cb(uc, 1.6, bra, brb), base + 2.15 - j * 0.16, back + 0.0), Color(0.95, 0.95, 0.9), false)
		"bakery":
			_sbox(sx, Vector3(room_w - 0.6, 0.95, 0.6), Vector3((ra + rb) * 0.5, base + 0.48, fz - 1.4), Color(0.6, 0.42, 0.28))
			_sbox(sx, Vector3(room_w - 0.6, 0.35, 0.55), Vector3((ra + rb) * 0.5, base + 1.13, fz - 1.4), Color(0.8, 0.9, 0.95))
			_sbox(sx, Vector3(bw - 0.2, 1.8, 0.4), Vector3(bm, base + 0.9, back + 0.2), wood)
			for k in 3:
				for j in int((bw - 0.6) / 0.3):
					_prim(sx, "sphere", Vector3(0.24, 0.14, 0.16), Vector3(bra + 0.45 + j * 0.3, base + 0.6 + k * 0.5, back + 0.25), Color(0.78, 0.55, 0.28).darkened(rng.randf() * 0.2))
		"flowers":
			var fc := [Color(0.92, 0.3, 0.35), Color(0.98, 0.75, 0.25), Color(0.85, 0.45, 0.8), Color(1, 1, 1), Color(0.95, 0.5, 0.2)]
			for j in int(room_w / 0.5):
				var bu := ra + 0.3 + j * 0.5
				_prim(sx, "cyl10", Vector3(0.3, 0.4, 0.3), Vector3(bu, base + 0.2, fz - 0.5), Color(0.35, 0.4, 0.45))
				for q in 5:
					_prim(sx, "sphere", Vector3.ONE * 0.12, Vector3(bu + rng.randf_range(-0.1, 0.1), base + 0.5 + rng.randf() * 0.25, fz - 0.5 + rng.randf_range(-0.1, 0.1)), fc[rng.randi() % fc.size()])
			_sbox(sx, Vector3(bw - 0.2, 1.6, 0.4), Vector3(bm, base + 0.8, back + 0.2), wood.lightened(0.15))
			for j in int((bw - 0.6) / 0.4):
				_plant(sx, bra + 0.5 + j * 0.4, base + 1.0, back + 0.25, 0.5)
		"classroom":
			for r in 2:
				for c in 2:
					var du := uc + (c - 0.5) * 1.3
					var dz := fz - 0.9 - r * 1.2
					_table(sx, du, base, dz, Vector3(1.1, 0.72, 0.55), Color(0.75, 0.6, 0.4))
					_chair(sx, du - 0.25, base, dz + 0.5, Vector2(0, -1), Color(0.2, 0.45, 0.65))
					_chair(sx, du + 0.25, base, dz + 0.5, Vector2(0, -1), Color(0.2, 0.45, 0.65))
			_sbox(sx, Vector3(minf(2.6, bw - 0.2), 1.1, 0.05), Vector3(_cb(uc, minf(2.6, bw - 0.2), bra, brb), base + 1.5, back), Color(0.15, 0.32, 0.22))
			for j in 2:
				_sbox(sx, Vector3(0.5, 0.65, 0.02), Vector3(ra + 0.4 + j * 0.65, base + 1.6, back + 0.02), Color.from_hsv(rng.randf(), 0.45, 0.9), false)
		"office":
			_table(sx, uc, base, fz - 0.6, Vector3(1.5, 0.74, 0.75), Color(0.85, 0.85, 0.83))
			_sbox(sx, Vector3(0.6, 0.38, 0.04), Vector3(uc - 0.3, base + 1.0, fz - 0.8), Color(0.1, 0.1, 0.12))
			_chair(sx, uc, base, fz - 1.3, Vector2(0, 1), Color(0.15, 0.15, 0.17))
			_sbox(sx, Vector3(0.5, 1.3, 0.6), Vector3(brb - 0.3, base + 0.65, back + 0.3), Color(0.6, 0.62, 0.64))
			_plant(sx, bra + 0.4, base, back + 0.4, 1.1)
		"stair":
			for j in 9:
				_sbox(sx, Vector3(1.2, 0.18, 0.3), Vector3(_cb(uc, 2.3, bra, brb) - 1.0 + j * 0.25, base + 0.09 + j * 0.18, back + 0.6), Color(0.7, 0.7, 0.7))
			_sbox(sx, Vector3(2.4, 0.05, 0.05), Vector3(_cb(uc, 2.3, bra, brb), base + 1.3, back + 0.1), Color(0.3, 0.3, 0.32))

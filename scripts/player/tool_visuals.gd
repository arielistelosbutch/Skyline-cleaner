class_name ToolVisuals
extends RefCounted
## Procedurální modely nástrojů – pro pohled z první osoby (HeldItems)
## i pro pracovní režim u skla (HandRig). Až budou hotové modely,
## stačí vrátit jiné meshe odsud.

const SKIN := Color(0.93, 0.74, 0.6)


const GLOVE := Color(0.84, 0.85, 0.87)
const GLOVE_PALM := Color(0.22, 0.38, 0.6)
const CUFF := Color(0.95, 0.55, 0.16)


## Úchop v pracovní rukavici kolem rukojeti. V lokálních souřadnicích xf vede
## rukojeť po ose Y (poloměr r), dlaň je vpravo vzadu (+X, +Z), prsty ji obejmou zepředu.
static func grip_hand(b: MeshBuilder, at, r: float) -> void:
	var xf: Transform3D = at if at is Transform3D else Transform3D(Basis.IDENTITY, at)
	var R := r + 0.01
	var pc := Vector3(R * 0.8 + 0.018, -0.004, R * 0.55 + 0.012)
	var pb := xf.basis * Basis(Vector3.UP, 0.6)
	b.add("sphere_hi", Transform3D(pb * Basis.from_scale(Vector3(0.042, 0.088, 0.066)), xf * pc), GLOVE, 0.0)
	b.add("sphere", Transform3D(pb * Basis.from_scale(Vector3(0.02, 0.074, 0.056)), xf * (pc - Vector3(0.012, 0, 0.008))), GLOVE_PALM, 0.0)
	# čtyři prsty obtočené kolem rukojeti (klouby jako kuličky, články jako válečky)
	for f in 4:
		var y := 0.033 - f * 0.022
		var fr := 0.0105 - f * 0.0007
		var prev := xf * Vector3(R * 0.9 + 0.008, y, R * 0.55)
		var angs := [0.25, -0.55, -1.45, -2.3]
		for k in angs.size():
			var ang: float = angs[k]
			var p := xf * Vector3(cos(ang) * R, y, sin(ang) * R)
			_limb(b, prev, p, fr, GLOVE if k < 2 else GLOVE_PALM)
			b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * fr * 2.1), p), GLOVE, 0.0)
			prev = p
	# palec přes prsty
	var t0 := xf * Vector3(R * 0.3, 0.03, R + 0.01)
	var t1 := xf * Vector3(-R - 0.004, 0.05, 0.004)
	var t2 := xf * Vector3(-R * 0.4, 0.056, -R - 0.002)
	_limb(b, t0, t1, 0.012, GLOVE)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.025), t1), GLOVE, 0.0)
	_limb(b, t1, t2, 0.011, GLOVE)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.022), t2), GLOVE_PALM, 0.0)


## Samostatný mesh úchopu (osa rukojeti = Y, střed v počátku) pro pracovní režim.
static func grip_mesh(r: float) -> ArrayMesh:
	var b := MeshBuilder.new(12)
	grip_hand(b, Vector3.ZERO, r)
	return b.commit()


## Báze pro úchop tyče/rukojeti mířící směrem axis (dlaň ke kameře, vpravo).
static func grip_basis(axis: Vector3) -> Basis:
	return MeshBuilder.basis_y(axis) * Basis(Vector3.UP, PI)


## Plochá dlaň v rukavici: zaoblený kvádr (lokálně X = šířka, Y = hřbet ruky,
## prsty míří do -Z) s mírně klenutým hřbetem. Sdílí ji hadr v ruce i HandRig.
static func palm(b: MeshBuilder, xf: Transform3D) -> void:
	const W := 0.056
	const L := 0.064
	const T := 0.028
	const R := 0.014
	var bs := xf.basis
	b.add_box(Vector3(W, T, L), xf.origin, GLOVE, bs, 0.0)
	b.add_box(Vector3(W + R * 2.0, T * 0.72, L), xf.origin, GLOVE, bs, 0.0)
	b.add_box(Vector3(W, T * 0.72, L + R * 2.0), xf.origin, GLOVE, bs, 0.0)
	for e: float in [-1.0, 1.0]:
		# zaoblené boky a hrana u kloubů / zápěstí
		b.add("cyl10", Transform3D(bs * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(R * 2.0, L, T)), xf * Vector3(e * W * 0.5, 0, 0)), GLOVE, 0.0)
		b.add("cyl10", Transform3D(bs * Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(T, W, R * 2.0)), xf * Vector3(0, 0, e * L * 0.5)), GLOVE, 0.0)
		for f: float in [-1.0, 1.0]:
			b.add("sphere", Transform3D(bs * Basis.from_scale(Vector3(R * 2.0, T, R * 2.0)), xf * Vector3(e * W * 0.5, 0, f * L * 0.5)), GLOVE, 0.0)
	b.add("sphere_hi", Transform3D(bs * Basis.from_scale(Vector3(W + 0.012, 0.022, L + 0.01)), xf * Vector3(0, T * 0.5 - 0.004, 0)), GLOVE, 0.0)


## Dlaň v rukavici položená shora na hadru / houbičce (prsty míří do -Z).
static func flat_hand(b: MeshBuilder, at: Vector3) -> void:
	palm(b, Transform3D(Basis.IDENTITY, at))
	for f in 4:
		var x := -0.03 + f * 0.02
		var length: float = [0.05, 0.058, 0.055, 0.045][f]
		var k0 := at + Vector3(x, 0.002, -0.038)
		var k1 := k0 + Vector3((f - 1.5) * 0.004, -0.004, -length * 0.55)
		var k2 := k1 + Vector3((f - 1.5) * 0.003, -0.01, -length * 0.45)
		b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.022), k0), GLOVE, 0.0)
		_limb(b, k0, k1, 0.0095, GLOVE)
		b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.019), k1), GLOVE, 0.0)
		_limb(b, k1, k2, 0.0088, GLOVE)
		b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.017), k2), GLOVE_PALM, 0.0)
	var t0 := at + Vector3(-0.04, -0.004, 0.0)
	var t1 := t0 + Vector3(-0.025, -0.012, -0.03)
	_limb(b, t0, t1, 0.012, GLOVE)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.022), t1), GLOVE_PALM, 0.0)


## Předloktí od zápěstí ke kameře: oranžová manžeta rukavice a rukáv pracovní bundy.
static func forearm(b: MeshBuilder, wrist: Vector3, toward: Vector3) -> void:
	var d := (toward - wrist).normalized()
	var cuff_end := wrist + d * 0.05
	_limb(b, wrist - d * 0.01, cuff_end, 0.036, CUFF)
	_limb(b, cuff_end, cuff_end + d * 0.02, 0.041, Cosmetics.sleeve().darkened(0.25))
	_limb(b, cuff_end + d * 0.02, toward, 0.044, Cosmetics.sleeve())


## Váleček z bodu a do bodu b o poloměru r.
static func _limb(b: MeshBuilder, from: Vector3, to: Vector3, r: float, c: Color, kind: String = "cyl10") -> void:
	var dv := to - from
	var l := dv.length()
	if l < 0.0005:
		return
	b.add(kind, Transform3D(MeshBuilder.basis_y(dv) * Basis.from_scale(Vector3(r * 2.0, l, r * 2.0)), (from + to) * 0.5), c, 0.0)


## Model v ruce před kamerou (včetně ruky v rukavici a rukávu).
static func held(t: ToolData) -> Node3D:
	if t.reach_bonus > 0.0:
		return _held_pole(t)
	var root := Node3D.new()
	var arm_dir := Vector3(0.1, -0.2, 0.42)
	match t.visual:
		"finger":
			# ukazováček natažený dopředu (-Z), ostatní prsty v pěst
			var b := MeshBuilder.new(3)
			pointing_hand(b, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 0.03, -0.06)))
			forearm(b, Vector3(-0.012, 0.025, 0.09), Vector3(-0.012, 0.025, 0.09) + arm_dir)
			root.add_child(_mi(b.commit()))
		"bottle":
			var bottle := spray_bottle(t.color)
			bottle.rotation = Vector3(0.0, 0.12, 0.0)
			root.add_child(bottle)
			var hb := MeshBuilder.new(4)
			grip_hand(hb, Vector3(0.0, 0.062, 0.0), 0.016)
			forearm(hb, Vector3(0.012, 0.0, 0.05), Vector3(0.012, 0.0, 0.05) + arm_dir)
			root.add_child(_mi(hb.commit()))
		"sponge":
			var b := MeshBuilder.new(3)
			_sponge(b, Basis(Vector3.FORWARD, 0.15), Vector3.ZERO, t.color)
			flat_hand(b, Vector3(0.0, 0.058, 0.01))
			forearm(b, Vector3(0.01, 0.05, 0.07), Vector3(0.01, 0.05, 0.07) + arm_dir)
			root.add_child(_mi(b.commit()))
		"squeegee":
			var b := MeshBuilder.new(3)
			_squeegee_head(b, t.blade_width, Vector3(0, 0.16, -0.06), t.color)
			# rukojeť s protiskluzovými kroužky
			_limb(b, Vector3(0, -0.06, -0.03), Vector3(0, 0.145, -0.055), 0.017, t.color)
			for k in 4:
				var y := -0.04 + k * 0.03
				b.add("cyl10", Transform3D(Basis(Vector3.RIGHT, -0.12) * Basis.from_scale(Vector3(0.038, 0.008, 0.038)), Vector3(0, y, -0.03 - (y + 0.06) * 0.12)), t.color.darkened(0.35), 0.0)
			b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.04, 0.014, 0.04)), Vector3(0, -0.066, -0.03)), Color(0.15, 0.15, 0.16), 0.0)
			grip_hand(b, Vector3(0.0, -0.01, -0.03), 0.017)
			forearm(b, Vector3(0.012, -0.06, 0.02), Vector3(0.012, -0.06, 0.02) + arm_dir)
			root.add_child(_mi(b.commit()))
		"brush":
			var b := MeshBuilder.new(3)
			# rotační hlava se štětinami ve chomáčích
			b.add("cyl16", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.115, 0.03, 0.115)), Vector3(0, 0.12, -0.09)), Color(0.2, 0.2, 0.22), 0.0)
			for k in 10:
				var a := TAU * k / 10.0
				b.add("cyl6", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.022, 0.03, 0.022)), Vector3(cos(a) * 0.038, 0.12 + sin(a) * 0.038, -0.118)), Color(0.95, 0.95, 0.9), 0.0)
			b.add("cyl6", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.024, 0.03, 0.024)), Vector3(0, 0.12, -0.118)), Color(0.95, 0.95, 0.9), 0.0)
			# tělo s motorem a tlačítkem
			b.add("cyl10", Transform3D(Basis(Vector3.RIGHT, 0.2) * Basis.from_scale(Vector3(0.06, 0.13, 0.065)), Vector3(0, 0.06, -0.065)), t.color, 0.0)
			b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.062, 0.05, 0.066)), Vector3(0, 0.125, -0.078)), t.color.darkened(0.15), 0.0)
			b.add_box(Vector3(0.022, 0.03, 0.012), Vector3(0, 0.07, -0.03), Color(0.15, 0.15, 0.15), Basis.IDENTITY, 0.0)
			grip_hand(b, Vector3(0.0, -0.0, -0.055), 0.03)
			forearm(b, Vector3(0.012, -0.06, 0.0), Vector3(0.012, -0.06, 0.0) + arm_dir)
			root.add_child(_mi(b.commit()))
		_:
			# zmačkaný hadr pod dlaní, jeden cíp visí dolů
			var rag := _mi(rag_mesh())
			var rm := StandardMaterial3D.new()
			rm.vertex_color_use_as_albedo = true
			rm.albedo_color = t.color
			rm.roughness = 1.0
			rm.cull_mode = BaseMaterial3D.CULL_DISABLED
			rag.material_override = rm
			rag.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.FORWARD, 0.2) * Basis.from_scale(Vector3(0.95, 0.95, 1.6)), Vector3(0.0, 0.0, 0.0))
			root.add_child(rag)
			var rb := MeshBuilder.new(3)
			rb.add_box(Vector3(0.05, 0.07, 0.006), Vector3(0.07, -0.04, 0.025), t.color.darkened(0.06), Basis(Vector3.FORWARD, -0.25) * Basis(Vector3.UP, 0.4), 0.0)
			flat_hand(rb, Vector3(0.0, 0.035, 0.01))
			forearm(rb, Vector3(0.01, 0.03, 0.07), Vector3(0.01, 0.03, 0.07) + arm_dir)
			root.add_child(_mi(rb.commit()))
	if t.auto_dose > 0.0:
		# elektrický stěrač: průhledná nádržka a tělo s motorem pod lištou
		var eb := MeshBuilder.new(6)
		eb.add_box(Vector3(0.07, 0.06, 0.045), Vector3(0, 0.1, -0.04), Color(0.55, 0.8, 0.95), Basis.IDENTITY, 0.0)
		eb.add_box(Vector3(0.08, 0.04, 0.055), Vector3(0, 0.055, -0.035), t.color.darkened(0.2))
		eb.add_box(Vector3(0.015, 0.012, 0.01), Vector3(0.02, 0.055, -0.065), Color(0.3, 0.9, 0.4), Basis.IDENTITY, 0.0)
		root.add_child(_mi(eb.commit()))
	return root


## Nástroj na tyči (teleskopická stěrka / mop, skládací mop): ruka drží tyč,
## hlava nástroje je na jejím horním konci.
static func _held_pole(t: ToolData) -> Node3D:
	var root := Node3D.new()
	var b := MeshBuilder.new(3)
	var alu := Color(0.78, 0.8, 0.83)
	var dark := Color(0.15, 0.15, 0.16)
	var grip := Vector3(-0.02, 0.03, 0.0)
	var axis := Vector3(-0.06, 0.5, -0.6).normalized()
	var top := grip + axis * (0.5 if t.fold else 0.8)
	var bottom := grip - axis * 0.2
	# tyč: spodní díl silnější, horní tenčí, mezi nimi zajišťovací objímky
	var mid := grip.lerp(top, 0.5)
	_limb(b, bottom, mid, 0.0145, alu)
	_limb(b, mid, top, 0.011, alu.lightened(0.08))
	_limb(b, mid - axis * 0.02, mid + axis * 0.025, 0.019, t.color.darkened(0.25))
	_limb(b, bottom - axis * 0.012, grip + axis * 0.07, 0.019, dark)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.04), bottom - axis * 0.012), dark, 0.0)
	if t.fold:
		for f in [0.3, 0.7]:
			b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.034), grip.lerp(top, f)), t.color.darkened(0.3), 0.0)
	# hlava nástroje
	var hb := MeshBuilder.basis_y(axis)
	if hb.x.x < 0.0:
		hb = hb * Basis(Vector3.UP, PI)
	_limb(b, top - axis * 0.01, top + axis * 0.05, 0.016, t.color)
	if t.visual == "squeegee":
		_squeegee_head(b, t.blade_width, top + axis * 0.06, t.color, hb)
	elif t.visual == "brush":
		# rotační hlava: motor v barevném pouzdře, pod ním kotouč se štětinami
		var bb := hb * Basis(Vector3.RIGHT, -PI * 0.35)
		var c := top + axis * 0.08
		b.add("cyl10", Transform3D(bb * Basis.from_scale(Vector3(0.06, 0.07, 0.06)), c), t.color, 0.0)
		b.add("sphere", Transform3D(bb * Basis.from_scale(Vector3(0.058, 0.03, 0.058)), c + bb * Vector3(0, -0.035, 0)), t.color.darkened(0.2), 0.0)
		b.add_box(Vector3(0.016, 0.02, 0.01), c + bb * Vector3(0, 0.01, 0.031), Color(0.3, 0.9, 0.4), bb, 0.0)
		var disc := c + bb * Vector3(0, 0.05, 0)
		b.add("cyl16", Transform3D(bb * Basis.from_scale(Vector3(0.15, 0.022, 0.15)), disc), Color(0.2, 0.2, 0.22), 0.0)
		for k in 10:
			var ang := TAU * k / 10.0
			b.add("cyl6", Transform3D(bb * Basis.from_scale(Vector3(0.024, 0.03, 0.024)), disc + bb * Vector3(cos(ang) * 0.05, 0.022, sin(ang) * 0.05)), Color(0.95, 0.95, 0.9), 0.0)
		b.add("cyl6", Transform3D(bb * Basis.from_scale(Vector3(0.028, 0.03, 0.028)), disc + bb * Vector3(0, 0.022, 0)), Color(0.95, 0.95, 0.9), 0.0)
	else:
		# mop: rámeček s návlekem
		var mb := hb * Basis(Vector3.RIGHT, PI * 0.5)
		var c := top + axis * 0.07
		b.add_box(Vector3(0.3, 0.02, 0.06), c, t.color.darkened(0.2), mb, 0.0)
		b.add_box(Vector3(0.32, 0.045, 0.075), c + mb * Vector3(0, -0.03, 0), Color(0.93, 0.93, 0.9), mb, 0.0)
		for k in 7:
			b.add_box(Vector3(0.02, 0.05, 0.075), c + mb * Vector3(-0.14 + k * 0.047, -0.035, 0), Color(0.85, 0.86, 0.82), mb, 0.0)
	grip_hand(b, Transform3D(grip_basis(axis), grip), 0.019)
	forearm(b, grip + Vector3(0.03, -0.06, 0.05), grip + Vector3(0.13, -0.28, 0.47))
	root.add_child(_mi(b.commit()))
	return root


static func _mi(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func spray_bottle(color: Color) -> Node3D:
	var b := MeshBuilder.new(11)
	var white := Color(0.95, 0.95, 0.95)
	# tělo lahve se zaobleným ramenem a hrdlem
	b.add("cyl16", Transform3D(Basis.from_scale(Vector3(0.07, 0.13, 0.052)), Vector3(0, -0.03, 0)), color, 0.0)
	b.add("sphere_hi", Transform3D(Basis.from_scale(Vector3(0.07, 0.04, 0.052)), Vector3(0, 0.035, 0)), color, 0.0)
	b.add("cyl16", Transform3D(Basis.from_scale(Vector3(0.068, 0.012, 0.05)), Vector3(0, -0.095, 0)), color.darkened(0.15), 0.0)
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.03, 0.03, 0.03)), Vector3(0, 0.065, 0)), white, 0.0)
	# hlava rozprašovače s tryskou a spouští
	b.add_box(Vector3(0.036, 0.034, 0.075), Vector3(0, 0.098, -0.016), white, Basis.IDENTITY, 0.0)
	b.add_box(Vector3(0.03, 0.012, 0.06), Vector3(0, 0.12, -0.012), white.darkened(0.06), Basis(Vector3.RIGHT, 0.12), 0.0)
	b.add("cyl10", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.016, 0.02, 0.016)), Vector3(0, 0.103, -0.062)), Color(0.2, 0.2, 0.2), 0.0)
	b.add_box(Vector3(0.012, 0.05, 0.014), Vector3(0, 0.068, -0.043), white, Basis(Vector3.RIGHT, -0.25), 0.0)
	# etiketa
	b.add_box(Vector3(0.05, 0.06, 0.004), Vector3(0, -0.03, -0.027), Color(1.0, 0.86, 0.3) if color.h > 0.15 or color.s < 0.3 else Color(0.95, 0.95, 0.9), Basis.IDENTITY, 0.0)
	b.add_box(Vector3(0.036, 0.008, 0.002), Vector3(0, -0.015, -0.0295), Color(0.2, 0.3, 0.45), Basis.IDENTITY, 0.0)
	var root := Node3D.new()
	root.add_child(_mi(b.commit()))
	return root


## Houbička se zaoblenými hranami a zelenou drsnou vrstvou.
static func _sponge(b: MeshBuilder, basis: Basis, at: Vector3, c: Color) -> void:
	b.add_box(Vector3(0.13, 0.042, 0.082), at + basis * Vector3(0, 0, 0), c, basis, 0.0)
	b.add_box(Vector3(0.122, 0.05, 0.074), at + basis * Vector3(0, 0, 0), c.darkened(0.04), basis, 0.0)
	b.add_box(Vector3(0.126, 0.014, 0.078), at + basis * Vector3(0, 0.031, 0), Color(0.25, 0.55, 0.3), basis, 0.0)


## Hlava stěrky: hliníkový žlab s koncovkami, gumová lišta, úchyt rukojeti.
static func _squeegee_head(b: MeshBuilder, w: float, at: Vector3, handle_c: Color, hb: Basis = Basis.IDENTITY) -> void:
	b.add_box(Vector3(w, 0.026, 0.024), at, Color(0.78, 0.8, 0.84), hb, 0.0)
	b.add_box(Vector3(w - 0.01, 0.006, 0.026), at + hb * Vector3(0, 0.011, 0), Color(0.88, 0.9, 0.93), hb, 0.0)
	b.add_box(Vector3(w - 0.008, 0.014, 0.008), at + hb * Vector3(0, 0.019, 0), Color(0.08, 0.08, 0.09), hb, 0.0)
	for s: float in [-1.0, 1.0]:
		b.add_box(Vector3(0.008, 0.03, 0.028), at + hb * Vector3(s * w * 0.5, 0, 0), Color(0.15, 0.15, 0.16), hb, 0.0)
	b.add_box(Vector3(0.05, 0.03, 0.032), at + hb * Vector3(0, -0.018, 0.004), handle_c.darkened(0.2), hb, 0.0)


## Kontaktní model nástroje u skla v pracovním režimu.
## Lokálně: X = podél skla (u stěrky podél lišty), Y = nahoru po skle, +Z = od skla.
## Vrací [mesh, používá_vertex_barvy_jako_hadr].
## Ruka s nataženým ukazováčkem. Lokálně: konec prstu v počátku, prst míří do -Z
## (ke sklu), pěst je za ním v +Z.
static func pointing_hand(b: MeshBuilder, xf: Transform3D) -> void:
	var tip := Vector3(0, 0, 0.006)
	var k1 := Vector3(0, 0.004, 0.032)
	var k0 := Vector3(0, 0.008, 0.066)
	b.add("sphere", Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * 0.018), xf * tip), GLOVE_PALM, 0.0)
	_limb(b, xf * tip, xf * k1, 0.0085, GLOVE, "cyl6")
	b.add("sphere", Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * 0.019), xf * k1), GLOVE, 0.0)
	_limb(b, xf * k1, xf * k0, 0.0095, GLOVE, "cyl6")
	# pěst se zatnutými prsty a palcem
	b.add("sphere_hi", Transform3D(xf.basis * Basis.from_scale(Vector3(0.07, 0.05, 0.075)), xf * Vector3(-0.016, -0.004, 0.092)), GLOVE, 0.0)
	for f in 3:
		b.add("sphere", Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * 0.022), xf * Vector3(-0.02 - f * 0.017, -0.012, 0.064)), GLOVE, 0.0)
	b.add("sphere", Transform3D(xf.basis * Basis.from_scale(Vector3(0.02, 0.02, 0.03)), xf * Vector3(0.012, -0.018, 0.08)), GLOVE, 0.0)
	b.add("cyl10", Transform3D(xf.basis * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.068, 0.03, 0.052)), xf * Vector3(-0.016, -0.002, 0.135)), CUFF, 0.0)


static func contact_mesh(t: ToolData) -> ArrayMesh:
	match t.visual:
		"finger":
			var b := MeshBuilder.new(9)
			pointing_hand(b, Transform3D.IDENTITY)
			return b.commit()
		"sponge":
			var b := MeshBuilder.new(9)
			b.add_box(Vector3(0.15, 0.1, 0.045), Vector3(0, 0, 0.022), Color(1, 1, 1), Basis.IDENTITY, 0.004)
			b.add_box(Vector3(0.15, 0.1, 0.014), Vector3(0, 0, 0.05), Color(0.35, 0.62, 0.38), Basis.IDENTITY, 0.0)
			return b.commit()
		"brush":
			# jen rotační kotouč se štětinami – tělo strojku je zvlášť (brush_body_mesh) a netočí se
			var b := MeshBuilder.new(9)
			var k := t.radius / 0.075
			b.add("cyl16", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.15 * k, 0.03, 0.15 * k)), Vector3(0, 0, 0.015)), Color(0.95, 0.95, 0.9), 0.06)
			b.add("cyl16", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.16 * k, 0.022, 0.16 * k)), Vector3(0, 0, 0.04)), Color(0.2, 0.2, 0.22), 0.0)
			b.add_box(Vector3(0.03, 0.15 * k, 0.012), Vector3(0, 0, 0.003), Color(0.85, 0.85, 0.8), Basis.IDENTITY, 0.0)
			b.add_box(Vector3(0.012, 0.13 * k, 0.004), Vector3(0, 0, 0.053), Color(0.95, 0.75, 0.2), Basis.IDENTITY, 0.0)
			return b.commit()
		"squeegee":
			var b := MeshBuilder.new(9)
			var w := t.blade_width
			b.add_box(Vector3(w - 0.006, 0.012, 0.016), Vector3(0, 0, 0.008), Color(0.12, 0.12, 0.13), Basis.IDENTITY, 0.0)
			b.add_box(Vector3(w, 0.03, 0.022), Vector3(0, -0.012, 0.026), Color(0.76, 0.78, 0.82), Basis.IDENTITY, 0.0)
			b.add("cyl10", Transform3D(Basis(Vector3.RIGHT, -0.55) * Basis.from_scale(Vector3(0.03, 0.17, 0.03)), Vector3(0, -0.085, 0.075)), t.color, 0.0)
			if t.auto_dose > 0.0:
				b.add_box(Vector3(0.1, 0.07, 0.06), Vector3(0, -0.06, 0.07), Color(0.55, 0.8, 0.95), Basis.IDENTITY, 0.0)
				b.add_box(Vector3(0.11, 0.05, 0.07), Vector3(0, -0.11, 0.09), t.color.darkened(0.2), Basis.IDENTITY, 0.0)
			return b.commit()
	return rag_mesh()


## Motor rotačního kartáče na konci tyče (netočí se). Lokálně jako contact_mesh.
static func brush_pole_mesh(c: Color) -> ArrayMesh:
	var b := MeshBuilder.new(10)
	b.add("cyl16", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.095, 0.03, 0.095)), Vector3(0, 0, 0.066)), c.darkened(0.2), 0.0)
	b.add("cyl10", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.07, 0.07, 0.07)), Vector3(0, 0, 0.11)), c, 0.0)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.07, 0.07, 0.04)), Vector3(0, 0, 0.145)), c.darkened(0.15), 0.0)
	b.add_box(Vector3(0.016, 0.01, 0.02), Vector3(0, 0.035, 0.11), Color(0.3, 0.9, 0.4), Basis.IDENTITY, 0.0)
	return b.commit()


## Tělo elektrického kartáče v pracovním režimu (netočí se). Lokálně jako contact_mesh.
static func brush_body_mesh(c: Color) -> ArrayMesh:
	var b := MeshBuilder.new(10)
	b.add("cyl16", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.1, 0.03, 0.1)), Vector3(0, 0, 0.066)), c.darkened(0.2), 0.0)
	var ax := Basis(Vector3.RIGHT, 0.4)
	b.add("cyl10", Transform3D(ax * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.068, 0.2, 0.068)), Vector3(0, -0.02, 0.16)), c, 0.0)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.072, 0.072, 0.072)), Vector3(0, -0.06, 0.255)), c.darkened(0.15), 0.0)
	b.add_box(Vector3(0.022, 0.012, 0.03), Vector3(0, 0.022, 0.15), Color(0.15, 0.15, 0.15), ax, 0.0)
	return b.commit()


static func rag_mesh() -> ArrayMesh:
	# Zmačkaný kus látky: mřížka s náhodným zvlněním a podvinutými okraji.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 9
	var ny := 8
	var sx := 0.17
	var sy := 0.14
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var pts := []
	for j in ny + 1:
		var row := []
		for i in nx + 1:
			var u := float(i) / nx - 0.5
			var v := float(j) / ny - 0.5
			var edge := maxf(absf(u), absf(v)) * 2.0
			var z := rng.randf_range(-0.004, 0.012) + pow(edge, 3.0) * 0.02
			var px := u * sx + rng.randf_range(-0.004, 0.004)
			var py := v * sy + rng.randf_range(-0.004, 0.004)
			row.append(Vector3(px, py, z))
		pts.append(row)
	for j in ny:
		for i in nx:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var c: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			var shade := rng.randf_range(0.85, 1.05)
			var col := Color(shade, shade, shade)
			for tri in [[a, c, b], [a, d, c]]:
				var fn: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if fn.z < 0.0:
					fn = -fn
				for p in tri:
					st.set_color(col)
					st.set_normal(fn)
					st.add_vertex(p)
	return st.commit()

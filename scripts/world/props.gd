class_name Props
extends RefCounted
## Drobné rekvizity do MeshBuilderu (auto, plot, lavička, lampa…).
## Každá funkce kreslí do předaného builderu, aby se vše spojilo do pár meshů.


static func car(b: MeshBuilder, xf: Transform3D, color: Color) -> void:
	var dark := Color(0.12, 0.12, 0.13)
	b.add_box(Vector3(1.75, 0.55, 4.0), xf * Vector3(0, 0.6, 0), color, xf.basis)
	b.add_box(Vector3(1.6, 0.5, 2.1), xf * Vector3(0, 1.1, -0.2), color.lightened(0.05), xf.basis)
	b.add_box(Vector3(1.62, 0.38, 2.0), xf * Vector3(0, 1.1, -0.2), Color(0.2, 0.26, 0.3), xf.basis, 0.0)
	b.add_box(Vector3(1.8, 0.14, 4.05), xf * Vector3(0, 0.38, 0), dark, xf.basis)
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			# kolo bez náhodného rozkmitu (jinak plochy pneu a disku blikají přes sebe)
			var wp := xf * Vector3(sx * 0.82, 0.34, sz * 1.25)
			b.add("cyl10", Transform3D(xf.basis * Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.66, 0.24, 0.66)), wp), dark, 0.0)
			# disk je tenký kotouč těsně vně pneumatiky – žádné shodné plochy
			var hp := xf * Vector3(sx * (0.82 + 0.13), 0.34, sz * 1.25)
			b.add("cyl10", Transform3D(xf.basis * Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.36, 0.015, 0.36)), hp), Color(0.75, 0.75, 0.75), 0.0)
	for sx: int in [-1, 1]:
		b.add_box(Vector3(0.3, 0.14, 0.05), xf * Vector3(sx * 0.6, 0.68, 2.0), Color(1.0, 0.97, 0.85), xf.basis, 0.0)
		b.add_box(Vector3(0.3, 0.12, 0.05), xf * Vector3(sx * 0.6, 0.7, -2.0), Color(0.85, 0.15, 0.12), xf.basis, 0.0)


static func picket_fence(b: MeshBuilder, body: StaticBody3D, a: Vector3, c: Vector3, color: Color, gate_at: float = -1.0, gate_w: float = 1.2) -> void:
	var d := c - a
	var length := d.length()
	if length < 0.1:
		return
	var dir := d / length
	var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
	var n := int(length / 0.16)
	for i in n:
		var t := (i + 0.5) * length / n
		if gate_at >= 0.0 and absf(t - gate_at) < gate_w * 0.5:
			continue
		var p := a + dir * t
		b.add_box(Vector3(0.09, 0.85, 0.03), p + Vector3(0, 0.425, 0), color, basis, 0.05)
		b.add("prism", Transform3D(basis * Basis.from_scale(Vector3(0.09, 0.08, 0.03)), p + Vector3(0, 0.89, 0)), color, 0.05)
	# příčky za laťkami (ne ve stejné rovině – jinak čela blikají)
	var back := basis * Vector3(0, 0, -0.03)
	for rail_y: float in [0.25, 0.65]:
		if gate_at < 0.0:
			b.add_box(Vector3(length, 0.06, 0.03), a + d * 0.5 + Vector3(0, rail_y, 0) + back, color.darkened(0.08), basis)
		else:
			var g0 := gate_at - gate_w * 0.5
			var g1 := gate_at + gate_w * 0.5
			if g0 > 0.0:
				b.add_box(Vector3(g0, 0.06, 0.03), a + dir * (g0 * 0.5) + Vector3(0, rail_y, 0) + back, color.darkened(0.08), basis)
			if g1 < length:
				b.add_box(Vector3(length - g1, 0.06, 0.03), a + dir * ((g1 + length) * 0.5) + Vector3(0, rail_y, 0) + back, color.darkened(0.08), basis)
	if body:
		var segs := []
		if gate_at < 0.0:
			segs.append([0.0, length])
		else:
			segs.append([0.0, gate_at - gate_w * 0.5])
			segs.append([gate_at + gate_w * 0.5, length])
		for s in segs:
			var sl: float = s[1] - s[0]
			if sl <= 0.05:
				continue
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(sl, 1.0, 0.12)
			cs.shape = bs
			cs.transform = Transform3D(basis, a + dir * ((s[0] + s[1]) * 0.5) + Vector3(0, 0.5, 0))
			body.add_child(cs)


static func bench(b: MeshBuilder, xf: Transform3D) -> void:
	var wood := Color(0.6, 0.4, 0.24)
	var iron := Color(0.2, 0.22, 0.22)
	for k in 3:
		b.add_box(Vector3(1.6, 0.04, 0.12), xf * Vector3(0, 0.45, -0.15 + k * 0.14), wood, xf.basis)
	for k in 2:
		b.add_box(Vector3(1.6, 0.1, 0.03), xf * Vector3(0, 0.65 + k * 0.15, -0.24), wood, xf.basis)
	for sx: float in [-0.7, 0.7]:
		b.add_box(Vector3(0.05, 0.45, 0.45), xf * Vector3(sx, 0.22, 0), iron, xf.basis)
		b.add_box(Vector3(0.05, 0.45, 0.05), xf * Vector3(sx, 0.68, -0.24), iron, xf.basis)


static func lamp_post(b: MeshBuilder, pos: Vector3, facing: float, lights: Array = []) -> void:
	var dark := Color(0.18, 0.2, 0.22)
	b.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.12, 4.2, 0.12)), pos + Vector3(0, 2.1, 0)), dark)
	b.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.26, 0.3, 0.26)), pos + Vector3(0, 0.15, 0)), dark)
	var arm := Vector3(cos(facing), 0, -sin(facing))
	b.add_box(Vector3(0.9, 0.07, 0.07), pos + Vector3(0, 4.15, 0) + arm * 0.4, dark, Basis(Vector3.UP, facing))
	b.add_box(Vector3(0.4, 0.12, 0.25), pos + Vector3(0, 4.08, 0) + arm * 0.85, dark, Basis(Vector3.UP, facing))
	b.add_box(Vector3(0.32, 0.03, 0.18), pos + Vector3(0, 4.01, 0) + arm * 0.85, Color(1.0, 0.95, 0.8), Basis(Vector3.UP, facing), 0.0)
	lights.append([pos + Vector3(0, 3.99, 0) + arm * 0.85, facing])


static var _lamp_mat: ShaderMaterial

## Svítidla lamp (v noci září) a jejich světla. Atmosphere je rozsvěcí přes skupinu "street_lights".
static func lamp_lights(parent: Node3D, lights: Array) -> void:
	if _lamp_mat == null:
		_lamp_mat = ShaderMaterial.new()
		_lamp_mat.shader = preload("res://shaders/lamp_glow.gdshader")
	var q := BoxMesh.new()
	q.size = Vector3(0.3, 0.02, 0.16)
	for l in lights:
		var at: Vector3 = l[0]
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = _lamp_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = at
		mi.rotation.y = l[1]
		parent.add_child(mi)
		var o := OmniLight3D.new()
		o.position = at - Vector3(0, 0.4, 0)
		o.omni_range = 11.0
		o.omni_attenuation = 1.2
		o.light_color = Color(1.0, 0.82, 0.55)
		o.light_energy = 0.0
		o.visible = false
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 70.0
		o.distance_fade_length = 20.0
		o.add_to_group("street_lights")
		parent.add_child(o)


static func mailbox(b: MeshBuilder, pos: Vector3, yaw: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	b.add_box(Vector3(0.08, 1.0, 0.08), pos + Vector3(0, 0.5, 0), Color(0.45, 0.32, 0.2), basis)
	b.add_box(Vector3(0.3, 0.32, 0.42), pos + Vector3(0, 1.12, 0), color, basis)
	b.add_box(Vector3(0.22, 0.03, 0.02), pos + basis * Vector3(0, 1.2, 0.215), Color(0.15, 0.15, 0.15), basis, 0.0)


static func hay_bale(b: MeshBuilder, pos: Vector3, yaw: float) -> void:
	b.add("cyl10", Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(1.3, 1.2, 1.3)), pos + Vector3(0, 0.65, 0)), Color(0.9, 0.78, 0.45), 0.06)


static func bucket(b: MeshBuilder, pos: Vector3) -> void:
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.32, 0.34, 0.32)), pos + Vector3(0, 0.17, 0)), Color(0.3, 0.55, 0.8), 0.04)
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.28, 0.01, 0.28)), pos + Vector3(0, 0.3, 0)), Color(0.55, 0.75, 0.82), 0.0)
	b.add_box(Vector3(0.3, 0.015, 0.015), pos + Vector3(0, 0.42, 0), Color(0.6, 0.6, 0.6), Basis(Vector3.FORWARD, 0.0))
	b.add_box(Vector3(0.015, 0.1, 0.015), pos + Vector3(-0.15, 0.37, 0), Color(0.6, 0.6, 0.6))
	b.add_box(Vector3(0.015, 0.1, 0.015), pos + Vector3(0.15, 0.37, 0), Color(0.6, 0.6, 0.6))


## Sud na dešťovou vodu (místo, kde se namočí / vymáchá nástroj).
static func water_barrel(b: MeshBuilder, pos: Vector3) -> void:
	var wood := Color(0.52, 0.34, 0.2)
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.6, 0.85, 0.6)), pos + Vector3(0, 0.425, 0)), wood, 0.05)
	for y: float in [0.15, 0.7]:
		b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.62, 0.05, 0.62)), pos + Vector3(0, y, 0)), Color(0.35, 0.35, 0.37), 0.02)
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.52, 0.01, 0.52)), pos + Vector3(0, 0.83, 0)), Color(0.35, 0.6, 0.75), 0.0)


## Zahradní kohoutek na sloupku s konví.
static func garden_tap(b: MeshBuilder, pos: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	b.add_box(Vector3(0.12, 0.9, 0.12), pos + Vector3(0, 0.45, 0), Color(0.55, 0.55, 0.56), bs)
	b.add_box(Vector3(0.04, 0.04, 0.16), pos + bs * Vector3(0, 0.78, 0.1), Color(0.75, 0.6, 0.3), bs)
	b.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.08, 0.02, 0.08)), pos + bs * Vector3(0, 0.84, 0.03)), Color(0.85, 0.2, 0.2))
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.28, 0.3, 0.28)), pos + bs * Vector3(0.0, 0.15, 0.3)), Color(0.3, 0.6, 0.45), 0.03)
	b.add("cyl6", Transform3D(bs * Basis(Vector3.RIGHT, 1.0) * Basis.from_scale(Vector3(0.04, 0.3, 0.04)), pos + bs * Vector3(0.0, 0.3, 0.5)), Color(0.3, 0.6, 0.45))


static func tomato_plant(b: MeshBuilder, pos: Vector3, rng: RandomNumberGenerator) -> void:
	b.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.02, 1.0, 0.02)), pos + Vector3(0, 0.5, 0)), Color(0.6, 0.48, 0.3))
	for k in 4:
		var p := pos + Vector3(rng.randf_range(-0.12, 0.12), 0.25 + k * 0.2, rng.randf_range(-0.12, 0.12))
		b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.3, 0.22, 0.3)), p), Color(0.28, 0.55, 0.25), 0.08)
		if rng.randf() < 0.75:
			b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.07), p + Vector3(rng.randf_range(-0.1, 0.1), -0.05, 0.12)), Color(0.9, 0.2, 0.15), 0.03)


static var _board_mats := {}

## Cedule za nápisem: deska podle velikosti textu, přidaná jako dítě Label3D
## (otáčí se s ním). Nápis tak není jen „text ve vzduchu" nad vchodem.
## Vrací desku (MeshInstance3D), ať se dá dál upravit.
static func board_behind(label: Label3D, color: Color, pad: Vector2 = Vector2(0.14, 0.08), depth: float = 0.04, frame: Color = Color(0, 0, 0, 0)) -> MeshInstance3D:
	var font: Font = label.font if label.font else ThemeDB.fallback_font
	var px := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, label.font_size)
	var sz := (px + Vector2.ONE * label.outline_size * 2.0) * label.pixel_size + pad * 2.0
	var b := MeshBuilder.new(5)
	b.add_box(Vector3(sz.x, sz.y, depth), Vector3(0, 0, -depth * 0.5 - 0.008), color, Basis.IDENTITY, 0.0)
	if frame.a > 0.0:
		var f := 0.035
		for e: float in [-1.0, 1.0]:
			b.add_box(Vector3(sz.x + f * 2.0, f, depth + 0.02), Vector3(0, e * (sz.y * 0.5 + f * 0.5), -depth * 0.5 - 0.008), frame, Basis.IDENTITY, 0.0)
			b.add_box(Vector3(f, sz.y, depth + 0.02), Vector3(e * (sz.x * 0.5 + f * 0.5), 0, -depth * 0.5 - 0.008), frame, Basis.IDENTITY, 0.0)
	var mi := MeshInstance3D.new()
	mi.name = "Board"
	mi.mesh = b.commit()
	label.add_child(mi)
	label.set_meta("board_size", sz)
	return mi


## Volně stojící cedule na dvou sloupcích (jméno u branky, chata u cesty…).
## Nápis je z obou stran (two_sided), deska je vidět i zezadu. Vrací přední nápis.
static func sign_post(parent: Node3D, pos: Vector3, yaw: float, text: String, two_sided: bool = false, board: Color = Color(0.78, 0.64, 0.45), ink: Color = Color(0.22, 0.14, 0.08), height: float = 1.45, font_size: int = 40) -> Label3D:
	var labels: Array[Label3D] = []
	for side in (2 if two_sided else 1):
		var l := Label3D.new()
		l.text = text
		l.font_size = font_size
		l.pixel_size = 0.004
		l.outline_size = 0
		l.modulate = ink
		l.double_sided = false
		var off := 0.036 if side == 0 else -0.036
		l.position = pos + Basis(Vector3.UP, yaw) * Vector3(0, height, off)
		l.rotation.y = yaw + (0.0 if side == 0 else PI)
		parent.add_child(l)
		labels.append(l)
	# deska s rámečkem jen jednou (u předního nápisu), tloušťka přes obě strany
	var bm := board_behind(labels[0], board, Vector2(0.12, 0.07), 0.056, board.darkened(0.35))
	bm.position.z = 0.0
	var sz: Vector2 = labels[0].get_meta("board_size")
	var b := MeshBuilder.new(6)
	var wood := board.darkened(0.45)
	var bas := Basis(Vector3.UP, yaw)
	for e: float in [-1.0, 1.0]:
		var top := height + sz.y * 0.5 + 0.06
		# oboustranná cedule má sloupky po stranách desky, jinak za ní
		var post := Vector3(e * (sz.x * 0.5 + 0.04), top * 0.5, 0.0) if two_sided else Vector3(e * (sz.x * 0.5 - 0.06), top * 0.5, -0.07)
		b.add_box(Vector3(0.08, top, 0.08), pos + bas * post, wood, bas)
	b.to_instance(parent, "SignPosts")
	return labels[0]


## Živý plot z a do c: zastřižená zeď z keřů s nepravidelným vrškem a kolizí.
## Barvy jsou zelené, takže s materiálem Nature.foliage_mat se mění s ročním obdobím.
static func hedge(b: MeshBuilder, body: StaticBody3D, a: Vector3, c: Vector3, height: float = 1.15, thick: float = 0.7) -> void:
	var d := c - a
	var length := d.length()
	if length < 0.2:
		return
	var dir := d / length
	var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
	var green := Color(0.27, 0.48, 0.24)
	# výška těla se u každého úseku trochu liší – v rozích se horní plochy nekryjí
	var body_h := height - 0.15 + b.rng.randf_range(-0.05, 0.05)
	b.add_box(Vector3(length, body_h, thick), a + d * 0.5 + Vector3(0, body_h * 0.5, 0), green, basis, 0.06)
	var n := maxi(2, int(length / 0.55))
	for i in n + 1:
		var t := float(i) / n
		var p := a + d * t
		var s := b.rng.randf_range(0.85, 1.15)
		b.add("sphere", Transform3D(basis * Basis.from_scale(Vector3(0.75 * s, 0.42 * s, thick * 1.05)), p + Vector3(0, height - 0.17, 0)), green.lightened(b.rng.randf_range(0.0, 0.1)), 0.08)
		if i % 2 == 0:
			for e: float in [-1.0, 1.0]:
				var side := basis * Vector3(0, 0, e * thick * 0.48)
				b.add("sphere", Transform3D(basis * Basis.from_scale(Vector3(0.6, 0.55, 0.2) * s), p + side + Vector3(0, b.rng.randf_range(0.3, height - 0.4), 0)), green.darkened(b.rng.randf_range(0.0, 0.1)), 0.08)
	if body:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(length, height, thick)
		cs.shape = bs
		cs.transform = Transform3D(basis, a + d * 0.5 + Vector3(0, height * 0.5, 0))
		body.add_child(cs)

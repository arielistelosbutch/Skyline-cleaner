class_name Nature
extends RefCounted
## Stromy, keře, květiny a tráva přes MultiMesh (jeden draw call na druh).

static func tree_mesh(kind: int) -> ArrayMesh:
	var b := MeshBuilder.new(100 + kind)
	match kind:
		0:  # listnatý
			b.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.28, 2.0, 0.28)), Vector3(0, 1.0, 0)), Color(0.45, 0.31, 0.2), 0.05)
			b.add("sphere", Transform3D(Basis.from_scale(Vector3(2.6, 2.3, 2.6)), Vector3(0, 2.9, 0)), Color(0.36, 0.62, 0.3), 0.07)
			b.add("sphere", Transform3D(Basis.from_scale(Vector3(1.8, 1.7, 1.8)), Vector3(0.7, 3.6, 0.3)), Color(0.42, 0.68, 0.33), 0.07)
			b.add("sphere", Transform3D(Basis.from_scale(Vector3(1.7, 1.5, 1.7)), Vector3(-0.6, 3.4, -0.4)), Color(0.33, 0.58, 0.28), 0.07)
		1:  # jehličnan
			b.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.25, 1.4, 0.25)), Vector3(0, 0.7, 0)), Color(0.4, 0.28, 0.18), 0.05)
			for k in 3:
				var s := 2.6 - k * 0.65
				b.add("cone7", Transform3D(Basis.from_scale(Vector3(s, 1.8, s)), Vector3(0, 1.6 + k * 1.05, 0)), Color(0.2, 0.45, 0.3).lightened(k * 0.05), 0.06)
		2:  # bříza
			b.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.2, 3.2, 0.2)), Vector3(0, 1.6, 0)), Color(0.92, 0.9, 0.85), 0.08)
			for k in 4:
				b.add_box(Vector3(0.21, 0.05, 0.12), Vector3(0, 0.6 + k * 0.6, 0.04), Color(0.2, 0.2, 0.2), Basis.IDENTITY, 0.0)
			b.add("sphere", Transform3D(Basis.from_scale(Vector3(1.7, 2.4, 1.7)), Vector3(0, 3.6, 0)), Color(0.55, 0.74, 0.35), 0.08)
			b.add("sphere", Transform3D(Basis.from_scale(Vector3(1.2, 1.6, 1.2)), Vector3(0.4, 4.3, 0.2)), Color(0.6, 0.78, 0.38), 0.08)
		3:  # ovocný strom s jablky
			b.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.24, 1.5, 0.24)), Vector3(0, 0.75, 0)), Color(0.42, 0.3, 0.2), 0.05)
			b.add("sphere", Transform3D(Basis.from_scale(Vector3(2.4, 1.8, 2.4)), Vector3(0, 2.2, 0)), Color(0.4, 0.62, 0.28), 0.07)
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for k in 14:
				var a := rng.randf() * TAU
				var y := rng.randf_range(1.6, 2.8)
				var p := Vector3(cos(a) * 1.05, y, sin(a) * 1.05)
				b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.13), p), Color(0.85, 0.2, 0.18), 0.05)
	return b.commit()


static func bush_mesh(kind: int) -> ArrayMesh:
	var b := MeshBuilder.new(200 + kind)
	var green: Color = [Color(0.3, 0.55, 0.28), Color(0.38, 0.6, 0.3), Color(0.27, 0.5, 0.32)][kind % 3]
	b.add("sphere", Transform3D(Basis.from_scale(Vector3(1.1, 0.8, 1.0)), Vector3(0, 0.35, 0)), green, 0.08)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.8, 0.65, 0.8)), Vector3(0.4, 0.45, 0.15)), green.lightened(0.06), 0.08)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.7, 0.6, 0.7)), Vector3(-0.35, 0.4, -0.1)), green.darkened(0.05), 0.08)
	if kind == 1:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		for k in 9:
			var a := rng.randf() * TAU
			b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.12), Vector3(cos(a) * 0.5, 0.45 + rng.randf() * 0.3, sin(a) * 0.45)), Color(0.95, 0.6, 0.75), 0.05)
	return b.commit()


static func flower_mesh() -> ArrayMesh:
	var b := MeshBuilder.new(301)
	b.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.02, 0.25, 0.02)), Vector3(0, 0.12, 0)), Color(0.3, 0.55, 0.25), 0.0)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.12, 0.06, 0.12)), Vector3(0, 0.26, 0)), Color(1, 1, 1), 0.05)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.05, 0.04, 0.05)), Vector3(0, 0.29, 0)), Color(1.0, 0.85, 0.3), 0.0)
	return b.commit()


static func grass_mesh() -> ArrayMesh:
	# trs zahnutých stébel, která se ke špičce zužují (UV.y = výška na stéble pro shader)
	if _grass_mesh:
		return _grass_mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 302
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEG := 3
	for k in 14:
		var a := k * TAU / 14.0 + rng.randf_range(-0.25, 0.25)
		var r := rng.randf_range(0.0, 0.1)
		var root := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face))
		var fwd := Vector3(-side.z, 0, side.x)
		# stébla ven z trsu a do strany, zahnutá
		var lean := (Vector3(cos(a), 0, sin(a)) * 0.6 + fwd * 0.4).normalized()
		var hgt := rng.randf_range(0.22, 0.48)
		var curve := rng.randf_range(0.04, 0.16) * hgt / 0.35
		var w0 := rng.randf_range(0.014, 0.024)
		var col := Color(0.4, 0.62, 0.27).lerp(Color(0.5, 0.68, 0.28), rng.randf())
		if rng.randf() < 0.18:
			col = col.lerp(Color(0.62, 0.66, 0.33), 0.5)
		var pts: Array[Vector3] = []
		for s in SEG + 1:
			var t := float(s) / SEG
			pts.append(root + Vector3(0, hgt * t, 0) + lean * curve * t * t + lean * 0.02 * t)
		for s in SEG:
			var t0 := float(s) / SEG
			var t1 := float(s + 1) / SEG
			var hw0 := w0 * (1.0 - t0 * 0.85)
			var hw1 := w0 * (1.0 - t1 * 0.85) if s < SEG - 1 else 0.0
			var a0 := pts[s] - side * hw0
			var b0 := pts[s] + side * hw0
			var a1 := pts[s + 1] - side * hw1
			var b1 := pts[s + 1] + side * hw1
			var fn := side.cross(pts[s + 1] - pts[s]).normalized()
			if fn.dot(lean) > 0.0:
				fn = -fn
			var nrm := (fn * 0.45 + Vector3.UP * 0.55).normalized()
			var quad := [[a0, 0.0, t0], [b0, 1.0, t0], [b1, 1.0, t1], [a0, 0.0, t0], [b1, 1.0, t1], [a1, 0.0, t1]]
			if s == SEG - 1:
				quad = [[a0, 0.0, t0], [b0, 1.0, t0], [a1, 0.5, t1]]
			for q in quad:
				st.set_color(col)
				st.set_normal(nrm)
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(q[0])
	_grass_mesh = st.commit()
	return _grass_mesh


const GRASS_SHADER := preload("res://shaders/grass.gdshader")
static var _grass_mesh: ArrayMesh
static var _grass_mat: ShaderMaterial


## Sdílený materiál trávy (vlny větru, ohýbání kolem hráče – viz Player).
static func grass_mat() -> ShaderMaterial:
	if _grass_mat == null:
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = GRASS_SHADER
	return _grass_mat


static func rock_mesh() -> ArrayMesh:
	var b := MeshBuilder.new(303)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.9, 0.55, 0.7)), Vector3(0, 0.15, 0)), Color(0.58, 0.58, 0.56), 0.1)
	b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.5, 0.4, 0.5)), Vector3(0.35, 0.1, 0.2)), Color(0.52, 0.52, 0.5), 0.1)
	return b.commit()


const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
static var _foliage := {}


## Materiál vegetace s barvami ročních období (kind 0 strom/keř, 1 tráva, 2 květiny, 3 kopce).
static func foliage_mat(kind: int = 0) -> ShaderMaterial:
	if not _foliage.has(kind):
		var m := ShaderMaterial.new()
		m.shader = FOLIAGE_SHADER
		m.set_shader_parameter("kind", kind)
		m.set_shader_parameter("sway", [0.0, 0.55, 0.35, 0.0][kind])
		_foliage[kind] = m
	return _foliage[kind]


## Hustá tráva po čtvercích 16 m (vzdálené čtverce se nekreslí). exclude(p) vynechá
## místa, height(x, z) dá výšku terénu.
static func grass_field(parent: Node, area: Rect2, count: int, exclude: Callable, height: Callable, rng: RandomNumberGenerator) -> void:
	const CHUNK := 16.0
	var chunks := {}
	var mesh := grass_mesh()
	for i in count:
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if exclude.call(p):
			continue
		var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
		if not chunks.has(key):
			chunks[key] = []
		var y: float = height.call(p.x, p.y)
		chunks[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, rng.randf_range(0.7, 1.5), 1.0) * rng.randf_range(0.75, 1.3)), Vector3(p.x, y - 0.02, p.y)))
	for key in chunks:
		var mmi := multimesh(parent, mesh, chunks[key], false)
		mmi.material_override = grass_mat()
		mmi.visibility_range_end = 75.0
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Vytvoří MultiMeshInstance3D z pole transformací.
static func multimesh(parent: Node, mesh: Mesh, xforms: Array, shadows: bool = true, colors: Array = [], foliage: int = -1) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if foliage >= 0:
		mmi.material_override = foliage_mat(foliage)
	parent.add_child(mmi)
	return mmi

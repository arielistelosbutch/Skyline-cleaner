class_name Terrain
extends RefCounted
## Mírně zvlněný terén venkova: louky s pahorky mezi vesnicí a lesem a vyšší
## hřbety na okrajích. Kolem silnic, domů, polí a rybníka je terén rovný
## (výška 0), takže okna, žebříky a židle stojí jako dřív.

const MIN := Vector2(-200.0, -140.0)
const MAX := Vector2(200.0, 140.0)
const STEP := 2.5
## Od této vzdálenosti od budov a cest se terén začne zvedat, plně až od FULL.
const FLAT := 5.0
const FULL := 22.0

var cols := 0
var rows := 0
var heights := PackedFloat32Array()


func _init(excludes: Array[Rect2], seed_value: int = 7) -> void:
	cols = int((MAX.x - MIN.x) / STEP) + 1
	rows = int((MAX.y - MIN.y) / STEP) + 1
	heights.resize(cols * rows)
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.018
	n.fractal_octaves = 3
	var n2 := FastNoiseLite.new()
	n2.seed = seed_value + 11
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n2.frequency = 0.07
	for j in rows:
		var z := MIN.y + j * STEP
		for i in cols:
			var x := MIN.x + i * STEP
			var p := Vector2(x, z)
			var d := 1e9
			for r in excludes:
				d = minf(d, _rect_dist(r, p))
				if d <= FLAT:
					break
			var mask := smoothstep(FLAT, FULL, d)
			# zvlněné louky (0 .. ~2,2 m) a drobné hrbolky
			var base := clampf((n.get_noise_2d(x, z) + 0.35) * 0.9, 0.0, 1.0)
			var h := base * 2.2 + (n2.get_noise_2d(x, z) * 0.5 + 0.5) * 0.35
			# hřbety za hranicí hratelné plochy, na samém kraji zpět k nule
			var edge := maxf(absf(x) / 150.0, absf(z) / 95.0)
			h += smoothstep(0.82, 1.1, edge) * (4.5 + base * 3.0)
			h *= mask
			var outer := maxf(absf(x) / MAX.x, absf(z) / MAX.y)
			h *= 1.0 - smoothstep(0.9, 1.0, outer)
			heights[j * cols + i] = h


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dz * dz)


## Výška terénu v bodě (bilineárně mezi vrcholy). Mimo oblast 0.
func height(x: float, z: float) -> float:
	var fx := (x - MIN.x) / STEP
	var fz := (z - MIN.y) / STEP
	if fx < 0.0 or fz < 0.0 or fx >= cols - 1 or fz >= rows - 1:
		return 0.0
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := heights[j * cols + i]
	var b := heights[j * cols + i + 1]
	var c := heights[(j + 1) * cols + i]
	var d := heights[(j + 1) * cols + i + 1]
	# stejné dělení čtverce na trojúhelníky jako v meshi (úhlopříčka a–d)
	if tx >= tz:
		return a + (b - a) * tx + (d - b) * tz
	return a + (c - a) * tz + (d - c) * tx


## Mesh terénu (jen čtverce, kde je někde výška > 0 – rovina pod ním zůstává)
## a kolize ve stejném tvaru.
func build(parent: Node3D, body: StaticBody3D, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for j in rows - 1:
		for i in cols - 1:
			var ia := j * cols + i
			var ha := heights[ia]
			var hb := heights[ia + 1]
			var hc := heights[ia + cols]
			var hd := heights[ia + cols + 1]
			if ha + hb + hc + hd <= 0.0005:
				continue
			var x0 := MIN.x + i * STEP
			var z0 := MIN.y + j * STEP
			var a := Vector3(x0, ha, z0)
			var b := Vector3(x0 + STEP, hb, z0)
			var c := Vector3(x0, hc, z0 + STEP)
			var d := Vector3(x0 + STEP, hd, z0 + STEP)
			for v in [a, b, d, a, d, c]:
				st.set_normal(_normal(v.x, v.z))
				st.add_vertex(v)
				faces.append(v)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	cs.shape = shape
	cs.name = "TerrainCollision"
	body.add_child(cs)
	return mi


func _normal(x: float, z: float) -> Vector3:
	var e := STEP
	var hx := height(x + e * 0.5, z) - height(x - e * 0.5, z)
	var hz := height(x, z + e * 0.5) - height(x, z - e * 0.5)
	return Vector3(-hx, e, -hz).normalized()

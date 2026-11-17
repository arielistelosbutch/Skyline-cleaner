class_name MeshBuilder
extends RefCounted
## Skládá více primitiv do jednoho ArrayMeshe s plochým (low-poly) stínováním
## a barvami ve vrcholech. Jeden mesh + jeden sdílený materiál = málo draw callů.
## Až budou k dispozici kvalitní modely, stačí nahradit výsledný MeshInstance3D.

static var _arrays_cache := {}

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value


func is_empty() -> bool:
	return _v.is_empty()


static func _unit(kind: String) -> Array:
	if _arrays_cache.has(kind):
		return _arrays_cache[kind]
	var m: PrimitiveMesh
	match kind:
		"box":
			m = BoxMesh.new()
		"cyl6":
			var c := CylinderMesh.new()
			c.radial_segments = 6
			c.rings = 1
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			m = c
		"cyl10":
			var c := CylinderMesh.new()
			c.radial_segments = 10
			c.rings = 1
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			m = c
		"cyl16":
			var c := CylinderMesh.new()
			c.radial_segments = 16
			c.rings = 1
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			m = c
		"cone7":
			var c := CylinderMesh.new()
			c.radial_segments = 7
			c.rings = 1
			c.top_radius = 0.0
			c.bottom_radius = 0.5
			c.height = 1.0
			m = c
		"sphere":
			var s := SphereMesh.new()
			s.radial_segments = 8
			s.rings = 5
			s.radius = 0.5
			s.height = 1.0
			m = s
		"sphere_hi":
			var s := SphereMesh.new()
			s.radial_segments = 12
			s.rings = 7
			s.radius = 0.5
			s.height = 1.0
			m = s
		"prism":
			var p := PrismMesh.new()
			p.size = Vector3.ONE
			m = p
		_:
			m = BoxMesh.new()
	var arr := m.surface_get_arrays(0)
	_arrays_cache[kind] = arr
	return arr


## Přidá jednotkové primitivum (velikost 1) transformované pomocí xf.
func add(kind: String, xf: Transform3D, color: Color, jitter: float = 0.035) -> void:
	add_arrays(_unit(kind), xf, color, jitter)


func add_box(size: Vector3, pos: Vector3, color: Color, basis: Basis = Basis.IDENTITY, jitter: float = 0.03) -> void:
	add("box", Transform3D(basis * Basis.from_scale(size), pos), color, jitter)


func add_arrays(arr: Array, xf: Transform3D, color: Color, jitter: float) -> void:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx_v = arr[Mesh.ARRAY_INDEX]
	var idx: PackedInt32Array = idx_v if idx_v != null else PackedInt32Array()
	var has_idx := idx.size() > 0
	var count := idx.size() if has_idx else verts.size()
	var nb := xf.basis.inverse().transposed()
	for t in range(0, count - 2, 3):
		var i0 := idx[t] if has_idx else t
		var i1 := idx[t + 1] if has_idx else t + 1
		var i2 := idx[t + 2] if has_idx else t + 2
		var a := xf * verts[i0]
		var b := xf * verts[i1]
		var c := xf * verts[i2]
		var fn := (b - a).cross(c - a)
		if fn.length_squared() < 1e-14:
			continue
		fn = fn.normalized()
		var on := nb * (norms[i0] + norms[i1] + norms[i2])
		if fn.dot(on) < 0.0:
			fn = -fn
		var shade := 1.0 + rng.randf_range(-jitter, jitter)
		var col := Color(color.r * shade, color.g * shade, color.b * shade, color.a)
		_v.append(a)
		_v.append(b)
		_v.append(c)
		for k in 3:
			_n.append(fn)
			_c.append(col)


## Jeden trojúhelník; pořadí vrcholů se otočí tak, aby přední strana mířila k hint.
func add_tri(a: Vector3, b: Vector3, c: Vector3, color: Color, hint: Vector3 = Vector3.UP) -> void:
	var fn := (c - a).cross(b - a)
	if fn.length_squared() < 1e-14:
		return
	if fn.dot(hint) < 0.0:
		var t := b
		b = c
		c = t
		fn = -fn
	fn = fn.normalized()
	_v.append(a)
	_v.append(b)
	_v.append(c)
	for k in 3:
		_n.append(fn)
		_c.append(color)


func commit(material: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _v.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material if material else Mats.vc())
	return mesh


func to_instance(parent: Node, name: String = "Mesh", shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = commit()
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Báze, jejíž osa Y míří směrem dir (pro válce mezi dvěma body).
static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

extends Node
## Hledá v celém postaveném světě plochy, které leží v jedné rovině a překrývají se
## (z-fighting – „blikající" grafika). Spuštění: godot --headless --path . -- --zscan
## Vypíše nálezy seřazené podle plochy překryvu (meze: odstup rovin < GAP, překryv > MIN_AREA).

const GAP := 0.004
const MIN_AREA := 0.0006
const CELL := 1.0

var main: Node
var _tris := []        # [a, b, c, n, src]
var _src_names: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	_collect(main.world)
	print("zscan: %d trojúhelníků z %d meshů (%d ms)" % [_tris.size(), _src_names.size(), Time.get_ticks_msec() - t0])
	var found := scan()
	var by_src := {}
	var flt := OS.get_environment("ZSCAN_FILTER")
	for f in found:
		var key: String = f["where"]
		if flt != "":
			if key.contains(flt):
				if OS.get_environment("ZSCAN_DETAIL") != "":
					print("     A ", f["ta"], "\n     B ", f["tb"])
				print("  · %.4f %s @ %s n%s %s/%s" % [f["area"], key, str(f["at"]).replace(" ", ""), str(f["n"]).replace(" ", ""), (f["ca"] as Color).to_html(false), (f["cb"] as Color).to_html(false)])
			continue
		if not by_src.has(key):
			by_src[key] = {"area": 0.0, "n": 0, "at": f["at"], "gap": f["gap"], "dir": f["n"], "ca": f["ca"], "cb": f["cb"], "ta": f["ta"], "tb": f["tb"]}
		by_src[key]["area"] += f["area"]
		by_src[key]["n"] += 1
	var keys := by_src.keys()
	keys.sort_custom(func(a, b): return by_src[a]["area"] > by_src[b]["area"])
	print("zscan: %d překryvů v %d skupinách (%d ms)" % [found.size(), keys.size(), Time.get_ticks_msec() - t0])
	for k in keys:
		var e: Dictionary = by_src[k]
		print("  %.3f m2  %3d×  %s  @ %s n%s  gap %.4f  %s/%s" % [e["area"], e["n"], k, str(e["at"]).replace(" ", ""), str(e["dir"]).replace(" ", ""), e["gap"], (e["ca"] as Color).to_html(false), (e["cb"] as Color).to_html(false)])
		if OS.get_environment("ZSCAN_DETAIL") != "" and not k.begins_with("("):
			print("     A ", e["ta"], "\n     B ", e["tb"])
	get_tree().quit(0)


func _collect(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if mi.name == "Ground" or mi.name == "Clouds":
			continue
		var xf := mi.global_transform
		var src := _src_names.size()
		_src_names.append(str(main.world.get_path_to(mi)))
		for s in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cols = arr[Mesh.ARRAY_COLOR]
			var mat := mi.get_active_material(s)
			var mid := mat.get_instance_id() if mat else 0
			var idx_v = arr[Mesh.ARRAY_INDEX]
			var idx: PackedInt32Array = idx_v if idx_v != null else PackedInt32Array()
			var cnt := idx.size() if idx.size() > 0 else v.size()
			for t in range(0, cnt - 2, 3):
				var a := xf * v[idx[t] if idx.size() > 0 else t]
				var b := xf * v[idx[t + 1] if idx.size() > 0 else t + 1]
				var c := xf * v[idx[t + 2] if idx.size() > 0 else t + 2]
				var nn := (b - a).cross(c - a)
				if nn.length_squared() < 1e-10:
					continue
				# Godot má přední stěny po směru hodinových ručiček → normála je opačná
				nn = -nn.normalized()
				# spodní plochy u země nikdo nevidí
				if nn.y < -0.9 and a.y < 0.12:
					continue
				var col := Color(1, 1, 1)
				if cols != null and (cols as PackedColorArray).size() > 0:
					col = (cols as PackedColorArray)[idx[t] if idx.size() > 0 else t]
				_tris.append([a, b, c, nn, src, col, mid])


func scan() -> Array:
	# rovina = (zaokrouhlená normála, vzdálenost po krocích GAP)
	var planes := {}
	for i in _tris.size():
		var t: Array = _tris[i]
		var n: Vector3 = t[3]
		var nk := Vector3i(roundi(n.x * 60.0), roundi(n.y * 60.0), roundi(n.z * 60.0))
		var d := n.dot(t[0])
		var key := [nk, floori(d / GAP)]
		if not planes.has(key):
			planes[key] = []
		planes[key].append(i)
	var found := []
	var seen := {}
	for key in planes:
		var nk: Vector3i = key[0]
		var di: int = key[1]
		var cand: Array = planes[key].duplicate()
		var own: int = cand.size()
		var nb = [nk, di + 1]
		if planes.has(nb):
			cand.append_array(planes[nb])
		if cand.size() < 2:
			continue
		var n: Vector3 = Vector3(nk).normalized()
		var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var w := n.cross(u)
		var polys := []
		var grid := {}
		for ci in cand.size():
			var t: Array = _tris[cand[ci]]
			var p := PackedVector2Array([Vector2(u.dot(t[0]), w.dot(t[0])), Vector2(u.dot(t[1]), w.dot(t[1])), Vector2(u.dot(t[2]), w.dot(t[2]))])
			# o 3 mm zmenšit, ať se nepočítají trojúhelníky, které se jen dotýkají hranou
			var cc := (p[0] + p[1] + p[2]) / 3.0
			for q in 3:
				var dv := p[q] - cc
				p[q] = cc + dv * maxf(0.0, 1.0 - 0.003 / maxf(dv.length(), 0.0001))
			polys.append(p)
			var r := Rect2(p[0], Vector2.ZERO).expand(p[1]).expand(p[2])
			for gx in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
				for gy in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
					var gk := Vector2i(gx, gy)
					if not grid.has(gk):
						grid[gk] = []
					grid[gk].append(ci)
		for gk in grid:
			var cell: Array = grid[gk]
			for x in cell.size():
				for y in range(x + 1, cell.size()):
					var i: int = cell[x]
					var j: int = cell[y]
					# páry jen mezi vlastní rovinou a sousední (ne sousední × sousední)
					if i >= own and j >= own:
						continue
					var ti: int = cand[i]
					var tj: int = cand[j]
					var pk := Vector2i(mini(ti, tj), maxi(ti, tj))
					if seen.has(pk):
						continue
					seen[pk] = true
					var A: Array = _tris[ti]
					var B: Array = _tris[tj]
					var gap := absf((A[3] as Vector3).dot(A[0]) - (A[3] as Vector3).dot(B[0]))
					if gap > GAP:
						continue
					var area := 0.0
					var big := PackedVector2Array()
					var big_a := 0.0
					for poly in Geometry2D.intersect_polygons(polys[i], polys[j]):
						var pa := absf(_area(poly))
						area += pa
						if pa > big_a:
							big_a = pa
							big = poly
					if area < MIN_AREA:
						continue
					# překryv přikrytý jinou plochou otočenou proti (dotyk dvou krabic) není vidět
					var cen := Vector2.ZERO
					for q in big:
						cen += q
					cen /= big.size()
					if _covered(planes, nk, di, cen, u, w, n):
						continue
					var an: String = _src_names[A[4]]
					var bn: String = _src_names[B[4]]
					var where := an if an == bn else an + " × " + bn
					var ca: Color = A[5]
					var cb: Color = B[5]
					var diff := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b)) / maxf(maxf(ca.r, ca.g), maxf(ca.b, 0.05))
					if A[6] != B[6]:
						diff = 1.0
					if diff < 0.08:
						where = "(stejná barva) " + where
					found.append({"where": where, "area": area, "gap": gap, "at": ((A[0] + A[1] + A[2]) / 3.0).snapped(Vector3.ONE * 0.1), "n": (A[3] as Vector3).snapped(Vector3.ONE * 0.01), "ca": ca, "cb": cb, "ta": [A[0], A[1], A[2]], "tb": [B[0], B[1], B[2]]})
	return found


func _covered(planes: Dictionary, nk: Vector3i, di: int, p: Vector2, u: Vector3, w: Vector3, n: Vector3) -> bool:
	var ok := -nk
	var od := -di - 1
	for dd in [od - 1, od, od + 1]:
		var key = [ok, dd]
		if not planes.has(key):
			continue
		for ti in planes[key]:
			var t: Array = _tris[ti]
			var tri := PackedVector2Array([Vector2(u.dot(t[0]), w.dot(t[0])), Vector2(u.dot(t[1]), w.dot(t[1])), Vector2(u.dot(t[2]), w.dot(t[2]))])
			if Geometry2D.is_point_in_polygon(p, tri):
				return true
	return false


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for k in p.size():
		s += p[k].cross(p[(k + 1) % p.size()])
	return s * 0.5

class_name Birds
extends Node3D
## Hejna ptáků kolem mrakodrapů (Etapa 7). Krouží kolem věží, mávají křídly
## a sem tam jeden slétne k rozdělanému oknu aktivní zakázky a „kápne“ na něj.
## Na hotová okna nikdy – je to relax hra (a dá se vypnout v Nastavení).
##
## Hejno: {"center": lokální bod věže (y = 0), "radius": m, "h0", "h1": výška kroužení, "count"}

const DROP_RANGE := 30.0      ## jak daleko od hráče smí být okno
const AREA_RANGE := 220.0     ## hráč musí být ve čtvrti
const SPEED := 9.0

var flocks: Array = []
var birds: Array = []   # {"node", "wl", "wr", "flock", "a", "phase", "speed", "state", "target", "via", "window", "c", "pos"}
var drop_timer := 0.0
var drops_done := 0
var _rng := RandomNumberGenerator.new()
var _told := false


static func create(parent: Node3D, flock_list: Array, seed_value: int) -> Birds:
	var b := Birds.new()
	b.name = "Birds"
	b.flocks = flock_list
	b._rng.seed = seed_value
	parent.add_child(b)
	return b


func _ready() -> void:
	add_to_group("birds")
	drop_timer = _rng.randf_range(60.0, 120.0)
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.13, 0.11, 0.34)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.09, 0.09, 0.1)
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.36, 0.02, 0.15)
	var mats := [_mat(Color(0.36, 0.37, 0.42)), _mat(Color(0.88, 0.88, 0.86)), _mat(Color(0.2, 0.2, 0.22))]
	for fi in flocks.size():
		var f: Dictionary = flocks[fi]
		for k in int(f.get("count", 6)):
			var m: StandardMaterial3D = mats[_rng.randi() % mats.size()]
			var n := Node3D.new()
			n.scale = Vector3.ONE * 2.2
			add_child(n)
			var bm := MeshInstance3D.new()
			bm.mesh = body_mesh
			bm.material_override = m
			bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(bm)
			var hm := MeshInstance3D.new()
			hm.mesh = head_mesh
			hm.material_override = m
			hm.position = Vector3(0, 0.04, -0.2)
			hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(hm)
			var wings := []
			for s: float in [-1.0, 1.0]:
				var pivot := Node3D.new()
				pivot.position = Vector3(s * 0.06, 0.03, 0)
				n.add_child(pivot)
				var wm := MeshInstance3D.new()
				wm.mesh = wing_mesh
				wm.material_override = m
				wm.position = Vector3(s * 0.18, 0, 0)
				wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				pivot.add_child(wm)
				wings.append(pivot)
			var v := {"node": n, "wl": wings[0], "wr": wings[1], "flock": fi, "a": _rng.randf() * TAU,
				"phase": _rng.randf() * TAU, "speed": _rng.randf_range(0.8, 1.15), "dir": (1.0 if k % 3 != 0 else -1.0),
				"state": "orbit", "pos": Vector3.ZERO, "window": null, "c": Vector2.ZERO, "t": 0.0}
			v["pos"] = orbit_pos(v)
			n.position = v["pos"]
			birds.append(v)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


## Bod na kruhové dráze hejna (lokálně).
func orbit_pos(v: Dictionary) -> Vector3:
	var f: Dictionary = flocks[v["flock"]]
	var r: float = float(f["radius"]) + sin(float(v["phase"]) + float(v["a"]) * 2.0) * 3.0
	var h := lerpf(float(f["h0"]), float(f["h1"]), 0.5 + 0.5 * sin(float(v["a"]) * 1.5 + float(v["phase"])))
	var c: Vector3 = f["center"]
	return c + Vector3(cos(float(v["a"])) * r, h, sin(float(v["a"])) * r)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := player != null and to_local(player.global_position).length() < AREA_RANGE
	if not near:
		visible = false
		return
	visible = true
	for v in birds:
		_step(v, delta)
	if Settings.bird_droppings:
		drop_timer -= delta
		if drop_timer <= 0.0:
			drop_timer = _rng.randf_range(90.0, 180.0)
			try_drop(player.global_position)


func _step(v: Dictionary, delta: float) -> void:
	var n: Node3D = v["node"]
	var pos: Vector3 = v["pos"]
	var flap := 9.0
	match str(v["state"]):
		"orbit", "seek":
			var f: Dictionary = flocks[v["flock"]]
			v["a"] = float(v["a"]) + float(v["dir"]) * SPEED * float(v["speed"]) / float(f["radius"]) * delta
			pos = orbit_pos(v)
			# pták krouží dál, dokud není na straně věže s oknem – pak slétne (neproletí budovou)
			if v["state"] == "seek":
				if not is_instance_valid(v["window"]):
					v["state"] = "orbit"
				elif absf(wrapf(float(v["a"]) - float(v["seek_a"]), -PI, PI)) < 0.25:
					v["state"] = "dive"
		"dive", "back":
			var tgt: Vector3 = v["target"]
			var d := tgt - pos
			var stepl := SPEED * 1.6 * delta
			if d.length() <= stepl:
				pos = tgt
				if v["state"] == "dive":
					if v.has("via2"):
						v["target"] = v["via2"]
						v.erase("via2")
					else:
						_hit(v)
				else:
					v["state"] = "orbit"
			else:
				pos += d.normalized() * stepl
				flap = 5.0
	var vel: Vector3 = pos - (v["pos"] as Vector3)
	v["pos"] = pos
	n.position = pos
	if vel.length_squared() > 1e-6:
		var fwd := vel.normalized()
		if absf(fwd.y) < 0.98:
			n.basis = Basis.looking_at(fwd, Vector3.UP)
	v["t"] = float(v["t"]) + delta
	# mávání střídané s plachtěním
	var t: float = float(v["t"]) + float(v["phase"])
	var glide := sin(t * 0.7) > 0.3
	var ang := 0.12 if glide else sin(t * flap) * 0.65
	(v["wl"] as Node3D).rotation.z = ang
	(v["wr"] as Node3D).rotation.z = -ang


## Vybere rozdělané okno aktivní zakázky blízko hráče a pošle k němu ptáka.
## Vrací true, když se pták vydal na cestu.
func try_drop(player_pos: Vector3) -> bool:
	var c := ContractManager.active()
	if c == null:
		return false
	var best: CleanableWindow = null
	var best_d := DROP_RANGE
	var cam := get_viewport().get_camera_3d()
	for wid in c.window_ids:
		var w := WindowRegistry.find_window(wid)
		if w == null or w.completed or not w.is_active():
			continue
		if w.global_position.y < 2.5:
			continue
		var d := w.global_position.distance_to(player_pos)
		# okna v zorném poli mají přednost (ať to hráč vidí)
		if cam and not cam.is_position_in_frustum(w.global_position):
			d += 12.0
		if d < best_d:
			best_d = d
			best = w
	if best == null:
		return false
	var wl := to_local(best.global_position)
	var fi := 0
	var fd := INF
	for k in flocks.size():
		var cc: Vector3 = flocks[k]["center"]
		var dd := Vector2(wl.x - cc.x, wl.z - cc.z).length()
		if dd < fd:
			fd = dd
			fi = k
	var v: Dictionary = {}
	for b in birds:
		if b["state"] == "orbit" and int(b["flock"]) == fi:
			v = b
			break
	if v.is_empty():
		return false
	var fc: Vector3 = flocks[fi]["center"]
	v["seek_a"] = atan2(wl.z - fc.z, wl.x - fc.x)
	var spot := Vector2(_rng.randf_range(0.2, best.glass_size.x - 0.2), _rng.randf_range(best.glass_size.y * 0.45, best.glass_size.y - 0.15))
	var out := best.normal()
	v["window"] = best
	v["c"] = spot
	v["state"] = "seek"
	v["target"] = to_local(best.global_position + out * 9.0 + Vector3.UP * 4.0)
	v["via2"] = to_local(best.plane_to_world(spot, 0.9) + Vector3.UP * 0.4)
	return true


func _hit(v: Dictionary) -> void:
	var w = v["window"]
	if is_instance_valid(w) and (w as CleanableWindow).add_bird_dropping(v["c"], _rng.randi()):
		drops_done += 1
		Audio.play("bird", -6.0, _rng.randf_range(0.9, 1.15))
		if not _told:
			_told = true
			Events.toast("Pták ti kápl na okno! Trus povolí, když ho namočíš [F]. (Vypnout jde v Nastavení.)", "info")
	v["window"] = null
	v["state"] = "back"
	v["target"] = orbit_pos(v)

class_name DroneDepot
extends Node3D
## Depo dronů (Etapa 6) na náměstí ve Velkoměstě. Po koupi (obchod → Technologie) tu
## stojí přistávací plocha se třemi místy a ovládacím pultem. Drony, které firma
## vlastní, tu přistávají, nabíjejí se a s autopilotem samy létají mýt okna
## rozpracované zakázky ve Velkoměstě – nejdřív ta nejvyšší, kam se hráč dostane
## jen plošinou. Okno, se kterým si dron neporadí, nechá hráči (dočistit ručně).
## Lokálně: plocha leží kolem počátku, pult stojí na straně +Z.

const DRONE_MODELS := ["drone_vazka", "drone_albatros", "drone_sokol"]
const DEPOT_ITEM := "drone_depot"
const PADS := 3

var persist_id := "drone_depot"
var depot_id := "horizont"
var area_id := "velkomesto"
var autopilot := true
var drones: Array[WindowDrone] = []
## Okna, na která drony nestačí (silná špína) – čekají na hráče.
var skipped: Array[String] = []
var _built: Node3D
var _empty: Node3D
var _pending := {}
var _think := 0.0


static func build(parent: Node3D, pos: Vector3, yaw: float, id: String) -> DroneDepot:
	var d := DroneDepot.new()
	d.depot_id = id
	d.name = "DroneDepot_" + id
	d.position = pos
	d.rotation.y = yaw
	parent.add_child(d)
	return d


static func get_depot(from: Node) -> DroneDepot:
	return from.get_tree().get_first_node_in_group("drone_depot") as DroneDepot


func _ready() -> void:
	add_to_group("drone_depot")
	add_to_group("persist")
	area_id = WorldMap.area_at(Vector2(global_position.x, global_position.z))
	Events.inventory_changed.connect(sync)
	Events.game_loaded.connect(sync)
	Events.window_completed.connect(_on_window_completed)
	Events.contract_changed.connect(_on_contract_changed)
	sync()


func owned() -> bool:
	return GameState.has_item(DEPOT_ITEM)


## Postaví depo / prázdný pozemek a jeden dron pro každý vlastněný model.
func sync() -> void:
	var own := owned()
	if own and _built == null:
		_build_depot()
	if not own and _built:
		_built.queue_free()
		_built = null
	if own and _empty:
		_empty.queue_free()
		_empty = null
	if not own and _empty == null:
		_build_empty()
	var want: Array[String] = []
	if own:
		for m in DRONE_MODELS:
			if GameState.has_item(m):
				want.append(m)
	for i in range(drones.size() - 1, -1, -1):
		if not want.has(drones[i].item_id):
			drones[i].queue_free()
			drones.remove_at(i)
	for m in want:
		var have := false
		for d in drones:
			if d.item_id == m:
				have = true
		if not have:
			var d := WindowDrone.create(m)
			d.depot = self
			add_child(d)
			drones.append(d)
			var st: Dictionary = _pending.get(m, {})
			d.battery = clampf(float(st.get("battery", 1.0)), 0.0, 1.0)
	for i in drones.size():
		drones[i].pad = DRONE_MODELS.find(drones[i].item_id)
		if drones[i].state == WindowDrone.State.DOCKED:
			drones[i].dock()


func _build_depot() -> void:
	_built = Node3D.new()
	_built.name = "Depot"
	add_child(_built)
	var b := MeshBuilder.new(150)
	b.add_box(Vector3(9.0, 0.16, 4.2), Vector3(0, 0.08, 0), Color(0.36, 0.38, 0.4))
	for k in PADS:
		var x := pad_x(k)
		b.add("cyl10", Transform3D(Basis.from_scale(Vector3(2.2, 0.03, 2.2)), Vector3(x, 0.175, -0.3)), Color(0.95, 0.75, 0.15), 0.0)
		b.add("cyl10", Transform3D(Basis.from_scale(Vector3(1.9, 0.035, 1.9)), Vector3(x, 0.18, -0.3)), Color(0.3, 0.32, 0.34), 0.0)
		# písmeno H
		b.add_box(Vector3(0.12, 0.01, 0.9), Vector3(x - 0.3, 0.2, -0.3), Color(0.97, 0.97, 0.97), Basis.IDENTITY, 0.0)
		b.add_box(Vector3(0.12, 0.01, 0.9), Vector3(x + 0.3, 0.2, -0.3), Color(0.97, 0.97, 0.97), Basis.IDENTITY, 0.0)
		b.add_box(Vector3(0.6, 0.01, 0.12), Vector3(x, 0.2, -0.3), Color(0.97, 0.97, 0.97), Basis.IDENTITY, 0.0)
		# nabíjecí sloupek
		b.add_box(Vector3(0.2, 0.9, 0.2), Vector3(x + 1.0, 0.6, 1.4), Color(0.85, 0.87, 0.9))
		b.add_box(Vector3(0.12, 0.12, 0.04), Vector3(x + 1.0, 0.95, 1.51), Color(0.3, 0.8, 0.4), Basis.IDENTITY, 0.0)
	# ovládací pult
	b.add_box(Vector3(1.0, 1.1, 0.5), Vector3(0, 0.55 + 0.16, 1.75), Color(0.2, 0.55, 0.78))
	b.add_box(Vector3(0.8, 0.45, 0.05), Vector3(0, 1.2, 2.02), Color(0.12, 0.14, 0.16), Basis(Vector3.RIGHT, -0.3), 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	_built.add_child(mi)
	var body := StaticBody3D.new()
	_built.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 1.3, 0.5)
	cs.shape = bs
	cs.position = Vector3(0, 0.65, 1.75)
	body.add_child(cs)
	var lbl := Label3D.new()
	lbl.text = "DEPO DRONŮ · CLEAR VIEW"
	lbl.font_size = 40
	lbl.pixel_size = 0.005
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0.1, 0.25, 0.4)
	lbl.position = Vector3(0, 1.75, 2.0)
	_built.add_child(lbl)
	Props.board_behind(lbl, Color(0.1, 0.25, 0.4))
	var it := SimpleInteractable.create("[E] Depo dronů – stav a autopilot", func(_p): get_tree().call_group("ui_root", "open_tablet_section", "drony"), Vector3(1.2, 1.4, 0.8), Vector3(0, 0.7, 1.75))
	it.prompt_fn = func(_p): return "[E] Depo dronů – %s" % status_line()
	_built.add_child(it)
	WorldMap.move_marker("drone_depot", Vector2(global_position.x, global_position.z), "Depo dronů", Color(0.2, 0.55, 0.78))


func _build_empty() -> void:
	_empty = Node3D.new()
	_empty.name = "EmptyLot"
	add_child(_empty)
	var b := MeshBuilder.new(151)
	b.add_box(Vector3(9.0, 0.06, 4.2), Vector3(0, 0.03, 0), Color(0.5, 0.5, 0.48))
	b.add_box(Vector3(0.08, 1.6, 0.08), Vector3(0, 0.8, 1.9), Color(0.4, 0.4, 0.42))
	b.add_box(Vector3(1.6, 0.8, 0.05), Vector3(0, 1.5, 1.95), Color(0.95, 0.95, 0.92))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	_empty.add_child(mi)
	var lbl := Label3D.new()
	lbl.text = "K PRONÁJMU\ndepo dronů"
	lbl.font_size = 30
	lbl.pixel_size = 0.004
	lbl.modulate = Color(0.15, 0.2, 0.25)
	lbl.outline_size = 0
	lbl.position = Vector3(0, 1.5, 1.98)
	_empty.add_child(lbl)
	var it := SimpleInteractable.create("Místo pro depo dronů – pronájem koupíš v obchodě (Technologie, od úrovně %d)" % int(GameState.ITEMS[DEPOT_ITEM]["level"]), func(_p): pass, Vector3(1.8, 1.8, 0.4), Vector3(0, 1.0, 1.95))
	_empty.add_child(it)


func pad_x(k: int) -> float:
	return (k - 1) * 3.0


func pad_transform(k: int) -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(pad_x(k), 0.42, -0.3))


## Výška letu: nad okny na cestě, ale aspoň MIN_CRUISE.
func cruise_height(a: Vector3, b: Vector3) -> float:
	return maxf(maxf(a.y, b.y) + 2.0, global_position.y + WindowDrone.MIN_CRUISE)


## Trasa letu: svisle nahoru, nad třídou (osa ulice) k oknu a dolů na místo.
## Třída vede podél X, takže nad ní dron nenarazí do budov.
func route(from: Vector3, to: Vector3) -> Array[Vector3]:
	var h := cruise_height(from, to)
	var street_z := street_z_at()
	# okna na bocích a vzadu budov: vodorovné úseky nesmí vést skrz budovu – zvedneme letovou hladinu nad střechu
	h = _clear_height(h, [[Vector3(from.x, 0, from.z), Vector3(from.x, 0, street_z)], [Vector3(to.x, 0, street_z), Vector3(to.x, 0, to.z)]])
	var out: Array[Vector3] = []
	out.append(Vector3(from.x, h, from.z))
	out.append(Vector3(from.x, h, street_z))
	out.append(Vector3(to.x, h, street_z))
	out.append(Vector3(to.x, h, to.z))
	out.append(to)
	return out


func _clear_height(h: float, segs: Array) -> float:
	if not is_inside_tree():
		return h
	var space := get_world_3d().direct_space_state
	for _i in 4:
		var raised := false
		for sg in segs:
			var a: Vector3 = sg[0]
			var b: Vector3 = sg[1]
			a.y = h
			b.y = h
			if a.distance_to(b) < 0.5:
				continue
			# kousek od konců (dron visí u fasády, start i cíl jsou volné)
			var dir := (b - a).normalized()
			var q := PhysicsRayQueryParameters3D.create(a + dir * 0.3, b - dir * 0.3, 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var p: Vector3 = hit["position"]
			var down := PhysicsRayQueryParameters3D.create(Vector3(p.x, 400.0, p.z) + dir * 0.5, Vector3(p.x, 0.0, p.z) + dir * 0.5, 1)
			var top := space.intersect_ray(down)
			var roof: float = (top["position"] as Vector3).y if not top.is_empty() else h + 10.0
			h = maxf(h + 2.0, roof + 4.0)
			raised = true
		if not raised:
			break
	return h


func street_z_at() -> float:
	# třída Velkoměsta leží na lokálním z = 0 oblasti
	var m := get_parent()
	if m is Metropolis:
		return (m as Node3D).global_position.z
	return global_position.z


# ------------------------------------------------------------------ autopilot

func _process(delta: float) -> void:
	_think -= delta
	if _think > 0.0:
		return
	_think = 0.5
	if not autopilot or not owned():
		return
	for d in drones:
		if d.state == WindowDrone.State.DOCKED and d.battery >= 0.9:
			var w := next_window(d)
			if w:
				d.dispatch(w)


## Další okno pro dron: rozpracovaná zakázka, tato oblast, neumyté, nevzaté – nejvyšší první.
func next_window(for_drone: WindowDrone) -> CleanableWindow:
	var c := ContractManager.active()
	if c == null:
		return null
	var best: CleanableWindow = null
	var fleet := RobotFleet.get_fleet(self)
	var player := get_tree().get_first_node_in_group("player")
	for wid in c.window_ids:
		if skipped.has(wid):
			continue
		var w := WindowRegistry.find_window(wid)
		if w == null or w.completed:
			continue
		if WorldMap.area_at(Vector2(w.global_position.x, w.global_position.z)) != area_id:
			continue
		var taken := false
		for d in drones:
			if d != for_drone and d.window == w:
				taken = true
		if taken:
			continue
		if fleet and fleet.robot_on(w):
			continue
		if player and player.cleaning and player.cleaning.active and player.cleaning.window == w:
			continue
		if best == null or w.global_position.y > best.global_position.y:
			best = w
	return best


func on_window_done(d: WindowDrone) -> void:
	var next := next_window(d) if autopilot else null
	if next and d.battery > d.return_cost() + 0.12:
		d.dispatch(next)
	else:
		d.recall()


func on_drone_docked(_d: WindowDrone) -> void:
	pass


func skip_window(d: WindowDrone, w: CleanableWindow) -> void:
	if not skipped.has(w.window_id):
		skipped.append(w.window_id)
	Events.toast("%s si se zbylou špínou na okně neporadí – nechává ho tobě (dočisti ručně)." % d.display_name(), "info")
	on_window_done(d)


func _on_window_completed(wid: String) -> void:
	skipped.erase(wid)
	for d in drones:
		if d.window and d.window.window_id == wid and d.state == WindowDrone.State.CLEANING:
			GameState.stats["drone_windows"] = int(GameState.stats.get("drone_windows", 0)) + 1


func _on_contract_changed() -> void:
	if ContractManager.active() == null:
		skipped.clear()


func set_autopilot(on: bool) -> void:
	autopilot = on
	if not on:
		recall_all()


func recall_all() -> int:
	var n := 0
	for d in drones:
		if d.state == WindowDrone.State.OUTBOUND or d.state == WindowDrone.State.CLEANING:
			d.recall()
			n += 1
	return n


func working_count() -> int:
	var n := 0
	for d in drones:
		if d.state != WindowDrone.State.DOCKED:
			n += 1
	return n


func status_line() -> String:
	if drones.is_empty():
		return "žádný dron (koupíš v obchodě, Technologie)"
	return "dronů %d, ve vzduchu %d, autopilot %s" % [drones.size(), working_count(), "zapnutý" if autopilot else "vypnutý"]


# ------------------------------------------------------------------ ukládání

func save_state() -> Dictionary:
	var ds := {}
	for d in drones:
		ds[d.item_id] = {"battery": d.battery}
	return {"autopilot": autopilot, "drones": ds, "skipped": skipped.duplicate()}


func load_state(d) -> void:
	if not d is Dictionary:
		return
	autopilot = bool(d.get("autopilot", true))
	skipped.clear()
	for s in d.get("skipped", []):
		skipped.append(str(s))
	_pending = d.get("drones", {})
	sync()
	for dr in drones:
		var st: Dictionary = _pending.get(dr.item_id, {})
		dr.battery = clampf(float(st.get("battery", 1.0)), 0.0, 1.0)
		dr.dock()
	_pending = {}

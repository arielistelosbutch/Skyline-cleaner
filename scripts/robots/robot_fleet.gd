class_name RobotFleet
extends Node
## Firma = hráč + roboti (Etapa 5). Spravuje roboty na okna: kde jsou
## (u hráče, na skle, ve stojanu), přiložení na okno, sundání, nabíjení,
## přivolání (talent) a ukládání. Které kusy firma vlastní, drží
## GameState.robot_units (až MAX_ROBOTS kusů, libovolné modely);
## tady je ke každému kusu jeden WindowRobot ve světě.

var persist_id := "robots"
var robots: Array[WindowRobot] = []
var _pending: Array = []   # uložený stav robotů, než se vytvoří


static func get_fleet(from: Node) -> RobotFleet:
	return from.get_tree().get_first_node_in_group("robot_fleet") as RobotFleet


func _ready() -> void:
	add_to_group("persist")
	add_to_group("robot_fleet")
	Events.inventory_changed.connect(sync)
	Events.window_completed.connect(_on_window_completed)
	sync()


## Jeden robot ve světě pro každý kus ve firmě. Vyměněný kus (jiný model)
## se postaví znovu – nový robot je nabitý a u hráče.
func sync() -> void:
	var units := GameState.robot_units
	for i in units.size():
		var model: String = units[i]
		if i < robots.size() and robots[i] != null and robots[i].item_id == model:
			continue
		var old: WindowRobot = robots[i] if i < robots.size() else null
		if old:
			old.queue_free()
		var r := WindowRobot.create(model)
		r.unit_index = i
		add_child(r)
		if i < robots.size():
			robots[i] = r
		else:
			robots.append(r)
		if i < _pending.size() and _pending[i] is Dictionary and str(_pending[i].get("model", model)) == model:
			_apply(r, _pending[i])
	while robots.size() > units.size():
		var extra: WindowRobot = robots.pop_back()
		extra.queue_free()
	_number()


## „Robot Mini 1/2" jen když je stejných modelů víc.
func _number() -> void:
	for r in robots:
		var same := 0
		var nth := 0
		for o in robots:
			if o.item_id == r.item_id:
				same += 1
				if o == r:
					nth = same
		r.model_number = nth if GameState.robot_count(r.item_id) > 1 else 0


func list() -> Array[WindowRobot]:
	return robots.duplicate()


func in_bag() -> Array[WindowRobot]:
	var out: Array[WindowRobot] = []
	for r in robots:
		if r.state == WindowRobot.State.BAG:
			out.append(r)
	return out


func of_model(model: String) -> Array[WindowRobot]:
	var out: Array[WindowRobot] = []
	for r in robots:
		if r.item_id == model:
			out.append(r)
	return out


func robot_on(w: CleanableWindow) -> WindowRobot:
	for r in robots:
		if r.window == w and r.state != WindowRobot.State.BAG and r.state != WindowRobot.State.CHARGING:
			return r
	return null


## Nápověda pro HUD, když hráč míří na okno.
func window_hint(w: CleanableWindow) -> String:
	if in_bag().is_empty() or w.completed or robot_on(w) != null:
		return ""
	return "[G] Přiložit robota (%d u tebe)" % in_bag().size()


## Přiloží nejlepšího nabitého robota z „batohu" na okno.
func place(w: CleanableWindow, hit: Vector3) -> bool:
	if w == null:
		return false
	var bag := in_bag()
	if bag.is_empty():
		if robots.is_empty():
			Events.toast("Nemáš robota na okna – koupíš ho v obchodě s vybavením (Technologie).", "info")
		else:
			Events.toast("Žádného robota u sebe nemáš. Roboty sundáš ze skla [E] nebo vezmeš ze stojanu.", "info")
		return false
	if w.completed:
		Events.toast("Tohle okno je už čisté.", "info")
		return false
	if not ContractManager.can_clean(w.window_id):
		Events.toast("Robota přilož jen na okno z rozpracované zakázky.", "info")
		return false
	if robot_on(w):
		Events.toast("Na tomhle okně už jeden robot pracuje.", "info")
		return false
	var usable: Array[WindowRobot] = []
	for r in bag:
		if r.battery >= 0.05:
			usable.append(r)
	if usable.is_empty():
		Events.toast("Roboti u tebe jsou vybití – dej je nabít do stojanu (garáž, pobočky obchodu).", "warn")
		return false
	# nejlepší model, pak nejvíc nabitý
	usable.sort_custom(func(a: WindowRobot, b: WindowRobot) -> bool:
		var ta := GameState.robot_tier(a.item_id)
		var tb := GameState.robot_tier(b.item_id)
		return ta > tb if ta != tb else a.battery > b.battery)
	var r: WindowRobot = usable[0]
	r.start_on(w, w.to_plane(hit))
	Audio.play("pickup", -6.0, 1.3)
	Events.toast("%s přiložen – myje sám (baterie %d %%). Mezitím můžeš dělat jiné okno." % [r.display_name(), int(r.battery * 100.0)], "info")
	return true


## Sundání robota (ze skla nebo ze stojanu) k hráči.
func take_robot(r: WindowRobot) -> void:
	r.put_in_bag()
	Audio.play("pickup", -6.0, 1.1)
	Events.toast("%s je u tebe (baterie %d %%)." % [r.display_name(), int(round(r.battery * 100.0))], "info")


## Volá robot při změně stavu (hotovo, vybitý…) – místo pro budoucí rozšíření (zvuk, HUD).
func on_robot_changed(_r: WindowRobot) -> void:
	pass


func _on_window_completed(wid: String) -> void:
	for r in robots:
		if r.window and r.window.window_id == wid and r.state == WindowRobot.State.WORKING:
			GameState.stats["robot_windows"] = int(GameState.stats.get("robot_windows", 0)) + 1


func _free_slot(c: RobotCharger) -> int:
	for k in RobotCharger.SLOTS:
		var used := false
		for r in robots:
			if r.state == WindowRobot.State.CHARGING and r.charger_id == c.charger_id and r.charger_slot == k:
				used = true
		if not used:
			return k
	return -1


func on_charger(c: RobotCharger) -> Array[WindowRobot]:
	var out: Array[WindowRobot] = []
	for r in robots:
		if r.state == WindowRobot.State.CHARGING and r.charger_id == c.charger_id:
			out.append(r)
	return out


func charger_prompt(c: RobotCharger) -> String:
	if not in_bag().is_empty():
		return "[E] Dát roboty nabíjet (%d u tebe)" % in_bag().size()
	var here := on_charger(c)
	if here.is_empty():
		return "Nabíjecí stojan – žádný robot tu není"
	var parts: Array[String] = []
	for r in here:
		parts.append("%s %d %%" % [r.display_name(), int(r.battery * 100.0)])
	return "[E] Vzít roboty ze stojanu (%s)" % ", ".join(parts)


func charger_interact(c: RobotCharger) -> void:
	var bag := in_bag()
	if not bag.is_empty():
		var placed := 0
		var longest := 0.0
		for r in bag:
			var k := _free_slot(c)
			if k < 0:
				break
			r.put_on_charger(c.charger_id, k, c.slot_transform(k))
			longest = maxf(longest, r.charge_time() * (1.0 - r.battery))
			placed += 1
		if placed > 0:
			Audio.play("click", -4.0, 1.2)
			Events.toast("Roboti se nabíjejí (do plna asi %d s). Vezmeš si je tady [E]." % int(ceil(longest)), "info")
		else:
			Events.toast("Stojan je plný.", "info")
		return
	var here := on_charger(c)
	if here.is_empty():
		Events.toast("Ve stojanu žádný robot není.", "info")
		return
	for r in here:
		r.put_in_bag()
	Audio.play("pickup", -6.0, 1.1)
	Events.toast("Roboti jsou u tebe (%d) – přilož je na okna [G]." % here.size(), "info")


func find_charger(id: String) -> RobotCharger:
	for c in get_tree().get_nodes_in_group("robot_charger"):
		if c.charger_id == id:
			return c
	return null


## Talent Dálkové přivolání: všichni roboti se vrátí k hráči.
func can_recall() -> bool:
	return Talents.has_effect("robot_recall")


func recall_all() -> int:
	if not can_recall():
		return 0
	var n := 0
	for r in robots:
		if r.state != WindowRobot.State.BAG:
			r.put_in_bag()
			n += 1
	if n > 0:
		Events.toast("Přivoláno robotů: %d. Jsou u tebe." % n, "success")
	return n


## Roboti, kteří se nabíjejí ve stojanu na dodávce, jedou s ní – po přeparkování je přesuneme.
func follow_charger(c: RobotCharger) -> void:
	for r in on_charger(c):
		r.global_transform = c.slot_transform(r.charger_slot)
		r.reset_physics_interpolation()


# ------------------------------------------------------------------ ukládání

func save_state() -> Array:
	var out: Array = []
	for r in robots:
		var d := r.save_state()
		d["model"] = r.item_id
		out.append(d)
	return out


## Načte stav robotů. Umí i formát z Etapy 5 (slovník model -> stav).
func load_state(d) -> void:
	var arr: Array = []
	if d is Array:
		arr = d
	elif d is Dictionary:
		for m in GameState.robot_units:
			var entry: Dictionary = d.get(m, {}).duplicate()
			entry["model"] = m
			arr.append(entry)
	_pending = arr.duplicate(true)
	sync()
	for i in robots.size():
		if i < arr.size() and arr[i] is Dictionary and str(arr[i].get("model", robots[i].item_id)) == robots[i].item_id:
			_apply(robots[i], arr[i])
		else:
			robots[i].put_in_bag()
	_pending.clear()


func _apply(r: WindowRobot, d: Dictionary) -> void:
	r.battery = clampf(float(d.get("battery", 1.0)), 0.0, 1.0)
	var st := int(d.get("state", 0))
	var wid := str(d.get("window", ""))
	if st == WindowRobot.State.CHARGING:
		var c := find_charger(str(d.get("charger", "")))
		if c:
			r.put_on_charger(c.charger_id, int(d.get("slot", 0)), c.slot_transform(int(d.get("slot", 0))))
			return
	if st != WindowRobot.State.BAG and st != WindowRobot.State.CHARGING and wid != "":
		var w := WindowRegistry.find_window(wid)
		if w:
			var pa: Array = d.get("p", [0.5, 0.5])
			r.start_on(w, Vector2(float(pa[0]), float(pa[1])))
			r.state = st as WindowRobot.State
			if r.state == WindowRobot.State.WORKING and w.completed:
				r.state = WindowRobot.State.DONE
			r._apply_state_visual()
			return
	r.put_in_bag()

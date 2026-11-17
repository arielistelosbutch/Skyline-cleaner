class_name WindowRobot
extends StaticBody3D
## Robot na okna (Etapa 5). Hráč ho přiloží na sklo okna z aktivní zakázky ([G]),
## robot si okno sám nastříká a projíždí ho „hadem" po řádcích, dokud není
## čisté nebo dokud nedojde baterie. Pak ho hráč sundá ([E]) a dá nabít do
## nabíjecího stojanu (garáž na základně, pobočky obchodu).
## Robot čistí přes stejné API jako hadr (CleanableWindow.scrub/spray),
## takže dokončení okna, odměny i ukládání masky fungují beze změny.
## Lokálně: +Z = ven od skla (k hráči), záda robota leží na skle.

enum State { BAG, WORKING, DONE, EMPTY, STUCK, CHARGING }

const SIZE := 0.26
const DEPTH := 0.07
## Pod tímhle množstvím špíny robot řádek jen rychle přejede.
const ROW_CLEAN := 0.03

## Parametry modelů (data – nový robot = nový záznam + položka v GameState.ITEMS).
const SPECS := {
	"robot_mini": {
		"name": "Robot Mini", "speed": 0.24, "radius": 0.155, "strength": 5.0, "tough": 5.0,
		"work": 120.0, "charge": 60.0, "color": Color(0.93, 0.94, 0.96), "accent": Color(0.2, 0.55, 0.85),
	},
	"robot_pro": {
		"name": "Robot Pro", "speed": 0.32, "radius": 0.165, "strength": 6.4, "tough": 3.4,
		"work": 240.0, "charge": 75.0, "color": Color(0.22, 0.24, 0.27), "accent": Color(0.95, 0.75, 0.15),
	},
	"robot_max": {
		"name": "Robot Max", "speed": 0.4, "radius": 0.175, "strength": 8.0, "tough": 2.2,
		"work": 330.0, "charge": 80.0, "color": Color(0.96, 0.97, 0.97), "accent": Color(0.25, 0.7, 0.45),
	},
}

var item_id := "robot_mini"
## Pořadí ve firmě (0–3) – z něj je číslo v názvu „Robot Mini 2".
var unit_index := 0
## Pořadové číslo v rámci modelu (jen když má firma víc kusů stejného modelu).
var model_number := 0
var battery := 1.0
var state := State.BAG
var window: CleanableWindow
var charger_id := ""
var charger_slot := 0

var _path: Array[Vector2] = []
var _wp := 0
var _p := Vector2.ZERO
var _spray_t := 0.0
var _pass_start_total := 0.0
var _tool: ToolData
var _spray_tool: ToolData
var _led_mat: StandardMaterial3D
var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _blink := 0.0


static func create(id: String) -> WindowRobot:
	var r := WindowRobot.new()
	r.item_id = id
	r.name = "Robot_" + id
	return r


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	set_meta("interactable", self)
	var sd := spec()
	var b := MeshBuilder.new(70 + GameState.robot_tier(item_id))
	var body_c: Color = sd["color"]
	var acc: Color = sd["accent"]
	b.add_box(Vector3(SIZE, SIZE, DEPTH * 0.6), Vector3(0, 0, DEPTH * 0.3), body_c)
	b.add_box(Vector3(SIZE - 0.04, SIZE - 0.04, DEPTH * 0.35), Vector3(0, 0, DEPTH * 0.6 + DEPTH * 0.17), body_c.lightened(0.08))
	# barevný pruh a „madlo" na sundání
	b.add_box(Vector3(SIZE + 0.004, 0.03, DEPTH * 0.62), Vector3(0, -SIZE * 0.32, DEPTH * 0.3), acc)
	b.add_box(Vector3(0.12, 0.025, 0.025), Vector3(0, SIZE * 0.3, DEPTH + 0.01), acc.darkened(0.2))
	# čisticí podložka (na skle)
	b.add_box(Vector3(SIZE - 0.02, SIZE - 0.02, 0.008), Vector3(0, 0, 0.004), Color(0.35, 0.62, 0.9))
	_mesh = MeshInstance3D.new()
	_mesh.mesh = b.commit()
	add_child(_mesh)
	var led := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.03, 0.03, 0.01)
	_led_mat = StandardMaterial3D.new()
	_led_mat.emission_enabled = true
	_led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.material = _led_mat
	led.mesh = lm
	led.position = Vector3(SIZE * 0.32, SIZE * 0.32, DEPTH + 0.006)
	add_child(led)
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(SIZE + 0.04, SIZE + 0.04, DEPTH + 0.04)
	_shape.shape = bs
	_shape.position = Vector3(0, 0, DEPTH * 0.5 + 0.02)
	add_child(_shape)
	_tool = ToolData.new()
	_tool.id = item_id + "_pad"
	_tool.display_name = sd["name"]
	_tool.radius = sd["radius"]
	_tool.tough_penalty = sd["tough"]
	_tool.wet_bonus = 3.2
	_tool.kind_mult = PackedFloat32Array([1.0, 1.2, 1.0, 1.1, 1.5, 1.0, 1.0])
	_tool.initial_press = 0.0
	_spray_tool = ToolData.new()
	_spray_tool.kind = "spray"
	_spray_tool.spray_radius = float(sd["radius"]) * 1.4
	_spray_tool.grease_power = 0.3
	_spray_tool.dissolve = 1.0
	_spray_tool.evaporation = 0.7
	_apply_state_visual()


func spec() -> Dictionary:
	return SPECS.get(item_id, SPECS["robot_mini"])


func display_name() -> String:
	if model_number > 0:
		return "%s %d" % [spec()["name"], model_number]
	return spec()["name"]


## Doba práce na plné nabití (s talentem Větší baterie).
func work_time() -> float:
	return float(spec()["work"]) * Talents.mult("robot_battery")


## Doba nabití z nuly do plna (s talentem Rychlé nabíjení).
func charge_time() -> float:
	var sp := GameState.charger_speed(charger_id) if state == State.CHARGING else 1.0
	return float(spec()["charge"]) / Talents.mult("robot_charge") / sp


func speed() -> float:
	return float(spec()["speed"]) * Talents.mult("robot_speed")


# ------------------------------------------------------------------ práce

## Přiloží robota na sklo; `at` = bod na skle (m), kde ho hráč přiložil.
func start_on(w: CleanableWindow, at: Vector2) -> void:
	window = w
	charger_id = ""
	state = State.WORKING if battery > 0.01 else State.EMPTY
	_build_path()
	# začne na řádku nejblíž místu přiložení, ať to vypadá přirozeně
	var best := 0
	for i in range(0, _path.size(), 2):
		if absf(_path[i].y - at.y) < absf(_path[best].y - at.y):
			best = i
	_wp = best
	_p = Vector2(clampf(at.x, _margin(), w.glass_size.x - _margin()), _path[_wp].y)
	_pass_start_total = _dirt_total()
	_place_on_glass()
	_apply_state_visual()


## Robot nesmí přejet rám – střed drží půl těla od okraje skla (podložka dosáhne skoro k rámu).
func _margin() -> float:
	return minf(SIZE * 0.5 + 0.005, minf(window.glass_size.x, window.glass_size.y) * 0.45)


## „Had": řádky shora dolů, každý tam a zpět střídavě.
func _build_path() -> void:
	_path.clear()
	var m := _margin()
	var gs := window.glass_size
	var step := float(spec()["radius"]) * 1.3
	var y := gs.y - m
	var left := true
	while true:
		var x0 := m if left else gs.x - m
		var x1 := gs.x - m if left else m
		_path.append(Vector2(x0, y))
		_path.append(Vector2(x1, y))
		left = not left
		if y <= m + 0.001:
			break
		y = maxf(m, y - step)


func _dirt_total() -> float:
	if window == null or window.mask == null:
		return 0.0
	return window.mask.current_total


func _row_dirty(row_y: float) -> bool:
	var gs := window.glass_size
	var r := float(spec()["radius"])
	for k in 7:
		var x := lerpf(r, gs.x - r, k / 6.0)
		for dy: float in [-r * 0.6, 0.0, r * 0.6]:
			if window.dirt_at(Vector2(x, clampf(row_y + dy, 0.0, gs.y))) > ROW_CLEAN:
				return true
	return false


func _process(delta: float) -> void:
	_blink += delta
	if state == State.CHARGING:
		if battery < 1.0:
			battery = minf(1.0, battery + delta / maxf(1.0, charge_time()))
			if battery >= 1.0:
				_apply_state_visual()
		_led_mat.emission_energy_multiplier = 0.6 + 0.5 * sin(_blink * 3.0) if battery < 1.0 else 1.0
		return
	if state != State.WORKING or window == null:
		return
	if window.completed:
		_finish(State.DONE)
		return
	if not ContractManager.can_clean(window.window_id):
		# zakázka je přerušená – robot počká
		_led_mat.emission_energy_multiplier = 0.4
		return
	_led_mat.emission_energy_multiplier = 1.0
	window.activate()
	var target := _path[_wp]
	var horizontal := _wp % 2 == 1
	var fast := horizontal and not _row_dirty(target.y)
	var sp := speed() * (4.0 if fast else 1.0)
	var before := _p
	_p = _p.move_toward(target, sp * delta)
	var mult := Talents.mult("robot_speed")
	_tool.strength = float(spec()["strength"]) * mult
	_tool.tough_penalty = float(spec()["tough"]) * Talents.mult("robot_tough")
	_spray_t -= delta
	if _spray_t <= 0.0 and not fast:
		_spray_t = 0.5
		var ahead := _p + (target - _p).normalized() * 0.12 if target != _p else _p
		window.spray(ahead, _spray_tool)
	window.scrub(before, _p, _tool, 0.5)
	battery = maxf(0.0, battery - delta / work_time() * (0.35 if fast else 1.0))
	_place_on_glass()
	if window.completed:
		_finish(State.DONE)
		return
	if _p.distance_to(target) < 0.001:
		_wp += 1
		if _wp >= _path.size():
			_end_pass()
	if state == State.WORKING and battery <= 0.0:
		_finish(State.EMPTY)


## Konec průjezdu celým oknem: skoro hotové okno se dočistí, jinak další průjezd.
func _end_pass() -> void:
	_wp = 0
	window.finish_if_almost()
	if window.completed:
		_finish(State.DONE)
		return
	var now := _dirt_total()
	var init := window.mask.initial_total if window.mask else 1.0
	if _pass_start_total - now < init * 0.004:
		_finish(State.STUCK)
		return
	_pass_start_total = now


func _finish(s: State) -> void:
	state = s
	_apply_state_visual()
	var where := ""
	if window:
		where = WorldMap.area_name(WorldMap.area_at(Vector2(global_position.x, global_position.z)))
	match s:
		State.DONE:
			Events.toast("%s umyl okno ✓ (baterie %d %%). Sundej ho [E] a přilož na další." % [display_name(), int(battery * 100.0)], "success")
		State.EMPTY:
			Events.toast("%s má vybitou baterii – sundej ho [E] a dej nabít do stojanu (garáž, pobočky obchodu). %s" % [display_name(), where], "warn")
		State.STUCK:
			Events.toast("%s si se zbylou špínou neporadí (silná špína, trus). Dočisti okno ručně." % display_name(), "info")
	get_tree().call_group("robot_fleet", "on_robot_changed", self)


func _place_on_glass() -> void:
	if window == null:
		return
	var wb := window.global_basis.orthonormalized()
	global_transform = Transform3D(wb, window.plane_to_world(_p, 0.006))


# ------------------------------------------------------------------ stav a vzhled

func put_in_bag() -> void:
	state = State.BAG
	window = null
	charger_id = ""
	_apply_state_visual()


func put_on_charger(cid: String, slot: int, xf: Transform3D) -> void:
	state = State.CHARGING
	window = null
	charger_id = cid
	charger_slot = slot
	global_transform = xf
	_apply_state_visual()


func _apply_state_visual() -> void:
	if not is_inside_tree() or _led_mat == null:
		return
	var shown := state != State.BAG
	visible = shown
	collision_layer = 1 if shown else 0
	var c := Color(0.25, 0.85, 0.35)
	match state:
		State.WORKING:
			c = Color(0.3, 0.7, 1.0)
		State.EMPTY:
			c = Color(0.95, 0.25, 0.2)
		State.STUCK:
			c = Color(0.95, 0.65, 0.15)
		State.CHARGING:
			c = Color(0.95, 0.75, 0.15) if battery < 1.0 else Color(0.25, 0.85, 0.35)
	_led_mat.albedo_color = c
	_led_mat.emission = c


func state_text() -> String:
	var bat := "baterie %d %%" % int(round(battery * 100.0))
	match state:
		State.BAG:
			return "u tebe (%s)" % bat
		State.WORKING:
			if window and not ContractManager.can_clean(window.window_id):
				return "čeká na skle – zakázka je přerušená (%s)" % bat
			return "myje okno – %d %% (%s)" % [int(window.cleanliness() * 100.0) if window else 0, bat]
		State.DONE:
			return "okno umyté ✓, čeká na skle (%s)" % bat
		State.EMPTY:
			return "vybitý, čeká na skle"
		State.STUCK:
			return "dál to nezvládne, čeká na skle (%s)" % bat
		State.CHARGING:
			return "nabíjí se – %s" % bat if battery < 1.0 else "nabitý ve stojanu"
	return ""


func area_id() -> String:
	if state == State.BAG:
		return ""
	return WorldMap.area_at(Vector2(global_position.x, global_position.z))


func get_prompt(_player) -> String:
	return "[E] Sundat robota – %s: %s" % [display_name(), state_text()]


func interact(_player) -> void:
	get_tree().call_group("robot_fleet", "take_robot", self)


func save_state() -> Dictionary:
	return {
		"state": int(state), "battery": battery, "window": window.window_id if window else "",
		"charger": charger_id, "slot": charger_slot, "wp": _wp, "p": [_p.x, _p.y],
	}

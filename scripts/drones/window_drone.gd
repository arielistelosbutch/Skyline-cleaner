class_name WindowDrone
extends Node3D
## Létající dron na okna (Etapa 6). Startuje z depa, sám vyletí k neumytému oknu
## rozpracované zakázky ve Velkoměstě (nejdřív k nejvyšším), nastříká ho a projede
## mycí hlavou „hadem" po řádcích. Když okno dodělá, vezme další; když mu dochází
## baterie, vrátí se do depa, nabije se a pokračuje. Čistí přes stejné API jako
## hadr a robot (CleanableWindow.scrub/spray), takže odměny i ukládání fungují beze změny.
## Dron nemá kolizi – je to jen vizuál, se kterým hráč nemůže zakopnout.

enum State { DOCKED, OUTBOUND, CLEANING, RETURNING }

## Odstup mycí hlavy od skla (m) a výška letu nad depem.
## Odstup těžiště dronu od skla – vrtule tak nezasahují do říms a parapetů,
## ke sklu dosáhne dlouhé mycí rameno.
const HOVER := 1.05
const MIN_CRUISE := 16.0
const ROW_CLEAN := 0.03

## Modely dronů (data – nový dron = nový záznam + položka v GameState.ITEMS).
const SPECS := {
	"drone_vazka": {
		"name": "Dron Vážka", "fly": 7.0, "speed": 0.34, "radius": 0.22, "strength": 6.0, "tough": 3.6,
		"work": 300.0, "charge": 70.0, "color": Color(0.95, 0.96, 0.97), "accent": Color(0.2, 0.6, 0.9),
	},
	"drone_albatros": {
		"name": "Dron Albatros", "fly": 9.0, "speed": 0.44, "radius": 0.26, "strength": 7.5, "tough": 2.6,
		"work": 420.0, "charge": 80.0, "color": Color(0.25, 0.27, 0.3), "accent": Color(0.95, 0.7, 0.15),
	},
	"drone_sokol": {
		"name": "Dron Sokol", "fly": 12.0, "speed": 0.55, "radius": 0.3, "strength": 9.0, "tough": 1.8,
		"work": 540.0, "charge": 80.0, "color": Color(0.9, 0.2, 0.2), "accent": Color(0.97, 0.97, 0.97),
	},
}

var item_id := "drone_vazka"
var depot: DroneDepot
var pad := 0
var battery := 1.0
var state := State.DOCKED
var window: CleanableWindow

var _route: Array[Vector3] = []
var _path: Array[Vector2] = []
var _wp := 0
var _p := Vector2.ZERO
var _spray_t := 0.0
var _pass_start_total := 0.0
var _tool: ToolData
var _spray_tool: ToolData
var _rotors: Array[Node3D] = []
var _led_mat: StandardMaterial3D
var _spray_fx: Node3D
var _t := 0.0
var _yaw := 0.0


static func create(id: String) -> WindowDrone:
	var d := WindowDrone.new()
	d.item_id = id
	d.name = "Drone_" + id
	return d


func spec() -> Dictionary:
	return SPECS.get(item_id, SPECS["drone_vazka"])


func display_name() -> String:
	return spec()["name"]


func _ready() -> void:
	add_to_group("drones")
	var sd := spec()
	var body_c: Color = sd["color"]
	var acc: Color = sd["accent"]
	var b := MeshBuilder.new(140 + item_id.length())
	b.add_box(Vector3(0.42, 0.14, 0.42), Vector3(0, 0, 0), body_c)
	b.add_box(Vector3(0.3, 0.06, 0.3), Vector3(0, 0.1, 0), acc)
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var dir := Vector3(cos(a), 0, sin(a))
		b.add_box(Vector3(0.62, 0.05, 0.06), dir * 0.31, body_c.darkened(0.2), Basis(Vector3.UP, -a))
		b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.08, 0.1, 0.08)), dir * 0.6 + Vector3(0, 0.04, 0)), Color(0.15, 0.15, 0.17))
	# podvozek
	for sx: float in [-0.16, 0.16]:
		b.add_box(Vector3(0.03, 0.16, 0.03), Vector3(sx, -0.14, 0), Color(0.2, 0.2, 0.22))
		b.add_box(Vector3(0.03, 0.03, 0.4), Vector3(sx, -0.22, 0), Color(0.2, 0.2, 0.22))
	# mycí rameno dopředu (-Z) s kulatou hlavou
	var head_z := -(HOVER - 0.04)
	b.add_box(Vector3(0.06, 0.06, -head_z - 0.15), Vector3(0, -0.02, (head_z - 0.15) * 0.5), Color(0.3, 0.3, 0.32))
	b.add("cyl10", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(float(sd["radius"]) * 1.6, 0.05, float(sd["radius"]) * 1.6)), Vector3(0, -0.02, head_z)), Color(0.35, 0.62, 0.9))
	# trysky po stranách ramene
	for sx: float in [-0.09, 0.09]:
		b.add_box(Vector3(0.05, 0.05, 0.12), Vector3(sx, -0.08, -0.26), Color(0.2, 0.45, 0.75))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	add_child(mi)
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var r := Node3D.new()
		r.position = Vector3(cos(a), 0, sin(a)) * 0.6 + Vector3(0, 0.1, 0)
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 0.2
		cm.height = 0.01
		cm.radial_segments = 12
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.85, 0.9, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.material = mat
		disc.mesh = cm
		r.add_child(disc)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.38, 0.012, 0.04)
		blade.mesh = bm
		r.add_child(blade)
		add_child(r)
		_rotors.append(r)
	var led := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.06, 0.03, 0.03)
	_led_mat = StandardMaterial3D.new()
	_led_mat.emission_enabled = true
	_led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.material = _led_mat
	led.mesh = lm
	led.position = Vector3(0, 0.0, -0.22)
	add_child(led)
	_spray_fx = _make_spray()
	add_child(_spray_fx)
	_tool = ToolData.new()
	_tool.id = item_id + "_head"
	_tool.display_name = sd["name"]
	_tool.radius = sd["radius"]
	_tool.tough_penalty = sd["tough"]
	_tool.wet_bonus = 3.2
	_tool.kind_mult = PackedFloat32Array([1.0, 1.2, 1.0, 1.1, 1.5, 1.0, 1.0])
	_tool.initial_press = 0.0
	_spray_tool = ToolData.new()
	_spray_tool.kind = "spray"
	_spray_tool.spray_radius = float(sd["radius"]) * 1.5
	_spray_tool.grease_power = 0.3
	_spray_tool.dissolve = 1.0
	_spray_tool.evaporation = 0.7
	_update_led()


## Doba práce na plné nabití (s talentem).
func work_time() -> float:
	return float(spec()["work"]) * Talents.mult("drone_battery")


func charge_time() -> float:
	return float(spec()["charge"]) / Talents.mult("robot_charge")


func fly_speed() -> float:
	return float(spec()["fly"]) * Talents.mult("drone_speed")


func clean_speed() -> float:
	return float(spec()["speed"]) * Talents.mult("drone_speed")


# ------------------------------------------------------------------ řízení

## Usadí dron na plošinu depa.
func dock() -> void:
	state = State.DOCKED
	window = null
	_route.clear()
	if depot:
		global_transform = depot.pad_transform(pad)
		_yaw = global_rotation.y
	_update_led()


## Vyšle dron k oknu (z depa nebo rovnou od předchozího okna).
func dispatch(w: CleanableWindow) -> void:
	window = w
	_build_path()
	_wp = 0
	_p = _path[0]
	_pass_start_total = _dirt_total()
	var hover := w.plane_to_world(_p, HOVER)
	_route = depot.route(global_position, hover)
	state = State.OUTBOUND
	_update_led()


func recall() -> void:
	if state == State.DOCKED or state == State.RETURNING:
		return
	_go_home()


func _go_home() -> void:
	window = null
	_route = depot.route(global_position, depot.pad_transform(pad).origin)
	state = State.RETURNING
	_update_led()


## Kolik baterie je potřeba na cestu domů (s rezervou).
func return_cost() -> float:
	if depot == null:
		return 0.0
	var home := depot.pad_transform(pad).origin
	var dist := absf(global_position.y - depot.cruise_height(global_position, home)) * 2.0 + Vector2(global_position.x - home.x, global_position.z - home.z).length()
	return dist / fly_speed() / work_time() * 0.6 * 1.4 + 0.03


func _process(delta: float) -> void:
	_t += delta
	var spinning := state != State.DOCKED
	for r in _rotors:
		r.rotation.y += delta * (40.0 if spinning else 0.0)
	match state:
		State.DOCKED:
			_set_spray(false)
			if battery < 1.0:
				battery = minf(1.0, battery + delta / maxf(1.0, charge_time()))
				_led_mat.emission_energy_multiplier = 0.6 + 0.5 * sin(_t * 3.0)
				if battery >= 1.0:
					_update_led()
		State.OUTBOUND, State.RETURNING:
			_set_spray(false)
			_fly(delta)
		State.CLEANING:
			_clean(delta)


func _fly(delta: float) -> void:
	battery = maxf(0.0, battery - delta / work_time() * 0.6)
	if _route.is_empty():
		_arrive()
		return
	var target := _route[0]
	var to := target - global_position
	var step := fly_speed() * delta
	if to.length() <= step:
		global_position = target
		_route.remove_at(0)
		if _route.is_empty():
			_arrive()
		return
	global_position += to.normalized() * step
	var flat := Vector2(to.x, to.z)
	if flat.length() > 0.3:
		_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), minf(1.0, delta * 4.0))
	global_rotation = Vector3(-0.12, _yaw, 0.0)


func _arrive() -> void:
	if state == State.RETURNING or window == null:
		dock()
		depot.on_drone_docked(self)
		return
	if window.completed or not ContractManager.can_clean(window.window_id):
		depot.on_window_done(self)
		return
	state = State.CLEANING
	_update_led()


## Sprška vody z trysek na sklo (jen při mytí): dva proudy kapek a mlha u hlavy.
func _make_spray() -> Node3D:
	var root := Node3D.new()
	root.name = "SprayFX"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.9, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var drop := SphereMesh.new()
	drop.radius = 0.018
	drop.height = 0.036
	drop.radial_segments = 6
	drop.rings = 3
	drop.material = mat
	for sx: float in [-0.09, 0.09]:
		var p := CPUParticles3D.new()
		p.mesh = drop
		p.amount = 36
		p.lifetime = 0.3
		p.emitting = false
		p.local_coords = false
		p.position = Vector3(sx, -0.08, -0.33)
		# proud míří šikmo dopředu ke sklu, kousek před mycí hlavu
		p.direction = Vector3(-sx * 1.2, 0.25, -1.0).normalized()
		p.spread = 7.0
		p.initial_velocity_min = 3.2
		p.initial_velocity_max = 3.8
		p.gravity = Vector3(0, -3.0, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		root.add_child(p)
	var mist := CPUParticles3D.new()
	var md := drop.duplicate() as SphereMesh
	md.radius = 0.03
	md.height = 0.06
	mist.mesh = md
	mist.amount = 24
	mist.lifetime = 0.45
	mist.emitting = false
	mist.local_coords = false
	mist.position = Vector3(0, -0.02, -(HOVER - 0.08))
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 0.15
	mist.direction = Vector3(0, -1, 0.3)
	mist.spread = 60.0
	mist.initial_velocity_min = 0.2
	mist.initial_velocity_max = 0.6
	mist.gravity = Vector3(0, -1.5, 0)
	root.add_child(mist)
	return root


func _set_spray(on: bool) -> void:
	if _spray_fx == null:
		return
	for c in _spray_fx.get_children():
		var p := c as CPUParticles3D
		if p and p.emitting != on:
			p.emitting = on


func spraying() -> bool:
	if _spray_fx == null:
		return false
	return (_spray_fx.get_child(0) as CPUParticles3D).emitting


func _clean(delta: float) -> void:
	if window == null or not is_instance_valid(window):
		_go_home()
		return
	if window.completed:
		depot.on_window_done(self)
		return
	if not ContractManager.can_clean(window.window_id):
		# zakázka přerušená nebo hotová – zpátky do depa
		_go_home()
		return
	window.activate()
	var target := _path[_wp]
	var horizontal := _wp % 2 == 1
	var fast := horizontal and not _row_dirty(target.y)
	var sp := clean_speed() * (4.0 if fast else 1.0)
	_set_spray(not fast)
	var before := _p
	_p = _p.move_toward(target, sp * delta)
	var power := Talents.mult("drone_power")
	_tool.strength = float(spec()["strength"]) * power
	_tool.tough_penalty = float(spec()["tough"]) / power
	_spray_t -= delta
	if _spray_t <= 0.0 and not fast:
		_spray_t = 0.4
		var ahead := _p + (target - _p).normalized() * 0.15 if target != _p else _p
		window.spray(ahead, _spray_tool)
	window.scrub(before, _p, _tool, 0.5)
	battery = maxf(0.0, battery - delta / work_time() * (0.5 if fast else 1.0))
	_hover_at(_p)
	if window.completed:
		depot.on_window_done(self)
		return
	if _p.distance_to(target) < 0.001:
		_wp += 1
		if _wp >= _path.size():
			_end_pass()
			if state != State.CLEANING:
				return
	if battery <= return_cost():
		Events.toast("%s se vrací do depa nabít (baterie %d %%)." % [display_name(), int(battery * 100.0)], "info")
		_go_home()


func _hover_at(p: Vector2) -> void:
	var pos := window.plane_to_world(p, HOVER) + Vector3(0, 0.03 * sin(_t * 5.0), 0)
	global_position = pos
	# rameno (−Z) vždy míří ke sklu – podle skutečné polohy skla, ne podle znaménka normály
	var to := window.plane_to_world(p) - pos
	_yaw = atan2(-to.x, -to.z)
	global_rotation = Vector3(0.0, _yaw, 0.0)


func _end_pass() -> void:
	_wp = 0
	window.finish_if_almost()
	if window.completed:
		depot.on_window_done(self)
		return
	var now := _dirt_total()
	var init := window.mask.initial_total if window.mask else 1.0
	if _pass_start_total - now < init * 0.004:
		depot.skip_window(self, window)
		return
	_pass_start_total = now


func _margin() -> float:
	return minf(float(spec()["radius"]) * 0.55, minf(window.glass_size.x, window.glass_size.y) * 0.45)


func _build_path() -> void:
	_path.clear()
	var m := _margin()
	var gs := window.glass_size
	var step := float(spec()["radius"]) * 1.3
	var y := gs.y - m
	var left := true
	while true:
		_path.append(Vector2(m if left else gs.x - m, y))
		_path.append(Vector2(gs.x - m if left else m, y))
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


func _update_led() -> void:
	if _led_mat == null:
		return
	var c := Color(0.25, 0.85, 0.35)
	match state:
		State.OUTBOUND, State.RETURNING:
			c = Color(0.95, 0.95, 1.0)
		State.CLEANING:
			c = Color(0.3, 0.7, 1.0)
		State.DOCKED:
			c = Color(0.95, 0.75, 0.15) if battery < 1.0 else Color(0.25, 0.85, 0.35)
	_led_mat.albedo_color = c
	_led_mat.emission = c
	_led_mat.emission_energy_multiplier = 1.0


func state_text() -> String:
	var bat := "baterie %d %%" % int(round(battery * 100.0))
	match state:
		State.DOCKED:
			return ("nabíjí se v depu (%s)" % bat) if battery < 1.0 else "nabitý, čeká v depu"
		State.OUTBOUND:
			return "letí k oknu (%s)" % bat
		State.CLEANING:
			return "myje okno – %d %% (%s)" % [int(window.cleanliness() * 100.0) if window else 0, bat]
		State.RETURNING:
			return "vrací se do depa (%s)" % bat
	return ""

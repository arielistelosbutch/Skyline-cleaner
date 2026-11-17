class_name Countryside
extends Node3D
## Oblast I – Venkov (vesnice Lipová Lhota). Staví prostředí, silnice,
## domy, zakázkový bungalov, garáž hráče, přírodu a registruje mapu.

const GROUND_SHADER := preload("res://shaders/ground.gdshader")
const CLOUD_SHADER := preload("res://shaders/clouds.gdshader")

var spawn_point := Vector3(-30.5, 0.0, -6.5)
## Autobusová zastávka na návsi (střed přístřešku) – mezi garáží a cestou k rybníku,
## mimo pozemky domů.
const BUS_X := -21.0
## Ploty předzahrádek stojí za chodníky po obou stranách silnice.
const FENCE_Z := 5.35
## Rybník: střed a poloosy elipsy břehu (dno jde do hloubky pod okolní terén).
const POND_C := Vector2(-24.0, -42.0)
const POND_R := Vector2(11.7, 7.2)
const POND_WATER_Y := -0.28
var spawn_yaw := -PI * 0.5
var menu_camera: Camera3D
var chair: Chair
var ladders: Array[Ladder] = []
var suburb: Suburb
var city: City
var metropolis: Metropolis
var base: CompanyBase
var sun: DirectionalLight3D
var weather: Weather
var atmosphere: Atmosphere

var _static: StaticBody3D
var carry_bucket: Bucket
var _deco: MeshBuilder
var _exclude: Array[Rect2] = []
var _rng := RandomNumberGenerator.new()
var _clouds: MeshInstance3D
var _menu_t := 0.0
var _bus_stop: SimpleInteractable
## Zvlněný terén luk (rovný kolem budov a cest).
var terrain: Terrain
var _ground_mat: ShaderMaterial


func _ready() -> void:
	_rng.seed = 2024
	add_to_group("world")
	WorldMap.clear()
	_static = StaticBody3D.new()
	_static.name = "StaticCollision"
	add_child(_static)
	_deco = MeshBuilder.new(77)

	_environment()
	_ground()
	_roads()
	_garage_base()
	_bungalow()
	_village_houses()
	_cottage()
	_greenhouse()
	_farm()
	_pond()
	_fields()
	_street_props()
	_terrain()
	_nature()
	_hills()
	_bounds()

	_deco.to_instance(self, "Decor")

	# přenosný kbelík (objeví se u garáže, až ho hráč koupí)
	carry_bucket = Bucket.new()
	carry_bucket.name = "CarryBucket"
	carry_bucket.position = Vector3(-32.9, 0, -9.4)
	add_child(carry_bucket)

	chair = Chair.new()
	chair.name = "Chair"
	chair.position = Vector3(-32.6, 0, -9.6)
	chair.rotation.y = 0.4
	add_child(chair)

	# Žebříky (objeví se opřené o pravou stěnu garáže, až je hráč koupí).
	var lad_specs := [["ladder_small", 4.2, -16.6], ["ladder_ext", 6.0, -12.4]]
	for spec in lad_specs:
		var l := Ladder.new()
		l.name = "Ladder_" + spec[0]
		l.persist_id = spec[0]
		l.item_id = spec[0]
		l.length = spec[1]
		var off: float = spec[1] * sin(Ladder.ANGLE) + 0.04
		l.transform = Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), Vector3(-31.0 + off, 0.0, spec[2]))
		add_child(l)
		ladders.append(l)

	# Ostatní oblasti: při startu hry je postaví main.gd postupně (načítací obrazovka),
	# jinak (testy, samostatné použití) hned.
	if not defer_areas:
		for k in AREA_STEPS:
			build_area(k)

	menu_camera = Camera3D.new()
	menu_camera.fov = 60.0
	menu_camera.far = 1600.0
	add_child(menu_camera)
	_update_menu_camera(0.0)

	WorldMap.add_marker("base", Vector2(-34, -14), "Základna – garáž", Color(0.25, 0.55, 0.85))


## Počet oblastí, které se staví zvlášť (Předměstí, Město, Velkoměsto).
const AREA_STEPS := 3
const AREA_LABELS := ["Předměstí Javorov", "Město Brodec", "Velkoměsto Horizont"]
## true = oblasti postaví volající po krocích přes build_area().
var defer_areas := false
## Během zahřívání shaderů kamera menu nekrouží (řídí ji main.gd).
var warming := false


## Krátce ukáže déšť, aby se jeho materiál zkompiloval při načítání.
func warm_up_effects() -> void:
	if weather:
		weather.warm_up()


func build_area(k: int) -> void:
	match k:
		0:
			# Oblast II – Předměstí (daleko na východ, jezdí se tam autobusem).
			suburb = Suburb.new()
			suburb.name = "Suburb"
			add_child(suburb)
		1:
			# Oblast III – Město Brodec (daleko na západ, Etapa 4).
			city = City.new()
			city.name = "City"
			add_child(city)
		2:
			# Oblast IV – Velkoměsto Horizont (daleko na jih, Etapa 6).
			metropolis = Metropolis.new()
			metropolis.name = "Metropolis"
			add_child(metropolis)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and _clouds:
		_clouds.global_position = cam.global_position
	if menu_camera and menu_camera.current and not warming:
		_menu_t += delta
		_update_menu_camera(_menu_t)


func _update_menu_camera(t: float) -> void:
	var a := 0.5 + t * 0.025
	var center := Vector3(0, 2.0, -8)
	var pos := center + Vector3(sin(a) * 46.0, 15.0 + sin(t * 0.1) * 1.5, cos(a) * 46.0)
	menu_camera.global_transform = Transform3D(Basis.looking_at(center - pos, Vector3.UP), pos)


func _exclude_rect(x0: float, z0: float, x1: float, z1: float) -> void:
	_exclude.append(Rect2(Vector2(minf(x0, x1), minf(z0, z1)), Vector2(absf(x1 - x0), absf(z1 - z0))))


func _excluded(p: Vector2, margin: float = 0.0) -> bool:
	for r in _exclude:
		if r.grow(margin).has_point(p):
			return true
	return false


func _col_box(size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	_static.add_child(cs)


# ------------------------------------------------------------------ prostředí

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.55, 0.86)
	sky_mat.sky_horizon_color = Color(0.72, 0.84, 0.94)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.3, 0.38, 0.3)
	sky_mat.ground_horizon_color = Color(0.7, 0.8, 0.86)
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.ambient_light_color = Color(0.92, 0.9, 0.84)
	env.ambient_light_sky_contribution = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.83, 0.92)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(32.0), 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.04
	add_child(sun)

	var dome := SphereMesh.new()
	dome.radius = 900.0
	dome.height = 1800.0
	dome.radial_segments = 32
	dome.rings = 16
	var cm := ShaderMaterial.new()
	cm.shader = CLOUD_SHADER
	cm.render_priority = -100
	_clouds = MeshInstance3D.new()
	_clouds.name = "Clouds"
	_clouds.mesh = dome
	_clouds.material_override = cm
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds.extra_cull_margin = 16384.0
	weather = Weather.new()
	weather.name = "Weather"
	weather.env = env
	weather.sky_mat = sky_mat
	weather.sun = sun
	weather.clouds = cm
	add_child(weather)
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	atmosphere.env = env
	atmosphere.sky_mat = sky_mat
	atmosphere.sun = sun
	atmosphere.clouds = cm
	atmosphere.weather = weather
	weather.atmosphere = atmosphere
	add_child(atmosphere)
	_clouds.top_level = true
	add_child(_clouds)


func _ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	_ground_mat = mat
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = mat
	# o kousek níž, ať se neprolíná s rovnými místy zvlněného terénu
	mi.position.y = -0.03
	add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	_static.add_child(cs)


func _terrain() -> void:
	# seno u pole a okolí zastávky zůstanou na rovině
	_exclude_rect(22, 70, 88, 78)
	terrain = Terrain.new(_exclude)
	terrain.build(self, _static, _ground_mat)


## Výška zvlněného terénu (0 na rovině u domů a cest).
func terrain_h(x: float, z: float) -> float:
	return terrain.height(x, z) if terrain else 0.0


func _strip(b: MeshBuilder, x0: float, z0: float, x1: float, z1: float, y: float, color: Color, thick: float = 0.04) -> void:
	b.add_box(Vector3(absf(x1 - x0), thick, absf(z1 - z0)), Vector3((x0 + x1) * 0.5, y - thick * 0.5, (z0 + z1) * 0.5), color, Basis.IDENTITY, 0.0)


func _roads() -> void:
	var b := MeshBuilder.new(31)
	var asphalt := Color(0.33, 0.34, 0.36)
	var walk := Color(0.66, 0.65, 0.62)
	var curb := Color(0.78, 0.77, 0.74)
	# hlavní silnice
	_strip(b, -150, -3, 150, 3, 0.03, asphalt)
	for x in range(-148, 148, 6):
		_strip(b, x, -0.07, x + 3.0, 0.07, 0.035, Color(0.95, 0.95, 0.92), 0.01)
	_strip(b, -150, -3.2, 150, -3.0, 0.07, curb, 0.08)
	_strip(b, -150, 3.0, 150, 3.2, 0.07, curb, 0.08)
	_strip(b, -90, -5.0, 90, -3.2, 0.06, walk, 0.06)
	_strip(b, -90, 3.2, 90, 5.0, 0.06, walk, 0.06)
	_exclude_rect(-160, -5.5, 160, 5.5)
	WorldMap.add_rect(Rect2(-90, -5.0, 180, 1.8), Color(0.62, 0.62, 0.6))
	WorldMap.add_rect(Rect2(-90, 3.2, 180, 1.8), Color(0.62, 0.62, 0.6))
	WorldMap.add_rect(Rect2(-150, -3, 300, 6), Color(0.45, 0.46, 0.5))
	# boční cesta na sever k rybníku
	_strip(b, -10.5, -60, -6.5, -3.2, 0.03, asphalt.lightened(0.05))
	_exclude_rect(-11.5, -62, -5.5, -3)
	WorldMap.add_rect(Rect2(-10.5, -60, 4, 57), Color(0.5, 0.5, 0.54))
	# štěrkové příjezdy a chodníčky
	var gravel := Color(0.74, 0.68, 0.56)
	_strip(b, -36.5, -10.5, -31.5, -5.0, 0.025, gravel)    # garáž
	_strip(b, 16.3, -12.2, 17.7, -5.0, 0.025, Color(0.8, 0.72, 0.6))  # chodník k bungalovu
	# dlážděné předprostí obchodu se smíšeným zbožím (od výloh k chodníku)
	var pave := Color(0.7, 0.68, 0.64)
	_strip(b, -79.6, -11.4, -68.4, -5.0, 0.03, pave)
	for k in range(1, 11):
		_strip(b, -79.6, -11.4 + k * 0.6 - 0.012, -68.4, -11.4 + k * 0.6 + 0.012, 0.036, pave.darkened(0.15), 0.006)
	for k in range(1, 19):
		_strip(b, -79.6 + k * 0.6 - 0.012, -11.4, -79.6 + k * 0.6 + 0.012, -5.0, 0.036, pave.darkened(0.15), 0.006)
	_exclude_rect(-80, -12, -68, -5)
	WorldMap.add_rect(Rect2(-79.6, -11.4, 11.2, 6.4), pave)
	_exclude_rect(-37, -11, -31, -5)
	_exclude_rect(16, -12.5, 18, -5)
	# zastávka a místo pro žebříky, které přijedou autobusem
	_exclude_rect(BUS_X - 3.0, -12.0, BUS_X + 8.5, -5)
	b.to_instance(self, "Roads", false)


# ------------------------------------------------------------------ budovy

func _garage_base() -> void:
	var spec := {
		"name": "Garage", "position": Vector3(-34, 0, -14), "width": 6.0, "depth": 7.0,
		"found_h": 0.12, "wall_h": 2.9, "roof_h": 1.4, "seed": 3,
		"wall_color": Color(0.66, 0.3, 0.26), "roof_color": Color(0.3, 0.32, 0.36),
		"trim_color": Color(0.96, 0.95, 0.92), "interior": true, "interior_color": Color(0.82, 0.74, 0.62),
		"floor_color": Color(0.55, 0.55, 0.53), "chimney": false,
		"openings": [
			{"side": "front", "type": "opening", "u": 0.0, "width": 3.4, "height": 2.55, "sill": 0.0},
			# okna vlastní firmy = zakázka tutoriálu (zakladna_garaz)
			{"side": "left", "u": 0.5, "width": 1.0, "height": 0.8, "sill": 1.3, "id": "zakladna_w2_blato", "dirt": 0.7, "profile": "zakladna_blato"},
			{"side": "right", "u": -0.8, "width": 1.0, "height": 0.8, "sill": 1.3, "id": "zakladna_w1_prach", "dirt": 0.7, "profile": "zakladna_prach"},
			{"side": "front", "u": -2.35, "width": 0.7, "height": 0.75, "sill": 1.62, "id": "zakladna_w3_vrata", "dirt": 0.6, "profile": "zakladna_prach"},
		],
		"door_step": false,
		"interior_light": Vector3(0, 2.4, 0),
	}
	var g := HouseBuilder.build(self, spec)
	_exclude_rect(-38, -18.5, -30, -9)
	WorldMap.add_rect(Rect2(-37, -17.5, 6, 7), Color(0.66, 0.3, 0.26), "Garáž")

	# vybavení garáže
	var b := MeshBuilder.new(41)
	var wood := Color(0.6, 0.42, 0.26)
	# pracovní stůl u zadní stěny
	b.add_box(Vector3(2.4, 0.08, 0.8), Vector3(-1.0, 0.95, -2.9), wood)
	for sx: float in [-2.1, 0.1]:
		for sz: float in [-3.2, -2.6]:
			b.add_box(Vector3(0.07, 0.9, 0.07), Vector3(sx, 0.55, sz), wood.darkened(0.2))
	b.add_box(Vector3(2.3, 0.05, 0.6), Vector3(-1.0, 0.35, -2.9), wood.darkened(0.1))
	# tablet na stole
	b.add_box(Vector3(0.36, 0.025, 0.26), Vector3(-0.6, 1.005, -2.8), Color(0.12, 0.13, 0.15), Basis(Vector3.UP, 0.2))
	b.add_box(Vector3(0.32, 0.005, 0.22), Vector3(-0.6, 1.02, -2.8), Color(0.35, 0.75, 0.85), Basis(Vector3.UP, 0.2), 0.0)
	# police s kanystry
	b.add_box(Vector3(0.5, 2.0, 1.6), Vector3(2.55, 1.12, -1.6), wood.darkened(0.1))
	var cols := [Color(0.85, 0.3, 0.25), Color(0.3, 0.6, 0.85), Color(0.95, 0.8, 0.3), Color(0.4, 0.7, 0.4)]
	for k in 3:
		for j in 4:
			b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.22, 0.28, 0.22)), Vector3(2.45, 0.6 + k * 0.6, -2.2 + j * 0.38)), cols[(k + j) % 4])
	# nástěnka
	b.add_box(Vector3(1.6, 1.0, 0.04), Vector3(1.3, 1.75, -3.25), Color(0.7, 0.55, 0.4))
	for k in 5:
		b.add_box(Vector3(0.28, 0.32, 0.01), Vector3(0.75 + k * 0.28, 1.75 + (k % 2) * 0.12 - 0.06, -3.22), Color(0.98, 0.96, 0.85) if k % 2 == 0 else Color(0.85, 0.95, 0.98), Basis(Vector3.FORWARD, (k - 2) * 0.06), 0.0)
	Props.bucket(b, Vector3(1.9, 0.12, 1.6))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	g.add_child(mi)
	var gcol := StaticBody3D.new()
	g.add_child(gcol)
	for pair in [[Vector3(2.4, 1.0, 0.8), Vector3(-1.0, 0.5, -2.9)], [Vector3(0.5, 2.0, 1.6), Vector3(2.55, 1.12, -1.6)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = pair[0]
		cs.shape = bs
		cs.position = pair[1]
		gcol.add_child(cs)

	var sign := Label3D.new()
	# jeden řádek na zdi nad vraty – dvouřádkový nápis zakrývala střecha
	sign.text = "CLEAR VIEW · mytí oken"
	sign.font_size = 64
	sign.outline_size = 0
	sign.modulate = Color(1, 1, 1)
	sign.pixel_size = 0.0034
	sign.position = Vector3(0, 2.8, 3.62)
	g.add_child(sign)
	Props.board_behind(sign, Color(0.15, 0.35, 0.45), Vector2(0.14, 0.05), 0.04)
	var board := Label3D.new()
	board.text = "NÁSTĚNKA\nCíl: první zakázka\nKoupit stěrku :)"
	board.font_size = 28
	board.pixel_size = 0.004
	board.modulate = Color(0.2, 0.18, 0.15)
	board.outline_size = 0
	board.position = Vector3(1.3, 2.13, -3.2)
	g.add_child(board)

	var tablet := SimpleInteractable.create("[E] Pracovní tablet", func(_p): get_tree().call_group("ui_root", "open_tablet"), Vector3(0.5, 0.2, 0.4), Vector3(-0.6, 1.05, -2.8))
	g.add_child(tablet)
	var bucket := SimpleInteractable.create("[E] Vymáchat hadr / namočit houbičku, doplnit rozprašovač (kýbl)", _rinse_rag, Vector3(0.45, 0.5, 0.45), Vector3(1.9, 0.35, 1.6))
	bucket.add_to_group("water_source")
	g.add_child(bucket)
	# firemní základna: dílna, hala a dodávka se postaví po koupi (místo pro ně je volné)
	_exclude_rect(CompanyBase.HALL_POS.x - 5.0, CompanyBase.HALL_POS.z - 4.5, CompanyBase.HALL_POS.x + 5.0, CompanyBase.HALL_POS.z + 4.5)
	_exclude_rect(CompanyBase.VAN_POS.x - 1.8, CompanyBase.VAN_POS.z - 3.2, CompanyBase.VAN_POS.x + 1.8, CompanyBase.VAN_POS.z + 3.2)
	base = CompanyBase.create(self, g)
	# nabíjecí stojan na roboty (Etapa 5) na levé stěně garáže
	RobotCharger.build(g, Vector3(-2.76, 0, -1.9), PI * 0.5, "zakladna")

	# Staré firemní auto vedle garáže.
	var cb := MeshBuilder.new(42)
	Props.car(cb, Transform3D(Basis(Vector3.UP, 0.08), Vector3(-39.3, 0, -9.5)), Color(0.93, 0.93, 0.9))
	cb.add_box(Vector3(0.02, 0.35, 1.6), Vector3(-40.18, 0.75, -9.4), Color(0.25, 0.6, 0.7), Basis(Vector3.UP, 0.08), 0.0)
	cb.to_instance(self, "Van")
	_col_box(Vector3(1.8, 1.4, 4.0), Transform3D(Basis(Vector3.UP, 0.08), Vector3(-39.3, 0.7, -9.5)))
	_exclude_rect(-41.5, -12, -37, -7)


func _rinse_rag(player) -> void:
	player.cleaning.rinse()
	Audio.play("water", -6.0)
	var t := GameState.wipe_tool()
	if t and t.spreads > 0.0:
		Events.toast("Houbička je nasáklá vodou – roztírej ji po skle, namočí i bláto.", "info")
	else:
		Events.toast("Nástroj je vymáchaný a čistý.", "info")


## Sud nebo kohoutek s vodou u domu zákazníka.
func _water_point(pos: Vector3, tap: bool = false, yaw: float = 0.0) -> void:
	var b := MeshBuilder.new(int(pos.x * 7.0 + pos.z))
	if tap:
		Props.garden_tap(b, pos, yaw)
	else:
		Props.water_barrel(b, pos)
	b.to_instance(self, "Water")
	var label := "[E] Vymáchat nástroj a doplnit rozprašovač (kohoutek)" if tap else "[E] Vymáchat nástroj a doplnit rozprašovač (sud s vodou)"
	var it := SimpleInteractable.create(label, _rinse_rag, Vector3(0.65, 0.95, 0.65), pos + Vector3(0, 0.47, 0))
	it.add_to_group("water_source")
	add_child(it)


func _bungalow() -> void:
	var spec := {
		"name": "BungalowNovak", "position": Vector3(20, 0, -16), "width": 11.0, "depth": 8.0,
		"found_h": 0.35, "wall_h": 2.75, "roof_h": 1.7, "seed": 11,
		"wall_color": Color(0.96, 0.91, 0.8), "roof_color": Color(0.74, 0.34, 0.24),
		"trim_color": Color(0.98, 0.98, 0.96), "door_color": Color(0.22, 0.5, 0.58),
		"interior": true, "interior_color": Color(0.95, 0.92, 0.86), "floor_color": Color(0.74, 0.56, 0.38),
		"chimney_x": 3.0,
		"openings": [
			{"side": "front", "type": "door", "u": -2.9, "width": 1.0, "height": 2.15, "sill": 0.0},
			{"side": "front", "u": 1.8, "width": 2.0, "height": 1.45, "sill": 0.85, "id": "novak_w1_obyvak", "dirt": 1.0},
			{"side": "front", "u": -0.7, "width": 1.2, "height": 1.15, "sill": 1.05, "id": "novak_w2_kuchyn", "dirt": 0.9},
			{"side": "right", "u": 0.6, "width": 1.3, "height": 1.4, "sill": 0.85, "id": "novak_w3_loznice", "dirt": 1.1},
			{"side": "back", "u": 1.2, "width": 1.8, "height": 2.1, "sill": 0.0, "id": "novak_w4_terasa", "dirt": 0.85},
			{"side": "back", "u": -3.0, "width": 1.2, "height": 1.3, "sill": 0.95, "id": "novak_w5_pracovna", "dirt": 1.0},
			{"side": "left", "u": 0.0, "width": 1.0, "height": 1.0, "sill": 1.1, "id": "novak_w6_koupelna", "dirt": 1.2},
		],
		"furniture": [
			{"kind": "sofa", "pos": Vector3(1.8, 0, 1.6), "size": Vector3(2.2, 0.8, 0.9), "color": Color(0.36, 0.55, 0.62)},
			{"kind": "rug", "pos": Vector3(1.8, 0, 0.3), "size": Vector3(2.6, 0.01, 1.8), "color": Color(0.85, 0.65, 0.45)},
			{"kind": "table", "pos": Vector3(1.8, 0, 0.3), "size": Vector3(1.1, 0.42, 0.6), "color": Color(0.55, 0.38, 0.24)},
			{"kind": "lamp", "pos": Vector3(3.6, 0, 2.6)},
			{"kind": "plant", "pos": Vector3(0.2, 0, 3.2)},
			{"kind": "shelf", "pos": Vector3(4.6, 0, -0.5), "size": Vector3(0.4, 1.8, 1.6), "color": Color(0.6, 0.45, 0.3)},
			{"kind": "box", "pos": Vector3(-0.8, 0, 3.4), "size": Vector3(2.0, 0.9, 0.6), "color": Color(0.9, 0.9, 0.88)},
			{"kind": "bed", "pos": Vector3(4.2, 0, -2.5), "size": Vector3(1.5, 0.6, 2.0), "color": Color(0.85, 0.55, 0.45)},
			{"kind": "table", "pos": Vector3(1.0, 0, -2.4), "size": Vector3(1.4, 0.75, 0.9), "color": Color(0.62, 0.45, 0.3)},
			{"kind": "box", "pos": Vector3(-3.0, 0, -3.3), "size": Vector3(1.4, 0.75, 0.6), "color": Color(0.5, 0.42, 0.35)},
			{"kind": "plant", "pos": Vector3(-4.6, 0, -3.2)},
			{"kind": "box", "pos": Vector3(-1.6, 0, 0.0), "size": Vector3(0.1, 2.7, 3.0), "color": Color(0.95, 0.92, 0.86)},
		],
		"interior_light": Vector3(1.5, 2.2, 0.5),
	}
	var house := HouseBuilder.build(self, spec)
	_exclude_rect(11, -27, 30, -4.5)
	WorldMap.add_rect(Rect2(14.5, -20, 11, 8), Color(0.95, 0.62, 0.3), "Bungalov Novákových")

	var b := MeshBuilder.new(51)
	# terasa za domem
	var deck := Color(0.66, 0.47, 0.3)
	b.add_box(Vector3(4.4, 0.3, 2.4), Vector3(19.6, 0.15, -21.2), deck)
	for k in 11:
		b.add_box(Vector3(4.4, 0.012, 0.012), Vector3(19.6, 0.305, -20.05 - k * 0.215), deck.darkened(0.2), Basis.IDENTITY, 0.0)
	_col_box(Vector3(4.4, 0.3, 2.4), Transform3D(Basis.IDENTITY, Vector3(19.6, 0.15, -21.2)))
	Props.bench(b, Transform3D(Basis(Vector3.UP, PI), Vector3(20.6, 0.3, -22.1)))
	# stříška nad vchodem
	b.add_box(Vector3(1.8, 0.1, 1.2), Vector3(17.1, 2.75, -11.5), Color(0.74, 0.34, 0.24))
	for sx: float in [16.4, 17.8]:
		b.add_box(Vector3(0.1, 2.4, 0.1), Vector3(sx, 1.55, -11.0), Color(0.98, 0.98, 0.96))
	# zahrada: plot, záhonky, keře
	var white := Color(0.97, 0.97, 0.94)
	Props.picket_fence(b, _static, Vector3(11.5, 0, -FENCE_Z), Vector3(29.5, 0, -FENCE_Z), white, 5.5, 1.6)
	Props.picket_fence(b, _static, Vector3(11.5, 0, -FENCE_Z), Vector3(11.5, 0, -27.0), white)
	Props.picket_fence(b, _static, Vector3(29.5, 0, -FENCE_Z), Vector3(29.5, 0, -27.0), white)
	Props.picket_fence(b, _static, Vector3(11.5, 0, -27.0), Vector3(29.5, 0, -27.0), white)
	var bed := Color(0.42, 0.3, 0.22)
	b.add_box(Vector3(6.0, 0.12, 0.8), Vector3(23.5, 0.06, -10.6), bed)
	b.add_box(Vector3(2.5, 0.12, 0.8), Vector3(12.9, 0.06, -10.6), bed)
	var fcols := [Color(0.95, 0.35, 0.4), Color(0.98, 0.8, 0.3), Color(0.75, 0.45, 0.9), Color(1, 1, 1), Color(1.0, 0.55, 0.3)]
	for k in 48:
		var p := Vector3(_rng.randf_range(20.7, 26.3), 0.12, _rng.randf_range(-10.9, -10.3))
		if k > 36:
			p = Vector3(_rng.randf_range(11.9, 14.0), 0.12, _rng.randf_range(-10.9, -10.3))
		b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.16, 0.2, 0.16)), p + Vector3(0, 0.05, 0)), Color(0.32, 0.56, 0.28), 0.06)
		b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.1), p + Vector3(0, 0.2, 0)), fcols[k % fcols.size()], 0.04)
	Props.mailbox(b, Vector3(15.0, 0, -5.6), 0.0, Color(0.85, 0.25, 0.2))
	b.to_instance(self, "BungalowGarden")
	_water_point(Vector3(13.2, 0, -19.0), true, PI * 0.5)

	Props.sign_post(self, Vector3(18.9, 0, -5.0), 0.0, "Bungalov Novákovi")

	# keře a stromy na zahradě (bez multimeshe, jen pár kusů)
	var bush := Nature.bush_mesh(1)
	var xfs := []
	for p in [Vector3(12.6, 0, -6.0), Vector3(28.3, 0, -6.2), Vector3(12.8, 0, -25.6), Vector3(28.0, 0, -25.4), Vector3(26.8, 0, -13.0)]:
		xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.9, 1.3)), p))
	Nature.multimesh(self, bush, xfs, true, [], 0)
	var apple := Nature.tree_mesh(3)
	Nature.multimesh(self, apple, [Transform3D(Basis(Vector3.UP, 1.0), Vector3(14.0, 0, -24.0)), Transform3D(Basis(Vector3.UP, 2.0).scaled(Vector3.ONE * 0.9), Vector3(27.2, 0, -23.5))], true, [], 0)
	for p in [Vector3(14.0, 0, -24.0), Vector3(27.2, 0, -23.5)]:
		_tree_collider(p)
	house.set_meta("contract", "novak_bungalow")


## Zákazníci z domů na vsi: [jméno do nabídky, kdo píše].
const VILLAGE_CLIENTS := [
	["Svobodovi", "Paní Svobodová"], ["paní Malá", "Paní Malá"], ["Procházkovi", "Pan Procházka"],
	["Černí", "Paní Černá"], ["Veselí", "Pan Veselý"], ["pan Pokorný", "Pan Pokorný"],
	["Marešovi", "Paní Marešová"], ["Hájkovi", "Pan Hájek"], ["Kratochvílovi", "Paní Kratochvílová"],
]


func _village_houses() -> void:
	var palette := [
		[Color(0.97, 0.86, 0.55), Color(0.42, 0.36, 0.34), Color(0.3, 0.5, 0.4)],
		[Color(0.7, 0.82, 0.9), Color(0.75, 0.36, 0.26), Color(0.95, 0.95, 0.95)],
		[Color(0.78, 0.9, 0.78), Color(0.33, 0.35, 0.4), Color(0.55, 0.35, 0.25)],
		[Color(0.96, 0.78, 0.74), Color(0.6, 0.3, 0.22), Color(0.35, 0.45, 0.6)],
		[Color(0.95, 0.93, 0.88), Color(0.28, 0.3, 0.33), Color(0.4, 0.55, 0.35)],
		[Color(0.98, 0.9, 0.7), Color(0.68, 0.33, 0.24), Color(0.6, 0.3, 0.3)],
	]
	var houses := [
		[Vector3(-58, 0, -16), 0.0, 9.0, 7.0],
		[Vector3(2, 0, -17), 0.0, 8.0, 6.5],
		[Vector3(48, 0, -17), 0.0, 9.5, 7.0],
		[Vector3(-48, 0, 15), PI, 8.5, 7.0],
		[Vector3(-20, 0, 16), PI, 10.0, 7.5],
		[Vector3(8, 0, 15), PI, 8.0, 6.5],
		[Vector3(36, 0, 16), PI, 9.0, 7.0],
		[Vector3(64, 0, 15), PI, 8.0, 6.5],
		[Vector3(-80, 0, 15), PI, 9.0, 7.0],
	]
	var b := MeshBuilder.new(61)
	var hedges := MeshBuilder.new(62)
	for i in houses.size():
		var h: Array = houses[i]
		var pal: Array = palette[i % palette.size()]
		var w: float = h[2]
		var d: float = h[3]
		var fb := i % 2 == 0
		var spec := {
			"name": "House%d" % i, "position": h[0], "rotation_y": h[1], "width": w, "depth": d,
			"found_h": 0.3, "wall_h": 2.7 + (i % 3) * 0.15, "roof_h": 1.8 + (i % 2) * 0.4, "seed": 100 + i,
			"wall_color": pal[0], "roof_color": pal[1], "shutter_color": pal[2], "door_color": pal[2].darkened(0.1),
			"chimney_x": (-1.0 if i % 2 else 1.0) * w * 0.25,
			"interior": true, "styles": ["house"], "interior_color": pal[0].lightened(0.55), "floor_color": Color(0.66, 0.48, 0.32),
			"openings": [
				{"side": "front", "type": "door", "u": -w * 0.25, "width": 1.0, "height": 2.1, "sill": 0.0},
				{"side": "front", "u": w * 0.15, "width": 1.2, "height": 1.3, "sill": 0.9, "shutters": true, "flowerbox": fb, "id": "ves_h%d_w1" % i},
				{"side": "front", "u": w * 0.36, "width": 0.9, "height": 1.2, "sill": 0.95, "shutters": not fb, "id": "ves_h%d_w2" % i},
				{"side": "back", "u": 0.0, "width": 1.4, "height": 1.3, "sill": 0.9, "id": "ves_h%d_w3" % i},
				{"side": "left", "u": 0.0, "width": 1.1, "height": 1.2, "sill": 0.95, "shutters": true, "id": "ves_h%d_w4" % i},
				{"side": "right", "u": -0.6, "width": 1.1, "height": 1.2, "sill": 0.95, "id": "ves_h%d_w5" % i},
			],
		}
		HouseBuilder.build(self, spec)
		var pos: Vector3 = h[0]
		var front := 1.0 if h[1] == 0.0 else -1.0
		# Dům na vsi = zákazník, který občas pošle poptávku (ContractManager generuje nabídky).
		var cname: Array = VILLAGE_CLIENTS[i]
		ContractManager.register_client({
			"id": "ves_h%d" % i, "name": cname[0], "who": cname[1],
			"pos": Vector2(pos.x - w * 0.25 * front, pos.z + front * (d * 0.5 + 2.0)),
			"front": ["ves_h%d_w1" % i, "ves_h%d_w2" % i],
			"all": ["ves_h%d_w1" % i, "ves_h%d_w2" % i, "ves_h%d_w3" % i, "ves_h%d_w4" % i, "ves_h%d_w5" % i],
			"tree": i % 3 == 1,
		})
		_exclude_rect(pos.x - w * 0.5 - 1.5, pos.z - d * 0.5 - 1.5, pos.x + w * 0.5 + 1.5, pos.z + d * 0.5 + 1.5)
		WorldMap.add_rect(Rect2(pos.x - w * 0.5, pos.z - d * 0.5, w, d), (pal[1] as Color).lightened(0.25))
		# předzahrádka: plot za chodníkem, chodníček, schránka
		var fence_z := -FENCE_Z if front > 0 else FENCE_Z
		var door_x := pos.x - w * 0.25 * front
		var fc: Color = [Color(0.97, 0.97, 0.94), Color(0.62, 0.45, 0.3), Color(0.5, 0.62, 0.5)][i % 3]
		var px0 := pos.x - w * 0.5 - 3.5
		var px1 := pos.x + w * 0.5 + 3.5
		Props.picket_fence(b, _static, Vector3(px0, 0, fence_z), Vector3(px1, 0, fence_z), fc, door_x - px0, 1.4)
		# pozemek oddělený od sousedů: boky a zadní strana plotem, nebo živým plotem
		var back_z := pos.z - front * (d * 0.5 + 4.5)
		if i == 5:
			back_z = 28.6   # zahrada se sklenikem paní Dvořákové
		_plot_border(b, hedges, Vector3(px0, 0, fence_z), Vector3(px0, 0, back_z), fc, i % 3 == 1)
		_plot_border(b, hedges, Vector3(px1, 0, fence_z), Vector3(px1, 0, back_z), fc, i % 3 == 1)
		_plot_border(b, hedges, Vector3(px0, 0, back_z), Vector3(px1, 0, back_z), fc, i % 3 != 0)
		var path_z0 := pos.z + front * d * 0.5
		_strip(b, door_x - 0.6, minf(path_z0, fence_z), door_x + 0.6, maxf(path_z0, fence_z), 0.025, Color(0.8, 0.72, 0.6))
		Props.mailbox(b, Vector3(door_x + 1.2, 0, fence_z + front * -0.2), 0.0 if front > 0 else PI, [Color(0.85, 0.25, 0.2), Color(0.2, 0.45, 0.75), Color(0.95, 0.75, 0.2)][i % 3])
		if i == 5:
			# chodníček od domu kolem západní stěny ke dveřím skleníku
			var gp := Color(0.8, 0.72, 0.6)
			_strip(b, 3.2, 10.4, door_x - 0.6, 11.6, 0.025, gp)
			_strip(b, 2.0, 10.4, 3.2, 25.6, 0.025, gp)
			_strip(b, 3.2, 24.4, 5.72, 25.6, 0.025, gp)
		if i == 4:
			Props.car(b, Transform3D(Basis(Vector3.UP, 0.0), Vector3(pos.x + w * 0.5 + 1.8, 0, pos.z - 3.0)), Color(0.85, 0.25, 0.22))
			_col_box(Vector3(1.8, 1.4, 4.0), Transform3D(Basis.IDENTITY, Vector3(pos.x + w * 0.5 + 1.8, 0.7, pos.z - 3.0)))
		if i == 2:
			Props.car(b, Transform3D(Basis(Vector3.UP, PI), Vector3(pos.x - w * 0.5 - 2.0, 0, pos.z + 1.0)), Color(0.25, 0.45, 0.7))
			_col_box(Vector3(1.8, 1.4, 4.0), Transform3D(Basis.IDENTITY, Vector3(pos.x - w * 0.5 - 2.0, 0.7, pos.z + 1.0)))

	# Obchod se smíšeným zbožím – nákup vybavení a zároveň zakázka (výlohy).
	var shop := {
		"name": "Shop", "position": Vector3(-74, 0, -15), "width": 10.0, "depth": 7.0,
		"found_h": 0.25, "wall_h": 3.1, "roof_h": 1.5, "seed": 300,
		"wall_color": Color(0.92, 0.95, 0.97), "roof_color": Color(0.25, 0.5, 0.42), "chimney": false,
		"interior": true, "interior_color": Color(0.96, 0.95, 0.9), "floor_color": Color(0.62, 0.6, 0.56),
		"openings": [
			{"side": "front", "type": "door", "u": 0.0, "width": 1.4, "height": 2.3, "sill": 0.0, "color": Color(0.3, 0.55, 0.45)},
			{"side": "front", "u": -3.0, "width": 2.6, "height": 1.7, "sill": 0.6, "id": "obchod_w1_vyloha_l", "dirt": 0.9, "profile": "obchod_mastnota"},
			{"side": "front", "u": 3.0, "width": 2.6, "height": 1.7, "sill": 0.6, "id": "obchod_w2_vyloha_p", "dirt": 0.9, "profile": "obchod_mastnota"},
			{"side": "left", "u": 0.0, "width": 1.2, "height": 1.2, "sill": 0.95, "id": "obchod_w3_bok_l", "dirt": 1.0, "profile": "kuchyn_mastnota"},
			{"side": "right", "u": 0.0, "width": 1.2, "height": 1.2, "sill": 0.95, "id": "obchod_w4_bok_p", "dirt": 1.0},
		],
		"furniture": [
			{"kind": "shelf", "pos": Vector3(-3.0, 0, 1.9), "size": Vector3(2.4, 1.2, 0.4), "color": Color(0.62, 0.46, 0.3)},
			{"kind": "shelf", "pos": Vector3(3.0, 0, 1.9), "size": Vector3(2.4, 1.2, 0.4), "color": Color(0.62, 0.46, 0.3)},
			{"kind": "shelf", "pos": Vector3(-2.5, 0, -3.0), "size": Vector3(3.5, 2.0, 0.5), "color": Color(0.6, 0.45, 0.3)},
			{"kind": "shelf", "pos": Vector3(2.5, 0, -3.0), "size": Vector3(3.5, 2.0, 0.5), "color": Color(0.6, 0.45, 0.3)},
			{"kind": "box", "pos": Vector3(0.0, 0, -0.8), "size": Vector3(2.2, 1.0, 0.7), "color": Color(0.75, 0.55, 0.35)},
			{"kind": "plant", "pos": Vector3(-4.4, 0, 0.0)},
			{"kind": "lamp", "pos": Vector3(4.4, 0, 0.0)},
		],
		"interior_light": Vector3(0, 2.6, 0),
	}
	HouseBuilder.build(self, shop)
	_exclude_rect(-81, -20, -67, -9)
	WorldMap.add_rect(Rect2(-79, -18.5, 10, 7), Color(0.3, 0.6, 0.5), "Obchod")
	WorldMap.add_marker("shop", Vector2(-74, -10.5), "Obchod s vybavením", Color(0.2, 0.65, 0.45))
	# štít obchodu: zelená deska s rámečkem nad vchodem a menší cedulka pod ní
	var shop_sign := Label3D.new()
	shop_sign.text = "SMÍŠENÉ ZBOŽÍ"
	shop_sign.font_size = 64
	shop_sign.pixel_size = 0.006
	shop_sign.outline_size = 6
	shop_sign.outline_modulate = Color(0.12, 0.3, 0.25)
	shop_sign.position = Vector3(-74, 3.02, -11.38)
	add_child(shop_sign)
	Props.board_behind(shop_sign, Color(0.2, 0.45, 0.38), Vector2(0.25, 0.08), 0.06, Color(0.95, 0.93, 0.85))
	var hours := Label3D.new()
	hours.text = "Potřeby pro domácnost a mytí oken"
	hours.font_size = 26
	hours.pixel_size = 0.004
	hours.outline_size = 0
	hours.modulate = Color(0.15, 0.3, 0.26)
	hours.position = Vector3(-74, 2.58, -11.4)
	add_child(hours)
	Props.board_behind(hours, Color(0.96, 0.94, 0.86), Vector2(0.1, 0.04), 0.03)
	# značka nad obchodem pro tutoriál (ukáže, kde se nakupuje)
	var mark := Label3D.new()
	mark.name = "ShopMarker"
	mark.text = "▼\nOBCHOD"
	mark.font_size = 72
	mark.pixel_size = 0.008
	mark.outline_size = 14
	mark.modulate = Color(0.45, 1.0, 0.6)
	mark.outline_modulate = Color(0.05, 0.25, 0.12)
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.fixed_size = false
	mark.position = Vector3(-74, 6.6, -12.0)
	mark.visible = false
	mark.add_to_group("tutorial_shop_marker")
	add_child(mark)
	var counter := SimpleInteractable.create("[E] Nakupovat – Smíšené zboží", func(_p): get_tree().call_group("ui_root", "open_shop"), Vector3(1.4, 2.2, 0.2), Vector3(-74, 1.35, -11.25))
	add_child(counter)
	_water_point(Vector3(-68.2, 0, -12.2), true, PI * 0.5)
	b.to_instance(self, "VillageGardens")
	var hm := hedges.to_instance(self, "Hedges")
	hm.material_override = Nature.foliage_mat(0)


## Hranice pozemku: laťkový plot, nebo živý plot (keře zastřižené do zdi).
## Pod plotem neroste tráva a nestojí na něm stromy.
func _plot_border(b: MeshBuilder, hedges: MeshBuilder, a: Vector3, c: Vector3, color: Color, hedge: bool) -> void:
	if hedge:
		Props.hedge(hedges, _static, a, c)
	else:
		Props.picket_fence(b, _static, a, c, color)
	var m := 0.5 if hedge else 0.25
	_exclude_rect(minf(a.x, c.x) - m, minf(a.z, c.z) - m, maxf(a.x, c.x) + m, maxf(a.z, c.z) + m)


## Rybník je zapuštěný do země: v rovině trávy je v elipse díra (ground shader),
## pod ní miska dna a hladina pod úrovní terénu, kolem kameny a rákosí.
func _pond() -> void:
	_ground_mat.set_shader_parameter("pond_center", POND_C)
	_ground_mat.set_shader_parameter("pond_radii", POND_R)
	add_child(_pond_basin())
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.04
	disc.radial_segments = 32
	var mi := MeshInstance3D.new()
	mi.name = "PondWater"
	mi.mesh = disc
	mi.material_override = Mats.water()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(POND_C.x, POND_WATER_Y - 0.02, POND_C.y)
	mi.scale = Vector3(POND_R.x * 0.965, 1.0, POND_R.y * 0.965)
	add_child(mi)
	var b := MeshBuilder.new(71)
	# kameny na břehu (přes šev díry v trávě)
	for k in 34:
		var a := k * TAU / 34.0 + _rng.randf_range(-0.04, 0.04)
		var r := _rng.randf_range(0.99, 1.04)
		var p := Vector3(POND_C.x + cos(a) * POND_R.x * r, -0.02, POND_C.y + sin(a) * POND_R.y * r)
		b.add("sphere", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3(0.8, 0.32, 0.6) * _rng.randf_range(0.65, 1.1)), p), Color(0.6, 0.6, 0.57).lightened(_rng.randf_range(-0.08, 0.06)), 0.1)
	# rákosí rostoucí z vody u břehu
	for k in 9:
		var a := _rng.randf() * TAU
		var p := Vector3(POND_C.x + cos(a) * POND_R.x * 0.88, POND_WATER_Y, POND_C.y + sin(a) * POND_R.y * 0.88)
		for j in 7:
			var h := _rng.randf_range(0.9, 1.5)
			var q := p + Vector3(_rng.randf_range(-0.35, 0.35), h * 0.5, _rng.randf_range(-0.35, 0.35))
			b.add("cyl6", Transform3D(Basis(Vector3.RIGHT, _rng.randf_range(-0.15, 0.15)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.15, 0.15)) * Basis.from_scale(Vector3(0.045, h, 0.045)), q), Color(0.45, 0.6, 0.3), 0.06)
			if j % 3 == 0:
				b.add("cyl6", Transform3D(Basis.from_scale(Vector3(0.08, 0.22, 0.08)), q + Vector3(0, h * 0.5 - 0.05, 0)), Color(0.42, 0.3, 0.18), 0.05)
	# lekníny
	for k in 12:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.2, 0.75)
		var p := Vector3(POND_C.x + cos(a) * POND_R.x * r, POND_WATER_Y + 0.01, POND_C.y + sin(a) * POND_R.y * r)
		var s := _rng.randf_range(0.35, 0.6)
		b.add("cyl10", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3(s, 0.012, s)), p), Color(0.3, 0.55, 0.28), 0.06)
		if k % 4 == 0:
			b.add("sphere", Transform3D(Basis.from_scale(Vector3(0.14, 0.09, 0.14)), p + Vector3(0.05, 0.05, 0.03)), Color(0.98, 0.85, 0.9), 0.03)
	# lavičky čelem k rybníku
	Props.bench(b, Transform3D(Basis(Vector3.UP, PI), Vector3(-24, 0, -32.5)))
	Props.bench(b, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-37.5, 0, -42)))
	b.to_instance(self, "Pond")
	_exclude_rect(-37, -51, -11, -33)
	WorldMap.add_rect(Rect2(-35.7, -47.9, 23.4, 11.8), Color(0.35, 0.6, 0.75), "Rybník")
	# Nerovnoměrně škálovaný tvar Jolt nepodporuje – použijeme dva kruhy.
	for cx: float in [-29.0, -19.0]:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 6.5
		cyl.height = 1.0
		cs.shape = cyl
		cs.position = Vector3(cx, 0.3, -42)
		_static.add_child(cs)


## Miska dna rybníka: soustředné elipsy od okraje díry (výška trávy) do hloubky.
func _pond_basin() -> MeshInstance3D:
	var b := MeshBuilder.new(72)
	var rings: Array[float] = [1.0, 0.97, 0.92, 0.84, 0.72, 0.55, 0.32, 0.0]
	const SEG := 40
	var pts := []
	for s in rings:
		var row := []
		var depth := -0.03 - 0.95 * pow(1.0 - s * s, 0.6)
		for k in SEG:
			var a := k * TAU / SEG
			var wob := 1.0 if s >= 0.999 or s <= 0.001 else 1.0 + sin(a * 3.0 + s * 7.0) * 0.02
			row.append(Vector3(POND_C.x + cos(a) * POND_R.x * s * wob, depth, POND_C.y + sin(a) * POND_R.y * s * wob))
		pts.append(row)
	for r in rings.size() - 1:
		var s: float = rings[r]
		var col := Color(0.4, 0.33, 0.22).lerp(Color(0.2, 0.26, 0.2), clampf((1.0 - s) * 1.6, 0.0, 1.0))
		for k in SEG:
			var a: Vector3 = pts[r][k]
			var c: Vector3 = pts[r][(k + 1) % SEG]
			var d: Vector3 = pts[r + 1][k]
			var e: Vector3 = pts[r + 1][(k + 1) % SEG]
			var sh := 1.0 + _rng.randf_range(-0.05, 0.05)
			b.add_tri(a, c, d, Color(col.r * sh, col.g * sh, col.b * sh))
			if r + 1 < rings.size() - 1:
				b.add_tri(c, e, d, Color(col.r * sh, col.g * sh, col.b * sh))
	var mi := MeshInstance3D.new()
	mi.name = "PondBasin"
	mi.mesh = b.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _fields() -> void:
	var b := MeshBuilder.new(81)
	var fields := [
		[Rect2(-110, 30, 60, 38), Color(0.85, 0.75, 0.38), true],
		[Rect2(-40, 32, 50, 34), Color(0.5, 0.68, 0.32), true],
		[Rect2(20, 30, 70, 40), Color(0.92, 0.82, 0.45), false],
		[Rect2(60, -70, 50, 40), Color(0.55, 0.72, 0.3), true],
	]
	for f in fields:
		var r: Rect2 = f[0]
		var col: Color = f[1]
		b.add_box(Vector3(r.size.x, 0.05, r.size.y), Vector3(r.get_center().x, 0.02, r.get_center().y), col.darkened(0.25), Basis.IDENTITY, 0.0)
		var rows := int(r.size.y / 1.2)
		for k in rows:
			var z := r.position.y + 0.6 + k * 1.2
			var h := 0.35 if f[2] else 0.6
			b.add("prism", Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(0.8, h, r.size.x - 1.0)), Vector3(r.get_center().x, h * 0.5 + 0.04, z)), col.lightened(_rng.randf_range(-0.05, 0.05)), 0.03)
		WorldMap.add_rect(r, col)
		_exclude.append(r.grow(1.0))
	for k in 7:
		Props.hay_bale(b, Vector3(_rng.randf_range(25, 85), 0, _rng.randf_range(72, 76)), _rng.randf() * PI)
	b.to_instance(self, "Fields", true)


func _street_props() -> void:
	var b := MeshBuilder.new(91)
	var lamps := []
	for x: float in [-70.0, -46.0, -25.5, 5.0, 30.0, 54.0, 78.0]:
		Props.lamp_post(b, Vector3(x, 0, -4.4), -PI * 0.5, lamps)
	Props.lamp_lights(self, lamps)
	# autobusová zastávka (na volném místě za chodníkem, ne na cizím pozemku)
	var bx := BUS_X
	b.add_box(Vector3(3.0, 0.1, 1.5), Vector3(bx, 2.4, -6.0), Color(0.3, 0.35, 0.4))
	for sx: float in [-1.4, 1.4]:
		b.add_box(Vector3(0.08, 2.35, 0.08), Vector3(bx + sx, 1.175, -6.6), Color(0.3, 0.35, 0.4))
		b.add_box(Vector3(0.08, 2.35, 0.08), Vector3(bx + sx, 1.175, -5.4), Color(0.3, 0.35, 0.4))
	b.add_box(Vector3(2.7, 2.2, 0.04), Vector3(bx, 1.2, -6.66), Color(0.65, 0.8, 0.85), Basis.IDENTITY, 0.0)
	Props.bench(b, Transform3D(Basis.IDENTITY, Vector3(bx, 0, -6.2)))
	_col_box(Vector3(3.0, 2.4, 0.2), Transform3D(Basis.IDENTITY, Vector3(bx, 1.2, -6.7)))
	# dlažba pod přístřeškem a k jízdním řádům
	_strip(b, bx - 1.8, -7.0, bx + 6.0, -5.0, 0.04, Color(0.62, 0.61, 0.58), 0.05)
	# cedule obce
	for sx: float in [-92.0, 92.0]:
		b.add_box(Vector3(0.08, 2.0, 0.08), Vector3(sx, 1.0, -4.0), Color(0.5, 0.5, 0.5))
		b.add_box(Vector3(0.06, 0.7, 1.8), Vector3(sx, 2.0, -4.0), Color(0.98, 0.98, 0.95))
	b.to_instance(self, "StreetProps")
	for sx: float in [-92.0, 92.0]:
		for side: float in [-1.0, 1.0]:
			var l := Label3D.new()
			l.text = "Lipová Lhota"
			l.font_size = 48
			l.pixel_size = 0.005
			l.modulate = Color(0.1, 0.1, 0.12)
			l.outline_size = 0
			l.position = Vector3(sx + side * 0.035, 2.0, -4.0)
			l.rotation.y = side * PI * 0.5
			add_child(l)
	# jízdní řády = cesty autobusem (vlastní mesh – dřív se kreslily do už hotového a nebyly vidět)
	var pb := MeshBuilder.new(92)
	pb.add_box(Vector3(0.08, 2.2, 0.08), Vector3(bx + 2.4, 1.1, -5.6), Color(0.5, 0.5, 0.52))
	pb.add_box(Vector3(0.5, 0.65, 0.05), Vector3(bx + 2.4, 1.7, -5.55), Color(0.95, 0.85, 0.2))
	var bus := SimpleInteractable.create("", func(p): bus_travel(Suburb.AREA_ID, p), Vector3(0.6, 2.2, 0.4), Vector3(bx + 2.4, 1.1, -5.6))
	bus.set_meta("interactable", self)
	bus.name = "BusStopVillage"
	add_child(bus)
	_bus_stop = bus
	# druhý jízdní řád: do města
	pb.add_box(Vector3(0.08, 2.2, 0.08), Vector3(bx + 3.6, 1.1, -5.6), Color(0.5, 0.5, 0.52))
	pb.add_box(Vector3(0.5, 0.65, 0.05), Vector3(bx + 3.6, 1.7, -5.55), Color(0.85, 0.3, 0.25))
	pb.add_box(Vector3(0.08, 2.2, 0.08), Vector3(bx + 4.8, 1.1, -5.6), Color(0.5, 0.5, 0.52))
	pb.add_box(Vector3(0.5, 0.65, 0.05), Vector3(bx + 4.8, 1.7, -5.55), Color(0.2, 0.45, 0.75))
	pb.to_instance(self, "BusPosts")
	var bus_metro := SimpleInteractable.create("[E] Autobus do Velkoměsta Horizont (zakázky od úrovně %d)" % Metropolis.UNLOCK_LEVEL, func(p): bus_travel(Metropolis.AREA_ID, p), Vector3(0.6, 2.2, 0.4), Vector3(bx + 4.8, 1.1, -5.6))
	bus_metro.name = "BusStopVillageMetro"
	add_child(bus_metro)
	var bus_city := SimpleInteractable.create("[E] Autobus do Brodce – Město (zakázky od úrovně %d)" % City.UNLOCK_LEVEL, func(p): bus_travel(City.AREA_ID, p), Vector3(0.6, 2.2, 0.4), Vector3(bx + 3.6, 1.1, -5.6))
	bus_city.name = "BusStopVillageCity"
	add_child(bus_city)
	for lt: Array in [["Javorov", bx + 2.4], ["Brodec", bx + 3.6], ["Horizont", bx + 4.8]]:
		var tl := Label3D.new()
		tl.text = lt[0]
		tl.font_size = 22
		tl.pixel_size = 0.006
		tl.modulate = Color(0.1, 0.1, 0.1)
		tl.outline_size = 0
		tl.position = Vector3(lt[1], 2.15, -5.5)
		add_child(tl)
		Props.board_behind(tl, Color(0.96, 0.96, 0.94), Vector2(0.06, 0.03), 0.03)
	var stop := Label3D.new()
	stop.text = "Lipová Lhota, náves"
	stop.font_size = 36
	stop.pixel_size = 0.004
	stop.outline_size = 0
	stop.modulate = Color(0.1, 0.12, 0.15)
	stop.position = Vector3(bx, 2.75, -5.3)
	add_child(stop)
	Props.board_behind(stop, Color(0.95, 0.85, 0.2), Vector2(0.1, 0.05), 0.04, Color(0.25, 0.3, 0.35))
	WorldMap.add_marker("village", Vector2(BUS_X + 1.5, -8.0), "Náves", Color(0.6, 0.6, 0.6))


func _tree_collider(p: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.25
	cyl.height = 3.0
	cs.shape = cyl
	cs.position = p + Vector3(0, 1.5, 0)
	_static.add_child(cs)


func _nature() -> void:
	var trees := [[], [], [], []]
	var area := Rect2(-140, -85, 280, 175)
	var placed := 0
	var tries := 0
	while placed < 240 and tries < 6000:
		tries += 1
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if _excluded(p, 2.5):
			continue
		# hustěji dál od silnice, řidčeji ve vesnici
		if absf(p.y) < 25.0 and absf(p.x) < 90.0 and _rng.randf() < 0.65:
			continue
		var kind := 0
		var r := _rng.randf()
		if p.y < -50.0 or absf(p.x) > 100.0:
			kind = 1 if r < 0.6 else (2 if r < 0.8 else 0)
		else:
			kind = 0 if r < 0.55 else (2 if r < 0.8 else (3 if r < 0.9 else 1))
		var s := _rng.randf_range(0.8, 1.35)
		var ty := terrain_h(p.x, p.y) - 0.1
		trees[kind].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, ty, p.y)))
		_exclude.append(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)))
		_tree_collider(Vector3(p.x, ty, p.y))
		placed += 1
	for k in 4:
		if not trees[k].is_empty():
			Nature.multimesh(self, Nature.tree_mesh(k), trees[k], true, [], 0)
	# keře
	for kind in 3:
		var xfs := []
		for i in 45:
			var p := Vector2(_rng.randf_range(-110, 110), _rng.randf_range(-60, 28))
			if _excluded(p, 0.8):
				continue
			xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.3)), Vector3(p.x, terrain_h(p.x, p.y) - 0.05, p.y)))
		Nature.multimesh(self, Nature.bush_mesh(kind), xfs, true, [], 0)
	# tráva – trsy ve čtvercích 16 m (vzdálené se nekreslí), houpou se ve větru
	Nature.grass_field(self, Rect2(-135, -85, 270, 170), 48000, func(p: Vector2) -> bool: return _excluded(p, 0.2), terrain_h, _rng)
	var flowers := []
	var fcolors := []
	var palette := [Color(1, 0.95, 0.95), Color(1.0, 0.85, 0.3), Color(0.75, 0.55, 1.0), Color(1.0, 0.5, 0.55)]
	for i in 900:
		var p := Vector2(_rng.randf_range(-90, 90), _rng.randf_range(-55, 28))
		if _excluded(p, 0.2):
			continue
		flowers.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.2)), Vector3(p.x, terrain_h(p.x, p.y), p.y)))
		fcolors.append(palette[_rng.randi() % palette.size()])
	Nature.multimesh(self, Nature.flower_mesh(), flowers, false, fcolors, 2)
	var rocks := []
	for i in 30:
		var p := Vector2(_rng.randf_range(-130, 130), _rng.randf_range(-80, 85))
		if _excluded(p, 1.0):
			continue
		rocks.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.5, 1.6)), Vector3(p.x, terrain_h(p.x, p.y) - 0.12, p.y)))
	Nature.multimesh(self, Nature.rock_mesh(), rocks)


func _hills() -> void:
	var b := MeshBuilder.new(99)
	var greens := [Color(0.38, 0.58, 0.32), Color(0.32, 0.52, 0.3), Color(0.45, 0.62, 0.35), Color(0.28, 0.45, 0.32)]
	for k in 34:
		var a := k * TAU / 34.0 + _rng.randf_range(-0.05, 0.05)
		var dist := _rng.randf_range(210.0, 300.0)
		var p := Vector3(cos(a) * dist * 1.25, -6.0, sin(a) * dist)
		var s := Vector3(_rng.randf_range(90, 160), _rng.randf_range(35, 75), _rng.randf_range(70, 120))
		b.add("sphere_hi", Transform3D(Basis(Vector3.UP, a).scaled(s), p), greens[k % greens.size()], 0.06)
	for k in 14:
		var a := _rng.randf() * TAU
		var dist := _rng.randf_range(330.0, 400.0)
		b.add("sphere", Transform3D(Basis(Vector3.UP, a).scaled(Vector3(200, _rng.randf_range(80, 130), 150)), Vector3(cos(a) * dist * 1.2, -10.0, sin(a) * dist)), Color(0.42, 0.55, 0.5), 0.05)
	var mi := b.to_instance(self, "Hills", false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = Nature.foliage_mat(3)


func _bounds() -> void:
	# Neviditelné hranice hratelné oblasti.
	for d in [[Vector3(0, 5, -88), Vector3(300, 10, 2)], [Vector3(0, 5, 88), Vector3(300, 10, 2)], [Vector3(-142, 5, 0), Vector3(2, 10, 180)], [Vector3(142, 5, 0), Vector3(2, 10, 180)]]:
		_col_box(d[1], Transform3D(Basis.IDENTITY, d[0]))


# ------------------------------------------------------------------ Etapa 2: další budovy

## Dřevěná chata u rybníka (bláto na oknech). Čelem k boční cestě na západ.
func _cottage() -> void:
	var spec := {
		"name": "CottageKucera", "position": Vector3(1, 0, -44), "rotation_y": -PI * 0.5,
		"width": 6.5, "depth": 5.0, "found_h": 0.35, "wall_h": 2.45, "roof_h": 2.0, "seed": 401,
		"wall_color": Color(0.62, 0.43, 0.28), "roof_color": Color(0.24, 0.36, 0.3),
		"trim_color": Color(0.95, 0.9, 0.78), "door_color": Color(0.4, 0.25, 0.16),
		"interior": true, "interior_color": Color(0.78, 0.62, 0.45), "floor_color": Color(0.55, 0.4, 0.28),
		"chimney_x": -1.8, "chimney_color": Color(0.55, 0.52, 0.5), "dirt_profile": "chata_blato",
		"door_step": false,
		"openings": [
			{"side": "front", "u": -1.8, "width": 1.1, "height": 1.1, "sill": 0.82, "id": "chata_w1_predni", "dirt": 1.0, "shutters": true, "shutter_color": Color(0.3, 0.45, 0.32)},
			{"side": "front", "type": "door", "u": 0.4, "width": 0.95, "height": 2.0, "sill": 0.0},
			{"side": "front", "u": 2.2, "width": 1.1, "height": 1.1, "sill": 0.82, "id": "chata_w2_predni", "dirt": 1.05, "shutters": true, "shutter_color": Color(0.3, 0.45, 0.32)},
			{"side": "right", "u": 0.0, "width": 1.0, "height": 1.0, "sill": 0.9, "id": "chata_w3_bok", "dirt": 1.1},
			{"side": "back", "u": 0.5, "width": 1.6, "height": 1.2, "sill": 0.7, "id": "chata_w4_zadni", "dirt": 0.95},
			{"side": "left", "u": 0.0, "width": 0.8, "height": 0.8, "sill": 1.1},
		],
		"furniture": [
			{"kind": "table", "pos": Vector3(-1.0, 0, 0.8), "size": Vector3(1.2, 0.75, 0.8), "color": Color(0.5, 0.34, 0.2)},
			{"kind": "bed", "pos": Vector3(2.0, 0, -1.2), "size": Vector3(1.2, 0.6, 1.9), "color": Color(0.35, 0.5, 0.7)},
			{"kind": "shelf", "pos": Vector3(-2.6, 0, -1.5), "size": Vector3(0.4, 1.6, 1.2), "color": Color(0.5, 0.34, 0.2)},
			{"kind": "rug", "pos": Vector3(0.2, 0, 0.3), "size": Vector3(1.8, 0.01, 1.2), "color": Color(0.75, 0.3, 0.25)},
		],
		"interior_light": Vector3(0.0, 2.0, 0.0),
	}
	HouseBuilder.build(self, spec)
	_exclude_rect(-6.0, -50.0, 5.5, -38.0)
	WorldMap.add_rect(Rect2(-1.5, -47.25, 5.0, 6.5), Color(0.62, 0.43, 0.28), "Chata")

	var b := MeshBuilder.new(402)
	var wood := Color(0.6, 0.42, 0.26)
	# chodníček od cesty a malá veranda
	_strip(b, -6.5, -44.3, -2.9, -42.9, 0.025, Color(0.74, 0.68, 0.56))
	b.add_box(Vector3(1.4, 0.3, 2.2), Vector3(-2.2, 0.15, -43.6), wood)
	_col_box(Vector3(1.4, 0.3, 2.2), Transform3D(Basis.IDENTITY, Vector3(-2.2, 0.15, -43.6)))
	# hranice dříví u zadní stěny
	for k in 5:
		for j in 3:
			b.add("cyl10", Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.2, 1.0, 0.2)), Vector3(4.0, 0.12 + j * 0.2, -46.6 + k * 0.22)), wood.darkened(0.1 * (k % 2)), 0.08)
	_col_box(Vector3(1.0, 0.65, 1.2), Transform3D(Basis.IDENTITY, Vector3(4.0, 0.32, -46.2)))
	# rybářský prut opřený o zeď a lavička
	b.add("cyl6", Transform3D(Basis(Vector3.FORWARD, 0.25) * Basis.from_scale(Vector3(0.02, 2.4, 0.02)), Vector3(-1.75, 1.2, -40.6)), Color(0.3, 0.25, 0.2))
	# lavička zády k chatě, sedí se čelem k rybníku (na západ)
	Props.bench(b, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-3.6, 0, -46.5)))
	b.to_instance(self, "CottageYard")
	# u chaty voda není – doneseš ji v kbelíku (nebo dojdeš ke kohoutku na návsi)
	# cedule u chodníčku, čitelná z obou stran
	Props.sign_post(self, Vector3(-5.9, 0, -45.4), -PI * 0.5, "Chata Kučerovi", true, Color(0.75, 0.6, 0.42), Color(0.25, 0.15, 0.08), 1.2, 34)


## Skleník paní Dvořákové za domem (pyl a prach). 8 omyvatelných tabulí.
func _greenhouse() -> void:
	var c := Vector3(9, 0, 25)
	var W := 6.4
	var D := 3.2
	var eave := 2.0
	var ridge := 2.75
	var root := Node3D.new()
	root.name = "Greenhouse"
	root.position = c
	add_child(root)
	var b := MeshBuilder.new(501)
	var frame := Color(0.95, 0.96, 0.95)
	var brick := Color(0.72, 0.38, 0.3)
	var body := StaticBody3D.new()
	root.add_child(body)
	var col := func(size: Vector3, pos: Vector3) -> void:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		body.add_child(cs)
	# cihlový sokl
	for z: float in [-D * 0.5, D * 0.5]:
		b.add_box(Vector3(W + 0.15, 0.45, 0.15), Vector3(0, 0.225, z), brick)
		col.call(Vector3(W + 0.15, 0.45, 0.15), Vector3(0, 0.225, z))
	# západní sokl má mezeru na dveře (DOOR_W), ať dveře nesplývají s cihlami
	var door_w := 0.9
	for x: float in [-W * 0.5, W * 0.5]:
		if x < 0.0:
			var seg := (D - door_w) * 0.5
			for e: float in [-1.0, 1.0]:
				var zc := e * (door_w * 0.5 + seg * 0.5)
				b.add_box(Vector3(0.15, 0.45, seg), Vector3(x, 0.225, zc), brick)
				col.call(Vector3(0.15, 0.45, seg), Vector3(x, 0.225, zc))
			continue
		b.add_box(Vector3(0.15, 0.45, D), Vector3(x, 0.225, 0), brick)
		col.call(Vector3(0.15, 0.45, D), Vector3(x, 0.225, 0))
	# sloupky a vaznice
	var bays := 4
	var bay := W / bays
	for z: float in [-D * 0.5, D * 0.5]:
		for k in bays + 1:
			var x := -W * 0.5 + k * bay
			b.add_box(Vector3(0.06, eave - 0.45, 0.06), Vector3(x, 0.45 + (eave - 0.45) * 0.5, z), frame)
			col.call(Vector3(0.06, eave - 0.45, 0.08), Vector3(x, 0.45 + (eave - 0.45) * 0.5, z))
		b.add_box(Vector3(W + 0.06, 0.06, 0.07), Vector3(0, eave, z), frame)
		b.add_box(Vector3(W + 0.06, 0.04, 0.05), Vector3(0, 0.47, z), frame)
	# omyvatelné tabule na dlouhých stranách
	var gh := eave - 0.03 - 0.5
	var idx := 1
	for side in 2:
		var z := D * 0.5 if side == 0 else -D * 0.5
		for k in bays:
			var x := -W * 0.5 + (k + 0.5) * bay
			var cw := CleanableWindow.new()
			cw.window_id = "sklenik_w%d" % idx
			cw.name = "Window_" + cw.window_id
			cw.glass_size = Vector2(bay - 0.08, gh - 0.02)
			cw.dirt_level = 0.95 + 0.1 * ((k + side) % 2)
			cw.dirt_profile = "sklenik_pyl"
			cw.transform = Transform3D(Basis(Vector3.UP, 0.0 if side == 0 else PI), Vector3(x, 0.5 + gh * 0.5, z + (0.01 if side == 0 else -0.01)))
			root.add_child(cw)
			idx += 1
	# štíty s dekorativním sklem a dveřmi, střecha ze skla
	var glass := Mats.glass_static().duplicate() as ShaderMaterial
	glass.set_shader_parameter("night_lights", false)
	var quad := func(size: Vector2, xf: Transform3D) -> void:
		var q := QuadMesh.new()
		q.size = size
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = glass
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = xf
		root.add_child(mi)
	for e: float in [-1.0, 1.0]:
		var x := e * W * 0.5
		col.call(Vector3(0.06, eave, D), Vector3(x, eave * 0.5, 0))
		if e > 0.0:
			quad.call(Vector2(D - 0.1, eave - 0.5), Transform3D(Basis(Vector3.UP, e * PI * 0.5), Vector3(x, 0.45 + (eave - 0.45) * 0.5, 0)))
			for z: float in [-D * 0.25, 0.0, D * 0.25]:
				b.add_box(Vector3(0.05, eave - 0.45, 0.05), Vector3(x, 0.45 + (eave - 0.45) * 0.5, z), frame)
		else:
			# západní štít: sklo jen vedle dveří, dveře mají vlastní zárubeň
			var gw := (D - door_w) * 0.5 - 0.1
			for g: float in [-1.0, 1.0]:
				var gz := g * (door_w * 0.5 + 0.05 + gw * 0.5)
				quad.call(Vector2(gw, eave - 0.5), Transform3D(Basis(Vector3.UP, e * PI * 0.5), Vector3(x, 0.45 + (eave - 0.45) * 0.5, gz)))
				b.add_box(Vector3(0.05, eave - 0.45, 0.05), Vector3(x, 0.45 + (eave - 0.45) * 0.5, g * (door_w * 0.5 + 0.025)), frame)
			# nadpraží nad dveřmi a sklo nad ním
			b.add_box(Vector3(0.05, 0.06, door_w + 0.1), Vector3(x, 1.93, 0), frame)
		# trojúhelníkový štít
		b.add("prism", Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(D, ridge - eave, 0.05)), Vector3(x, eave + (ridge - eave) * 0.5, 0)), frame.darkened(0.03), 0.0)
	# dveře na západním štítu: rám s prosklenou výplní v otvoru mezi sloupky
	var dx := -W * 0.5
	var dcol := Color(0.88, 0.92, 0.9)
	var dh := 1.9
	var dw := door_w - 0.02
	b.add_box(Vector3(0.04, dh, 0.06), Vector3(dx, dh * 0.5, -dw * 0.5 + 0.03), dcol)
	b.add_box(Vector3(0.04, dh, 0.06), Vector3(dx, dh * 0.5, dw * 0.5 - 0.03), dcol)
	b.add_box(Vector3(0.04, 0.06, dw - 0.12), Vector3(dx, dh - 0.03, 0), dcol)
	b.add_box(Vector3(0.04, 0.5, dw - 0.12), Vector3(dx, 0.25, 0), dcol)
	b.add_box(Vector3(0.04, 0.04, dw - 0.12), Vector3(dx, 1.15, 0), dcol)
	# klika (z obou stran)
	for e: float in [-1.0, 1.0]:
		b.add_box(Vector3(0.05, 0.02, 0.1), Vector3(dx + e * 0.045, 1.0, dw * 0.5 - 0.12), Color(0.55, 0.56, 0.58))
	quad.call(Vector2(dw - 0.12, dh - 0.56), Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(dx, 0.5 + (dh - 0.56) * 0.5, 0)))
	var half := D * 0.5
	var slope := atan2(ridge - eave, half)
	var slen := sqrt(half * half + (ridge - eave) * (ridge - eave))
	for e: float in [1.0, -1.0]:
		var mid := Vector3(0, (eave + ridge) * 0.5, e * half * 0.5)
		var bas := Basis(Vector3.RIGHT, slope if e > 0 else -slope)
		quad.call(Vector2(W, slen), Transform3D(Basis(Vector3.RIGHT, slope - PI * 0.5 if e > 0 else PI * 0.5 - slope), mid))
		for k in bays + 1:
			var x := -W * 0.5 + k * bay
			# příčka leží nad sklem (ne v jeho rovině)
			b.add_box(Vector3(0.05, 0.05, slen), mid + bas * Vector3(0, 0.03, 0) + Vector3(x, 0, 0), frame, bas)
	b.add_box(Vector3(W + 0.1, 0.08, 0.1), Vector3(0, ridge, 0), frame)
	# uvnitř: stoly s rajčaty
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# uvnitř: závěsné police s květinami a rajčaty, visí na lankách z vaznic
	var shelf_w := W - 1.2
	var shelf_c := 0.2
	var cable := Color(0.42, 0.43, 0.45)
	for z: float in [-0.85, 0.85]:
		b.add_box(Vector3(shelf_w, 0.05, 0.8), Vector3(shelf_c, 0.75, z), Color(0.6, 0.45, 0.3))
		# lišta na okraji, ať květináče nespadnou
		for e: float in [-1.0, 1.0]:
			b.add_box(Vector3(shelf_w, 0.05, 0.025), Vector3(shelf_c, 0.8, z + e * 0.39), Color(0.55, 0.4, 0.26))
		# lanka: čtyři v rozích police, nahoru až pod střechu
		for cx: float in [shelf_c - shelf_w * 0.5 + 0.12, shelf_c + shelf_w * 0.5 - 0.12]:
			for e: float in [-1.0, 1.0]:
				var cz := z + e * 0.34
				var top := ridge - (absf(cz) / half) * (ridge - eave) - 0.04
				var bot := 0.775
				b.add_box(Vector3(0.018, top - bot, 0.018), Vector3(cx, (top + bot) * 0.5, cz), cable)
				# háček pod střechou
				b.add_box(Vector3(0.05, 0.02, 0.05), Vector3(cx, top, cz), frame.darkened(0.2))
		# květináče rozložené tak, aby celé stály na polici
		var n_pots := 7
		var step := (shelf_w - 0.5) / (n_pots - 1)
		for k in n_pots:
			var px := shelf_c - shelf_w * 0.5 + 0.25 + k * step
			b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.2, 0.2, 0.2)), Vector3(px, 0.875, z)), Color(0.75, 0.42, 0.3))
			Props.tomato_plant(b, Vector3(px, 0.95, z), rng)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	root.add_child(mi)
	_exclude_rect(c.x - W * 0.5 - 1.2, c.z - D * 0.5 - 1.2, c.x + W * 0.5 + 1.8, c.z + D * 0.5 + 1.2)
	WorldMap.add_rect(Rect2(c.x - W * 0.5, c.z - D * 0.5, W, D), Color(0.7, 0.88, 0.9), "Skleník")


## Statek Horákových a chlév (silná špína, bláto). Vysoká okna – židle.
func _farm() -> void:
	var spec := {
		"name": "FarmHorak", "position": Vector3(82, 0, -21), "width": 12.0, "depth": 8.0,
		"found_h": 0.3, "wall_h": 3.0, "roof_h": 2.3, "seed": 601,
		"wall_color": Color(0.96, 0.88, 0.68), "roof_color": Color(0.62, 0.3, 0.22),
		"trim_color": Color(0.97, 0.96, 0.92), "door_color": Color(0.38, 0.28, 0.2), "shutter_color": Color(0.32, 0.45, 0.3),
		"interior": true, "interior_color": Color(0.94, 0.9, 0.82), "floor_color": Color(0.6, 0.45, 0.3),
		"chimney_x": -3.5, "dirt_profile": "statek_silna",
		"openings": [
			{"side": "front", "type": "door", "u": -3.5, "width": 1.1, "height": 2.2, "sill": 0.0},
			{"side": "front", "u": -0.8, "width": 1.3, "height": 1.4, "sill": 1.1, "id": "statek_w1", "dirt": 1.0, "shutters": true},
			{"side": "front", "u": 2.2, "width": 1.3, "height": 1.4, "sill": 1.1, "id": "statek_w2", "dirt": 1.05, "shutters": true},
			{"side": "front", "u": 4.6, "width": 1.0, "height": 1.2, "sill": 1.2, "id": "statek_w3", "dirt": 1.1, "profile": "kuchyn_mastnota"},
			{"side": "right", "u": 0.0, "width": 1.3, "height": 1.3, "sill": 1.0, "id": "statek_w4", "dirt": 1.0},
			{"side": "back", "u": 0.5, "width": 1.6, "height": 1.4, "sill": 0.9, "id": "statek_w5", "dirt": 1.0},
			{"side": "left", "u": 0.0, "width": 1.1, "height": 1.2, "sill": 1.1, "shutters": true},
			{"side": "back", "u": -3.5, "width": 1.1, "height": 1.2, "sill": 1.1},
		],
		"furniture": [
			{"kind": "table", "pos": Vector3(-0.5, 0, 1.5), "size": Vector3(1.8, 0.78, 1.0), "color": Color(0.55, 0.38, 0.24)},
			{"kind": "box", "pos": Vector3(4.6, 0, 3.3), "size": Vector3(2.0, 0.9, 0.6), "color": Color(0.9, 0.9, 0.88)},
			{"kind": "sofa", "pos": Vector3(2.4, 0, -2.6), "size": Vector3(2.2, 0.8, 0.9), "color": Color(0.6, 0.32, 0.28)},
			{"kind": "shelf", "pos": Vector3(5.5, 0, -1.0), "size": Vector3(0.4, 1.8, 1.6), "color": Color(0.55, 0.4, 0.28)},
			{"kind": "plant", "pos": Vector3(-1.8, 0, 3.2)},
		],
		"interior_light": Vector3(0.5, 2.6, 0.0),
	}
	HouseBuilder.build(self, spec)
	var barn := {
		"name": "BarnHorak", "position": Vector3(98, 0, -22), "width": 7.0, "depth": 5.0,
		"found_h": 0.15, "wall_h": 2.6, "roof_h": 1.8, "seed": 602, "chimney": false,
		"wall_color": Color(0.66, 0.3, 0.24), "roof_color": Color(0.36, 0.34, 0.33),
		"trim_color": Color(0.95, 0.93, 0.88), "door_color": Color(0.5, 0.36, 0.24), "door_step": false,
		"dirt_profile": "chlev_silna",
		"openings": [
			{"side": "front", "u": -2.2, "width": 1.0, "height": 0.8, "sill": 1.2, "id": "chlev_w1", "dirt": 1.1, "cross": true},
			{"side": "front", "type": "door", "u": 0.3, "width": 2.2, "height": 2.2, "sill": 0.0},
			{"side": "front", "u": 2.6, "width": 1.0, "height": 0.8, "sill": 1.2, "id": "chlev_w2", "dirt": 1.2, "cross": true},
		],
	}
	HouseBuilder.build(self, barn)
	_exclude_rect(73, -28, 104, -15.5)
	WorldMap.add_rect(Rect2(76, -25, 12, 8), Color(0.62, 0.3, 0.22).lightened(0.3), "Statek")
	WorldMap.add_rect(Rect2(94.5, -24.5, 7, 5), Color(0.66, 0.3, 0.24).lightened(0.2), "Chlév")

	var b := MeshBuilder.new(603)
	var fc := Color(0.62, 0.45, 0.3)
	Props.picket_fence(b, _static, Vector3(74.5, 0, -FENCE_Z), Vector3(104.0, 0, -FENCE_Z), fc, 5.5, 1.8)
	_strip(b, 79.2, -16.9, 81.4, -5.0, 0.025, Color(0.74, 0.68, 0.56))
	_strip(b, 76.0, -16.9, 81.4, -15.6, 0.025, Color(0.74, 0.68, 0.56))
	_strip(b, 95.5, -19.5, 100.5, -5.0, 0.02, Color(0.62, 0.52, 0.4))
	for k in 4:
		Props.hay_bale(b, Vector3(91.5 + (k % 2) * 1.4, 0, -12.0 - (k / 2) * 1.5), 0.2 * k)
		_col_box(Vector3(1.3, 1.3, 1.3), Transform3D(Basis.IDENTITY, Vector3(91.5 + (k % 2) * 1.4, 0.65, -12.0 - (k / 2) * 1.5)))
	Props.car(b, Transform3D(Basis(Vector3.UP, 0.1), Vector3(88.0, 0, -11.0)), Color(0.35, 0.55, 0.32))
	_col_box(Vector3(1.8, 1.4, 4.0), Transform3D(Basis(Vector3.UP, 0.1), Vector3(88.0, 0.7, -11.0)))
	Props.mailbox(b, Vector3(78.6, 0, -5.65), 0.0, Color(0.2, 0.45, 0.75))
	b.to_instance(self, "FarmYard")
	_water_point(Vector3(89.0, 0, -16.2), true, 0.0)
	Props.sign_post(self, Vector3(83.2, 0, -5.0), 0.0, "Statek Horákovi")


# ------------------------------------------------------------------ cesty autobusem

## Text u jízdního řádu na návsi (interactable = Countryside).
func get_prompt(_player) -> String:
	if GameState.level < Suburb.UNLOCK_LEVEL:
		return "Autobus do Javorova (Předměstí) – zakázky tam dostaneš od úrovně %d" % Suburb.UNLOCK_LEVEL
	return "[E] Autobus do Javorova – Předměstí"


func interact(player) -> void:
	travel(Suburb.AREA_ID, player)


## Přesun mezi oblastmi. Žebříky, které hráč nenese, jedou s ním (naložené v autobuse).
## Výška povrchu (chodník, tráva) pod bodem – bez žebříků samotných.
func ground_y(p: Vector3) -> float:
	var ex: Array[RID] = []
	for l in ladders:
		ex.append(l.get_rid())
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 4.0, p.z), Vector3(p.x, p.y - 4.0, p.z), 1, ex)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return maxf((hit["position"] as Vector3).y, p.y) if not hit.is_empty() else p.y


## Cesta autobusem s animací příjezdu a odjezdu (BusRide). Zastávky volají tohle.
func bus_travel(area: String, player) -> void:
	if player.mode != Player.Mode.WALK or not get_tree().get_nodes_in_group("bus_ride").is_empty():
		return
	if not _travel_allowed(area):
		return
	BusRide.start(self, player, area)


## Místo u zastávky dané oblasti, kde hráč vystoupí.
func stop_point(area: String) -> Vector3:
	if area == Suburb.AREA_ID:
		return Suburb.ORIGIN + Suburb.ARRIVE
	if area == Metropolis.AREA_ID:
		return Metropolis.ORIGIN + Metropolis.ARRIVE
	if area == City.AREA_ID:
		return City.ORIGIN + City.ARRIVE
	return Vector3(BUS_X + 3.1, 0.05, -4.4)


## Střed pruhu u zastávky (z), ve kterém staví autobus.
func stop_lane_z(area: String) -> float:
	if area == Suburb.AREA_ID:
		return Suburb.ORIGIN.z - 2.0
	if area == Metropolis.AREA_ID:
		return Metropolis.ORIGIN.z - 2.4
	if area == City.AREA_ID:
		return City.ORIGIN.z - 2.75
	return -1.5


func _travel_allowed(area: String) -> bool:
	if area == Suburb.AREA_ID and GameState.level < Suburb.UNLOCK_LEVEL:
		Events.toast("Na Předměstí tě zatím nikdo nezná. Získej úroveň %d a zakázky z Javorova se ozvou." % Suburb.UNLOCK_LEVEL, "info")
		return false
	if area == Metropolis.AREA_ID and GameState.level < Metropolis.UNLOCK_LEVEL:
		Events.toast("Ve Velkoměstě zatím Clear View nikdo nezná. Od úrovně %d se ozvou správci mrakodrapů z Horizontu." % Metropolis.UNLOCK_LEVEL, "info")
		return false
	if area == City.AREA_ID and GameState.level < City.UNLOCK_LEVEL:
		Events.toast("Ve městě zatím nikdo nezná tvou firmu. Od úrovně %d se ozvou kanceláře a hotely z Brodce." % City.UNLOCK_LEVEL, "info")
		return false
	return true


func travel(area: String, player, van_dest: String = "") -> bool:
	if player.mode != Player.Mode.WALK:
		return false
	if not _travel_allowed(area):
		return false
	GameState.unlock_area(area)
	var dest: Vector3
	var yaw: float
	var lad_spot: Vector3
	var place := ""
	if area == Suburb.AREA_ID:
		dest = Suburb.ORIGIN + Suburb.ARRIVE
		yaw = Suburb.ARRIVE_YAW
		lad_spot = Suburb.ORIGIN + Suburb.LADDER_SPOT
		place = "Javorov – Předměstí"
	elif area == Metropolis.AREA_ID:
		dest = Metropolis.ORIGIN + Metropolis.ARRIVE
		yaw = Metropolis.ARRIVE_YAW
		lad_spot = Metropolis.ORIGIN + Metropolis.LADDER_SPOT
		place = "Horizont – Hlavní bulvár"
	elif area == City.AREA_ID:
		dest = City.ORIGIN + City.ARRIVE
		yaw = City.ARRIVE_YAW
		lad_spot = City.ORIGIN + City.LADDER_SPOT
		place = "Brodec – Hlavní třída"
	else:
		dest = Vector3(BUS_X + 3.1, 0.05, -4.4)
		yaw = PI * 0.5
		lad_spot = Vector3(BUS_X + 6.5, 0.0, -8.2)
		place = "Lipová Lhota – náves"
	var moved := 0
	var away: Array[Ladder] = []
	for l in ladders:
		if l.is_owned() and not l.is_carried():
			var from_area := WorldMap.area_at(Vector2(l.global_position.x, l.global_position.z))
			if from_area != area:
				away.append(l)
	# firemní dodávkou: dodávka přijede s hráčem a žebříky vezou na střeše
	var on_roof := 0
	if van_dest != "" and base:
		base.park_van(van_dest)
		on_roof = base.load_ladders(away)
	for i in range(on_roof, away.size()):
		var lp := lad_spot + Vector3(0, 0, -moved * 0.9)
		lp.y = ground_y(lp)
		away[i].lay_down(lp, PI * 0.5)
		moved += 1
	# kbelík z jiné oblasti dorazí k zastávce taky (vedle žebříků)
	for bk in get_tree().get_nodes_in_group("buckets"):
		var bucket := bk as Bucket
		if bucket.is_owned() and not bucket.is_carried() and WorldMap.area_at(Vector2(bucket.global_position.x, bucket.global_position.z)) != area:
			var bp := lad_spot + Vector3(1.6, 0, -moved * 0.9)
			bp.y = ground_y(bp)
			bucket.global_position = bp
			bucket.reset_physics_interpolation()
	player.global_position = dest
	player.yaw = yaw
	player.pitch = 0.0
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player._safe_hist.clear()
	player._air_top = dest.y
	Audio.play("click", -4.0, 0.7)
	var msg := "Vystupuješ: %s." % place
	if on_roof > 0:
		msg += " Žebříky jsou na střeše dodávky."
	if moved > 0:
		msg += " Žebříky jely s tebou – stojí u zastávky."
	Events.toast(msg, "info")
	Events.area_changed.emit(area)
	return true


## Cesta firemní dodávkou (odkudkoli). dest: "zakladna", "venkov", "predmesti", "mesto", "velkomesto".
func van_travel(dest: String, player) -> bool:
	if not GameState.has_item("company_van"):
		Events.toast("Firemní dodávku koupíš v obchodě (kategorie Firma).", "info")
		return false
	if player.mode != Player.Mode.WALK:
		Events.toast("Do dodávky nastoupíš, až budeš stát na zemi (ne na žebříku, laně nebo plošině).", "info")
		return false
	var area := "venkov" if dest == "zakladna" else dest
	if not travel(area, player, dest):
		return false
	if dest == "zakladna":
		player.global_position = CompanyBase.BASE_SPOT
		player.yaw = 0.0
		player.reset_physics_interpolation()
		player._safe_hist.clear()
		player._air_top = CompanyBase.BASE_SPOT.y
	Events.toast("Dodávka tě odvezla: %s." % {"zakladna": "základna – garáž", "venkov": "Lipová Lhota – náves", "predmesti": "Javorov – Předměstí", "mesto": "Brodec – Hlavní třída", "velkomesto": "Horizont – Hlavní bulvár"}.get(dest, dest), "success")
	return true

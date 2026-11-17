class_name Weather
extends Node3D
## Nepřízeň počasí (Etapa 7): občas se zatáhne a přijde bouřka s deštěm a hromy.
## Když přejde, ozvou se zákazníci s okny ušpiněnými od bouřky (poptávky „Po bouřce“
## nad běžný počet nabídek). Rozdělaná okna bouřka nekazí – relax hra.
## Dá se vypnout v Nastavení. Časovač se neukládá: po načtení hry začne znovu.

const FIRST_MIN := 12.0 * 60.0
const FIRST_MAX := 18.0 * 60.0
const NEXT_MIN := 20.0 * 60.0
const NEXT_MAX := 30.0 * 60.0
const STORM_LEN := 75.0
const RAMP := 10.0
const MIN_LEVEL := 2

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var clouds: ShaderMaterial
var atmosphere: Atmosphere
## V zimě místo deště sněží.
var snowing := false
## Mokrá okna po dešti (stékající kapky na skle, pomalu osychají).
var glass_rain := 0.0
var _rain_mesh: Mesh
var _snow_mesh: Mesh

var timer := 0.0
var storm_left := 0.0
var intensity := 0.0
var storms_done := 0
var _rng := RandomNumberGenerator.new()
var _base := {}
var _rain: CPUParticles3D
var _roof_timer := 0.0
var _under_roof := false
var _thunder_timer := 0.0
var _flash := 0.0
var _warm := false


func _ready() -> void:
	_rng.randomize()
	timer = _rng.randf_range(FIRST_MIN, FIRST_MAX)
	if sky_mat:
		_base["top"] = sky_mat.sky_top_color
		_base["hor"] = sky_mat.sky_horizon_color
	if sun:
		_base["sun"] = sun.light_energy
	if env:
		_base["amb"] = env.ambient_light_energy
		_base["fog"] = env.fog_density
		_base["fogc"] = env.fog_light_color
	if clouds:
		var cov = clouds.get_shader_parameter("coverage")
		_base["cov"] = float(cov) if cov != null else 0.52
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 1600
	_rain.lifetime = 0.9
	_rain.local_coords = false
	_rain.emitting = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(16.0, 0.5, 16.0)
	_rain.direction = Vector3(0.08, -1.0, 0.04)
	_rain.spread = 2.0
	_rain.gravity = Vector3.ZERO
	_rain.initial_velocity_min = 19.0
	_rain.initial_velocity_max = 23.0
	_rain.particle_flag_align_y = true
	var drop := BoxMesh.new()
	drop.size = Vector3(0.012, 0.45, 0.012)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.82, 0.9, 0.35)
	drop.material = m
	_rain.mesh = drop
	_rain_mesh = drop
	var flake := QuadMesh.new()
	flake.size = Vector2(0.05, 0.05)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(0.97, 0.98, 1.0, 0.85)
	flake.material = fm
	_snow_mesh = flake
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.extra_cull_margin = 30.0
	add_child(_rain)


## Jeden snímek deště (kompilace materiálu za načítací obrazovkou).
func warm_up() -> void:
	_warm = true
	await get_tree().process_frame
	await get_tree().process_frame
	_warm = false


func is_storm() -> bool:
	return storm_left > 0.0


## Spustí bouřku hned (test, ladění).
func start_storm() -> void:
	storm_left = STORM_LEN
	_thunder_timer = _rng.randf_range(6.0, 12.0)
	_set_snow(atmosphere != null and atmosphere.winter > 0.5)
	if snowing:
		Events.toast("Zatahuje se – přichází sněhová vánice. Po ní budou mít lidé co mýt.", "info")
	else:
		Events.toast("Zatahuje se – blíží se bouřka. Po ní budou mít lidé co mýt.", "info")


func _set_snow(on: bool) -> void:
	snowing = on
	_rain.mesh = _snow_mesh if on else _rain_mesh
	_rain.lifetime = 7.0 if on else 0.9
	_rain.initial_velocity_min = 1.2 if on else 19.0
	_rain.initial_velocity_max = 2.4 if on else 23.0
	_rain.spread = 25.0 if on else 2.0
	_rain.amount = 1400 if on else 1600
	_rain.particle_flag_align_y = not on


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if storm_left > 0.0:
		storm_left -= delta
		if storm_left <= 0.0:
			storm_left = 0.0
			_storm_over()
	elif player and Settings.weather_events and GameState.level >= MIN_LEVEL:
		timer -= delta
		if timer <= 0.0:
			timer = _rng.randf_range(NEXT_MIN, NEXT_MAX)
			start_storm()
	var target := 1.0 if storm_left > RAMP * 0.5 else 0.0
	intensity = move_toward(intensity, target, delta / RAMP)
	_apply(delta)
	# déšť kolem kamery, pod střechou ne
	var cam := get_viewport().get_camera_3d()
	if cam:
		_rain.global_position = cam.global_position + Vector3(0, 13.0, 0)
		_roof_timer -= delta
		if _roof_timer <= 0.0 and intensity > 0.0:
			_roof_timer = 0.3
			var q := PhysicsRayQueryParameters3D.create(cam.global_position + Vector3.UP * 0.3, cam.global_position + Vector3.UP * 40.0)
			q.collision_mask = 1
			_under_roof = not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	var rain_on := intensity > 0.35
	_rain.emitting = rain_on or _warm
	_rain.visible = not _under_roof or _warm
	Audio.set_loop("rain", intensity * (0.35 if _under_roof else 0.7) * (0.25 if snowing else 1.0))
	# kapky na oknech: při dešti přibývají, potom sklo pomalu osychá (~40 s)
	var wet_target := intensity if not snowing else 0.0
	glass_rain = move_toward(glass_rain, wet_target, delta * (0.25 if wet_target > glass_rain else 0.025))
	RenderingServer.global_shader_parameter_set("rain_glass", glass_rain)
	# hromy (při sněžení ne)
	if storm_left > RAMP and not snowing:
		_thunder_timer -= delta
		if _thunder_timer <= 0.0:
			_thunder_timer = _rng.randf_range(14.0, 26.0)
			_flash = 1.0
			Audio.play("thunder", 2.0, _rng.randf_range(0.8, 1.1))


func _apply(delta: float) -> void:
	var i := intensity
	_flash = maxf(0.0, _flash - delta * 4.0)
	if sky_mat and _base.has("top"):
		sky_mat.sky_top_color = (_base["top"] as Color).lerp(Color(0.36, 0.4, 0.46), i)
		sky_mat.sky_horizon_color = (_base["hor"] as Color).lerp(Color(0.56, 0.6, 0.64), i)
	if sun and _base.has("sun"):
		sun.light_energy = lerpf(_base["sun"], 0.4, i) + _flash * 2.5
	if env and _base.has("amb"):
		env.ambient_light_energy = lerpf(_base["amb"], 0.72, i)
		env.fog_density = lerpf(_base["fog"], 0.0065, i)
		env.fog_light_color = (_base["fogc"] as Color).lerp(Color(0.55, 0.58, 0.62), i)
	if clouds and _base.has("cov"):
		clouds.set_shader_parameter("coverage", lerpf(_base["cov"], 0.88, i))


func _storm_over() -> void:
	storms_done += 1
	var n := ContractManager.storm_offers(2)
	if n > 0:
		Events.toast("Bouřka přešla. Ušpinila lidem okna – v tabletu %s %d %s „Po bouřce“." % ["přibyla" if n == 1 else "přibyly", n, "poptávka" if n == 1 else "poptávky"], "success")
	else:
		Events.toast("Bouřka přešla a znovu svítí slunce.", "info")

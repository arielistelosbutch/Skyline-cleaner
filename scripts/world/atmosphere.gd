class_name Atmosphere
extends Node
## Denní doba a roční období. Posouvá slunce po obloze (ráno, poledne, zlatá
## hodinka, večer, krátká noc s rozsvícenými okny), barví oblohu, mlhu a mraky
## a nastavuje globální parametry shaderů (season_*, night_amount, frost_glass,
## wind_strength). Bouřku navrch přidává Weather – čte si odsud základní barvy.
##
## Čas a den se ukládají v GameState (clock, day). Obojí jde v Nastavení vypnout
## (pak je pořád dopoledne / léto).

## Herní hodina ve dne = 60 s, noc (22–5 h) běží 4× rychleji.
const DAY_HOUR_SEC := 60.0
const NIGHT_SPEED := 4.0
## Délka jednoho ročního období ve dnech (den ≈ 19 minut hraní).
const SEASON_DAYS := 2
const SEASON_NAMES := ["Jaro", "Léto", "Podzim", "Zima"]

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var clouds: ShaderMaterial
var weather: Weather

## Podíly ročních období 0..1 (plynulé přechody).
var spring := 0.0
var summer := 1.0
var autumn := 0.0
var winter := 0.0
var night := 0.0
var _last_season := -1
var _leaves: CPUParticles3D
var _lamp_level := -1.0


func _ready() -> void:
	process_priority = -10
	_leaves = CPUParticles3D.new()
	_leaves.name = "SeasonParticles"
	_leaves.amount = 90
	_leaves.lifetime = 9.0
	_leaves.preprocess = 9.0
	_leaves.local_coords = false
	_leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_leaves.emission_box_extents = Vector3(14.0, 0.5, 14.0)
	_leaves.direction = Vector3(0.3, -1.0, 0.1)
	_leaves.spread = 25.0
	_leaves.gravity = Vector3(0.25, -0.35, 0.1)
	_leaves.initial_velocity_min = 0.3
	_leaves.initial_velocity_max = 0.8
	_leaves.angular_velocity_min = -160.0
	_leaves.angular_velocity_max = 160.0
	_leaves.angle_min = 0.0
	_leaves.angle_max = 360.0
	_leaves.scale_amount_min = 0.6
	_leaves.scale_amount_max = 1.2
	_leaves.particle_flag_rotate_y = false
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.06)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.roughness = 0.9
	q.material = m
	_leaves.mesh = q
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(0.9, 0.55, 0.12), Color(0.8, 0.28, 0.1), Color(0.92, 0.78, 0.22)])
	_leaves.color_initial_ramp = grad
	_leaves.emitting = false
	_leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leaves.extra_cull_margin = 20.0
	add_child(_leaves)
	_update_all(0.0)


func _process(delta: float) -> void:
	if Settings.day_cycle and get_tree().get_first_node_in_group("player") != null:
		var rate := 1.0 / DAY_HOUR_SEC
		if GameState.clock >= 22.0 or GameState.clock < 5.0:
			rate *= NIGHT_SPEED
		GameState.clock += delta * rate
		if GameState.clock >= 24.0:
			GameState.clock -= 24.0
			GameState.day += 1
	_update_all(delta)


## Čas pro zobrazení (při vypnutém střídání je pořád dopoledne).
func visual_clock() -> float:
	return GameState.clock if Settings.day_cycle else 11.0


func season_pos() -> float:
	if not Settings.seasons:
		return 1.0
	return fposmod((GameState.day + GameState.clock / 24.0) / SEASON_DAYS, 4.0)


func season_index() -> int:
	return int(season_pos()) % 4


func season_name() -> String:
	return SEASON_NAMES[season_index()]


static func clock_text(h: float) -> String:
	var hh := int(h) % 24
	var mm := int((h - floorf(h)) * 60.0)
	return "%d:%02d" % [hh, mm]


func _update_all(_delta: float) -> void:
	_seasons()
	_sky()
	_particles()


func _seasons() -> void:
	var f := season_pos()
	var idx := int(f) % 4
	var t := f - floorf(f)
	var w := [0.0, 0.0, 0.0, 0.0]
	var nxt := smoothstep(0.8, 1.0, t)
	w[idx] = 1.0 - nxt
	w[(idx + 1) % 4] += nxt
	spring = w[0]
	summer = w[1]
	autumn = w[2]
	winter = w[3]
	RenderingServer.global_shader_parameter_set("season_spring", spring)
	RenderingServer.global_shader_parameter_set("season_autumn", autumn)
	RenderingServer.global_shader_parameter_set("season_winter", winter)
	if idx != _last_season:
		if _last_season >= 0 and Settings.seasons:
			Events.toast("Začíná %s." % ["jaro", "léto", "podzim", "zima"][idx], "info")
		_last_season = idx


func _sky() -> void:
	var h := visual_clock()
	# výška slunce: východ 6 h, západ 20 h, v zimě níž
	var max_elev := lerpf(62.0, 36.0, winter)
	var day_t := (h - 6.0) / 14.0
	var elev := sin(clampf(day_t, -0.25, 1.25) * PI) * max_elev
	if day_t < 0.0 or day_t > 1.0:
		elev = minf(elev, -2.0 - absf(day_t - 0.5) * 20.0)
	var azim := lerpf(-105.0, 105.0, clampf(day_t, 0.0, 1.0))
	night = 1.0 - smoothstep(-7.0, 4.0, elev)
	var golden := (1.0 - smoothstep(4.0, 22.0, elev)) * (1.0 - night)
	RenderingServer.global_shader_parameter_set("night_amount", night)
	_street_lights()
	var morning := 1.0 - smoothstep(7.0, 10.0, h)
	RenderingServer.global_shader_parameter_set("frost_glass", winter * clampf(night + morning * 0.8, 0.0, 1.0))
	var wind := autumn * 0.6 + (weather.intensity if weather else 0.0) * 0.8
	RenderingServer.global_shader_parameter_set("wind_strength", wind)

	if sun:
		if night > 0.5:
			# měsíc: tlumené modravé světlo z vysoka, ať jde v noci pořád pracovat
			sun.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(150.0), 0.0)
		else:
			sun.rotation = Vector3(deg_to_rad(-maxf(elev, 3.0)), deg_to_rad(azim), 0.0)
		var day_col := Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.97, 0.93), winter * 0.5)
		var col := day_col.lerp(Color(1.0, 0.62, 0.36), golden)
		var moon_mix := smoothstep(0.35, 0.65, night)
		sun.light_color = col.lerp(Color(0.62, 0.72, 1.0), moon_mix)
		var day_energy := lerpf(1.3, 1.1, winter) * lerpf(1.0, 0.75, golden)
		var energy := lerpf(day_energy, 0.32, moon_mix)
		# v okamžiku přepnutí slunce/měsíc (soumrak) krátce ztlumit
		energy *= 1.0 - (1.0 - absf(night - 0.5) * 2.0) * 0.8
		if weather:
			weather._base["sun"] = energy
		else:
			sun.light_energy = energy
		if clouds:
			clouds.set_shader_parameter("sun_dir", sun.basis.z)

	var top := Color(0.32, 0.55, 0.86).lerp(Color(0.42, 0.58, 0.82), winter * 0.6)
	var hor := Color(0.72, 0.84, 0.94).lerp(Color(0.82, 0.86, 0.9), winter * 0.6)
	top = top.lerp(Color(0.36, 0.48, 0.74), golden)
	hor = hor.lerp(Color(0.98, 0.68, 0.46), golden)
	top = top.lerp(Color(0.03, 0.06, 0.15), night)
	hor = hor.lerp(Color(0.1, 0.14, 0.26), night)
	var amb := lerpf(0.9, 0.42, night)
	var fogc := hor.lerp(Color(0.74, 0.83, 0.92), 0.3 * (1.0 - night))
	if weather:
		weather._base["top"] = top
		weather._base["hor"] = hor
		weather._base["amb"] = amb
		weather._base["fogc"] = fogc
		weather._base["fog"] = 0.0022 + winter * 0.0012 + autumn * 0.0006
	elif sky_mat and env:
		sky_mat.sky_top_color = top
		sky_mat.sky_horizon_color = hor
		env.ambient_light_energy = amb
		env.fog_light_color = fogc
	if sky_mat:
		sky_mat.ground_horizon_color = hor.lerp(Color(0.7, 0.8, 0.86), 0.3)
		sky_mat.ground_bottom_color = Color(0.3, 0.38, 0.3).lerp(Color(0.05, 0.06, 0.08), night)
	if clouds:
		var cc := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.72, 0.6), golden).lerp(Color(0.18, 0.2, 0.28), night)
		clouds.set_shader_parameter("tint", cc)


func _particles() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# podzim: padající listí, jaro: pár okvětních lístků (jen u země, ne na mrakodrapu)
	var amount := autumn * 1.0 + spring * 0.35
	var low := cam.global_position.y < 25.0
	var raining := weather != null and weather.intensity > 0.3
	_leaves.emitting = amount > 0.25 and low and not raining
	if _leaves.emitting:
		_leaves.global_position = cam.global_position + Vector3(0, 8.0, 0)
		var petals := spring > autumn
		var grad := _leaves.color_initial_ramp
		if petals:
			grad.colors = PackedColorArray([Color(1.0, 0.85, 0.9), Color(1.0, 0.97, 0.97), Color(0.98, 0.75, 0.85)])
		else:
			grad.colors = PackedColorArray([Color(0.9, 0.55, 0.12), Color(0.8, 0.28, 0.1), Color(0.92, 0.78, 0.22)])


## Pouliční lampy svítí od soumraku do svítání.
func _street_lights() -> void:
	var lv := smoothstep(0.15, 0.6, night)
	if absf(lv - _lamp_level) < 0.02 and not (lv == 0.0 and _lamp_level != 0.0):
		return
	_lamp_level = lv
	for l in get_tree().get_nodes_in_group("street_lights"):
		var o := l as OmniLight3D
		o.visible = lv > 0.01
		o.light_energy = lv * 1.6

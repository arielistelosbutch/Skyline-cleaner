class_name CleanableWindow
extends Node3D
## Omyvatelné okno. Lokální osa +Z míří ven (k hráči), sklo leží v rovině XY
## se středem v počátku. Každé okno má unikátní window_id kvůli ukládání.

const GLASS_SHADER := preload("res://shaders/glass_dirt.gdshader")
const COMPLETE_THRESHOLD := 0.98
const WINDOW_LAYER := 2

@export var window_id := ""
@export var glass_size := Vector2(1.2, 1.2)
@export_range(0.2, 1.5) var dirt_level := 1.0
## Id profilu znečištění (data/dirt/<id>.tres) – určuje typy nečistot.
@export var dirt_profile := ""
## Profil špíny dané poptávky (přebije výchozí profil okna, ukládá se).
var override_profile := ""
## Kolikrát už bylo okno „znovu zašpiněno" (opakované zakázky) – mění seed.
var generation := 0

var mask: DirtMask
var material: ShaderMaterial
var mesh_instance: MeshInstance3D
var body: StaticBody3D
var completed := false
var touched := false

var _wet_timer := 0.0
var _fade_tw: Tween
var _sparkles: CPUParticles3D
var _last_reported := -1.0


## Zrcadlové sklo (mrakodrapy): 0 = průhledné, 1 = zrcadlo; mirror_tint = barva skla.
var mirror := 0.0
var mirror_tint := Color(0.45, 0.6, 0.7)


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = GLASS_SHADER
	material.set_shader_parameter("glass_size", glass_size)
	material.set_shader_parameter("proc_level", dirt_level)
	material.set_shader_parameter("seed", float(absi(hash(window_id)) % 1000) * 0.37)
	material.set_shader_parameter("use_mask", false)
	material.set_shader_parameter("mirror", mirror)
	material.set_shader_parameter("mirror_tint", mirror_tint)

	var quad := QuadMesh.new()
	quad.size = glass_size
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = quad
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)

	body = StaticBody3D.new()
	body.collision_layer = 1 | WINDOW_LAYER
	body.collision_mask = 0
	body.set_meta("window", self)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(glass_size.x, glass_size.y, 0.05)
	cs.shape = box
	body.add_child(cs)
	add_child(body)

	WindowRegistry.register(self)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_task_mask = null
	WindowRegistry.unregister(self)


# --- předgenerování masky ve vlákně (Etapa 7, výkon): generování trvá desítky ms,
# v hlavním vlákně by při chůzi kolem oken způsobovalo záseky.
var _task := -1
var _task_mask: DirtMask
var _task_key := ""


## Spustí generování masky na pozadí. Vrací false, když není co dělat.
func prefetch() -> bool:
	if mask or _task >= 0:
		return false
	var m := DirtMask.new(glass_size)
	var sd := dirt_seed()
	var lvl := dirt_level
	var prof := DirtProfile.get_profile(profile_id())
	_task_mask = m
	_task_key = "%d|%s" % [generation, override_profile]
	_task = WorkerThreadPool.add_task(func() -> void: m.generate(sd, lvl, prof, false), false, "dirt mask")
	return true


func prefetch_pending() -> bool:
	return _task >= 0


func prefetch_done() -> bool:
	return _task < 0 or WorkerThreadPool.is_task_completed(_task)


## Převezme masku z vlákna (počká, když ještě není hotová).
func finish_prefetch() -> void:
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var m := _task_mask
	_task_mask = null
	if mask == null and m and _task_key == "%d|%s" % [generation, override_profile]:
		m.finish_textures()
		_use_mask(m)


## Vytvoří aktivní masku (drahou část) až když je potřeba – hráč je blízko
## nebo okno má uložený stav. Vzdálená okna používají levnou procedurální náhradu.
func activate() -> void:
	finish_prefetch()
	if mask:
		return
	var m := DirtMask.new(glass_size)
	m.generate(dirt_seed(), dirt_level, DirtProfile.get_profile(profile_id()))
	_use_mask(m)


func _use_mask(m: DirtMask) -> void:
	mask = m
	material.set_shader_parameter("dirt_tex", mask.texture)
	material.set_shader_parameter("wet_tex", mask.wet_texture)
	material.set_shader_parameter("use_mask", true)


## Pták kápl na okno (Etapa 7) – jen na rozdělané, ne na hotové okno.
func add_bird_dropping(c: Vector2, seed_value: int) -> bool:
	if completed or mask == null:
		return false
	c.x = clampf(c.x, 0.12, glass_size.x - 0.12)
	c.y = clampf(c.y, 0.2, glass_size.y - 0.08)
	mask.add_bird(c, 0.03, seed_value)
	mask.flush()
	touched = true
	_check_progress()
	return true


func dirt_seed() -> int:
	return hash(window_id) + generation * 7919


## Typy nečistot na okně (bez aktivní masky se odhadnou z profilu).
func kinds_present() -> Array[int]:
	if mask:
		return mask.kinds_present()
	return DirtProfile.kinds_of(profile_id())


func profile_id() -> String:
	return override_profile if override_profile != "" else dirt_profile


func is_active() -> bool:
	return mask != null


func cleanliness() -> float:
	if completed:
		return 1.0
	if mask == null:
		return 0.0
	return mask.cleanliness()


func normal() -> Vector3:
	return global_basis.z.normalized()


## Světový bod -> souřadnice na skle (metry od levého dolního rohu).
func to_plane(world: Vector3) -> Vector2:
	var l := to_local(world)
	return Vector2(l.x + glass_size.x * 0.5, l.y + glass_size.y * 0.5)


## Souřadnice na skle -> světový bod, volitelně odsazený od skla ven.
func plane_to_world(p: Vector2, out: float = 0.0) -> Vector3:
	return to_global(Vector3(p.x - glass_size.x * 0.5, p.y - glass_size.y * 0.5, out))


func scrub(a: Vector2, b: Vector2, tool: ToolData, moisture: float, mult: float = 1.0, carry_chem: float = 0.0) -> float:
	if completed:
		return 0.0
	activate()
	var removed := mask.scrub(a, b, tool, moisture, mult, carry_chem)
	if removed > 0.0 or mask.last_absorbed != 0.0:
		touched = true
	if removed > 0.0:
		_check_progress()
	return removed


## Rotační kartáč: čištění pod hlavou bez pohybu (dráha = spin × čas).
func spin_scrub(c: Vector2, tool: ToolData, moisture: float, amount: float) -> float:
	if completed:
		return 0.0
	activate()
	var removed := mask.spin_scrub(c, tool, moisture, amount)
	if removed > 0.0:
		touched = true
		_check_progress()
	return removed


func scrub_blade(a: Vector2, b: Vector2, axis: Vector2, width: float, tool: ToolData, mult: float = 1.0) -> float:
	if completed:
		return 0.0
	activate()
	var removed := mask.scrub_blade(a, b, axis, width, tool, mult)
	if removed > 0.0:
		touched = true
		_check_progress()
	return removed


func press(c: Vector2, tool: ToolData) -> float:
	if completed:
		return 0.0
	activate()
	var removed := mask.press(c, tool)
	if removed > 0.0:
		touched = true
		_check_progress()
	return removed


func spray(c: Vector2, t: ToolData, radius_mult: float = 1.0, evap_mult: float = 1.0) -> void:
	if completed or t == null:
		return
	activate()
	mask.spray(c, t.spray_radius * radius_mult, t.grease_power, t.dissolve, t.evaporation * evap_mult)
	touched = true


func dirt_at(c: Vector2) -> float:
	if completed or mask == null:
		return 0.0 if completed else 1.0
	return mask.dirt_at(c)


func _process(delta: float) -> void:
	if mask == null:
		return
	if not mask.drips.is_empty():
		var before := mask.current_total
		mask.update_drips(delta)
		if before != mask.current_total:
			_check_progress()
	_wet_timer += delta
	if _wet_timer >= 0.1:
		mask.update_wet(_wet_timer)
		_wet_timer = 0.0
	mask.flush()


func _check_progress() -> void:
	var c := cleanliness()
	if absf(c - _last_reported) > 0.002:
		_last_reported = c
		Events.window_progress.emit(window_id, c)
	if not completed and c >= GameState.complete_threshold():
		_complete()


## Při odchodu od skoro hotového okna (95,5 %+) se zbylé šmouhy dočistí samy –
## je to relaxační hra, hráč nemá hledat poslední pixel v rohu.
const FINISH_ON_LEAVE := 0.955


func finish_if_almost() -> void:
	if not completed and mask != null and cleanliness() >= minf(FINISH_ON_LEAVE, GameState.complete_threshold()):
		_complete()


func _complete() -> void:
	completed = true
	# Zbylé drobné nečistoty plynule zmizí – hráč nemusí hledat poslední pixel.
	var tw := create_tween()
	_fade_tw = tw
	tw.tween_method(func(v: float) -> void: material.set_shader_parameter("fade", v), 0.0, 1.0, 0.9)
	# Dočištění se týká jen téhle masky – kdyby se okno mezitím znovu zašpinilo
	# (nová zakázka), nová špína nesmí zmizet.
	var m := mask
	tw.tween_callback(func() -> void:
		if mask and mask == m and completed:
			mask.clear_all()
			mask.flush()
		material.set_shader_parameter("fade", 0.0))
	play_glint(0.25)
	_burst_sparkles()
	Audio.play("complete")
	Events.window_progress.emit(window_id, 1.0)
	Events.window_completed.emit(window_id)


func play_glint(delay: float = 0.0) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void: material.set_shader_parameter("glint", v), 0.0, 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: material.set_shader_parameter("glint", -1.0))


func _burst_sparkles() -> void:
	if _sparkles == null:
		_sparkles = CPUParticles3D.new()
		_sparkles.one_shot = true
		_sparkles.emitting = false
		_sparkles.amount = 36
		_sparkles.lifetime = 1.3
		_sparkles.explosiveness = 0.6
		_sparkles.local_coords = true
		_sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_sparkles.emission_box_extents = Vector3(glass_size.x * 0.5, glass_size.y * 0.5, 0.01)
		_sparkles.direction = Vector3(0, 0, 1)
		_sparkles.spread = 40.0
		_sparkles.gravity = Vector3(0, 0.15, 0)
		_sparkles.initial_velocity_min = 0.05
		_sparkles.initial_velocity_max = 0.2
		_sparkles.scale_amount_min = 0.5
		_sparkles.scale_amount_max = 1.3
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.0))
		curve.add_point(Vector2(0.25, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
		_sparkles.scale_amount_curve = curve
		var q := QuadMesh.new()
		q.size = Vector2(0.05, 0.05)
		q.material = Mats.sparkle()
		_sparkles.mesh = q
		_sparkles.position = Vector3(0, 0, 0.03)
		add_child(_sparkles)
	_sparkles.restart()


# ------------------------------------------------------------------ ukládání

func save_state() -> Dictionary:
	if not touched and not completed:
		var e := {}
		if generation > 0:
			e["gen"] = generation
		if override_profile != "":
			e["prof"] = override_profile
		return e
	var d := {"completed": completed, "gen": generation}
	if override_profile != "":
		d["prof"] = override_profile
	if not completed and mask:
		d["mask"] = mask.to_save()
	return d


## Okno se znovu zašpiní (opakovaná zakázka / poptávka) – nový vzor špíny,
## případně s jiným profilem (po bouřce, mastnota…).
func redirty(profile: String = "") -> void:
	reset_state()
	override_profile = profile
	generation += 1


func reset_state() -> void:
	if _fade_tw and _fade_tw.is_valid():
		_fade_tw.kill()
	_fade_tw = null
	completed = false
	touched = false
	_last_reported = -1.0
	if mask:
		mask = null
		material.set_shader_parameter("use_mask", false)
	material.set_shader_parameter("fade", 0.0)
	material.set_shader_parameter("glint", -1.0)


func load_state(d: Dictionary) -> void:
	reset_state()
	generation = int(d.get("gen", 0))
	override_profile = str(d.get("prof", ""))
	if not d.has("completed"):
		return
	activate()
	touched = true
	if bool(d.get("completed", false)):
		completed = true
		mask.clear_all()
		mask.flush()
	elif d.has("mask"):
		mask.apply_save(d["mask"])
		mask.flush()

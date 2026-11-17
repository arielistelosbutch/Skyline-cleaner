class_name CleaningController
extends Node
## Pracovní režim ručního čištění.
##
## * Pohyb myši posouvá nástroj po lokální rovině skla (nezávisle na kameře).
## * Nástroj se drží v dosahu ruky (podle polohy nohou hráče) a v rozměrech skla.
## * Levé tlačítko přitlačí nástroj – čistí se jen při pohybu, úměrně ujeté dráze.
## * Kamera nástroj jemně sleduje s mrtvou zónou, takže malé pohyby ji nehýbou.
## * Každý nástroj se chová jinak: hadr (kulatý, všesměrový), houbička (roztírá
##   vodu a přípravek), stěrka (lišta kolmá ke směru tahu, potřebuje mokré sklo,
##   odměňuje dlouhé souvislé tahy).

const WORK_DISTANCE := 0.72
const REACH_SIDE := 0.78
const REACH_LOW := 0.18
const REACH_HIGH := 2.22
const DEADZONE := 0.17
const BASE_SENS := 0.00105

var player: Player
var window: CleanableWindow
var tool: ToolData
var active := false
var has_pose := false
var camera_xf := Transform3D.IDENTITY

var rag := Vector2.ZERO
var rag_target := Vector2.ZERO
var rag_vel := Vector2.ZERO
var look := Vector2.ZERO
var pressing := false
var press := 0.0
var moisture := 0.0
var rag_dirt := 0.0
var speed := 0.0
## Natočení lišty stěrky (úhel osy lišty v rovině skla).
var blade_angle := PI * 0.5
## Délka aktuálního souvislého tahu (pro bonus stěrky).
var stroke_len := 0.0
## Přípravek, který houbička nasála a roztírá.
var carry_chem := 0.0
## Odstraněná špína za poslední snímek (pro testy a efekty).
var last_removed := 0.0

var reach_min := Vector2.ZERO
var reach_max := Vector2.ONE
var bounds_max := Vector2.ONE
var reach_valid := false
## Pro automatické testy: simuluje držení levého tlačítka.
var debug_press := false

var _was_pressing := false
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _hint_cd := 0.0
var _blocked_high := false
var _weak_t := 0.0
var _moist := {}
## Zanesení jednotlivých nástrojů (id -> 0..1), ať se při přepnutí nepřenáší.
var _dirty := {}
var _dust: CPUParticles3D
var _spray_fx: CPUParticles3D
## Kapky odletující od rotačního kartáče na mokrém skle.
var _splash: CPUParticles3D
var _dose_t := 0.0
var _wet_t := 0.0
var _washer_warned := false
var _wring_cd := 0.0
var _soil_hint := false
## Od kolika je nástroj „plný špinavé vody" (čistí hůř, rada vyždímat).
const SOIL_WARN := 0.6


func _ready() -> void:
	_dust = CPUParticles3D.new()
	_dust.top_level = true
	_dust.emitting = false
	_dust.amount = 28
	_dust.lifetime = 0.9
	_dust.local_coords = false
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_dust.emission_sphere_radius = 0.05
	_dust.gravity = Vector3(0, -0.6, 0)
	_dust.initial_velocity_min = 0.02
	_dust.initial_velocity_max = 0.08
	_dust.scale_amount_min = 0.4
	_dust.scale_amount_max = 1.0
	_dust.color = Color(0.55, 0.48, 0.38, 0.7)
	var dq := QuadMesh.new()
	dq.size = Vector2(0.008, 0.008)
	dq.material = Mats.particle(Color(1, 1, 1, 1))
	_dust.mesh = dq
	add_child(_dust)

	_spray_fx = CPUParticles3D.new()
	_spray_fx.top_level = true
	_spray_fx.one_shot = true
	_spray_fx.emitting = false
	_spray_fx.amount = 60
	_spray_fx.lifetime = 0.35
	_spray_fx.explosiveness = 0.85
	_spray_fx.local_coords = false
	_spray_fx.direction = Vector3(0, 0, -1)
	_spray_fx.spread = 9.0
	_spray_fx.gravity = Vector3(0, -1.5, 0)
	_spray_fx.initial_velocity_min = 2.5
	_spray_fx.initial_velocity_max = 4.5
	_spray_fx.scale_amount_min = 0.5
	_spray_fx.scale_amount_max = 1.4
	_spray_fx.color = Color(0.85, 0.95, 1.0, 0.55)
	var sq := QuadMesh.new()
	sq.size = Vector2(0.012, 0.012)
	sq.material = Mats.particle(Color(1, 1, 1, 1))
	_spray_fx.mesh = sq
	add_child(_spray_fx)

	_splash = CPUParticles3D.new()
	_splash.top_level = true
	_splash.emitting = false
	_splash.amount = 40
	_splash.lifetime = 0.45
	_splash.local_coords = false
	_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_splash.emission_ring_axis = Vector3(0, 0, 1)
	_splash.emission_ring_radius = 0.08
	_splash.emission_ring_inner_radius = 0.06
	_splash.emission_ring_height = 0.0
	_splash.direction = Vector3(0, 0, -1)
	_splash.spread = 70.0
	_splash.gravity = Vector3(0, -6.0, 0)
	_splash.initial_velocity_min = 0.5
	_splash.initial_velocity_max = 1.3
	_splash.scale_amount_min = 0.5
	_splash.scale_amount_max = 1.2
	_splash.color = Color(0.85, 0.94, 1.0, 0.6)
	var wq := QuadMesh.new()
	wq.size = Vector2(0.007, 0.007)
	wq.material = Mats.particle(Color(1, 1, 1, 1))
	_splash.mesh = wq
	add_child(_splash)


func begin(w: CleanableWindow, hit_point: Vector3) -> bool:
	var t := GameState.wipe_tool()
	if t == null:
		Events.toast("Nemáš čím mýt – chybí ti hadr.", "warn")
		return false
	_set_tool(t)
	window = w
	w.activate()
	_update_reach()
	if not reach_valid:
		if reach_min.y >= reach_max.y:
			Events.toast("Na toto okno nedosáhneš. " + _reach_tip(), "warn")
		else:
			Events.toast("Stoupni si víc před okno.", "warn")
		window = null
		return false
	rag = w.to_plane(hit_point).clamp(reach_min, reach_max)
	rag_target = rag
	rag_vel = Vector2.ZERO
	look = rag
	press = 0.0
	stroke_len = 0.0
	blade_angle = PI * 0.5
	_was_pressing = false
	_cam_pos = player.camera.global_position
	_cam_look = w.plane_to_world(look)
	active = true
	_compute_camera(0.0)
	has_pose = true
	player.hand.begin(tool)
	Audio.play("cloth", -6.0)
	_announce_dirt()
	_spin_tip()
	return true


## Jednorázová rada k rotačnímu kartáči (za hru jednou).
static var _spin_tip_shown := false
func _spin_tip() -> void:
	if tool == null or tool.spin <= 0.0 or _spin_tip_shown:
		return
	_spin_tip_shown = true
	Events.toast("Rotační kartáč myje sám – podrž levé tlačítko a jen s ním pomalu jezdi po skle, drhnout není potřeba.", "info")


func end() -> void:
	active = false
	pressing = false
	_dust.emitting = false
	Audio.set_loop("rub", 0.0)
	Audio.set_loop("squeak", 0.0)
	_splash.emitting = false
	player.hand.end()
	window = null


func _set_tool(t: ToolData) -> void:
	if tool and tool != t:
		_moist[tool.id] = moisture
		_dirty[tool.id] = rag_dirt
	tool = t
	moisture = float(_moist.get(t.id, moisture if t.visual == "rag" else 0.0))
	rag_dirt = float(_dirty.get(t.id, 0.0))
	_soil_hint = rag_dirt > SOIL_WARN


## Přepnutí ručního nástroje přímo v pracovním režimu (kolečko myši).
func cycle_tool(dir: int) -> void:
	var owned := GameState.owned_tools("rag")
	if owned.size() < 2:
		return
	var idx := maxi(0, owned.find(tool))
	var t: ToolData = owned[wrapi(idx + dir, 0, owned.size())]
	GameState.set_active(t.id)
	_set_tool(t)
	stroke_len = 0.0
	if active:
		player.hand.begin(tool)
		_update_reach()
		rag_target = rag_target.clamp(reach_min, reach_max)
		_spin_tip()
	Audio.play("cloth", -10.0, 1.2)


## Vymáchání / namočení nástroje (kýbl, sud s vodou).
func rinse() -> void:
	GameState.refill_tank()
	Events.toast("Nástroj vymáchaný, rozprašovač doplněný (%d nástřiků)." % int(GameState.tank_max()), "info")
	Audio.play("spray", -10.0, 0.6)
	rag_dirt = 0.0
	_soil_hint = false
	carry_chem = 0.0
	var t := GameState.wipe_tool()
	_moist.clear()
	_dirty.clear()
	if t and t.spreads > 0.0:
		_moist[t.id] = 1.0
	if t:
		_set_tool(t)
	moisture = 1.0 if tool and tool.spreads > 0.0 else 0.6
	Events.tutorial_event.emit("rinse")


## Rada, jak dosáhnout výš – podle toho, co hráč vlastní (s žebříkem už
## nemá smysl radit židli).
func _reach_tip(lower: bool = false) -> String:
	var ladder := GameState.has_item("ladder_small") or GameState.has_item("ladder_ext")
	var tele := false
	for t in GameState.owned_tools("rag"):
		if t.reach_bonus > 0.0:
			tele = true
	var tip := ""
	if ladder:
		tip = "Opři o zeď žebřík a vylez na něj."
		if tele and (tool == null or tool.reach_bonus <= 0.0):
			tip = "Opři o zeď žebřík, nebo vezmi teleskopickou tyč [kolečko]."
	elif tele and (tool == null or tool.reach_bonus <= 0.0):
		tip = "Vezmi teleskopickou tyč [kolečko] nebo si přistav židli."
	else:
		tip = "Přistav si židli z garáže a vyskoč na ni (nebo si v obchodě kup žebřík)."
	if lower:
		tip = tip.substr(0, 1).to_lower() + tip.substr(1)
	return tip


func _announce_dirt() -> void:
	var kinds := window.kinds_present()
	var names: Array[String] = []
	for k in kinds:
		names.append(DirtTypes.name_of(k).to_lower())
	if not names.is_empty():
		Events.cleaning_hint.emit("Na okně: " + ", ".join(names) + ".")


func on_mouse_motion(rel: Vector2) -> void:
	if not active:
		return
	var s := BASE_SENS * Settings.clean_sensitivity
	var raw := rag_target + Vector2(rel.x, -rel.y) * s
	_blocked_high = raw.y > reach_max.y + 0.01 and reach_max.y < bounds_max.y - 0.03
	rag_target = raw.clamp(reach_min, reach_max)


func blade_axis() -> Vector2:
	return Vector2(cos(blade_angle), sin(blade_angle))


func update(delta: float) -> void:
	if not active or window == null:
		return
	_update_reach()
	rag_target = rag_target.clamp(reach_min, reach_max)
	var prev := rag
	rag = rag.lerp(rag_target, 1.0 - exp(-30.0 * delta)).clamp(reach_min, reach_max)
	var moved := rag - prev
	var prev_vel := rag_vel
	if delta > 0.0:
		rag_vel = rag_vel.lerp(moved / delta, 1.0 - exp(-14.0 * delta))
	speed = rag_vel.length()
	var blade := tool.shape == "blade"

	# Lišta stěrky se natáčí kolmo ke směru tahu (lišta je symetrická → úhel mod π).
	if blade and moved.length() > 0.0012:
		var target := atan2(moved.x, -moved.y)
		if absf(angle_difference(blade_angle, target)) > PI * 0.5:
			target += PI
		blade_angle = lerp_angle(blade_angle, target, 1.0 - exp(-16.0 * delta))

	pressing = (debug_press or Input.is_action_pressed("use_tool")) and not player.ui_open
	press = move_toward(press, 1.0 if pressing else 0.0, delta * 9.0)
	var removed := 0.0
	if pressing and press > 0.6:
		# Souvislý tah: délka roste, ostrá otočka nebo zastavení ji vynuluje.
		if speed > 0.04:
			if prev_vel.length() > 0.08 and absf(prev_vel.angle_to(rag_vel)) > deg_to_rad(65.0):
				stroke_len = 0.0
			stroke_len += moved.length()
		elif speed < 0.015:
			stroke_len = maxf(0.0, stroke_len - delta * 0.6)
		var mult := GameState.clean_mult(tool) * soil_mult()
		if tool.fold:
			# skládací mop: čím víc je vysunutý nad dosah ruky, tím slaběji čistí
			var feet_v := window.to_plane(player.global_position).y
			var rb := maxf(0.01, GameState.reach_bonus(tool))
			mult *= lerpf(1.0, tool.fold_mult, clampf((rag.y - feet_v - REACH_HIGH) / rb, 0.0, 1.0))
		if tool.auto_dose > 0.0 and speed > 0.05:
			_auto_dose(delta)
		if tool.stroke_bonus > 0.0:
			mult *= lerpf(1.0, lerpf(0.55, 1.2, smoothstep(0.0, 0.3, stroke_len)), tool.stroke_bonus)
		if not _was_pressing:
			removed += window.press(rag, tool)
			Audio.play("cloth", -12.0, 1.1)
		if tool.spin > 0.0:
			# rotační hlava čistí sama i bez drhnutí – hráč s ní jen jezdí po skle
			removed += window.spin_scrub(rag, tool, moisture, tool.strength * tool.spin * delta * mult)
		if blade:
			removed += window.scrub_blade(prev, rag, blade_axis(), tool.blade_width * GameState.blade_width_mult(), tool, mult)
		else:
			removed += window.scrub(prev, rag, tool, moisture, mult, carry_chem)
		if window.mask:
			var absorbed := window.mask.last_absorbed
			if tool.spreads > 0.0:
				moisture = clampf(moisture + absorbed * 0.0004, 0.0, 1.0)
				carry_chem = maxf(carry_chem, window.mask.last_chem_seen)
				if moisture < 0.05:
					carry_chem = 0.0
			elif not blade:
				moisture = clampf(moisture + absorbed * 0.004 - moved.length() * 0.35, 0.0, 1.0)
		_soil(removed, window.mask.last_absorbed if window.mask else 0.0)
		_check_weak(delta, blade)
	else:
		stroke_len = 0.0
		_weak_t = 0.0
	_was_pressing = pressing and press > 0.6
	last_removed = removed
	if Talents.has_effect("auto_wet") and player.anchor != null:
		_auto_wet(delta)

	# Zvuk: tření podle rychlosti tahu, vrzání na už čistém skle.
	var rub := 0.0
	var squeak := 0.0
	if pressing:
		rub = clampf(speed / 0.7, 0.0, 1.0) * (0.4 if blade else 0.55)
		if tool.spin > 0.0:
			rub = maxf(rub, 0.32)
		var dry_glass := window.mask == null or window.mask.wet_at(rag) < 0.1
		if speed > 0.35 and window.dirt_at(rag) < 0.04 and moisture < 0.15 and dry_glass:
			squeak = clampf((speed - 0.35) / 0.8, 0.0, 1.0) * (0.2 if blade else 0.12)
	var rub_pitch := (0.7 if blade else 0.85) + clampf(speed, 0.0, 1.5) * 0.25
	if tool.spin > 0.0:
		rub_pitch = 1.35 + clampf(speed, 0.0, 1.0) * 0.1
	Audio.set_loop("rub", rub, rub_pitch)
	Audio.set_loop("squeak", squeak, 0.9 + clampf(speed, 0.0, 1.0) * 0.2)

	# Prach odpadávající z nástroje.
	_dust.global_position = window.plane_to_world(rag, 0.03)
	_dust.emitting = pressing and removed > 0.004 and (speed > 0.1 or tool.spin > 0.0)
	var splash := tool.spin > 0.0 and pressing and press > 0.6 and window.mask != null and window.mask.wet_at(rag) > 0.15
	if splash:
		_splash.emission_ring_radius = tool.radius
		_splash.emission_ring_inner_radius = tool.radius * 0.75
		var wn := window.normal()
		_splash.global_transform = Transform3D(Basis.looking_at(wn, Vector3.FORWARD if absf(wn.y) > 0.95 else Vector3.UP), window.plane_to_world(rag, 0.02))
	_splash.emitting = splash

	_wring_cd = maxf(0.0, _wring_cd - delta)
	_hint_cd = maxf(0.0, _hint_cd - delta)
	if _blocked_high and _hint_cd <= 0.0:
		_hint_cd = 6.0
		Events.toast("Výš nedosáhneš – " + _reach_tip(true), "info")
		_blocked_high = false

	_compute_camera(delta)
	player.hand.pose(self, delta)


## Nástroj, který se zanáší (hadr, houbička, mop) – ne stěrka ani kartáč.
func soils() -> bool:
	return tool != null and tool.shape != "blade" and tool.spin <= 0.0 and tool.soil_rate > 0.0


## Zanesený nástroj čistí hůř (nejvýš o třetinu – relax, ne trest).
func soil_mult() -> float:
	if not soils():
		return 1.0
	return lerpf(1.0, 0.65, smoothstep(SOIL_WARN - 0.1, 1.0, rag_dirt))


## Nástroj nabírá špínu ze skla a špinavou vodu (houbička i nasátou).
func _soil(removed: float, absorbed: float) -> void:
	if not soils():
		return
	# za 1 m² úplně umytého skla se nástroj zanese zhruba o 40 % (× soil_rate)
	var add := maxf(absorbed, 0.0) * 0.00006
	if window and window.mask:
		add += removed / window.mask.initial_total * window.glass_size.x * window.glass_size.y * 0.4
	rag_dirt = clampf(rag_dirt + add * tool.soil_rate, 0.0, 1.0)
	if rag_dirt > SOIL_WARN and not _soil_hint:
		_soil_hint = true
		Events.cleaning_hint.emit("%s je plná špinavé vody a čistí hůř – vyždímej ji [R]. Úplně čistou ji máš po vymáchání ve vodě." % ("Houbička" if tool.visual == "sponge" else "Hadr"))


## Vyždímání nástroje [R]: vyteče špinavá voda, nástroj zůstane vlhký.
func wring() -> bool:
	if not active or not soils() or _wring_cd > 0.0:
		return false
	_wring_cd = 0.9
	var had := rag_dirt
	rag_dirt *= 0.3
	moisture = minf(moisture, 0.35 if tool.spreads > 0.0 else 0.2)
	carry_chem = 0.0
	if had > SOIL_WARN * 0.8:
		_soil_hint = false
	player.hand.play_wring(had)
	Audio.play("water", -8.0, 1.25)
	Events.tutorial_event.emit("wring")
	return true


## Když nástroj na daném místě skoro nečistí, poradí proč (bláto nasucho,
## mastnota bez přípravku, stěrka na suchém skle…).
func _check_weak(delta: float, blade: bool) -> void:
	var m := window.mask
	if m == null or speed < 0.12 or m.dirt_at(rag) < 0.2:
		_weak_t = maxf(0.0, _weak_t - delta)
		return
	var wi := m._widx(rag)
	var k := m.kind_at(rag)
	var f := m._factor(k, m.wet[wi], wi, tool) / (1.0 + m._tough_at(m._idx(rag)) * tool.tough_penalty)
	if f >= 0.3:
		_weak_t = maxf(0.0, _weak_t - delta)
		return
	_weak_t += delta
	if _weak_t < 0.8 or _hint_cd > 0.0:
		return
	_weak_t = 0.0
	_hint_cd = 8.0
	var text := ""
	if blade and m.wet[wi] < 0.15:
		text = "Stěrka čistí jen mokré sklo – nejdřív nastříkej přípravek [F]."
	else:
		text = DirtTypes.HINTS[k]
	if text == "":
		text = "Tady to jde ztuha – zkus sklo navlhčit [F] nebo jiný nástroj [kolečko]."
	Events.cleaning_hint.emit(text)


func _update_reach() -> void:
	var m := 0.02 if tool and tool.shape == "blade" else (tool.radius * 0.35 if tool else 0.02)
	bounds_max = window.glass_size - Vector2(m, m)
	var feet := window.to_plane(player.global_position)
	var rb := GameState.reach_bonus(tool)
	reach_min = Vector2(maxf(m, feet.x - REACH_SIDE - rb * 0.35), maxf(m, feet.y + REACH_LOW))
	reach_max = Vector2(minf(bounds_max.x, feet.x + REACH_SIDE + rb * 0.35), minf(bounds_max.y, feet.y + REACH_HIGH + rb))
	var dist := window.to_local(player.global_position).z
	reach_valid = reach_max.x > reach_min.x + 0.05 and reach_max.y > reach_min.y + 0.05 and dist > -0.2 and dist < 1.6 + rb * 0.6


func _compute_camera(delta: float) -> void:
	# Mrtvá zóna: kamera se hýbe, až když nástroj odjede dál od středu pohledu.
	var off := rag - look
	var d := off.length()
	if d > DEADZONE:
		var k := 1.0 - exp(-9.0 * delta) if delta > 0.0 else 1.0
		look += off / d * (d - DEADZONE) * k
	if delta > 0.0:
		look = look.lerp(rag, 1.0 - exp(-0.7 * delta))
	var feet := window.to_plane(player.global_position)
	var eye_v := feet.y + Player.EYE_HEIGHT
	var cam_u := feet.x + clampf(look.x - feet.x, -0.32, 0.32)
	var cam_v := clampf(look.y + 0.06, eye_v - 0.6, eye_v + 0.2 + GameState.reach_bonus(tool) * 0.35)
	var target_pos := window.plane_to_world(Vector2(cam_u, cam_v), WORK_DISTANCE)
	var target_look := window.plane_to_world(look, 0.0)
	if delta > 0.0:
		_cam_pos = _cam_pos.lerp(target_pos, 1.0 - exp(-5.0 * delta))
		_cam_look = _cam_look.lerp(target_look, 1.0 - exp(-6.5 * delta))
	else:
		_cam_pos = target_pos
		_cam_look = target_look
	var dir := _cam_look - _cam_pos
	if dir.length_squared() > 0.0001:
		camera_xf = Transform3D(Basis.looking_at(dir, Vector3.UP), _cam_pos)


## Elektrický stěrač: dávkuje přípravek z vlastní nádržky pod lištu, dokud se jezdí.
func _auto_dose(delta: float) -> void:
	if not GameState.use_washer(delta):
		if not _washer_warned:
			_washer_warned = true
			Events.cleaning_hint.emit("Nádržka elektrického stěrače je prázdná – doplň ji u vody (sud, kohoutek, kýbl). Do té doby stírá jen jako stěrka.")
		return
	_washer_warned = false
	_dose_t -= delta
	if _dose_t > 0.0:
		return
	_dose_t = 0.12
	var t := GameState.spray_tool()
	if t == null:
		t = GameState.get_tool("detergent_basic")
	window.spray(rag, t, 0.5 * GameState.spray_radius_mult(), GameState.evaporation_mult())


## Talent Automatický zavlažovač: na laně a na plošině tryska sama vlhčí sklo kolem nástroje.
func _auto_wet(delta: float) -> void:
	_wet_t -= delta
	if _wet_t > 0.0:
		return
	_wet_t = 0.7
	var t := GameState.spray_tool()
	if t == null:
		t = GameState.get_tool("detergent_basic")
	window.spray(rag + Vector2(0.0, 0.12), t, 0.9 * GameState.spray_radius_mult(), GameState.evaporation_mult())


func spray() -> void:
	var t := GameState.spray_tool()
	if not active or t == null:
		return
	if not GameState.use_tank():
		return
	var target := rag + Vector2(0.0, 0.05)
	window.spray(target, t, GameState.spray_radius_mult(), GameState.evaporation_mult())
	Audio.play("spray", -4.0, randf_range(0.95, 1.05))
	var from := camera_xf.origin + camera_xf.basis * Vector3(-0.22, -0.18, -0.2)
	spawn_spray_fx(from, window.plane_to_world(target), t.color)
	player.hand.flash_bottle(t)


func spawn_spray_fx(from: Vector3, to: Vector3, tint: Color = Color(0.85, 0.95, 1.0)) -> void:
	var dir := (to - from)
	if dir.length_squared() < 0.0001:
		return
	_spray_fx.color = Color(tint.lerp(Color(0.9, 0.97, 1.0), 0.6), 0.55)
	_spray_fx.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), from)
	_spray_fx.restart()

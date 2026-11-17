extends Node
## Automatický test hlavní smyčky Etapy 1 (spouští se s argumentem -- --autotest).
## Simuluje hráče: přijetí zakázky, příchod k oknu, pracovní režim, tahy myší,
## kontrolu masky, židli, dokončení oken, odměnu, uložení a načtení.
## S argumentem --shots navíc ukládá snímky obrazovky (vyžaduje grafický výstup).

var main: Node
var shots_only := false
var _fails: Array[String] = []
var _passes := 0
var _shot_dir := ""


func _ready() -> void:
	_shot_dir = OS.get_environment("CLEARVIEW_SHOTS")
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
		print("  OK   ", what)
	else:
		_fails.append(what)
		print("  FAIL ", what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


func _shot(name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir.path_join(name + ".png"))
	print("  shot ", name)


func _run() -> void:
	print("=== Clear View autotest ===")
	# náhodné události (bouřka, ptáci) by test rozházely – testují se ručně v Etapě 7
	Settings.weather_events = false
	Settings.bird_droppings = false
	var player: Player = main.player
	var ui: UIRoot = main.ui
	GameState.reset()
	ContractManager.reset()
	WindowRegistry.reset_all()
	main._enter_game()
	await _frames(5)

	if shots_only:
		await _shots(player)
		get_tree().quit(0)
		return

	_check(WindowRegistry.windows.size() == 529, "registrováno 529 omyvatelných oken – základna 3 + vesnice 74 + Předměstí 62 + město 102 + Velkoměsto 288 (%d)" % WindowRegistry.windows.size())
	var c := ContractManager.get_contract("novak_bungalow")
	_check(c != null, "zakázka Bungalov Novákových načtena")
	for wid in c.window_ids:
		_check(WindowRegistry.find_window(wid) != null, "okno zakázky existuje: " + wid)

	# --- pohyb hráče
	var start := player.global_position
	Input.action_press("move_forward")
	await _frames(40)
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(start) > 1.0, "hráč se pohybuje WASD (%.2f m)" % player.global_position.distance_to(start))
	_check(player.is_on_floor(), "hráč stojí na zemi (gravitace + kolize)")

	# --- okno bez zakázky nejde mýt
	var w := WindowRegistry.find_window("novak_w1_obyvak")
	_stand_before(player, w, 0.9, 0.7)
	await _frames(20)
	player.begin_cleaning(w, w.plane_to_world(Vector2(0.9, 0.4)))
	_check(player.mode == Player.Mode.WALK, "bez přijaté zakázky se pracovní režim nespustí")

	ContractManager.accept("novak_bungalow")
	_check(ContractManager.active_id == "novak_bungalow", "zakázka přijata")

	# --- pracovní režim
	await get_tree().create_timer(1.5).timeout
	_check(w.is_active(), "okno v blízkosti hráče má aktivní masku")
	player.begin_cleaning(w, w.plane_to_world(Vector2(0.9, 0.45)))
	_check(player.mode == Player.Mode.CLEANING, "pracovní režim zahájen")
	await _frames(30)
	var cam_dist := w.to_local(player.camera.global_position).z
	_check(cam_dist < 0.95 and cam_dist > 0.4, "kamera se přiblížila ke sklu (%.2f m)" % cam_dist)
	_check(player.hand.visible, "ruka s hadrem je vidět")

	var cc := player.cleaning
	var c0 := w.cleanliness()
	var start_rag := cc.rag
	Input.action_press("use_tool")
	await _frames(10)
	var c1 := w.cleanliness()
	await _frames(40)
	var c2 := w.cleanliness()
	_check(c1 >= c0, "přitlačení setře jen tenkou vrstvu (%.4f -> %.4f)" % [c0, c1])
	_check(absf(c2 - c1) < 0.00001, "držení tlačítka bez pohybu myši nečistí (%.5f -> %.5f)" % [c1, c2])

	# vodorovný tah doprava
	var dirt_on_line_before := _avg_dirt(w, start_rag + Vector2(0.25, 0.0), 0.02)
	var dirt_above_before := _avg_dirt(w, start_rag + Vector2(0.25, 0.3), 0.02)
	for i in 45:
		cc.on_mouse_motion(Vector2(9, 0))
		await _frames(1)
	await _frames(10)
	var moved := cc.rag - start_rag
	_check(moved.x > 0.3 and absf(moved.y) < 0.01, "hadr sleduje pohyb myši doprava (posun %.2f, %.3f m)" % [moved.x, moved.y])
	var dirt_on_line_after := _avg_dirt(w, start_rag + Vector2(0.25, 0.0), 0.02)
	var dirt_above_after := _avg_dirt(w, start_rag + Vector2(0.25, 0.3), 0.02)
	_check(dirt_on_line_after < dirt_on_line_before * 0.8, "špína mizí na dráze hadru (%.3f -> %.3f)" % [dirt_on_line_before, dirt_on_line_after])
	_check(absf(dirt_above_after - dirt_above_before) < 0.0001, "mimo dráhu hadru zůstává špína (%.3f -> %.3f)" % [dirt_above_before, dirt_above_after])
	var c3 := w.cleanliness()
	_check(c3 > c2, "procento čistoty roste při tahu (%.3f)" % c3)
	var look_before := cc.look

	# tah nahoru a zpět doleva (souvislá stopa i při rychlém pohybu)
	for i in 12:
		cc.on_mouse_motion(Vector2(0, -60))
		await _frames(1)
	await _frames(10)
	_check(cc.rag.y > start_rag.y + 0.2, "hadr jde nahoru (%.2f)" % cc.rag.y)
	_check(cc.look.distance_to(look_before) > 0.01, "kamera jemně následuje hadr")
	_check(cc.rag.y <= cc.reach_max.y + 0.0001, "hadr je omezen dosahem ruky (%.2f <= %.2f)" % [cc.rag.y, cc.reach_max.y])
	var reach_ground := cc.reach_max.y
	_check(reach_ground < w.glass_size.y - 0.05, "ze země nedosáhne na horní část okna (dosah %.2f / výška %.2f)" % [reach_ground, w.glass_size.y])

	# puštění tlačítka – hadr se hýbe, ale nečistí
	Input.action_release("use_tool")
	await _frames(8)
	var c4 := w.cleanliness()
	for i in 20:
		cc.on_mouse_motion(Vector2(-12, 3))
		await _frames(1)
	await _frames(5)
	_check(absf(w.cleanliness() - c4) < 0.00001, "bez stisku tlačítka se hadr hýbe a nečistí")

	# saponát
	var wet_before := _avg_wet(w, cc.rag, 0.05)
	cc.spray()
	await _frames(3)
	_check(_avg_wet(w, cc.rag + Vector2(0, 0.05), 0.05) > wet_before + 0.2, "saponát smáčí sklo")
	_check(not w.mask.drips.is_empty() or true, "vznikají stékající kapky")

	player.end_cleaning()
	await _frames(30)
	_check(player.mode == Player.Mode.WALK, "pracovní režim ukončen")
	var kept := w.cleanliness()
	_check(absf(kept - c4) < 0.05, "stav okna se po ukončení zachoval (%.3f)" % kept)

	# --- židle
	var chair: Chair = main.world.chair
	player.global_position = chair.global_position + Vector3(0, 0, 1.2)
	player.yaw = 0.0
	player.pitch = deg_to_rad(-50.0)
	await _frames(15)
	_check(player.focus_object == chair, "hráč míří na židli")
	player.pick_up(chair)
	_check(player.carried == chair and not chair.visible, "židle zvednuta")
	_stand_before(player, w, 0.9, 1.6)
	await _frames(15)
	player._try_place()
	_check(player.carried == null and chair.visible, "židle položena pod okno")
	var chair_dist := w.to_local(chair.global_position).z
	_check(chair_dist > 0.1 and chair_dist < 1.3, "židle stojí u okna (%.2f m)" % chair_dist)
	# postavíme hráče na židli (jako po skoku) a ověříme větší dosah
	player.global_position = chair.global_position + Vector3(0, Chair.SEAT_SIZE.y + 0.05, 0)
	player.velocity = Vector3.ZERO
	await _frames(20)
	_check(player.global_position.y > 0.4, "hráč stojí na židli (výška nohou %.2f)" % player.global_position.y)
	player.begin_cleaning(w, w.plane_to_world(Vector2(w.to_plane(chair.global_position).x, w.glass_size.y - 0.2)))
	_check(player.mode == Player.Mode.CLEANING, "čištění ze židle")
	await _frames(3)
	_check(cc.reach_max.y > reach_ground + 0.3, "ze židle je dosah vyšší (%.2f > %.2f)" % [cc.reach_max.y, reach_ground])
	player.end_cleaning()
	await _frames(5)

	# --- částečné vyčištění + uložení / načtení
	var w2 := WindowRegistry.find_window("novak_w2_kuchyn")
	w2.activate()
	var tool := GameState.best_tool("rag")
	for k in 6:
		w2.scrub(Vector2(0.05, 0.3), Vector2(w2.glass_size.x - 0.05, 0.3), tool, 0.0)
		w2.scrub(Vector2(w2.glass_size.x - 0.05, 0.3), Vector2(0.05, 0.3), tool, 0.0)
	var w2_partial := w2.cleanliness()
	var w1_partial := w.cleanliness()
	_check(w2_partial > 0.05 and w2_partial < 0.9, "okno 2 je rozpracované (%.3f)" % w2_partial)
	var money_before := GameState.money
	_check(SaveManager.save_game(true), "hra uložena")
	WindowRegistry.reset_all()
	GameState.money = 0
	ContractManager.reset()
	_check(SaveManager.load_game(), "hra načtena")
	_check(GameState.money == money_before, "peníze po načtení sedí")
	_check(ContractManager.active_id == "novak_bungalow", "rozpracovaná zakázka po načtení pokračuje")
	_check(absf(WindowRegistry.find_window("novak_w2_kuchyn").cleanliness() - w2_partial) < 0.02, "čistota okna 2 po načtení (%.3f vs %.3f)" % [WindowRegistry.find_window("novak_w2_kuchyn").cleanliness(), w2_partial])
	_check(absf(WindowRegistry.find_window("novak_w1_obyvak").cleanliness() - w1_partial) < 0.02, "čistota okna 1 po načtení")
	var saved: Dictionary = SaveManager.read_save()
	_check(int(saved.get("version", 0)) == SaveManager.SAVE_VERSION, "uložená data mají verzi %d" % SaveManager.SAVE_VERSION)
	_check(saved.get("persist", {}).has("chair_wood"), "pozice židle se ukládá")

	# --- dokončení všech oken (simulované cikcak tahy po celé ploše)
	var xp_before := GameState.xp + GameState.level * 10000
	var completed_events := [0]
	Events.window_completed.connect(func(_id): completed_events[0] += 1)
	for wid in c.window_ids:
		var ww := WindowRegistry.find_window(wid)
		ww.activate()
		var passes := 0
		while not ww.completed and passes < 60:
			_zigzag(ww, tool)
			passes += 1
			await _frames(1)
		_check(ww.completed, "okno %s dokončeno (%d průchodů, ~98 %% => automaticky doleštěno)" % [wid, passes])
	await _frames(70)
	_check(completed_events[0] == 6, "6× oznámení o dokončeném okně (%d)" % completed_events[0])
	_check(ContractManager.state.get("novak_bungalow") == "completed", "zakázka dokončena")
	_check(GameState.money == money_before + 480 + 80, "odměna 480 Kč + bonus za rychlost 80 Kč vyplacena (%d)" % (GameState.money - money_before))
	_check(GameState.xp + GameState.level * 10000 > xp_before, "získány zkušenosti (úroveň %d, %d XP)" % [GameState.level, GameState.xp])
	_check(GameState.history.size() == 1, "zakázka zapsána do historie")
	_check(WindowRegistry.find_window("novak_w1_obyvak").mask.current_total < 0.001, "zbytek špíny po dokončení zmizel")
	await _frames(30)
	_check(SaveManager.read_save().get("contracts", {}).get("state", {}).get("novak_bungalow") == "completed", "automatické uložení po dokončení zakázky")

	# --- UI
	ui.open_tablet()
	await _frames(3)
	_check(ui.tablet.visible and player.ui_open, "tablet se otevře")
	ui.close_all()
	await _frames(2)
	_check(not ui.tablet.visible and not player.ui_open, "tablet se zavře")

	await _etapa2(player)
	await _etapa3(player)
	await _etapa3_fixes(player)
	await _access_checks(player)
	await _etapa4(player)
	await _etapa5(player)
	await _company_base(player)
	await _etapa6(player)
	await _etapa7(player)
	await _tutorial(player)
	await _spin_brushes(player)
	await _cosmetics(player)
	await _atmosphere_checks(player)
	await _kikuska(player)

	# --- výkon: jeden tah přes celé okno
	var t0 := Time.get_ticks_usec()
	var wperf := WindowRegistry.find_window("novak_w5_pracovna")
	wperf.reset_state()
	wperf.activate()
	for k in 60:
		wperf.mask.scrub(Vector2(0.1, 0.5), Vector2(0.12, 0.52), tool, 0.0)
	var per_frame := (Time.get_ticks_usec() - t0) / 60.0
	print("  info: průměrná cena jednoho snímku drhnutí: %.0f µs" % per_frame)
	var t1 := Time.get_ticks_usec()
	wperf.mask.update_wet(0.1)
	wperf.mask.flush()
	print("  info: odpařování + nahrání textury: %.0f µs" % float(Time.get_ticks_usec() - t1))

	print("=== výsledek: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("  - ", f)
	SaveManager.delete_save()
	get_tree().quit(0 if _fails.is_empty() else 1)


func _stand_before(player: Player, w: CleanableWindow, u: float, dist: float) -> void:
	var p := w.plane_to_world(Vector2(u, 0.0), dist)
	player.global_position = Vector3(p.x, 0.02, p.z)
	var n := w.normal()
	player.yaw = atan2(n.x, n.z)
	player.pitch = deg_to_rad(5.0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


func _look(player: Player, pos: Vector3, target: Vector3) -> void:
	player.global_position = pos
	var d := target - (pos + Vector3(0, 1.65, 0))
	player.yaw = atan2(-d.x, -d.z)
	player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player._air_top = pos.y
	player._safe_hist.clear()


func _zigzag(w: CleanableWindow, tool: ToolData) -> void:
	var y := 0.02
	var step := tool.radius * 1.2
	while y < w.glass_size.y:
		w.scrub(Vector2(0.0, y), Vector2(w.glass_size.x, y), tool, 0.0)
		w.scrub(Vector2(w.glass_size.x, y), Vector2(0.0, y), tool, 0.0)
		y += step


func _avg_dirt(w: CleanableWindow, c: Vector2, r: float) -> float:
	var m := w.mask
	var s := 0.0
	var n := 0
	for y in range(int((m.size_m.y - c.y - r) * DirtMask.PX_PER_M), int((m.size_m.y - c.y + r) * DirtMask.PX_PER_M)):
		for x in range(int((c.x - r) * DirtMask.PX_PER_M), int((c.x + r) * DirtMask.PX_PER_M)):
			if x >= 0 and y >= 0 and x < m.w and y < m.h:
				s += m.dirt[y * m.w + x]
				n += 1
	return s / maxi(1, n)


func _avg_wet(w: CleanableWindow, c: Vector2, r: float) -> float:
	var m := w.mask
	var s := 0.0
	var n := 0
	for k in 20:
		var p := c + Vector2(cos(k * 0.7), sin(k * 0.7)) * r * (k / 20.0)
		var x := int(p.x * DirtMask.PX_PER_M / DirtMask.WET_DIV)
		var y := int((m.size_m.y - p.y) * DirtMask.PX_PER_M / DirtMask.WET_DIV)
		if x >= 0 and y >= 0 and x < m.ww and y < m.wh:
			s += m.wet[y * m.ww + x]
			n += 1
	return s / maxi(1, n)


# ------------------------------------------------------------------ Etapa 2

## Okno 1 × 0.6 m s jedním typem špíny všude (pro porovnání nástrojů).
func _uniform(k: int, d: float, t: float) -> DirtMask:
	var m := DirtMask.new(Vector2(1.0, 0.6))
	m.dirt.fill(d)
	m.tough.fill(t)
	m.kind.fill(k)
	return m


func _total(m: DirtMask) -> float:
	var s := 0.0
	for v in m.dirt:
		s += v
	return s


func _wet_all(m: DirtMask, grease: float, dissolve: float = 1.0) -> void:
	for y in [0.1, 0.3, 0.5]:
		for x in [0.1, 0.3, 0.5, 0.7, 0.9]:
			m.spray(Vector2(x, y), 0.17, grease, dissolve)


## Stejné vodorovné tahy hadrem/houbou přes střed okna, vrací odstraněné množství.
func _strokes(m: DirtMask, t: ToolData, n: int, moisture: float = 0.0) -> float:
	var before := _total(m)
	for k in n:
		m.scrub(Vector2(0.05, 0.3), Vector2(0.95, 0.3), t, moisture)
		m.scrub(Vector2(0.95, 0.3), Vector2(0.05, 0.3), t, moisture)
	return before - _total(m)


func _etapa2(player: Player) -> void:
	print("--- Etapa 2 ---")
	var rag := GameState.get_tool("rag_old")
	var micro := GameState.get_tool("rag_micro")
	var sponge := GameState.get_tool("sponge")
	var sq := GameState.get_tool("squeegee_25")
	var deg := GameState.get_tool("degreaser")
	_check(rag and micro and sponge and sq and deg and GameState.get_tool("squeegee_35") and GameState.get_tool("detergent_pro"), "načteno 8 nástrojů a přípravků")

	# typy nečistot na nových oknech
	var expect := {"chata_w1_predni": DirtTypes.MUD, "sklenik_w1": DirtTypes.POLLEN, "obchod_w1_vyloha_l": DirtTypes.GREASE, "statek_w1": DirtTypes.HEAVY, "chlev_w1": DirtTypes.HEAVY, "obchod_w3_bok_l": DirtTypes.GREASE}
	for wid in expect:
		var ww := WindowRegistry.find_window(wid)
		if ww == null:
			_check(false, "okno %s existuje" % wid)
			continue
		ww.activate()
		var kinds := ww.kinds_present()
		_check(kinds.has(expect[wid]), "okno %s má špínu typu %s (%s)" % [wid, DirtTypes.name_of(expect[wid]), ", ".join(kinds.map(func(k): return DirtTypes.name_of(k)))])
	var nov := WindowRegistry.find_window("novak_w1_obyvak")
	var nk := DirtMask.new(nov.glass_size)
	nk.generate(nov.dirt_seed(), nov.dirt_level, DirtProfile.get_profile(""))
	var nkinds := nk.kinds_present()
	_check(not nkinds.has(DirtTypes.MUD) and not nkinds.has(DirtTypes.GREASE) and not nkinds.has(DirtTypes.HEAVY), "Novákovi mají jen špínu jako v Etapě 1")

	# bláto: nasucho skoro nejde, s vodou ano
	var m_dry := _uniform(DirtTypes.MUD, 0.8, 0.5)
	var m_wet := _uniform(DirtTypes.MUD, 0.8, 0.5)
	_wet_all(m_wet, 0.3)
	var r_dry := m_dry.scrub(Vector2(0.05, 0.3), Vector2(0.95, 0.3), rag, 0.0)
	var r_wet := m_wet.scrub(Vector2(0.05, 0.3), Vector2(0.95, 0.3), rag, 0.0)
	_check(r_wet > r_dry * 3.0, "bláto: mokré jde %.1f× lépe než suché (%.1f vs %.1f)" % [r_wet / maxf(r_dry, 0.001), r_wet, r_dry])

	# mastnota: voda s běžným saponátem málo, odmašťovač hodně
	var g_soap := _uniform(DirtTypes.GREASE, 0.8, 0.4)
	var g_deg := _uniform(DirtTypes.GREASE, 0.8, 0.4)
	_wet_all(g_soap, GameState.get_tool("detergent_basic").grease_power)
	_wet_all(g_deg, deg.grease_power)
	var r_soap := g_soap.scrub(Vector2(0.05, 0.3), Vector2(0.95, 0.3), rag, 0.0)
	var r_deg := g_deg.scrub(Vector2(0.05, 0.3), Vector2(0.95, 0.3), rag, 0.0)
	_check(r_deg > r_soap * 1.5, "mastnota: odmašťovač %.1f× účinnější než saponát (%.1f vs %.1f)" % [r_deg / maxf(r_soap, 0.001), r_deg, r_soap])
	var g_micro := _uniform(DirtTypes.GREASE, 0.8, 0.4)
	_wet_all(g_micro, deg.grease_power)
	_check(g_micro.scrub(Vector2(0.05, 0.3), Vector2(0.95, 0.3), micro, 0.0) > r_deg, "mikrovlákno bere mastnotu lépe než starý hadr")

	# silná špína ve vrstvách: první vrstva jde ztuha, spodní rychleji
	var hv_top := _uniform(DirtTypes.HEAVY, 1.0, 1.0)
	var hv_low := _uniform(DirtTypes.HEAVY, 0.3, 1.0)
	var h1 := hv_top.scrub(Vector2(0.05, 0.3), Vector2(0.95, 0.3), rag, 0.0)
	var h2 := hv_low.scrub(Vector2(0.05, 0.3), Vector2(0.95, 0.3), rag, 0.0)
	_check(h2 > h1 * 1.5, "silná špína: horní krusta jde hůř než spodní vrstva (%.1f -> %.1f)" % [h1, h2])

	# stěrka: nasucho skoro nic, na mokrém skle hodně a široký pruh
	var s_dry := _uniform(DirtTypes.DUST, 0.7, 0.3)
	var s_wet := _uniform(DirtTypes.DUST, 0.7, 0.3)
	s_wet.wet.fill(1.0)
	var axis := Vector2(1, 0)
	var bd := _total(s_dry)
	s_dry.scrub_blade(Vector2(0.5, 0.55), Vector2(0.5, 0.05), axis, sq.blade_width, sq)
	var bw := _total(s_wet)
	var wet_mid := s_wet.wet_at(Vector2(0.5, 0.3))
	s_wet.scrub_blade(Vector2(0.5, 0.55), Vector2(0.5, 0.05), axis, sq.blade_width, sq)
	var rd := bd - _total(s_dry)
	var rw := bw - _total(s_wet)
	_check(rw > rd * 4.0, "stěrka: na mokrém skle %.1f× účinnější než nasucho" % (rw / maxf(rd, 0.001)))
	_check(s_wet.dirt_at(Vector2(0.5, 0.3)) < 0.2 and s_wet.dirt_at(Vector2(0.6, 0.3)) < 0.2, "stěrka čistí široký pruh jedním tahem (%.2f / %.2f)" % [s_wet.dirt_at(Vector2(0.5, 0.3)), s_wet.dirt_at(Vector2(0.6, 0.3))])
	_check(s_wet.dirt_at(Vector2(0.5 + sq.blade_width * 0.5 + 0.06, 0.3)) > 0.6, "mimo lištu stěrky špína zůstává")
	_check(s_wet.wet_at(Vector2(0.5, 0.3)) < wet_mid * 0.3, "stěrka stírá vodu ze skla (%.2f -> %.2f)" % [wet_mid, s_wet.wet_at(Vector2(0.5, 0.3))])
	# stejný tah po kouscích = stejný výsledek (nezávislé na FPS)
	var s_a := _uniform(DirtTypes.DUST, 0.7, 0.3)
	var s_b := _uniform(DirtTypes.DUST, 0.7, 0.3)
	s_a.wet.fill(1.0)
	s_b.wet.fill(1.0)
	s_a.scrub_blade(Vector2(0.5, 0.55), Vector2(0.5, 0.05), axis, sq.blade_width, sq)
	for k in 20:
		s_b.scrub_blade(Vector2(0.5, 0.55 - k * 0.025), Vector2(0.5, 0.55 - (k + 1) * 0.025), axis, sq.blade_width, sq)
	_check(absf(_total(s_a) - _total(s_b)) < _total(s_a) * 0.05 + 1.0, "stěrka: výsledek nezávisí na počtu snímků (%.1f vs %.1f)" % [_total(s_a), _total(s_b)])

	# houba roztírá vodu na suché sklo, hadr ne
	var sp := _uniform(DirtTypes.DUST, 0.5, 0.2)
	sp.spray(Vector2(0.15, 0.3), 0.12)
	var rg := _uniform(DirtTypes.DUST, 0.5, 0.2)
	rg.spray(Vector2(0.15, 0.3), 0.12)
	sp.scrub(Vector2(0.15, 0.3), Vector2(0.85, 0.3), sponge, 1.0)
	rg.scrub(Vector2(0.15, 0.3), Vector2(0.85, 0.3), rag, 0.0)
	_check(sp.wet_at(Vector2(0.8, 0.3)) > 0.4 and rg.wet_at(Vector2(0.8, 0.3)) < 0.05, "houba roztírá vodu po skle (%.2f), suchý hadr ne (%.2f)" % [sp.wet_at(Vector2(0.8, 0.3)), rg.wet_at(Vector2(0.8, 0.3))])

	# --- obchod
	GameState.money = 100
	_check(Shop.buy_problem("sponge") != "", "obchod: na houbu nemáš (100 Kč)")
	_check(not Shop.buy("sponge") and not GameState.has_item("sponge"), "obchod: bez peněz se nekoupí")
	GameState.money = 5000
	GameState.level = 2
	_check(Shop.buy_problem("squeegee_35") != "", "obchod: stěrka 35 cm je až od úrovně 3")
	var m0 := GameState.money
	var sponge_price := Shop.price("sponge")
	_check(Shop.buy("sponge") and GameState.has_item("sponge"), "obchod: houba koupena")
	_check(GameState.money == m0 - sponge_price, "obchod: odečteno %d Kč (%d)" % [sponge_price, m0 - GameState.money])
	GameState.level = 3
	var rep0 := GameState.reputation
	GameState.reputation = 0
	_check(Shop.buy_problem("squeegee_35").contains("pověsti"), "obchod: stěrka 35 cm potřebuje pověst ★★★ (%s)" % Shop.buy_problem("squeegee_35"))
	GameState.reputation = GameState.REP_STEPS[2]
	_check(Shop.buy_problem("squeegee_35") == "", "obchod: s pověstí ★★★ jde stěrka 35 cm koupit")
	GameState.reputation = rep0
	GameState.level = 2
	_check(Shop.buy_problem("sponge") != "", "obchod: podruhé stejnou věc nekoupíš")
	for id in Shop.catalog("Nástroje") + Shop.catalog("Chemie") + Shop.catalog("Přístupové vybavení"):
		_check(id.has("price") and int(id["price"]) > 0 and str(id["desc"]) != "", "katalog: %s má cenu a popis" % id["name"])

	# --- talenty
	GameState.talent_points = 0
	_check(not Talents.unlock("pevna_ruka"), "talent bez bodů nejde odemknout")
	GameState.talent_points = 6
	_check(Talents.unlock_problem("profesionalni_tah") != "", "talent bez předpokladu nejde odemknout")
	_check(Talents.unlock_problem("automatizace") != "", "talent z pozdější etapy nejde odemknout")
	var cm0 := GameState.clean_mult()
	_check(Talents.unlock("pevna_ruka") and is_equal_approx(GameState.clean_mult(), cm0 * 1.06), "Pevná ruka: čištění ×1.06 (%.2f)" % GameState.clean_mult())
	var bw0 := GameState.blade_width_mult()
	_check(Talents.unlock("profesionalni_tah") and GameState.blade_width_mult() > bw0 * 1.2, "Profesionální tah: širší stěrka (%.2f)" % GameState.blade_width_mult())
	_check(Talents.unlock("dokonaly_lesk") and GameState.complete_threshold() < 0.98, "Dokonalý lesk: okno hotové dřív (%.2f)" % GameState.complete_threshold())
	var price0 := Shop.price("rag_micro")
	Talents.unlock("dobry_vyjednavac")
	Talents.unlock("vyhodny_nakup")
	_check(Shop.price("rag_micro") < price0, "Výhodný nákup: sleva v obchodě (%d -> %d Kč)" % [price0, Shop.price("rag_micro")])
	_check(is_equal_approx(GameState.reward_multiplier(), 1.1), "Dobrý vyjednavač: odměny ×1.1")
	_check(GameState.talent_points == 1, "body se za talenty odečetly (zbývá %d)" % GameState.talent_points)
	# účinek talentu na skutečné čištění
	var t_a := _uniform(DirtTypes.DUST, 0.7, 0.3)
	var t_b := _uniform(DirtTypes.DUST, 0.7, 0.3)
	t_a.scrub(Vector2(0.05, 0.3), Vector2(0.95, 0.3), rag, 0.0, 1.0)
	t_b.scrub(Vector2(0.05, 0.3), Vector2(0.95, 0.3), rag, 0.0, GameState.clean_mult())
	_check(_total(t_b) < _total(t_a), "násobič z talentu opravdu čistí víc")

	# --- stěrka v pracovním režimu (hráč, myš)
	Shop.buy("squeegee_25")
	GameState.set_active("squeegee_25")
	ContractManager.accept("chata_rybnik")
	var cw := WindowRegistry.find_window("chata_w1_predni")
	_stand_before(player, cw, cw.glass_size.x * 0.5, 0.7)
	await _frames(25)
	cw.activate()
	var sy := 0.08
	while sy < cw.glass_size.y:
		var sx := 0.08
		while sx < cw.glass_size.x:
			cw.spray(Vector2(sx, sy), GameState.get_tool("detergent_basic"))
			sx += 0.12
		sy += 0.12
	player.begin_cleaning(cw, cw.plane_to_world(Vector2(cw.glass_size.x * 0.5, minf(cw.glass_size.y - 0.15, 0.9))))
	_check(player.mode == Player.Mode.CLEANING and player.cleaning.tool.id == "squeegee_25", "pracovní režim se stěrkou")
	if player.mode == Player.Mode.CLEANING:
		var cc := player.cleaning
		await _frames(20)
		var p0 := cc.rag
		var d0 := _avg_dirt(cw, p0 + Vector2(0.0, -0.2), 0.03)
		var dside := _avg_dirt(cw, p0 + Vector2(0.09, -0.2), 0.02)
		cc.debug_press = true
		await _frames(2)
		for i in 70:
			cc.on_mouse_motion(Vector2(0, 5))
			await _frames(1)
		await _frames(10)
		print("  info: stěrka ujela %.2f m, délka tahu %.2f" % [p0.y - cc.rag.y, cc.stroke_len])
		_check(absf(cos(cc.blade_angle)) > 0.9, "lišta stěrky je kolmo na tah (úhel %.2f)" % cc.blade_angle)
		var d1 := _avg_dirt(cw, p0 + Vector2(0.0, -0.2), 0.03)
		var dside1 := _avg_dirt(cw, p0 + Vector2(0.09, -0.2), 0.02)
		_check(d1 < d0 * 0.5 and dside1 < dside * 0.6, "tah stěrkou dolů čistí široký pruh (%.2f -> %.2f, bok %.2f -> %.2f)" % [d0, d1, dside, dside1])
		cc.debug_press = false
		player.end_cleaning()
		await _frames(10)
	GameState.set_active("rag_old")

	# --- nové zakázky: všechny jdou dokončit (nástřik + cikcak)
	GameState.level = 3
	Shop.buy("rag_micro")
	for cid in ["chata_rybnik", "sklenik_dvorakova", "obchod_naves", "statek_horak"]:
		var con := ContractManager.get_contract(cid)
		_check(not ContractManager.is_locked(cid), "zakázka %s je na úrovni 3 dostupná" % con.title)
		ContractManager.accept(cid)
		var money0 := GameState.money
		var expect_money := ContractManager.reward_money(cid)
		var max_passes := 0
		for wid in con.window_ids:
			var ww := WindowRegistry.find_window(wid)
			ww.activate()
			var passes := 0
			while not ww.completed and passes < 80:
				var y := 0.08
				while y < ww.glass_size.y:
					var x := 0.08
					while x < ww.glass_size.x:
						ww.spray(Vector2(x, y), deg)
						x += 0.25
					y += 0.25
				_zigzag(ww, micro)
				passes += 1
				await _frames(1)
			max_passes = maxi(max_passes, passes)
			if not ww.completed:
				_check(false, "okno %s dokončeno (%.1f %%)" % [wid, ww.cleanliness() * 100.0])
		await _frames(5)
		_check(ContractManager.state.get(cid) == "completed", "zakázka %s dokončena (nejvíc %d průchodů na okno)" % [con.title, max_passes])
		_check(GameState.money - money0 >= expect_money, "odměna za %s vyplacena (%d Kč)" % [con.title, GameState.money - money0])

	# --- opakovaná zakázka (pravidelný úklid)
	var ch := WindowRegistry.find_window("chata_w1_predni")
	var gen0 := ch.generation
	ContractManager.accept("chata_rybnik")
	_check(ContractManager.active_id == "chata_rybnik" and ContractManager.is_repeat("chata_rybnik"), "hotovou zakázku lze přijmout znovu")
	_check(ch.generation == gen0 + 1 and not ch.completed and ch.cleanliness() < 0.6, "okna se znovu zašpinila (generace %d, %.0f %%)" % [ch.generation, ch.cleanliness() * 100.0])
	var rep := ContractManager.reward_money("chata_rybnik")
	_check(rep == int(round(420.0 * 0.6 * GameState.reward_multiplier() / 10.0)) * 10, "pravidelný úklid platí 60 %% (%d Kč)" % rep)

	# --- poptávky z vesnice
	await _frames(2)
	var offer_ids: Array = []
	for id in ContractManager.order:
		if ContractManager.is_offer(id) and ContractManager.state.get(id) == "available":
			offer_ids.append(id)
	_check(offer_ids.size() == ContractManager.offer_slots(), "z vesnice visí %d poptávky (míst %d, pověst %s)" % [offer_ids.size(), ContractManager.offer_slots(), GameState.stars_text(GameState.stars())])
	var clients_seen := {}
	for id in offer_ids:
		clients_seen[ContractManager.offers[id]["client"]] = true
		var oc := ContractManager.get_contract(id)
		_check(oc.window_ids.size() >= 2 and WindowRegistry.find_window(oc.window_ids[0]) != null and oc.reward_money > 0, "poptávka %s: %d oken, %d Kč, %d XP" % [oc.title, oc.window_ids.size(), oc.reward_money, oc.reward_xp])
	_check(clients_seen.size() == offer_ids.size(), "každá poptávka je od jiného domu")
	# odmítnutí – přijde jiná
	var declined: String = offer_ids[0]
	ContractManager.decline(declined)
	var after: Array = []
	for id in ContractManager.order:
		if ContractManager.is_offer(id) and ContractManager.state.get(id) == "available":
			after.append(id)
	_check(not ContractManager.contracts.has(declined) and after.size() == offer_ids.size(), "odmítnutá poptávka zmizela a přišla jiná")
	# přijetí a dokončení
	var oid: String = after[0]
	var spec: Dictionary = ContractManager.offers[oid]
	var ocon := ContractManager.get_contract(oid)
	ContractManager.accept(oid)
	var ow := WindowRegistry.find_window(ocon.window_ids[0])
	_check(ow.override_profile == str(spec["profile"]) and not ow.completed, "okna domu se zašpinila podle situace (%s)" % spec["profile"])
	var rep_before := GameState.reputation
	var money_o := GameState.money
	var expect_o := ContractManager.reward_money(oid)
	var cid: String = spec["client"]
	for wid in ocon.window_ids:
		var ww := WindowRegistry.find_window(wid)
		ww.activate()
		var passes := 0
		while not ww.completed and passes < 80:
			var y := 0.08
			while y < ww.glass_size.y:
				var x := 0.08
				while x < ww.glass_size.x:
					ww.spray(Vector2(x, y), deg)
					x += 0.25
				y += 0.25
			_zigzag(ww, micro)
			passes += 1
			await _frames(1)
	await _frames(5)
	_check(GameState.money - money_o >= expect_o, "poptávka dokončena a zaplacena (%d Kč)" % (GameState.money - money_o))
	_check(GameState.reputation > rep_before, "pověst stoupla (%d -> %d)" % [rep_before, GameState.reputation])
	_check(not ContractManager.contracts.has(oid) and int(ContractManager.client_done.get(cid, 0)) == 1, "hotová poptávka zmizela, zákazník si to pamatuje")
	var open_now := 0
	for id in ContractManager.order:
		if ContractManager.is_offer(id) and ContractManager.state.get(id) == "available":
			open_now += 1
	_check(open_now == ContractManager.offer_slots(), "po dokončení přišla nová poptávka (%d)" % open_now)
	# pověst: víc míst a náročnější situace
	var rep_keep := GameState.reputation
	GameState.reputation = GameState.REP_STEPS[4]
	ContractManager.ensure_offers()
	var open4 := 0
	for id in ContractManager.order:
		if ContractManager.is_offer(id) and ContractManager.state.get(id) == "available":
			open4 += 1
	var exp4 := 4 + (1 if GameState.unlocked_areas.has("predmesti") else 0)
	_check(GameState.stars() == 5 and open4 == exp4, "s pověstí ★★★★★ visí %d poptávky (%d)" % [exp4, open4])
	var sits := {}
	for k in 40:
		ContractManager.offer_counter += 1
		var r := ContractManager._roll_offer()
		if not r.is_empty():
			sits[r["situation"]] = true
	_check(sits.has("zanedbane") and sits.has("kuchyn"), "vysoká pověst přináší náročné poptávky (%s)" % ", ".join(sits.keys()))
	GameState.reputation = 0
	sits.clear()
	for k in 40:
		ContractManager.offer_counter += 1
		var r := ContractManager._roll_offer()
		if not r.is_empty():
			sits[r["situation"]] = true
	_check(not sits.has("zanedbane") and not sits.has("kuchyn"), "začátečník nedostává náročné poptávky (%s)" % ", ".join(sits.keys()))
	GameState.reputation = rep_keep
	# rozpracovaná poptávka pro test uložení
	var keep_offer := ""
	for id in ContractManager.order:
		if ContractManager.is_offer(id) and ContractManager.state.get(id) == "available":
			keep_offer = id
			break
	ContractManager.accept(keep_offer)
	var keep_win: String = ContractManager.get_contract(keep_offer).window_ids[0]
	var keep_prof := WindowRegistry.find_window(keep_win).override_profile
	var offers_before: Array = ContractManager.offers.keys()
	offers_before.sort()
	ContractManager.accept("chata_rybnik")

	# --- uložení v2: talenty, inventář, aktivní nástroje, generace oken
	GameState.set_active("sponge")
	var ranks := Talents.to_dict()
	var inv := GameState.inventory.duplicate()
	_check(SaveManager.save_game(true), "Etapa 2: hra uložena")
	Talents.reset()
	GameState.reset()
	WindowRegistry.reset_all()
	ContractManager.reset()
	_check(SaveManager.load_game(), "Etapa 2: hra načtena")
	_check(Talents.to_dict() == ranks, "talenty po načtení sedí")
	_check(GameState.inventory == inv, "inventář po načtení sedí")
	_check(GameState.active_wipe == "sponge", "aktivní nástroj po načtení sedí")
	_check(WindowRegistry.find_window("chata_w1_predni").generation == gen0 + 1, "generace špíny okna se ukládá")
	_check(ContractManager.is_repeat("chata_rybnik") and ContractManager.active_id == "chata_rybnik", "opakovaná zakázka po načtení pokračuje")
	var offers_after: Array = ContractManager.offers.keys()
	offers_after.sort()
	_check(offers_after == offers_before, "poptávky z vesnice se uložily (%s)" % ", ".join(offers_after))
	_check(ContractManager.state.get(keep_offer) == "paused" and WindowRegistry.find_window(keep_win).override_profile == keep_prof, "rozpracovaná poptávka a její špína se uložily")
	_check(GameState.reputation == rep_keep, "pověst se uložila (%d)" % GameState.reputation)

	# --- migrace uložení z Etapy 1 (verze 1)
	var v1 := {
		"version": 1, "game": "clear_view",
		"state": {"money": 777, "xp": 20, "level": 2, "talent_points": 1, "inventory": ["rag_old", "detergent_basic", "chair_wood", "bucket_basic"], "stats": {}, "history": []},
		"contracts": {"state": {"novak_bungalow": "completed"}, "active_id": ""},
		"windows": {}, "player": {"equipped": 1}, "persist": {},
	}
	var mig := SaveManager._migrate(v1)
	_check(int(mig["version"]) == SaveManager.SAVE_VERSION, "migrace v1 -> v%d" % SaveManager.SAVE_VERSION)
	_check(mig["player"].get("held") == "detergent_basic", "migrace: držený předmět z v1")
	GameState.from_dict(mig["state"])
	ContractManager.from_dict(mig["contracts"])
	_check(GameState.money == 777 and GameState.talent_points == 1 and Talents.to_dict().is_empty(), "migrace: peníze a talentový bod z Etapy 1")
	_check(ContractManager.is_repeat("novak_bungalow") and not ContractManager.is_locked("chata_rybnik"), "migrace: hotová zakázka z Etapy 1 = pravidelný úklid")
	_check(GameState.wipe_tool().id == "rag_old" and GameState.spray_tool().id == "detergent_basic", "migrace: výchozí nástroje")


# ------------------------------------------------------------------ Etapa 3

func _face_wall(player: Player, w: CleanableWindow, dist: float) -> void:
	var p := w.plane_to_world(Vector2(w.glass_size.x * 0.5, 0.0), dist)
	player.global_position = Vector3(p.x, 0.02, p.z)
	var n := w.normal()
	player.yaw = atan2(n.x, n.z)
	player.pitch = 0.0
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


func _hold_action(action: String, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)
	await _frames(2)


func _etapa3(player: Player) -> void:
	print("--- Etapa 3: práce ve výškách")
	var world: Countryside = main.world
	var sub: Suburb = world.suburb
	_check(sub != null and sub.global_position.x > 1500.0, "Předměstí je postavené daleko od vesnice")
	var sub_wins := 0
	for id in WindowRegistry.windows:
		if str(id).begins_with("pr_"):
			sub_wins += 1
	_check(sub_wins == 62, "Předměstí má 62 omyvatelných oken (%d)" % sub_wins)
	for cid in ["pr_dum_maly", "pr_kavarna", "pr_vila", "pr_bytovy_dum", "pr_skola"]:
		var cc := ContractManager.get_contract(cid)
		var ok := cc != null
		if ok:
			for wid in cc.window_ids:
				if WindowRegistry.find_window(wid) == null:
					ok = false
					print("  chybí okno ", wid)
		_check(ok, "zakázka %s načtena a všechna její okna existují" % cid)
	var lvl_keep := GameState.level
	GameState.level = 3
	GameState.unlocked_areas = ["venkov"]
	_check(ContractManager.is_locked("pr_dum_maly"), "zakázky Předměstí jsou pod úrovní 4 zamčené")
	# --- autobus
	player.global_position = Vector3(Countryside.BUS_X + 3.1, 0.05, -4.4)
	world.travel(Suburb.AREA_ID, player)
	_check(player.global_position.x < 100.0, "autobus na Předměstí pod úrovní 4 nejede")
	GameState.level = 4
	world.travel(Suburb.AREA_ID, player)
	await _frames(5)
	_check(player.global_position.distance_to(Suburb.ORIGIN + Suburb.ARRIVE) < 1.0, "autobus dovezl hráče na Předměstí")
	_check(GameState.unlocked_areas.has("predmesti"), "oblast Předměstí odemčena")
	_check(WorldMap.area_at(Vector2(player.global_position.x, player.global_position.z)) == "predmesti", "mapa ukazuje oblast Předměstí")
	_check(not ContractManager.is_locked("pr_dum_maly") and ContractManager.is_locked("pr_bytovy_dum"), "od úrovně 4 jde vzít patrový dům, bytový dům ještě ne")
	var sub_offer := false
	for k in 30:
		ContractManager.offer_counter += 1
		var r := ContractManager._roll_offer()
		if not r.is_empty() and str(r["client"]).begins_with("pr_"):
			sub_offer = true
			_check(ContractManager._build_offer(r).location.begins_with("Předměstí"), "poptávka z Předměstí má správné místo")
			break
	_check(sub_offer, "po odemčení chodí i poptávky z Předměstí")
	# pobočka obchodu na Předměstí: blízko zastávky, pult otevře obchod
	var kiosk: ShopKiosk = null
	for c in sub.find_children("ShopKiosk*", "", true, false):
		if c is ShopKiosk:
			kiosk = c
	_check(kiosk != null and kiosk.global_position.distance_to(Suburb.ORIGIN + Suburb.ARRIVE) < 12.0, "na Předměstí je pobočka obchodu kousek od zastávky")
	if kiosk:
		var counter: SimpleInteractable = null
		for c in kiosk.get_children():
			if c is SimpleInteractable:
				counter = c
		_check(counter != null and counter.get_prompt(player).contains("Nakupovat"), "pult pobočky nabízí nákup")
		if counter:
			counter.interact(player)
			await _frames(3)
			var ui_node = world.get_tree().get_first_node_in_group("ui_root")
			_check(ui_node.shop.visible, "pult pobočky otevře obchod s vybavením")
			_check(ui_node.shop._title.text.begins_with("Úklid & Výšky"), "obchod na pobočce má nadpis pobočky")
			ui_node.close_all()
			await _frames(2)

	# --- žebřík: koupě, cesta autobusem, nesení, opření, lezení
	var lad: Ladder = world.ladders[0]
	_check(not lad.visible, "nekoupený žebřík ve světě není")
	GameState.add_item("ladder_small")
	await _frames(2)
	_check(lad.visible and lad.global_position.distance_to(lad.home.origin) < 0.01, "koupený žebřík stojí u garáže")
	world.travel("venkov", player)
	world.travel(Suburb.AREA_ID, player)
	await _frames(3)
	_check(lad.lying and lad.global_position.x > 1500.0, "žebřík jel autobusem s hráčem a leží u zastávky")
	player.global_position = lad.global_position + Vector3(0, 0, 1.2)
	player.pick_up(lad)
	_check(player.carried == lad and not lad.visible, "žebřík zvednut")
	var w4 := WindowRegistry.find_window("pr_maly_w4")
	_face_wall(player, w4, 1.7)
	await _frames(6)
	_check(player._ghost_valid, "u zdi jde žebřík opřít (náhled zelený)")
	player._try_place()
	await _frames(2)
	_check(player.carried == null and lad.visible and not lad.lying, "žebřík opřený o zeď")
	var wall_d := w4.to_local(lad.global_position).z
	_check(absf(wall_d - lad.base_offset()) < 0.25, "pata žebříku je správně od zdi (%.2f m, má být %.2f)" % [wall_d, lad.base_offset()])
	# nedosáhne ze země
	ContractManager.accept("pr_dum_maly")
	_check(ContractManager.active_id == "pr_dum_maly", "zakázka patrového domu přijata")
	_face_wall(player, w4, 0.6)
	await _frames(3)
	player.begin_cleaning(w4, w4.plane_to_world(w4.glass_size * 0.5))
	_check(player.mode == Player.Mode.WALK, "horní okno ze země bez žebříku nejde")
	lad.interact(player)
	_check(player.mode == Player.Mode.LADDER and player.ladder == lad, "hráč vylezl na žebřík")
	await _hold_action("move_forward", 40)
	var h1 := player.ladder_h
	_check(h1 > 0.5, "[W] leze nahoru (%.2f m)" % h1)
	await _frames(20)
	_check(absf(player.ladder_h - h1) < 0.001, "na žebříku jde zastavit v libovolné výšce")
	await _hold_action("move_back", 10)
	_check(player.ladder_h < h1, "[S] slézá dolů")
	player.ladder_h = lad.max_stand()
	await _frames(3)
	_check(player.global_position.y > 2.5, "nahoře na žebříku (nohy %.2f m)" % player.global_position.y)
	player.leave_ladder()
	_check(player.mode == Player.Mode.LADDER and player._auto_descend, "z výšky se neseskakuje – mezerník spustí sestup po příčkách")
	await _frames(20)
	_check(player.mode == Player.Mode.LADDER and player.ladder_h < lad.max_stand() - 0.3, "sestup po příčkách běží (%.2f m)" % player.ladder_h)
	player._auto_descend = false
	player.ladder_h = lad.max_stand()
	await _frames(5)
	player.begin_cleaning(w4, w4.plane_to_world(Vector2(w4.glass_size.x * 0.5, w4.glass_size.y - 0.1)))
	_check(player.mode == Player.Mode.CLEANING, "z žebříku jde mýt horní okno")
	var cc: CleaningController = player.cleaning
	await _frames(3)
	_check(cc.reach_max.y >= w4.glass_size.y - 0.05 and cc.reach_min.y <= 0.05, "ze žebříku dosáhneš na celé okno (%.2f..%.2f z %.2f)" % [cc.reach_min.y, cc.reach_max.y, w4.glass_size.y])
	var dirt0 := w4.cleanliness()
	cc.debug_press = true
	for k in 40:
		cc.rag_target = Vector2(0.1 + (k % 10) * 0.1, w4.glass_size.y * 0.6)
		await _frames(1)
	cc.debug_press = false
	_check(w4.cleanliness() > dirt0, "na žebříku se opravdu myje (%.3f -> %.3f)" % [dirt0, w4.cleanliness()])
	player.end_cleaning()
	await _frames(3)
	_check(player.mode == Player.Mode.LADDER, "po mytí zůstává hráč na žebříku")
	# uložení na žebříku
	_check(SaveManager.save_game(true), "uložení na žebříku")
	var lad_pos := lad.global_position
	player.ladder_h = 0.0
	await _frames(2)
	player.leave_ladder()
	_check(player.mode == Player.Mode.WALK and player.global_position.y < 0.3, "dole ze žebříku jde slézt")
	var saved := SaveManager.read_save()
	_check(int(saved.get("version", 0)) == SaveManager.SAVE_VERSION, "uloženo ve verzi %d" % SaveManager.SAVE_VERSION)
	var sp := SaveManager.arr_to_vec3(saved["player"].get("pos"))
	_check(sp.y < 0.3 and sp.distance_to(lad_pos) < 2.0, "na žebříku se uloží bezpečné místo u paty")
	_check(saved["persist"].has("ladder_small") and saved["state"].get("unlocked_areas", []).has("predmesti"), "uložení obsahuje žebřík a odemčenou oblast")
	lad.send_home()
	SaveManager.load_game()
	await _frames(3)
	_check(lad.global_position.distance_to(lad_pos) < 0.05 and not lad.lying, "žebřík po načtení stojí tam, kde byl opřený")
	_check(player.mode == Player.Mode.WALK and player.ladder == null, "po načtení hráč stojí na zemi")
	# v2 → v3 migrace
	var v2 := {"version": 2, "state": {"level": 5, "unlocked_areas": ["venkov"]}, "contracts": {}, "windows": {}, "player": {}, "persist": {}}
	var m3 := SaveManager._migrate(v2)
	_check(int(m3["version"]) == SaveManager.SAVE_VERSION and (m3["state"]["unlocked_areas"] as Array).has("predmesti"), "migrace v2 -> v3 odemkne Předměstí hráči od úrovně 4")
	var v3 := {"version": 3, "state": {"level": 9, "unlocked_areas": ["venkov", "predmesti"]}, "contracts": {}, "windows": {}, "player": {}, "persist": {}}
	var m4 := SaveManager._migrate(v3)
	_check(int(m4["version"]) == SaveManager.SAVE_VERSION and (m4["state"]["unlocked_areas"] as Array).has("mesto"), "migrace v3 -> v4 odemkne Město hráči od úrovně 8")
	var v3b := {"version": 3, "state": {"level": 6, "unlocked_areas": ["venkov", "predmesti"]}, "contracts": {}, "windows": {}, "player": {}, "persist": {}}
	_check(not (SaveManager._migrate(v3b)["state"]["unlocked_areas"] as Array).has("mesto"), "migrace v3 -> v4 neodemkne Město hráči pod úrovní 8")

	# --- teleskopická tyč
	ContractManager.accept("pr_dum_maly")
	GameState.add_item("tele_squeegee")
	var w1 := WindowRegistry.find_window("pr_maly_w1")
	GameState.set_active("rag_micro" if GameState.has_item("rag_micro") else "rag_old")
	_face_wall(player, w1, 0.6)
	await _frames(3)
	player.begin_cleaning(w1, w1.plane_to_world(w1.glass_size * 0.5))
	await _frames(2)
	var r_hand := cc.reach_max.y
	player.end_cleaning()
	await _frames(2)
	_check(player.mode == Player.Mode.WALK, "mytí rukou ukončeno")
	GameState.set_active("tele_squeegee")
	player.begin_cleaning(w1, w1.plane_to_world(w1.glass_size * 0.5))
	_check(player.mode == Player.Mode.CLEANING and cc.tool.id == "tele_squeegee", "mytí teleskopickou tyčí se stěrkou")
	await _frames(2)
	_check(player.hand.pole.visible, "v ruce je vidět teleskopická tyč")
	var r_tele := cc.reach_max.y
	player.end_cleaning()
	await _frames(2)
	_check(r_tele > r_hand or r_tele >= w1.glass_size.y - 0.05, "tyč prodlouží dosah (%.2f -> %.2f)" % [r_hand, r_tele])
	Talents.ranks["dlouhy_dosah"] = 1
	_check(is_equal_approx(GameState.reach_bonus(GameState.get_tool("tele_squeegee")), 1.7 * 1.2), "talent Dlouhý dosah: tyč ×1.2")
	Talents.ranks.erase("dlouhy_dosah")
	GameState.set_active("rag_old")

	# --- elektrický kartáč a speciální chemie
	var brush := GameState.get_tool("brush_electric")
	var rag := GameState.get_tool("rag_old")
	var mb := _uniform(DirtTypes.HEAVY, 0.9, 1.0)
	var mr := _uniform(DirtTypes.HEAVY, 0.9, 1.0)
	_check(_strokes(mb, brush, 2) > _strokes(mr, rag, 2) * 1.5, "elektrický kartáč rozbije silnou špínu rychleji než hadr")
	var e0 := GameState.clean_mult(brush)
	Talents.ranks["technicky_genius"] = 1
	_check(GameState.clean_mult(brush) > e0 and is_equal_approx(GameState.clean_mult(rag), Talents.mult("clean_mult")), "Technický génius posílí jen elektrické nástroje")
	Talents.ranks.erase("technicky_genius")
	var sponge := GameState.get_tool("sponge")
	var ms := _uniform(DirtTypes.HEAVY, 0.9, 1.0)
	var mp := _uniform(DirtTypes.HEAVY, 0.9, 1.0)
	var spec_t := GameState.get_tool("chem_special")
	var pro_t := GameState.get_tool("detergent_pro")
	_wet_all(ms, spec_t.grease_power, spec_t.dissolve)
	_wet_all(mp, pro_t.grease_power, pro_t.dissolve)
	var rs := _strokes(ms, sponge, 2)
	var rp := _strokes(mp, sponge, 2)
	_check(rs > rp * 1.15, "speciální chemie povolí silnou špínu víc než profesionální přípravek (%.0f vs %.0f)" % [rs, rp])

	# --- tlakový rozprašovač
	var w5 := WindowRegistry.find_window("pr_maly_w5")
	w5.activate()
	_look(player, w5.plane_to_world(Vector2(w5.glass_size.x * 0.5, 0.0), 3.2) * Vector3(1, 0, 1) + Vector3(0, 0.02, 0), w5.plane_to_world(w5.glass_size * 0.5))
	await _frames(4)
	_check(player.focus_window == null, "horní okno je mimo běžný dosah")
	_check(not player._spray_far(), "bez tlakového rozprašovače na patro nenastříkáš")
	GameState.add_item("sprayer_pressure")
	var wet0 := _avg_wet(w5, w5.glass_size * 0.5, 0.1)
	_check(player._spray_far(), "tlakový rozprašovač nastříká okno v patře ze země")
	_check(_avg_wet(w5, w5.glass_size * 0.5, 0.1) > wet0 + 0.2, "okno v patře je po nástřiku mokré")

	# --- lano a slaňování
	var a: RopeAnchor = sub.anchors[0]
	sub._teleport(player, a.roof_spot() - Suburb.ORIGIN, PI)
	await _frames(20)
	_check(player.is_on_floor() and player.global_position.y > 12.0, "schodiště vede na střechu bytového domu (%.2f m)" % player.global_position.y)
	a.interact(player)
	_check(player.mode == Player.Mode.WALK, "bez lanového setu se připnout nejde")
	GameState.add_item("rope_kit")
	a.interact(player)
	_check(player.mode == Player.Mode.ROPE and player.anchor == a, "hráč se připnul ke kotvě")
	var y_top := player.rope_y
	await _hold_action("move_back", 60)
	_check(player.rope_y < y_top - 0.8, "[S] spouští po fasádě (%.2f -> %.2f)" % [y_top, player.rope_y])
	var y_mid := player.rope_y
	await _frames(20)
	_check(absf(player.rope_y - y_mid) < 0.001, "na laně jde zastavit v libovolné výšce")
	await _hold_action("move_right", 200)
	_check(absf(player.rope_u - a.side_range()) < 0.01, "do stran jen v omezeném rozsahu (%.2f)" % player.rope_u)
	player._rope_exit()
	_check(player.mode == Player.Mode.ROPE, "v půlce fasády se odepnout nejde")
	var wp := WindowRegistry.find_window("pr_byty_p3_1")
	player.rope_u = a.side().dot(wp.global_position - a.global_position)
	player.rope_y = wp.global_position.y - 1.4
	await _frames(3)
	GameState.level = 6
	ContractManager.accept("pr_bytovy_dum")
	player.begin_cleaning(wp, wp.plane_to_world(wp.glass_size * 0.5))
	_check(player.mode == Player.Mode.CLEANING, "z lana jde mýt okno ve 3. patře")
	await _frames(2)
	_check(cc.reach_valid and cc.reach_max.y > wp.glass_size.y * 0.8, "z lana je dosah na okno")
	await _hold_action("move_back", 20)
	_check(player.rope_y < wp.global_position.y - 1.4, "při mytí jde po laně pomalu posouvat")
	player.end_cleaning()
	await _frames(2)
	_check(player.mode == Player.Mode.ROPE, "po mytí visí hráč dál na laně")
	player.rope_y = a.bottom_feet()
	await _frames(2)
	player._rope_exit()
	await _frames(10)
	_check(player.mode == Player.Mode.WALK and player.global_position.y < 0.5, "dole na zemi se jde odepnout")
	# zpět nahoru a odepnout u kotvy
	sub._teleport(player, a.roof_spot() - Suburb.ORIGIN, PI)
	await _frames(5)
	a.interact(player)
	await _hold_action("move_back", 30)
	await _hold_action("move_forward", 200)
	_check(absf(player.rope_y - a.top_feet()) < 0.01, "[W] vytáhne hráče nahoru ke kotvě")
	player._rope_exit()
	await _frames(10)
	_check(player.mode == Player.Mode.WALK and player.global_position.y > 12.0, "nahoře se jde odepnout zpět na střechu")

	# --- pád z výšky = bezpečný návrat
	await _frames(30)
	player.global_position = a.global_position + a.outward() * 2.5 + Vector3(0, 1.0, 0)
	player.velocity = Vector3.ZERO
	await _frames(90)
	_check(player.global_position.y > 12.0, "po pádu ze střechy se hráč bezpečně vrátil (%.2f m)" % player.global_position.y)

	GameState.level = lvl_keep
	sub._teleport(player, Suburb.ARRIVE, Suburb.ARRIVE_YAW)
	world.travel("venkov", player)
	await _frames(3)


## Opravy po hraní Etapy 3: zakrytá okna, nádržka rozprašovače, interiéry.
func _etapa3_fixes(player: Player) -> void:
	print("--- Etapa 3: nádržka, zakrytá okna, interiéry")
	await _frames(2)
	var space := player.get_world_3d().direct_space_state
	# --- žádné okno není zakryté zdí: paprsek zvenku musí jako první trefit sklo
	var covered: Array[String] = []
	for id in WindowRegistry.windows:
		var w: CleanableWindow = WindowRegistry.windows[id]
		var gs := w.glass_size
		for p: Vector2 in [Vector2(0.5, 0.5), Vector2(0.15, 0.2), Vector2(0.85, 0.8), Vector2(0.15, 0.8), Vector2(0.85, 0.2)]:
			var pp := Vector2(gs.x * p.x, gs.y * p.y)
			var q := PhysicsRayQueryParameters3D.create(w.plane_to_world(pp, 0.6), w.plane_to_world(pp, -0.05), 1 | CleanableWindow.WINDOW_LAYER, [player.get_rid()])
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty() or not (hit["collider"] as Object).has_meta("window") or hit["collider"].get_meta("window") != w:
				covered.append(str(id))
				if covered.size() <= 2:
					print("  info: okno %s zakrývá %s v %s" % [id, "nic" if hit.is_empty() else str((hit["collider"] as Node).get_path()), "-" if hit.is_empty() else str(hit["position"])])
				break
	_check(covered.is_empty(), "žádné okno není zakryté zdí ani jiným dílem (%s)" % ", ".join(covered))
	# --- interiéry: za každým oknem velkých budov je zařízená místnost
	for cid in ["pr_dum_maly", "pr_kavarna", "pr_vila", "pr_bytovy_dum", "pr_skola"]:
		var c := ContractManager.get_contract(cid)
		var rooms := 0
		for wid in c.window_ids:
			var n: Node = WindowRegistry.find_window(wid)
			while n and not n.has_meta("rooms"):
				n = n.get_parent()
			if n and (n.get_meta("rooms") as Dictionary).has(str(wid)):
				rooms += 1
		_check(rooms == c.window_ids.size(), "%s: za každým oknem je zařízená místnost (%d/%d)" % [cid, rooms, c.window_ids.size()])
	# --- dispozice: každé patro má chodbu, do které vedou dveře z pokojů
	var plans := 0
	var bad_corr := []
	for b in main.world.find_children("*", "Node3D", true, false):
		if b.has_meta("plan"):
			plans += 1
			for pl in b.get_meta("plan"):
				if float(pl["corridor"][1]) - float(pl["corridor"][0]) < 1.0:
					bad_corr.append("%s/%d" % [b.name, pl["level"]])
	_check(plans >= 17 and bad_corr.is_empty(), "%d budov s dispozicí, každé patro má chodbu aspoň 1 m (%s)" % [plans, ", ".join(bad_corr)])
	# --- nádržka rozprašovače
	var keep_inv := GameState.inventory.duplicate()
	GameState.inventory.erase("sprayer_pressure")
	GameState.inventory.erase("tank_backpack")
	_check(is_equal_approx(GameState.tank_max(), 30.0), "základní nádržka má 30 nástřiků (%.0f)" % GameState.tank_max())
	GameState.refill_tank()
	var w0 := WindowRegistry.find_window("novak_w5_pracovna")
	w0.reset_state()
	_stand_before(player, w0, w0.glass_size.x * 0.5, 0.9)
	await _frames(3)
	var t0 := GameState.tank
	_check(GameState.use_tank() and is_equal_approx(GameState.tank, t0 - 1.0), "nástřik ubere z nádržky jeden díl")
	GameState.tank = 0.0
	_check(not GameState.use_tank() and GameState.tank == 0.0, "s prázdnou nádržkou rozprašovač nestříká")
	GameState.refill_tank()
	_check(is_equal_approx(GameState.tank, GameState.tank_max()), "doplnění u vody nádržku naplní")
	# mytí nasucho jde, ale pomaleji
	var tool: ToolData = GameState.get_tool("rag_old")
	w0.reset_state()
	w0.activate()
	var dry := 0.0
	for k in 3:
		dry += w0.mask.scrub(Vector2(0.35, 0.5), Vector2(0.65, 0.5), tool, 0.0)
	w0.reset_state()
	w0.activate()
	for x in [0.35, 0.5, 0.65]:
		w0.spray(Vector2(x, 0.5), GameState.spray_tool(), 1.0, 0.0)
	var wet := 0.0
	for k in 3:
		wet += w0.mask.scrub(Vector2(0.35, 0.5), Vector2(0.65, 0.5), tool, 0.0)
	print("  info: nasucho %.4f, namokro %.4f" % [dry, wet])
	_check(dry > 0.0 and wet > dry * 1.5, "nasucho se myje taky, ale znatelně pomaleji (%.1f× pomaleji)" % (wet / maxf(dry, 0.001)))
	# kolik tahů je potřeba na čistý pruh (nasucho vs. jeden nástřik)
	var strokes := []
	for wet_run in [false, true]:
		w0.reset_state()
		w0.activate()
		if wet_run:
			for x in [0.35, 0.5, 0.65]:
				w0.spray(Vector2(x, 0.5), GameState.spray_tool(), 1.0, 0.0)
		var n := 0
		while n < 300:
			w0.mask.scrub(Vector2(0.3, 0.5), Vector2(0.7, 0.5), tool, 0.0)
			n += 1
			var clean := true
			for x in [0.4, 0.5, 0.6]:
				if w0.mask.dirt_at(Vector2(x, 0.5)) > 0.05:
					clean = false
			if clean:
				break
		strokes.append(n)
	print("  info: tahů na čistý pruh – nasucho %d, po nástřiku %d" % strokes)
	_check(strokes[0] >= strokes[1] * 2, "nasucho je potřeba aspoň dvakrát víc tahů (%d vs %d)" % strokes)
	w0.reset_state()
	# kapacita: tlakový rozprašovač, zádová nádrž, talent Velká nádržka
	GameState.add_item("sprayer_pressure")
	GameState.add_item("tank_backpack")
	_check(is_equal_approx(GameState.tank_max(), 75.0), "tlakový rozprašovač + zádová nádrž = 75 nástřiků (%.0f)" % GameState.tank_max())
	var keep_r := Talents.ranks.duplicate()
	Talents.ranks["velka_nadrz"] = 1
	_check(is_equal_approx(GameState.tank_max(), 112.5), "talent Velká nádržka zvětší nádržku o polovinu (%.1f)" % GameState.tank_max())
	_check(not Talents.has_effect("auto_wet"), "automatický zavlažovač je jen připravený na Etapu 4")
	GameState.tank = 42.0
	_check(SaveManager.save_game(true), "uložení s nádržkou")
	GameState.tank = 3.0
	_check(SaveManager.load_game(), "načtení s nádržkou")
	_check(is_equal_approx(GameState.tank, 42.0), "stav nádržky se uloží a načte (%.0f)" % GameState.tank)
	Talents.ranks = keep_r
	GameState.inventory = keep_inv
	GameState.refill_tank()
	await _frames(3)


## Dosažitelnost oken, nutné vybavení, počítání oken zakázek a značky zbývajících oken.
func _access_checks(player: Player) -> void:
	print("--- Dosah oken, nutné vybavení, počítadlo zakázek")
	var names := ["země", "židle", "malý žebřík", "výsuvný žebřík", "lano", "plošina", "NIC"]
	# 1) všechny seznamy oken (příběhové zakázky i zákazníci) – existují, bez duplicit, dosažitelné
	var lists := {}
	for id in ContractManager.order:
		lists[id] = ContractManager.contracts[id].window_ids
	for cid in ContractManager.clients:
		lists["klient " + cid] = PackedStringArray(ContractManager.clients[cid]["all"])
	var problems := []
	for key in lists:
		var seen := {}
		var top := 0
		for wid in lists[key]:
			var w := WindowRegistry.find_window(wid)
			if w == null:
				problems.append("%s: okno %s neexistuje" % [key, wid])
				continue
			if seen.has(wid):
				problems.append("%s: okno %s je v seznamu dvakrát" % [key, wid])
			seen[wid] = true
			var t := WindowAccess.tier(w, true)
			top = maxi(top, WindowAccess.tier(w))
			if t == WindowAccess.NONE:
				problems.append("%s: na okno %s (horní hrana %.1f m) nejde dosáhnout ničím" % [key, wid, WindowAccess.top_height(w)])
		if str(key).begins_with("pr_") or str(key).begins_with("klient pr_") or str(key).begins_with("me_") or str(key).begins_with("klient me_"):
			print("  info: %s – nejvýš potřeba: %s" % [key, names[top]])
	_check(problems.is_empty(), "všechna okna všech zakázek existují, nejsou dvakrát a dá se na ně dosáhnout (%s)" % "; ".join(problems))
	# 2) nutné vybavení v tabletu
	var keep_inv := GameState.inventory.duplicate()
	for it in ["ladder_small", "ladder_ext", "rope_kit", "tele_squeegee", "tele_mop"]:
		GameState.inventory.erase(it)
	var skola := ContractManager.get_contract("pr_skola")
	var r := WindowAccess.requirement(skola.window_ids)
	print("  info: škola bez vybavení: ", r["text"])
	_check(r["missing"] and int(r["tier"]) >= WindowAccess.LADDER_S, "škola bez žebříku/lana: tablet hlásí chybějící nutné vybavení")
	var nov := WindowAccess.requirement(ContractManager.get_contract("novak_bungalow").window_ids)
	_check(not nov["missing"], "bungalov jde umýt se základním vybavením (%s)" % nov["text"])
	GameState.inventory = keep_inv
	for it in ["ladder_small", "ladder_ext", "rope_kit"]:
		GameState.add_item(it)
	r = WindowAccess.requirement(skola.window_ids)
	print("  info: škola s žebříky a lanem: ", r["text"])
	_check(not r["missing"], "se žebříky a lanem je škola celá dosažitelná")
	# 3) každá příběhová zakázka Předměstí jde dokončit a počítadlo sedí
	var lvl_keep := GameState.level
	GameState.level = 10
	GameState.unlock_area("predmesti")
	var markers: WindowMarkers = main.get_node("WindowMarkers")
	for cid in ["pr_dum_maly", "pr_kavarna", "pr_vila", "pr_bytovy_dum", "pr_skola"]:
		ContractManager.accept(cid)
		await _frames(2)
		var c := ContractManager.get_contract(cid)
		var p0 := ContractManager.progress(cid)
		_check(markers.remaining().size() == p0.y - p0.x and markers._marks.size() == p0.y - p0.x, "%s: značky jsou u všech %d zbývajících oken" % [cid, p0.y - p0.x])
		for wid in c.window_ids:
			var w := WindowRegistry.find_window(wid)
			if not w.completed:
				w.activate()
				w._complete()
		await _frames(3)
		var p := ContractManager.progress(cid)
		_check(ContractManager.state.get(cid) == "completed" and p.x == p.y, "%s: po umytí všech oken je zakázka hotová (%d / %d)" % [cid, p.x, p.y])
		_check(markers.remaining().is_empty(), "%s: po dokončení nezůstane žádná značka" % cid)
	# 4) poptávka sdílející okna s hotovou příběhovou zakázkou se taky dokončí
	var spec := {"id": "poptavka_test", "client": "pr_dum_b", "situation": "bezne", "profile": "", "windows": ["pr_maly_w1", "pr_maly_w2"], "scope": "test", "money": 100, "xp": 10, "rep": 1, "bonus_min": 0.0, "bonus_money": 0, "prepared": false}
	if ContractManager.clients.has("pr_dum_b"):
		ContractManager._add_offer(spec)
		ContractManager.accept("poptavka_test")
		await _frames(2)
		_check(ContractManager.progress("poptavka_test").x == 0, "přijatá poptávka má okna znovu špinavá (0 / 2)")
		for wid in ["pr_maly_w1", "pr_maly_w2"]:
			WindowRegistry.find_window(wid)._complete()
		await _frames(3)
		_check(not ContractManager.offers.has("poptavka_test") or ContractManager.state.get("poptavka_test") == "completed", "poptávka se sdílenými okny se po umytí dokončí")
	else:
		print("  info: klient pr_maly neexistuje, test sdílených oken přeskočen")
	# 5) skoro hotové okno se při odchodu dočistí
	var wf := WindowRegistry.find_window("novak_w2_kuchyn")
	wf.reset_state()
	wf.activate()
	wf.finish_if_almost()
	_check(not wf.completed, "špinavé okno se odchodem nedokončí")
	wf.mask.clear_all()
	wf.finish_if_almost()
	_check(wf.completed, "skoro čisté okno se při odchodu dočistí samo")
	# dokončení a hned nové zašpinění (nová zakázka): nová špína nesmí po animaci zmizet
	wf.redirty()
	wf.activate()
	await get_tree().create_timer(1.3).timeout
	_check(not wf.completed and wf.cleanliness() < 0.2, "znovu zašpiněné okno nezůstane neviditelně čisté (%.2f)" % wf.cleanliness())
	wf.reset_state()
	# 6) z lana jde ve 3. patře školy dosáhnout na celou šířku každého okna
	ContractManager.accept("pr_skola")
	var cc: CleaningController = player.cleaning
	var full := 0
	for k in 5:
		var ws := WindowRegistry.find_window("pr_skola_p2_%d" % (k + 1))
		var an := WindowAccess.anchor_for(ws)
		if an == null:
			continue
		player.attach_rope(an)
		await _frames(2)
		var c := ws.plane_to_world(ws.glass_size * 0.5)
		var u0 := an.side().dot(c - an.global_position)
		var lo := 99.0
		var hi := -99.0
		for off: float in [-0.8, 0.0, 0.8]:
			player.rope_u = clampf(u0 + off, -an.side_range(), an.side_range())
			player.rope_y = ws.plane_to_world(Vector2(0, 0)).y - 0.3
			await _frames(3)
			player.begin_cleaning(ws, c)
			await _frames(2)
			if player.mode == Player.Mode.CLEANING and cc.reach_valid:
				lo = minf(lo, cc.reach_min.x)
				hi = maxf(hi, cc.reach_max.x)
			player.end_cleaning()
			await _frames(2)
		if lo <= 0.15 and hi >= ws.glass_size.x - 0.15:
			full += 1
		else:
			print("  info: okno %d dosah x %.2f–%.2f z %.2f" % [k + 1, lo, hi, ws.glass_size.x])
		player.rope_y = an.top_feet()
		await _frames(2)
		player._rope_exit()
		await _frames(5)
	_check(full == 5, "z lana jde ve 3. patře školy dosáhnout na celou šířku všech 5 oken (%d)" % full)
	GameState.level = lvl_keep
	GameState.inventory = keep_inv
	await _frames(3)


## Etapa 4 – město Brodec, závěsná plošina, výškové zakázky, nové nástroje a talenty.
func _etapa4(player: Player) -> void:
	print("--- Etapa 4: město")
	var world: Countryside = main.world
	var ui: UIRoot = main.ui
	var city: City = world.city
	_check(city != null and city.global_position.x < -1500.0, "Město je postavené daleko od vesnice")
	var cw := 0
	for id in WindowRegistry.windows:
		if str(id).begins_with("me_"):
			cw += 1
	_check(cw == 102, "Město má 102 omyvatelných oken (%d)" % cw)
	var keep_inv := GameState.inventory.duplicate()
	var lvl_keep := GameState.level
	# --- autobus a odemčení
	player.global_position = Vector3(Countryside.BUS_X + 3.1, 0.05, -4.4)
	await _frames(2)
	GameState.level = 7
	GameState.unlocked_areas.erase("mesto")
	world.travel(City.AREA_ID, player)
	_check(player.global_position.x > -100.0, "autobus do města pod úrovní 8 nejede")
	_check(ContractManager.is_locked("me_od_vylohy"), "zakázky města jsou pod úrovní 8 zamčené")
	GameState.level = 8
	world.travel(City.AREA_ID, player)
	await _frames(5)
	_check(player.global_position.distance_to(City.ORIGIN + City.ARRIVE) < 1.0, "autobus dovezl hráče do města")
	_check(GameState.unlocked_areas.has("mesto"), "oblast Město odemčena")
	_check(WorldMap.area_at(Vector2(player.global_position.x, player.global_position.z)) == "mesto", "mapa ukazuje oblast Město")
	_check(not ContractManager.is_locked("me_od_vylohy") and ContractManager.is_locked("me_meridian_vyssi"), "od úrovně 8 jdou výlohy, Meridian nahoře až později")
	var kiosk: ShopKiosk = null
	for c in city.find_children("ShopKiosk*", "", true, false):
		if c is ShopKiosk:
			kiosk = c
	_check(kiosk != null and kiosk.global_position.distance_to(City.ORIGIN + City.ARRIVE) < 15.0, "ve městě je pobočka obchodu kousek od zastávky")
	var exits := 0
	for c in city.get_children():
		if c is SimpleInteractable and (c as SimpleInteractable).prompt.contains("Sejít schodištěm"):
			exits += 1
	_check(exits == 4, "na všech 4 střechách města je nástavba se schodištěm dolů (%d)" % exits)
	var city_offer := false
	for k in 40:
		ContractManager.offer_counter += 1
		var r := ContractManager._roll_offer()
		if not r.is_empty() and str(r["client"]).begins_with("me_"):
			city_offer = true
			_check(ContractManager._build_offer(r).location.begins_with("Město"), "poptávka z města má správné místo")
			break
	_check(city_offer, "po odemčení chodí i poptávky z města")
	# --- nutné vybavení: plošina
	for it in ["ladder_small", "ladder_ext", "rope_kit", "tele_squeegee", "tele_mop", "fold_mop", "platform_cert"]:
		GameState.inventory.erase(it)
	var mv := ContractManager.get_contract("me_meridian_vyssi")
	var req := WindowAccess.requirement(mv.window_ids)
	print("  info: Meridian nahoře bez vybavení: ", req["text"])
	_check(int(req["tier"]) == WindowAccess.PLATFORM and req["missing"], "horní patra Meridianu potřebují plošinu a tablet to hlásí")
	GameState.add_item("platform_cert")
	req = WindowAccess.requirement(mv.window_ids)
	_check(not req["missing"], "s oprávněním k plošinám jsou horní patra Meridianu dosažitelná (%s)" % req["text"])
	for cid in ["me_hotel_vyssi", "me_meridian_nizsi", "me_hotel_nizsi"]:
		_check(not WindowAccess.requirement(ContractManager.get_contract(cid).window_ids)["missing"], "%s: s plošinou je všechno dosažitelné" % cid)
	for it in ["ladder_small", "ladder_ext", "rope_kit"]:
		GameState.add_item(it)
	for cid in ["me_od_vylohy", "me_od_patra", "me_cinzak_ulice"]:
		_check(not WindowAccess.requirement(ContractManager.get_contract(cid).window_ids)["missing"], "%s: se žebříky a lanem je všechno dosažitelné" % cid)
	# --- závěsná plošina
	var pl: SuspendedPlatform = city.platforms[0]
	GameState.inventory.erase("platform_cert")
	player.global_position = pl.roof_spot()
	await _frames(3)
	pl.interact(player)
	_check(player.mode == Player.Mode.WALK, "bez oprávnění se na plošinu nastoupit nedá")
	GameState.add_item("platform_cert")
	pl.interact(player)
	await _frames(3)
	_check(player.mode == Player.Mode.ROPE and player.anchor == pl, "s oprávněním hráč nastoupí do koše plošiny")
	_check(pl.side_range() > 8.0, "plošina jezdí po celé šířce fasády (±%.1f m)" % pl.side_range())
	var y0 := player.rope_y
	Input.action_press("move_back")
	await _frames(40)
	Input.action_release("move_back")
	_check(player.rope_y < y0 - 0.3, "[S] spouští koš dolů (%.2f -> %.2f)" % [y0, player.rope_y])
	var u0 := player.rope_u
	Input.action_press("move_right")
	await _frames(40)
	Input.action_release("move_right")
	_check(absf(player.rope_u - u0) > 0.3, "[D] posouvá koš podél fasády")
	_check(pl._basket.global_position.distance_to(player.global_position) < 0.2, "koš plošiny jede s hráčem")
	# umytí okna v 6. patře z plošiny
	GameState.level = 10
	ContractManager.accept("me_meridian_vyssi")
	await _frames(2)
	var w6 := WindowRegistry.find_window("me_meridian_p6_2")
	var wc := w6.plane_to_world(w6.glass_size * 0.5)
	player.rope_u = pl.side().dot(wc - pl.global_position)
	player.rope_y = w6.plane_to_world(Vector2(0, 0)).y - 0.4
	await _frames(4)
	w6.activate()
	player.begin_cleaning(w6, wc)
	await _frames(3)
	var ccl: CleaningController = player.cleaning
	if not (player.mode == Player.Mode.CLEANING and ccl.reach_valid):
		print("  info: plošina mód %d, reach_valid %s, min %s max %s, dist %.2f, feet %s" % [player.mode, ccl.reach_valid, ccl.reach_min, ccl.reach_max, w6.to_local(player.global_position).z, w6.to_plane(player.global_position)])
	_check(player.mode == Player.Mode.CLEANING and ccl.reach_valid, "z plošiny jde mýt okno v 6. patře")
	if player.mode == Player.Mode.CLEANING:
		var cl0 := _total(w6.mask)
		ccl.debug_press = true
		for i in 60:
			ccl.on_mouse_motion(Vector2(12 if (i / 15) % 2 == 0 else -12, 2))
			await _frames(1)
		ccl.debug_press = false
		_check(_total(w6.mask) < cl0 - 5.0, "na plošině se okno opravdu myje – starým hadrem nasucho jen málo (špína %.0f -> %.0f)" % [cl0, _total(w6.mask)])
		# automatický zavlažovač (talent)
		GameState.talent_points += 4
		for tid in ["sikovny_pracovnik", "uspore_davkovani", "velka_nadrz", "automaticky_zavlazovac"]:
			Talents.unlock(tid)
		_check(Talents.has_effect("auto_wet"), "talent Automatický zavlažovač jde v Etapě 4 odemknout")
		var wet0 := w6.mask.wet_at(ccl.rag + Vector2(0, 0.12))
		await get_tree().create_timer(1.0).timeout
		_check(w6.mask.wet_at(ccl.rag + Vector2(0, 0.12)) > wet0 + 0.05, "zavlažovač na plošině sám vlhčí sklo (%.2f -> %.2f)" % [wet0, w6.mask.wet_at(ccl.rag + Vector2(0, 0.12))])
		player.end_cleaning()
		await _frames(2)
	player.rope_y = 2.0
	await _frames(2)
	player._rope_exit()
	_check(player.mode == Player.Mode.ROPE, "uprostřed fasády z plošiny vystoupit nejde")
	player.rope_y = pl.top_feet()
	await _frames(2)
	player._rope_exit()
	await _frames(5)
	_check(player.mode == Player.Mode.WALK and player.global_position.y > 20.0, "nahoře hráč vystoupí z koše na střechu")
	# sjet dolů, vystoupit a znovu nastoupit zespodu přímo do koše
	pl.interact(player)
	await _frames(2)
	player.rope_y = pl.bottom_feet()
	await _frames(3)
	player._rope_exit()
	await _frames(5)
	var low_ok := player.mode == Player.Mode.WALK and player.global_position.y < pl.ground_y + 1.0
	_check(low_ok, "dole hráč z plošiny vystoupí na zem (y %.1f)" % player.global_position.y)
	_check(pl._board.collision_layer == 1, "prázdný koš dole má nástup [E] (kolize zapnutá)")
	_check(player.global_position.distance_to(pl._basket.global_position) > 0.8, "po vystoupení hráč nestojí v koši")
	_look(player, player.global_position, pl._basket.global_position + Vector3.UP * 0.6)
	# kamera po výstupu z koše plynule dosedne do výšky očí – počkat, než se ustálí
	for k in 40:
		await _frames(1)
		if absf(player.camera.global_position.y - player.global_position.y - 1.65) < 0.1:
			break
	_look(player, player.global_position, pl._basket.global_position + Vector3.UP * 0.6)
	await _frames(3)
	_check(player.focus_object == pl._board, "zespodu se dá zamířit na koš plošiny")
	if player.focus_object != pl._board:
		var cf := player.camera.global_position
		var qd := PhysicsRayQueryParameters3D.create(cf, cf - player.camera.global_basis.z * 4.0, 1 | CleanableWindow.WINDOW_LAYER, [player.get_rid()])
		var hd := player.get_world_3d().direct_space_state.intersect_ray(qd)
		print("  DEBUG koš: kamera %s, koš %s, zásah %s" % [cf, pl._basket.global_position, (str((hd["collider"] as Node).get_path()) + " " + str(hd["position"])) if not hd.is_empty() else "nic"])
	if player.focus_object:
		player.focus_object.interact(player)
	await _frames(3)
	_check(player.mode == Player.Mode.ROPE and player.anchor == pl and absf(player.rope_y - pl.bottom_feet()) < 0.3, "zespodu jde do koše znovu nastoupit a jet (výška %.1f)" % player.rope_y)
	_check(pl._board.collision_layer == 0, "když v koši jede hráč, koš ho neblokuje")
	player.rope_y = 6.0
	await _frames(3)
	_check(absf(player.global_position.y - 6.0) < 0.2 and pl._basket.global_position.distance_to(player.global_position) < 0.2, "po novém nástupu koš jede s hráčem nahoru")
	_check(pl._cables[0].visible and pl._cables[1].visible, "lana vedou z kladek výložníku do navijáků koše")
	player.rope_y = pl.top_feet()
	await _frames(2)
	player._rope_exit()
	await _frames(3)
	# tablet: zakázky jen pro oblast, kde hráč je
	var tab: Tablet = ui.tablet
	tab._all_areas = false
	_check(tab.current_area() == "mesto", "tablet pozná, že hráč je ve Městě")
	var shown_here := 0
	var shown_other := 0
	for cid in ContractManager.order:
		if tab._shown_here(cid, "mesto"):
			if Tablet.contract_area(cid) == "mesto":
				shown_here += 1
			elif not ContractManager.state.get(cid, "available") in ["active", "paused"]:
				shown_other += 1
	_check(shown_here > 0 and shown_other == 0, "ve Městě tablet ukazuje jen městské zakázky (%d), z jiných oblastí jen rozpracované" % shown_here)
	tab._all_areas = true
	_check(tab._shown_here("novak_bungalow", "mesto"), "tlačítko Všechny oblasti ukáže i zakázky odjinud")
	tab._all_areas = false
	ui.open_tablet()
	await _frames(3)
	ui.close_all()
	await _frames(2)
	ContractManager.pause_active()
	# --- všechny příběhové zakázky města jdou dokončit
	var markers: WindowMarkers = main.get_node("WindowMarkers")
	GameState.level = 12
	for cid in ["me_od_vylohy", "me_od_patra", "me_cinzak_ulice", "me_hotel_nizsi", "me_hotel_vyssi", "me_meridian_nizsi", "me_meridian_vyssi"]:
		ContractManager.accept(cid)
		await _frames(2)
		var c := ContractManager.get_contract(cid)
		var p0 := ContractManager.progress(cid)
		_check(ContractManager.active_id == cid and markers.remaining().size() == p0.y - p0.x, "%s: přijata, značky u %d zbývajících oken" % [cid, p0.y - p0.x])
		for wid in c.window_ids:
			var w := WindowRegistry.find_window(wid)
			if not w.completed:
				w.activate()
				w._complete()
		await _frames(3)
		var p := ContractManager.progress(cid)
		_check(ContractManager.state.get(cid) == "completed" and p.x == p.y, "%s: po umytí všech oken je hotová (%d / %d)" % [cid, p.x, p.y])
	# --- talent Městské kontakty
	var base := ContractManager.reward_money("me_od_vylohy")
	GameState.talent_points += 3
	Talents.unlock("dobry_vyjednavac")
	var base2 := ContractManager.reward_money("me_od_vylohy")
	Talents.unlock("spokojeni_zakaznici")
	Talents.unlock("mestske_kontakty")
	var city_r := ContractManager.reward_money("me_od_vylohy")
	_check(city_r > base2 * 1.1 and ContractManager.reward_money("novak_bungalow") > 0, "Městské kontakty: městské zakázky platí víc (%d -> %d, bez talentu %d)" % [base2, city_r, base])
	_check(Talents.talents["dobry_zamestnavatel"].display_name == "Servisní smlouva" and Talents.talents["dobry_zamestnavatel"].effect == "robot_price", "zaměstnance nahradila Servisní smlouva pro roboty")
	await _etapa4_tools(player)
	GameState.level = lvl_keep
	GameState.inventory = keep_inv
	GameState.refill_tank()
	world.travel("venkov", player)
	await _frames(3)


## Nové nástroje Etapy 4: elektrický stěrač s nádržkou a skládací mop.
func _etapa4_tools(player: Player) -> void:
	var world: Countryside = main.world
	world.travel("venkov", player)
	await _frames(3)
	var w := WindowRegistry.find_window("novak_w1_obyvak")
	w.reset_state()
	ContractManager.reset()
	ContractManager.accept("novak_bungalow")
	await _frames(2)
	w.activate()
	# elektrický stěrač: dávkuje sám, nádržka ubývá a doplní se u vody
	GameState.add_item("washer_electric")
	GameState.set_active("washer_electric")
	player.hold("washer_electric")
	GameState.refill_tank()
	var tank0 := GameState.tank
	_check(is_equal_approx(GameState.washer, GameState.washer_max()) and GameState.washer > 0.0, "nádržka stěrače je po doplnění plná (%.0f s)" % GameState.washer)
	_stand_before(player, w, 0.9, 0.7)
	await _frames(10)
	player.begin_cleaning(w, w.plane_to_world(Vector2(0.9, 0.6)))
	await _frames(3)
	var cc: CleaningController = player.cleaning
	_check(player.mode == Player.Mode.CLEANING and cc.tool.id == "washer_electric", "mytí elektrickým stěračem")
	var cl0 := w.cleanliness()
	var ws0 := GameState.washer
	cc.debug_press = true
	for i in 90:
		cc.on_mouse_motion(Vector2(14 if (i / 15) % 2 == 0 else -14, 3 if (i / 15) % 2 == 0 else -3))
		await _frames(1)
	cc.debug_press = false
	_check(GameState.washer < ws0 - 0.5, "stěrač při jízdě spotřebovává svou nádržku (%.1f -> %.1f s)" % [ws0, GameState.washer])
	_check(is_equal_approx(GameState.tank, tank0), "rozprašovač [F] přitom zůstal plný")
	_check(w.cleanliness() > cl0 + 0.01, "elektrický stěrač myje bez stříkání (%.3f -> %.3f za 1,5 s tahů)" % [cl0, w.cleanliness()])
	GameState.washer = 0.0
	cc.debug_press = true
	for i in 30:
		cc.on_mouse_motion(Vector2(14 if (i / 15) % 2 == 0 else -14, 0))
		await _frames(1)
	cc.debug_press = false
	_check(GameState.washer == 0.0, "prázdná nádržka stěrače nejde do minusu")
	player.end_cleaning()
	cc.rinse()
	_check(GameState.washer > 80.0, "u vody se nádržka stěrače doplní (%.0f s)" % GameState.washer)
	# skládací mop: dosah jako tyč, natažený čistí slaběji
	GameState.add_item("fold_mop")
	GameState.set_active("fold_mop")
	player.hold("fold_mop")
	_check(WindowAccess.has_tele(), "skládací mop se počítá jako teleskopická tyč pro dosah")
	player.begin_cleaning(w, w.plane_to_world(Vector2(0.9, 0.6)))
	await _frames(3)
	_check(cc.tool.id == "fold_mop" and GameState.reach_bonus(cc.tool) > 1.5, "skládací mop se vysune o %.1f m výš než ruka" % GameState.reach_bonus(cc.tool))
	player.end_cleaning()
	await _frames(2)
	GameState.set_active("rag_old")
	player.hold("rag_old")
	ContractManager.reset()
	w.reset_state()


# ------------------------------------------------------------------ snímky

func _shots(player: Player) -> void:
	var ui: UIRoot = main.ui
	ui.hud.visible = true
	if OS.get_environment("CLEARVIEW_SET") == "atmo":
		await _shots_atmo(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "fb":
		await _shots_fb(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "fix2":
		await _shots_fix2(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "kik":
		await _shots_kik(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "kosm":
		await _shots_kosm(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "brush":
		await _shots_brush(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "cafe":
		await _shots_cafe(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "3":
		await _shots3(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "4":
		await _shots4(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "metro":
		await _shots_metro(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "lad":
		await _shots_lad(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "tut":
		await _shots_tut(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "base":
		await _shots_base(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "5":
		await _shots5(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "fix":
		await _shots_fix(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "kiosk":
		await _shots_kiosk(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "marks":
		await _shots_marks(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "probe":
		await _probe_behind_glass()
		return
	if OS.get_environment("CLEARVIEW_SET") == "drone":
		await _drone_probe()
		return
	if OS.get_environment("CLEARVIEW_SET") == "perf":
		await _perf_probe()
		return
	if OS.get_environment("CLEARVIEW_SET") == "8":
		await _shots8(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "9":
		await _shots9(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "7":
		await _shots7(player)
		return
	if OS.get_environment("CLEARVIEW_SET") == "plan":
		await _shots_plan(player)
		return
	# 1) pohled od garáže
	player.global_position = Vector3(-30.5, 0.02, -6.5)
	player.yaw = -PI * 0.5 + 0.25
	player.pitch = deg_to_rad(-4)
	player.reset_physics_interpolation()
	await _frames(40)
	await _shot("01_garaz_vesnice")
	# 2) bungalov z ulice
	player.global_position = Vector3(17.0, 0.02, -2.0)
	player.yaw = 0.15
	player.pitch = deg_to_rad(2)
	player.reset_physics_interpolation()
	await _frames(40)
	await _shot("02_bungalov")
	# 3) okno zblízka (špinavé)
	ContractManager.accept("novak_bungalow")
	var w := WindowRegistry.find_window("novak_w1_obyvak")
	_stand_before(player, w, 0.93, 1.3)
	await _frames(40)
	await _shot("03_spinave_okno")
	# 4) pracovní režim + tahy
	player.begin_cleaning(w, w.plane_to_world(Vector2(0.5, 0.55)))
	await _frames(30)
	player.cleaning.debug_press = true
	await _frames(3)
	for pass_i in 3:
		for i in 40:
			player.cleaning.on_mouse_motion(Vector2(10, 0))
			await _frames(1)
		for i in 4:
			player.cleaning.on_mouse_motion(Vector2(0, 6))
			await _frames(1)
		for i in 40:
			player.cleaning.on_mouse_motion(Vector2(-10, 0))
			await _frames(1)
	await _frames(10)
	print("  info: po tazích okno %.1f %% čisté, hadr %s, dosah %s..%s" % [w.cleanliness() * 100.0, player.cleaning.rag, player.cleaning.reach_min, player.cleaning.reach_max])
	await _shot("04_cisteni_tahy")
	player.cleaning.spray()
	await _frames(25)
	await _shot("05_saponat")
	player.cleaning.debug_press = false
	player.end_cleaning()
	# 5) dokončené okno
	var tool := GameState.best_tool("rag")
	var w3 := WindowRegistry.find_window("novak_w3_loznice")
	w3.activate()
	for k in 30:
		if w3.completed:
			break
		_zigzag(w3, tool)
	_stand_before(player, w3, 0.65, 2.2)
	player.pitch = deg_to_rad(8)
	await _frames(25)
	await _shot("06_ciste_okno_lesk")
	# 6) tablet
	ui.open_tablet()
	await _frames(10)
	await _shot("07_tablet")
	ui.close_all()
	# --- poptávka z vesnice
	var vo := ""
	for id in ContractManager.order:
		if ContractManager.is_offer(id):
			vo = id
			break
	if vo != "":
		ContractManager.accept(vo)
		var vw := WindowRegistry.find_window(ContractManager.get_contract(vo).window_ids[0])
		_stand_before(player, vw, vw.glass_size.x * 0.5, 2.6)
		player.pitch = deg_to_rad(4)
		await _frames(40)
		await _shot("23_poptavka_ves")
		ContractManager.pause_active()
	# --- Etapa 2
	GameState.money = 3000
	GameState.level = 3
	GameState.talent_points = 3
	for id in ["sponge", "squeegee_25", "rag_micro", "degreaser"]:
		Shop.buy(id)
	Talents.unlock("pevna_ruka")
	Talents.unlock("dobry_vyjednavac")
	ContractManager.pause_active()
	_look(player, Vector3(9.0, 0.02, -51.0), Vector3(1.0, 1.0, -44.0))
	await _frames(40)
	await _shot("10_chata")
	_look(player, Vector3(15.5, 0.02, 29.5), Vector3(9.0, 0.8, 25.0))
	await _frames(40)
	await _shot("11_sklenik")
	_look(player, Vector3(78.0, 0.02, -3.0), Vector3(88.0, 2.0, -21.0))
	await _frames(40)
	await _shot("12_statek")
	_look(player, Vector3(-70.0, 0.02, -2.0), Vector3(-74.0, 1.5, -15.0))
	await _frames(40)
	await _shot("13_obchod_naves")
	ContractManager.accept("chata_rybnik")
	var cw := WindowRegistry.find_window("chata_w1_predni")
	_stand_before(player, cw, cw.glass_size.x * 0.5, 1.1)
	await _frames(40)
	await _shot("14_blato_zblizka")
	var ow := WindowRegistry.find_window("obchod_w3_bok_l")
	_stand_before(player, ow, ow.glass_size.x * 0.5, 1.1)
	await _frames(40)
	await _shot("15_mastnota_zblizka")
	var sw := WindowRegistry.find_window("statek_w1")
	_stand_before(player, sw, sw.glass_size.x * 0.5, 1.4)
	player.pitch = deg_to_rad(18)
	await _frames(40)
	await _shot("16_silna_spina")
	# stěrka v akci
	GameState.set_active("squeegee_25")
	_stand_before(player, cw, cw.glass_size.x * 0.5, 0.7)
	await _frames(20)
	var sy := 0.08
	while sy < cw.glass_size.y:
		var sx := 0.08
		while sx < cw.glass_size.x:
			cw.spray(Vector2(sx, sy), GameState.get_tool("detergent_basic"))
			sx += 0.12
		sy += 0.12
	player.begin_cleaning(cw, cw.plane_to_world(Vector2(cw.glass_size.x * 0.35, minf(cw.glass_size.y - 0.12, 0.95))))
	await _frames(25)
	player.cleaning.debug_press = true
	await _frames(3)
	for i in 55:
		player.cleaning.on_mouse_motion(Vector2(0, 6))
		await _frames(1)
	await _frames(6)
	await _shot("17_sterka_tah")
	player.cleaning.debug_press = false
	player.end_cleaning()
	GameState.set_active("rag_old")
	await _frames(5)
	ui.open_shop()
	await _frames(10)
	await _shot("18_obchod_panel")
	ui.close_all()
	ui.open_tablet()
	ui.tablet._show("talenty")
	await _frames(10)
	await _shot("19_talenty")
	ui.tablet._show("inventar")
	await _frames(10)
	await _shot("20_inventar")
	ui.tablet._show("zakazky")
	await _frames(10)
	var sc: ScrollContainer = null
	var n: Node = ui.tablet._content.get_parent()
	while n and sc == null:
		if n is ScrollContainer:
			sc = n
		n = n.get_parent()
	if sc:
		sc.scroll_vertical = 4200
	await _frames(10)
	await _shot("21_zakazky")
	ui.close_all()
	# 7) hlavní menu
	main.world.menu_camera.current = true
	ui.show_main_menu()
	await _frames(20)
	await _shot("09_menu")


## Snímky Etapy 3 (CLEARVIEW_SET=3 jen tyto).
func _shots3(player: Player) -> void:
	var ui: UIRoot = main.ui
	var world: Countryside = main.world
	var sub: Suburb = world.suburb
	GameState.level = 7
	GameState.reputation = GameState.REP_STEPS[3]
	GameState.money = 9000
	world.travel(Suburb.AREA_ID, player)
	await _frames(10)
	# 24) ulice Předměstí od zastávky
	_look(player, Suburb.ORIGIN + Vector3(-62, 0.02, -2.0), Suburb.ORIGIN + Vector3(-20, 3.0, -8.0))
	await _frames(40)
	await _shot("24_predmesti_ulice")
	_look(player, Suburb.ORIGIN + Vector3(-30, 0.02, 1.5), Suburb.ORIGIN + Vector3(-12, 3.5, -18.0))
	await _frames(30)
	await _shot("25_vila")
	_look(player, Suburb.ORIGIN + Vector3(-58, 0.02, -1.0), Suburb.ORIGIN + Vector3(-30, 3.0, 12.0))
	await _frames(30)
	await _shot("26_kavarna_obchody")
	_look(player, Suburb.ORIGIN + Vector3(0, 0.02, -3.0), Suburb.ORIGIN + Vector3(14, 4.5, 18.0))
	await _frames(30)
	await _shot("27_skola")
	_look(player, Suburb.ORIGIN + Vector3(8, 0.02, 2.5), Suburb.ORIGIN + Vector3(22, 6.0, -15.0))
	await _frames(30)
	await _shot("28_bytovy_dum")
	# žebřík
	GameState.add_item("ladder_small")
	await _frames(2)
	var lad: Ladder = world.ladders[0]
	lad.lay_down(Suburb.ORIGIN + Suburb.LADDER_SPOT, PI * 0.5)
	player.pick_up(lad)
	var w4 := WindowRegistry.find_window("pr_maly_w4")
	_face_wall(player, w4, 1.9)
	player.pitch = deg_to_rad(8)
	await _frames(30)
	await _shot("29_zebrik_nesu")
	player._try_place()
	_look(player, w4.plane_to_world(Vector2(w4.glass_size.x * 0.5 + 2.5, 0.0), 5.0) * Vector3(1, 0, 1) + Vector3(0, 0.02, 0), lad.global_position + Vector3(0, 2.2, 0))
	await _frames(30)
	await _shot("30_zebrik_opreny")
	ContractManager.accept("pr_dum_maly")
	_face_wall(player, w4, 1.7)
	await _frames(3)
	lad.interact(player)
	player.ladder_h = lad.max_stand()
	player.pitch = deg_to_rad(-10)
	await _frames(30)
	await _shot("31_na_zebriku")
	player.begin_cleaning(w4, w4.plane_to_world(w4.glass_size * 0.5))
	await _frames(30)
	player.cleaning.debug_press = true
	for i in 50:
		player.cleaning.on_mouse_motion(Vector2(9, (2 if i % 10 < 5 else -2)))
		await _frames(1)
	player.cleaning.debug_press = false
	await _frames(10)
	await _shot("32_zebrik_myti")
	player.end_cleaning()
	player.ladder_h = 0.0
	await _frames(3)
	player.leave_ladder()
	# teleskopická tyč
	GameState.add_item("tele_squeegee")
	GameState.set_active("tele_squeegee")
	player.hold("tele_squeegee")
	var w2 := WindowRegistry.find_window("pr_maly_w2")
	_stand_before(player, w2, w2.glass_size.x * 0.5, 1.3)
	await _frames(25)
	await _shot("33_tele_v_ruce")
	for k in 6:
		w2.spray(Vector2(0.15 + k * 0.2, 0.6), GameState.get_tool("detergent_basic"))
	player.begin_cleaning(w2, w2.plane_to_world(Vector2(w2.glass_size.x * 0.5, w2.glass_size.y - 0.15)))
	await _frames(30)
	player.cleaning.debug_press = true
	for i in 40:
		player.cleaning.on_mouse_motion(Vector2(10, 0))
		await _frames(1)
	await _frames(5)
	await _shot("34_tele_myti")
	player.cleaning.debug_press = false
	player.end_cleaning()
	GameState.set_active("rag_old")
	player.hold("rag_old")
	# lano
	GameState.add_item("rope_kit")
	var a: RopeAnchor = sub.anchors[0]
	sub._teleport(player, a.roof_spot() - Suburb.ORIGIN, PI)
	player.pitch = deg_to_rad(-25)
	await _frames(30)
	await _shot("35_strecha_kotva")
	ContractManager.accept("pr_bytovy_dum")
	a.interact(player)
	var wp := WindowRegistry.find_window("pr_byty_p2_2")
	player.rope_u = a.side().dot(wp.global_position - a.global_position)
	player.rope_y = wp.global_position.y - 1.35
	player.pitch = deg_to_rad(-35)
	player.yaw += 0.5
	await _frames(30)
	await _shot("36_lano_pohled_dolu")
	player.yaw -= 0.5
	player.pitch = deg_to_rad(65)
	await _frames(20)
	await _shot("37_lano_pohled_nahoru")
	player.pitch = 0.0
	player.begin_cleaning(wp, wp.plane_to_world(wp.glass_size * 0.5))
	await _frames(30)
	player.cleaning.debug_press = true
	for i in 50:
		player.cleaning.on_mouse_motion(Vector2(-9, (2 if i % 10 < 5 else -2)))
		await _frames(1)
	player.cleaning.debug_press = false
	await _frames(10)
	await _shot("38_lano_myti")
	player.end_cleaning()
	player.rope_y = a.top_feet()
	await _frames(3)
	player._rope_exit()
	sub._teleport(player, Suburb.ARRIVE, Suburb.ARRIVE_YAW)
	await _frames(10)
	ui.open_shop()
	ui.shop._category = "Přístupové vybavení"
	ui.shop.refresh()
	await _frames(10)
	await _shot("40_obchod_vyskove")
	ui.shop._category = "Nástroje"
	ui.shop.refresh()
	var sc := _find_scroll(ui.shop._content)
	if sc:
		sc.scroll_vertical = 900
	await _frames(10)
	await _shot("41_obchod_nastroje")
	ui.close_all()
	ui.open_tablet()
	ui.tablet._show("talenty")
	await _frames(10)
	await _shot("42_talenty_etapa3")
	ui.tablet._show("zakazky")
	await _frames(10)
	await _shot("43_zakazky_predmesti")
	ui.close_all()


func _find_scroll(node: Node) -> ScrollContainer:
	var n := node.get_parent()
	while n:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


func _shots_cafe(player: Player) -> void:
	GameState.level = 7
	main.world.travel(Suburb.AREA_ID, player)
	ContractManager.accept("pr_kavarna")
	var w := WindowRegistry.find_window("pr_kavarna_w1")
	w.activate()
	var rag := GameState.get_tool("rag_micro")
	for k in 30:
		var y := 0.05 + k * 0.07
		w.scrub(Vector2(1.0, y), Vector2(w.glass_size.x - 0.05, y), rag, 1.0, 5.0)
	print("  info: kavárna w1 %.2f, střed %s" % [w.cleanliness(), w.global_position])
	_look(player, w.plane_to_world(Vector2(w.glass_size.x * 0.5, 0.0), 4.0) * Vector3(1, 0, 1) + Vector3(0, 0.02, 0), w.plane_to_world(w.glass_size * 0.5))
	await _frames(40)
	await _shot("cafe_a")
	_look(player, w.plane_to_world(Vector2(w.glass_size.x * 0.5, 0.0), 1.2) * Vector3(1, 0, 1) + Vector3(0, 0.02, 0), w.plane_to_world(w.glass_size * 0.5))
	await _frames(30)
	await _shot("cafe_b")
	var views := [
		["cafe_c", Vector3(-50, 0.02, 3.5), Vector3(-46, 1.5, 10)],
		["shops", Vector3(-16, 0.02, 2.5), Vector3(-16, 1.6, 9)],
		["house_a", Vector3(-45, 0.02, -4.0), Vector3(-45, 2.5, -11.6)],
		["villa", Vector3(-12, 0.02, -2.0), Vector3(-12, 2.5, -13.6)],
		["apt", Vector3(22, 0.02, -3.0), Vector3(22, 4.0, -12.6)],
		["school", Vector3(14, 0.02, 4.0), Vector3(14, 3.5, 14.6)],
	]
	for v in views:
		_look(player, Suburb.ORIGIN + v[1], Suburb.ORIGIN + v[2])
		await _frames(25)
		await _shot(v[0])
	var wa := WindowRegistry.find_window("pr_byty_p2_2")
	var eye := wa.plane_to_world(Vector2(wa.glass_size.x * 0.5, wa.glass_size.y * 0.5), 1.0)
	_look(player, eye - Vector3(0, 1.65, 0), wa.plane_to_world(wa.glass_size * 0.5))
	player.set_physics_process(false)
	await _frames(5)
	await _shot("apt_close")
	player.set_physics_process(true)
	main.world.travel("venkov", player)
	_look(player, Vector3(2, 0.02, -6.0), Vector3(2, 1.6, -13.5))
	await _frames(25)
	await _shot("village_house")


## Ladicí snímky dispozic: pohled z chodby a z místnosti ke dveřím (CLEARVIEW_SET=plan).
func _shots_plan(player: Player) -> void:
	GameState.level = 7
	main.ui.hud.visible = false
	player.set_physics_process(false)
	var shots := [
		["p_apt_room", "pr_byty_p1_2", 0], ["p_school_room", "pr_skola_p0_2", 0], ["p_cafe_room", "pr_kavarna_w1", 0],
		["p_villa_room", "pr_vila_w1", 0], ["p_maly_room", "pr_maly_w2", 0], ["p_apt_corr", "pr_byty_prizemi_w2", 1],
		["p_school_corr", "pr_skola_p0_2", 1], ["p_maly_corr", "pr_maly_w2", 1], ["p_village_room", "ves_h0_w1", 0], ["p_village_corr", "ves_h0_w1", 1],
	]
	for v in shots:
		var w: CleanableWindow = WindowRegistry.find_window(v[1]) if v[1] != "" else null
		if w == null:
			for id in WindowRegistry.windows:
				if str(id).begins_with("hs0") or str(id).begins_with("house0"):
					w = WindowRegistry.windows[id]
					break
		if w == null:
			print("  info: okno pro ", v[0], " nenalezeno")
			continue
		if w.global_position.x > 1000.0:
			main.world.travel(Suburb.AREA_ID, player)
		else:
			main.world.travel("venkov", player)
		await _frames(3)
		var n: Node = w
		while n and not n.has_meta("plan"):
			n = n.get_parent()
		for c in (n as Node).find_children("*", "CleanableWindow", true, false):
			c.visible = false
		var floor_y := w.plane_to_world(Vector2(0, 0)).y - 1.0
		var c := w.plane_to_world(w.glass_size * 0.5)
		var nrm := w.normal()
		if v[2] == 0:
			# z místnosti u okna směrem ke dveřím do chodby
			var p := c - nrm * 0.45
			_look(player, Vector3(p.x, floor_y, p.z), c - nrm * 5.0 + Vector3(0, -0.4, 0) + nrm.cross(Vector3.UP) * 0.8)
		else:
			# z chodby podél ní
			var plan: Array = n.get_meta("plan")
			var bxf: Transform3D = (n as Node3D).global_transform
			var lvl: Dictionary = plan[0]
			var cz := (float(lvl["corridor"][0]) + float(lvl["corridor"][1])) * 0.5
			var a := bxf * Vector3(0.0, 0.0, cz)
			var b := bxf * Vector3(10.0, 0.0, cz)
			_look(player, Vector3(a.x, floor_y, a.z), Vector3(b.x, floor_y + 1.2, b.z))
		player.global_position.y = floor_y
		await _frames(20)
		await _shot(v[0])
	player.set_physics_process(true)


## Snímky: značky zbývajících oken a nutné vybavení v tabletu (CLEARVIEW_SET=marks).
func _shots_marks(player: Player) -> void:
	var ui: UIRoot = main.ui
	GameState.level = 7
	main.world.travel(Suburb.AREA_ID, player)
	for it in ["ladder_small", "ladder_ext", "rope_kit"]:
		GameState.inventory.erase(it)
	GameState.add_item("ladder_small")
	ContractManager.accept("pr_skola")
	var w := WindowRegistry.find_window("pr_skola_p1_3")
	w.activate()
	w._complete()
	var c := w.plane_to_world(Vector2(w.glass_size.x * 0.5, 0.0), 16.0)
	_look(player, Vector3(c.x, 0.02, c.z), w.plane_to_world(w.glass_size * 0.5) + Vector3(0, 0.3, 0))
	await _frames(60)
	await _shot("m_skola_znacky")
	# vedlejší pohled zboku – značky jsou vidět i přes zeď
	var side := w.plane_to_world(Vector2(-14.0, 0.0), 10.0)
	_look(player, Vector3(side.x, 0.02, side.z), w.plane_to_world(w.glass_size * 0.5))
	await _frames(30)
	await _shot("m_skola_zboku")
	ContractManager.pause_active()
	ui.open_tablet()
	ui.tablet._show("zakazky")
	await _frames(10)
	var target: Control = null
	for l in ui.tablet._content.find_children("*", "Label", true, false):
		if (l as Label).text.contains("nedosáhneš"):
			target = l
	var sc: ScrollContainer = null
	var n: Node = ui.tablet._content.get_parent()
	while n and sc == null:
		if n is ScrollContainer:
			sc = n
		n = n.get_parent()
	if sc and target:
		await _frames(2)
		sc.ensure_control_visible(target)
		sc.scroll_vertical += 120
	await _frames(10)
	await _shot("m_tablet_nutne")
	ui.close_all()


## Snímek pobočky obchodu na Předměstí (CLEARVIEW_SET=kiosk).
func _shots_kiosk(player: Player) -> void:
	GameState.level = 7
	main.world.travel(Suburb.AREA_ID, player)
	await _frames(20)
	var k: Node3D = null
	for c in main.world.suburb.find_children("ShopKiosk*", "", true, false):
		if c is ShopKiosk:
			k = c
	_look(player, k.global_position + Vector3(-3.5, 0.02, 6.5), k.global_position + Vector3(0, 1.6, 0))
	await _frames(60)
	await _shot("k_pobocka")


## Snímky oprav z hraní Předměstí (CLEARVIEW_SET=fix): obklad vily, chodníčky, parkoviště, výlez ze střechy, schody.
func _shots_fix(player: Player) -> void:
	GameState.level = 7
	main.world.travel(Suburb.AREA_ID, player)
	await _frames(20)
	var o := Suburb.ORIGIN
	var w := WindowRegistry.find_window("pr_vila_w3")
	var c := w.plane_to_world(Vector2(w.glass_size.x * 0.5, 0.0), 7.0)
	_look(player, Vector3(c.x, 0.02, c.z), w.plane_to_world(w.glass_size * 0.5))
	await _frames(40)
	await _shot("f_vila_obklad")
	_look(player, o + Vector3(-30.0, 0.02, 0.0), o + Vector3(-16.0, 0.5, 10.0))
	await _frames(30)
	await _shot("f_chodnicky_jih")
	_look(player, o + Vector3(30.0, 0.02, 2.0), o + Vector3(40.0, 0.0, -12.0))
	await _frames(30)
	await _shot("f_parkoviste")
	var sub: Suburb = main.world.suburb
	sub._to_roof(player, Vector3(22.0, 12.4, -6.6 - 6.0 - 5.0 - 1.8), PI)
	await _frames(30)
	var rp := player.global_position
	_look(player, rp + Vector3(2.5, 0.0, 2.0), o + Vector3(22.0, rp.y + 0.5, -6.6 - 6.0 - 5.0 - 3.6))
	await _frames(30)
	await _shot("f_strecha_vylez")
	# pohled oknem dovnitř (schody, chodba) – bez fyziky, aby hráč nespadl
	player.set_physics_process(false)
	main.ui.hud.visible = false
	for wid in ["pr_dum_c_w4", "pr_dum_c_w5", "pr_dum_b_w4", "pr_dum_b_w5", "pr_byty_p1_2", "pr_dum_maly_w1"]:
		var ww := WindowRegistry.find_window(wid)
		if ww == null:
			continue
		ww.visible = false
		var cc := ww.plane_to_world(ww.glass_size * 0.5)
		var nn := ww.normal()
		var eye := cc + nn * 0.7
		_look(player, eye - Vector3(0, 1.65, 0), cc - nn * 6.0 + Vector3(0, -0.6, 0))
		await _frames(20)
		await _shot("f_okno_" + wid)
		ww.visible = true
	player.set_physics_process(true)
	main.ui.hud.visible = true


## Snímky Etapy 4 (CLEARVIEW_SET=4): město, plošina, nové nástroje, talenty.
func _shots4(player: Player) -> void:
	var ui: UIRoot = main.ui
	GameState.level = 10
	GameState.money = 20000
	main.world.travel(City.AREA_ID, player)
	await _frames(30)
	var o := City.ORIGIN
	_look(player, o + Vector3(-6.0, 0.02, -4.0), o + Vector3(-40.0, 10.0, -14.0))
	await _frames(40)
	await _shot("c4_trida_meridian")
	_look(player, o + Vector3(4.0, 0.02, 2.0), o + Vector3(30.0, 7.0, -14.0))
	await _frames(30)
	await _shot("c4_hotel")
	_look(player, o + Vector3(-8.0, 0.02, 4.0), o + Vector3(-30.0, 4.0, 16.0))
	await _frames(30)
	await _shot("c4_obchodni_dum")
	_look(player, o + Vector3(14.0, 0.02, 6.0), o + Vector3(0.0, 1.0, 22.0))
	await _frames(30)
	await _shot("c4_namesti")
	# plošina: nástup a jízda
	GameState.add_item("platform_cert")
	var pl: SuspendedPlatform = main.world.city.platforms[0]
	player.global_position = pl.roof_spot()
	await _frames(5)
	pl.interact(player)
	player.rope_u = -2.0
	player.rope_y = pl.top_feet() - 9.0
	await _frames(20)
	var fw := -pl.outward()
	player.yaw = atan2(-fw.x, -fw.z) + deg_to_rad(70.0)
	player.pitch = deg_to_rad(-40.0)
	await _frames(20)
	await _shot("c4_na_plosine")
	var w := WindowRegistry.find_window("me_meridian_p5_2")
	player.rope_y = w.plane_to_world(Vector2(0, 0)).y - 0.4
	player.rope_u = pl.side().dot(w.plane_to_world(w.glass_size * 0.5) - pl.global_position)
	await _frames(10)
	ContractManager.accept("me_meridian_vyssi")
	await _frames(3)
	w.activate()
	player.begin_cleaning(w, w.plane_to_world(w.glass_size * 0.5))
	await _frames(40)
	await _shot("c4_myti_z_plosiny")
	player.end_cleaning()
	player.rope_y = pl.top_feet()
	await _frames(3)
	player._rope_exit()
	await _frames(5)
	# pohled zvenku na koš
	player.rope_u = 0.0
	_look(player, o + Vector3(-20.0, 0.02, 6.0), o + Vector3(-34.0, 14.0, -10.0))
	pl.rig_visual(-4.0, 12.0)
	await _frames(30)
	await _shot("c4_plosina_zvenku")
	# elektrický stěrač v ruce
	GameState.add_item("washer_electric")
	GameState.set_active("washer_electric")
	player.hold("washer_electric")
	_look(player, o + Vector3(0.0, 0.02, -8.0), o + Vector3(0.0, 1.0, -20.0))
	await _frames(20)
	await _shot("c4_elektricky_sterac")
	GameState.add_item("fold_mop")
	GameState.set_active("fold_mop")
	player.hold("fold_mop")
	await _frames(20)
	await _shot("c4_skladaci_mop")
	# vesnická zastávka se dvěma jízdními řády
	main.world.travel("venkov", player)
	await _frames(10)
	_look(player, Vector3(1.5, 0.02, -1.5), Vector3(1.5, 1.6, -5.6))
	await _frames(30)
	await _shot("c4_zastavka_naves")
	# tablet: obchod a talenty
	ui.open_shop()
	await _frames(10)
	ui.shop._category = "Přístupové vybavení"
	ui.shop.refresh()
	await _frames(10)
	await _shot("c4_obchod")
	ui.shop._category = "Nástroje"
	ui.shop.refresh()
	await _frames(10)
	await _shot("c4_obchod_nastroje")
	ui.close_all()
	ui.open_tablet()
	ui.tablet._show("talenty")
	await _frames(10)
	await _shot("c4_talenty")
	ui.close_all()


## Etapa 5 – roboti na okna, nabíjecí stojany, strom Robotika, přísavné rukavice.
func _etapa5(player: Player) -> void:
	print("--- Etapa 5: roboti")
	var world: Countryside = main.world
	var ui: UIRoot = main.ui
	var fleet: RobotFleet = main.get_node("RobotFleet")
	var keep_inv := GameState.inventory.duplicate()
	var lvl_keep := GameState.level
	var rep_keep := GameState.reputation
	var ranks_keep := Talents.ranks.duplicate()
	_check(fleet != null and fleet.robots.is_empty(), "bez koupě nemá hráč žádného robota")
	# --- obchod
	var techs := Shop.catalog("Technologie")
	var ids: Array = []
	for d in techs:
		ids.append(d["id"])
	_check(ids.has("robot_mini") and ids.has("robot_pro"), "roboti Mini a Pro jsou v obchodě (Technologie)")
	GameState.level = 8
	_check(Shop.buy_problem("robot_mini").begins_with("Od úrovně"), "robot Mini chce vyšší úroveň (%s)" % Shop.buy_problem("robot_mini"))
	GameState.level = 12
	GameState.reputation = GameState.REP_STEPS[2]
	_check(Shop.buy_problem("robot_mini").begins_with("Od pověsti"), "robot Mini chce i pověst (%s)" % Shop.buy_problem("robot_mini"))
	GameState.reputation = GameState.REP_STEPS[4] + 10
	var p0 := Shop.price("robot_mini")
	Talents.ranks["vyhodny_nakup"] = 1
	Talents.ranks["dobry_zamestnavatel"] = 1
	var p1 := Shop.price("robot_mini")
	_check(p1 < p0 * 0.9, "Servisní smlouva zlevní roboty (%d -> %d Kč)" % [p0, p1])
	Talents.ranks = ranks_keep.duplicate()
	GameState.money = 50000
	var spent := GameState.money
	Shop.buy("robot_mini")
	await _frames(2)
	_check(GameState.has_item("robot_mini") and fleet.of_model("robot_mini").size() == 1, "koupený robot Mini patří do firmy (%d Kč)" % (spent - GameState.money))
	var r: WindowRobot = fleet.of_model("robot_mini")[0]
	_check(r.state == WindowRobot.State.BAG and r.battery >= 0.99 and not r.visible, "nový robot je nabitý a u hráče")
	# --- talenty Robotika
	var rob := Talents.in_branch("robotika")
	_check(rob.size() == 9 and Talents.CURRENT_STAGE >= 5 and Talents.get_talent("nabijeni_na_cestach") == null, "strom Robotika má 9 talentů (6 roboti, 3 drony), Nabíjení na cestách je zrušené")
	GameState.talent_points += 3
	_check(Talents.unlock_problem("rychle_nabijeni") == "", "první talent Robotiky jde odemknout")
	GameState.talent_points -= 3
	_check(Talents.get_talent("prisavne_rukavice").tier == 3 and Talents.get_talent("prisavne_rukavice").requires.size() == 2, "Přísavné rukavice jsou na konci stromu")
	# --- přiložení na okno
	ContractManager.accept("novak_bungalow")
	await _frames(2)
	var c := ContractManager.active()
	var w: CleanableWindow = null
	for wid in c.window_ids:
		var cw := WindowRegistry.find_window(wid)
		if not cw.completed:
			w = cw
			break
	_check(w != null, "zakázka pro robota má neumyté okno")
	player.focus_window = null
	player.focus_object = null
	_check(not fleet.place(null, Vector3.ZERO), "bez okna robota přiložit nejde")
	var w_other: CleanableWindow = null
	for id2 in WindowRegistry.windows:
		var ow: CleanableWindow = WindowRegistry.windows[id2]
		if not ContractManager.can_clean(ow.window_id) and not ow.completed:
			w_other = ow
			break
	_check(not fleet.place(w_other, w_other.global_position), "na okno mimo rozpracovanou zakázku robot nejde")
	player.focus_window = w
	player.focus_point = w.plane_to_world(w.glass_size * 0.5, 0.0)
	_check(player._focus_prompt().contains("[G] Přiložit robota"), "u okna nápověda [G] Přiložit robota")
	var dirt0 := w.mask.current_total if w.mask else 0.0
	w.activate()
	dirt0 = w.mask.current_total
	_check(player.place_robot(), "[G] přiloží robota na okno")
	_check(r.state == WindowRobot.State.WORKING and r.visible and r.window == w, "robot je na skle a pracuje")
	_check(r.global_position.distance_to(w.plane_to_world(r._p, 0.006)) < 0.01 and absf(w.to_local(r.global_position).z) < 0.05, "robot sedí na skle")
	_check(not fleet.place(w, player.focus_point), "druhý robot na stejné okno nejde")
	var t := 0.0
	var bat0 := r.battery
	while t < 400.0 and r.state == WindowRobot.State.WORKING:
		r._process(0.1)
		t += 0.1
	print("  info: robot Mini – okno %.2f x %.2f m, stav %d za %.0f s, baterie %.2f, čistota %.3f" % [w.glass_size.x, w.glass_size.y, r.state, t, r.battery, w.cleanliness()])
	_check(w.mask.current_total < dirt0 * 0.5 or w.completed, "robot okno opravdu myje (špína %.0f -> %.0f)" % [dirt0, w.mask.current_total if not w.completed else 0.0])
	_check(r.battery < bat0, "práce vybíjí baterii (%.2f -> %.2f)" % [bat0, r.battery])
	_check(r.state != WindowRobot.State.WORKING, "robot práci ukončí (stav %d)" % r.state)
	if r.state == WindowRobot.State.DONE:
		_check(w.completed and int(GameState.stats.get("robot_windows", 0)) >= 1, "robot dokončil okno a započítá se do statistik")
	# vybitý robot
	r.interact(player)
	_check(r.state == WindowRobot.State.BAG and not r.visible and r.collision_layer == 0, "[E] na robota ho sundá k hráči")
	var w2: CleanableWindow = null
	for wid in c.window_ids:
		var cw := WindowRegistry.find_window(wid)
		if not cw.completed and cw != w:
			w2 = cw
			break
	if w2:
		r.battery = 0.03
		_check(not fleet.place(w2, w2.global_position), "vybitého robota nejde přiložit")
		r.battery = 0.08
		fleet.place(w2, w2.plane_to_world(w2.glass_size * 0.5))
		var t2 := 0.0
		while t2 < 60.0 and r.state == WindowRobot.State.WORKING:
			r._process(0.1)
			t2 += 0.1
		_check(r.state == WindowRobot.State.EMPTY and r.battery <= 0.0, "když dojde baterie, robot se zastaví a čeká na skle")
		# přerušená zakázka – robot čeká
		r.battery = 0.6
		r.state = WindowRobot.State.WORKING
		ContractManager.pause_active()
		var d2 := w2.mask.current_total
		for k in 20:
			r._process(0.1)
		_check(absf(w2.mask.current_total - d2) < 0.001 and r.state_text().contains("přerušená"), "u přerušené zakázky robot nemyje a čeká")
		ContractManager.accept("novak_bungalow")
		r.interact(player)
	# --- nabíjecí stojan
	var ch: RobotCharger = fleet.find_charger("zakladna")
	_check(ch != null and ch.global_position.distance_to(Vector3(-34, 0, -14)) < 5.0, "nabíjecí stojan je v garáži na základně")
	var kiosks := get_tree().get_nodes_in_group("robot_charger")
	_check(kiosks.size() >= 3, "stojany jsou i u poboček obchodu (%d celkem)" % kiosks.size())
	r.battery = 0.1
	_check(ch.get_prompt(player).contains("Dát roboty nabíjet"), "stojan nabízí nabíjení robotů")
	ch.interact(player)
	_check(r.state == WindowRobot.State.CHARGING and r.visible and r.global_position.distance_to(ch.global_position) < 1.5, "robot je ve stojanu a nabíjí se")
	for k in 30:
		r._process(1.0)
	var mid := r.battery
	for k in 60:
		r._process(1.0)
	_check(mid > 0.3 and mid < 1.0 and r.battery >= 1.0, "nabíjení trvá chvíli a skončí na 100 %% (%.2f po 30 s)" % mid)
	Talents.ranks["rychle_nabijeni"] = 2
	_check(r.charge_time() < 35.0, "Rychlé nabíjení zkrátí nabíjení (%.0f s)" % r.charge_time())
	Talents.ranks["vetsi_baterie"] = 2
	_check(r.work_time() > 120.0, "Větší baterie prodlouží práci (%.0f s)" % r.work_time())
	_check(ch.get_prompt(player).contains("Vzít roboty"), "nabitého robota jde ze stojanu vzít")
	ch.interact(player)
	_check(r.state == WindowRobot.State.BAG, "robot je zase u hráče")
	# --- přivolání a nabíjení na cestách
	if w2 and not w2.completed:
		fleet.place(w2, w2.plane_to_world(w2.glass_size * 0.5))
	_check(fleet.recall_all() == 0, "bez talentu se roboti přivolat nedají")
	Talents.ranks["dalkove_privolani"] = 1
	_check(fleet.recall_all() >= 0 and r.state == WindowRobot.State.BAG, "Dálkové přivolání vrátí roboty k hráči")
	r.battery = 0.2
	Events.area_changed.emit("venkov")
	_check(r.battery < 0.3, "robot se cestou autobusem nenabije")
	_check(Talents.get_talent("turbo_rezim").requires.has("vetsi_baterie"), "Turbo režim navazuje na Větší baterii")
	# --- Pro a dva roboti najednou
	GameState.add_item("robot_pro")
	await _frames(2)
	var rp: WindowRobot = fleet.of_model("robot_pro")[0]
	_check(rp != null and rp.work_time() > r.work_time() and rp.speed() > r.speed(), "robot Pro je rychlejší a vydrží déle")
	# --- tablet Roboti
	ui.open_tablet()
	ui.tablet._show("roboti")
	await _frames(3)
	var found := false
	for n in ui.tablet._content.find_children("*", "Label", true, false):
		if (n as Label).text.contains("Robot Pro"):
			found = true
	_check(found, "tablet ukazuje roboty a jejich stav")
	ui.close_all()
	await _frames(2)
	# --- ukládání robotů
	if w2 and not w2.completed:
		r.start_on(w2, w2.glass_size * 0.5)
	rp.battery = 0.4
	rp.put_on_charger("zakladna", 1, ch.slot_transform(1))
	var saved := fleet.save_state()
	r.put_in_bag()
	rp.put_in_bag()
	fleet.load_state(JSON.parse_string(JSON.stringify(saved)))
	_check(rp.state == WindowRobot.State.CHARGING and absf(rp.battery - 0.4) < 0.01, "uložení: robot ve stojanu zůstane ve stojanu")
	if w2 and not w2.completed:
		_check(r.state == WindowRobot.State.WORKING and r.window == w2, "uložení: robot na skle pokračuje na stejném okně")
	var mig := SaveManager._migrate({"version": 4, "state": {"level": 9, "stats": {}}, "persist": {}})
	_check(int(mig["version"]) == SaveManager.SAVE_VERSION and mig["persist"].has("robots") and mig["state"]["stats"].has("robot_windows"), "migrace uložení v4 -> v5 (-> v6)")
	# --- přísavné rukavice
	ContractManager.pause_active()
	r.put_in_bag()
	rp.put_in_bag()
	_look(player, Vector3(-38.3, 0.02, -16.4), Vector3(-37.0, 0.9, -16.4))
	await _frames(3)
	_check(not player.try_climb() or player.anchor == null or not Talents.has_effect("wall_climb"), "bez talentu se po zdi lézt nedá")
	if player.anchor:
		player._rope_exit()
	player.focus_object = null
	player.focus_window = null
	Talents.ranks["prisavne_rukavice"] = 1
	_look(player, Vector3(-38.3, 0.02, -16.4), Vector3(-37.0, 0.9, -16.4))
	await _frames(3)
	var climbed := player.try_climb()
	_check(climbed and player.mode == Player.Mode.ROPE and player.anchor is ClimbGrip, "s Přísavnými rukavicemi se hráč chytí zdi garáže")
	if climbed:
		var g := player.anchor as ClimbGrip
		_check(player.rope_y < 0.5 and g.roof_y > 2.5, "leze se odspodu, střecha je ve výšce %.1f m" % g.roof_y)
		player.rope_y = 1.5
		await _frames(2)
		player._rope_exit()
		_check(player.mode == Player.Mode.ROPE, "uprostřed zdi se pustit nejde (bezpečnost)")
		player.rope_y = g.top_feet()
		await _frames(2)
		player._rope_exit()
		await _frames(3)
		_check(player.mode == Player.Mode.WALK and player.global_position.y > 2.4, "nahoře hráč vyleze na střechu (y %.1f)" % player.global_position.y)
	# --- až 4 roboti a výměna za lepší model
	if player.anchor:
		player._rope_exit()
	GameState.money = 100000
	_check(GameState.robot_count() == 2, "firma má zatím 2 roboty")
	_check(Shop.buy_problem("robot_mini") == "", "dalšího Mini jde koupit znovu")
	Shop.buy("robot_mini")
	Shop.buy("robot_mini")
	await _frames(2)
	_check(GameState.robot_count() == 4 and fleet.robots.size() == 4 and fleet.of_model("robot_mini").size() == 3, "firma má 4 roboty (3× Mini, 1× Pro)")
	_check(fleet.of_model("robot_mini")[2].display_name() == "Robot Mini 3", "stejné modely se číslují (%s)" % fleet.of_model("robot_mini")[2].display_name())
	_check(Shop.buy_problem("robot_mini").begins_with("Máš 4"), "pátý robot už nejde (%s)" % Shop.buy_problem("robot_mini"))
	var bag4 := fleet.in_bag().size()
	_check(bag4 == 4, "všichni 4 roboti můžou být u hráče (%d)" % bag4)
	var ch4: RobotCharger = fleet.find_charger("zakladna")
	ch4.interact(player)
	_check(fleet.on_charger(ch4).size() == 4, "stojan pojme 4 roboty")
	var xs := {}
	for rr in fleet.on_charger(ch4):
		xs[snappedf(ch4.to_local(rr.global_position).x, 0.01)] = true
	_check(xs.size() == 4, "každý robot má ve stojanu své místo")
	ch4.interact(player)
	GameState.level = 13
	var money_before := GameState.money
	var idx := Shop.weakest_below("robot_max")
	var cost := Shop.upgrade_cost(idx, "robot_max")
	_check(Shop.upgrade_problem("robot_max") == "" and cost == Shop.price("robot_max") - Shop.trade_in("robot_mini"), "výměna Mini za Max: doplatek %d Kč (cena minus půlka ceny Mini)" % cost)
	Shop.upgrade_robot("robot_max")
	await _frames(2)
	_check(GameState.robot_count() == 4 and GameState.robot_count("robot_max") == 1 and GameState.robot_count("robot_mini") == 2 and money_before - GameState.money == cost, "Mini nahrazen robotem Max, počet zůstal 4")
	var rmax: WindowRobot = fleet.of_model("robot_max")[0]
	_check(rmax.state == WindowRobot.State.BAG and rmax.battery >= 0.99 and rmax.work_time() > rp.work_time(), "nový Max je nabitý u hráče a vydrží nejdéle")
	Shop.upgrade_robot("robot_max")
	Shop.upgrade_robot("robot_max")
	await _frames(2)
	_check(GameState.robot_count("robot_mini") == 0 and not GameState.has_item("robot_mini") and GameState.robot_count("robot_max") == 3, "po výměně všech Mini zmizí Mini z inventáře")
	_check(Shop.upgrade_problem("robot_pro") != "", "Max nejde „vyměnit“ za horší Pro")
	var st6 := GameState.to_dict()
	var fl6 = JSON.parse_string(JSON.stringify(fleet.save_state()))
	GameState.from_dict(JSON.parse_string(JSON.stringify(st6)))
	fleet.load_state(fl6)
	await _frames(2)
	_check(GameState.robot_count() == 4 and fleet.robots.size() == 4 and fleet.of_model("robot_max").size() == 3, "uložení a načtení zachová 4 roboty")
	var mig6 := SaveManager._migrate({"version": 5, "state": {"level": 12, "inventory": ["rag_old", "robot_mini", "robot_pro"], "stats": {}}, "persist": {"robots": {"robot_pro": {"state": 5, "battery": 0.5, "charger": "zakladna", "slot": 1}}}})
	_check((mig6["state"]["robot_units"] as Array).size() == 2 and mig6["persist"]["robots"] is Array and float(mig6["persist"]["robots"][1]["battery"]) == 0.5, "migrace v5 -> v6: roboti ze starého uložení zůstanou")
	# úklid
	Talents.ranks = ranks_keep.duplicate()
	GameState.inventory = keep_inv
	GameState.robot_units.clear()
	Events.inventory_changed.emit()
	await _frames(2)
	_check(fleet.robots.is_empty(), "po odebrání z inventáře robot zmizí (nová hra)")
	GameState.level = lvl_keep
	GameState.reputation = rep_keep
	world.travel("venkov", player)
	await _frames(3)


## Snímky Etapy 5 (CLEARVIEW_SET=5): plošina dole, tablet podle oblasti, roboti, stojany, strom.
## Snímky Velkoměsta a dronů (CLEARVIEW_SET=metro).
func _shots_metro(player: Player) -> void:
	var ui: UIRoot = main.ui
	var world: Countryside = main.world
	GameState.level = 17
	GameState.reputation = GameState.REP_STEPS[4] + 10
	GameState.money = 300000
	GameState.talent_points = 8
	GameState.add_item("platform_cert")
	world.travel(Metropolis.AREA_ID, player)
	await _frames(20)
	var O := Metropolis.ORIGIN
	_look(player, O + Vector3(-70.0, 0.1, 3.0), O + Vector3(0.0, 30.0, -6.0))
	await _frames(30)
	await _shot("vm_bulvar")
	_look(player, O + Vector3(4.0, 0.1, -4.0), O + Vector3(8.0, 1.6, -13.2))
	await _frames(20)
	await _shot("vm_obchod_pobocka")
	_look(player, O + Vector3(60.0, 0.1, 44.0), O + Vector3(36.0, 22.0, 19.4))
	await _frames(20)
	await _shot("vm_panorama_dokola")
	_look(player, O + Vector3(20.0, 0.1, 9.0), O + Vector3(34.0, 70.0, -20.0))
	await _frames(20)
	await _shot("vm_horizont_tower")
	_look(player, O + Vector3(-60.0, 0.1, 6.0), O + Vector3(-38.0, 8.0, 14.0))
	await _frames(20)
	await _shot("vm_oc")
	Shop.buy("drone_depot")
	Shop.buy("drone_vazka")
	Shop.buy("drone_albatros")
	Shop.buy("drone_sokol")
	await _frames(5)
	var depot := DroneDepot.get_depot(world)
	_look(player, depot.global_position + Vector3(4.0, 0.1, -7.0), depot.global_position + Vector3(0, 0.6, 0))
	await _frames(20)
	await _shot("vm_depo")
	# dron u výlohy v přízemí (zblízka)
	ContractManager.accept("vm_oc_vylohy")
	depot._think = 0.0
	depot._process(0.1)
	var dr: WindowDrone = depot.drones[0]
	for k in 600:
		for d in depot.drones:
			d._process(0.1)
		if dr.state == WindowDrone.State.CLEANING:
			break
	for k in 120:
		for d in depot.drones:
			d._process(0.05)
	if dr.window:
		var w := dr.window
		var c := w.plane_to_world(w.glass_size * 0.5)
		_look(player, c + w.normal() * 4.5 + w.global_basis.x * 2.5 + Vector3(0, -c.y + 0.1, 0), dr.global_position)
		await _frames(20)
		await _shot("vm_dron_vyloha")
	ContractManager.pause_active()
	for d in depot.drones:
		d.dock()
	# drony vysoko na Rezidenci Panorama
	ContractManager.accept("vm_panorama_vyssi")
	depot._think = 0.0
	depot._process(0.1)
	for k in 900:
		for d in depot.drones:
			d._process(0.1)
		depot._think = 0.0
		depot._process(0.1)
	var pw := WindowRegistry.find_window("vm_panorama_p12_2")
	_look(player, O + Vector3(26.0, 0.1, 8.5), pw.global_position + Vector3(0, -2.0, 0))
	await _frames(20)
	await _shot("vm_drony_panorama")
	# z plošiny na Horizont Tower nahoře
	ContractManager.pause_active()
	var pl: SuspendedPlatform = null
	for p2 in main.world.metropolis.platforms:
		if p2.anchor_id == "vm_horizont":
			pl = p2
	pl.rig_visual(-6.0, pl.top_feet() - 8.0)
	var bp := pl._basket.global_position
	player.set_physics_process(false)  # kamera „visí“ ve vzduchu před fasádou
	_look(player, bp + pl.outward() * 13.0 + pl.side() * 5.0 + Vector3.UP * 2.0, bp + Vector3.UP * 0.6)
	await _frames(20)
	await _shot("vm_horizont_strecha")
	player.set_physics_process(true)
	ui.open_tablet()
	ui.tablet._show("drony")
	await _frames(10)
	await _shot("vm_tablet_drony")
	ui.tablet._show("talenty")
	await _frames(10)
	await _shot("vm_talenty")
	ui.close_all()
	ui.open_shop()
	ui.shop._category = "Technologie"
	ui.shop.refresh()
	await _frames(10)
	await _shot("vm_obchod")
	ui.close_all()


## Snímky žebříků po cestě (CLEARVIEW_SET=lad).
func _shots_lad(player: Player) -> void:
	GameState.level = 12
	GameState.add_item("ladder_small")
	GameState.add_item("ladder_ext")
	await _frames(5)
	for area in [Suburb.AREA_ID, City.AREA_ID]:
		main.world.travel(area, player)
		await _frames(20)
		var l: Ladder = main.world.ladders[0]
		var space := player.get_world_3d().direct_space_state
		var p := l.global_position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 5, 0), p + Vector3(0, -5, 0)))
		print("DBG ladder ", area, " pos ", p, " ground ", hit.get("position", "none"), " col ", hit.get("collider", null))
		_look(player, p + Vector3(3.0, 0.02, 3.0), p + Vector3(-1.0, 0.0, 0.0))
		await _frames(20)
		await _shot("lad_" + area)
	GameState.add_item("company_van")
	await _frames(5)
	var base: CompanyBase = get_tree().get_first_node_in_group("company_base")
	for dest in ["mesto", "predmesti", "zakladna"]:
		main.world.van_travel(dest, player)
		await _frames(20)
		var vp := base.van_position()
		_look(player, vp + Vector3(5.0, 1.5, 6.0), vp + Vector3(0, 1.6, 0))
		await _frames(20)
		await _shot("lad_van_" + dest)


## Snímky firemní základny (CLEARVIEW_SET=base).
func _shots_base(player: Player) -> void:
	var ui: UIRoot = main.ui
	GameState.level = 12
	GameState.reputation = GameState.REP_STEPS[4] + 10
	GameState.money = 80000
	await _frames(10)
	_look(player, Vector3(-30.0, 0.02, -2.0), Vector3(-42.0, 1.5, -12.0))
	await _frames(30)
	await _shot("cb_zakladna_pred")
	GameState.add_item("company_van")
	GameState.add_item("base_workshop")
	GameState.add_item("base_hall")
	await _frames(10)
	_look(player, Vector3(-30.0, 0.02, -2.0), Vector3(-42.0, 1.5, -12.0))
	await _frames(30)
	await _shot("cb_zakladna_po")
	_look(player, CompanyBase.VAN_POS + Vector3(4.0, 0.02, 4.5), CompanyBase.VAN_POS + Vector3(0, 1.1, 0))
	await _frames(20)
	await _shot("cb_dodavka")
	var vanq: Node3D = main.world.get_node("CompanyVan")
	var rear := vanq.global_transform * Vector3(1.4, 0.02, -4.4)
	_look(player, rear, vanq.global_transform * Vector3(0, 1.0, -2.6))
	await _frames(20)
	await _shot("cb_dodavka_stojan")
	_look(player, CompanyBase.HALL_POS + Vector3(-0.8, 0.02, 9.0), CompanyBase.HALL_POS + Vector3(-0.8, 1.6, 0))
	await _frames(20)
	await _shot("cb_hala_venku")
	_look(player, CompanyBase.HALL_POS + Vector3(-0.8, 0.12, 2.6), CompanyBase.HALL_POS + Vector3(0.6, 1.4, -3.3))
	await _frames(20)
	await _shot("cb_hala_uvnitr")
	_look(player, Vector3(-34.0, 0.14, -11.0), Vector3(-35.5, 1.2, -16.5))
	await _frames(20)
	await _shot("cb_dilna")
	ui.open_tablet()
	ui.tablet._show("firma")
	await _frames(10)
	await _shot("cb_tablet_firma")
	ui.close_all()
	ui.open_shop()
	ui.shop._category = "Firma"
	ui.shop.refresh()
	await _frames(10)
	await _shot("cb_obchod_firma")
	ui.close_all()


func _shots5(player: Player) -> void:
	var ui: UIRoot = main.ui
	var fleet: RobotFleet = main.get_node("RobotFleet")
	GameState.level = 13
	GameState.reputation = GameState.REP_STEPS[4] + 10
	GameState.money = 40000
	GameState.talent_points = 6
	GameState.add_item("platform_cert")
	main.world.travel(City.AREA_ID, player)
	await _frames(20)
	var pl: SuspendedPlatform = main.world.city.platforms[0]
	pl.rig_visual(-3.0, pl.bottom_feet())
	var bp := pl._basket.global_position
	_look(player, bp + pl.outward() * 3.2 + pl.side() * 1.5, bp + Vector3.UP * 0.9)
	await _frames(30)
	await _shot("c5_plosina_dole")
	pl.rig_visual(-3.0, pl.top_feet() - 6.0)
	_look(player, pl.roof_spot() + pl.side() * -6.0, pl._trolley.global_position + pl.outward() * 0.6)
	await _frames(30)
	await _shot("c5_plosina_navijaky")
	_look(player, pl.hang_pos(-3.0, pl.ground_y) + pl.outward() * 6.0 + Vector3(0, 0.02, 0), pl.hang_pos(-3.0, pl.top_feet() - 6.0) + Vector3.UP * 1.0)
	await _frames(20)
	await _shot("c5_plosina_zespodu")
	ui.open_tablet()
	ui.tablet._show("zakazky")
	await _frames(10)
	await _shot("c5_tablet_zakazky_mesto")
	ui.close_all()
	main.world.travel("venkov", player)
	await _frames(20)
	GameState.add_item("robot_mini")
	GameState.add_item("robot_pro")
	GameState.add_item("robot_mini")
	GameState.add_item("robot_max")
	await _frames(3)
	ContractManager.accept("novak_bungalow")
	await _frames(3)
	var c := ContractManager.active()
	var wins: Array[CleanableWindow] = []
	for wid in c.window_ids:
		var cw := WindowRegistry.find_window(wid)
		if not cw.completed and cw.glass_size.y < 2.0:
			wins.append(cw)
	if wins.size() > 0:
		var w := wins[0]
		_stand_before(player, w, w.glass_size.x * 0.5, 1.6)
		await _frames(5)
		fleet.place(w, w.plane_to_world(w.glass_size * 0.5))
		var r: WindowRobot = fleet.of_model("robot_max")[0]
		for k in 120:
			r._process(0.1)
		await _frames(5)
		player.focus_window = w
		await _frames(20)
		await _shot("c5_robot_na_okne")
		if wins.size() > 1:
			fleet.place(wins[1], wins[1].plane_to_world(wins[1].glass_size * 0.5))
			for k in 60:
				fleet.of_model("robot_mini")[0]._process(0.1)
			_stand_before(player, wins[1], -1.5, 3.5)
			await _frames(20)
			await _shot("c5_dva_roboti")
	var ch: RobotCharger = fleet.find_charger("zakladna")
	for r2 in fleet.list():
		r2.put_in_bag()
		r2.battery = 0.35
	ch.interact(player)
	_look(player, ch.global_position + ch.global_basis.z * 2.2 + Vector3(0, 0.02, 0), ch.global_position + Vector3.UP * 1.2)
	await _frames(30)
	await _shot("c5_stojan_garaz")
	ui.open_tablet()
	ui.tablet._show("roboti")
	await _frames(10)
	await _shot("c5_tablet_roboti")
	ui.tablet._show("talenty")
	await _frames(10)
	await _shot("c5_talenty")
	ui.close_all()
	ui.open_shop()
	ui.shop._category = "Technologie"
	ui.shop.refresh()
	await _frames(10)
	await _shot("c5_obchod_roboti")
	ui.close_all()
	# přísavné rukavice na zdi garáže
	Talents.ranks["prisavne_rukavice"] = 1
	_look(player, Vector3(-38.3, 0.02, -16.4), Vector3(-37.0, 0.9, -16.4))
	await _frames(5)
	player.try_climb()
	player.rope_y = 1.6
	await _frames(10)
	player.pitch = deg_to_rad(35.0)
	await _frames(20)
	await _shot("c5_prisavne_rukavice")
	# stojan u pobočky na Předměstí
	if player.anchor:
		player.rope_y = player.anchor.bottom_feet()
		await _frames(3)
		player._rope_exit()
	main.world.travel(Suburb.AREA_ID, player)
	await _frames(20)
	var kch: RobotCharger = null
	for n in get_tree().get_nodes_in_group("robot_charger"):
		if n.charger_id.begins_with("pobocka_571"):
			kch = n
	if kch:
		_look(player, kch.global_position + kch.global_basis.z * 3.0 + kch.global_basis.x * 1.5 + Vector3(0, 0.02, 0), kch.global_position + Vector3.UP * 1.2)
		await _frames(30)
		await _shot("c5_pobocka_stojan")


## Firemní dodávka a vylepšení základny (kam s penězi).

## Etapa 6 – Velkoměsto Horizont, mrakodrapy, depo a drony, talenty, turbo navijáky, uložení v7.
func _etapa6(player: Player) -> void:
	print("--- Etapa 6: Velkoměsto a drony")
	var world: Countryside = main.world
	var ui: UIRoot = main.ui
	var keep_inv := GameState.inventory.duplicate()
	var lvl_keep := GameState.level
	var rep_keep := GameState.reputation
	var money_keep := GameState.money
	var metro: Metropolis = world.metropolis
	_check(metro != null and metro.towers.size() == 4, "Velkoměsto stojí se 4 budovami (%d)" % (metro.towers.size() if metro else 0))
	# všechna okna zakázek existují
	var missing := 0
	var total := 0
	for cid in ["vm_oc_vylohy", "vm_aurora_nizsi", "vm_oc_patra", "vm_panorama_vyssi", "vm_aurora_vyssi", "vm_horizont_finale", "vm_panorama_cela"]:
		var c := ContractManager.get_contract(cid)
		_check(c != null, "zakázka %s je načtená" % cid)
		if c == null:
			continue
		for wid in c.window_ids:
			total += 1
			var w := WindowRegistry.find_window(wid)
			if w == null:
				missing += 1
			elif WorldMap.area_at(Vector2(w.global_position.x, w.global_position.z)) != Metropolis.AREA_ID:
				missing += 1
			elif WindowAccess.tier(w, true) == WindowAccess.NONE:
				missing += 1
				print("  nedosažitelné okno ", wid)
	_check(total == 300 and missing == 0, "všech %d oken zakázek Velkoměsta existuje a dá se na ně dosáhnout (chybí %d)" % [total, missing])
	var fin := WindowRegistry.find_window("vm_horizont_p27_3")
	_check(fin != null and fin.global_position.y > 90.0 and WindowAccess.tier(fin) == WindowAccess.PLATFORM, "nejvyšší okno Horizont Tower je ve %.0f m a myje se z plošiny" % (fin.global_position.y if fin else 0.0))
	# cestování
	GameState.level = 13
	_check(not world.travel(Metropolis.AREA_ID, player), "pod úrovní 14 autobus do Velkoměsta nejede")
	GameState.level = 17
	GameState.reputation = GameState.REP_STEPS[4] + 10
	GameState.money = 300000
	GameState.add_xp(0)
	_check(world.travel(Metropolis.AREA_ID, player), "autobusem do Velkoměsta")
	await _frames(3)
	_check(player.global_position.distance_to(Metropolis.ORIGIN + Metropolis.ARRIVE) < 1.0 and GameState.unlocked_areas.has(Metropolis.AREA_ID), "hráč vystoupil v Horizontu a oblast je odemčená")
	# výtah na střechu a zpět
	var lift: SimpleInteractable = null
	for n in metro.towers["horizont"].get_children():
		if n is SimpleInteractable and (n as SimpleInteractable).prompt.contains("Výtahem"):
			lift = n
	_check(lift != null, "Horizont Tower má výtah na střechu")
	if lift:
		lift.interact(player)
		await _frames(3)
		_check(player.global_position.y > 100.0, "výtah vyveze hráče na střechu (%.0f m)" % player.global_position.y)
		var pl: SuspendedPlatform = null
		for p2 in metro.platforms:
			if p2.anchor_id == "vm_horizont":
				pl = p2
		_check(pl != null and player.global_position.distance_to(pl.global_position) < 10.0, "na střeše je u hráče závěsná plošina")
		var sp0 := pl.speed()
		GameState.add_item("platform_cert")
		GameState.add_item("platform_turbo")
		_check(absf(pl.speed() / sp0 - 2.0) < 0.01, "turbo navijáky zrychlí plošinu 2×")
		world.travel(Metropolis.AREA_ID, player)
		await _frames(2)
	# obchod: drony potřebují depo
	var depot := DroneDepot.get_depot(world)
	_check(depot != null and not depot.owned() and depot.drones.is_empty(), "na náměstí je místo pro depo dronů")
	_check(Shop.buy_problem("drone_vazka").contains("Nejdřív kup"), "dron bez depa koupit nejde")
	_check(Shop.buy("drone_depot") and depot.owned(), "depo dronů jde koupit")
	_check(Shop.buy("drone_vazka"), "Dron Vážka jde koupit")
	await _frames(2)
	_check(depot.drones.size() == 1 and depot.drones[0].state == WindowDrone.State.DOCKED, "dron stojí v depu")
	var dr: WindowDrone = depot.drones[0]
	_check(dr.global_position.distance_to(depot.pad_transform(dr.pad).origin) < 0.01, "dron sedí na přistávací ploše")
	# bez zakázky dron nikam neletí
	depot._think = 0.0
	depot._process(0.1)
	_check(dr.state == WindowDrone.State.DOCKED, "bez rozpracované zakázky dron čeká")
	# zakázka v jiné oblasti – dron nikam
	ContractManager.accept("me_meridian_vyssi")
	depot._think = 0.0
	depot._process(0.1)
	_check(dr.state == WindowDrone.State.DOCKED, "na zakázku v jiném městě dron neletí")
	ContractManager.pause_active()
	# zakázka ve Velkoměstě – dron vyletí k nejvyššímu oknu
	ContractManager.accept("vm_panorama_vyssi")
	depot._think = 0.0
	depot._process(0.1)
	_check(dr.state == WindowDrone.State.OUTBOUND and dr.window != null, "dron vyletěl k oknu zakázky")
	var first := dr.window
	var top := true
	if first:
		for wid in ContractManager.active().window_ids:
			if WindowRegistry.find_window(wid).global_position.y > first.global_position.y + 0.01:
				top = false
	_check(top, "dron bere nejdřív nejvyšší okna")
	var max_y := 0.0
	var steps := 0
	while dr.state == WindowDrone.State.OUTBOUND and steps < 600:
		dr._process(0.1)
		max_y = maxf(max_y, dr.global_position.y)
		steps += 1
	_check(dr.state == WindowDrone.State.CLEANING, "dron doletěl k oknu a myje (%.0f s letu)" % (steps * 0.1))
	_check(dr.global_position.distance_to(first.plane_to_world(first.glass_size * 0.5, WindowDrone.HOVER)) < 3.0, "dron visí před oknem")
	for k in 5:
		dr._process(0.1)
	var gap_d := (dr.global_position - first.global_position).dot(first.normal())
	_check(gap_d > 0.95, "dron visí dál od fasády, vrtule nezasahují do říms (%.2f m)" % gap_d)
	_check(dr.state != WindowDrone.State.CLEANING or dr.spraying(), "dron při mytí stříká vodu na okno (efekt)")
	var done_before := ContractManager.progress("vm_panorama_vyssi").x
	steps = 0
	while not first.completed and steps < 4000 and dr.state == WindowDrone.State.CLEANING:
		dr._process(0.1)
		steps += 1
	_check(first.completed, "dron umyl okno sám (%.0f s, baterie %d %%)" % [steps * 0.1, int(dr.battery * 100.0)])
	_check(ContractManager.progress("vm_panorama_vyssi").x == done_before + 1, "okno umyté dronem se počítá do zakázky")
	_check(int(GameState.stats.get("drone_windows", 0)) >= 1, "statistika oken umytých drony")
	# po okně rovnou další
	_check(dr.state == WindowDrone.State.OUTBOUND and dr.window != first, "po umytí letí dron rovnou k dalšímu oknu")
	# vybitá baterie: návrat do depa a nabíjení
	dr.battery = 0.03
	steps = 0
	while dr.state != WindowDrone.State.DOCKED and steps < 2000:
		if dr.state == WindowDrone.State.CLEANING:
			dr._process(0.1)
		else:
			dr._process(0.1)
		steps += 1
	_check(dr.state == WindowDrone.State.DOCKED, "dron s vybitou baterií se vrátil do depa")
	var b0 := dr.battery
	dr._process(5.0)
	_check(dr.battery > b0, "dron se v depu nabíjí")
	depot._think = 0.0
	depot._process(0.1)
	_check(dr.state == WindowDrone.State.DOCKED, "napůl nabitý dron ještě čeká")
	dr.battery = 1.0
	depot._think = 0.0
	depot._process(0.1)
	_check(dr.state == WindowDrone.State.OUTBOUND, "nabitý dron sám pokračuje")
	# autopilot vypnout = domů
	depot.set_autopilot(false)
	_check(dr.state == WindowDrone.State.RETURNING, "vypnutý autopilot pošle drony domů")
	steps = 0
	while dr.state != WindowDrone.State.DOCKED and steps < 2000:
		dr._process(0.1)
		steps += 1
	depot._think = 0.0
	depot._process(0.1)
	_check(dr.state == WindowDrone.State.DOCKED, "bez autopilota dron zůstane v depu")
	depot.set_autopilot(true)
	# talenty dronů
	var f0 := dr.fly_speed()
	var w0 := dr.work_time()
	Talents.ranks["rychle_vrtule"] = 2
	Talents.ranks["vydrzne_baterie"] = 1
	_check(absf(dr.fly_speed() / f0 - 1.5) < 0.01 and absf(dr.work_time() / w0 - 1.3) < 0.01, "talenty Rychlé vrtule a Výdržné baterie platí")
	Talents.ranks.erase("rychle_vrtule")
	Talents.ranks.erase("vydrzne_baterie")
	# víc dronů nesahá na stejné okno
	Shop.buy("drone_albatros")
	await _frames(2)
	_check(depot.drones.size() == 2, "druhý dron přibyl do depa")
	depot._think = 0.0
	depot._process(0.1)
	var same := depot.drones.size() == 2 and depot.drones[0].window != null and depot.drones[0].window == depot.drones[1].window
	_check(not same and depot.working_count() == 2, "dva drony letí každý k jinému oknu")
	# tablet
	ui.open_tablet_section("drony")
	await _frames(3)
	var txt := ""
	for n in ui.tablet._content.find_children("*", "Label", true, false):
		txt += (n as Label).text + " "
	_check(txt.contains("Dron Vážka") and txt.contains("Dron Albatros") and txt.contains("autopilot"), "tablet ukazuje drony a autopilot")
	ui.close_all()
	await _frames(2)
	# uložení
	var sd := depot.save_state()
	depot.drones[0].battery = 0.2
	depot.load_state(sd)
	_check(depot.drones.size() == 2 and depot.drones[0].state == WindowDrone.State.DOCKED and depot.autopilot, "stav depa se uloží a načte (drony v depu)")
	_check(not depot.drones[0].spraying(), "dron v depu nestříká")
	# výměna dronu za lepší a prodej
	var m0 := GameState.money
	var upc := Shop.drone_upgrade_cost("drone_vazka", "drone_sokol")
	_check(Shop.weakest_drone_below("drone_sokol") == "drone_vazka" and Shop.drone_upgrade_problem("drone_sokol") == "", "Vážku jde v obchodě vyměnit za Sokola (%s)" % Shop.drone_upgrade_problem("drone_sokol"))
	_check(Shop.upgrade_drone("drone_sokol") and GameState.has_item("drone_sokol") and not GameState.has_item("drone_vazka") and GameState.money == m0 - upc and upc == Shop.price("drone_sokol") - Shop.trade_in("drone_vazka"), "výměna: Vážka pryč, Sokol v depu, doplatek po odečtení poloviny ceny Vážky")
	await _frames(2)
	var models: Array[String] = []
	for d in depot.drones:
		models.append(d.item_id)
	_check(depot.drones.size() == 2 and models.has("drone_sokol") and not models.has("drone_vazka"), "v depu je místo Vážky Sokol %s" % str(models))
	_check(Shop.drone_upgrade_problem("drone_albatros") == "Už vlastníš.", "vlastněný model se znovu vyměnit nedá")
	var m1 := GameState.money
	_check(Shop.sell_drone("drone_albatros") and not GameState.has_item("drone_albatros") and GameState.money == m1 + Shop.trade_in("drone_albatros"), "dron jde prodat za polovinu ceny")
	await _frames(2)
	_check(depot.drones.size() == 1, "prodaný dron z depa zmizí")
	GameState.add_item("drone_vazka")
	GameState.add_item("drone_albatros")
	GameState.remove_item("drone_sokol")
	await _frames(2)
	# migrace v6 → v7
	var mig := SaveManager._migrate({"version": 6, "state": {"level": 15, "unlocked_areas": ["venkov", "predmesti", "mesto"], "stats": {}}, "persist": {}})
	_check(int(mig.get("version", 0)) == SaveManager.SAVE_VERSION and (mig["state"]["unlocked_areas"] as Array).has("velkomesto") and mig["state"]["stats"].has("drone_windows"), "migrace uložení v6 → v7 (Velkoměsto, statistika dronů)")
	# celá budova kolem dokola – Rezidence Panorama
	var cela := ContractManager.get_contract("vm_panorama_cela")
	var per_side := {"p": 0, "z": 0, "l": 0, "r": 0}
	var floors_set := {}
	var wrong_dir := 0
	var tw_p: Node3D = metro.towers["panorama"]
	for wid in cela.window_ids:
		var tag := wid.substr(12, 1)
		per_side[tag] = int(per_side.get(tag, 0)) + 1
		floors_set[ContractManager.floor_of(wid)] = true
		var ww := WindowRegistry.find_window(wid)
		# normála okna míří ven z budovy
		var hor := ww.global_position - tw_p.global_position if ww else Vector3.ZERO
		hor.y = 0.0
		if ww and hor.normalized().dot(ww.normal()) < 0.3:
			wrong_dir += 1
			print("  okno míří dovnitř: ", wid)
		if ww and (WindowAccess.tier(ww) == WindowAccess.NONE or (ContractManager.floor_of(wid) >= 3 and WindowAccess.tier(ww) != WindowAccess.PLATFORM)):
			wrong_dir += 1
			print("  okno bez plošiny: ", wid)
	_check(cela.window_ids.size() == 182 and per_side["p"] == 52 and per_side["z"] == 52 and per_side["l"] == 39 and per_side["r"] == 39 and floors_set.size() == 13, "zakázka Celá budova: 182 oken, 13 pater, všechny 4 strany %s" % str(per_side))
	_check(wrong_dir == 0, "všechna okna kolem dokola míří ven a myjí se z plošiny na své straně (%d chyb)" % wrong_dir)
	var side_pl := 0
	for p3 in metro.platforms:
		if p3.anchor_id.begins_with("vm_panorama"):
			side_pl += 1
	_check(side_pl == 4, "Rezidence Panorama má plošinu na každé straně (%d)" % side_pl)
	_check(ContractManager.floor_of("vm_panorama_z12_3") == 12 and ContractManager.floor_of("vm_panorama_p1_1") == 1 and ContractManager.floor_of("vm_oc_vyloha_w3") == -1, "patro se pozná z id okna")
	# trasa dronu k oknu vzadu vede nad střechou, ne skrz budovu
	var back_w := WindowRegistry.find_window("vm_panorama_z3_2")
	var rt: Array[Vector3] = depot.route(depot.pad_transform(0).origin, back_w.plane_to_world(back_w.glass_size * 0.5, WindowDrone.HOVER))
	var roof_p: float = tw_p.global_position.y + 14 * 3.2 + 0.3
	_check(rt.size() >= 4 and rt[2].y > roof_p + 1.0, "dron letí k zadnímu oknu nad střechou (%.0f m, střecha %.0f m)" % [rt[2].y if rt.size() > 2 else 0.0, roof_p])
	# přijetí: okna umytá v jiné zakázce se znovu zašpiní
	var pw_done := WindowRegistry.find_window("vm_panorama_p12_2")
	if pw_done and not pw_done.completed:
		pw_done.activate()
		pw_done._complete()
	ContractManager.accept("vm_panorama_cela")
	_check(ContractManager.progress("vm_panorama_cela").x == 0, "nová zakázka na celou budovu začíná od nuly (%d)" % ContractManager.progress("vm_panorama_cela").x)
	# bonus za patro kolem dokola
	var floor1: Array = []
	for wid in cela.window_ids:
		if ContractManager.floor_of(wid) == 1:
			floor1.append(wid)
	for i in floor1.size() - 1:
		var fw := WindowRegistry.find_window(floor1[i])
		fw.activate()
		fw._complete()
	_check(ContractManager.floor_progress(cela, 1) == Vector2i(13, 14), "1. patro: 13 ze 14 oken")
	var fl_before := int(GameState.stats.get("floors_round", 0))
	var lastw := WindowRegistry.find_window(floor1[floor1.size() - 1])
	lastw.activate()
	lastw._complete()
	_check(int(GameState.stats.get("floors_round", 0)) == fl_before + 1, "umyté patro kolem dokola dá bonus (statistika)")
	ContractManager.pause_active()
	for wid in cela.window_ids:
		var rw := WindowRegistry.find_window(wid)
		if rw:
			rw.reset_state()
	# migrace v7 → v8: zrušený talent Nabíjení na cestách vrátí bod
	var mig8 := SaveManager._migrate({"version": 7, "state": {"level": 15, "talent_points": 2, "talents": {"nabijeni_na_cestach": 1, "vetsi_baterie": 2}, "stats": {}}, "persist": {}})
	_check(int(mig8["state"]["talent_points"]) == 3 and not (mig8["state"]["talents"] as Dictionary).has("nabijeni_na_cestach") and int(mig8["state"]["talents"]["vetsi_baterie"]) == 2 and int(mig8.get("refunded_talent_points", 0)) == 1, "migrace v7 → v8: za zrušený talent se vrátí bod")
	# plošina visí dál od zdi než lano (neprojíždí parapety)
	var plg: SuspendedPlatform = main.world.metropolis.platforms[0]
	var gap := (plg.hang_pos(0.0, 10.0) - plg.global_position).dot(plg.outward())
	_check(gap > plg.wall_out + RopeAnchor.HANG_OUT + 0.4, "koš plošiny visí dál od fasády (%.2f m)" % gap)
	# pobočka obchodu ve Velkoměstě nestojí v budově
	var kq: ShopKiosk = null
	for c in main.world.metropolis.get_children():
		if c is ShopKiosk:
			kq = c
	var free_k := true
	for dz: float in [-1.0, 0.0, 1.0]:
		var qk := PhysicsRayQueryParameters3D.create(kq.global_position + Vector3(-3.0, 1.5, dz), kq.global_position + Vector3(3.0, 1.5, dz))
		var hk := player.get_world_3d().direct_space_state.intersect_ray(qk)
		if not hk.is_empty() and not kq.is_ancestor_of(hk["collider"]) and hk["collider"] != kq:
			free_k = false
	_check(free_k, "pobočka ve Velkoměstě stojí volně, ne ve zdi")
	# HUD: text vpravo dole roste doleva
	_check(main.ui.hud._equip.grow_horizontal == Control.GROW_DIRECTION_BEGIN, "text V ruce / Přípravek nepřetéká přes pravý okraj")
	# úklid
	depot.recall_all()
	for d in depot.drones:
		d.dock()
	ContractManager.pause_active()
	for cid in ["vm_panorama_vyssi"]:
		for wid in ContractManager.get_contract(cid).window_ids:
			var w := WindowRegistry.find_window(wid)
			if w:
				w.reset_state()
	ContractManager.reset()
	GameState.inventory = keep_inv
	Events.inventory_changed.emit()
	await _frames(3)
	_check(depot.drones.is_empty() and not depot.owned(), "nová hra: depo je zase prázdný pozemek")
	GameState.level = lvl_keep
	GameState.reputation = rep_keep
	GameState.money = money_keep
	world.travel("venkov", player)
	await _frames(2)

func _company_base(player: Player) -> void:
	print("--- Firma: dodávka a základna")
	var world: Countryside = main.world
	var ui: UIRoot = main.ui
	var base: CompanyBase = world.base
	var fleet: RobotFleet = main.get_node("RobotFleet")
	var keep_inv := GameState.inventory.duplicate()
	var lvl_keep := GameState.level
	var rep_keep := GameState.reputation
	var money_keep := GameState.money
	_check(base != null and not base.workshop_built() and not base.hall_built() and not base.has_van(), "základna je na začátku jen garáž")
	var ids: Array = []
	for d in Shop.catalog("Firma"):
		ids.append(d["id"])
	_check(ids.has("base_workshop") and ids.has("base_hall") and ids.has("company_van"), "v obchodě (Firma) je dílna, hala a dodávka")
	GameState.level = 12
	GameState.reputation = GameState.REP_STEPS[4] + 10
	GameState.money = 100000
	_check(Shop.buy_problem("base_hall").begins_with("Nejdřív kup"), "hala chce nejdřív dílnu (%s)" % Shop.buy_problem("base_hall"))
	# dílna
	var ch: RobotCharger = fleet.find_charger("zakladna")
	GameState.add_item("robot_mini")
	await _frames(2)
	var r: WindowRobot = fleet.robots[0]
	r.battery = 0.2
	r.put_on_charger("zakladna", 0, ch.slot_transform(0))
	var t1 := r.charge_time()
	Shop.buy("base_workshop")
	await _frames(2)
	_check(base.workshop_built() and world.get_node_or_null("Garage/Workshop") != null or base.workshop_built(), "po koupi se garáž změní v dílnu")
	_check(absf(r.charge_time() - t1 * 0.5) < 0.5 and GameState.charger_speed("zakladna") == 2.0, "rychlonabíječka v dílně nabíjí 2× (%.0f -> %.0f s)" % [t1, r.charge_time()])
	_check(ch._title.text.contains("×2"), "stojan v garáži ukazuje rychlonabíjení")
	# hala
	var rm0 := GameState.reward_multiplier()
	_check(Shop.buy_problem("base_hall") == "", "po dílně jde koupit hala")
	Shop.buy("base_hall")
	await _frames(3)
	_check(base.hall_built(), "firemní hala stojí vedle garáže")
	_check(absf(GameState.reward_multiplier() / rm0 - 1.05) < 0.001, "hala přidá k odměnám 5 %")
	var hch: RobotCharger = fleet.find_charger("hala")
	_check(hch != null and hch._title.text.contains("×3"), "v hale je stojan s rychlonabíjením 3×")
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(CompanyBase.HALL_POS + Vector3(-0.8, 1.2, 8.0), CompanyBase.HALL_POS + Vector3(-0.8, 1.2, -1.0))
	var hit := space.intersect_ray(q)
	_check(hit.is_empty() or (hit["position"] as Vector3).z < CompanyBase.HALL_POS.z + 3.0, "do haly se dá vejít velkými vraty")
	var qg := PhysicsRayQueryParameters3D.create(Vector3(-34, 1.2, -6.0), Vector3(-34, 1.2, -13.0))
	var hg := space.intersect_ray(qg)
	_check(hg.is_empty() or (hg["position"] as Vector3).z < -16.0, "do garáže se dá vejít vraty (žádné neviditelné sklo)")
	ui.open_tablet_section("zakazky_vse")
	await _frames(3)
	_check(ui.tablet.visible and ui.tablet._current == "zakazky" and ui.tablet._all_areas, "nástěnka v hale otevře všechny zakázky")
	ui.tablet._all_areas = false
	ui.close_all()
	await _frames(2)
	# dodávka
	var tb := world.get_node_or_null("CompanyVan")
	_check(tb == null, "dodávka bez koupě u základny nestojí")
	_check(not world.van_travel("mesto", player), "bez dodávky se jí jet nedá")
	Shop.buy("company_van")
	await _frames(2)
	_check(base.has_van(), "koupená dodávka parkuje u základny")
	r.put_in_bag()
	r.battery = 0.2
	_check(world.van_travel("mesto", player), "dodávka odveze hráče do Města")
	await _frames(3)
	_check(player.global_position.distance_to(City.ORIGIN + City.ARRIVE) < 3.0, "hráč je ve Městě")
	_check(absf(r.battery - 0.2) < 0.01, "robot u hráče se cestou dodávkou nedobije (%.2f)" % r.battery)
	# stojan na dodávce: robot jede s ní a nabíjí se
	var vch: RobotCharger = fleet.find_charger(CompanyBase.VAN_CHARGER_ID)
	_check(vch != null and vch.global_position.distance_to(world.get_node("CompanyVan").global_position) < 3.5, "dodávka má na zadních dveřích nabíjecí stojan")
	var blocked: Array[String] = []
	var spot_keep := base.van_spot
	for sp in CompanyBase.VAN_SPOTS:
		base.park_van(sp)
		var cpos := vch.global_position + Vector3.UP * 1.1
		var cout := vch.global_basis.z.normalized()
		for dx: float in [-0.7, 0.0, 0.7]:
			var o := cpos + vch.global_basis.x.normalized() * dx + cout * 0.15
			var qv := PhysicsRayQueryParameters3D.create(o, o + cout * 1.6, 1, [player.get_rid()])
			var hv := player.get_world_3d().direct_space_state.intersect_ray(qv)
			if not hv.is_empty() and not sp in blocked:
				blocked.append(sp)
	base.park_van(spot_keep)
	_check(blocked.is_empty(), "ke stojanu na dodávce je všude volný přístup %s" % str(blocked))
	vch.interact(player)
	_check(r.state == WindowRobot.State.CHARGING and r.charger_id == CompanyBase.VAN_CHARGER_ID, "robota jde dát nabíjet do dodávky")
	var vpos0 := r.global_position
	_check(world.van_travel("zakladna", player), "dodávkou s robotem ve stojanu na základnu")
	await _frames(2)
	_check(r.global_position.distance_to(vch.slot_transform(r.charger_slot).origin) < 0.05 and r.global_position.distance_to(vpos0) > 50.0, "robot ve stojanu jede s dodávkou")
	var b0v := r.battery
	r._process(2.0)
	_check(r.battery > b0v, "robot se ve stojanu na dodávce nabíjí")
	vch.interact(player)
	_check(r.state == WindowRobot.State.BAG, "robota jde z dodávky zase vzít")
	_check(world.van_travel("mesto", player), "a zpět dodávkou do Města")
	await _frames(3)
	ui.open_tablet_section("firma")
	await _frames(3)
	var btns := 0
	for n in ui.tablet._content.find_children("*", "Button", true, false):
		if (n as Button).text.contains("Základna"):
			btns += 1
	_check(btns == 1, "tablet (Firma) nabízí cestu dodávkou")
	ui.close_all()
	await _frames(2)
	_check(world.van_travel("zakladna", player), "dodávka odveze hráče na základnu")
	await _frames(3)
	_check(player.global_position.distance_to(CompanyBase.BASE_SPOT) < 1.0, "hráč stojí před garáží")
	# žebříky na střeše dodávky
	GameState.add_item("ladder_small")
	GameState.add_item("ladder_ext")
	await _frames(2)
	_check(world.van_travel("mesto", player), "dodávkou se žebříky do Města")
	await _frames(3)
	var vp := base.van_position()
	_check(vp.distance_to(City.ORIGIN + City.ARRIVE) < 9.0, "dodávka zaparkovala ve Městě kousek od hráče (%.1f m)" % vp.distance_to(City.ORIGIN + City.ARRIVE))
	_check(base.roof_ladders().size() == 2, "oba žebříky přijely na střeše dodávky (%d)" % base.roof_ladders().size())
	var door: SimpleInteractable = null
	for n in base._van.get_children():
		if n is SimpleInteractable:
			door = n
	_check(door != null and door.get_prompt(player).contains("Sundat žebřík"), "u dodávky je nabídka sundat žebřík")
	door.interact(player)
	_check(player.carried is Ladder and base.roof_ladders().size() == 1, "[E] u dodávky sundá žebřík ze střechy")
	player.focus_object = door
	_check(player.get_prompt().contains("Naložit"), "s žebříkem v ruce nabídne dodávka naložení")
	player._try_place()
	_check(player.carried == null and base.roof_ladders().size() == 2, "nesený žebřík jde naložit zpátky na střechu")
	_check(base.save_state()["van"] == "mesto", "uloží se, kde dodávka stojí")
	# autobusem: žebříky ze střechy jedou na zastávku a leží na chodníku (ne v něm)
	_check(world.travel(Suburb.AREA_ID, player), "autobusem na Předměstí")
	await _frames(2)
	_check(world.travel(City.AREA_ID, player), "autobusem zpět do Města")
	await _frames(2)
	var on_walk := true
	for l in world.ladders:
		if not l.lying or l.global_position.y < 0.1:
			on_walk = false
	_check(on_walk, "žebříky u městské zastávky leží na chodníku, ne zapadlé")
	_check(base.roof_ladders().is_empty(), "po cestě autobusem na střeše dodávky nic nezůstalo")
	_check(world.van_travel("zakladna", player), "dodávkou zpět na základnu")
	await _frames(3)
	_check(base.roof_ladders().size() == 2 and base.van_position().distance_to(CompanyBase.VAN_POS) < 0.1, "dodávka se žebříky stojí zase u základny")
	base.load_state({"van": "predmesti"})
	_check(base.van_position().distance_to(Suburb.ORIGIN) < 120.0, "načtení postaví dodávku tam, kde zůstala")
	base.load_state({"van": "zakladna"})
	await _frames(2)
	# žebřík ze starého uložení na střeše dodávky na staré pozici (o 1,6 m blíž k hale)
	var rl := base.roof_ladders()
	var vinv: Transform3D = world.get_node("CompanyVan").global_transform.affine_inverse()
	var want_z := (vinv * rl[0].global_position).z
	rl[0].lay_down(rl[0].global_position + Vector3(0, -0.04, -1.6), rl[0]._lie_yaw)
	base.load_state({"van": "zakladna"})
	await _frames(2)
	var got_z := (vinv * rl[0].global_position).z
	_check(base.roof_ladders().size() == 2 and absf(got_z - want_z) < 0.15, "žebřík ze staré pozice dodávky se po načtení srovná na střechu (%.2f vs %.2f)" % [got_z, want_z])
	# uložení
	var st := GameState.to_dict()
	GameState.from_dict(JSON.parse_string(JSON.stringify(st)))
	Events.game_loaded.emit()
	await _frames(2)
	_check(base.hall_built() and base.has_van() and base.workshop_built(), "po načtení základna i dodávka zůstanou")
	# úklid
	GameState.inventory = keep_inv
	GameState.robot_units.clear()
	Events.inventory_changed.emit()
	await _frames(3)
	_check(not base.hall_built() and not base.has_van() and not base.workshop_built(), "nová hra: základna je zase jen garáž")
	GameState.level = lvl_keep
	GameState.reputation = rep_keep
	GameState.money = money_keep


func _etapa7(_player: Player) -> void:
	print("--- Etapa 7: živé město")
	var world: Countryside = main.world
	var city_tr := world.city.get_node_or_null("Traffic") as Traffic
	var metro_tr := world.metropolis.get_node_or_null("Traffic") as Traffic
	_check(city_tr != null and metro_tr != null, "doprava jezdí v Brodci i v Horizontu")
	if city_tr == null or metro_tr == null:
		return
	var trams := city_tr.vehicles.filter(func(v): return v["kind"] == "tram")
	_check(trams.size() == 1, "v Brodci jezdí tramvaj (%d)" % trams.size())
	_check(city_tr.vehicles.size() >= 8 and metro_tr.vehicles.size() >= 10, "dost aut (%d / %d)" % [city_tr.vehicles.size(), metro_tr.vehicles.size()])
	# vozidla se hýbou (hráč daleko)
	var far := Vector3(1e6, 0, 1e6)
	var car: Dictionary = metro_tr.vehicles[0]
	car["wait"] = 0.0
	var x_before: float = car["x"]
	for o in metro_tr.vehicles:
		if o != car and o["lane"] == car["lane"]:
			o["x"] = 1e5
	car["x"] = 0.0
	x_before = 0.0
	metro_tr.step(car, 0.5, far)
	var dir: float = metro_tr.lanes[car["lane"]]["dir"]
	_check((float(car["x"]) - x_before) * dir > 1.0, "auto jede po pruhu (%.2f m)" % ((float(car["x"]) - x_before) * dir))
	# hráč v pruhu před autem → auto stojí
	var lz: float = metro_tr.lanes[car["lane"]]["z"]
	var front: float = float(car["x"]) + dir * float(car["len"]) * 0.5
	var pl := Vector3(front + dir * 3.0, 0.9, lz)
	var xs: float = car["x"]
	for k in 20:
		metro_tr.step(car, 0.1, pl)
	_check(is_equal_approx(float(car["x"]), xs), "auto před hráčem zastaví a počká")
	# hráč ustoupí → jede dál
	for k in 5:
		metro_tr.step(car, 0.1, far)
	_check((float(car["x"]) - xs) * dir > 1.0, "po uvolnění pruhu auto pokračuje")
	# auto za jiným vozidlem udrží odstup
	var lead: Dictionary = {}
	for o in metro_tr.vehicles:
		if o != car and o["lane"] == car["lane"]:
			lead = o
			break
	if not lead.is_empty():
		lead["x"] = float(car["x"]) + dir * (float(car["len"]) * 0.5 + float(lead["len"]) * 0.5 + 2.0)
		lead["wait"] = 99.0
		var xc: float = car["x"]
		metro_tr.step(car, 0.5, far)
		_check(is_equal_approx(float(car["x"]), xc), "auto nenajede do vozidla před sebou")
		lead["wait"] = 0.0
	# na konci ulice se vrátí na začátek
	var ln: Dictionary = metro_tr.lanes[car["lane"]]
	if not lead.is_empty():
		lead["x"] = 0.0
	car["x"] = float(ln["x1"]) - 0.1 if dir > 0.0 else float(ln["x0"]) + 0.1
	car["wait"] = 0.0
	metro_tr.step(car, 0.5, far)
	var start: float = float(ln["x0"]) if dir > 0.0 else float(ln["x1"])
	_check(is_equal_approx(float(car["x"]), start), "na konci ulice se auto vrátí na začátek")
	# tramvaj zastaví na zastávce
	var tram: Dictionary = trams[0]
	var tl: Dictionary = city_tr.lanes[tram["lane"]]
	var td: float = tl["dir"]
	tram["wait"] = 0.0
	tram["x"] = float(tl["stop_x"]) - td * 0.3
	city_tr.step(tram, 0.2, far)
	_check(is_equal_approx(float(tram["x"]), float(tl["stop_x"])) and float(tram["wait"]) > 1.0, "tramvaj staví na zastávce")
	tram["wait"] = 0.0
	# doprava nemá kolizi (nepřekáží hráči ani oknům)
	var bodies := 0
	for n in city_tr.find_children("*", "CollisionObject3D", true, false):
		bodies += 1
	for n in metro_tr.find_children("*", "CollisionObject3D", true, false):
		bodies += 1
	_check(bodies == 0, "vozidla nemají kolizi")
	# stará tramvaj s kolizí je pryč: střed třídy u bývalé zastávky je volný
	var space := world.city.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(world.city.to_global(Vector3(18.0, 1.5, 0.0)), world.city.to_global(Vector3(34.0, 1.5, 0.0)))
	_check(space.intersect_ray(q).is_empty(), "na tramvajovém pásu nestojí neprůchodná tramvaj")
	await _etapa7_birds_weather()


func _etapa7_birds_weather() -> void:
	print("--- Etapa 7: ptáci a počasí")
	var world: Countryside = main.world
	var birds := world.metropolis.get_node_or_null("Birds") as Birds
	_check(birds != null and birds.birds.size() >= 18, "kolem mrakodrapů krouží ptáci (%d)" % (birds.birds.size() if birds else 0))
	if birds == null:
		return
	# ptáci krouží mimo věže (ne uvnitř budov)
	var space := world.metropolis.get_world_3d().direct_space_state
	var inside := 0
	for v in birds.birds:
		var p: Vector3 = birds.to_global(birds.orbit_pos(v))
		var q := PhysicsPointQueryParameters3D.new()
		q.position = p
		if not space.intersect_point(q).is_empty():
			inside += 1
	_check(inside == 0, "žádný pták nekrouží uvnitř budovy (%d)" % inside)
	# trus na rozdělaném okně: přibude špína, uloží se a po načtení zůstane
	var w := WindowRegistry.find_window("vm_aurora_p3_2")
	_check(w != null, "okno pro ptačí test existuje")
	if w == null:
		return
	w.reset_state()
	w.activate()
	var before := w.mask.current_total
	_check(w.add_bird_dropping(Vector2(0.6, 1.0), 77), "pták může kápnout na rozdělané okno")
	_check(w.mask.current_total > before + 1.0, "na okně přibyla špína (%.1f → %.1f)" % [before, w.mask.current_total])
	_check(w.mask.kind_at(Vector2(0.6, 1.0)) == DirtTypes.BIRD, "špína je ptačí trus")
	var with_bird := w.mask.current_total
	var sv := w.save_state()
	w.load_state(JSON.parse_string(JSON.stringify(sv)))
	_check(absf(w.mask.current_total - with_bird) < with_bird * 0.02 + 1.0, "trus zůstane i po načtení hry (%.1f / %.1f)" % [w.mask.current_total, with_bird])
	w.reset_state()
	w.activate()
	w.completed = true
	_check(not w.add_bird_dropping(Vector2(0.6, 1.0), 78), "na hotové okno pták nekápne")
	w.reset_state()
	# pták sám slétne k oknu aktivní zakázky a kápne na něj
	var keep_active := ContractManager.active_id
	ContractManager.active_id = "vm_aurora_nizsi"
	w.activate()
	var drops0 := birds.drops_done
	var sent := birds.try_drop(w.global_position + w.normal() * 3.0)
	_check(sent, "pták se vydal k rozdělanému oknu")
	var steps := 0
	while birds.drops_done == drops0 and steps < 1500:
		for v in birds.birds:
			birds._step(v, 0.05)
		steps += 1
	_check(birds.drops_done == drops0 + 1, "pták doletěl a kápl na okno (%.1f s)" % (steps * 0.05))
	var dirty_bird := false
	for wid in ContractManager.active().window_ids:
		var ww := WindowRegistry.find_window(wid)
		if ww and ww.mask and not ww.mask.extras.is_empty():
			dirty_bird = true
			ww.reset_state()
	_check(dirty_bird, "trus je na okně zakázky")
	var back_ok := false
	for k in 600:
		for v in birds.birds:
			birds._step(v, 0.05)
		back_ok = birds.birds.all(func(v): return v["state"] == "orbit")
		if back_ok:
			break
	_check(back_ok, "pták se vrátí do hejna")
	ContractManager.active_id = keep_active
	# bouřka: zatáhne se, prší, po ní přibudou poptávky „Po bouřce“
	var wx: Weather = world.weather
	_check(wx != null, "počasí existuje")
	if wx == null:
		return
	var sun_e := world.sun.light_energy
	var offers0 := ContractManager.offers.keys()
	wx.start_storm()
	for k in 30:
		wx._process(0.5)
	_check(wx.intensity > 0.9 and world.sun.light_energy < sun_e * 0.6, "při bouřce se zatáhne (slunce %.2f → %.2f)" % [sun_e, world.sun.light_energy])
	_check(wx._rain.emitting, "prší")
	wx.storm_left = 0.2
	wx._process(0.5)
	var new_ids := ContractManager.offers.keys().filter(func(id): return not offers0.has(id))
	var storm_ok := new_ids.size() >= 1
	for id in new_ids:
		if str(ContractManager.offers[id].get("situation")) != "po_bource":
			storm_ok = false
	_check(storm_ok, "po bouřce přibyly poptávky „Po bouřce“ (%d)" % new_ids.size())
	for k in 30:
		wx._process(0.5)
	_check(wx.intensity == 0.0 and not wx._rain.emitting and absf(world.sun.light_energy - sun_e) < 0.01, "po bouřce se vyjasní")
	for id in new_ids:
		ContractManager._remove_offer(id)
	Events.contract_changed.emit()
	await _etapa7_fixes()


func _etapa7_fixes() -> void:
	print("--- Etapa 7: opravy po testu")
	# dron v otočeném depu míří ramenem ke sklu
	var d := WindowDrone.new()
	var holder := Node3D.new()
	holder.rotation.y = PI
	main.world.add_child(holder)
	holder.add_child(d)
	var wrong := 0
	for id in ["vm_aurora_p3_2", "vm_panorama_r5_1", "vm_panorama_z5_2", "vm_oc_p1_1"]:
		var w := WindowRegistry.find_window(id)
		if w == null:
			wrong += 1
			continue
		d.window = w
		d._hover_at(w.glass_size * 0.5)
		if d.to_global(Vector3(0, 0, -WindowDrone.HOVER)).distance_to(w.plane_to_world(w.glass_size * 0.5)) > 0.3:
			wrong += 1
	_check(wrong == 0, "dron míří mycí hlavou ke sklu i v otočeném depu (%d špatně)" % wrong)
	holder.queue_free()



## Snímky Etapy 7 (CLEARVIEW_SET=7): nástroje v rukavici, doprava, ptáci, bouřka, dodávka.
func _shots7(player: Player) -> void:
	var world: Countryside = main.world
	GameState.level = 17
	GameState.reputation = GameState.REP_STEPS[4] + 10
	GameState.money = 300000
	for id in ["rag_micro", "sponge", "squeegee_35", "brush_electric", "detergent_basic", "company_van"]:
		GameState.add_item(id)
	await _frames(5)
	# nástroje v ruce (FPS pohled na trávník u garáže)
	_look(player, Vector3(-28.0, 0.02, -2.0), Vector3(-10.0, 0.6, -2.0))
	for id in ["rag_micro", "detergent_basic", "squeegee_35", "brush_electric", "sponge"]:
		player.hold(id)
		await _frames(25)
		await _shot("e7_ruka_" + id)
	player.hold("rag_micro")
	# mytí okna v rukavici
	ContractManager.accept("novak_bungalow")
	var w := WindowRegistry.find_window("novak_w1_obyvak")
	_stand_before(player, w, 0.93, 1.3)
	await _frames(20)
	player.begin_cleaning(w, w.plane_to_world(Vector2(0.5, 0.55)))
	await _frames(30)
	player.cleaning.debug_press = true
	for i in 30:
		player.cleaning.on_mouse_motion(Vector2(8, 2))
		await _frames(1)
	await _shot("e7_myti_rukavice")
	player.cleaning.debug_press = false
	player.end_cleaning()
	ContractManager.pause_active()
	# dodávka s opraveným čelním sklem
	_look(player, CompanyBase.VAN_POS + Vector3(3.5, 0.02, 5.0), CompanyBase.VAN_POS + Vector3(0, 1.5, 1.8))
	await _frames(25)
	await _shot("e7_dodavka_sklo")
	_look(player, CompanyBase.VAN_POS + Vector3(5.0, 0.02, 1.8), CompanyBase.VAN_POS + Vector3(0, 1.6, 1.8))
	await _frames(20)
	await _shot("e7_dodavka_bok")
	# Brodec: doprava a tramvaj na zastávce
	world.travel(City.AREA_ID, player)
	await _frames(20)
	var tr := world.city.get_node("Traffic") as Traffic
	for v in tr.vehicles:
		if v["kind"] == "tram":
			v["x"] = 26.0
			v["wait"] = 30.0
			tr._place(v)
	var C := City.ORIGIN
	_look(player, C + Vector3(8.0, 0.1, -8.5), C + Vector3(30.0, 1.5, 0.0))
	await _frames(40)
	await _shot("e7_brodec_tramvaj")
	_look(player, C + Vector3(-40.0, 0.1, -8.0), C + Vector3(10.0, 1.0, 0.0))
	await _frames(60)
	await _shot("e7_brodec_doprava")
	# Horizont: auta a ptáci kolem věží
	world.travel(Metropolis.AREA_ID, player)
	await _frames(20)
	var O := Metropolis.ORIGIN
	_look(player, O + Vector3(-20.0, 0.1, -9.0), O + Vector3(20.0, 1.0, 0.0))
	await _frames(60)
	await _shot("e7_horizont_doprava")
	_look(player, O + Vector3(-12.0, 0.1, 6.0), O + Vector3(-40.0, 48.0, -20.4))
	await _frames(30)
	await _shot("e7_ptaci_aurora")
	# bouřka
	var wx := world.weather
	wx.start_storm()
	wx.storm_left = 9999.0
	for k in 30:
		wx._process(0.5)
	_look(player, O + Vector3(-60.0, 0.1, 4.0), O + Vector3(0.0, 25.0, -6.0))
	await _frames(40)
	await _shot("e7_bourka_horizont")
	world.travel("venkov", player)
	await _frames(20)
	_look(player, Vector3(-30.5, 0.02, -6.5), Vector3(0.0, 2.0, -2.0))
	await _frames(40)
	await _shot("e7_bourka_vesnice")



## Ladění: co leží těsně za sklem (stěny prostrčené za okno). CLEARVIEW_SET=probe
func _probe_behind_glass() -> void:
	await _frames(5)
	var space: PhysicsDirectSpaceState3D = (main.world as Node3D).get_world_3d().direct_space_state
	var bad := {}
	for id in WindowRegistry.windows:
		var w: CleanableWindow = WindowRegistry.windows[id]
		var n := w.normal()
		for u in [0.1, 0.3, 0.5, 0.7, 0.9]:
			for v in [0.15, 0.5, 0.85]:
				var p := w.plane_to_world(Vector2(w.glass_size.x * u, w.glass_size.y * v))
				var q := PhysicsRayQueryParameters3D.create(p - n * 0.03, p - n * 0.6)
				q.exclude = [w.body.get_rid()]
				var hit: Dictionary = space.intersect_ray(q)
				if not hit.is_empty():
					var d: float = (hit["position"] - p).length()
					if d < 0.45:
						var key := "%s" % id
						if not bad.has(key):
							bad[key] = []
						bad[key].append("u%.1f v%.2f d%.2f %s" % [u, v, d, str(hit["collider"].get_path()).get_file()])
	print("PROBE: %d oken s něčím těsně za sklem" % bad.size())
	for k in bad:
		print("PROBE ", k, " ", bad[k].slice(0, 3))



## Snímky úchopů (CLEARVIEW_SET=8): tyče v ruce a nástroje v pracovním režimu.
func _shots8(player: Player) -> void:
	GameState.level = 17
	for id in ["squeegee_35", "brush_electric", "tele_squeegee", "tele_mop", "fold_mop"]:
		GameState.add_item(id)
	await _frames(5)
	_look(player, Vector3(-28.0, 0.02, -2.0), Vector3(-10.0, 0.6, -2.0))
	for id in ["tele_squeegee", "tele_mop", "fold_mop"]:
		player.hold(id)
		await _frames(20)
		await _shot("e8_ruka_" + id)
	ContractManager.accept("novak_bungalow")
	var w := WindowRegistry.find_window("novak_w1_obyvak")
	for id in ["brush_electric", "squeegee_35", "tele_squeegee", "fold_mop"]:
		player.hold(id)
		_stand_before(player, w, 0.93, 1.3)
		await _frames(10)
		player.begin_cleaning(w, w.plane_to_world(Vector2(0.5, 0.6)))
		await _frames(25)
		player.cleaning.debug_press = true
		for i in 20:
			player.cleaning.on_mouse_motion(Vector2(6, 1))
			await _frames(1)
		await _shot("e8_myti_" + id)
		player.cleaning.debug_press = false
		player.end_cleaning()
		await _frames(5)



## Snímky 3. kola oprav (CLEARVIEW_SET=9): plošina dole, kola aut, dron u okna, interiéry.
func _shots9(player: Player) -> void:
	var world: Countryside = main.world
	GameState.level = 17
	await _frames(5)
	# plošina sjetá úplně dolů (Brodec)
	world.travel(City.AREA_ID, player)
	await _frames(20)
	var pl: SuspendedPlatform = world.city.platforms[0]
	pl.rig_visual(0.0, pl.bottom_feet())
	var out := pl.outward()
	var bp := pl.hang_pos(0.0, pl.bottom_feet())
	_look(player, Vector3(bp.x, 0.1, bp.z) + out * 3.2 + pl.side() * 1.6, bp + Vector3(0, 0.3, 0))
	await _frames(30)
	await _shot("r3_plosina_dole")
	# interiéry za okny (židle u stolů, stěny u bočních oken)
	player.set_physics_process(false)
	var k := 0
	for id in WindowRegistry.windows:
		var w: CleanableWindow = WindowRegistry.windows[id]
		if not ("_p1_" in str(id) or "pracovna" in str(id) or "kuchyn" in str(id) or "obyvak" in str(id)):
			continue
		var p := w.plane_to_world(Vector2(w.glass_size.x * 0.5, 0.0), 0.7)
		var n := w.normal()
		player.global_position = Vector3(p.x, w.plane_to_world(Vector2.ZERO).y - 0.9, p.z)
		player.yaw = atan2(n.x, n.z)
		player.pitch = deg_to_rad(-22.0)
		player.reset_physics_interpolation()
		w.material.set_shader_parameter("fade", 1.0)
		await _frames(12)
		await _shot("r3_interier_%d_%s" % [k, id])
		w.material.set_shader_parameter("fade", 0.0)
		k += 1
		if k >= 10:
			break
	player.set_physics_process(true)
	# kola aut zblízka (Brodec, auta zastavená)
	var trc := world.city.get_node("Traffic") as Traffic
	trc.process_mode = Node.PROCESS_MODE_DISABLED
	for v in trc.vehicles:
		if v["kind"] == "car" or v["kind"] == "bus":
			var vn: Node3D = v["node"]
			var side := vn.global_basis.x.normalized()
			_look(player, vn.global_position + side * 3.5 + vn.global_basis.z.normalized() * 1.5, vn.global_position + Vector3(0, 0.4, 0))
			player.set_physics_process(false)
			await _frames(20)
			await _shot("r3_kola_" + str(v["kind"]))
			player.set_physics_process(true)
			if v["kind"] == "bus":
				break
	trc.process_mode = Node.PROCESS_MODE_INHERIT
	world.travel(Metropolis.AREA_ID, player)
	await _frames(20)
	# dron v otočeném depu u okna
	var w2 := WindowRegistry.find_window("vm_aurora_p3_2")
	var holder := Node3D.new()
	holder.rotation.y = PI
	world.add_child(holder)
	var d := WindowDrone.new()
	holder.add_child(d)
	await _frames(2)
	d.window = w2
	d._hover_at(w2.glass_size * 0.5)
	d.process_mode = Node.PROCESS_MODE_DISABLED
	var n := w2.normal()
	var dp := d.global_position
	_look(player, Vector3(dp.x, 0.0, dp.z) + n * 3.0 + w2.global_basis.x.normalized() * 2.5 + Vector3(0, dp.y - 1.65, 0), dp)
	player.set_physics_process(false)
	await _frames(20)
	await _shot("r3_dron_u_okna")
	player.set_physics_process(true)
	holder.queue_free()


func player_ref() -> Player:
	return main.player


## Ladění výkonu (CLEARVIEW_SET=perf): kolik stojí vytvoření masky okna.
func _perf_probe() -> void:
	await _frames(5)
	var worst := 0
	var worst_id := ""
	var total := 0
	var n := 0
	var slow := 0
	for id in WindowRegistry.windows:
		var w: CleanableWindow = WindowRegistry.windows[id]
		w.reset_state()
		var t0 := Time.get_ticks_usec()
		w.activate()
		var dt := Time.get_ticks_usec() - t0
		total += dt
		n += 1
		if dt > 16000:
			slow += 1
		if dt > worst:
			worst = dt
			worst_id = id
		w.reset_state()
	print("PERF activate: avg %d us, max %d us (%s), >16 ms: %d / %d" % [total / maxi(n, 1), worst, worst_id, slow, n])
	var nodes := get_tree().get_node_count()
	print("PERF nodes: %d" % nodes)
	# předgenerování ve vlákně: kolik stojí hlavní vlákno
	var w2 := WindowRegistry.find_window("vm_aurora_p17_1")
	w2.reset_state()
	var t1 := Time.get_ticks_usec()
	w2.prefetch()
	var t_start := Time.get_ticks_usec() - t1
	while not w2.prefetch_done():
		await _frames(1)
	var t2 := Time.get_ticks_usec()
	w2.finish_prefetch()
	print("PERF prefetch: start %d us, převzetí %d us, aktivní %s" % [t_start, Time.get_ticks_usec() - t2, w2.is_active()])
	main.world.travel("venkov", player_ref())
	GameState.level = 20
	for area in ["venkov", "predmesti", "mesto", "velkomesto"]:
		main.world.travel(area, player_ref())
		await _frames(30)
		var mx := 0.0
		var sum := 0.0
		for k in 120:
			await _frames(1)
			var tp := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			var tph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			mx = maxf(mx, tp + tph)
			sum += tp + tph
		print("PERF %s: skripty+fyzika průměr %.2f ms, max %.2f ms" % [area, sum / 120.0, mx])



## Ladění: míří rameno dronu ke sklu u všech oken Velkoměsta? (CLEARVIEW_SET=drone)
func _drone_probe() -> void:
	await _frames(5)
	var d := WindowDrone.new()
	var holder := Node3D.new()
	holder.rotation.y = PI
	main.world.add_child(holder)
	holder.add_child(d)
	var bad := 0
	var old_bad := 0
	for id in WindowRegistry.windows:
		if not str(id).begins_with("vm_"):
			continue
		var w: CleanableWindow = WindowRegistry.windows[id]
		d.window = w
		var n := w.normal()
		d._hover_at(w.glass_size * 0.5)
		var head := d.to_global(Vector3(0, 0, -WindowDrone.HOVER))
		if head.distance_to(w.plane_to_world(w.glass_size * 0.5)) > 0.3:
			bad += 1
		# stará verze: yaw z normály
		var oy := atan2(n.x, n.z)
		var ohead := d.global_position + Basis(Vector3.UP, oy) * Vector3(0, 0, -WindowDrone.HOVER)
		if ohead.distance_to(w.plane_to_world(w.glass_size * 0.5)) > 0.3:
			old_bad += 1
			if old_bad < 5:
				print("DRONE staré špatně: ", id, " n=", n, " det=", w.global_basis.determinant())
	print("DRONE nově špatně: %d, dříve špatně: %d" % [bad, old_bad])


## Tutoriál na základně: nová hra, kroky po sobě, přeskočení, uložení a migrace v8 → v9.
func _tutorial(player: Player) -> void:
	print("--- tutoriál")
	var ui: UIRoot = main.ui
	var tut: Tutorial = main.tutorial
	GameState.reset()
	ContractManager.reset()
	WindowRegistry.reset_all()
	player.end_cleaning()
	_check(GameState.tutorial_step == -1 and not Tutorial.active(), "po resetu tutoriál neběží (autotest, načtené hry)")
	var c := ContractManager.get_contract(Tutorial.CONTRACT_ID)
	_check(c != null and c.window_ids.size() == 3, "zakázka Okna vlastní firmy má 3 okna garáže")
	_check(ContractManager.order[0] == Tutorial.CONTRACT_ID, "zakázka garáže je v tabletu první")
	for wid in c.window_ids:
		var ww := WindowRegistry.find_window(wid)
		_check(ww != null, "okno garáže existuje: " + wid)
	var wd := WindowRegistry.find_window(Tutorial.W_DUST)
	var wm := WindowRegistry.find_window(Tutorial.W_MUD)
	var wh := WindowRegistry.find_window(Tutorial.W_HIGH)
	wm.activate()
	_check(wm.kinds_present().has(DirtTypes.MUD), "na okně u bláta je bláto")
	# žádné okno garáže nesmí být zakryté zdí: paprsek zvenku musí jako první trefit sklo
	player.global_position = main.world.spawn_point
	await _frames(2)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for ww: CleanableWindow in [wd, wm, wh]:
		var ok := true
		for pf: Vector2 in [Vector2(0.5, 0.5), Vector2(0.15, 0.2), Vector2(0.85, 0.8)]:
			var pp := Vector2(ww.glass_size.x * pf.x, ww.glass_size.y * pf.y)
			var q := PhysicsRayQueryParameters3D.create(ww.plane_to_world(pp, 0.6), ww.plane_to_world(pp, -0.05), 1 | CleanableWindow.WINDOW_LAYER, [player.get_rid()])
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty() or not (hit["collider"] as Object).has_meta("window") or hit["collider"].get_meta("window") != ww:
				ok = false
		_check(ok, "okno %s je zvenku volné (nic ho nezakrývá)" % ww.window_id)
	_check(not WindowAccess.can_reach(wh) or GameState.has_item("chair_wood"), "okénko u vrat je dosažitelné se židlí")
	_check(wh.global_position.y + wh.glass_size.y * 0.5 > CleaningController.REACH_HIGH + 0.1, "okénko u vrat je výš, než hráč dosáhne ze země (učí židli)")
	_check(wd.global_position.y + wd.glass_size.y * 0.5 <= CleaningController.REACH_HIGH + 0.01, "boční okna jsou dosažitelná ze země")

	# nová hra
	player.global_position = main.world.spawn_point
	player.velocity = Vector3.ZERO
	tut.start()
	await _frames(5)
	_check(GameState.tutorial_step == Tutorial.Step.MOVE, "nová hra: tutoriál začíná krokem Pohyb")
	_check(ui.hud._objective.text.contains("WASD") and ui.hud._obj_head.text.begins_with("TUTORIÁL"), "HUD ukazuje úkol tutoriálu")
	player.global_position = main.world.spawn_point + Vector3(0, 0, 4.5)
	await _frames(3)
	_check(GameState.tutorial_step == Tutorial.Step.TABLET, "po pár krocích: otevři tablet")
	ContractManager.accept("novak_bungalow")
	await _frames(3)
	_check(GameState.tutorial_step == Tutorial.Step.TABLET, "jiná zakázka krok nesplní")
	ContractManager.accept(Tutorial.CONTRACT_ID)
	await _frames(3)
	_check(GameState.tutorial_step == Tutorial.Step.WINDOW, "zakázka přijata: dojdi k oknu")
	_stand_before(player, wd, wd.glass_size.x * 0.5, 0.7)
	await _frames(20)
	await get_tree().create_timer(1.0).timeout
	player.begin_cleaning(wd, wd.plane_to_world(wd.glass_size * 0.5))
	await _frames(5)
	_check(player.mode == Player.Mode.CLEANING, "boční okno garáže jde mýt ze země")
	_check(GameState.tutorial_step == Tutorial.Step.SPRAY, "pracovní režim: nastříkej saponát")
	player.cleaning.spray()
	await _frames(3)
	_check(GameState.tutorial_step == Tutorial.Step.WIPE, "po nástřiku: drhni")
	var tool := GameState.best_tool("rag")
	var passes := 0
	while not wd.completed and passes < 60:
		_zigzag(wd, tool)
		passes += 1
		await _frames(1)
	await _frames(5)
	_check(wd.completed, "okno s prachem umyté (%d průchodů)" % passes)
	_check(GameState.tutorial_step == Tutorial.Step.RINSE, "po prvním okně: vymáchej hadr")
	player.end_cleaning()
	main.world._rinse_rag(player)
	await _frames(3)
	_check(GameState.tutorial_step == Tutorial.Step.MUD, "po vymáchání: okno s blátem")
	wm.activate()
	passes = 0
	while not wm.completed and passes < 80:
		_wet_all(wm.mask, 0.0)
		_zigzag(wm, tool)
		passes += 1
		await _frames(1)
	await _frames(5)
	_check(GameState.tutorial_step == Tutorial.Step.CHAIR, "obě boční okna hotová: židle k vysokému okénku")
	_check(ui.hud._objective.text.contains("židli"), "HUD radí židli")
	# ze země na horní okraj okénka nedosáhne
	_stand_before(player, wh, wh.glass_size.x * 0.5, 0.7)
	await _frames(20)
	player.begin_cleaning(wh, wh.plane_to_world(wh.glass_size * 0.5))
	await _frames(5)
	if player.mode == Player.Mode.CLEANING:
		_check(player.cleaning.reach_max.y < wh.glass_size.y - 0.05, "okénko u vrat: ze země dosáhne jen na spodek (%.2f / %.2f)" % [player.cleaning.reach_max.y, wh.glass_size.y])
		player.end_cleaning()
	else:
		_check(true, "okénko u vrat: ze země se mytí nespustí")
	var money0 := GameState.money
	wh.activate()
	passes = 0
	while not wh.completed and passes < 60:
		_zigzag(wh, tool)
		passes += 1
		await _frames(1)
	await _frames(70)
	_check(ContractManager.state.get(Tutorial.CONTRACT_ID) == "completed", "zakázka Okna vlastní firmy dokončena")
	_check(GameState.money - money0 == 120, "odměna za garáž vyplacena (%d Kč)" % (GameState.money - money0))
	_check(GameState.tutorial_step == Tutorial.Step.SHOP, "po garáži: ukáže se cesta do obchodu")
	_check(ui.hud._objective.text.contains("OBCHOD"), "HUD popisuje, kde je obchod")
	var smark := get_tree().get_first_node_in_group("tutorial_shop_marker") as Node3D
	_check(smark != null and smark.visible, "nad obchodem svítí značka pro tutoriál")
	player.global_position = Vector3(-74.0, 0.1, -7.0)
	await _frames(3)
	_check(GameState.tutorial_step == Tutorial.Step.DONE, "u obchodu: poslední krok, první zákaznice v tabletu")
	_check(smark != null and not smark.visible, "značka obchodu po kroku zmizí")
	_check(ui.hud._objective.text.contains("Nováková"), "HUD odkazuje na paní Novákovou")
	# uložení a načtení uprostřed posledního kroku
	_check(SaveManager.save_game(true), "uložení během tutoriálu")
	GameState.tutorial_step = -1
	SaveManager.load_game()
	_check(GameState.tutorial_step == Tutorial.Step.DONE, "krok tutoriálu se ukládá")
	ContractManager.accept("novak_bungalow")
	await _frames(3)
	_check(GameState.tutorial_step == -1, "přijetím další zakázky tutoriál skončí")
	_check(ui.hud._obj_head.text == "ÚKOL", "HUD je zpátky u běžného úkolu")

	# přeskočení
	GameState.reset()
	ContractManager.reset()
	WindowRegistry.reset_all()
	tut.start()
	await _frames(2)
	ui._open(ui.pause_menu, true)
	await _frames(2)
	var skip_btn: Button = null
	for b in ui._pause_box.get_children():
		if b is Button and b.text == "Přeskočit tutoriál":
			skip_btn = b
	_check(skip_btn != null and skip_btn.visible, "v pauze je tlačítko Přeskočit tutoriál")
	skip_btn.pressed.emit()
	await _frames(2)
	_check(not Tutorial.active() and not ui.pause_menu.visible, "tutoriál přeskočen, menu zavřené")
	ui._open(ui.pause_menu, true)
	await _frames(2)
	_check(not skip_btn.visible, "bez tutoriálu tlačítko Přeskočit není vidět")
	ui.close_all()

	# migrace uložení v8 → v9: starý hráč tutoriál nedostane, zakázka garáže je hotová
	var old := {"version": 8, "state": {"level": 9, "inventory": ["rag_old"]}, "contracts": {"state": {"novak_bungalow": "completed"}, "times_done": {"novak_bungalow": 2}}, "windows": {}, "player": {}, "persist": {}}
	var mig := SaveManager._migrate(old)
	_check(int(mig["version"]) == SaveManager.SAVE_VERSION, "migrace v8 → v%d" % SaveManager.SAVE_VERSION)
	_check(mig["contracts"]["state"].get(Tutorial.CONTRACT_ID) == "completed" and int(mig["contracts"]["times_done"].get(Tutorial.CONTRACT_ID)) == 1, "staré uložení: garáž je hotová (jde jen jako pravidelný úklid)")
	_check(int(mig["state"]["tutorial_step"]) == -1, "staré uložení: tutoriál se nespustí")
	GameState.reset()
	ContractManager.reset()
	WindowRegistry.reset_all()


## Snímky tutoriálu (CLEARVIEW_SET=tut).
func _shots_tut(player: Player) -> void:
	var ui: UIRoot = main.ui
	var tut: Tutorial = main.tutorial
	player.global_position = main.world.spawn_point
	var tg: Vector3 = Vector3(-33.0, 0.0, -12.0) - (main.world.spawn_point as Vector3)
	player.yaw = atan2(-tg.x, -tg.z)
	player.pitch = 0.0
	tut.start()
	await _frames(40)
	await _shot("t1_start")
	player.global_position += Vector3(0, 0, 4.5)
	await _frames(5)
	player.global_position = main.world.spawn_point
	await _frames(10)
	ui.open_tablet()
	ui.tablet._show("zakazky")
	await _frames(10)
	await _shot("t2_tablet")
	ui.close_all()
	ContractManager.accept(Tutorial.CONTRACT_ID)
	_look(player, Vector3(-27.0, 0.02, -6.0), Vector3(-34.0, 1.5, -14.0))
	await _frames(40)
	await _shot("t3_garaz_znacky")
	var wd := WindowRegistry.find_window(Tutorial.W_DUST)
	_stand_before(player, wd, wd.glass_size.x * 0.5, 0.7)
	await _frames(30)
	await get_tree().create_timer(1.0).timeout
	player.begin_cleaning(wd, wd.plane_to_world(wd.glass_size * 0.5))
	await _frames(40)
	await _shot("t4_okno_prach")
	player.cleaning.spray()
	await _frames(20)
	await _shot("t5_sprej")
	player.end_cleaning()
	var wm := WindowRegistry.find_window(Tutorial.W_MUD)
	_stand_before(player, wm, wm.glass_size.x * 0.5, 0.7)
	await _frames(30)
	await get_tree().create_timer(1.0).timeout
	player.begin_cleaning(wm, wm.plane_to_world(wm.glass_size * 0.5))
	await _frames(40)
	await _shot("t6_okno_blato")
	player.end_cleaning()
	var tool := GameState.best_tool("rag")
	for ww: CleanableWindow in [wd, wm]:
		ww.activate()
		var n := 0
		while not ww.completed and n < 80:
			_wet_all(ww.mask, 0.0)
			_zigzag(ww, tool)
			n += 1
			await _frames(1)
	main.world._rinse_rag(player)
	await _frames(10)
	var wh := WindowRegistry.find_window(Tutorial.W_HIGH)
	_look(player, wh.plane_to_world(wh.glass_size * 0.5, 3.2) * Vector3(1, 0, 1), wh.plane_to_world(wh.glass_size * 0.5))
	await _frames(40)
	await _shot("t7_zidle")
	wh.activate()
	var k := 0
	while not wh.completed and k < 80:
		_zigzag(wh, tool)
		k += 1
		await _frames(1)
	await _frames(80)
	_look(player, Vector3(-28.0, 0.02, -5.0), Vector3(-34.0, 1.5, -14.0))
	await _frames(30)
	await _shot("t8_hotovo")
	_look(player, Vector3(-40.5, 0.02, -12.0), Vector3(-37.0, 1.6, -14.0))
	await _frames(30)
	await _shot("t9_bok_blato")


## Rotační kartáče (ruční i na teleskopické tyči): myjí i bez drhnutí myší.
func _cosmetics(player: Player) -> void:
	print("--- Kosmetika ---")
	var saved := GameState.cosmetics.duplicate(true)
	var money0 := GameState.money
	GameState.cosmetics = {}
	_check(Cosmetics.selected("van") == "van_bila" and Cosmetics.owns("van_bila"), "výchozí lak je bílý a zdarma")
	_check(not Cosmetics.owns("van_grafit"), "grafit se musí koupit")
	GameState.money = 100
	_check(Cosmetics.choose("van_grafit") != "" and Cosmetics.selected("van") == "van_bila", "bez peněz se nekoupí")
	GameState.money = 10000
	_check(Cosmetics.choose("van_grafit") == "" and Cosmetics.selected("van") == "van_grafit", "koupený lak se použije")
	_check(GameState.money == 10000 - int(Cosmetics.OPTIONS["van_grafit"][2]), "lak stojí peníze")
	Cosmetics.choose("van_bila")
	var m1 := GameState.money
	Cosmetics.choose("van_grafit")
	_check(GameState.money == m1, "přepnutí na koupený lak je zdarma")
	_check(Cosmetics.choose("out_oranzova") == "" and Cosmetics.sleeve() == Cosmetics.OPTIONS["out_oranzova"][3], "oblečení mění barvu rukávů")
	var d := GameState.to_dict()
	GameState.cosmetics = {}
	GameState.from_dict(d)
	_check(Cosmetics.selected("van") == "van_grafit" and Cosmetics.owns("van_grafit"), "kosmetika se ukládá")
	if not GameState.has_item("company_van"):
		GameState.add_item("company_van")
	await _frames(3)
	var base: CompanyBase = get_tree().get_first_node_in_group("company_base")
	Cosmetics.choose("liv_oranzovy")
	await _frames(2)
	var vm: MeshInstance3D = base._van.get_node_or_null("VanMesh") if base and base._van else null
	_check(vm != null and base._van.get_child_count() > 3, "dodávka se přebarví na místě")
	GameState.cosmetics = saved
	GameState.money = money0
	Events.cosmetics_changed.emit()
	await _frames(2)


func _atmosphere_checks(_player: Player) -> void:
	print("--- Denní doba a roční období ---")
	var atmo: Atmosphere = null
	if main.world and "atmosphere" in main.world:
		atmo = main.world.atmosphere
	_check(atmo != null, "atmosféra existuje")
	if atmo == null:
		return
	var c0 := GameState.clock
	var d0 := GameState.day
	GameState.clock = 12.0
	GameState.day = 2
	await _frames(2)
	_check(atmo.night < 0.05, "v poledne není noc")
	GameState.clock = 1.0
	await _frames(2)
	_check(atmo.night > 0.9, "v jednu v noci je noc")
	var lamps := get_tree().get_nodes_in_group("street_lights")
	_check(lamps.size() > 0 and (lamps[0] as Node3D).visible, "v noci svítí lampy")
	GameState.day = 4
	GameState.clock = 12.0
	await _frames(2)
	_check(atmo.season_index() == 2 and atmo.autumn > 0.9, "4. den je podzim")
	GameState.day = 6
	await _frames(2)
	_check(atmo.season_index() == 3 and atmo.winter > 0.9, "6. den je zima")
	GameState.clock = c0
	GameState.day = d0
	await _frames(2)


func _spin_brushes(player: Player) -> void:
	print("--- Rotační kartáče ---")
	var bt := GameState.get_tool("brush_tele")
	var be := GameState.get_tool("brush_electric")
	_check(bt != null and bt.spin > 0.0 and bt.reach_bonus > 1.5 and bt.electric, "nový nástroj: rotační kartáč na teleskopické tyči")
	_check(be.spin > 0.0, "ruční elektrický kartáč se taky točí sám")
	var in_shop := false
	for d in Shop.catalog("Nástroje"):
		if d["id"] == "brush_tele":
			in_shop = true
	_check(in_shop, "kartáč na tyči je v obchodě")
	# bez pohybu: kartáč pod sebou čistí, hadr ne
	var mb := _uniform(DirtTypes.DUST, 0.8, 0.0)
	var mr := _uniform(DirtTypes.DUST, 0.8, 0.0)
	var rag := GameState.get_tool("rag_old")
	var rb := 0.0
	for i in 60:
		rb += mb.spin_scrub(Vector2(0.5, 0.3), bt, 0.3, bt.strength * bt.spin / 60.0)
	var rr := mr.scrub(Vector2(0.5, 0.3), Vector2(0.5, 0.3), rag, 0.3)
	_check(rb > 0.5 and rr == 0.0, "stojící kartáč myje sám (%.1f), stojící hadr ne" % rb)
	# ve hře: přitlačený kartáč bez pohybu myší čistí okno
	var world: Countryside = main.world
	world.travel("venkov", player)
	await _frames(3)
	var w := WindowRegistry.find_window("novak_w1_obyvak")
	w.reset_state()
	ContractManager.reset()
	ContractManager.accept("novak_bungalow")
	await _frames(2)
	w.activate()
	GameState.add_item("brush_tele")
	GameState.set_active("brush_tele")
	player.hold("brush_tele")
	_check(WindowAccess.has_tele(), "kartáč na tyči se počítá jako teleskopická tyč")
	_stand_before(player, w, 0.9, 0.7)
	await _frames(10)
	player.begin_cleaning(w, w.plane_to_world(Vector2(0.9, 0.6)))
	await _frames(3)
	var cc: CleaningController = player.cleaning
	_check(player.mode == Player.Mode.CLEANING and cc.tool.id == "brush_tele", "mytí kartáčem na tyči")
	_check(player.hand.pole.visible and player.hand.brush_body.visible, "v ruce je tyč a na jejím konci motor kartáče")
	var cl0 := w.cleanliness()
	cc.debug_press = true
	await _frames(45)
	cc.debug_press = false
	_check(w.cleanliness() > cl0 + 0.003, "kartáč myje i bez pohybu myší (%.3f -> %.3f)" % [cl0, w.cleanliness()])
	# pomalá jízda bez drhnutí: jednou přejet řádek stačí, aby byl pruh čistý
	cc.debug_press = true
	for i in 60:
		cc.on_mouse_motion(Vector2(4, 0))
		await _frames(1)
	cc.debug_press = false
	_check(w.cleanliness() > cl0 + 0.01, "pomalé přejetí kartáčem umývá pruh (%.3f)" % w.cleanliness())
	player.end_cleaning()
	await _frames(2)
	GameState.set_active("rag_old")
	player.hold("rag_old")
	ContractManager.reset()
	w.reset_state()


## Poznámky z hraní s Kikuskou (2026-11-14): kompas, hledání nářadí, ždímání,
## kbelík, žebřík, talenty.
func _kikuska(player: Player) -> void:
	print("--- Poznámky z hraní (kompas, kbelík, ždímání…) ---")
	# tablet se vejde na obrazovku ve všech sekcích i kategoriích obchodu
	var tab: Tablet = main.ui.tablet
	main.ui.open_tablet()
	# nejmenší podporovaná obrazovka = základní rozlišení 1600×900
	var vp := Vector2(1600, 900)
	var worst := ""
	for sec in Tablet.SECTIONS:
		var cats: Array = Shop.CATEGORIES if sec[0] == "obchod" else [""]
		for cat in cats:
			if cat != "":
				tab._shop_cat = cat
			tab._show(sec[0])
			await _frames(3)
			var r: Rect2 = tab._bezel.get_global_rect()
			if r.size.x > vp.x + 1.0 or r.size.y > vp.y + 1.0 or r.position.x < -1.0:
				worst += " %s/%s %dx%d" % [sec[0], cat, int(r.size.x), int(r.size.y)]
	_check(worst == "", "tablet se vejde na obrazovku (%dx%d)%s" % [int(vp.x), int(vp.y), worst])
	main.ui.close_all()
	await _frames(2)
	var world: Countryside = main.world
	world.travel("venkov", player)
	await _frames(3)
	var w := WindowRegistry.find_window("novak_w1_obyvak")
	w.reset_state()
	ContractManager.reset()
	ContractManager.accept("novak_bungalow")
	await _frames(2)
	# kompas: daleko = značka zakázky s nápisem, blízko = šipky nad okny
	var nav: NavArrow = main.ui.hud.nav
	player.global_position = Vector3(-30, 0.1, -6)
	player.reset_physics_interpolation()
	await _frames(15)
	_check(nav.has_target and not nav.arrived and nav._label.text.contains("m"), "kompas ukazuje k zakázce a vzdálenost (%s)" % nav._label.text)
	var mk: WindowMarkers = main.get_node("WindowMarkers")
	await _frames(15)
	var any_vis := false
	for k in mk._marks:
		any_vis = any_vis or mk._marks[k].visible
	_check(not any_vis, "daleko od budovy šipky nad okny nesvítí")
	_stand_before(player, w, 0.9, 1.0)
	await _frames(15)
	any_vis = false
	for k in mk._marks:
		any_vis = any_vis or mk._marks[k].visible
	_check(nav.arrived and any_vis, "u budovy se rozsvítí šipky ▼ nad okny")
	_check(not InputMap.has_action("map"), "mapa [M] je ze hry pryč")
	# [R] najde nářadí
	var finder: ToolFinder = main.get_node("ToolFinder")
	finder.show_tools()
	await _frames(2)
	_check(finder._labels.size() >= 1 and nav.tool_marks.size() == finder._labels.size(), "[R] ukáže nářadí modrými šipkami (%d)" % finder._labels.size())
	_check(InputMap.action_get_events("robot")[0].physical_keycode == KEY_G, "robot se přikládá klávesou [G]")
	finder._clear()
	# houbička se zanáší a ždímá se [R]
	GameState.add_item("sponge")
	GameState.set_active("sponge")
	player.hold("sponge")
	player.begin_cleaning(w, w.plane_to_world(Vector2(0.9, 0.6)))
	await _frames(3)
	var cc: CleaningController = player.cleaning
	_check(cc.tool.id == "sponge" and cc.soils(), "houbička se při mytí zanáší")
	cc.rag_dirt = 0.9
	cc.moisture = 1.0
	var weak := cc.soil_mult()
	_check(weak < 0.8 and weak >= 0.6, "zanesená houbička čistí hůř, ale ne o moc (×%.2f)" % weak)
	_check(cc.wring(), "[R] vyždímá houbičku")
	_check(cc.rag_dirt < 0.3 and cc.moisture <= 0.35, "po vyždímání je houbička čistší a jen vlhká (%.2f / %.2f)" % [cc.rag_dirt, cc.moisture])
	await _frames(30)
	cc.rag_dirt = 0.0
	cc.debug_press = true
	for i in 90:
		cc.rag_target = Vector2(0.15 + (i % 15) * 0.08, 0.3 + (i / 15) * 0.12)
		await _frames(1)
	cc.debug_press = false
	_check(cc.rag_dirt > 0.02, "mytím špinavého okna se houbička postupně zanáší (%.2f, okno %.2f, %.1f m²)" % [cc.rag_dirt, w.cleanliness(), w.glass_size.x * w.glass_size.y])
	player.end_cleaning()
	await _frames(2)
	# kbelík
	var bk: Bucket = world.carry_bucket
	_check(not bk.visible, "kbelík je ve světě až po koupi")
	GameState.add_item("bucket_carry")
	await _frames(2)
	_check(bk.visible and bk.water == Bucket.capacity(), "koupený kbelík stojí u garáže plný")
	bk.global_position = w.plane_to_world(Vector2(0.0, 0.0), 1.5) * Vector3(1, 0, 1)
	GameState.tank = 0.0
	bk.interact(player)
	_check(bk.water == Bucket.capacity() - 1 and GameState.tank > 1.0, "z kbelíku se doplní rozprašovač (zbývá %d)" % bk.water)
	bk.water = 0
	bk.global_position = Vector3(-60, 0, -40)
	bk.set_carried(false)
	_check(bk.water == 0, "kbelík daleko od vody se nenaplní")
	var src := get_tree().get_nodes_in_group("water_source")
	_check(src.size() >= 10, "zdroje vody jsou označené (%d)" % src.size())
	bk.global_position = (src[0] as Node3D).global_position + Vector3(1.0, 0, 0)
	bk.set_carried(false)
	_check(bk.water == Bucket.capacity(), "kbelík postavený u vody se naplní")
	player.global_position = bk.global_position + Vector3(0, 0, 1.0)
	player.pick_up(bk)
	_check(player.carried == bk and not bk.visible, "kbelík jde nést")
	player.release_carried()
	GameState.remove_item("bucket_carry")
	bk.global_transform = bk.home
	# žebřík: podržené [E] zvedne, sestup mezerníkem dojede až dolů
	var lad: Ladder = world.ladders[0]
	GameState.add_item(lad.item_id)
	await _frames(2)
	player.global_position = lad.global_position + lad.global_basis.z * 1.3
	player.reset_physics_interpolation()
	player.climb_ladder(lad)
	player.ladder_h = 1.5
	await _frames(2)
	player.leave_ladder()
	for i in 200:
		await _frames(1)
		if player.mode == Player.Mode.WALK:
			break
	_check(player.mode == Player.Mode.WALK and player.ladder == null, "[mezerník] nahoře na žebříku: hráč sleze dolů sám")
	player._e_hold_target = lad
	player._e_hold_t = 0.0
	await _frames(35)
	_check(player.carried == lad, "podržením [E] se žebřík zvedne")
	player.release_carried()
	lad.send_home()
	# talenty: svítící upozornění a zhasnutí po otevření stromu
	GameState.talent_points = 1
	HUD.talents_seen = 0
	await _frames(40)
	_check(main.ui.hud._talent_hint.visible, "nerozdaný talentový bod svítí pod úrovní")
	main.ui.open_tablet_section("talenty")
	await _frames(40)
	_check(not main.ui.hud._talent_hint.visible, "po otevření stromu talentů upozornění zhasne")
	var tree: TalentTree = null
	for n in main.ui.tablet._content.get_children():
		if n is TalentTree:
			tree = n
	_check(tree != null and tree.custom_minimum_size.y < 560.0, "strom talentů se vejde bez posouvání (%.0f px)" % (tree.custom_minimum_size.y if tree else -1.0))
	main.ui.close_all()
	GameState.talent_points = 0
	ContractManager.reset()
	w.reset_state()
	GameState.set_active("rag_old")
	player.hold("rag_old")


## Snímky k poznámkám z hraní s Kikuskou (CLEARVIEW_SET=kik).
func _shots_kik(player: Player) -> void:
	var ui: UIRoot = main.ui
	var world: Countryside = main.world
	GameState.clock = 11.0
	GameState.day = 2
	GameState.level = 4
	ContractManager.accept("novak_bungalow")
	# kompas daleko od zakázky
	_look(player, Vector3(-30, 0.02, -2.0), Vector3(0, 1.6, -2.0))
	await _frames(30)
	await _shot("kik_kompas")
	# u budovy: šipky nad okny
	var w := WindowRegistry.find_window("novak_w1_obyvak")
	_look(player, w.plane_to_world(Vector2(0.6, 0.0), 7.0) * Vector3(1, 0, 1), w.plane_to_world(w.glass_size * 0.5))
	await _frames(30)
	await _shot("kik_sipky_okna")
	# [R] nářadí
	GameState.add_item("ladder_small")
	GameState.add_item("bucket_carry")
	await _frames(5)
	main.get_node("ToolFinder").show_tools()
	_look(player, Vector3(-20, 0.02, -2.0), Vector3(-30, 1.0, -10.0))
	await _frames(20)
	await _shot("kik_najit_naradi")
	# nástřik saponátu na okno
	_stand_before(player, w, 0.6, 1.1)
	await _frames(10)
	player.begin_cleaning(w, w.plane_to_world(Vector2(0.6, 0.7)))
	await _frames(25)
	player.cleaning.spray()
	await _frames(12)
	await _shot("kik_nastrik")
	# houbička: zanesená + ždímání
	GameState.add_item("sponge")
	player.cleaning.cycle_tool(1)
	while player.cleaning.tool.id != "sponge":
		player.cleaning.cycle_tool(1)
	player.cleaning.rag_dirt = 0.85
	player.cleaning._soil_hint = false
	player.cleaning._soil(0.0, 0.0)
	await _frames(20)
	await _shot("kik_houba_spinava")
	player.cleaning.wring()
	await _frames(14)
	await _shot("kik_zdimani")
	await _frames(30)
	# prst do prachu
	while player.cleaning.tool.id != "finger":
		player.cleaning.cycle_tool(1)
	var w2 := WindowRegistry.find_window("novak_w2_kuchyn")
	player.end_cleaning()
	await _frames(3)
	_stand_before(player, w2 if w2 else w, 0.6, 1.1)
	await _frames(10)
	var ww: CleanableWindow = w2 if w2 else w
	player.begin_cleaning(ww, ww.plane_to_world(Vector2(0.4, 0.9)))
	await _frames(10)
	var cc: CleaningController = player.cleaning
	cc.debug_press = true
	# srdíčko
	var c0 := Vector2(ww.glass_size.x * 0.5, 0.95)
	for i in 64:
		var t := TAU * i / 63.0
		var hp := Vector2(16.0 * pow(sin(t), 3.0), 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)) * 0.016
		cc.rag_target = c0 + hp
		await _frames(1)
	cc.debug_press = false
	await _frames(20)
	await _shot("kik_prst_srdicko")
	player.end_cleaning()
	await _frames(3)
	# kbelík u domu
	var bk: Bucket = world.carry_bucket
	bk.global_position = w.plane_to_world(Vector2(-0.3, 0.0), 1.0) * Vector3(1, 0, 1)
	_look(player, w.plane_to_world(Vector2(0.8, 0.0), 3.0) * Vector3(1, 0, 1), bk.global_position + Vector3(0, 0.3, 0))
	await _frames(20)
	await _shot("kik_kbelik")
	# lavička u chaty
	_look(player, Vector3(-9.0, 0.02, -49.0), Vector3(-3.6, 0.6, -46.5))
	await _frames(20)
	await _shot("kik_lavicka_chata")
	# skleník
	_look(player, Vector3(9.0, 0.02, 33.0), Vector3(9.0, 1.4, 25.0))
	await _frames(20)
	await _shot("kik_sklenik")
	# karta nové úrovně
	GameState.talent_points = 1
	HUD.talents_seen = 0
	ui.notifications.show_level_card(5)
	await _frames(40)
	await _shot("kik_nova_uroven")
	ui.notifications.hide_level_card()
	ui.open_tablet_section("talenty")
	await _frames(15)
	await _shot("kik_talenty")
	ui.close_all()
	ContractManager.reset()
	ui.open_tablet_section("zakazky")
	ContractManager.state["chata_rybnik"] = "completed"
	ui.tablet._show("zakazky")
	await _frames(15)
	await _shot("kik_zakazky_tlacitka")
	ui.close_all()
	# autobus
	_look(player, Vector3(Countryside.BUS_X + 3.1, 0.05, -5.4), Vector3(Countryside.BUS_X + 18.0, 1.5, -1.5))
	await _frames(10)
	world.bus_travel(Suburb.AREA_ID, player)
	await get_tree().create_timer(2.6).timeout
	await _shot("kik_autobus_prijezd")
	await get_tree().create_timer(3.5).timeout
	player.yaw += 0.6
	await get_tree().create_timer(1.5).timeout
	await _shot("kik_autobus_odjezd")
	await get_tree().create_timer(4.0).timeout


## Snímky oprav po druhém testu (CLEARVIEW_SET=fix2): tablet-obchod, skleník.
func _shots_fix2(player: Player) -> void:
	var ui: UIRoot = main.ui
	GameState.clock = 11.0
	GameState.day = 2
	GameState.level = 18
	GameState.money = 250000
	# skleník zvenku (dveře na západním štítu) a uvnitř (police na lankách)
	_look(player, Vector3(3.0, 0.02, 27.5), Vector3(5.8, 1.0, 25.0))
	await _frames(25)
	await _shot("fix2_sklenik_dvere")
	_look(player, Vector3(4.6, 0.02, 25.0), Vector3(9.0, 1.0, 25.0))
	await _frames(20)
	await _shot("fix2_sklenik_dvere_blizko")
	_look(player, Vector3(9.0, 0.02, 33.0), Vector3(9.0, 1.4, 25.0))
	await _frames(20)
	await _shot("fix2_sklenik")
	player.global_position = Vector3(6.4, 0.02, 25.0)
	_look(player, Vector3(6.4, 0.02, 25.0), Vector3(12.0, 1.1, 25.6))
	await _frames(20)
	await _shot("fix2_sklenik_police")
	var i := 0
	for cat in Shop.CATEGORIES:
		ui.open_tablet_section("obchod")
		ui.tablet._shop_cat = cat
		ui.tablet._show("obchod")
		await _frames(15)
		await _shot("fix2_tablet_obchod_%d" % i)
		print("tablet obchod %s: %s" % [cat, ui.tablet._bezel.get_global_rect()])
		ui.close_all()
		i += 1


## Snímky rotačního kartáče na tyči (CLEARVIEW_SET=brush).
func _shots_brush(player: Player) -> void:
	GameState.level = 17
	GameState.reputation = GameState.REP_STEPS[GameState.REP_STEPS.size() - 1]
	for id in ["brush_tele", "brush_electric"]:
		GameState.add_item(id)
	await _frames(5)
	_look(player, Vector3(-28.0, 0.02, -2.0), Vector3(-10.0, 0.6, -2.0))
	player.hold("brush_tele")
	await _frames(20)
	await _shot("k_ruka_brush_tele")
	ContractManager.accept("novak_bungalow")
	var w := WindowRegistry.find_window("novak_w1_obyvak")
	for id in ["brush_tele", "brush_electric"]:
		GameState.set_active(id)
		player.hold(id)
		_stand_before(player, w, 0.93, 1.3)
		await _frames(10)
		player.begin_cleaning(w, w.plane_to_world(Vector2(0.5, 0.9 if id == "brush_tele" else 0.6)))
		await _frames(25)
		player.cleaning.spray()
		await _frames(5)
		player.cleaning.debug_press = true
		for i in 40:
			player.cleaning.on_mouse_motion(Vector2(3, 0))
			await _frames(1)
		await _shot("k_myti_" + id)
		player.cleaning.debug_press = false
		player.end_cleaning()
	main.ui.open_shop()
	await _frames(10)
	await _shot("k_obchod")
	main.ui.shop.visible = false
	main.ui.pause_menu.visible = true
	main.ui._pause_box.visible = false
	main.ui._settings.visible = true
	await _frames(10)
	await _shot("k_nastaveni")
	main.ui._settings.visible = false
	main.ui.pause_menu.visible = false


## Snímky denní doby, ročních období, terénu a počasí (CLEARVIEW_SET=atmo).
## Snímky kosmetiky (CLEARVIEW_SET=kosm).
func _shots_kosm(player: Player) -> void:
	var ui: UIRoot = main.ui
	GameState.level = 12
	GameState.money = 90000
	GameState.clock = 11.0
	GameState.day = 2
	GameState.add_item("company_van")
	await _frames(10)
	var base: CompanyBase = get_tree().get_first_node_in_group("company_base")
	var vp := base.van_position()
	ui.hud.visible = false
	for combo: Array in [["van_bila", "liv_modry"], ["van_grafit", "liv_oranzovy"], ["van_zluta", "liv_zeleny"], ["van_vinova", "liv_zlaty"]]:
		Cosmetics.choose(combo[0])
		Cosmetics.choose(combo[1])
		_look(player, vp + Vector3(5.5, 0.02, 4.5), vp + Vector3(0, 1.3, 0))
		await _frames(20)
		await _shot("k_" + combo[0])
	ui.hud.visible = true
	Cosmetics.choose("out_oranzova")
	_look(player, Vector3(-30.0, 0.02, -2.0), Vector3(-42.0, 1.5, -12.0))
	await _frames(20)
	await _shot("k_rukav")
	ui.open_tablet_section("firma")
	await _frames(10)
	var sc: Node = ui.tablet._content
	while sc and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc:
		(sc as ScrollContainer).scroll_vertical = 100000
	await _frames(10)
	await _shot("k_tablet")


func _shots_atmo(player: Player) -> void:
	var world: Countryside = main.world
	main.ui.hud.visible = false
	Settings.day_cycle = true
	Settings.seasons = true
	var at := world.atmosphere
	var meadow := Vector3(46.0, 0.0, -40.0)
	meadow.y = world.terrain_h(meadow.x, meadow.z) + 0.05
	var village := Vector3(5.0, 3.0, -12.0)
	var views := [
		["a_leto_poledne", 2, 12.5, meadow, village],
		["a_leto_zlata", 2, 19.4, meadow, village],
		["a_leto_noc", 2, 23.0, Vector3(8.0, 0.02, 1.5), Vector3(-10.0, 2.5, -14.0)],
		["a_podzim", 4, 11.0, meadow, village],
		["a_zima", 6, 11.0, meadow, village],
		["a_zima_vesnice", 6, 10.0, Vector3(8.0, 0.02, 1.5), Vector3(-10.0, 2.5, -14.0)],
		["a_jaro", 0, 9.5, meadow, village],
		["a_louka", 2, 10.0, Vector3(-60.0, 0.0, -30.0), Vector3(-90.0, 1.0, -60.0)],
		["a_kopce", 2, 15.0, Vector3(-100.0, 0.0, -70.0), Vector3(-160.0, 2.0, -90.0)],
	]
	for v in views:
		GameState.day = v[1]
		GameState.clock = v[2]
		var pos: Vector3 = v[3]
		if pos.y < 0.01:
			pos.y = world.terrain_h(pos.x, pos.z) + 0.05
		_look(player, pos, v[4])
		await _frames(30)
		await _shot(v[0])
	# déšť na skle a námraza: pohled zblízka na okno bungalovu
	var w := WindowRegistry.find_window("novak_w1_obyvak")
	w.activate()
	GameState.day = 2
	GameState.clock = 13.0
	world.weather.start_storm()
	world.weather.intensity = 1.0
	world.weather.storm_left = 40.0
	_stand_before(player, w, 0.9, 1.2)
	await _frames(60)
	await _shot("a_dest_sklo")
	world.weather.storm_left = 0.0
	world.weather.intensity = 0.0
	world.weather.glass_rain = 0.0
	GameState.day = 6
	GameState.clock = 7.5
	await _frames(40)
	await _shot("a_namraza")
	GameState.day = 6
	GameState.clock = 12.0
	world.weather.start_storm()
	world.weather.intensity = 1.0
	_look(player, meadow, village)
	await _frames(60)
	await _shot("a_snezeni")
	world.weather.storm_left = 0.0
	world.weather.intensity = 0.0
	main.ui.hud.visible = true


## Kontrolní snímky k Ariho připomínkám (jezírko, cedule, ploty, zastávka, ruka, tráva, mraky).
func _shots_fb(player: Player) -> void:
	var world: Countryside = main.world
	main.ui.hud.visible = false
	Settings.day_cycle = true
	GameState.day = 2
	GameState.clock = 11.0
	get_tree().call_group("tutorial_shop_marker", "set_visible", true)
	var views := [
		["fb_jezirko", Vector3(-24.0, 0.02, -31.2), Vector3(-24.0, -0.4, -42.0)],
		["fb_jezirko_bok", Vector3(-7.5, 0.02, -38.0), Vector3(-24.0, -0.3, -43.0)],
		["fb_lavicka_zapad", Vector3(-41.0, 0.02, -36.0), Vector3(-36.0, 0.4, -42.0)],
		["fb_chata_cedule", Vector3(-8.6, 0.02, -43.6), Vector3(-5.9, 1.1, -45.4)],
		["fb_obchod", Vector3(-74.0, 0.02, -1.0), Vector3(-74.0, 2.2, -14.0)],
		["fb_zastavka", Vector3(-16.0, 0.02, -1.2), Vector3(-19.0, 1.4, -6.4)],
		["fb_chodnik_jih", Vector3(-30.0, 0.02, 3.6), Vector3(10.0, 0.6, 7.0)],
		["fb_ploty", Vector3(22.0, 0.02, 2.0), Vector3(40.0, 0.8, 16.0)],
		["fb_zivy_plot", Vector3(-6.0, 0.02, 4.0), Vector3(-20.0, 0.8, 18.0)],
		["fb_statek", Vector3(83.0, 0.02, -1.2), Vector3(83.2, 1.3, -5.5)],
		["fb_garaz", Vector3(-34.0, 0.02, -5.5), Vector3(-34.0, 2.6, -10.5)],
		["fb_sklenik", Vector3(0.5, 0.02, 21.0), Vector3(6.0, 0.6, 25.0)],
		["fb_obchod_uvnitr", Vector3(-71.5, 0.27, -13.0), Vector3(-76.5, 1.0, -18.4)],
		["fb_mraky", Vector3(46.0, 0.0, -40.0), Vector3(80.0, 40.0, -60.0)],
		["fb_mraky_obzor", Vector3(46.0, 0.0, -40.0), Vector3(120.0, 12.0, -80.0)],
	]
	for v in views:
		var pos: Vector3 = v[1]
		if pos.y < 0.01:
			pos.y = world.terrain_h(pos.x, pos.z) + 0.05
		_look(player, pos, v[2])
		await _frames(25)
		await _shot(v[0])
	# tráva zblízka (louka) a ruka s hadrem
	var meadow := Vector3(44.0, 0.0, -38.0)
	meadow.y = world.terrain_h(meadow.x, meadow.z) + 0.05
	_look(player, meadow, meadow + Vector3(3.0, 0.4, 3.0))
	player.hold("rag_old")
	await _frames(25)
	await _shot("fb_trava_ruka")
	player.held.flash_left(GameState.spray_tool())
	await _frames(6)
	await _shot("fb_lahvicka_vlevo")
	_look(player, meadow, meadow + Vector3(2.0, -1.2, 2.0))
	await _frames(20)
	await _shot("fb_trava_dolu")

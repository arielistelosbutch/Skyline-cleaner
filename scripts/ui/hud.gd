class_name HUD
extends Control
## Minimalistické herní rozhraní: zaměřovač, nápověda interakce, peníze,
## úkol, panel čištění, ukazatel zkušeností a vybavení.

var player: Player

var _crosshair: Control
var _prompt: Label
var _money: Label
var _level: Label
var _xp_bar: ProgressBar
var _rep: Label
var _objective: Label
var _obj_head: Label
var tutorial: Tutorial
var _clean_panel: PanelContainer
var _clean_pct: Label
var _clean_bar: ProgressBar
var _clean_contract: Label
var _clean_tool: Label
var _hints: Label
var _equip: Label
var _hint_box: PanelContainer
var _hint_text: Label
var _hint_time := 0.0
var _shown_money := 0.0
var _target_money := 0
var _arrived := false


var _clock: Label


var nav: NavArrow
var _talent_hint: Label
var _talent_check := 0.0
var _talent_can := false
var _glow := 0.0
## Počet bodů, které hráč už „viděl" ve stromu talentů – svítí se jen na nové.
static var talents_seen := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.get_theme()

	_crosshair = Control.new()
	UITheme.place(_crosshair, Vector2(0.5, 0.5), Vector2.ZERO)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(func() -> void:
		_crosshair.draw_circle(Vector2.ZERO, 3.5, Color(0, 0, 0, 0.35))
		_crosshair.draw_circle(Vector2.ZERO, 2.2, Color(1, 1, 1, 0.9)))
	add_child(_crosshair)

	_prompt = UITheme.shadow_label("", 20)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.place(_prompt, Vector2(0.5, 0.5), Vector2(-400, 28), Vector2(800, 30))
	add_child(_prompt)

	# vpravo nahoře – peníze a úroveň
	var top_right := PanelContainer.new()
	top_right.add_theme_stylebox_override("panel", UITheme.box(Color(0.1, 0.13, 0.15, 0.55), 14, 16, 14))
	top_right.custom_minimum_size = Vector2(230, 0)
	UITheme.place(top_right, Vector2(1.0, 0.0), Vector2(-250, 20), Vector2(230, 0))
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(top_right)
	var tv := VBoxContainer.new()
	top_right.add_child(tv)
	_money = UITheme.label("", 26, Color(1.0, 0.86, 0.45))
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tv.add_child(_money)
	_level = UITheme.label("", 15, Color(0.88, 0.93, 0.95))
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tv.add_child(_level)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(0, 6)
	tv.add_child(_xp_bar)
	# svítí, jen když má hráč nerozdaný talentový bod a je ho kam dát; zhasne,
	# jakmile si otevře strom talentů (i když body nerozdá)
	_talent_hint = UITheme.label("★ Talentový bod  [T]", 16, Color(1.0, 0.85, 0.3), true)
	_talent_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_talent_hint.visible = false
	tv.add_child(_talent_hint)
	_rep = UITheme.label("", 15, Color(1.0, 0.86, 0.45))
	_rep.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tv.add_child(_rep)
	_clock = UITheme.label("", 14, Color(0.8, 0.88, 0.95))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tv.add_child(_clock)

	# vlevo nahoře – aktuální úkol
	var obj_panel := PanelContainer.new()
	obj_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.1, 0.13, 0.15, 0.5), 14, 16, 14))
	obj_panel.position = Vector2(20, 20)
	obj_panel.custom_minimum_size = Vector2(380, 0)
	add_child(obj_panel)
	var ov := VBoxContainer.new()
	obj_panel.add_child(ov)
	_obj_head = UITheme.label("ÚKOL", 13, Color(0.55, 0.85, 0.9))
	ov.add_child(_obj_head)
	_objective = UITheme.label("", 17, Color(0.95, 0.97, 0.97))
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(350, 0)
	ov.add_child(_objective)

	# vlevo dole – panel čištění
	_clean_panel = PanelContainer.new()
	_clean_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.97, 0.98, 0.97, 0.9), 16, 18, 16))
	_clean_panel.custom_minimum_size = Vector2(320, 0)
	UITheme.place(_clean_panel, Vector2(0.0, 1.0), Vector2(20, -230), Vector2(320, 0))
	_clean_panel.visible = false
	add_child(_clean_panel)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	_clean_panel.add_child(cv)
	_clean_pct = UITheme.label("Aktuální okno: 0 % čistoty", 19, UITheme.TEXT, true)
	cv.add_child(_clean_pct)
	_clean_bar = ProgressBar.new()
	_clean_bar.show_percentage = false
	_clean_bar.custom_minimum_size = Vector2(0, 12)
	_clean_bar.max_value = 100.0
	cv.add_child(_clean_bar)
	_clean_contract = UITheme.label("", 16, UITheme.TEXT_SOFT)
	cv.add_child(_clean_contract)
	_clean_tool = UITheme.label("", 16, UITheme.TEXT_SOFT)
	cv.add_child(_clean_tool)

	_hints = UITheme.shadow_label("", 16, Color(1, 1, 1, 0.92))
	_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.place(_hints, Vector2(0.5, 1.0), Vector2(-600, -46), Vector2(1200, 30))
	add_child(_hints)

	_equip = UITheme.shadow_label("", 17, Color(1, 1, 1, 0.95))
	_equip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.place(_equip, Vector2(1.0, 1.0), Vector2(-540, -110), Vector2(520, 52))
	# dlouhý text (název přípravku) roste doleva a nahoru, ne přes pravý okraj
	_equip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_equip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_equip)

	# nápověda k nečistotám a nástrojům (Events.cleaning_hint), nad panelem čištění
	_hint_box = PanelContainer.new()
	_hint_box.add_theme_stylebox_override("panel", UITheme.box(Color(0.1, 0.13, 0.15, 0.78), 14, 16, 12))
	UITheme.place(_hint_box, Vector2(0.0, 1.0), Vector2(20, -370), Vector2(420, 0))
	_hint_box.visible = false
	add_child(_hint_box)
	_hint_text = UITheme.label("", 16, Color(0.97, 0.95, 0.85))
	_hint_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_text.custom_minimum_size = Vector2(390, 0)
	_hint_box.add_child(_hint_text)
	Events.cleaning_hint.connect(func(text: String) -> void:
		_hint_text.text = text
		_hint_box.visible = true
		_hint_time = 6.0)

	# kompas se značkou zakázky (nahoře uprostřed, nad oznámeními)
	nav = NavArrow.new()
	nav.player = player
	UITheme.place(nav, Vector2(0.5, 0.0), Vector2(-NavArrow.WIDTH * 0.5, 10), Vector2(NavArrow.WIDTH, NavArrow.HEIGHT))
	add_child(nav)

	Events.money_changed.connect(func(v: int, _d: int) -> void: _target_money = v)
	Events.equipment_changed.connect(func(_id: String) -> void: _update_equip())
	Events.tank_changed.connect(func(_v: float, _c: float) -> void: _update_equip())
	Events.inventory_changed.connect(_update_equip)
	_target_money = GameState.money
	_shown_money = GameState.money


func _process(delta: float) -> void:
	if player == null:
		return
	# plynulé načítání peněz
	_shown_money = lerpf(_shown_money, _target_money, 1.0 - exp(-6.0 * delta))
	if absf(_shown_money - _target_money) < 0.5:
		_shown_money = _target_money
	_money.text = UITheme.money(int(round(_shown_money)))
	_level.text = "Úroveň %d  ·  %d / %d XP" % [GameState.level, GameState.xp, GameState.xp_to_next()]
	_xp_bar.max_value = GameState.xp_to_next()
	_xp_bar.value = GameState.xp
	_rep.text = "Pověst " + GameState.stars_text(GameState.stars())
	_update_talent_hint(delta)
	var parts: Array[String] = []
	if Settings.day_cycle:
		parts.append(Atmosphere.clock_text(GameState.clock))
	if Settings.seasons:
		parts.append(Atmosphere.SEASON_NAMES[int(fposmod((GameState.day + GameState.clock / 24.0) / Atmosphere.SEASON_DAYS, 4.0)) % 4])
	_clock.text = "Den %d  ·  %s" % [GameState.day + 1, "  ·  ".join(parts)] if not parts.is_empty() else ""

	if _hint_time > 0.0:
		_hint_time -= delta
		_hint_box.modulate.a = clampf(_hint_time, 0.0, 1.0)
		if _hint_time <= 0.0:
			_hint_box.visible = false
	var cleaning := player.mode == Player.Mode.CLEANING
	_crosshair.visible = not cleaning and not player.ui_open
	_prompt.text = player.get_prompt() if not player.ui_open else ""
	_clean_panel.visible = cleaning
	_equip.visible = not cleaning and player.carried == null
	if cleaning and player.cleaning.window:
		var w := player.cleaning.window
		var pct := int(floor(w.cleanliness() * 100.0))
		_clean_pct.text = "Aktuální okno: %d %% čistoty" % pct
		_clean_bar.value = lerpf(_clean_bar.value, w.cleanliness() * 100.0, 1.0 - exp(-10.0 * delta))
		var c := ContractManager.active()
		if c:
			var p := ContractManager.progress(c.id)
			_clean_contract.text = "Zakázka: %d / %d oken" % [p.x, p.y]
		else:
			_clean_contract.text = ""
		var spray := GameState.spray_tool()
		_clean_tool.text = "Nástroj: %s\nPřípravek: %s · nádržka %d / %d" % [player.cleaning.tool.display_name, spray.display_name if spray else "–", int(GameState.tank), int(GameState.tank_max())]
		if player.cleaning.tool.auto_dose > 0.0:
			_clean_tool.text += "\nNádržka stěrače: %d s (dávkuje sám při jízdě)" % int(ceilf(GameState.washer))
		var lmb := "[LMB] táhnout stěrku (dlouhé tahy)" if player.cleaning.tool.shape == "blade" else ("[LMB] přitlačit a jezdit (myje sám)" if player.cleaning.tool.spin > 0.0 else "[LMB] přitlačit a drhnout")
		_hints.text = "%s   ·   [F] nastříkat   ·   [kolečko] nástroj   ·   [Q] přípravek   ·   [A/D] posun   ·   [E] / [PTM] konec" % lmb
	elif player.carried is Ladder:
		_hints.text = "Neseš žebřík – podívej se na zeď a opři ho [E] / [LMB], pak na něj vylez [E]"
	elif player.carried is Bucket:
		_hints.text = "Neseš kbelík – postav ho k domu, kde myješ [E]. U sudu nebo kohoutku se sám naplní."
	elif player.carried:
		_hints.text = "Neseš židli – polož ji pod okno, pak na ni vyskoč [mezerník]"
	else:
		_hints.text = "[Tab] tablet   ·   [T] talenty   ·   [R] najít nářadí   ·   [P] fotorežim   ·   [Esc] menu"
	if tutorial and Tutorial.active():
		_obj_head.text = tutorial.header()
		_obj_head.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
		_objective.text = tutorial.text()
	else:
		_obj_head.text = "ÚKOL"
		_obj_head.add_theme_color_override("font_color", Color(0.55, 0.85, 0.9))
		_objective.text = _objective_text()


func _objective_text() -> String:
	var c := ContractManager.active()
	if c == null:
		var any_open := false
		for id in ContractManager.order:
			if ContractManager.state.get(id) != "completed":
				any_open = true
		if any_open:
			return "Otevři pracovní tablet [Tab] a přijmi zakázku."
		return "Všechny zakázky jsou hotové. V tabletu je můžeš přijmout znovu jako pravidelný úklid, nebo se podívej do obchodu s vybavením a do talentů."
	var target := Vector3(c.map_position.x, 0, c.map_position.y)
	var dist := player.global_position.distance_to(target)
	var p := ContractManager.progress(c.id)
	if dist > 16.0 and p.x == 0:
		_arrived = false
		return "Dojdi k domu: %s (%d m). Cestu ukazuje zlatá značka na kompasu nahoře." % [c.title, int(dist)]
	if not _arrived:
		_arrived = true
		Events.toast("Dorazil jsi na místo zakázky: %s" % c.title, "info")
	var tip := ""
	if p.x == 0:
		tip = "\nPodívej se zblízka na okno a stiskni [E]. Neumytá okna mají nad sebou žlutou značku ▼."
	else:
		tip = "\nZbývající okna ukazují žluté značky ▼ (vidíš je i přes zeď)."
	var left := PackedStringArray()
	for wid in c.window_ids:
		var ww := WindowRegistry.find_window(wid)
		if ww and not ww.completed:
			left.append(wid)
	var req := WindowAccess.requirement(left)
	if req["missing"]:
		tip += "\nNa %d %s zatím nedosáhneš (oranžová značka) – co je potřeba, je v tabletu." % [int(req["unreachable"]), "okno" if int(req["unreachable"]) == 1 else "oken"]
	return "Umyj okna – %s: %d / %d.%s" % [c.title, p.x, p.y, tip]


func _update_equip() -> void:
	if player == null:
		return
	var spray := GameState.spray_tool()
	var tank := "nádržka %d / %d" % [int(GameState.tank), int(GameState.tank_max())]
	if GameState.tank < 1.0:
		tank = "nádržka PRÁZDNÁ – doplň u vody"
	_equip.text = "V ruce: %s   [kolečko] přepnout\nPřípravek: %s (%s)   [Q] změnit" % [GameState.item_name(player.held_id), spray.display_name if spray else "–", tank]


func _update_talent_hint(delta: float) -> void:
	var pts := GameState.talent_points
	if pts < talents_seen:
		talents_seen = pts
	_talent_check -= delta
	if _talent_check <= 0.0:
		_talent_check = 0.5
		_talent_can = false
		if pts > talents_seen:
			for id in Talents.order:
				if Talents.unlock_problem(id) == "":
					_talent_can = true
					break
	_talent_hint.visible = _talent_can
	if _talent_can:
		_glow += delta
		_talent_hint.text = "★ Talentový bod k rozdělení: %d  [T]" % pts
		_talent_hint.modulate = Color(1, 1, 1, 0.7 + 0.3 * sin(_glow * 4.0))

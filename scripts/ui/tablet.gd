class_name Tablet
extends Control
## Pracovní tablet: zakázky, mapa, inventář, obchod (katalog), talenty, profil, historie.
## Sekce budoucích etap jsou viditelně označené jako „připravujeme".

var player: Player
var _content: VBoxContainer
var _nav: VBoxContainer
var _bezel: PanelContainer
var _header_money: Label
var _current := "zakazky"
var _shop_cat := "Nástroje"
## Zakázky: false = jen oblast, ve které hráč je (+ rozpracované), true = všechny oblasti.
var _all_areas := false

const SECTIONS := [
	["zakazky", "Zakázky", true],
	["inventar", "Inventář", true],
	["obchod", "Obchod", true],
	["talenty", "Talenty", true],
	["profil", "Profil a statistiky", true],
	["historie", "Historie prací", true],
	["firma", "Firma a dodávka", true],
	["roboti", "Roboti", true],
	["drony", "Drony", true],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.1, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var bezel := PanelContainer.new()
	_bezel = bezel
	bezel.add_theme_stylebox_override("panel", UITheme.box(Color(0.11, 0.13, 0.15), 34, 22, 22))
	bezel.custom_minimum_size = Vector2(1440, 800)
	center.add_child(bezel)
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", UITheme.box(Color(0.95, 0.96, 0.95), 18, 0, 0))
	bezel.add_child(screen)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	screen.add_child(root)

	var header := PanelContainer.new()
	var hsb := UITheme.box(UITheme.ACCENT, 18, 22, 18)
	hsb.corner_radius_bottom_left = 0
	hsb.corner_radius_bottom_right = 0
	header.add_theme_stylebox_override("panel", hsb)
	root.add_child(header)
	var hh := HBoxContainer.new()
	header.add_child(hh)
	hh.add_child(UITheme.label("Clear View  ·  Pracovní tablet", 22, Color.WHITE, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(spacer)
	_header_money = UITheme.label("", 20, Color(1.0, 0.92, 0.6))
	hh.add_child(_header_money)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	var navp := PanelContainer.new()
	navp.add_theme_stylebox_override("panel", UITheme.box(Color(0.9, 0.92, 0.92), 0, 14, 16))
	navp.custom_minimum_size = Vector2(240, 0)
	body.add_child(navp)
	_nav = VBoxContainer.new()
	_nav.add_theme_constant_override("separation", 6)
	navp.add_child(_nav)
	for s in SECTIONS:
		var b := Button.new()
		b.text = s[1] if s[2] else "%s  (brzy)" % s[1]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 42)
		b.set_meta("section", s[0])
		b.pressed.connect(_show.bind(s[0]))
		_nav.add_child(b)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nav.add_child(filler)
	_nav.add_child(UITheme.label("[Tab] / [Esc] zavřít", 14, UITheme.TEXT_SOFT))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	scroll.add_child(margin)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 14)
	margin.add_child(_content)

	Events.contract_changed.connect(func() -> void:
		if visible:
			_show(_current))
	Events.inventory_changed.connect(func() -> void:
		if visible:
			_show(_current))
	Talents.changed.connect(func() -> void:
		if visible:
			_refresh_nav())


func open() -> void:
	visible = true
	_show(_current)


func _show(section: String) -> void:
	_current = section
	_fit_bezel()
	_refresh_nav()
	for ch in _content.get_children():
		_content.remove_child(ch)
		ch.queue_free()
	_show_content(section)


## Tablet se vždy vejde na obrazovku (i na menších a širokých monitorech).
func _fit_bezel() -> void:
	if _bezel == null or not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	_bezel.custom_minimum_size = Vector2(minf(1440.0, vp.x - 40.0), minf(800.0, vp.y - 40.0))


func _refresh_nav() -> void:
	_header_money.text = "%s   ·   Úroveň %d" % [UITheme.money(GameState.money), GameState.level]
	var section := _current
	for b in _nav.get_children():
		if b is Button:
			var active: bool = b.get_meta("section", "") == section
			b.add_theme_stylebox_override("normal", UITheme.box(UITheme.ACCENT_DARK if active else Color(0.72, 0.78, 0.8), 10, 10, 14))
			if b.get_meta("section", "") == "talenty":
				# nevyužité talentové body jsou vidět přímo v menu
				b.text = "Talenty  ★ %d" % GameState.talent_points if GameState.talent_points > 0 else "Talenty"
				if GameState.talent_points > 0 and not active:
					b.add_theme_stylebox_override("normal", UITheme.box(UITheme.GOLD, 10, 10, 14))


func _show_content(section: String) -> void:
	match section:
		"zakazky":
			_contracts()
		"inventar":
			_inventory()
		"profil":
			_profile()
		"historie":
			_history()
		"obchod":
			_shop()
		"talenty":
			_talents()
		"roboti":
			_robots()
		"drony":
			_drones()
		"firma":
			_company()
		_:
			_coming_soon(section)


func _title(t: String) -> void:
	_content.add_child(UITheme.label(t, 28, UITheme.TEXT, true))


func _card() -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color.WHITE, 14, 22, 22, Color(0.85, 0.88, 0.88), 1))
	_content.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	return v


func _row(parent: Container, key: String, value: String) -> Label:
	var h := HBoxContainer.new()
	var k := UITheme.label(key, 16, UITheme.TEXT_SOFT)
	k.custom_minimum_size = Vector2(230, 0)
	h.add_child(k)
	var v := UITheme.label(value, 16)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	parent.add_child(h)
	return v


func _contracts() -> void:
	_title("Zakázky")
	_content.add_child(UITheme.label("Nabídky práce v okolí. Bez časových limitů – pracuj svým tempem. Bonus za rychlost je jen nepovinný.", 16, UITheme.TEXT_SOFT))
	var rp := GameState.rep_progress()
	var rep_txt := "Tvoje pověst: %s" % GameState.stars_text(GameState.stars())
	if rp.y > 0:
		rep_txt += "   (%d / %d bodů do další hvězdy)" % [rp.x, rp.y]
	_content.add_child(UITheme.label(rep_txt, 17, UITheme.ACCENT_DARK, true))
	_content.add_child(UITheme.label("Vyšší pověst = víc poptávek, náročnější a lépe placená práce a lepší vybavení v obchodě.", 15, UITheme.TEXT_SOFT))
	var here := current_area()
	var filt := HBoxContainer.new()
	filt.add_theme_constant_override("separation", 10)
	_content.add_child(filt)
	for opt: Array in [[false, "Jen tato oblast"], [true, "Všechny oblasti"]]:
		var fb := Button.new()
		fb.text = opt[1]
		fb.toggle_mode = true
		fb.button_pressed = _all_areas == opt[0]
		fb.custom_minimum_size = Vector2(200, 38)
		var val: bool = opt[0]
		fb.pressed.connect(func() -> void:
			_all_areas = val
			_show("zakazky"))
		filt.add_child(fb)
	var hidden := 0
	var ids: Array = []
	for id in ContractManager.order:
		if ContractManager.is_offer(id):
			continue
		if _shown_here(id, here):
			ids.append(id)
		else:
			hidden += 1
	ids.append("#vesnice")
	for id in ContractManager.order:
		if not ContractManager.is_offer(id):
			continue
		if _shown_here(id, here):
			ids.append(id)
		else:
			hidden += 1
	if not _all_areas:
		var note := "Ukazuji zakázky z oblasti: %s." % WorldMap.area_name(here)
		if hidden > 0:
			note += " Další nabídky v jiných oblastech: %d (tlačítko Všechny oblasti)." % hidden
		_content.add_child(UITheme.label(note, 15, UITheme.TEXT_SOFT))
	_content.add_child(UITheme.label("Stálé zakázky", 20, UITheme.ACCENT_DARK, true))
	for id in ids:
		if id == "#vesnice":
			_content.add_child(UITheme.label("Poptávky od zákazníků", 20, UITheme.ACCENT_DARK, true))
			_content.add_child(UITheme.label("Sousedé se ozývají sami. Po každé hotové práci přijde nová poptávka; s lepší pověstí jich je víc a jsou náročnější.", 15, UITheme.TEXT_SOFT))
			continue
		var c := ContractManager.get_contract(id)
		var st: String = ContractManager.state.get(id, "available")
		var locked := ContractManager.is_locked(id)
		var repeat := ContractManager.is_repeat(id) and st != "completed"
		var v := _card()
		var top := HBoxContainer.new()
		v.add_child(top)
		top.add_child(UITheme.label("Zakázka: " + c.title, 22, UITheme.TEXT_SOFT if locked else UITheme.TEXT, true))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(sp)
		var badge_text: String = {"available": "Nová nabídka", "active": "Probíhá", "paused": "Přerušeno", "completed": "Dokončeno ✓"}.get(st, st)
		var badge_col: Color = {"available": UITheme.GOLD, "active": UITheme.ACCENT, "paused": UITheme.WARN, "completed": UITheme.SUCCESS}.get(st, UITheme.ACCENT)
		if locked:
			badge_text = "Od úrovně %d" % c.required_level
			badge_col = Color(0.6, 0.63, 0.65)
		elif repeat and st == "available":
			badge_text = "Pravidelný úklid"
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", UITheme.box(badge_col, 10, 12, 8))
		badge.add_child(UITheme.label(badge_text, 15, Color.WHITE))
		top.add_child(badge)
		var desc := UITheme.label(c.description, 16, UITheme.TEXT_SOFT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(desc)
		_row(v, "Typ budovy", c.building_type)
		_row(v, "Lokalita", c.location)
		_row(v, "Počet oken", str(c.window_ids.size()))
		_row(v, "Znečištění", c.dirt_level_text + "  –  " + _dirt_kinds_text(c))
		var req := WindowAccess.requirement(c.window_ids)
		var rl := _row(v, "Nutné vybavení", req["text"])
		if req["missing"]:
			rl.add_theme_color_override("font_color", Color(0.78, 0.2, 0.15))
		_row(v, "Doporučené vybavení", c.recommended_equipment)
		var money_txt := UITheme.money(ContractManager.reward_money(id))
		if ContractManager.is_repeat(id) or st == "completed":
			money_txt += "  (pravidelný úklid: %d %% původní odměny)" % int(c.repeat_factor * 100.0)
		_row(v, "Odměna", money_txt)
		_row(v, "Zkušenosti", "%d XP (+%d XP za každé okno)" % [ContractManager.reward_xp(id), ContractManager.WINDOW_XP])
		var bonus := c.bonus_goal
		var left := ContractManager.bonus_time_left(id)
		if st == "active" or st == "paused":
			if left == INF:
				pass
			elif left > 0.0:
				bonus += "  Zbývá %d:%02d." % [int(left) / 60, int(left) % 60]
			else:
				bonus += "  Bonus propadl – nevadí, odměna zůstává."
		_row(v, "Bonusové cíle", bonus)
		if locked:
			v.add_child(UITheme.label("Zakázka se odemkne na úrovni %d. Zkušenosti získáš za každé umyté okno a dokončené zakázky." % c.required_level, 15, UITheme.TEXT_SOFT))
			continue
		var p := ContractManager.progress(id)
		var pb := ProgressBar.new()
		pb.max_value = maxi(1, p.y)
		pb.value = p.x
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 10)
		v.add_child(pb)
		v.add_child(UITheme.label("Hotovo: %d / %d oken" % [p.x, p.y], 15, UITheme.TEXT_SOFT))
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 10)
		v.add_child(buttons)
		match st:
			"available", "paused", "completed":
				var b := Button.new()
				b.text = {"available": "Přijmout zakázku", "paused": "Pokračovat v zakázce", "completed": "Přijmout znovu (pravidelný úklid)"}[st]
				b.custom_minimum_size = Vector2(300, 44)
				# nová zakázka zeleně, pokračování oranžově, opakovaný úklid modrofialově
				var bcol: Color = {"available": UITheme.SUCCESS, "paused": UITheme.WARN, "completed": Color(0.42, 0.48, 0.78)}[st]
				b.add_theme_stylebox_override("normal", UITheme.box(bcol, 10, 10, 14))
				b.add_theme_stylebox_override("hover", UITheme.box(bcol.lightened(0.12), 10, 10, 14))
				b.add_theme_stylebox_override("pressed", UITheme.box(bcol.darkened(0.12), 10, 10, 14))
				b.pressed.connect(func() -> void: ContractManager.accept(id))
				buttons.add_child(b)
				if st == "available" and ContractManager.is_offer(id):
					var d := Button.new()
					d.text = "Odmítnout"
					d.custom_minimum_size = Vector2(160, 44)
					d.add_theme_stylebox_override("normal", UITheme.box(Color(0.6, 0.62, 0.64), 10, 10, 14))
					d.pressed.connect(func() -> void: ContractManager.decline(id))
					buttons.add_child(d)
			"active":
				var b := Button.new()
				b.text = "Přerušit zakázku"
				b.custom_minimum_size = Vector2(240, 44)
				b.add_theme_stylebox_override("normal", UITheme.box(Color(0.6, 0.62, 0.64), 10, 10, 14))
				b.pressed.connect(func() -> void: ContractManager.pause_active())
				buttons.add_child(b)
				var hint := UITheme.label("Cestu k budově ukazuje kompas nahoře.", 15, UITheme.TEXT_SOFT)
				buttons.add_child(hint)
	var more := _card()
	more.add_child(UITheme.label("Další oblasti", 20, UITheme.TEXT, true))
	more.add_child(UITheme.label("Mezi oblastmi (Venkov, Předměstí, Město) jezdí autobus. Velkoměsto přijde v další etapě.", 16, UITheme.TEXT_SOFT))


## Oblast, ve které hráč právě je (id z WorldMap).
func current_area() -> String:
	if player == null:
		return WorldMap.DEFAULT_AREA
	return WorldMap.area_at(Vector2(player.global_position.x, player.global_position.z))


## Oblast zakázky podle její polohy na mapě.
static func contract_area(id: String) -> String:
	var c := ContractManager.get_contract(id)
	if c == null:
		return WorldMap.DEFAULT_AREA
	return WorldMap.area_at(c.map_position)


## Rozpracovaná zakázka se ukazuje vždy, ostatní jen z aktuální oblasti (pokud není zapnuto „Všechny").
func _shown_here(id: String, here: String) -> bool:
	if _all_areas:
		return true
	var st: String = ContractManager.state.get(id, "available")
	if st == "active" or st == "paused":
		return true
	return contract_area(id) == here


func _dirt_kinds_text(c: ContractData) -> String:
	var kinds := {}
	if c.dirt_profile_id != "" and ContractManager.state.get(c.id) == "available":
		for k in DirtProfile.kinds_of(c.dirt_profile_id):
			kinds[k] = true
	for wid in ([] if not kinds.is_empty() else c.window_ids):
		var w := WindowRegistry.find_window(wid)
		if w:
			for k in w.kinds_present():
				kinds[k] = true
	var names: Array[String] = []
	for k in DirtTypes.COUNT:
		if kinds.has(k):
			names.append(DirtTypes.name_of(k).to_lower())
	return ", ".join(names)


func _inventory() -> void:
	_title("Inventář")
	_content.add_child(UITheme.label("Ruční nástroje přepínáš kolečkem myši (i během mytí), přípravky klávesou [Q]. Nástřik je vždy [F].", 16, UITheme.TEXT_SOFT))
	for kind in ["rag", "spray"]:
		_content.add_child(UITheme.label("Ruční nástroje" if kind == "rag" else "Přípravky do rozprašovače", 20, UITheme.ACCENT_DARK, true))
		for t in GameState.owned_tools(kind):
			var v := _card()
			var h := HBoxContainer.new()
			v.add_child(h)
			h.add_child(UITheme.label(t.display_name, 20, UITheme.TEXT, true))
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(sp)
			var active := (GameState.active_wipe if kind == "rag" else GameState.active_spray) == t.id
			if active:
				h.add_child(UITheme.label("Vybráno ✓", 16, UITheme.SUCCESS, true))
			else:
				var b := Button.new()
				b.text = "Vybrat"
				b.custom_minimum_size = Vector2(140, 38)
				b.pressed.connect(func() -> void:
					if player:
						player.hold(t.id)
					else:
						GameState.set_active(t.id)
					_show("inventar"))
				h.add_child(b)
			var d := UITheme.label(t.description, 16, UITheme.TEXT_SOFT)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(d)
			v.add_child(UITheme.label(ShopPanel.tool_stats(t.id), 14, UITheme.ACCENT_DARK))
	_content.add_child(UITheme.label("Vybavení", 20, UITheme.ACCENT_DARK, true))
	for id in GameState.inventory:
		if GameState.get_tool(id):
			continue
		var info: Dictionary = GameState.ITEMS.get(id, {})
		var v := _card()
		var h := HBoxContainer.new()
		v.add_child(h)
		h.add_child(UITheme.label(info.get("name", id), 20, UITheme.TEXT, true))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		h.add_child(UITheme.label(info.get("category", ""), 15, UITheme.ACCENT_DARK))
		var d := UITheme.label(info.get("desc", ""), 16, UITheme.TEXT_SOFT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)


func _shop() -> void:
	_title("Obchod – katalog")
	var intro := UITheme.label("Nakupuje se osobně v obchodě s vybavením – Smíšené zboží na návsi a pobočky „Úklid & Výšky“ na Předměstí a ve městě. Tady si v klidu prohlédneš, co kde mají a za kolik.", 16, UITheme.TEXT_SOFT)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(intro)
	var cats := HBoxContainer.new()
	cats.add_theme_constant_override("separation", 8)
	_content.add_child(cats)
	for cat in Shop.CATEGORIES:
		var b := Button.new()
		b.text = cat
		b.custom_minimum_size = Vector2(0, 38)
		b.add_theme_stylebox_override("normal", UITheme.box(UITheme.ACCENT_DARK if cat == _shop_cat else Color(0.62, 0.7, 0.72), 10, 12, 14))
		b.pressed.connect(func() -> void:
			_shop_cat = cat
			_show("obchod"))
		cats.add_child(b)
	ShopPanel.build_catalog(_content, _shop_cat, false, Callable())


func _talents() -> void:
	# strom otevřen = upozornění v HUD zhasne (i když hráč body nerozdá)
	HUD.talents_seen = GameState.talent_points
	_title("Talenty  ·  [T]")
	var tree := TalentTree.new()
	_content.add_child(tree)


func _profile() -> void:
	_title("Profil a statistiky")
	var v := _card()
	v.add_child(UITheme.label("Úroveň %d – %s" % [GameState.level, GameState.level_title()], 22, UITheme.TEXT, true))
	var pb := ProgressBar.new()
	pb.max_value = GameState.xp_to_next()
	pb.value = GameState.xp
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 12)
	v.add_child(pb)
	_row(v, "Zkušenosti", "%d / %d XP" % [GameState.xp, GameState.xp_to_next()])
	_row(v, "Talentové body", "%d (utratíš je v sekci Talenty)" % GameState.talent_points)
	_row(v, "Pověst", "%s  (%d bodů)" % [GameState.stars_text(GameState.stars()), GameState.reputation])
	_row(v, "Peníze", UITheme.money(GameState.money))
	var s := _card()
	s.add_child(UITheme.label("Statistiky firmy", 20, UITheme.TEXT, true))
	_row(s, "Umytá okna", str(GameState.stats.get("windows_cleaned", 0)))
	_row(s, "Dokončené zakázky", str(GameState.stats.get("contracts_done", 0)))
	_row(s, "Celkem vyděláno", UITheme.money(int(GameState.stats.get("money_earned", 0))))
	_row(s, "Utraceno za vybavení", UITheme.money(int(GameState.stats.get("money_spent", 0))))
	var secs := int(GameState.stats.get("play_time", 0.0))
	_row(s, "Odehraný čas", "%d h %02d min" % [secs / 3600, (secs / 60) % 60])
	_row(s, "Okna umytá roboty", str(GameState.stats.get("robot_windows", 0)))
	_row(s, "Okna umytá drony", str(GameState.stats.get("drone_windows", 0)))
	var an: Array[String] = []
	for a in GameState.unlocked_areas:
		an.append({"venkov": "Venkov", "predmesti": "Předměstí", "mesto": "Město", "velkomesto": "Velkoměsto"}.get(a, str(a)))
	_row(s, "Odemčené oblasti", ", ".join(an))


func _company() -> void:
	_title("Firma a dodávka")
	var intro := UITheme.label("Vylepšení základny a dodávku koupíš v obchodě v kategorii Firma. Základna je garáž na návsi v Lipové Lhotě.", 16, UITheme.TEXT_SOFT)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(intro)
	# dodávka
	var v := _card()
	v.add_child(UITheme.label("Firemní dodávka", 22, UITheme.TEXT, true))
	if not GameState.has_item("company_van"):
		v.add_child(UITheme.label("Zatím nemáš. V obchodě za %s (od úrovně %d) – pak cestuješ odkudkoli, bez čekání na autobus." % [UITheme.money(Shop.price("company_van")), Shop.required_level("company_van")], 16, UITheme.TEXT_SOFT))
	else:
		v.add_child(UITheme.label("Kam pojedeme? Žebříky jedou na střeše, roboti ve stojanu na dodávce se nabíjejí i za jízdy.", 16, UITheme.TEXT_SOFT))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		for d: Array in [["zakladna", "Základna (garáž)", 1], ["venkov", "Náves – Lipová Lhota", 1], ["predmesti", "Předměstí – Javorov", Suburb.UNLOCK_LEVEL], ["mesto", "Město – Brodec", City.UNLOCK_LEVEL], ["velkomesto", "Velkoměsto – Horizont", Metropolis.UNLOCK_LEVEL]]:
			var b := Button.new()
			var dest: String = d[0]
			b.text = d[1] if GameState.level >= int(d[2]) else "%s (od úrovně %d)" % [d[1], int(d[2])]
			b.disabled = GameState.level < int(d[2])
			b.custom_minimum_size = Vector2(150, 44)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.pressed.connect(func() -> void:
				var world := get_tree().get_first_node_in_group("world")
				if world and player and world.van_travel(dest, player):
					get_tree().call_group("ui_root", "close_all"))
			row.add_child(b)
	# základna
	var z := _card()
	z.add_child(UITheme.label("Základna", 22, UITheme.TEXT, true))
	var lvl := "Garáž"
	if GameState.has_item("base_hall"):
		lvl = "Garáž s dílnou a firemní hala"
	elif GameState.has_item("base_workshop"):
		lvl = "Garáž s dílnou"
	_row(z, "Stav", lvl)
	_row(z, "Nabíjení robotů", "garáž %d×%s" % [int(GameState.charger_speed("zakladna")), ", hala 3×" if GameState.has_item("base_hall") else ""])
	_row(z, "Bonus k odměnám", "+5 % (firemní hala)" if GameState.has_item("base_hall") else "žádný (přinese firemní hala)")
	var nxt := ""
	if not GameState.has_item("base_workshop"):
		nxt = "Další krok: Dílna v garáži (%s) – rychlonabíječka 2× a vybavená dílna." % UITheme.money(Shop.price("base_workshop"))
	elif not GameState.has_item("base_hall"):
		nxt = "Další krok: Firemní hala (%s, od úrovně %d) – nástěnka zakázek, nabíjení 3×, odměny +5 %%." % [UITheme.money(Shop.price("base_hall")), Shop.required_level("base_hall")]
	else:
		nxt = "Základna je plně vybavená. Depo pro létající drony přibude v Etapě 6."
	var nl := UITheme.label(nxt, 15, UITheme.TEXT_SOFT)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	z.add_child(nl)
	_cosmetics_card()


## Vzhled firmy: lak dodávky, polep a pracovní oblečení. Koupená volba zůstává,
## přepínat se dá kdykoli zdarma.
func _cosmetics_card() -> void:
	var c := _card()
	c.add_child(UITheme.label("Vzhled firmy", 22, UITheme.TEXT, true))
	var info := UITheme.label("Čistě pro radost: kup si barvu jednou a pak přepínej, jak chceš.%s" % ("" if GameState.has_item("company_van") else " Lak a polep uvidíš, až budeš mít firemní dodávku."), 15, UITheme.TEXT_SOFT)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(info)
	for slot: String in Cosmetics.SLOTS:
		c.add_child(UITheme.label(Cosmetics.SLOTS[slot]["name"], 17, UITheme.TEXT, true))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		c.add_child(flow)
		var sel := Cosmetics.selected(slot)
		for id in Cosmetics.options(slot):
			var o: Array = Cosmetics.OPTIONS[id]
			var b := Button.new()
			b.custom_minimum_size = Vector2(150, 40)
			var swatch := Image.create(18, 18, false, Image.FORMAT_RGBA8)
			swatch.fill(o[3])
			b.icon = ImageTexture.create_from_image(swatch)
			if id == sel:
				b.text = "%s ✓" % o[1]
				b.disabled = true
			elif Cosmetics.owns(id):
				b.text = o[1]
			else:
				b.text = "%s · %s" % [o[1], UITheme.money(int(o[2]))]
				b.tooltip_text = "Koupit a použít"
			var pick: String = id
			b.pressed.connect(func() -> void:
				var err := Cosmetics.choose(pick)
				if err != "":
					Events.toast(err, "warn")
				else:
					Events.toast("Vzhled firmy: %s." % Cosmetics.OPTIONS[pick][1], "info")
				_show.call_deferred("firma"))
			flow.add_child(b)


func _robots() -> void:
	_title("Roboti na okna")
	var intro := UITheme.label("Firma = ty a tvoji roboti. Robota přiložíš na okno rozpracované zakázky [G], umyje ho sám a ty mezitím děláš jiné okno. Vybitého sundáš [E] a dáš nabít do stojanu – v garáži na základně a u poboček obchodu na Předměstí a ve Městě.", 16, UITheme.TEXT_SOFT)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(intro)
	var fleet := RobotFleet.get_fleet(self)
	if fleet == null or fleet.robots.is_empty():
		var v := _card()
		v.add_child(UITheme.label("Zatím nemáš žádného robota", 20, UITheme.TEXT, true))
		var parts: Array[String] = []
		for m in GameState.ROBOT_MODELS:
			parts.append("%s od úrovně %d a pověsti %s" % [GameState.item_name(m).replace("Robot na okna ", "Robot "), int(GameState.ITEMS[m]["level"]), GameState.stars_text(int(GameState.ITEMS[m]["rep"]))])
		var nl := UITheme.label("V obchodě (Technologie): " + ", ".join(parts) + ". Firma může mít až %d roboty." % GameState.MAX_ROBOTS, 16, UITheme.TEXT_SOFT)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(nl)
		return
	_content.add_child(UITheme.label("Roboti ve firmě: %d / %d. Slabší model vyměníš v obchodě za lepší – starý se započítá za polovinu ceny." % [GameState.robot_count(), GameState.MAX_ROBOTS], 16, UITheme.ACCENT_DARK, true))
	for r in fleet.list():
		var v := _card()
		v.add_child(UITheme.label(r.display_name(), 22, UITheme.TEXT, true))
		var pb := ProgressBar.new()
		pb.max_value = 100
		pb.value = r.battery * 100.0
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 10)
		v.add_child(pb)
		_row(v, "Stav", r.state_text())
		var where := "u tebe"
		if r.state != WindowRobot.State.BAG:
			where = WorldMap.area_name(r.area_id())
			if r.state == WindowRobot.State.CHARGING:
				where = "nabíjecí stojan – " + ("garáž na základně" if r.charger_id == "zakladna" else "pobočka obchodu") + " (" + where + ")"
			if r.window:
				var c := ContractManager.contract_for_window(r.window.window_id)
				if c:
					where += " – " + c.title
		_row(v, "Kde je", where)
		_row(v, "Výdrž / nabití", "asi %d s práce, plně nabitý za %d s" % [int(r.work_time()), int(r.charge_time())])
	var rv := _card()
	if fleet.can_recall():
		var b := Button.new()
		b.text = "Přivolat všechny roboty k sobě"
		b.custom_minimum_size = Vector2(340, 44)
		b.pressed.connect(func() -> void:
			fleet.recall_all()
			_show("roboti"))
		rv.add_child(b)
	else:
		rv.add_child(UITheme.label("S talentem Dálkové přivolání (strom Robotika) přivoláš roboty odsud odkudkoli.", 15, UITheme.TEXT_SOFT))


func _drones() -> void:
	_title("Drony a depo")
	var intro := UITheme.label("Drony startují z depa na náměstí ve Velkoměstě Horizont. S autopilotem samy létají k oknům rozpracované zakázky ve Velkoměstě – nejdřív k nejvyšším patrům – a když jim dochází baterie, vrátí se nabít a pak pokračují. Ty mezitím myješ nižší patra nebo jedeš plošinou. Dron jde v obchodě (Technologie) prodat nebo vyměnit za lepší model – starý vezmou za polovinu ceny.", 16, UITheme.TEXT_SOFT)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(intro)
	var depot := DroneDepot.get_depot(self)
	if depot == null or not depot.owned():
		var v := _card()
		v.add_child(UITheme.label("Zatím nemáš depo dronů", 20, UITheme.TEXT, true))
		var nl := UITheme.label("V obchodě (Technologie) si pronajmeš depo (od úrovně %d) a pak koupíš drony: Vážka, Albatros a Sokol (až 3 drony)." % int(GameState.ITEMS[DroneDepot.DEPOT_ITEM]["level"]), 16, UITheme.TEXT_SOFT)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(nl)
		return
	var cv := _card()
	cv.add_child(UITheme.label("Depo – náměstí Horizont", 22, UITheme.TEXT, true))
	_row(cv, "Stav", depot.status_line())
	var c := ContractManager.active()
	var job := "žádná rozpracovaná zakázka – drony čekají"
	if c:
		job = c.title
		if contract_area(c.id) != depot.area_id:
			job += " (není ve Velkoměstě – drony na ni nepoletí)"
	_row(cv, "Pracují na", job)
	if not depot.skipped.is_empty():
		_row(cv, "Nechaly tobě", "%d oken se silnou špínou – dočisti je ručně" % depot.skipped.size())
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	cv.add_child(hb)
	var ab := Button.new()
	ab.text = "Vypnout autopilot (drony domů)" if depot.autopilot else "Zapnout autopilot"
	ab.custom_minimum_size = Vector2(320, 44)
	ab.pressed.connect(func() -> void:
		depot.set_autopilot(not depot.autopilot)
		_show("drony"))
	hb.add_child(ab)
	if not depot.skipped.is_empty():
		var rb := Button.new()
		rb.text = "Zkusit vynechaná okna znovu"
		rb.custom_minimum_size = Vector2(300, 44)
		rb.pressed.connect(func() -> void:
			depot.skipped.clear()
			_show("drony"))
		hb.add_child(rb)
	if depot.drones.is_empty():
		var v := _card()
		v.add_child(UITheme.label("V depu zatím není žádný dron – koupíš ho v obchodě (Technologie).", 17, UITheme.TEXT_SOFT))
		return
	for d in depot.drones:
		var v := _card()
		v.add_child(UITheme.label(d.display_name(), 22, UITheme.TEXT, true))
		var pb := ProgressBar.new()
		pb.max_value = 100
		pb.value = d.battery * 100.0
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 10)
		v.add_child(pb)
		_row(v, "Stav", d.state_text())
		_row(v, "Výdrž / nabití", "asi %d s práce, plně nabitý za %d s, let %.0f m/s" % [int(d.work_time()), int(d.charge_time()), d.fly_speed()])


func _history() -> void:
	_title("Historie prací")
	if GameState.history.is_empty():
		_content.add_child(UITheme.label("Zatím žádná dokončená zakázka.", 17, UITheme.TEXT_SOFT))
		return
	for i in range(GameState.history.size() - 1, -1, -1):
		var h: Dictionary = GameState.history[i]
		var v := _card()
		v.add_child(UITheme.label(str(h.get("title", "")), 20, UITheme.TEXT, true))
		_row(v, "Lokalita", str(h.get("location", "")))
		_row(v, "Okna", str(h.get("windows", "")))
		var earn := "%s  ·  %d XP" % [UITheme.money(int(h.get("money", 0))), int(h.get("xp", 0))]
		if int(h.get("bonus", 0)) > 0:
			earn += "  (včetně bonusu %s)" % UITheme.money(int(h.get("bonus", 0)))
		_row(v, "Výdělek", earn)
		if h.has("minutes"):
			_row(v, "Doba práce", "%d min" % int(h["minutes"]))
		_row(v, "Dokončeno", str(h.get("date", "")))


func _coming_soon(section: String) -> void:
	var names := {"drony": "Drony"}
	var stage := {"obchod": 2, "talenty": 2, "drony": 6}
	_title(names.get(section, section))
	var v := _card()
	v.add_child(UITheme.label("Připravujeme", 22, UITheme.TEXT, true))
	var l := UITheme.label("Tato sekce zatím není implementovaná. Plánovaná je v Etapě %d vývoje." % stage.get(section, 2), 17, UITheme.TEXT_SOFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)

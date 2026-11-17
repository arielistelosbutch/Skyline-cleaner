class_name ShopPanel
extends Control
## Obchod „Smíšené zboží" na návsi: kategorie, karty zboží, nákup.
## Stejný katalog (jen k prohlížení) ukazuje i pracovní tablet.

var _content: VBoxContainer
var _cats: HBoxContainer
var _money: Label
var _title: Label
var _subtitle: Label
var _category := "Nástroje"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.1, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.97, 0.96, 0.92), 20, 26, 22))
	panel.custom_minimum_size = Vector2(1080, 700)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var titles := VBoxContainer.new()
	head.add_child(titles)
	_title = UITheme.label("Smíšené zboží – vybavení na mytí oken", 28, UITheme.TEXT, true)
	titles.add_child(_title)
	_subtitle = UITheme.label("„Dobrý nástroj je půlka práce,“ říká paní vedoucí.", 15, UITheme.TEXT_SOFT)
	titles.add_child(_subtitle)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_money = UITheme.label("", 24, Color(0.75, 0.55, 0.1), true)
	head.add_child(_money)
	_cats = HBoxContainer.new()
	_cats.add_theme_constant_override("separation", 8)
	root.add_child(_cats)
	for cat in Shop.CATEGORIES:
		var b := Button.new()
		b.text = cat
		b.custom_minimum_size = Vector2(0, 40)
		b.set_meta("cat", cat)
		b.pressed.connect(func() -> void:
			_category = cat
			refresh())
		_cats.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	root.add_child(UITheme.label("[E] / [Esc] odejít z obchodu", 14, UITheme.TEXT_SOFT))
	Events.money_changed.connect(func(_v: int, _d: int) -> void:
		if visible:
			refresh())


## `store` = název obchodu (prázdný = Smíšené zboží na návsi); sortiment je všude stejný.
func open(store: String = "") -> void:
	if store == "":
		_title.text = "Smíšené zboží – vybavení na mytí oken"
		_subtitle.text = "„Dobrý nástroj je půlka práce,“ říká paní vedoucí."
	else:
		_title.text = store + " – vybavení na mytí oken"
		_subtitle.text = "Pobočka – stejný sortiment i ceny jako Smíšené zboží na návsi."
	visible = true
	refresh()


func refresh() -> void:
	_money.text = UITheme.money(GameState.money)
	for b in _cats.get_children():
		var active: bool = b.get_meta("cat", "") == _category
		b.add_theme_stylebox_override("normal", UITheme.box(UITheme.ACCENT_DARK if active else Color(0.62, 0.7, 0.72), 10, 12, 14))
	for ch in _content.get_children():
		_content.remove_child(ch)
		ch.queue_free()
	build_catalog(_content, _category, true, refresh)


## Karty zboží jedné kategorie. can_buy = false → jen katalog (tablet).
static func build_catalog(parent: VBoxContainer, category: String, can_buy: bool, on_change: Callable) -> void:
	var items := Shop.catalog(category)
	for it in items:
		var id: String = it["id"]
		var card := PanelContainer.new()
		var robot := GameState.is_robot(id)
		var owned := GameState.has_item(id) and not robot
		card.add_theme_stylebox_override("panel", UITheme.box(Color(0.93, 0.97, 0.93) if owned else Color.WHITE, 14, 20, 18, Color(0.85, 0.88, 0.88), 1))
		parent.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		card.add_child(h)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UITheme.label(it["name"], 20, UITheme.TEXT, true))
		var d := UITheme.label(it["desc"], 15, UITheme.TEXT_SOFT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		var stats := tool_stats(id)
		if stats != "":
			var sl := UITheme.label(stats, 14, UITheme.ACCENT_DARK)
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(sl)
		var right := VBoxContainer.new()
		right.custom_minimum_size = Vector2(210, 0)
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(right)
		var price_txt := UITheme.money(int(it["price"]))
		if int(it["price"]) != int(it["base_price"]):
			price_txt += "  (sleva)"
		var pl := UITheme.label(price_txt, 20, Color(0.7, 0.5, 0.1), true)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(pl)
		if int(it["level"]) > 1:
			var ll := UITheme.label("od úrovně %d" % int(it["level"]), 14, UITheme.TEXT_SOFT)
			ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(ll)
		if int(it.get("rep", 1)) > 1:
			var rl := UITheme.label("od pověsti %s" % GameState.stars_text(int(it["rep"])), 14, UITheme.TEXT_SOFT if GameState.stars() >= int(it["rep"]) else UITheme.WARN)
			rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(rl)
		if robot:
			var cl := UITheme.label("máš %d× · ve firmě %d / %d" % [GameState.robot_count(id), GameState.robot_count(), GameState.MAX_ROBOTS], 14, UITheme.SUCCESS if GameState.robot_count(id) > 0 else UITheme.TEXT_SOFT)
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(cl)
		var drone := Shop.drone_tier(id) >= 0
		if owned:
			var ol := UITheme.label("Vlastníš ✓", 16, UITheme.SUCCESS, true)
			ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(ol)
			if drone and can_buy:
				var sb := Button.new()
				sb.text = "Prodat za %s" % UITheme.money(Shop.trade_in(id))
				sb.custom_minimum_size = Vector2(200, 42)
				sb.pressed.connect(func() -> void:
					Shop.sell_drone(id)
					if on_change.is_valid():
						on_change.call())
				right.add_child(sb)
		elif can_buy:
			var problem := Shop.buy_problem(id)
			var b := Button.new()
			b.text = "Koupit" if problem == "" else problem
			b.disabled = problem != ""
			b.custom_minimum_size = Vector2(200, 42)
			b.pressed.connect(func() -> void:
				Shop.buy(id)
				if on_change.is_valid():
					on_change.call())
			right.add_child(b)
			if robot and Shop.weakest_below(id) >= 0:
				var oi := Shop.weakest_below(id)
				var up_problem := Shop.upgrade_problem(id)
				var ub := Button.new()
				ub.text = "Vyměnit za %s (doplatíš %s)" % [GameState.item_name(GameState.robot_units[oi]).replace("Robot na okna ", ""), UITheme.money(Shop.upgrade_cost(oi, id))] if up_problem == "" else up_problem
				ub.disabled = up_problem != ""
				ub.custom_minimum_size = Vector2(200, 42)
				ub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				ub.pressed.connect(func() -> void:
					Shop.upgrade_robot(id)
					if on_change.is_valid():
						on_change.call())
				right.add_child(ub)
			if drone and Shop.weakest_drone_below(id) != "":
				var od := Shop.weakest_drone_below(id)
				var dp := Shop.drone_upgrade_problem(id)
				var db := Button.new()
				db.text = "Vyměnit za %s (doplatíš %s)" % [GameState.item_name(od).replace("Dron ", ""), UITheme.money(Shop.drone_upgrade_cost(od, id))] if dp == "" else dp
				db.disabled = dp != ""
				db.custom_minimum_size = Vector2(200, 42)
				db.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				db.pressed.connect(func() -> void:
					Shop.upgrade_drone(id)
					if on_change.is_valid():
						on_change.call())
				right.add_child(db)
	for c in Shop.coming(category):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UITheme.box(Color(0.92, 0.93, 0.93), 14, 20, 12))
		parent.add_child(card)
		var h := HBoxContainer.new()
		card.add_child(h)
		var n := UITheme.label(c["name"], 17, Color(0.5, 0.54, 0.56))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(UITheme.label("připravujeme – Etapa %d" % int(c["stage"]), 14, Color(0.5, 0.54, 0.56)))
	if items.is_empty() and Shop.coming(category).is_empty():
		parent.add_child(UITheme.label("V této kategorii zatím nic není.", 16, UITheme.TEXT_SOFT))


## Krátký přehled herních hodnot nástroje (aby bylo vidět, co předmět skutečně dělá).
static func tool_stats(id: String) -> String:
	var t := GameState.get_tool(id)
	if t == null:
		return ""
	if t.kind == "spray":
		return "Nástřik %d cm  ·  na mastnotu %d %%  ·  rozpouštění ×%.1f  ·  vydrží mokré ×%.1f" % [int(t.spray_radius * 200.0), int(t.grease_power * 100.0), t.dissolve, 1.0 / maxf(t.evaporation, 0.1)]
	if t.shape == "blade":
		return "Záběr %d cm  ·  síla %.0f  ·  jen na mokré sklo  ·  bonus za dlouhý tah" % [int(t.blade_width * 100.0), t.strength]
	var extra := "  ·  roztírá vodu a přípravek" if t.spreads > 0.0 else ""
	if t.spin > 0.0:
		extra += "  ·  točí se a myje sám"
	if t.reach_bonus > 0.0:
		extra += "  ·  dosah +%.1f m" % t.reach_bonus
	return "Záběr %d cm  ·  síla tahu %.1f  ·  na odolnou špínu %s%s" % [int(t.radius * 200.0), t.strength, "dobře" if t.tough_penalty <= 4.5 else "slabě", extra]

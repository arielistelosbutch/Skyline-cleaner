class_name SettingsPanel
extends VBoxContainer
## Ovládací prvky nastavení (sdílené pauzou i hlavním menu).

signal closed


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	add_child(UITheme.label("Nastavení", 28, UITheme.TEXT, true))
	_slider("Citlivost myši (rozhlížení)", 0.0008, 0.006, Settings.mouse_sensitivity, func(v: float) -> void: Settings.mouse_sensitivity = v)
	_slider("Citlivost hadru při čištění", 0.4, 2.5, Settings.clean_sensitivity, func(v: float) -> void: Settings.clean_sensitivity = v)
	_slider("Hlasitost", 0.0, 1.0, Settings.master_volume, func(v: float) -> void:
		Settings.master_volume = v
		Settings.apply())
	_slider("Zorné pole (FOV)", 60.0, 95.0, Settings.fov, func(v: float) -> void:
		Settings.fov = v
		Settings.apply())
	var cb := CheckBox.new()
	cb.text = "Jemné pohupování kamery při chůzi"
	cb.button_pressed = Settings.head_bob
	cb.toggled.connect(func(on: bool) -> void: Settings.head_bob = on)
	add_child(cb)
	var cbw := CheckBox.new()
	cbw.text = "Občas přijde bouřka (ušpiní okna, přinese poptávky)"
	cbw.button_pressed = Settings.weather_events
	cbw.toggled.connect(func(on: bool) -> void: Settings.weather_events = on)
	add_child(cbw)
	var cbb := CheckBox.new()
	cbb.text = "Ptáci občas kápnou na rozdělané okno"
	cbb.button_pressed = Settings.bird_droppings
	cbb.toggled.connect(func(on: bool) -> void: Settings.bird_droppings = on)
	add_child(cbb)
	var cbd := CheckBox.new()
	cbd.text = "Střídá se den a noc (večer se rozsvítí okna)"
	cbd.button_pressed = Settings.day_cycle
	cbd.toggled.connect(func(on: bool) -> void: Settings.day_cycle = on)
	add_child(cbd)
	var cbs := CheckBox.new()
	cbs.text = "Střídají se roční období (jaro, léto, podzim, zima)"
	cbs.button_pressed = Settings.seasons
	cbs.toggled.connect(func(on: bool) -> void: Settings.seasons = on)
	add_child(cbs)
	add_child(UITheme.label("Grafika", 18, UITheme.TEXT, true))
	var aa_row := HBoxContainer.new()
	aa_row.add_theme_constant_override("separation", 10)
	aa_row.add_child(UITheme.label("Vyhlazování hran", 16, UITheme.TEXT_SOFT))
	var aa := OptionButton.new()
	for n in Settings.AA_NAMES:
		aa.add_item(n)
	aa.selected = Settings.aa_mode
	aa.item_selected.connect(func(i: int) -> void:
		Settings.aa_mode = i
		Settings.apply_graphics())
	aa_row.add_child(aa)
	add_child(aa_row)
	_slider("Rozlišení 3D (méně = plynulejší na slabším PC)", 0.5, 1.0, Settings.render_scale, func(v: float) -> void:
		Settings.render_scale = v
		Settings.apply_graphics())
	var cbf := CheckBox.new()
	cbf.text = "Celá obrazovka"
	cbf.button_pressed = Settings.fullscreen
	cbf.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply_graphics())
	add_child(cbf)
	var back := Button.new()
	back.text = "Zpět"
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(func() -> void:
		Settings.save_settings()
		closed.emit())
	add_child(back)


func _slider(title: String, lo: float, hi: float, value: float, cb: Callable) -> void:
	var l := UITheme.label(title, 16, UITheme.TEXT_SOFT)
	add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	s.custom_minimum_size = Vector2(380, 24)
	s.value_changed.connect(cb)
	add_child(s)

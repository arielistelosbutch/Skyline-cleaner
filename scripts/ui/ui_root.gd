class_name UIRoot
extends CanvasLayer
## Kořen UI: HUD, oznámení, tablet, mapa, pauza a hlavní menu.
## Řídí, kdy je kurzor volný a kdy hráč nereaguje na vstup.

signal start_requested(load_save: bool)

var player: Player
var hud: HUD
var notifications: Notifications
var tablet: Tablet
var shop: ShopPanel
var pause_menu: Control
var main_menu: Control
var _pause_box: VBoxContainer
var _settings: SettingsPanel
var _in_menu := true


var _screen: Control


func _ready() -> void:
	add_to_group("ui_root")
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Jeden kořenový Control s ručně nastavenou velikostí obrazovky –
	# všechny panely se pak spolehlivě kotví vůči němu.
	_screen = Control.new()
	_screen.name = "Screen"
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	_fit_screen()
	get_viewport().size_changed.connect(_fit_screen)
	hud = HUD.new()
	hud.player = player
	hud.visible = false
	_screen.add_child(hud)
	notifications = Notifications.new()
	_screen.add_child(notifications)
	tablet = Tablet.new()
	tablet.player = player
	_screen.add_child(tablet)
	shop = ShopPanel.new()
	_screen.add_child(shop)
	_build_pause()
	_build_main_menu()


func _fit_screen() -> void:
	_screen.position = Vector2.ZERO
	_screen.size = get_viewport().get_visible_rect().size


func _build_pause() -> void:
	pause_menu = Control.new()
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.theme = UITheme.get_theme()
	pause_menu.visible = false
	_screen.add_child(pause_menu)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.1, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, 20, 34, 30))
	p.custom_minimum_size = Vector2(440, 0)
	center.add_child(p)
	var stack := VBoxContainer.new()
	p.add_child(stack)
	_pause_box = VBoxContainer.new()
	_pause_box.add_theme_constant_override("separation", 12)
	stack.add_child(_pause_box)
	_pause_box.add_child(UITheme.label("Pauza", 32, UITheme.TEXT, true))
	_btn(_pause_box, "Pokračovat", close_all)
	_btn(_pause_box, "Uložit hru  [F5]", func() -> void: SaveManager.save_game())
	_btn(_pause_box, "Načíst poslední uloženou hru  [F9]", _quick_load)
	var skip_btn := _btn(_pause_box, "Přeskočit tutoriál", func() -> void:
		for t in get_tree().get_nodes_in_group("tutorial"):
			t.skip()
		close_all())
	_pause_box.visibility_changed.connect(func() -> void: skip_btn.visible = Tutorial.active())
	pause_menu.visibility_changed.connect(func() -> void: skip_btn.visible = Tutorial.active())
	_btn(_pause_box, "Nastavení", func() -> void:
		_pause_box.visible = false
		_settings.visible = true)
	_btn(_pause_box, "Uložit a ukončit hru", func() -> void:
		SaveManager.save_game(true)
		get_tree().quit())
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_pause_box.visible = true
		if player:
			player.camera.fov = Settings.fov)
	stack.add_child(_settings)


func _build_main_menu() -> void:
	main_menu = Control.new()
	main_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_menu.theme = UITheme.get_theme()
	_screen.add_child(main_menu)
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.12, 0.16, 0.78))
	g.set_color(1, Color(0.05, 0.12, 0.16, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	grad.offset_right = 900
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	main_menu.add_child(grad)
	var v := VBoxContainer.new()
	v.position = Vector2(90, 170)
	v.add_theme_constant_override("separation", 14)
	main_menu.add_child(v)
	v.add_child(UITheme.shadow_label("Clear View", 76, Color.WHITE))
	v.add_child(UITheme.shadow_label("Window Cleaning Simulator", 26, Color(0.8, 0.95, 0.97)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	v.add_child(gap)
	var cont := _btn(v, "Pokračovat", func() -> void: start_requested.emit(true))
	cont.disabled = not SaveManager.has_save()
	_btn(v, "Nová hra", func() -> void: start_requested.emit(false))
	var settings_btn := _btn(v, "Nastavení", Callable())
	_btn(v, "Ukončit", func() -> void: get_tree().quit())
	var menu_settings := SettingsPanel.new()
	menu_settings.visible = false
	var sp := PanelContainer.new()
	sp.position = Vector2(560, 50)
	sp.visible = false
	sp.add_child(menu_settings)
	main_menu.add_child(sp)
	settings_btn.pressed.connect(func() -> void:
		sp.visible = not sp.visible
		menu_settings.visible = sp.visible)
	menu_settings.closed.connect(func() -> void: sp.visible = false)
	var foot := UITheme.shadow_label("Etapa 2 – nástroje, obchod, talenty a nové zakázky  ·  Godot 4", 15, Color(1, 1, 1, 0.75))
	UITheme.place(foot, Vector2(0.0, 1.0), Vector2(90, -50), Vector2(700, 30))
	main_menu.add_child(foot)
	for b in v.get_children():
		if b is Button:
			b.custom_minimum_size = Vector2(320, 52)
			b.add_theme_font_size_override("font_size", 22)


func _btn(parent: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	if cb.is_valid():
		b.pressed.connect(func() -> void:
			Audio.play("click")
			cb.call())
	parent.add_child(b)
	return b


# ------------------------------------------------------------------ stavy

func show_main_menu() -> void:
	_in_menu = true
	main_menu.visible = true
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player.ui_open = true


func enter_game() -> void:
	_in_menu = false
	main_menu.visible = false
	hud.visible = true
	close_all()


func any_open() -> bool:
	return tablet.visible or pause_menu.visible or shop.visible


func close_all() -> void:
	tablet.visible = false
	pause_menu.visible = false
	shop.visible = false
	_settings.visible = false
	_pause_box.visible = true
	get_tree().paused = false
	if not _in_menu:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if player:
			player.ui_open = false


func _open(panel: Control, pause: bool = false) -> void:
	close_all()
	panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player.ui_open = true
	if pause:
		get_tree().paused = true


func open_tablet() -> void:
	if _in_menu:
		return
	if player and player.mode == Player.Mode.CLEANING:
		player.end_cleaning()
	_open(tablet)
	tablet.open()
	Audio.play("click", -4.0, 0.9)


## Otevře tablet rovnou na sekci (dodávka → „firma", nástěnka v hale → všechny zakázky).
func open_tablet_section(section: String) -> void:
	if _in_menu:
		return
	open_tablet()
	if section == "zakazky_vse":
		tablet._all_areas = true
		section = "zakazky"
	tablet._show(section)


func open_shop(store: String = "") -> void:
	if _in_menu:
		return
	_open(shop)
	shop.open(store)
	Events.tutorial_event.emit("shop")
	Audio.play("click", -4.0, 0.8)


func _quick_load() -> void:
	if SaveManager.has_save():
		SaveManager.reload_and_load()
	else:
		Events.toast("Zatím nemáš žádnou uloženou hru.", "warn")


func _input(event: InputEvent) -> void:
	if _in_menu:
		return
	if shop.visible and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close_all()
		return
	if event.is_action_pressed("tablet"):
		get_viewport().set_input_as_handled()
		if tablet.visible:
			close_all()
		else:
			open_tablet()
	elif event.is_action_pressed("talents"):
		# [T] = rovnou talenty v tabletu (nákup talentu bez proklikávání)
		get_viewport().set_input_as_handled()
		if tablet.visible and tablet._current == "talenty":
			close_all()
		else:
			notifications.hide_level_card()
			open_tablet_section("talenty")
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if any_open():
			close_all()
		else:
			_open(pause_menu, true)
	elif event.is_action_pressed("quick_save"):
		get_viewport().set_input_as_handled()
		SaveManager.save_game()
	elif event.is_action_pressed("quick_load"):
		get_viewport().set_input_as_handled()
		_quick_load()


func _notification(what: int) -> void:
	# Při ztrátě fokusu okna hru zapauzujeme, ať hráč nepřijde o kurzor.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _in_menu and not any_open():
		_open(pause_menu, true)

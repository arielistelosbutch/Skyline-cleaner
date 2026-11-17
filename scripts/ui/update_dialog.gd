class_name UpdateDialog
extends Control
## Okno „Je tu nová verze" (s tlačítkem Aktualizovat) a „Co je nového" po aktualizaci.

signal dismissed

var _title: Label
var _notes: RichTextLabel
var _progress: ProgressBar
var _status: Label
var _buttons: HBoxContainer
var _primary: Button
var _secondary: Button
var _mode := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.1, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, 20, 34, 30))
	p.custom_minimum_size = Vector2(680, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	_title = UITheme.label("", 30, UITheme.TEXT, true)
	v.add_child(_title)
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = true
	_notes.fit_content = true
	_notes.scroll_active = false
	_notes.add_theme_color_override("default_color", UITheme.TEXT)
	_notes.add_theme_font_size_override("normal_font_size", 18)
	_notes.add_theme_font_size_override("bold_font_size", 18)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(612, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_notes)
	v.add_child(scroll)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 22)
	_progress.max_value = 1.0
	_progress.step = 0.001
	_progress.visible = false
	v.add_child(_progress)
	_status = UITheme.label("", 16, UITheme.TEXT_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	v.add_child(_status)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(_buttons)
	_secondary = Button.new()
	_secondary.custom_minimum_size = Vector2(160, 48)
	_secondary.pressed.connect(_on_secondary)
	_buttons.add_child(_secondary)
	_primary = Button.new()
	_primary.custom_minimum_size = Vector2(220, 48)
	_primary.pressed.connect(_on_primary)
	_buttons.add_child(_primary)
	Updater.download_progress.connect(func(r: float) -> void:
		_progress.value = r
		_status.text = "Stahuji novou verzi… %d %%" % roundi(r * 100.0))
	Updater.install_failed.connect(func(msg: String) -> void:
		if _mode != "update":
			return
		_progress.visible = false
		_status.text = msg
		_buttons.visible = true
		_primary.visible = false
		_secondary.text = "Zavřít")


## Nabídka aktualizace na novou verzi.
func show_update(info: Dictionary) -> void:
	_mode = "update"
	_title.text = "Vyšla nová verze %s" % info.version
	var intro := "Máš verzi %s. Aktualizace se stáhne a hra se sama znovu spustí, uložená hra zůstane.\n\n" % Updater.current_version()
	if not Updater.can_self_install():
		intro = "Máš verzi %s. Novou verzi stáhneš ze stránky hry.\n\n" % Updater.current_version()
	_notes.text = intro + "[b]Co je nového:[/b]\n" + Updater.markdown_to_bbcode(info.notes if info.notes != "" else "Bez popisu.")
	_primary.text = "Aktualizovat teď" if Updater.can_self_install() else "Otevřít stránku hry"
	_primary.visible = true
	_secondary.text = "Později"
	_secondary.visible = true
	_buttons.visible = true
	_progress.visible = false
	_status.visible = false
	_open()


## Okno s novinkami po spuštění nové verze.
func show_whats_new(version: String, notes: String) -> void:
	_mode = "whats_new"
	_title.text = "Co je nového ve verzi %s" % version
	_notes.text = Updater.markdown_to_bbcode(notes)
	_primary.text = "Pokračovat"
	_primary.visible = true
	_secondary.visible = false
	_buttons.visible = true
	_progress.visible = false
	_status.visible = false
	_open()


func _open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_primary.grab_focus.call_deferred()


func _on_primary() -> void:
	Audio.play("click")
	if _mode == "update":
		if not Updater.can_self_install():
			Updater.install_update()  # otevře stránku vydání
			_close()
			return
		_buttons.visible = false
		_progress.visible = true
		_progress.value = 0.0
		_status.visible = true
		_status.text = "Stahuji novou verzi…"
		Updater.install_update()
	else:
		_close()


func _on_secondary() -> void:
	Audio.play("click")
	_close()


func _close() -> void:
	visible = false
	_secondary.visible = true
	dismissed.emit()

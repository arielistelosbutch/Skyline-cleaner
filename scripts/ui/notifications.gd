class_name Notifications
extends Control
## Jemná oznámení nahoře uprostřed (bez blikání) a slavnostní banner
## při dokončení zakázky nebo nové úrovni.

const MAX_VISIBLE := 4

var _box: VBoxContainer
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _level_card: PanelContainer
var _level_title: Label
var _level_sub: Label
var _last_text := ""
var _last_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.get_theme()
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(600, 0)
	UITheme.place(_box, Vector2(0.5, 0.0), Vector2(-300, 74), Vector2(600, 0))
	_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_box.add_theme_constant_override("separation", 8)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", UITheme.box(Color(0.98, 0.98, 0.96, 0.95), 22, 40, 34))
	_banner.custom_minimum_size = Vector2(520, 0)
	UITheme.place(_banner, Vector2(0.5, 0.5), Vector2(-260, -200), Vector2(520, 0))
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_child(v)
	_banner_title = UITheme.label("", 34, UITheme.ACCENT_DARK, true)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_banner_title)
	_banner_sub = UITheme.label("", 22, UITheme.TEXT)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_banner_sub)

	_build_level_card()

	Events.notify.connect(show_toast)
	Events.contract_completed.connect(_on_contract_completed)
	Events.level_up.connect(_on_level_up)


func show_toast(text: String, kind: String = "info") -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if text == _last_text and now - _last_time < 2.0:
		return
	_last_text = text
	_last_time = now
	while _box.get_child_count() >= MAX_VISIBLE:
		var old := _box.get_child(0)
		_box.remove_child(old)
		old.queue_free()
	var accent := UITheme.ACCENT
	match kind:
		"success":
			accent = UITheme.SUCCESS
		"warn":
			accent = UITheme.WARN
		"money":
			accent = UITheme.GOLD
	var p := PanelContainer.new()
	var sb := UITheme.box(Color(0.98, 0.98, 0.97, 0.94), 12, 16, 14)
	sb.border_color = accent
	sb.border_width_left = 6
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.label(text, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.modulate.a = 0.0
	_box.add_child(p)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func show_banner(title: String, sub: String, hold: float = 3.0) -> void:
	_banner_title.text = title
	_banner_sub.text = sub
	_banner.visible = true
	_banner.pivot_offset = _banner.size * 0.5
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.85, 0.85)
	var tw := _banner.create_tween()
	tw.set_parallel(true)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.35)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(hold)
	tw.chain().tween_property(_banner, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(func() -> void: _banner.visible = false)


func _on_contract_completed(id: String, money: int, xp: int) -> void:
	var c := ContractManager.get_contract(id)
	show_banner("Zakázka dokončena!", "%s\n+%s    +%d XP" % [c.title if c else "", UITheme.money(money), xp], 3.5)


## Výrazná zlatá karta při nové úrovni (talentový bod) – drží déle než běžný banner
## a nabízí rovnou otevřít talenty v tabletu klávesou [T].
func _build_level_card() -> void:
	_level_card = PanelContainer.new()
	var sb := UITheme.box(Color(1.0, 0.97, 0.86, 0.97), 24, 44, 30, UITheme.GOLD, 5)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 18
	_level_card.add_theme_stylebox_override("panel", sb)
	_level_card.custom_minimum_size = Vector2(600, 0)
	UITheme.place(_level_card, Vector2(0.5, 0.5), Vector2(-300, 20), Vector2(600, 0))
	_level_card.visible = false
	_level_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_level_card)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	_level_card.add_child(v)
	var star := UITheme.label("★", 54, UITheme.GOLD, true)
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(star)
	_level_title = UITheme.label("", 38, Color(0.55, 0.38, 0.05), true)
	_level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_level_title)
	_level_sub = UITheme.label("", 21, UITheme.TEXT)
	_level_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_level_sub)
	var key := UITheme.label("Stiskni  [T]  a vyber si talent", 24, UITheme.ACCENT_DARK, true)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(key)


func show_level_card(level: int) -> void:
	_level_title.text = "Nová úroveň %d!" % level
	var pts := GameState.talent_points
	_level_sub.text = "Získáváš talentový bod (k utracení: %d)." % pts if pts > 1 else "Získáváš talentový bod."
	_level_card.visible = true
	_level_card.pivot_offset = Vector2(300, 120)
	_level_card.modulate.a = 0.0
	_level_card.scale = Vector2(0.6, 0.6)
	var tw := _level_card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(_level_card, "modulate:a", 1.0, 0.3)
	tw.tween_property(_level_card, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(6.0)
	tw.chain().tween_property(_level_card, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(func() -> void: _level_card.visible = false)


func hide_level_card() -> void:
	_level_card.visible = false


func _on_level_up(level: int) -> void:
	await get_tree().create_timer(0.8).timeout
	show_level_card(level)

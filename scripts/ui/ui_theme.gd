class_name UITheme
extends RefCounted
## Jednotný vzhled rozhraní: světlé panely, tyrkysový akcent, zaoblené rohy.

const ACCENT := Color(0.18, 0.6, 0.66)
const ACCENT_DARK := Color(0.12, 0.42, 0.48)
const TEXT := Color(0.13, 0.16, 0.18)
const TEXT_SOFT := Color(0.38, 0.43, 0.46)
const PANEL := Color(0.97, 0.98, 0.97, 0.96)
const GOLD := Color(0.95, 0.72, 0.25)
const SUCCESS := Color(0.3, 0.7, 0.42)
const WARN := Color(0.92, 0.6, 0.25)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.6))
	t.set_stylebox("normal", "Button", box(ACCENT, 10, 10, 14))
	t.set_stylebox("hover", "Button", box(ACCENT.lightened(0.12), 10, 10, 14))
	t.set_stylebox("pressed", "Button", box(ACCENT_DARK, 10, 10, 14))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 10, 0, 0, Color(1, 1, 1, 0.6), 2))
	t.set_stylebox("disabled", "Button", box(Color(0.6, 0.65, 0.67), 10, 10, 14))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 16, 18, 18))
	t.set_stylebox("panel", "Panel", box(PANEL, 16, 18, 18))
	t.set_stylebox("background", "ProgressBar", box(Color(0.82, 0.86, 0.87), 6, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 6, 0, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", TEXT)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_focus_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", TEXT)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	_theme = t
	return t


static func box(color: Color, radius: int = 12, margin_h: int = 12, margin_v: int = -1, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if margin_v < 0:
		margin_v = margin_h
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v * 0.6 if margin_v > 0 else 0
	s.content_margin_bottom = margin_v * 0.6 if margin_v > 0 else 0
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.anti_aliasing = true
	return s


static func label(text: String, size: int = 18, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_constant_override("outline_size", 1)
		l.add_theme_color_override("font_outline_color", color)
	return l


static func shadow_label(text: String, size: int = 18, color: Color = Color.WHITE) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 4)
	return l


static func money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return ("-" if v < 0 else "") + out + " Kč"


## Ukotví prvek k bodu rodiče (0..1) s pevným odsazením a velikostí.
static func place(c: Control, anchor: Vector2, pos: Vector2, size: Vector2 = Vector2.ZERO) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + size.x
	c.offset_bottom = pos.y + size.y

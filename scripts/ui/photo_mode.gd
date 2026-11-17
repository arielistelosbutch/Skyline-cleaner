class_name PhotoMode
extends Node3D
## Fotorežim [P]: volná kamera bez HUD pro hezké snímky.
## WASD / myš = pohyb a rozhlížení, mezerník / Ctrl = nahoru / dolů, Shift = rychleji,
## kolečko = přiblížení, [T] / [G] = posunout denní dobu, [Enter] nebo [F12] = uložit
## snímek (user://fotky), [P] / [Esc] = konec. Kamera se drží do 40 m od hráče.

const MAX_DIST := 40.0
const SPEED := 3.0

var player: Player
var ui: UIRoot
var active := false
var cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _hint: Label
var _layer: CanvasLayer
var _prev_hud := true


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "PhotoCamera"
	cam.far = 2000.0
	add_child(cam)
	_layer = CanvasLayer.new()
	_layer.layer = 50
	_layer.visible = false
	add_child(_layer)
	_hint = UITheme.label("FOTOREŽIM  ·  [WASD] pohyb  ·  [mezerník/Ctrl] nahoru/dolů  ·  [kolečko] zoom  ·  [T/G] čas  ·  [Enter] uložit snímek  ·  [H] skrýt nápovědu  ·  [P] konec", 15, Color(1, 1, 1), true)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.position = Vector2(20, 14)
	_layer.add_child(_hint)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if player == null or ui == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if not active:
			if k == KEY_P and not ui._in_menu and not ui.any_open() and player.mode == Player.Mode.WALK:
				get_viewport().set_input_as_handled()
				enter()
			return
		get_viewport().set_input_as_handled()
		match k:
			KEY_P, KEY_ESCAPE:
				leave()
			KEY_ENTER, KEY_KP_ENTER, KEY_F12:
				save_photo()
			KEY_H:
				_hint.visible = not _hint.visible
			KEY_T:
				GameState.clock = fposmod(GameState.clock + 1.0, 24.0)
			KEY_G:
				GameState.clock = fposmod(GameState.clock - 1.0, 24.0)
		return
	if not active:
		return
	if event is InputEventMouseMotion:
		var s := Settings.mouse_sensitivity
		_yaw -= event.relative.x * s
		_pitch = clampf(_pitch - event.relative.y * s, -1.5, 1.5)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.fov = clampf(cam.fov - 3.0, 20.0, 100.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.fov = clampf(cam.fov + 3.0, 20.0, 100.0)
		get_viewport().set_input_as_handled()


func enter() -> void:
	active = true
	var pc := player.camera
	cam.global_transform = pc.global_transform
	cam.fov = pc.fov
	_yaw = player.yaw
	_pitch = player.pitch
	cam.current = true
	player.ui_open = true
	_prev_hud = ui.visible
	ui.visible = false
	player.hand.visible = false
	_layer.visible = true
	_hint.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func leave() -> void:
	active = false
	player.camera.current = true
	player.ui_open = false
	ui.visible = _prev_hud
	_layer.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if not active:
		return
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir.x += 1.0
	var b := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	var move := b * dir
	if Input.is_physical_key_pressed(KEY_SPACE):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL):
		move.y -= 1.0
	var sp := SPEED * (3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	var pos := cam.global_position + move * sp * delta
	var center := player.global_position + Vector3(0, 1.6, 0)
	if pos.distance_to(center) > MAX_DIST:
		pos = center + (pos - center).normalized() * MAX_DIST
	cam.global_transform = Transform3D(b, pos)


## Uloží snímek bez nápovědy do user://fotky a ukáže cestu.
func save_photo() -> void:
	var hint_was := _hint.visible
	_hint.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_hint.visible = hint_was
	DirAccess.make_dir_recursive_absolute("user://fotky")
	var t := Time.get_datetime_dict_from_system()
	var fname := "foto_%04d%02d%02d_%02d%02d%02d.png" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	var path := "user://fotky/" + fname
	if img.save_png(path) == OK:
		Audio.play("cloth", -8.0, 1.6)
		_flash_note("Snímek uložen: " + ProjectSettings.globalize_path(path))
	else:
		_flash_note("Snímek se nepodařilo uložit.")


func _flash_note(text: String) -> void:
	var l := UITheme.label(text, 16, Color(1, 1, 0.85), true)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.position = Vector2(20, 44)
	_layer.add_child(l)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

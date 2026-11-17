extends Node
## Uživatelská nastavení (citlivost, hlasitost, zorné pole).
## Ukládají se odděleně od herní pozice do user://settings.cfg.

const PATH := "user://settings.cfg"

var mouse_sensitivity := 0.0024
var clean_sensitivity := 1.0
var master_volume := 0.8
var fov := 72.0
var head_bob := true
## Etapa 7: občasné bouřky a ptáci, kteří kápnou na okno (relax hra – jde vypnout).
var weather_events := true
var bird_droppings := true
## Střídání denní doby a ročních období (vypnuto = pořád dopoledne / léto).
var day_cycle := true
var seasons := true
## Grafika: vyhlazování hran (0 vypnuto, 1 FXAA, 2 MSAA 2×, 3 MSAA 4×),
## rozlišení vykreslování 3D (méně = rychlejší na slabších PC, dopočítá FSR)
## a celá obrazovka.
var aa_mode := 2
var render_scale := 1.0
var fullscreen := false

const AA_NAMES := ["Vypnuto", "Rychlé (FXAA)", "MSAA 2×", "MSAA 4×"]


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	mouse_sensitivity = float(cf.get_value("input", "mouse_sensitivity", mouse_sensitivity))
	clean_sensitivity = float(cf.get_value("input", "clean_sensitivity", clean_sensitivity))
	master_volume = float(cf.get_value("audio", "master_volume", master_volume))
	fov = float(cf.get_value("video", "fov", fov))
	head_bob = bool(cf.get_value("video", "head_bob", head_bob))
	weather_events = bool(cf.get_value("game", "weather_events", weather_events))
	bird_droppings = bool(cf.get_value("game", "bird_droppings", bird_droppings))
	day_cycle = bool(cf.get_value("game", "day_cycle", day_cycle))
	seasons = bool(cf.get_value("game", "seasons", seasons))
	aa_mode = clampi(int(cf.get_value("video", "aa_mode", aa_mode)), 0, AA_NAMES.size() - 1)
	render_scale = clampf(float(cf.get_value("video", "render_scale", render_scale)), 0.5, 1.0)
	fullscreen = bool(cf.get_value("video", "fullscreen", fullscreen))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("input", "clean_sensitivity", clean_sensitivity)
	cf.set_value("audio", "master_volume", master_volume)
	cf.set_value("video", "fov", fov)
	cf.set_value("video", "head_bob", head_bob)
	cf.set_value("game", "weather_events", weather_events)
	cf.set_value("game", "bird_droppings", bird_droppings)
	cf.set_value("game", "day_cycle", day_cycle)
	cf.set_value("game", "seasons", seasons)
	cf.set_value("video", "aa_mode", aa_mode)
	cf.set_value("video", "render_scale", render_scale)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.save(PATH)


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam and cam.is_in_group("player_camera"):
		cam.fov = fov
	apply_graphics()


func apply_graphics() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][aa_mode]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa_mode == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = render_scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var cur := DisplayServer.window_get_mode()
	var is_full := cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen != is_full:
		DisplayServer.window_set_mode(want)

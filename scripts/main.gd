extends Node3D
## Vstupní bod hry: postaví venkovskou oblast, hráče a rozhraní.

var world: Countryside
var player: Player
var ui: UIRoot
var tutorial: Tutorial


func _ready() -> void:
	# Načítací obrazovka s tipy; oblasti se staví po krocích, aby se obrazovka překreslovala.
	var args := OS.get_cmdline_user_args()
	var loading := LoadingScreen.new()
	add_child(loading)
	loading.set_progress(0.05, "Lipová Lhota")
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	world = Countryside.new()
	world.name = "Countryside"
	world.defer_areas = true
	add_child(world)
	for k in Countryside.AREA_STEPS:
		loading.set_progress(0.2 + 0.25 * k, Countryside.AREA_LABELS[k])
		await get_tree().process_frame
		await get_tree().process_frame
		world.build_area(k)
	# Zahřátí shaderů: za načítací obrazovkou se kamera podívá do každé oblasti,
	# aby se materiály zkompilovaly teď, a ne až při první návštěvě (záseky).
	loading.set_progress(0.85, "Připravuji grafiku")
	var cam := world.menu_camera
	cam.current = true
	world.warming = true
	var views := [
		[Vector3(-20, 12, 30), Vector3(0, 2, -8)],
		[Suburb.ORIGIN + Vector3(-30, 14, 30), Suburb.ORIGIN + Vector3(0, 4, 0)],
		[City.ORIGIN + Vector3(-40, 16, 25), City.ORIGIN + Vector3(0, 8, 0)],
		[Metropolis.ORIGIN + Vector3(-60, 20, 30), Metropolis.ORIGIN + Vector3(0, 40, -10)],
		[Metropolis.ORIGIN + Vector3(30, 60, 10), Metropolis.ORIGIN + Vector3(-40, 30, -20)],
	]
	for v in views:
		cam.global_transform = Transform3D(Basis.looking_at(v[1] - v[0], Vector3.UP), v[0])
		await get_tree().process_frame
		await get_tree().process_frame
	world.warm_up_effects()
	await get_tree().process_frame
	await get_tree().process_frame
	world.warming = false
	loading.set_progress(0.95, "Firma Clear View")
	await get_tree().process_frame

	player = Player.new()
	player.name = "Player"
	player.position = world.spawn_point
	player.yaw = world.spawn_yaw
	player.spawn_point = world.spawn_point
	add_child(player)

	var fleet := RobotFleet.new()
	fleet.name = "RobotFleet"
	add_child(fleet)

	var markers := WindowMarkers.new()
	markers.name = "WindowMarkers"
	markers.player = player
	add_child(markers)

	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	tutorial.player = player
	add_child(tutorial)

	ui = UIRoot.new()
	ui.name = "UI"
	ui.player = player
	add_child(ui)
	ui.hud.tutorial = tutorial
	var finder := ToolFinder.new()
	finder.name = "ToolFinder"
	finder.player = player
	finder.nav = ui.hud.nav
	add_child(finder)
	player.finder = finder
	ui.start_requested.connect(_on_start)
	var photo := PhotoMode.new()
	photo.name = "PhotoMode"
	photo.player = player
	photo.ui = ui
	add_child(photo)
	Audio.set_loop("wind", 0.22)
	print("Svět postaven za %d ms" % (Time.get_ticks_msec() - t0))
	loading.finish()

	if args.has("--zscan"):
		var z := preload("res://scripts/tests/zfight_scan.gd").new()
		z.main = self
		add_child(z)
		return

	if args.has("--autotest") or args.has("--shots"):
		var t := preload("res://scripts/tests/autotest.gd").new()
		t.main = self
		t.shots_only = args.has("--shots")
		add_child(t)
		return

	if SaveManager.pending_load:
		SaveManager.pending_load = false
		await get_tree().process_frame
		SaveManager.load_game()
		_enter_game()
		Events.toast("Hra načtena.", "info")
	else:
		world.menu_camera.current = true
		ui.show_main_menu()


func _on_start(load_save: bool) -> void:
	if load_save and SaveManager.has_save():
		SaveManager.load_game()
		_enter_game()
		Events.toast("Vítej zpátky v Lipové Lhotě.", "info")
	else:
		GameState.reset()
		ContractManager.reset()
		WindowRegistry.reset_all()
		tutorial.start()
		# nová hra začíná čelem ke garáži firmy (tutoriál)
		var to_garage := Vector3(-33.0, 0.0, -12.0) - player.global_position
		player.yaw = atan2(-to_garage.x, -to_garage.z)
		player.pitch = 0.0
		_enter_game()
		Events.toast("Vítej v Lipové Lhotě! Tvoje firma Clear View právě začíná – úkoly tutoriálu najdeš vlevo nahoře.", "info")


func _enter_game() -> void:
	player.activate_camera()
	ui.enter_game()

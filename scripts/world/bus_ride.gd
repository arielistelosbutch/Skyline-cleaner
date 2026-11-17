class_name BusRide
extends Node3D
## Animace cesty autobusem: autobus přijede k zastávce, hráč nastoupí (zatmívačka),
## v cílové oblasti autobus stojí u zastávky, hráč vystoupí a autobus odjede.
## Samotný přesun dělá Countryside.travel() uprostřed zatmění.

const DRIVE_IN := 3.2
const DRIVE_OUT := 3.4
const FADE := 0.45
const RUN := 55.0

var world: Countryside
var player: Player
var area := ""
var bus: MeshInstance3D
var _fade: ColorRect
var _layer: CanvasLayer
var running := false


static func start(w: Countryside, p: Player, target_area: String) -> BusRide:
	var r := BusRide.new()
	r.world = w
	r.player = p
	r.area = target_area
	w.add_child(r)
	r._go()
	return r


func _ready() -> void:
	add_to_group("bus_ride")
	bus = MeshInstance3D.new()
	bus.mesh = Traffic._vehicle_mesh("bus", 0)
	add_child(bus)
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)


## Místo, kde autobus stojí u zastávky oblasti (střed autobusu v pruhu).
func _bus_spot(a: String) -> Vector3:
	var p := world.stop_point(a)
	return Vector3(p.x - 1.5, 0.0, world.stop_lane_z(a))


func _place_bus(spot: Vector3, x_off: float) -> void:
	# autobus jede v pruhu u zastávky směrem -X (pravostranný provoz), předek v +Z modelu
	bus.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), spot + Vector3(x_off, 0, 0))
	bus.reset_physics_interpolation()


func _go() -> void:
	running = true
	player.ui_open = true
	player.velocity = Vector3.ZERO
	var stop := _bus_spot(WorldMap.area_at(Vector2(player.global_position.x, player.global_position.z)))
	# 1) příjezd k zastávce (brzdí)
	var t := 0.0
	while t < DRIVE_IN:
		t += get_process_delta_time()
		var k := clampf(t / DRIVE_IN, 0.0, 1.0)
		_place_bus(stop, RUN * pow(1.0 - k, 2.0))
		await get_tree().process_frame
	Audio.play("spray", -10.0, 0.45)   # syknutí dveří
	await get_tree().create_timer(0.5).timeout
	# 2) nástup – zatmění a přesun
	await _fade_to(1.0)
	if not world.travel(area, player):
		await _fade_to(0.0)
		_finish()
		return
	var dest := _bus_spot(area)
	_place_bus(dest, 0.0)
	player.ui_open = true
	await get_tree().create_timer(0.25).timeout
	await _fade_to(0.0)
	Audio.play("spray", -10.0, 0.45)
	await get_tree().create_timer(0.6).timeout
	# 3) odjezd (rozjíždí se)
	player.ui_open = false
	t = 0.0
	while t < DRIVE_OUT:
		t += get_process_delta_time()
		var k := clampf(t / DRIVE_OUT, 0.0, 1.0)
		_place_bus(dest, -RUN * 1.4 * k * k)
		await get_tree().process_frame
	_finish()


func _fade_to(a: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, FADE)
	await tw.finished


func _finish() -> void:
	running = false
	if player and not _ui_blocking():
		player.ui_open = false
	queue_free()


func _ui_blocking() -> bool:
	var ui := get_tree().get_first_node_in_group("ui_root")
	return ui != null and ui.any_open()

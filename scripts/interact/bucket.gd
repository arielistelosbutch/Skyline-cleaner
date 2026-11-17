class_name Bucket
extends StaticBody3D
## Přenosný kbelík s vodou (pomocník navíc). Hráč ho nosí jako židli a postaví
## si ho k domu, kde myje – vymáchá v něm nástroj a doplní rozprašovač, aniž by
## běhal k sudu nebo kohoutku. Voda v něm vydrží na několik vymáchání; znovu se
## naplní sám, když ho hráč postaví k vodě (sud, kohoutek, kýbl v garáži).
## Ve světě je jen tehdy, když ho hráč vlastní (koupí se v obchodě).

const SIZE := Vector3(0.36, 0.34, 0.36)
## Jak blízko vody musí kbelík stát, aby se naplnil.
const FILL_DIST := 3.2

@export var persist_id := "bucket_carry"
@export var item_id := "bucket_carry"

var mesh: ArrayMesh
var water := 0
var _mi: MeshInstance3D
var _water_mi: MeshInstance3D
var _cs: CollisionShape3D
var _carried := false
var _was_owned := false
## Kam se kbelík postaví po koupi (u garáže).
var home := Transform3D.IDENTITY


func _ready() -> void:
	add_to_group("persist")
	add_to_group("buckets")
	collision_layer = 1
	collision_mask = 0
	set_meta("interactable", self)
	mesh = build_mesh()
	_mi = MeshInstance3D.new()
	_mi.mesh = mesh
	add_child(_mi)
	_water_mi = MeshInstance3D.new()
	var wb := MeshBuilder.new(5)
	wb.add("cyl16", Transform3D(Basis.from_scale(Vector3(0.3, 0.01, 0.3)), Vector3.ZERO), Color(0.45, 0.7, 0.82), 0.0)
	_water_mi.mesh = wb.commit()
	add_child(_water_mi)
	_cs = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	_cs.shape = box
	_cs.position = Vector3(0, SIZE.y * 0.5, 0)
	add_child(_cs)
	if home == Transform3D.IDENTITY:
		home = transform
	water = capacity()
	Events.inventory_changed.connect(_refresh_owned)
	_refresh_owned()


static func capacity() -> int:
	return 6


static func build_mesh() -> ArrayMesh:
	var b := MeshBuilder.new(23)
	var body := Color(0.22, 0.52, 0.78)
	b.add("cyl16", Transform3D(Basis.from_scale(Vector3(0.3, 0.3, 0.3)), Vector3(0, 0.15, 0)), body, 0.04)
	b.add("cyl16", Transform3D(Basis.from_scale(Vector3(0.34, 0.03, 0.34)), Vector3(0, 0.3, 0)), body.darkened(0.15), 0.02)
	# ucho
	for k in 7:
		var a := PI * k / 6.0
		var p := Vector3(cos(a) * 0.17, 0.32 + sin(a) * 0.13, 0)
		b.add_box(Vector3(0.03, 0.018, 0.018), p, Color(0.75, 0.76, 0.78), Basis(Vector3.BACK, a + PI * 0.5), 0.0)
	return b.commit()


func is_owned() -> bool:
	return GameState.has_item(item_id)


func _refresh_owned() -> void:
	var o := is_owned()
	if o and not _was_owned and not _carried:
		transform = home
		water = capacity()
		reset_physics_interpolation()
	_was_owned = o
	_apply()


func _apply() -> void:
	var show := is_owned() and not _carried
	visible = show
	_cs.disabled = not show
	_water_mi.visible = water > 0
	_water_mi.position = Vector3(0, 0.06 + 0.22 * float(water) / capacity(), 0)


## Kbelík jde zvednout podržením [E] (krátký stisk = vymáchat).
func can_hold_pick() -> bool:
	return true


func get_prompt(player) -> String:
	if player.carried != null:
		return ""
	if water <= 0:
		return "Kbelík je prázdný – postav ho k vodě (sud, kohoutek), sám se naplní    [podrž E] / [LMB] Zvednout"
	return "[E] Vymáchat nástroj a doplnit rozprašovač (kbelík %d/%d)    [podrž E] / [LMB] Zvednout" % [water, capacity()]


func interact(player) -> void:
	if water <= 0:
		Events.toast("Kbelík je prázdný. Postav ho k sudu nebo kohoutku a naplní se.", "info")
		return
	water -= 1
	player.cleaning.rinse()
	Audio.play("water", -6.0, 1.1)
	_apply()


func set_carried(v: bool) -> void:
	_carried = v
	_apply()
	if not v:
		try_fill()


func is_carried() -> bool:
	return _carried


## Naplní kbelík, když stojí u vody.
func try_fill() -> bool:
	if not is_inside_tree() or water >= capacity():
		return false
	for n in get_tree().get_nodes_in_group("water_source"):
		if (n as Node3D).global_position.distance_to(global_position) < FILL_DIST:
			water = capacity()
			_apply()
			Audio.play("water", -8.0, 0.9)
			Events.toast("Kbelík je plný – vystačí na %d vymáchání." % capacity(), "info")
			return true
	return false


func save_state() -> Dictionary:
	return {"pos": SaveManager.vec3_to_arr(global_position), "yaw": global_rotation.y, "water": water}


func load_state(d: Dictionary) -> void:
	global_position = SaveManager.arr_to_vec3(d.get("pos"), global_position)
	global_rotation = Vector3(0, float(d.get("yaw", 0.0)), 0)
	water = int(d.get("water", capacity()))
	_carried = false
	_apply()

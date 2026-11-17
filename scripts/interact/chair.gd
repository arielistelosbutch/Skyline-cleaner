class_name Chair
extends StaticBody3D
## Přenosná dřevěná židle. Skutečná kolize sedáku – hráč na ni vyskočí
## a dosáhne výš. Opěradlo kolizi nemá, aby nepřekáželo u okna.

const SEAT_SIZE := Vector3(0.5, 0.47, 0.5)

@export var persist_id := "chair_wood"

var mesh: ArrayMesh
var _mi: MeshInstance3D
var _cs: CollisionShape3D


func _ready() -> void:
	add_to_group("persist")
	add_to_group("chairs")
	collision_layer = 1
	collision_mask = 0
	set_meta("interactable", self)
	mesh = build_mesh()
	_mi = MeshInstance3D.new()
	_mi.mesh = mesh
	add_child(_mi)
	_cs = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SEAT_SIZE
	_cs.shape = box
	_cs.position = Vector3(0, SEAT_SIZE.y * 0.5, 0)
	add_child(_cs)


static func build_mesh() -> ArrayMesh:
	var b := MeshBuilder.new(21)
	var wood := Color(0.62, 0.4, 0.23)
	var dark := Color(0.5, 0.31, 0.17)
	var h := SEAT_SIZE.y
	b.add_box(Vector3(0.5, 0.05, 0.5), Vector3(0, h - 0.025, 0), wood)
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			b.add_box(Vector3(0.045, h - 0.05, 0.045), Vector3(sx * 0.21, (h - 0.05) * 0.5, sz * 0.21), dark)
	# opěradlo na zadní straně (-Z)
	for sx: int in [-1, 1]:
		b.add_box(Vector3(0.045, 0.5, 0.045), Vector3(sx * 0.21, h + 0.25, -0.21), dark)
	b.add_box(Vector3(0.46, 0.08, 0.035), Vector3(0, h + 0.45, -0.21), wood)
	b.add_box(Vector3(0.46, 0.06, 0.03), Vector3(0, h + 0.25, -0.21), wood)
	b.add_box(Vector3(0.38, 0.03, 0.03), Vector3(0, 0.14, 0.21), dark)
	b.add_box(Vector3(0.38, 0.03, 0.03), Vector3(0, 0.14, -0.21), dark)
	return b.commit()


func get_prompt(_player) -> String:
	return "[E] Zvednout židli"


func interact(player) -> void:
	player.pick_up(self)


func set_carried(v: bool) -> void:
	visible = not v
	_cs.disabled = v


func save_state() -> Dictionary:
	return {"pos": SaveManager.vec3_to_arr(global_position), "yaw": global_rotation.y}


func load_state(d: Dictionary) -> void:
	global_position = SaveManager.arr_to_vec3(d.get("pos"), global_position)
	global_rotation = Vector3(0, float(d.get("yaw", 0.0)), 0)
	set_carried(false)

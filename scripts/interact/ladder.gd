class_name Ladder
extends StaticBody3D
## Přenosný žebřík. Hráč ho nese, opře o zeď (pod úhlem ANGLE) a vyleze po něm.
## Na žebříku jde zastavit v libovolné výšce a odtud mýt okna (dosah se počítá
## od nohou hráče). Lokálně: počátek = pata žebříku na zemi, zeď je ve směru -Z.
## Žebřík je ve světě jen tehdy, když ho hráč vlastní (koupí se objeví u garáže).

const ANGLE := 0.2618          # 15° od svislice
const WIDTH := 0.48
const CLIMB_SPEED := 1.1
## Hráč stojí za žebříkem (dál od zdi) – vzdálenost těžiště od roviny žebříku.
const STAND_BACK := 0.3

@export var persist_id := "ladder_small"
@export var item_id := "ladder_small"
@export var length := 4.2

var mesh: ArrayMesh
var carry_mesh: ArrayMesh
var _mi: MeshInstance3D
var _cs: CollisionShape3D
var _carried := false
var _was_owned := false
## Žebřík leží na zemi (po cestě autobusem) – jde jen zvednout.
var lying := false
var _lie_yaw := 0.0
## Kam se žebřík postaví po koupi (opřený o garáž).
var home := Transform3D.IDENTITY


func _ready() -> void:
	add_to_group("persist")
	add_to_group("ladders")
	collision_layer = 1
	collision_mask = 0
	set_meta("interactable", self)
	mesh = build_mesh(length, true)
	carry_mesh = build_mesh(length, false)
	_mi = MeshInstance3D.new()
	_mi.mesh = mesh
	add_child(_mi)
	_cs = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH + 0.06, length, 0.08)
	_cs.shape = box
	_cs.transform = Transform3D(Basis(Vector3.RIGHT, -ANGLE), up_local() * length * 0.5)
	add_child(_cs)
	if home == Transform3D.IDENTITY:
		home = transform
	Events.inventory_changed.connect(_refresh_owned)
	_refresh_owned()


func is_owned() -> bool:
	return GameState.has_item(item_id)


func _refresh_owned() -> void:
	var o := is_owned()
	if o and not _was_owned and not _carried:
		transform = home
		lying = false
		reset_physics_interpolation()
	_was_owned = o
	_apply()


func _apply() -> void:
	var show := is_owned() and not _carried
	visible = show
	_cs.disabled = not show


## Směr žebříku (od paty nahoru) v lokálních souřadnicích.
static func up_local() -> Vector3:
	return Vector3(0.0, cos(ANGLE), -sin(ANGLE))


## Výška opření o zeď (horní konec).
func top_height() -> float:
	return length * cos(ANGLE)


## Nejvyšší příčka, na které se dá stát (nohy) – musíš se mít čeho držet.
func max_stand() -> float:
	return top_height() - 1.05


## Vodorovná vzdálenost paty od zdi.
func base_offset() -> float:
	return length * sin(ANGLE)


static func build_mesh(len_m: float, leaning: bool) -> ArrayMesh:
	var b := MeshBuilder.new(31)
	var rail := Color(0.78, 0.8, 0.82)
	var rung := Color(0.66, 0.68, 0.7)
	var foot := Color(0.15, 0.15, 0.16)
	var tilt := Basis(Vector3.RIGHT, -ANGLE) if leaning else Basis(Vector3.RIGHT, -PI * 0.5)
	for sx: float in [-1.0, 1.0]:
		var c := tilt * Vector3(sx * WIDTH * 0.5, len_m * 0.5, 0)
		b.add_box(Vector3(0.05, len_m, 0.07), c, rail, tilt)
		b.add_box(Vector3(0.07, 0.06, 0.1), tilt * Vector3(sx * WIDTH * 0.5, 0.03, 0), foot, tilt)
		b.add_box(Vector3(0.07, 0.06, 0.1), tilt * Vector3(sx * WIDTH * 0.5, len_m - 0.03, 0), foot, tilt)
	var n := int(len_m / 0.28)
	for k in n:
		var h := 0.25 + k * 0.28
		if h > len_m - 0.1:
			break
		b.add_box(Vector3(WIDTH, 0.035, 0.045), tilt * Vector3(0, h, 0), rung, tilt)
	return b.commit()


func get_prompt(player) -> String:
	if player.carried != null:
		return ""
	if lying:
		return "[E] / [LMB] Zvednout žebřík"
	return "[E] Vylézt na žebřík    [podrž E] / [LMB] Zvednout a nést"


func interact(player) -> void:
	if lying:
		player.pick_up(self)
	else:
		player.climb_ladder(self)


## Položí žebřík naplocho na zem (yaw = natočení kolem svislé osy).
func lay_down(pos: Vector3, yaw: float) -> void:
	lying = true
	_lie_yaw = yaw
	global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -(PI * 0.5 - ANGLE)), pos + Vector3(0, 0.04, 0))
	reset_physics_interpolation()


func set_carried(v: bool) -> void:
	_carried = v
	if v:
		lying = false
	_apply()


func is_carried() -> bool:
	return _carried


## Vrátí žebřík na výchozí místo (u garáže) – např. když se zatoulá.
func send_home() -> void:
	if _carried:
		return
	transform = home
	lying = false
	reset_physics_interpolation()


## Světová poloha nohou hráče ve výšce h nad patou žebříku.
func feet_at(h: float) -> Vector3:
	var up := global_basis * up_local()
	var back := global_basis.z.normalized()
	return global_position + up * (h / cos(ANGLE)) + back * STAND_BACK


func save_state() -> Dictionary:
	return {"pos": SaveManager.vec3_to_arr(global_position), "yaw": _lie_yaw if lying else global_rotation.y, "lying": lying}


func load_state(d: Dictionary) -> void:
	var p := SaveManager.arr_to_vec3(d.get("pos"), global_position)
	var yaw := float(d.get("yaw", 0.0))
	set_carried(false)
	if bool(d.get("lying", false)):
		lay_down(p - Vector3(0, 0.04, 0), yaw)
	else:
		lying = false
		global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
		reset_physics_interpolation()

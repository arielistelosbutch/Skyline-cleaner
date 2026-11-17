class_name RobotCharger
extends StaticBody3D
## Nabíjecí stojan na roboty (Etapa 5) – na zdi v garáži na základně a u poboček
## obchodu. [E] = dát roboty, které neseš, nabíjet; když neneseš žádného,
## vezmeš si nabité. Lokálně: stojan visí na zdi, +Z = do místnosti / k ulici.

const SLOTS := 4

@export var charger_id := ""
## Stojan na dodávce: kabel vede do karoserie, ne do zásuvky na zemi.
@export var on_vehicle := false
var _title: Label3D


static func build(parent: Node3D, pos: Vector3, yaw: float, id: String, vehicle := false) -> RobotCharger:
	var c := RobotCharger.new()
	c.charger_id = id
	c.on_vehicle = vehicle
	c.name = "RobotCharger_" + id
	c.position = pos
	c.rotation.y = yaw
	parent.add_child(c)
	return c


func _ready() -> void:
	add_to_group("robot_charger")
	collision_layer = 1
	collision_mask = 0
	set_meta("interactable", self)
	var b := MeshBuilder.new(72)
	var grey := Color(0.88, 0.89, 0.9)
	var dark := Color(0.2, 0.22, 0.25)
	b.add_box(Vector3(1.7, 0.75, 0.06), Vector3(0, 1.25, 0.03), grey)
	b.add_box(Vector3(1.72, 0.1, 0.07), Vector3(0, 1.675, 0.035), Color(0.25, 0.55, 0.85))
	for k in SLOTS:
		var x := slot_x(k)
		b.add_box(Vector3(0.32, 0.04, 0.12), Vector3(x, 1.02, 0.09), dark)
		b.add_box(Vector3(0.05, 0.05, 0.02), Vector3(x, 1.5, 0.07), Color(0.3, 0.8, 0.4))
	if on_vehicle:
		# kabel zezadu stojanu do zásuvky v dodávce
		b.add_box(Vector3(0.03, 0.2, 0.03), Vector3(0.78, 0.97, -0.02), dark)
		b.add_box(Vector3(0.03, 0.03, 0.34), Vector3(0.78, 0.88, -0.17), dark)
		b.add_box(Vector3(0.12, 0.12, 0.04), Vector3(0.78, 0.88, -0.33), Color(0.95, 0.95, 0.93))
	else:
		# kabel do zásuvky
		b.add_box(Vector3(0.03, 0.9, 0.03), Vector3(0.78, 0.45, 0.04), dark)
		b.add_box(Vector3(0.1, 0.1, 0.05), Vector3(0.78, 0.3, 0.04), Color(0.95, 0.95, 0.93))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.75, 0.8, 0.12)
	cs.shape = bs
	cs.position = Vector3(0, 1.25, 0.06)
	add_child(cs)
	var lbl := Label3D.new()
	_title = lbl
	lbl.text = "NABÍJENÍ ROBOTŮ"
	lbl.font_size = 26
	lbl.pixel_size = 0.004
	lbl.outline_size = 6
	lbl.modulate = Color.WHITE
	lbl.outline_modulate = Color(0.15, 0.3, 0.45)
	lbl.position = Vector3(0, 1.67, 0.07)
	add_child(lbl)
	refresh_title()


## Rychlonabíječka (Dílna / Hala) se ukáže v nápisu.
func refresh_title() -> void:
	if _title == null:
		return
	var sp := GameState.charger_speed(charger_id)
	_title.text = "NABÍJENÍ ROBOTŮ" if sp <= 1.0 else "RYCHLONABÍJENÍ ×%d" % int(sp)


func slot_x(k: int) -> float:
	return -0.6 + k * 0.4


## Kde robot ve slotu „sedí" (záda na stojanu, čelem ven).
func slot_transform(k: int) -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(slot_x(k), 1.2, 0.07))


func get_prompt(_player) -> String:
	var fleet := RobotFleet.get_fleet(self)
	if fleet == null or fleet.robots.is_empty():
		return "Nabíjecí stojan na roboty – roboty na okna koupíš v obchodě (od úrovně %d)" % int(GameState.ITEMS["robot_mini"]["level"])
	return fleet.charger_prompt(self)


func interact(_player) -> void:
	var fleet := RobotFleet.get_fleet(self)
	if fleet:
		fleet.charger_interact(self)

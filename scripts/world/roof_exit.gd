class_name RoofExit
extends RefCounted
## Nástavba schodiště na ploché střeše: malý domek s dveřmi a cedulí „↓ SCHODIŠTĚ".
## Dveřmi se hráč vrátí dolů (zjednodušeně přenesením, stejně jako cesta nahoru).
## Lokálně stojí dveře čelem do +Z; `yaw` celou nástavbu natočí.

const SIZE := Vector3(2.0, 2.4, 2.0)


static func build(parent: Node3D, body: StaticBody3D, b: MeshBuilder, pos: Vector3, yaw: float, action: Callable) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, pos)
	var wall := Color(0.68, 0.68, 0.7)
	b.add_box(SIZE, xf * Vector3(0, SIZE.y * 0.5, 0), wall, basis)
	b.add_box(Vector3(SIZE.x + 0.2, 0.12, SIZE.z + 0.2), xf * Vector3(0, SIZE.y + 0.06, 0), wall.darkened(0.25), basis)
	# dveře, rám a klika
	b.add_box(Vector3(0.95, 2.0, 0.05), xf * Vector3(0, 1.0, SIZE.z * 0.5 + 0.02), Color(0.3, 0.42, 0.55), basis)
	b.add_box(Vector3(1.1, 0.08, 0.07), xf * Vector3(0, 2.04, SIZE.z * 0.5 + 0.02), Color(0.25, 0.25, 0.27), basis)
	b.add_box(Vector3(0.12, 0.04, 0.06), xf * Vector3(0.32, 1.0, SIZE.z * 0.5 + 0.06), Color(0.85, 0.85, 0.8), basis)
	# cedule nad dveřmi
	b.add_box(Vector3(1.2, 0.26, 0.04), xf * Vector3(0, 2.22, SIZE.z * 0.5 + 0.03), Color(0.2, 0.6, 0.35), basis, 0.0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = SIZE
	cs.shape = bs
	cs.transform = Transform3D(basis, pos + Vector3(0, SIZE.y * 0.5, 0))
	body.add_child(cs)
	var l := Label3D.new()
	l.text = "↓ SCHODIŠTĚ"
	l.font_size = 30
	l.pixel_size = 0.005
	l.outline_size = 6
	l.outline_modulate = Color(0.1, 0.3, 0.15)
	l.transform = Transform3D(basis, xf * Vector3(0, 2.22, SIZE.z * 0.5 + 0.06))
	parent.add_child(l)
	var it := SimpleInteractable.create("[E] Sejít schodištěm dolů", action, Vector3(1.0, 2.0, 0.3), xf * Vector3(0, 1.0, SIZE.z * 0.5 + 0.1))
	it.rotation.y = yaw
	parent.add_child(it)

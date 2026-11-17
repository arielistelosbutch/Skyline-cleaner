class_name ShopKiosk
extends Node3D
## Pobočka obchodu s vybavením (stánek s markýzou a pultem) – aby hráč nemusel
## kvůli nákupu jezdit autobusem zpátky na náves. Otevírá stejný obchod
## jako Smíšené zboží ve vesnici (sortiment i ceny jsou společné).
## Lokálně: stánek stojí čelem do +Z (k ulici), šířka 4,4 m, hloubka 3 m.

const W := 4.4
const D := 3.0
const H := 2.7


## Postaví stánek do `parent` na lokální pozici `pos` s natočením `yaw`.
## `map_pos` je globální poloha na mapě (Vector2 x/z), `title` nápis nad pultem.
static func build(parent: Node3D, pos: Vector3, yaw: float, title: String, map_pos: Vector2, seed_value: int) -> ShopKiosk:
	var k := ShopKiosk.new()
	k.name = "ShopKiosk"
	k.position = pos
	k.rotation.y = yaw
	parent.add_child(k)
	k._build(title, seed_value)
	WorldMap.add_marker("shop_" + str(seed_value), map_pos, "Obchod s vybavením (pobočka)", Color(0.2, 0.65, 0.45))
	return k


func _build(title: String, seed_value: int) -> void:
	var b := MeshBuilder.new(seed_value)
	var wall := Color(0.92, 0.95, 0.97)
	var green := Color(0.25, 0.5, 0.42)
	var wood := Color(0.62, 0.46, 0.3)
	# zadní a boční stěny, střecha
	b.add_box(Vector3(W, H, 0.15), Vector3(0, H * 0.5, -D * 0.5 + 0.075), wall)
	for s: float in [-1.0, 1.0]:
		b.add_box(Vector3(0.15, H, D), Vector3(s * (W * 0.5 - 0.075), H * 0.5, 0), wall)
	b.add_box(Vector3(W + 0.3, 0.2, D + 0.3), Vector3(0, H + 0.1, 0), green)
	# štít s nápisem na střeše
	b.add_box(Vector3(W - 0.2, 0.7, 0.08), Vector3(0, H + 0.55, D * 0.5 + 0.05), Color(0.97, 0.97, 0.95))
	for s: float in [-1.0, 1.0]:
		b.add_box(Vector3(0.1, 0.74, 0.12), Vector3(s * (W * 0.5 - 0.1), H + 0.55, D * 0.5 + 0.05), green)
	# markýza v pruzích
	for i in 8:
		var c := green if i % 2 == 0 else Color(0.95, 0.95, 0.9)
		# markýza o kousek širší než stánek (konce pruhů nejsou v rovině boků)
		var aw := W + 0.12
		var x := -aw * 0.5 + (i + 0.5) * aw / 8.0
		b.add_box(Vector3(aw / 8.0, 0.06, 1.1), Vector3(x, H - 0.25, D * 0.5 + 0.45), c, Basis(Vector3.RIGHT, 0.35))
	# pult a regály se zbožím
	b.add_box(Vector3(W - 0.4, 1.0, 0.5), Vector3(0, 0.5, D * 0.5 - 0.3), wood)
	b.add_box(Vector3(W - 0.3, 0.06, 0.6), Vector3(0, 1.03, D * 0.5 - 0.3), wood.lightened(0.2))
	b.add_box(Vector3(W - 0.6, 2.4, 0.3), Vector3(0, 1.2, -D * 0.5 + 0.3), wood.darkened(0.1))
	for row in 3:
		b.add_box(Vector3(W - 0.6, 0.05, 0.45), Vector3(0, 1.12 + row * 0.5, -D * 0.5 + 0.65), wood)
	var goods := [Color(0.2, 0.55, 0.85), Color(0.95, 0.75, 0.15), Color(0.85, 0.25, 0.2), Color(0.3, 0.7, 0.4), Color(0.9, 0.9, 0.92)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for row in 3:
		for i in 9:
			var gx := -W * 0.5 + 0.55 + i * 0.42
			var gh := rng.randf_range(0.18, 0.32)
			b.add_box(Vector3(0.22, gh, 0.22), Vector3(gx, 1.15 + row * 0.5 + gh * 0.5, -D * 0.5 + 0.7), goods[rng.randi() % goods.size()])
	# kbelík a stěrka na pultu (ať je jasné, co se tu prodává)
	Props.bucket(b, Vector3(-1.3, 1.06, D * 0.5 - 0.3))
	b.add_box(Vector3(0.45, 0.06, 0.05), Vector3(0.9, 1.1, D * 0.5 - 0.3), Color(0.15, 0.15, 0.17))
	b.add_box(Vector3(0.04, 0.04, 0.4), Vector3(0.9, 1.1, D * 0.5 - 0.1), Color(0.95, 0.75, 0.15))
	b.to_instance(self, "KioskMesh")
	# kolize (stěny a pult; dovnitř se nechodí)
	var body := StaticBody3D.new()
	add_child(body)
	for box: Array in [
		[Vector3(W, H, 0.15), Vector3(0, H * 0.5, -D * 0.5 + 0.075)],
		[Vector3(0.15, H, D), Vector3(-W * 0.5 + 0.075, H * 0.5, 0)],
		[Vector3(0.15, H, D), Vector3(W * 0.5 - 0.075, H * 0.5, 0)],
		[Vector3(W, 1.05, 0.5), Vector3(0, 0.52, D * 0.5 - 0.3)],
	]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box[0]
		cs.shape = bs
		cs.position = box[1]
		body.add_child(cs)
	# nápis
	var lbl := Label3D.new()
	lbl.text = title
	lbl.font_size = 40
	lbl.pixel_size = 0.006
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0.15, 0.35, 0.3)
	lbl.position = Vector3(0, H + 0.66, D * 0.5 + 0.1)
	add_child(lbl)
	var sub := Label3D.new()
	sub.text = "Vybavení na mytí oken"
	sub.font_size = 28
	sub.pixel_size = 0.004
	sub.outline_size = 6
	sub.outline_modulate = Color(0.15, 0.35, 0.3)
	sub.position = Vector3(0, H + 0.36, D * 0.5 + 0.1)
	add_child(sub)
	# nabíjecí stojan na roboty na boku stánku (Etapa 5)
	RobotCharger.build(self, Vector3(W * 0.5 + 0.08, 0, D * 0.5 - 0.9), PI * 0.5, "pobocka_" + str(seed_value))
	var counter := SimpleInteractable.create("[E] Nakupovat – " + title, func(_p): get_tree().call_group("ui_root", "open_shop", title), Vector3(W - 0.4, 1.6, 0.4), Vector3(0, 1.3, D * 0.5 - 0.05))
	add_child(counter)

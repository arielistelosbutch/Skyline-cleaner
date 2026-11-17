class_name SuspendedPlatform
extends RopeAnchor
## Závěsná plošina (gondola) na střeše výškové budovy – Etapa 4.
## Ovládá se stejně jako lano ([S]/[W] dolů a nahoru, [A]/[D] do stran), ale
## jezdí po kolejnici podél celé fasády a hráč stojí v koši se zábradlím.
## Technicky je to „kotva" s velkým rozsahem do stran, takže hráč, mytí,
## ukládání i bezpečnost fungují stejně jako na laně (ověřené systémy).
## Nastupuje se u pultu na střeše (koš přijede nahoru) nebo přímo do koše tam,
## kde zůstal stát (třeba dole na chodníku); potřebuješ Oprávnění k obsluze plošin (obchod).

const CERT_ITEM := "platform_cert"
const PLATFORM_SPEED := 1.0
const BASKET_LEN := 2.6
## Rozteč závěsů (lan) na koši – lana vedou z kladek výložníku do navijáků v koši.
const HOIST_X := 1.12
## O kolik dál od fasády visí koš než hráč na laně – aby neprojížděl okapy, římsy
## a parapety. Na okno z koše dosáhneš pořád (dosah hráče je 2,4 m).
const WALL_GAP := 0.5

## Půl délky kolejnice podél fasády (koš se posouvá v rozsahu ±rail_half).
@export var rail_half := 8.0

var _basket: MeshInstance3D
var _cables: Array[MeshInstance3D] = []
var _trolley: MeshInstance3D
var _park_u := 0.0
var _park_y := 0.0
## Nástup přímo do koše (kolize koše, když na něm nikdo není).
var _board: SimpleInteractable
var _ridden_frame := -100


func _ready() -> void:
	add_to_group("rope_anchor")
	add_to_group("platform")
	collision_layer = 1
	collision_mask = 0
	set_meta("interactable", self)
	# ovládací pult na střeše (na něj se kouká a mačká [E])
	var b := MeshBuilder.new(43)
	b.add_box(Vector3(0.5, 1.0, 0.35), Vector3(0, 0.5, 0), Color(0.95, 0.75, 0.15))
	b.add_box(Vector3(0.4, 0.25, 0.04), Vector3(0, 0.85, 0.19), Color(0.15, 0.15, 0.17))
	b.add_box(Vector3(0.08, 0.08, 0.04), Vector3(-0.1, 0.65, 0.19), Color(0.2, 0.75, 0.3))
	b.add_box(Vector3(0.08, 0.08, 0.04), Vector3(0.1, 0.65, 0.19), Color(0.85, 0.2, 0.15))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.1, 0.45)
	cs.shape = box
	cs.position = Vector3(0, 0.55, 0)
	add_child(cs)
	# kolejnice na atice a vozík s výložníkem
	var rail := MeshBuilder.new(44)
	var out := wall_out
	rail.add_box(Vector3(rail_half * 2.0 + 1.2, 0.12, 0.18), Vector3(0, edge_h + 0.066, out - 0.25), Color(0.5, 0.52, 0.55))
	var rmi := MeshInstance3D.new()
	rmi.mesh = rail.commit()
	add_child(rmi)
	var boom := 0.7 + WALL_GAP  # výložník sahá nad koš
	var tb := MeshBuilder.new(45)
	tb.add_box(Vector3(0.6, 0.35, 0.5), Vector3(0, 0.17, 0), Color(0.95, 0.75, 0.15))
	tb.add_box(Vector3(0.12, 0.12, boom + 0.35), Vector3(0, 0.4, boom * 0.5 - 0.025), Color(0.95, 0.75, 0.15))
	tb.add_box(Vector3(0.08, 0.3, 0.08), Vector3(0, 0.25, boom), Color(0.95, 0.75, 0.15))
	tb.add_box(Vector3(HOIST_X * 2.0 + 0.3, 0.1, 0.12), Vector3(0, 0.4, boom), Color(0.95, 0.75, 0.15))
	for sx: float in [-1.0, 1.0]:
		# kladka na konci příčníku
		tb.add_box(Vector3(0.05, 0.16, 0.14), Vector3(sx * HOIST_X, 0.27, boom), Color(0.3, 0.32, 0.35))
		tb.add("cyl10", Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.14, 0.06, 0.14)), Vector3(sx * HOIST_X, 0.25, boom)), Color(0.2, 0.2, 0.22), 0.02)
		# buben navijáku na vozíku (záložní lano)
		tb.add("cyl10", Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.22, 0.3, 0.22)), Vector3(sx * 0.2, 0.47, -0.05)), Color(0.25, 0.27, 0.3), 0.02)
	_trolley = MeshInstance3D.new()
	_trolley.mesh = tb.commit()
	_trolley.top_level = true
	add_child(_trolley)
	# koš plošiny
	var bb := MeshBuilder.new(46)
	var yellow := Color(0.95, 0.75, 0.15)
	var grey := Color(0.55, 0.57, 0.6)
	bb.add_box(Vector3(BASKET_LEN, 0.08, 0.75), Vector3(0, -0.04, 0), grey)
	for s: float in [-1.0, 1.0]:
		# zábradlí končí uvnitř bočnic, bočnice stojí na podlaze (žádné shodné plochy)
		bb.add_box(Vector3(BASKET_LEN - 0.02, 0.05, 0.05), Vector3(0, 1.05, s * 0.36), yellow)
		bb.add_box(Vector3(BASKET_LEN - 0.02, 0.04, 0.04), Vector3(0, 0.55, s * 0.36), yellow)
		bb.add_box(Vector3(0.06, 1.05, 0.77), Vector3(s * BASKET_LEN * 0.5, 0.525, 0), yellow)
		bb.add_box(Vector3(BASKET_LEN - 0.02, 0.25, 0.03), Vector3(0, 0.125, s * 0.37), grey.darkened(0.2))
	for x: float in [-0.9, 0.0, 0.9]:
		for s: float in [-1.0, 1.0]:
			bb.add_box(Vector3(0.04, 1.05, 0.04), Vector3(x, 0.52, s * 0.36), yellow)
	# třmeny s navijáky (motory), do kterých vedou lana
	for sx: float in [-1.0, 1.0]:
		var hx := sx * HOIST_X
		bb.add_box(Vector3(0.05, 0.05, 0.75), Vector3(hx, 1.05, 0), yellow)
		bb.add_box(Vector3(0.24, 0.34, 0.3), Vector3(hx, 1.25, 0), Color(0.3, 0.32, 0.35))
		bb.add_box(Vector3(0.26, 0.06, 0.32), Vector3(hx, 1.43, 0), Color(0.95, 0.75, 0.15))
		bb.add("cyl10", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.16, 0.34, 0.16)), Vector3(hx, 1.22, 0)), Color(0.2, 0.2, 0.22), 0.02)
	_basket = MeshInstance3D.new()
	_basket.mesh = bb.commit()
	_basket.top_level = true
	add_child(_basket)
	_board = SimpleInteractable.create("[E] Nastoupit do koše plošiny", func(p): board_basket(p), Vector3(BASKET_LEN, 1.1, 0.8), Vector3(0, 0.55, 0))
	_basket.add_child(_board)
	for k in 2:
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		cm.height = 1.0
		cm.radial_segments = 4
		c.mesh = cm
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.15, 0.15, 0.17)
		cm.material = cmat
		c.top_level = true
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		_cables.append(c)
	_park_y = top_feet()
	call_deferred("_place", _park_u, _park_y)
	call_deferred("_probe_ground")


## Podlaha koše má tloušťku pod nohama – dole se postaví na skutečný povrch
## (chodník je o pár cm výš než ground_y), aby jím neprošla.
func _probe_ground() -> void:
	if not is_inside_tree():
		return
	var best := ground_y
	for u: float in [-rail_half * 0.8, 0.0, rail_half * 0.8]:
		var p := hang_pos(u, ground_y)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.5, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var y: float = hit["position"].y
			if y > best and y < ground_y + 0.4:
				best = y
	# chodníky jsou jen tenké pásy bez kolize (~8–12 cm nad zemí) → rezerva 0,13 m
	ground_y = maxf(best + 0.02, ground_y + 0.13)


func get_prompt(_player) -> String:
	if not GameState.has_item(CERT_ITEM):
		return "Závěsná plošina – k obsluze potřebuješ Oprávnění k obsluze plošin (obchod)"
	return "[E] Nastoupit na závěsnou plošinu"


func interact(player) -> void:
	if not GameState.has_item(CERT_ITEM):
		Events.toast("Závěsná plošina. Bez oprávnění k obsluze ji nesmíš použít – kurz koupíš v obchodě s vybavením.", "info")
		return
	player.attach_rope(self)
	player.rope_u = _park_u
	player.rope_y = top_feet()


## Nástup přímo do koše tam, kde stojí (např. dole po vystoupení).
func board_basket(player) -> void:
	if not GameState.has_item(CERT_ITEM):
		Events.toast("Závěsná plošina. Bez oprávnění k obsluze ji nesmíš použít – kurz koupíš v obchodě s vybavením.", "info")
		return
	var u := _park_u
	var y := _park_y
	player.attach_rope(self)
	if player.anchor != self:
		return
	player.rope_u = u
	player.rope_y = y
	player.global_position = hang_pos(u, y)
	player.reset_physics_interpolation()
	rig_visual(u, y)


## Jak daleko od koše se hráč postaví, když vystoupí dole.
func exit_out() -> float:
	return 0.95


func _process(_delta: float) -> void:
	if _board:
		# dokud na plošině někdo jede, koš nemá kolizi ani nabídku nástupu
		var ridden := Engine.get_process_frames() - _ridden_frame < 3
		_board.collision_layer = 0 if ridden else 1


func attach_text() -> String:
	return "Jsi na plošině. [S]/[W] dolů a nahoru, [A]/[D] podél fasády. Okno umyješ jako obvykle [E]. Vystoupit jde nahoře na střeše nebo dole na zemi."


func side_range() -> float:
	return rail_half


func speed() -> float:
	return PLATFORM_SPEED * Talents.mult("platform_speed") * (2.0 if GameState.has_item("platform_turbo") else 1.0)


func hang_pos(u: float, feet_y: float) -> Vector3:
	return super.hang_pos(u, feet_y) + outward() * WALL_GAP


## Plošina zastaví o kus výš než lano (koš je pod nohama).
func top_feet() -> float:
	return roof_y - 1.2


## Plošina sjede až na chodník (navijáky nemají délkový limit lana).
func bottom_feet() -> float:
	return ground_y


## Vizuál koše, vozíku a lan podle polohy hráče (volá hráč každý snímek).
func rig_visual(u: float, feet_y: float) -> void:
	_ridden_frame = Engine.get_process_frames()
	if _board:
		_board.collision_layer = 0
	_park_u = u
	_park_y = feet_y
	_place(u, feet_y)


func _place(u: float, feet_y: float) -> void:
	if not is_inside_tree():
		return
	var feet := hang_pos(u, feet_y)
	var basis := global_basis.orthonormalized()
	_basket.global_transform = Transform3D(basis, feet)
	var top := global_position + side() * u + outward() * (wall_out - 0.25)
	top.y = roof_y + edge_h
	_trolley.global_transform = Transform3D(basis, top)
	var tip := top + outward() * (0.7 + WALL_GAP) + Vector3.UP * 0.18
	for k in 2:
		var sx := -1.0 if k == 0 else 1.0
		var a := tip + side() * sx * HOIST_X
		var bpt := feet + side() * sx * HOIST_X + Vector3.UP * 1.46
		var d := bpt - a
		var l := d.length()
		if l < 0.05:
			_cables[k].visible = false
			continue
		var y := d / l
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		_cables[k].global_transform = Transform3D(Basis(x, y * l, x.cross(y).normalized()), (a + bpt) * 0.5)
		_cables[k].visible = true

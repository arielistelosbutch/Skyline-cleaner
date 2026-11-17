class_name CompanyBase
extends Node3D
## Firemní základna a dodávka (Etapa 5 – kam s penězi):
## * Dílna (base_workshop) – vybavení garáže, rychlonabíječka ve stojanu (2×).
## * Firemní hala (base_hall) – nová budova vedle garáže s nástěnkou zakázek,
##   stojanem s rychlonabíjením (3×) a bonusem +5 % ke všem odměnám.
## * Firemní dodávka (company_van) – parkuje u základny; cestovat se s ní dá
##   odkudkoli přes tablet (Firma) nebo u auta [E]. Roboti u hráče se cestou dobíjí.
## Vylepšení se kupují v obchodě (kategorie Firma); svět se po koupi sám přestaví.

const HALL_POS := Vector3(-47.0, 0.0, -15.5)
const VAN_POS := Vector3(-44.0, 0.0, -7.0)
const OLD_VAN_POS := Vector3(-44.0, 0.0, -8.6)  # do verze 7 (kvůli žebříkům na střeše ze starého uložení)
## Kam dodávka hráče odveze, když jede „na základnu".
const BASE_SPOT := Vector3(-34.0, 0.05, -7.6)
## Kde dodávka zaparkuje v cíli cesty: [poloha ve světě, natočení].
const VAN_SPOTS := {
	"zakladna": [VAN_POS, 0.05],
	"venkov": [VAN_POS, 0.05],
	"predmesti": [Suburb.ORIGIN + Vector3(-58.5, 0.0, -3.3), PI * 0.5],
	"mesto": [City.ORIGIN + Vector3(-10.0, 0.0, -4.8), PI * 0.5],
	"velkomesto": [Metropolis.ORIGIN + Metropolis.VAN_SPOT, PI * 0.5],
}
const VAN_ROOF := 2.38
## Žebříky na střeše: x posun od osy dodávky.
const ROOF_X := [-0.45, 0.45]

var persist_id := "company_base"
var van_spot := "zakladna"

var garage: Node3D
var _workshop: Node3D
var _hall: Node3D
var _van: Node3D
var _van_labels: Array[Label3D] = []
var _van_charger: RobotCharger
const VAN_CHARGER_ID := "dodavka"
const VAN_CHARGER_Z := -2.76


static func create(parent: Node3D, g: Node3D) -> CompanyBase:
	var cb := CompanyBase.new()
	cb.name = "CompanyBase"
	cb.garage = g
	parent.add_child(cb)
	return cb


func _ready() -> void:
	add_to_group("company_base")
	add_to_group("persist")
	Events.inventory_changed.connect(refresh)
	Events.game_loaded.connect(refresh)
	Events.cosmetics_changed.connect(_repaint_van)
	refresh()


## Přestaví základnu podle toho, co hráč vlastní.
func refresh() -> void:
	var ws := GameState.has_item("base_workshop")
	if ws and _workshop == null:
		_build_workshop()
	elif not ws and _workshop:
		_workshop.queue_free()
		_workshop = null
	var hall := GameState.has_item("base_hall")
	if hall and _hall == null:
		_build_hall()
	elif not hall and _hall:
		_hall.queue_free()
		_hall = null
	var van := GameState.has_item("company_van")
	if van and _van == null:
		_build_van()
	elif not van and _van:
		_van.queue_free()
		_van = null
		_van_charger = null
	for c in get_tree().get_nodes_in_group("robot_charger"):
		if c.has_method("refresh_title"):
			c.refresh_title()


# ------------------------------------------------------------------ dílna

func _build_workshop() -> void:
	_workshop = Node3D.new()
	_workshop.name = "Workshop"
	garage.add_child(_workshop)
	var b := MeshBuilder.new(80)
	var red := Color(0.75, 0.2, 0.18)
	var steel := Color(0.6, 0.62, 0.65)
	# nářaďová skříň v levém předním rohu
	b.add_box(Vector3(0.6, 1.8, 1.1), Vector3(-2.5, 0.9, 2.3), red)
	for k in 5:
		b.add_box(Vector3(0.02, 0.22, 0.95), Vector3(-2.19, 0.35 + k * 0.3, 2.3), red.darkened(0.25))
		b.add_box(Vector3(0.03, 0.03, 0.3), Vector3(-2.17, 0.4 + k * 0.3, 2.3), steel)
	# děrovaná deska s nářadím nad pracovním stolem
	b.add_box(Vector3(2.2, 0.9, 0.03), Vector3(-1.0, 1.65, -3.27), Color(0.78, 0.66, 0.5))
	for k in 7:
		var x := -1.95 + k * 0.32
		b.add_box(Vector3(0.05, 0.28 + (k % 3) * 0.08, 0.04), Vector3(x, 1.65, -3.23), [Color(0.95, 0.75, 0.15), Color(0.2, 0.5, 0.85), steel][k % 3])
	# zářivka pod stropem
	b.add_box(Vector3(1.6, 0.06, 0.18), Vector3(0, 2.75, 0), Color(0.95, 0.96, 0.98))
	# regál s krabicemi u pravé stěny vpředu
	b.add_box(Vector3(0.5, 1.6, 1.2), Vector3(2.55, 0.8, 2.2), steel)
	for k in 3:
		b.add_box(Vector3(0.4, 0.3, 0.5), Vector3(2.55, 0.35 + k * 0.5, 2.0), Color(0.72, 0.56, 0.36))
		b.add_box(Vector3(0.4, 0.25, 0.45), Vector3(2.55, 0.33 + k * 0.5, 2.55), Color(0.72, 0.56, 0.36).darkened(0.1))
	b.to_instance(_workshop, "WorkshopMesh")
	var body := StaticBody3D.new()
	_workshop.add_child(body)
	for pair in [[Vector3(0.6, 1.8, 1.1), Vector3(-2.5, 0.9, 2.3)], [Vector3(0.5, 1.6, 1.2), Vector3(2.55, 0.8, 2.2)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = pair[0]
		cs.shape = bs
		cs.position = pair[1]
		body.add_child(cs)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.6, 0)
	lamp.light_energy = 0.8
	lamp.omni_range = 6.0
	lamp.light_color = Color(0.95, 0.97, 1.0)
	_workshop.add_child(lamp)
	var sign := Label3D.new()
	sign.text = "DÍLNA"
	sign.font_size = 40
	sign.pixel_size = 0.005
	sign.outline_size = 8
	sign.outline_modulate = Color(0.3, 0.12, 0.1)
	sign.position = Vector3(-1.0, 2.3, -3.24)
	_workshop.add_child(sign)
	Props.board_behind(sign, Color(0.3, 0.12, 0.1))


# ------------------------------------------------------------------ hala

func _build_hall() -> void:
	var spec := {
		"name": "CompanyHall", "position": HALL_POS, "width": 8.0, "depth": 7.0,
		"found_h": 0.12, "wall_h": 3.6, "roof_h": 0.9, "seed": 81,
		"wall_color": Color(0.9, 0.92, 0.94), "roof_color": Color(0.25, 0.45, 0.6),
		"trim_color": Color(0.25, 0.55, 0.75), "interior": true, "interior_color": Color(0.92, 0.93, 0.92),
		"floor_color": Color(0.6, 0.62, 0.63), "chimney": false,
		"openings": [
			{"side": "front", "type": "opening", "u": -0.8, "width": 3.8, "height": 3.1, "sill": 0.0},
			{"side": "front", "u": 2.7, "width": 1.3, "height": 1.2, "sill": 1.2},
			{"side": "left", "u": 0.0, "width": 2.4, "height": 1.2, "sill": 1.4},
			{"side": "right", "u": 0.0, "width": 2.4, "height": 1.2, "sill": 1.4},
		],
		"door_step": false,
		"interior_light": Vector3(0, 3.2, 0),
	}
	_hall = HouseBuilder.build(get_parent(), spec)
	var b := MeshBuilder.new(82)
	# nástěnka zakázek a pracovní pult
	b.add_box(Vector3(1.5, 1.0, 0.04), Vector3(2.4, 1.6, -3.26), Color(0.7, 0.55, 0.4))
	for k in 6:
		b.add_box(Vector3(0.3, 0.36, 0.01), Vector3(1.85 + (k % 3) * 0.48, 1.4 + (k / 3) * 0.42, -3.23), Color(0.98, 0.96, 0.85) if k % 2 == 0 else Color(0.85, 0.95, 0.98), Basis(Vector3.FORWARD, (k - 2) * 0.05), 0.0)
	b.add_box(Vector3(2.4, 0.08, 0.8), Vector3(-2.6, 0.95, 1.8), Color(0.55, 0.4, 0.26))
	b.add_box(Vector3(2.3, 0.9, 0.7), Vector3(-2.6, 0.45, 1.8), Color(0.25, 0.45, 0.6))
	# barevné pruhy na podlaze (místo pro dodávku)
	for sx: float in [-2.6, 1.0]:
		b.add_box(Vector3(0.12, 0.01, 5.0), Vector3(sx, 0.125, 0.5), Color(0.95, 0.8, 0.2), Basis.IDENTITY, 0.0)
	b.to_instance(_hall, "HallMesh")
	var body := StaticBody3D.new()
	_hall.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 1.0, 0.8)
	cs.shape = bs
	cs.position = Vector3(-2.6, 0.5, 1.8)
	body.add_child(cs)
	RobotCharger.build(_hall, Vector3(-0.9, 0.12, -3.28), 0.0, "hala")
	var board := SimpleInteractable.create("[E] Nástěnka zakázek – všechny oblasti", func(_p): get_tree().call_group("ui_root", "open_tablet_section", "zakazky_vse"), Vector3(1.5, 1.0, 0.2), Vector3(2.4, 1.6, -3.2))
	_hall.add_child(board)
	var lbl := Label3D.new()
	lbl.text = "ZAKÁZKY"
	lbl.font_size = 30
	lbl.pixel_size = 0.004
	lbl.outline_size = 6
	lbl.outline_modulate = Color(0.25, 0.2, 0.15)
	lbl.position = Vector3(2.4, 2.2, -3.22)
	_hall.add_child(lbl)
	var sign := Label3D.new()
	sign.text = "CLEAR VIEW s.r.o."
	sign.font_size = 72
	sign.pixel_size = 0.007
	sign.outline_size = 12
	sign.outline_modulate = Color(0.15, 0.35, 0.5)
	sign.position = Vector3(0, 4.2, 3.62)
	_hall.add_child(sign)
	Props.board_behind(sign, Color(0.15, 0.35, 0.5), Vector2(0.2, 0.1), 0.05, Color(0.9, 0.92, 0.94))
	WorldMap.add_rect(Rect2(HALL_POS.x - 4.0, HALL_POS.z - 3.5, 8.0, 7.0), Color(0.25, 0.45, 0.6), "Hala")


# ------------------------------------------------------------------ dodávka

## Nový lak / polep: přebarvit karoserii a nápisy na místě (stojan s roboty zůstává).
func _repaint_van() -> void:
	if _van == null:
		return
	var old := _van.get_node_or_null("VanMesh")
	if old:
		_van.remove_child(old)
		old.queue_free()
	_van_body().to_instance(_van, "VanMesh")
	for l in _van_labels:
		_paint_label(l)


func _van_body() -> MeshBuilder:
	var b := MeshBuilder.new(83)
	var white := Cosmetics.color("van")
	var blue := Cosmetics.color("livery")
	var dark := Color(0.12, 0.12, 0.13)
	var glass := Color(0.2, 0.27, 0.32)
	# nákladový prostor (vzadu, -Z) a kabina (vpředu, +Z)
	b.add_box(Vector3(2.0, 1.95, 3.4), Vector3(0, 1.4, -0.75), white)
	b.add_box(Vector3(1.96, 1.2, 1.5), Vector3(0, 1.0, 1.7), white)
	b.add_box(Vector3(1.9, 0.6, 1.1), Vector3(0, 1.75, 1.5), white.darkened(0.03))
	# šikmé čelo kabiny od kapoty (y 1.6, z 2.44) ke střeše kabiny (y 2.05, z 2.05); sklo leží těsně na něm
	var ws := Basis(Vector3.RIGHT, -0.713)
	b.add_box(Vector3(1.9, 0.596, 0.3), Vector3(0, 1.727, 2.132), white.darkened(0.03), ws, 0.0)
	b.add_box(Vector3(1.8, 0.54, 0.03), Vector3(0, 1.835, 2.257), glass, ws, 0.0)
	for s: float in [-1.0, 1.0]:
		b.add_box(Vector3(0.03, 0.45, 0.8), Vector3(s * 0.97, 1.8, 1.45), glass, Basis.IDENTITY, 0.0)
		b.add_box(Vector3(0.03, 0.18, 3.3), Vector3(s * 1.005, 1.15, -0.75), blue, Basis.IDENTITY, 0.0)
		for z: float in [-1.5, 1.6]:
			b.add("cyl10", Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.68, 0.26, 0.68)), Vector3(s * 0.9, 0.34, z)), dark, 0.0)
			b.add("cyl10", Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.36, 0.015, 0.36)), Vector3(s * 1.04, 0.34, z)), Color(0.75, 0.75, 0.75), 0.0)
	b.add_box(Vector3(2.04, 0.2, 5.0), Vector3(0, 0.45, 0.0), dark)
	b.add_box(Vector3(0.4, 0.12, 0.04), Vector3(-0.7, 0.9, 2.47), Color(0.98, 0.95, 0.75), Basis.IDENTITY, 0.0)
	b.add_box(Vector3(0.4, 0.12, 0.04), Vector3(0.7, 0.9, 2.47), Color(0.98, 0.95, 0.75), Basis.IDENTITY, 0.0)
	# střešní nosič na žebříky
	var rack := Color(0.55, 0.57, 0.6)
	for z: float in [-2.1, -0.5, 1.1]:
		b.add_box(Vector3(1.9, 0.05, 0.08), Vector3(0, VAN_ROOF - 0.03, z), rack)
	for x: float in [-0.92, 0.92]:
		b.add_box(Vector3(0.05, 0.1, 3.4), Vector3(x, VAN_ROOF + 0.02, -0.5), rack)
		for z: float in [-2.1, 1.1]:
			b.add_box(Vector3(0.05, 0.08, 0.05), Vector3(x, VAN_ROOF - 0.08, z), rack)
	return b


func _paint_label(lbl: Label3D) -> void:
	var paint := Cosmetics.color("van")
	var light := paint.get_luminance() > 0.45
	var c := Cosmetics.color("livery", true)
	# nápis musí být od laku dost odlišný: na světlém ztmavit, na tmavém zesvětlit
	for i in 8:
		if absf(c.get_luminance() - paint.get_luminance()) >= 0.38:
			break
		c = c.darkened(0.2) if light else c.lightened(0.2)
	lbl.modulate = c
	lbl.outline_modulate = paint


func _build_van() -> void:
	_van = Node3D.new()
	_van.name = "CompanyVan"
	get_parent().add_child(_van)
	_place_van()
	_van_labels.clear()
	_van_body().to_instance(_van, "VanMesh")
	var body := StaticBody3D.new()
	_van.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.0, 2.2, 5.0)
	cs.shape = bs
	cs.position = Vector3(0, 1.1, 0)
	body.add_child(cs)
	for s: float in [-1.0, 1.0]:
		var lbl := Label3D.new()
		lbl.text = "CLEAR VIEW\nmytí oken"
		lbl.font_size = 56
		lbl.pixel_size = 0.006
		lbl.outline_size = 8
		_paint_label(lbl)
		_van_labels.append(lbl)
		lbl.position = Vector3(s * 1.02, 1.65, -0.8)
		lbl.rotation.y = s * PI * 0.5
		_van.add_child(lbl)
	var door := SimpleInteractable.create("[E] Firemní dodávka – kam pojedeme?", _van_interact, Vector3(2.2, 2.2, 5.2), Vector3(0, 1.1, 0))
	door.prompt_fn = _van_prompt
	door.set_meta("van_rack", self)
	_van.add_child(door)
	# nabíjecí stojan na zadních dveřích (roboti se nabíjejí i během jízdy – jedou s dodávkou)
	var rack := Color(0.55, 0.57, 0.6)
	var bracket := MeshBuilder.new(84)
	for x: float in [-0.7, 0.7]:
		bracket.add_box(Vector3(0.08, 0.08, 0.32), Vector3(x, 1.1, -2.6), rack)
		bracket.add_box(Vector3(0.08, 0.08, 0.32), Vector3(x, 1.45, -2.6), rack)
	bracket.to_instance(_van, "ChargerBracket")
	_van_charger = RobotCharger.build(_van, Vector3(0, -0.05, VAN_CHARGER_Z), PI, VAN_CHARGER_ID, true)
	_place_van()


## Postaví dodávku na místo podle van_spot a posune značku na mapě.
func _place_van() -> void:
	if _van == null:
		return
	var spot: Array = VAN_SPOTS.get(van_spot, VAN_SPOTS["zakladna"])
	_van.position = spot[0]
	_van.rotation = Vector3(0, spot[1], 0)
	_van.reset_physics_interpolation()
	if _van_charger and _van_charger.is_inside_tree():
		var fleet := RobotFleet.get_fleet(self)
		if fleet:
			fleet.follow_charger(_van_charger)
	var p: Vector3 = spot[0]
	WorldMap.move_marker("van", Vector2(p.x, p.z), "Firemní dodávka", Color(0.2, 0.55, 0.78))


## Dodávka přijede s hráčem do cíle (zakladna / venkov / predmesti / mesto).
func park_van(dest: String) -> void:
	van_spot = dest if VAN_SPOTS.has(dest) else "zakladna"
	_place_van()


## Položí žebříky na střešní nosič (nejvýš 2). Vrací, kolik se jich vešlo.
func load_ladders(list: Array) -> int:
	if _van == null:
		return 0
	var n := 0
	for l in list:
		if n >= ROOF_X.size():
			break
		_lay_on_roof(l, n)
		n += 1
	return n


## Žebříky, které právě leží na střeše dodávky.
func roof_ladders() -> Array[Ladder]:
	var out: Array[Ladder] = []
	if _van == null:
		return out
	for n in get_tree().get_nodes_in_group("ladders"):
		var l := n as Ladder
		if l == null or not l.is_owned() or l.is_carried() or not l.lying:
			continue
		var loc := _van.global_transform.affine_inverse() * l.global_position
		if loc.y > VAN_ROOF - 0.3 and absf(loc.x) < 1.2 and absf(loc.z) < 4.5:
			out.append(l)
	return out


func _van_prompt(player) -> String:
	if player.carried == null and not roof_ladders().is_empty():
		return "[E] Sundat žebřík ze střechy dodávky (%d nahoře) · cestovat přes tablet [Tab] → Firma" % roof_ladders().size()
	return ""


func _van_interact(player) -> void:
	var up := roof_ladders()
	if player.carried == null and not up.is_empty() and player.mode == Player.Mode.WALK:
		player.pick_up(up[0])
		return
	get_tree().call_group("ui_root", "open_tablet_section", "firma")


## Hráč naloží nesený žebřík na nosič (2 místa).
func stow_ladder(player, lad: Ladder) -> bool:
	if _van == null:
		return false
	var used := roof_ladders()
	if used.size() >= ROOF_X.size():
		Events.toast("Na střeše dodávky už jsou dva žebříky.", "info")
		return true
	var slot := 0
	for k in ROOF_X.size():
		var taken := false
		for l in used:
			var loc := _van.global_transform.affine_inverse() * l.global_position
			if absf(loc.x - ROOF_X[k]) < 0.2:
				taken = true
		if not taken:
			slot = k
			break
	player.release_carried()
	_lay_on_roof(lad, slot)
	Audio.play("step", -6.0, 0.7)
	Events.toast("Žebřík je na střeše dodávky – při cestě dodávkou jede s tebou.", "info")
	return true


func _lay_on_roof(lad: Ladder, slot: int) -> void:
	# střed žebříku = střed nosiče; nejdřív položit, pak podle skutečného směru posunout patu
	var center := _van.global_transform * Vector3(ROOF_X[slot], VAN_ROOF + 0.06, -0.5)
	lad.lay_down(center, _van.rotation.y)
	var d := lad.global_basis * Ladder.up_local()
	d.y = 0.0
	lad.lay_down(center - d.normalized() * lad.length * 0.5, _van.rotation.y)


func van_position() -> Vector3:
	return _van.global_position if _van else VAN_POS


func save_state() -> Dictionary:
	return {"van": van_spot}


func load_state(d) -> void:
	if d is Dictionary:
		van_spot = str(d.get("van", "zakladna"))
	_place_van()
	_fix_old_roof_ladders.call_deferred()


## Starší verze parkovaly dodávku na základně o 1,6 m blíž k hale. Žebříky, které
## zůstaly ležet na střeše na staré pozici, znovu naložíme na střechu.
func _fix_old_roof_ladders() -> void:
	if _van == null or van_spot != "zakladna":
		return
	var stray: Array = []
	for l in roof_ladders():
		stray.append(l)
	for n in get_tree().get_nodes_in_group("ladders"):
		var l := n as Ladder
		if l and l.is_owned() and l.lying and not l.is_carried() and l.global_position.y > 1.8 \
				and Vector2(l.global_position.x - OLD_VAN_POS.x, l.global_position.z - OLD_VAN_POS.z).length() < 3.5 \
				and not stray.has(l):
			stray.append(l)
	if not stray.is_empty():
		load_ladders(stray)


func has_van() -> bool:
	return _van != null


func hall_built() -> bool:
	return _hall != null


func workshop_built() -> bool:
	return _workshop != null

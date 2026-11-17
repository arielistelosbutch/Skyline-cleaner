class_name RopeAnchor
extends StaticBody3D
## Kotvicí bod na střeše. S lanovým setem se k němu hráč připne a spouští se
## po fasádě: [S]/[W] dolů a nahoru, [A]/[D] do stran v omezeném rozsahu.
## Nejde o fyzikální simulaci lana – hráč „visí" na rovině fasády, což je
## stabilní a pohodlně ovladatelné. Lokálně: +Z = ven z budovy (kolmo k fasádě).

const ROPE_ITEM := "rope_kit"
const ROPE_LENGTH := 30.0
const SIDE_RANGE := 2.4
const SPEED := 1.25
## Vzdálenost těžiště hráče od fasády při visení.
const HANG_OUT := 0.42

@export var anchor_id := ""
## Vzdálenost od kotvy (počátek uzlu) k líci fasády ve směru +Z.
@export var wall_out := 0.4
## Výška atiky nad střechou (lano přes ni vede k hráči).
@export var edge_h := 0.5
## Výška střechy (podlahy, kam se hráč vrací) – světová Y.
@export var roof_y := 0.0
@export var ground_y := 0.0


func _ready() -> void:
	add_to_group("rope_anchor")
	collision_layer = 1
	collision_mask = 0
	set_meta("interactable", self)
	var b := MeshBuilder.new(41)
	b.add_box(Vector3(0.3, 0.06, 0.3), Vector3(0, 0.03, 0), Color(0.4, 0.42, 0.45))
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.06, 0.35, 0.06)), Vector3(0, 0.2, 0)), Color(0.85, 0.65, 0.15), 0.02)
	b.add("cyl10", Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.14, 0.03, 0.14)), Vector3(0, 0.4, 0)), Color(0.85, 0.65, 0.15), 0.02)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 0.6, 0.45)
	cs.shape = box
	cs.position = Vector3(0, 0.3, 0)
	add_child(cs)


func get_prompt(_player) -> String:
	if not GameState.has_item(ROPE_ITEM):
		return "Kotvicí bod – k připnutí potřebuješ lanový set (obchod)"
	return "[E] Připnout se lanem a spustit se po fasádě"


func interact(player) -> void:
	if not GameState.has_item(ROPE_ITEM):
		Events.toast("Kotvicí bod. Na slaňování potřebuješ lanový set s úvazkem – koupíš ho v obchodě.", "info")
		return
	player.attach_rope(self)


func outward() -> Vector3:
	return global_basis.z.normalized()


func side() -> Vector3:
	return global_basis.x.normalized()


## Nejvyšší poloha nohou na laně (těsně pod hranou střechy).
func top_feet() -> float:
	return roof_y - 1.45


func bottom_feet() -> float:
	return maxf(ground_y, global_position.y - ROPE_LENGTH)


func side_range() -> float:
	return SIDE_RANGE * (1.4 if Talents.has_effect("rope_speed") else 1.0)


func speed() -> float:
	return SPEED * Talents.mult("rope_speed")


## Poloha těžiště (nohou) hráče visícího na laně.
func hang_pos(u: float, feet_y: float) -> Vector3:
	var p := global_position + outward() * (wall_out + HANG_OUT) + side() * u
	p.y = feet_y
	return p


## Jak daleko od fasády se hráč postaví, když se odepne dole.
func exit_out() -> float:
	return 0.35


## Kam se hráč postaví, když vyleze zpět na střechu.
func roof_spot() -> Vector3:
	var p := global_position - outward() * 1.1
	p.y = roof_y + 0.05
	return p

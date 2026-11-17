class_name ClimbGrip
extends RopeAnchor
## Talent „Přísavné rukavice" (vrchol stromu Robotika, pro radost): hráč vyleze
## po stěně kterékoli budovy. Technicky je to neviditelná „kotva" vytvořená na
## místě, kde se hráč chytil zdi – pohyb, mytí oken, výstup na střechu a seskok
## dole tedy fungují stejně jako na laně (ověřený systém).
## Do stran se dá lézt jen kousek (±2 m) – po zdi se nehledá její konec.

const CLIMB_SPEED := 0.9
const CLIMB_SIDE := 2.0


## Zkusí vytvořit úchop na zdi, na kterou hráč míří. Vrací null, když to nejde.
static func try_create(player: Node3D, from: Vector3, dir: Vector3, exclude: Array[RID]) -> ClimbGrip:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1.6, 1, exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.3:
		return null
	var col: Object = hit["collider"]
	if col.has_meta("window") or col.has_meta("interactable") or not (col is StaticBody3D):
		return null
	n.y = 0.0
	n = n.normalized()
	var wall: Vector3 = hit["position"]
	# střecha: paprsek shora kousek za lícem zdi
	var probe := wall - n * 0.6
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(probe.x, wall.y + 80.0, probe.z), Vector3(probe.x, wall.y + 0.5, probe.z), 1, exclude)
	var roof := space.intersect_ray(q2)
	if roof.is_empty() or (roof["normal"] as Vector3).y < 0.7:
		return null
	var roof_h: float = (roof["position"] as Vector3).y
	if roof_h < player.global_position.y + 2.2:
		return null
	var g := ClimbGrip.new()
	g.wall_out = 1.0
	g.edge_h = 0.0
	g.roof_y = roof_h
	g.ground_y = player.global_position.y
	var origin := wall - n * g.wall_out
	origin.y = roof_h
	g.transform = Transform3D(Basis.looking_at(-n, Vector3.UP), origin)
	return g


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0


func get_prompt(_player) -> String:
	return ""


func interact(_player) -> void:
	pass


func hides_rope() -> bool:
	return true


func side_range() -> float:
	return CLIMB_SIDE


func speed() -> float:
	return CLIMB_SPEED


func bottom_feet() -> float:
	return ground_y


func attach_text() -> String:
	return "Přísavné rukavice drží! [W]/[S] nahoru a dolů, [A]/[D] kousek do stran. Okna myješ jako obvykle [E]. Nahoře vylezeš na střechu, dole seskočíš [mezerník]."


func status_text() -> String:
	return "lezeš po zdi – do střechy %.0f m" % maxf(0.0, top_feet() - (get_tree().get_first_node_in_group("player").rope_y if get_tree() else 0.0))

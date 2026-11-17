extends Node
## Data pro herní mapu: tvary (silnice, budovy, pole) a značky.
## Svět je registruje při stavbě, kompas a oblasti je jen čtou.

var shapes: Array[Dictionary] = []   # {"rect": Rect2 (x,z), "color": Color, "label": String}
var markers: Array[Dictionary] = []  # {"id","pos": Vector2,"label","color"}
var bounds := Rect2(-120, -70, 240, 150)
## Oblasti: id -> {"name", "bounds"}. Mapa ukazuje tu, ve které hráč je.
var areas := {}
const DEFAULT_AREA := "venkov"


func clear() -> void:
	shapes.clear()
	markers.clear()
	areas.clear()
	add_area(DEFAULT_AREA, "Oblast I – Venkov · Lipová Lhota", bounds)


func add_area(id: String, area_name: String, rect: Rect2) -> void:
	areas[id] = {"name": area_name, "bounds": rect}


## Oblast, do které patří bod (x, z) ve světě.
func area_at(p: Vector2) -> String:
	for id in areas:
		if (areas[id]["bounds"] as Rect2).grow(60.0).has_point(p):
			return id
	return DEFAULT_AREA


func area_bounds(id: String) -> Rect2:
	return areas.get(id, {}).get("bounds", bounds)


func area_name(id: String) -> String:
	return areas.get(id, {}).get("name", "")


func add_rect(rect: Rect2, color: Color, label: String = "") -> void:
	shapes.append({"rect": rect, "color": color, "label": label})


func add_marker(id: String, pos: Vector2, label: String, color: Color) -> void:
	markers.append({"id": id, "pos": pos, "label": label, "color": color})


## Přesune značku (např. firemní dodávka zaparkovala jinde); když není, přidá ji.
func move_marker(id: String, pos: Vector2, label: String, color: Color) -> void:
	for m in markers:
		if m["id"] == id:
			m["pos"] = pos
			return
	add_marker(id, pos, label, color)

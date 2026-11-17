extends Node
## Obchod s vybavením: katalog, ceny (se slevou z talentů), podmínky a nákup.
## Nástroje a přípravky se berou z ToolData (.tres), ostatní předměty
## z GameState.ITEMS. Položky budoucích etap jsou v katalogu označené.

const CATEGORIES := ["Nástroje", "Chemie", "Přístupové vybavení", "Technologie", "Firma"]

## Připravované položky (zatím je nelze koupit – jen je ukazujeme v katalogu).
const COMING := []


## Seznam položek k prodeji v kategorii: {id, name, desc, price, level}.
func catalog(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in GameState.all_tools():
		var cat := "Chemie" if t.kind == "spray" else "Nástroje"
		if cat == category and t.price > 0:
			out.append({"id": t.id, "name": t.display_name, "desc": t.description, "base_price": t.price, "level": t.required_level, "rep": t.required_rep, "order": t.shop_order})
	for id in GameState.ITEMS:
		var it: Dictionary = GameState.ITEMS[id]
		if it.get("category", "") == category and int(it.get("price", 0)) > 0:
			out.append({"id": id, "name": it["name"], "desc": it["desc"], "base_price": int(it["price"]), "level": int(it.get("level", 1)), "rep": int(it.get("rep", 1)), "order": int(it.get("order", 50))})
	out.sort_custom(func(a, b): return a["order"] < b["order"])
	for d in out:
		d["price"] = price(d["id"])
	return out


func coming(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in COMING:
		if c["category"] == category:
			out.append(c)
	return out


func base_price(id: String) -> int:
	var t := GameState.get_tool(id)
	if t:
		return t.price
	return int(GameState.ITEMS.get(id, {}).get("price", 0))


func required_level(id: String) -> int:
	var t := GameState.get_tool(id)
	if t:
		return t.required_level
	return int(GameState.ITEMS.get(id, {}).get("level", 1))


func required_rep(id: String) -> int:
	var t := GameState.get_tool(id)
	if t:
		return t.required_rep
	return int(GameState.ITEMS.get(id, {}).get("rep", 1))


func price(id: String) -> int:
	var m := GameState.price_multiplier()
	if id.begins_with("robot_"):
		m *= Talents.mult("robot_price")
	return int(round(base_price(id) * m))


## Kolik obchod dá za starého robota při výměně (polovina ceny).
func trade_in(model: String) -> int:
	return int(round(base_price(model) * 0.5 / 10.0)) * 10


## Nejslabší robot ve firmě horšího modelu než `model` (index), nebo -1.
func weakest_below(model: String) -> int:
	var best := -1
	for i in GameState.robot_units.size():
		var m: String = GameState.robot_units[i]
		if GameState.robot_tier(m) < GameState.robot_tier(model):
			if best < 0 or GameState.robot_tier(m) < GameState.robot_tier(GameState.robot_units[best]):
				best = i
	return best


## Doplatek za výměnu robota idx za model.
func upgrade_cost(idx: int, model: String) -> int:
	return maxi(0, price(model) - trade_in(GameState.robot_units[idx]))


# ------------------------------------------------------------------ drony: prodej a výměna

## Pořadí modelu dronu (0 = Vážka, vyšší = lepší), -1 = není dron.
func drone_tier(model: String) -> int:
	return DroneDepot.DRONE_MODELS.find(model)


## Nejslabší vlastněný dron horší než `model`, nebo "".
func weakest_drone_below(model: String) -> String:
	for m in DroneDepot.DRONE_MODELS:
		if GameState.has_item(m) and drone_tier(m) < drone_tier(model):
			return m
	return ""


func drone_upgrade_cost(old: String, model: String) -> int:
	return maxi(0, price(model) - trade_in(old))


func drone_upgrade_problem(model: String) -> String:
	if GameState.has_item(model):
		return "Už vlastníš."
	var old := weakest_drone_below(model)
	if old == "":
		return "Nemáš slabší dron."
	var rq := _req_problem(model)
	if rq != "":
		return rq
	if GameState.money < drone_upgrade_cost(old, model):
		return "Chybí ti %s." % UITheme.money(drone_upgrade_cost(old, model) - GameState.money)
	return ""


func upgrade_drone(model: String) -> bool:
	var problem := drone_upgrade_problem(model)
	if problem != "":
		Events.toast(problem, "warn")
		return false
	var old := weakest_drone_below(model)
	var cost := drone_upgrade_cost(old, model)
	GameState.add_money(-cost)
	GameState.remove_item(old)
	GameState.add_item(model)
	Audio.play("coins", -4.0, 0.9)
	Events.toast("%s vyměněn za %s – starý jsme vzali za %s, doplatil jsi %s. Nový dron čeká nabitý v depu." % [GameState.item_name(old), GameState.item_name(model), UITheme.money(trade_in(old)), UITheme.money(cost)], "success")
	return true


## Prodej dronu zpět obchodu (polovina ceny).
func sell_drone(model: String) -> bool:
	if drone_tier(model) < 0 or not GameState.has_item(model):
		return false
	var got := trade_in(model)
	GameState.remove_item(model)
	GameState.add_money(got)
	Audio.play("coins", -4.0, 1.05)
	Events.toast("%s prodán za %s." % [GameState.item_name(model), UITheme.money(got)], "success")
	return true


func _req_problem(id: String) -> String:
	if GameState.level < required_level(id):
		return "Od úrovně %d." % required_level(id)
	if GameState.stars() < required_rep(id):
		return "Od pověsti %s." % GameState.stars_text(required_rep(id))
	return ""


## Výměna nejslabšího horšího robota za `model`: prázdný řetězec = jde, jinak důvod.
func upgrade_problem(model: String) -> String:
	var idx := weakest_below(model)
	if idx < 0:
		return "Nemáš slabšího robota."
	var rq := _req_problem(model)
	if rq != "":
		return rq
	if GameState.money < upgrade_cost(idx, model):
		return "Chybí ti %s." % UITheme.money(upgrade_cost(idx, model) - GameState.money)
	return ""


func upgrade_robot(model: String) -> bool:
	var problem := upgrade_problem(model)
	if problem != "":
		Events.toast(problem, "warn")
		return false
	var idx := weakest_below(model)
	var old: String = GameState.robot_units[idx]
	var cost := upgrade_cost(idx, model)
	GameState.add_money(-cost)
	GameState.replace_robot(idx, model)
	Audio.play("coins", -4.0, 0.9)
	Events.toast("%s vyměněn za %s – starý jsme vzali za %s, doplatil jsi %s. Nový robot je u tebe." % [GameState.item_name(old), GameState.item_name(model), UITheme.money(trade_in(old)), UITheme.money(cost)], "success")
	return true


## Prázdný řetězec = lze koupit, jinak důvod.
func buy_problem(id: String) -> String:
	if GameState.is_robot(id):
		if GameState.robot_count() >= GameState.MAX_ROBOTS:
			return "Máš %d roboty (maximum)." % GameState.MAX_ROBOTS
	elif GameState.has_item(id):
		return "Už vlastníš."
	if base_price(id) <= 0:
		return "Není na prodej."
	var req := str(GameState.ITEMS.get(id, {}).get("requires", ""))
	if req != "" and not GameState.has_item(req):
		return "Nejdřív kup: %s." % GameState.item_name(req)
	if GameState.level < required_level(id):
		return "Od úrovně %d." % required_level(id)
	if GameState.stars() < required_rep(id):
		return "Od pověsti %s." % GameState.stars_text(required_rep(id))
	if GameState.money < price(id):
		return "Chybí ti %s." % UITheme.money(price(id) - GameState.money)
	return ""


func buy(id: String) -> bool:
	var problem := buy_problem(id)
	if problem != "":
		Events.toast(problem, "warn")
		return false
	var p := price(id)
	GameState.add_money(-p)
	GameState.add_item(id)
	if DroneDepot.DRONE_MODELS.has(id):
		Audio.play("coins", -4.0, 0.9)
		Events.toast("Koupeno: %s (%s). Dron čeká v depu na náměstí ve Velkoměstě – s autopilotem sám myje okna rozpracované zakázky tam." % [GameState.item_name(id), UITheme.money(p)], "success")
		return true
	if id == DroneDepot.DEPOT_ITEM:
		Audio.play("coins", -4.0, 0.9)
		Events.toast("Depo dronů je tvoje – stojí na náměstí ve Velkoměstě Horizont. Teď ještě dron (Technologie).", "success")
		return true
	if GameState.is_robot(id):
		Audio.play("coins", -4.0, 0.9)
		Events.toast("Koupeno: %s (%s). Robot je u tebe – přilož ho na okno [G]. Roboti ve firmě: %d / %d." % [GameState.item_name(id), UITheme.money(p), GameState.robot_count(), GameState.MAX_ROBOTS], "success")
		return true
	var t := GameState.get_tool(id)
	if t:
		GameState.set_active(id)
		get_tree().call_group("player", "hold", id)
	Audio.play("coins", -4.0, 0.9)
	Events.toast("Koupeno: %s (%s). %s" % [GameState.item_name(id), UITheme.money(p), "Máš ho v ruce – přepínání kolečkem myši." if t and t.kind == "rag" else ("Přípravek je vybraný – přepnout [Q]." if t else "")], "success")
	return true

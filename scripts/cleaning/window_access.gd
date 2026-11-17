class_name WindowAccess
extends RefCounted
## Co hráč potřebuje, aby na okno dosáhl celé (podle výšky horní hrany skla nad zemí).
## Počítá se stejnými čísly jako dosah v pracovním režimu (CleaningController),
## takže tablet i značky u oken říkají pravdu: bez nutného vybavení okno celé umýt nejde.

enum { GROUND, CHAIR, LADDER_S, LADDER_E, ROPE, PLATFORM, NONE }

const TELE_BONUS := 1.7          # teleskopická tyč (ToolData.reach_bonus)
const CHAIR_FEET := 0.47         # Chair.SEAT_SIZE.y
const LADDER_S_LEN := 4.2
const LADDER_E_LEN := 6.0

const LABEL := {
	GROUND: "ze země",
	CHAIR: "židle (garáž)",
	LADDER_S: "žebřík (stačí malý)",
	LADDER_E: "výsuvný žebřík 6 m",
	ROPE: "lano a úvazek (kotva na střeše)",
	PLATFORM: "závěsná plošina (oprávnění)",
	NONE: "zatím nedosažitelné",
}
const SHORT := {GROUND: "", CHAIR: "židle", LADDER_S: "žebřík", LADDER_E: "dlouhý žebřík", ROPE: "lano", PLATFORM: "plošina", NONE: "?"}


static func _ladder_feet(length: float) -> float:
	return length * cos(Ladder.ANGLE) - 1.05


## Výška horní hrany skla nad terénem (budovy stojí na rovině y = 0).
static func top_height(w: CleanableWindow) -> float:
	var a := w.plane_to_world(Vector2(0.0, w.glass_size.y)).y
	var b := w.plane_to_world(Vector2(w.glass_size.x, w.glass_size.y)).y
	return maxf(a, b)


## Nejnižší stupeň přístupu, který na celé okno stačí. `tele` = hráč má teleskopickou tyč.
static func tier(w: CleanableWindow, tele: bool = false) -> int:
	var h := top_height(w) + 0.02
	var reach := CleaningController.REACH_HIGH + (TELE_BONUS if tele else 0.0)
	if h <= reach:
		return GROUND
	if h <= CHAIR_FEET + reach:
		return CHAIR
	if h <= _ladder_feet(LADDER_S_LEN) + reach:
		return LADDER_S
	if h <= _ladder_feet(LADDER_E_LEN) + reach:
		return LADDER_E
	if anchor_for(w, false) != null:
		return ROPE
	if anchor_for(w, true) != null:
		return PLATFORM
	return NONE


## Kotvicí bod (platform=false) nebo závěsná plošina (true), ze které se na okno dosáhne.
static func anchor_for(w: CleanableWindow, platform: bool = false) -> RopeAnchor:
	var tree := w.get_tree()
	if tree == null:
		return null
	var c := w.plane_to_world(w.glass_size * 0.5)
	var n := w.normal()
	for node in tree.get_nodes_in_group("rope_anchor"):
		var a := node as RopeAnchor
		if a == null or a.outward().dot(n) < 0.9 or (a is SuspendedPlatform) != platform:
			continue
		var d := c - a.global_position
		if absf(d.dot(n)) > 1.5:
			continue
		var side := absf(d.dot(a.side()))
		if side + w.glass_size.x * 0.5 > a.side_range() + CleaningController.REACH_SIDE + 0.05:
			continue
		var bottom := w.plane_to_world(Vector2(w.glass_size.x * 0.5, 0.0)).y
		var top := top_height(w)
		if top <= a.top_feet() + CleaningController.REACH_HIGH and bottom >= a.bottom_feet() + CleaningController.REACH_LOW - 0.05:
			return a
	return null


## Má hráč vybavení pro daný stupeň? (židli má každý v garáži)
static func owns(t: int) -> bool:
	match t:
		GROUND, CHAIR:
			return true
		LADDER_S:
			return GameState.has_item("ladder_small") or GameState.has_item("ladder_ext")
		LADDER_E:
			return GameState.has_item("ladder_ext")
		ROPE:
			return GameState.has_item("rope_kit")
		PLATFORM:
			return GameState.has_item(SuspendedPlatform.CERT_ITEM)
	return false


static func has_tele() -> bool:
	return GameState.has_item("tele_squeegee") or GameState.has_item("tele_mop") or GameState.has_item("fold_mop") or GameState.has_item("brush_tele")


## Zvládne hráč s tím, co má, okno umýt celé? Žebřík stačí i vyšší, lano kde je kotva.
static func can_reach(w: CleanableWindow) -> bool:
	var t := tier(w, has_tele())
	if t == NONE:
		return false
	for k in range(t, ROPE):
		if owns(k):
			return true
	# lano i plošina jdou použít jen tam, kde je kotva / plošina nad oknem
	if owns(ROPE) and anchor_for(w, false) != null:
		return true
	if owns(PLATFORM) and anchor_for(w, true) != null:
		return true
	return false


## Krátký popis toho, co okno potřebuje (pro značku u okna).
static func need_short(w: CleanableWindow) -> String:
	return SHORT[tier(w, has_tele())]


## Co je k zakázce nutné: {"tier", "tier_tele", "missing", "unreachable", "text"}
static func requirement(window_ids: PackedStringArray) -> Dictionary:
	var top := GROUND
	var top_tele := GROUND
	var count := {}
	var unreachable := 0
	for wid in window_ids:
		var w := WindowRegistry.find_window(wid)
		if w == null:
			continue
		var t := tier(w)
		top = maxi(top, t)
		top_tele = maxi(top_tele, tier(w, true))
		count[t] = int(count.get(t, 0)) + 1
		if not can_reach(w):
			unreachable += 1
	var text := ""
	if top == NONE:
		text = "Některá okna zatím nejdou umýt žádným vybavením."
	elif top <= CHAIR:
		text = "Nic navíc – všechna okna jsou ze země." if top == GROUND else "Nic navíc – na vyšší okna stačí židle z garáže."
	else:
		var parts := []
		for t in range(LADDER_S, NONE):
			if count.has(t):
				var n := int(count[t])
				parts.append("%s (%d %s)" % [LABEL[t], n, "okno" if n == 1 else ("okna" if n < 5 else "oken")])
		text = ", ".join(parts)
		text = text.substr(0, 1).to_upper() + text.substr(1)
		if top_tele < top:
			text += "; s teleskopickou tyčí stačí %s" % LABEL[top_tele]
		text += "."
	if unreachable > 0:
		text += "  ✖ S tím, co máš, nedosáhneš na %d %s – vybavení koupíš v obchodě (náves nebo pobočky)." % [unreachable, "okno" if unreachable == 1 else ("okna" if unreachable < 5 else "oken")]
	elif top > CHAIR:
		text += "  ✔ Máš potřebné vybavení."
	return {"tier": top, "tier_tele": top_tele, "missing": unreachable > 0, "unreachable": unreachable, "text": text}

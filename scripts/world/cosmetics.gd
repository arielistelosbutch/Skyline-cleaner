class_name Cosmetics
extends RefCounted
## Vzhled firmy za peníze: lak dodávky, polep (pruh a nápis) a pracovní
## oblečení (barva rukávů). Čistě kosmetické, kupuje a přepíná se v tabletu
## (Firma → Vzhled firmy). Stav v GameState.cosmetics:
## {"owned": [id, …], "van": id, "livery": id, "outfit": id}.

const SLOTS := {
	"van": {"name": "Lak dodávky", "default": "van_bila"},
	"livery": {"name": "Polep firmy", "default": "liv_modry"},
	"outfit": {"name": "Pracovní oblečení", "default": "out_modra"},
}

## id → [slot, název, cena, barva, (barva 2)]
const OPTIONS := {
	"van_bila": ["van", "Bílá", 0, Color(0.95, 0.96, 0.97)],
	"van_modra": ["van", "Nebeská modrá", 1800, Color(0.55, 0.74, 0.9)],
	"van_zelena": ["van", "Lesní zelená", 1800, Color(0.3, 0.5, 0.36)],
	"van_zluta": ["van", "Slunečná žlutá", 2200, Color(0.98, 0.82, 0.3)],
	"van_grafit": ["van", "Grafit", 2500, Color(0.27, 0.29, 0.32)],
	"van_vinova": ["van", "Vínová", 2500, Color(0.5, 0.16, 0.2)],
	"liv_modry": ["livery", "Modrý pruh", 0, Color(0.2, 0.55, 0.78), Color(0.16, 0.44, 0.62)],
	"liv_oranzovy": ["livery", "Oranžový pruh", 900, Color(0.95, 0.5, 0.15), Color(0.82, 0.38, 0.08)],
	"liv_zeleny": ["livery", "Zelený pruh", 900, Color(0.35, 0.7, 0.3), Color(0.2, 0.5, 0.2)],
	"liv_zlaty": ["livery", "Zlatý pruh", 1600, Color(0.86, 0.7, 0.28), Color(0.62, 0.48, 0.12)],
	"liv_bily": ["livery", "Bílý pruh", 900, Color(0.97, 0.97, 0.97), Color(0.95, 0.95, 0.95)],
	"out_modra": ["outfit", "Modrá montérka", 0, Color(0.22, 0.42, 0.62)],
	"out_oranzova": ["outfit", "Oranžová reflexní", 700, Color(0.95, 0.48, 0.12)],
	"out_zelena": ["outfit", "Zelená pracovní", 700, Color(0.27, 0.45, 0.28)],
	"out_seda": ["outfit", "Šedá softshell", 900, Color(0.38, 0.4, 0.43)],
	"out_cervena": ["outfit", "Červená mikina", 900, Color(0.7, 0.18, 0.18)],
	"out_bezova": ["outfit", "Béžová kanvas", 1100, Color(0.72, 0.62, 0.45)],
}


static func options(slot: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in OPTIONS:
		if OPTIONS[id][0] == slot:
			out.append(id)
	return out


static func selected(slot: String) -> String:
	var id: String = GameState.cosmetics.get(slot, "")
	if not OPTIONS.has(id):
		id = SLOTS[slot]["default"]
	return id


static func owns(id: String) -> bool:
	if not OPTIONS.has(id):
		return false
	if int(OPTIONS[id][2]) == 0:
		return true
	return id in (GameState.cosmetics.get("owned", []) as Array)


static func color(slot: String, second := false) -> Color:
	var o: Array = OPTIONS[selected(slot)]
	if second and o.size() > 4:
		return o[4]
	return o[3]


static func sleeve() -> Color:
	return color("outfit")


## Koupí (pokud je třeba) a nastaví. Vrací prázdný řetězec, nebo důvod, proč nejde.
static func choose(id: String) -> String:
	if not OPTIONS.has(id):
		return "Neznámá volba."
	var o: Array = OPTIONS[id]
	if not owns(id):
		var price := int(o[2])
		if GameState.money < price:
			return "Na to nemáš dost peněz (%s)." % UITheme.money(price)
		GameState.add_money(-price)
		var owned: Array = GameState.cosmetics.get("owned", [])
		owned.append(id)
		GameState.cosmetics["owned"] = owned
		Audio.play("coins", -4.0, 1.1)
	GameState.cosmetics[o[0]] = id
	Events.cosmetics_changed.emit()
	return ""

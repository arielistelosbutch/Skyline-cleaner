extends Node
## Stav postavy a firmy: peníze, zkušenosti, úroveň, inventář, vybavení, statistiky.
## Herní hodnoty ovlivněné talenty a vylepšeními se počítají tady.

const START_MONEY := 150
const START_INVENTORY: Array[String] = ["rag_old", "detergent_basic", "chair_wood", "bucket_basic", "finger"]

const TOOL_PATHS := [
	"res://data/tools/rag_old.tres", "res://data/tools/rag_micro.tres",
	"res://data/tools/sponge.tres", "res://data/tools/squeegee_25.tres",
	"res://data/tools/squeegee_35.tres", "res://data/tools/detergent_basic.tres",
	"res://data/tools/degreaser.tres", "res://data/tools/detergent_pro.tres",
	"res://data/tools/tele_mop.tres", "res://data/tools/tele_squeegee.tres",
	"res://data/tools/brush_electric.tres", "res://data/tools/chem_special.tres",
	"res://data/tools/washer_electric.tres", "res://data/tools/fold_mop.tres",
	"res://data/tools/brush_tele.tres", "res://data/tools/finger.tres",
]

## Předměty, které nejsou čisticí nástroje (vybavení, vylepšení).
const ITEMS := {
	"chair_wood": {"name": "Dřevěná židle", "category": "Přístupové vybavení", "desc": "Postav ji pod okno a vyskoč na ni, dosáhneš výš.", "price": 0},
	"bucket_basic": {"name": "Obyčejný kýbl", "category": "Nástroje", "desc": "V garáži. Vymácháš v něm hadr nebo namočíš houbičku. U domů zákazníků najdeš kohoutek nebo sud s vodou.", "price": 0},
	"bucket_carry": {"name": "Kbelík s uchem", "category": "Nástroje", "desc": "Přenosný kbelík na vodu. Postav si ho k domu, kde myješ, a vymáchej v něm nástroj nebo dolij rozprašovač – voda vydrží na 6 vymáchání. Naplní se sám, když ho postavíš k sudu, kohoutku nebo ke kýblu v garáži. Najdeš ho u garáže.", "price": 90, "order": 9},
	"ladder_small": {"name": "Malý přenosný žebřík", "category": "Přístupové vybavení", "desc": "Hliníkový žebřík 4,2 m. Opři ho o zeď, vylez a zastav se v jakékoli výšce – dosáhneš na okna v patře. Najdeš ho opřený u garáže.", "price": 480, "level": 3, "rep": 1, "order": 20},
	"ladder_ext": {"name": "Výsuvný žebřík 6 m", "category": "Přístupové vybavení", "desc": "Delší výsuvný žebřík pro vysoká okna patrových domů a vil.", "price": 1250, "level": 5, "rep": 3, "order": 21},
	"rope_kit": {"name": "Úvazek a lano", "category": "Přístupové vybavení", "desc": "Horolezecký úvazek a 30m lano. Na střeše bytového domu se připneš ke kotvicímu bodu a spustíš se po fasádě.", "price": 1900, "level": 6, "rep": 3, "order": 22},
	"sprayer_pressure": {"name": "Tlakový rozprašovač", "category": "Nástroje", "desc": "Tlaková nádrž s pumpičkou a dlouhou tryskou. Nastříkáš okna až na 7 metrů – třeba patro rovnou ze země, než vylezeš na žebřík. Nádržka pojme o 15 nástřiků víc.", "price": 690, "level": 4, "rep": 2, "order": 10},
	"tank_backpack": {"name": "Zádová nádrž", "category": "Nástroje", "desc": "Nádrž na záda s hadičkou k rozprašovači: +30 nástřiků. Hodí se hlavně na laně a na žebříku, kde se k vodě nechodí snadno.", "price": 540, "level": 3, "rep": 2, "order": 11},
	"platform_cert": {"name": "Oprávnění k obsluze plošin", "category": "Přístupové vybavení", "desc": "Kurz a průkaz pro obsluhu závěsných plošin. Na střechách výškových budov ve městě (Meridian, Hotel Grand) pak nastoupíš do koše a projedeš celou fasádu – dolů, nahoru i do stran.", "price": 2400, "level": 8, "rep": 3, "order": 23},
	"robot_mini": {"name": "Robot na okna Mini", "category": "Technologie", "desc": "Přiložíš ho na sklo okna z rozpracované zakázky [G] a umyje ho sám – mezitím můžeš dělat jiné okno. Baterie vydrží asi 2 minuty práce, pak ho sundej [E] a dej nabít do stojanu (garáž, pobočky obchodu). Na silnou špínu a trus je slabší.", "price": 3200, "level": 9, "rep": 4, "order": 40},
	"robot_pro": {"name": "Robot na okna Pro", "category": "Technologie", "desc": "Silnější a rychlejší robot s větší podložkou a baterií na zhruba 4 minuty práce. Poradí si i s odolnější špínou.", "price": 7800, "level": 11, "rep": 5, "order": 41},
	"robot_max": {"name": "Robot na okna Max", "category": "Technologie", "desc": "Nejnovější model: velká podložka, rychlá jízda a baterie na zhruba 5,5 minuty. Zvládne i silnou špínu a většinu trusu – ruční dočištění bývá potřeba jen výjimečně.", "price": 14500, "level": 13, "rep": 5, "order": 42},
	"base_workshop": {"name": "Dílna v garáži", "category": "Firma", "desc": "Garáž na základně se změní v dílnu: nářaďová skříň, deska s nářadím, regál a světlo. Stojan v garáži dostane rychlonabíječku – roboti se tam nabíjí 2× rychleji.", "price": 12000, "level": 6, "rep": 2, "order": 60},
	"base_hall": {"name": "Firemní hala", "category": "Firma", "desc": "Nová hala Clear View s.r.o. vedle garáže: nástěnka se všemi zakázkami, stojan s rychlonabíjením 3× a zázemí firmy – všechny zakázky platí o 5 % víc.", "price": 30000, "level": 10, "rep": 4, "order": 61, "requires": "base_workshop"},
	"company_van": {"name": "Firemní dodávka", "category": "Firma", "desc": "Dodávka s logem firmy (lak a polep si pak vybereš v tabletu – Firma → Vzhled firmy). Parkuje u základny a odveze tě odkudkoli – v tabletu (Firma) vybereš základnu, náves, Předměstí, Město nebo Velkoměsto. Žebříky vezeš na střeše a na zadních dveřích má nabíjecí stojan pro 4 roboty – nabíjí se i za jízdy.", "price": 26000, "level": 7, "rep": 3, "order": 62},
	"drone_depot": {"name": "Depo dronů (pronájem, Velkoměsto)", "category": "Technologie", "desc": "Přistávací plocha na náměstí ve Velkoměstě Horizont pro 3 drony s nabíjením a ovládacím pultem. Bez depa drony létat nemůžou.", "price": 15000, "level": 14, "rep": 5, "order": 50},
	"drone_vazka": {"name": "Dron Vážka", "category": "Technologie", "desc": "Lehký dron s mycí hlavou. S autopilotem sám létá z depa k oknům rozpracované zakázky ve Velkoměstě – nejdřív k nejvyšším patrům – a když mu dochází baterie (asi 5 minut práce), vrátí se nabít.", "price": 16000, "level": 14, "rep": 5, "order": 51, "requires": "drone_depot"},
	"drone_albatros": {"name": "Dron Albatros", "category": "Technologie", "desc": "Silnější dron: rychlejší let, větší mycí hlava, odolnější špína a baterie na 7 minut práce.", "price": 26000, "level": 15, "rep": 5, "order": 52, "requires": "drone_depot"},
	"drone_sokol": {"name": "Dron Sokol", "category": "Technologie", "desc": "Nejrychlejší dron firmy: velká hlava, silný přítlak a baterie na 9 minut. Poradí si skoro s každou špínou.", "price": 38000, "level": 17, "rep": 5, "order": 53, "requires": "drone_depot"},
	"platform_turbo": {"name": "Turbo navijáky plošin", "category": "Přístupové vybavení", "desc": "Výkonnější navijáky pro závěsné plošiny: koš jezdí nahoru a dolů 2× rychleji. Na mrakodrapech ve Velkoměstě ušetří spoustu času.", "price": 9000, "level": 14, "rep": 5, "order": 24, "requires": "platform_cert"},
	"sprayer_wide": {"name": "Rozprašovač s nastavitelnou tryskou", "category": "Nástroje", "desc": "Lepší tryska pro všechny přípravky: nástřik pokryje o 35 % větší plochu.", "price": 320, "level": 1, "rep": 2, "order": 9},
}

## Roboti na okna: firma jich může mít až MAX_ROBOTS, modely od nejslabšího po nejlepší.
const MAX_ROBOTS := 4
const ROBOT_MODELS := ["robot_mini", "robot_pro", "robot_max"]
## Vlastnění roboti – model každého kusu (pořadí = číslo robota ve firmě).
var robot_units: Array[String] = []

var money := START_MONEY
var xp := 0
var level := 1
var talent_points := 0
## Pověst u zákazníků (body). Hvězdy odemykají těžší poptávky, víc nabídek a lepší vybavení.
var reputation := 0
const REP_STEPS := [0, 60, 170, 340, 600]
var inventory: Array[String] = []
var unlocked_areas: Array[String] = ["venkov"]
var stats := {}
var history: Array = []
## Aktuálně zvolený ruční nástroj a přípravek.
var active_wipe := "rag_old"
var active_spray := "detergent_basic"
## Náplň rozprašovače (počet nástřiků). Doplňuje se u vody (kohoutek, sud, kýbl).
var tank := 30.0
const TANK_BASE := 30.0
## Nádržka elektrického stěrače (sekundy dávkování).
var washer := 0.0
var _empty_warn_t := 0
## Krok úvodního tutoriálu (Tutorial.Step), -1 = neběží / hotovo.
var tutorial_step := -1
## Denní doba (hodiny 0..24) a počet uplynulých herních dní (roční období).
var clock := 8.0
var day := 0
## Vzhled firmy: barva dodávky, pracovní oblečení, polep (id volby).
var cosmetics := {}

var _tools := {}
var tool_order: Array[String] = []


func _ready() -> void:
	for path in TOOL_PATHS:
		var t: ToolData = load(path)
		if t:
			_tools[t.id] = t
			tool_order.append(t.id)
	reset()


func reset() -> void:
	money = START_MONEY
	xp = 0
	level = 1
	talent_points = 0
	reputation = 0
	inventory = START_INVENTORY.duplicate()
	robot_units.clear()
	unlocked_areas = ["venkov"]
	stats = {"windows_cleaned": 0, "money_earned": 0, "money_spent": 0, "contracts_done": 0, "play_time": 0.0, "robot_windows": 0, "drone_windows": 0}
	history = []
	active_wipe = "rag_old"
	active_spray = "detergent_basic"
	tank = TANK_BASE
	washer = 90.0
	tutorial_step = -1
	clock = 8.0
	day = 0
	cosmetics = {}
	if is_inside_tree() and has_node("/root/Talents"):
		Talents.reset()


func _process(delta: float) -> void:
	stats["play_time"] = float(stats.get("play_time", 0.0)) + delta


# ------------------------------------------------------------------ nástroje

func get_tool(id: String) -> ToolData:
	return _tools.get(id)


func all_tools() -> Array[ToolData]:
	var out: Array[ToolData] = []
	for id in tool_order:
		out.append(_tools[id])
	return out


## Vlastněné nástroje daného druhu ("rag" = ruční, "spray" = přípravky), seřazené.
func owned_tools(kind: String) -> Array[ToolData]:
	var out: Array[ToolData] = []
	for id in tool_order:
		var t: ToolData = _tools[id]
		if t.kind == kind and inventory.has(id):
			out.append(t)
	return out


## Nejlepší vlastněný nástroj daného druhu (podle síly).
func best_tool(kind: String) -> ToolData:
	var best: ToolData = null
	for t in owned_tools(kind):
		if t.visual == "finger":
			continue   # prst kreslí, nemyje
		if best == null or t.strength > best.strength:
			best = t
	return best


func wipe_tool() -> ToolData:
	var t: ToolData = _tools.get(active_wipe)
	if t == null or not inventory.has(active_wipe):
		var owned := owned_tools("rag")
		t = owned[0] if not owned.is_empty() else null
		if t:
			active_wipe = t.id
	return t


func spray_tool() -> ToolData:
	var t: ToolData = _tools.get(active_spray)
	if t == null or not inventory.has(active_spray):
		var owned := owned_tools("spray")
		t = owned[0] if not owned.is_empty() else null
		if t:
			active_spray = t.id
	return t


func set_active(id: String) -> void:
	var t: ToolData = _tools.get(id)
	if t == null or not inventory.has(id):
		return
	if t.kind == "rag":
		active_wipe = id
	else:
		active_spray = id
	Events.equipment_changed.emit(id)


func has_item(id: String) -> bool:
	return inventory.has(id)


func item_name(id: String) -> String:
	var t: ToolData = _tools.get(id)
	if t:
		return t.display_name
	return ITEMS.get(id, {}).get("name", id)


## Odebere předmět (prodej dronu apod.). Roboty odebírá replace_robot / prodej robotů.
func remove_item(id: String) -> bool:
	if is_robot(id) or not inventory.has(id):
		return false
	inventory.erase(id)
	Events.inventory_changed.emit()
	return true


func add_item(id: String) -> void:
	if is_robot(id):
		add_robot(id)
		return
	if not inventory.has(id):
		inventory.append(id)
		Events.inventory_changed.emit()


# ------------------------------------------------------------------ roboti

## Rychlost nabíjení stojanu: Dílna zrychlí stojan v garáži 2×, stojan v hale nabíjí 3×.
func charger_speed(charger_id: String) -> float:
	if charger_id == "hala":
		return 3.0
	if charger_id == "zakladna" and has_item("base_workshop"):
		return 2.0
	return 1.0


func is_robot(id: String) -> bool:
	return ROBOT_MODELS.has(id)


## Úroveň modelu (0 = Mini, vyšší = lepší).
func robot_tier(model: String) -> int:
	return ROBOT_MODELS.find(model)


func robot_count(model: String = "") -> int:
	if model == "":
		return robot_units.size()
	return robot_units.count(model)


## Přidá nového robota (když je ve firmě místo). Vrací false při plném počtu.
func add_robot(model: String) -> bool:
	if not is_robot(model) or robot_units.size() >= MAX_ROBOTS:
		return false
	robot_units.append(model)
	_sync_robot_items()
	Events.inventory_changed.emit()
	return true


## Vymění robota na pozici idx za jiný model.
func replace_robot(idx: int, model: String) -> bool:
	if idx < 0 or idx >= robot_units.size() or not is_robot(model):
		return false
	robot_units[idx] = model
	_sync_robot_items()
	Events.inventory_changed.emit()
	return true


## Modely robotů v inventáři = modely, kterých má firma aspoň jeden kus (kvůli has_item).
func _sync_robot_items() -> void:
	for m in ROBOT_MODELS:
		var have := robot_units.has(m)
		if have and not inventory.has(m):
			inventory.append(m)
		elif not have and inventory.has(m):
			inventory.erase(m)


# ------------------------------------------------------------------ hodnoty z talentů a vylepšení

## Násobič účinnosti ručního čištění (Pevná ruka, Mistr čistoty).
func clean_mult(t: ToolData = null) -> float:
	var m := Talents.mult("clean_mult")
	if t and t.electric:
		m *= Talents.mult("electric")
	return m


## Extra dosah teleskopického nástroje (s talentem Dlouhý dosah).
func reach_bonus(t: ToolData) -> float:
	if t == null or t.reach_bonus <= 0.0:
		return 0.0
	return t.reach_bonus * Talents.mult("tele_reach")


func blade_width_mult() -> float:
	return Talents.mult("blade_width")


func complete_threshold() -> float:
	return Talents.min_value("complete_threshold", CleanableWindow.COMPLETE_THRESHOLD)


func spray_radius_mult() -> float:
	var m := Talents.mult("spray_radius")
	if has_item("sprayer_wide"):
		m *= 1.35
	return m


## Odpařování: Úsporné dávkování drží sklo déle mokré.
func evaporation_mult() -> float:
	return 0.7 if Talents.has_effect("spray_radius") else 1.0


func carry_speed_mult() -> float:
	return 1.0 if Talents.has_effect("carry") else 0.85


## Násobič odměn – talent „Dobrý vyjednavač".
func reward_multiplier() -> float:
	var m := Talents.mult("reward") * (1.0 + 0.05 * (stars() - 1))
	if has_item("base_hall"):
		m *= 1.05
	return m


## Hvězdy pověsti 1–5.
func stars() -> int:
	var st := 1
	for k in REP_STEPS.size():
		if reputation >= REP_STEPS[k]:
			st = k + 1
	return st


## Body do další hvězdy (Vector2i(máš, potřebuješ)); na 5 hvězdách (0, 0).
func rep_progress() -> Vector2i:
	var st := stars()
	if st >= REP_STEPS.size():
		return Vector2i.ZERO
	return Vector2i(reputation - REP_STEPS[st - 1], REP_STEPS[st] - REP_STEPS[st - 1])


static func stars_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(maxi(0, 5 - n))


func add_reputation(amount: int) -> void:
	if amount <= 0:
		return
	var before := stars()
	reputation += amount
	Events.toast("Pověst +%d" % amount, "info")
	if stars() > before:
		Audio.play("levelup", -4.0, 1.1)
		Events.toast("Pověst stoupla na %s! Ozve se víc zákazníků a s náročnější prací, obchod nabídne lepší vybavení." % stars_text(stars()), "money")
		ContractManager.ensure_offers()
	Events.inventory_changed.emit()


func xp_multiplier() -> float:
	return Talents.mult("xp")


func price_multiplier() -> float:
	return Talents.mult("price")


# ------------------------------------------------------------------ peníze a zkušenosti

func xp_to_next(lvl: int = -1) -> int:
	if lvl < 0:
		lvl = level
	return 100 + (lvl - 1) * 72


func level_title(lvl: int = -1) -> String:
	if lvl < 0:
		lvl = level
	if lvl >= 8:
		return "Profesionální čistič"
	if lvl >= 4:
		return "Začínající profesionál"
	return "Amatér"


func add_money(amount: int) -> void:
	money += amount
	if amount > 0:
		stats["money_earned"] = int(stats.get("money_earned", 0)) + amount
	else:
		stats["money_spent"] = int(stats.get("money_spent", 0)) - amount
	Events.money_changed.emit(money, amount)


func add_xp(amount: int) -> void:
	xp += amount
	var leveled := false
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		talent_points += 1
		leveled = true
		Events.level_up.emit(level)
	Events.xp_changed.emit(xp, level, amount)
	if leveled:
		Audio.play("levelup")
		if level >= Suburb.UNLOCK_LEVEL and not unlocked_areas.has(Suburb.AREA_ID):
			unlock_area(Suburb.AREA_ID)
			Events.toast("Nová oblast: Předměstí Javorov! Autobus jede z návsi – čekají tam patrové domy, vila i bytový dům.", "info")
		if level >= City.UNLOCK_LEVEL and not unlocked_areas.has(City.AREA_ID):
			unlock_area(City.AREA_ID)
			Events.toast("Nová oblast: Město Brodec! Autobus jede z návsi i z Předměstí – kanceláře, hotel a obchodní dům. Na výškové budovy budeš potřebovat závěsnou plošinu.", "info")
		if level >= Metropolis.UNLOCK_LEVEL and not unlocked_areas.has(Metropolis.AREA_ID):
			unlock_area(Metropolis.AREA_ID)
			Events.toast("Nová oblast: Velkoměsto Horizont! Autobus jede z Brodce (nebo firemní dodávkou) – opravdové mrakodrapy. Na horní patra se vyplatí drony z depa na náměstí.", "info")


## Kapacita rozprašovače: základ + tlakový rozprašovač + zádová nádrž, × talent Větší nádržka.
func tank_max() -> float:
	var cap := TANK_BASE
	if has_item("sprayer_pressure"):
		cap += 15.0
	if has_item("tank_backpack"):
		cap += 30.0
	return cap * Talents.mult("tank")


## Spotřebuje jeden nástřik. Prázdná nádržka = false (a jednou za čas upozornění).
func use_tank() -> bool:
	if tank < 1.0:
		var now := Time.get_ticks_msec()
		if now - _empty_warn_t > 4000:
			_empty_warn_t = now
			Events.toast("Rozprašovač je prázdný – doplň ho u vody (kohoutek, sud, kýbl v garáži). Mýt jde i bez něj, jen pomaleji.", "warn")
			Events.cleaning_hint.emit("Nádržka je prázdná. Doplň ji u vody, nebo drhni nasucho – jde to, ale pomaleji.")
		return false
	tank -= 1.0
	Events.tank_changed.emit(tank, tank_max())
	return true


func refill_tank() -> void:
	tank = tank_max()
	washer = washer_max()
	Events.tank_changed.emit(tank, tank_max())


## Kolik sekund dávkování pojme nádržka elektrického stěrače (× talent Větší nádržka).
func washer_max() -> float:
	var t := get_tool("washer_electric")
	return (t.auto_dose if t else 90.0) * Talents.mult("tank")


## Spotřebuje `dt` sekund dávkování stěrače. Vrací false, když je nádržka prázdná.
func use_washer(dt: float) -> bool:
	if washer <= 0.0:
		return false
	washer = maxf(0.0, washer - dt)
	return true


func unlock_area(id: String) -> void:
	if unlocked_areas.has(id):
		return
	unlocked_areas.append(id)
	Events.area_unlocked.emit(id)
	if has_node("/root/ContractManager"):
		ContractManager.ensure_offers()


# ------------------------------------------------------------------ ukládání

func to_dict() -> Dictionary:
	return {
		"money": money, "xp": xp, "level": level, "talent_points": talent_points, "reputation": reputation,
		"inventory": inventory.duplicate(), "unlocked_areas": unlocked_areas.duplicate(),
		"stats": stats.duplicate(), "history": history.duplicate(true),
		"active_wipe": active_wipe, "active_spray": active_spray,
		"talents": Talents.to_dict(), "tank": tank, "washer": washer,
		"robot_units": robot_units.duplicate(),
		"tutorial_step": tutorial_step,
		"clock": clock, "day": day, "cosmetics": cosmetics.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	reset()
	money = int(d.get("money", START_MONEY))
	xp = int(d.get("xp", 0))
	level = maxi(1, int(d.get("level", 1)))
	talent_points = int(d.get("talent_points", 0))
	reputation = int(d.get("reputation", 0))
	tutorial_step = int(d.get("tutorial_step", -1))
	# starší uložení: pokračuje se v létě dopoledne
	clock = clampf(float(d.get("clock", 9.0)), 0.0, 23.99)
	day = maxi(0, int(d.get("day", 2)))
	cosmetics = (d.get("cosmetics", {}) as Dictionary).duplicate()
	inventory.clear()
	for it in d.get("inventory", START_INVENTORY):
		inventory.append(str(it))
	# prst na kreslení do prachu má každý (i ve starších uloženích)
	if not inventory.has("finger"):
		inventory.append("finger")
	robot_units.clear()
	if d.has("robot_units"):
		for m in d["robot_units"]:
			if ROBOT_MODELS.has(str(m)) and robot_units.size() < MAX_ROBOTS:
				robot_units.append(str(m))
	else:
		# uložení z Etapy 5 (bez kusů): od každého vlastněného modelu jeden robot
		for m in ROBOT_MODELS:
			if inventory.has(m):
				robot_units.append(m)
	_sync_robot_items()
	unlocked_areas.clear()
	for a in d.get("unlocked_areas", ["venkov"]):
		unlocked_areas.append(str(a))
	if level >= Suburb.UNLOCK_LEVEL and not unlocked_areas.has(Suburb.AREA_ID):
		unlocked_areas.append(Suburb.AREA_ID)
	if level >= City.UNLOCK_LEVEL and not unlocked_areas.has(City.AREA_ID):
		unlocked_areas.append(City.AREA_ID)
	if level >= Metropolis.UNLOCK_LEVEL and not unlocked_areas.has(Metropolis.AREA_ID):
		unlocked_areas.append(Metropolis.AREA_ID)
	var s: Dictionary = d.get("stats", {})
	for k in s:
		stats[k] = s[k]
	history = d.get("history", []).duplicate(true)
	active_wipe = str(d.get("active_wipe", "rag_old"))
	active_spray = str(d.get("active_spray", "detergent_basic"))
	wipe_tool()
	spray_tool()
	Talents.from_dict(d.get("talents", {}))
	tank = clampf(float(d.get("tank", tank_max())), 0.0, tank_max())
	washer = clampf(float(d.get("washer", washer_max())), 0.0, washer_max())
	Events.tank_changed.emit(tank, tank_max())
	Events.money_changed.emit(money, 0)
	Events.xp_changed.emit(xp, level, 0)
	Events.inventory_changed.emit()

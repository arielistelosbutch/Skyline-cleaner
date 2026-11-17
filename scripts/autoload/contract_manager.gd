extends Node
## Správa zakázek: přijetí, přerušení, postup, dokončení, odměna,
## volitelný bonus za rychlost a opakované zakázky (pravidelný úklid).

const CONTRACT_PATHS := [
	"res://data/contracts/zakladna_garaz.tres",
	"res://data/contracts/novak_bungalow.tres",
	"res://data/contracts/chata_rybnik.tres",
	"res://data/contracts/sklenik_dvorakova.tres",
	"res://data/contracts/obchod_naves.tres",
	"res://data/contracts/statek_horak.tres",
	"res://data/contracts/pr_dum_maly.tres",
	"res://data/contracts/pr_kavarna.tres",
	"res://data/contracts/pr_vila.tres",
	"res://data/contracts/pr_bytovy_dum.tres",
	"res://data/contracts/pr_skola.tres",
	"res://data/contracts/me_od_vylohy.tres",
	"res://data/contracts/me_od_patra.tres",
	"res://data/contracts/me_cinzak_ulice.tres",
	"res://data/contracts/me_hotel_nizsi.tres",
	"res://data/contracts/me_hotel_vyssi.tres",
	"res://data/contracts/me_meridian_nizsi.tres",
	"res://data/contracts/me_meridian_vyssi.tres",
	"res://data/contracts/vm_oc_vylohy.tres",
	"res://data/contracts/vm_aurora_nizsi.tres",
	"res://data/contracts/vm_oc_patra.tres",
	"res://data/contracts/vm_panorama_vyssi.tres",
	"res://data/contracts/vm_aurora_vyssi.tres",
	"res://data/contracts/vm_horizont_finale.tres",
	"res://data/contracts/vm_panorama_cela.tres",
]
const WINDOW_XP := 10

var contracts := {}      # id -> ContractData
var order: Array[String] = []
var state := {}          # id -> "available" | "active" | "paused" | "completed"
var active_id := ""
## Odpracovaný čas na zakázce v sekundách (jen když je aktivní).
var elapsed := {}
## Kolikrát byla zakázka dokončena (opakování = pravidelný úklid).
var times_done := {}

# ------------------------------------------------------------------ poptávky z vesnice
## Zákazníci z domů na vsi (registruje je svět při stavbě): id -> {name, who, pos, front, all, tree}.
var clients := {}
## Vygenerované poptávky: id -> spec (ukládá se, ContractData se z něj staví znovu).
var offers := {}
var offer_counter := 0
## Kolikrát který zákazník z vesnice dostal hotovou práci (stálý zákazník = příplatek).
var client_done := {}

## Situace, se kterými se zákazníci ozývají. stars = potřebná pověst.
const SITUATIONS := [
	{"id": "bezne", "name": "Běžné mytí", "profile": "venkov_bezne", "diff": 1.0, "stars": 1,
		"dirt": "Lehké", "equip": "Hadr a saponát",
		"text": "Chtěli bychom zase čistá okna. Nic zvláštního – prach, kapky po dešti a sem tam šmouha."},
	{"id": "po_bource", "name": "Po bouřce", "profile": "po_bource", "diff": 1.3, "stars": 1,
		"dirt": "Střední (bláto, šmouhy)", "equip": "Saponát nebo houbička, stěrka",
		"text": "Včerejší bouřka nám ocákala okna blátem a nechala na nich šmouhy. Bláto prý chce nejdřív namočit."},
	{"id": "ptaci", "name": "Ptáci na stromě", "profile": "ptaci_strom", "diff": 1.15, "stars": 1,
		"dirt": "Střední (ptačí trus, pyl)", "equip": "Saponát, hadr",
		"text": "Před domem nám hnízdí kosi a strom práší pyl. Okna to dost odnesla."},
	{"id": "pyl", "name": "Jarní pyl", "profile": "sklenik_pyl", "diff": 1.05, "stars": 1,
		"dirt": "Lehké (pyl)", "equip": "Hadr, stěrka",
		"text": "Kvetou lípy a okna máme žlutá od pylu."},
	{"id": "kuchyn", "name": "Mastná okna", "profile": "kuchyn_mastnota", "diff": 1.45, "stars": 2,
		"dirt": "Střední (mastnota)", "equip": "Odmašťovač, mikrovláknový hadr",
		"text": "Hodně vaříme a smažíme – okna mají mastný film a otisky. Samotná voda na to nestačí."},
	{"id": "zanedbane", "name": "Roky nemyto", "profile": "zanedbane", "diff": 1.8, "stars": 3,
		"dirt": "Silné (vrstvy špíny)", "equip": "Profesionální přípravek, stěrka, trpělivost",
		"text": "Koupili jsme starý dům a okna roky nikdo nemyl. Je na nich tvrdá krusta."},
]
## Rozsah práce: které okna domu.
const SCOPES := [
	{"id": "front", "name": "přední okna", "w": 3},
	{"id": "some", "name": "tři okna", "w": 3},
	{"id": "all", "name": "celý dům", "w": 2},
]


func _ready() -> void:
	for p in CONTRACT_PATHS:
		var c: ContractData = load(p)
		if c:
			contracts[c.id] = c
			order.append(c.id)
	reset()
	Events.window_completed.connect(_on_window_completed)


func reset() -> void:
	for id in offers:
		contracts.erase(id)
		order.erase(id)
	offers.clear()
	offer_counter = 0
	client_done.clear()
	state.clear()
	elapsed.clear()
	times_done.clear()
	for id in order:
		state[id] = "available"
		elapsed[id] = 0.0
		times_done[id] = 0
	active_id = ""
	ensure_offers()


func _process(delta: float) -> void:
	if active_id != "" and not get_tree().paused:
		elapsed[active_id] = float(elapsed.get(active_id, 0.0)) + delta


func get_contract(id: String) -> ContractData:
	return contracts.get(id)


func active() -> ContractData:
	return contracts.get(active_id)


func is_locked(id: String) -> bool:
	var c: ContractData = contracts.get(id)
	return c != null and GameState.level < c.required_level and state.get(id) == "available" and int(times_done.get(id, 0)) == 0


func is_repeat(id: String) -> bool:
	return int(times_done.get(id, 0)) > 0


## Odměna, kterou hráč za zakázku teď dostane (bez bonusu za rychlost).
func reward_money(id: String) -> int:
	var c: ContractData = contracts.get(id)
	if c == null:
		return 0
	var base := float(c.reward_money)
	if is_repeat(id):
		base *= c.repeat_factor
	if c.location.begins_with("Město"):
		base *= Talents.mult("city_pay")
	return int(round(base * GameState.reward_multiplier() / 10.0)) * 10


func reward_xp(id: String) -> int:
	var c: ContractData = contracts.get(id)
	if c == null:
		return 0
	var base := float(c.reward_xp)
	if is_repeat(id):
		base *= c.repeat_factor
	return int(round(base * GameState.xp_multiplier()))


## Zbývající čas pro bonus za rychlost v sekundách (záporné = bonus propadl, INF = bez bonusu).
func bonus_time_left(id: String) -> float:
	var c: ContractData = contracts.get(id)
	if c == null or c.bonus_time_min <= 0.0:
		return INF
	return c.bonus_time_min * 60.0 - float(elapsed.get(id, 0.0))


func accept(id: String) -> void:
	if not contracts.has(id) or is_locked(id):
		return
	if state.get(id) == "completed":
		_restart(id)
	if offers.has(id) and not bool(offers[id].get("prepared", false)):
		# Poptávka: okna domu se zašpiní podle situace (bouřka, mastnota…).
		for wid in contracts[id].window_ids:
			var w := WindowRegistry.find_window(wid)
			if w:
				w.redirty(str(offers[id]["profile"]))
		offers[id]["prepared"] = true
	if state.get(id, "available") == "available":
		# nová zakázka: okna umytá v jiné zakázce mezitím zase zašpinila (jinak by byla hned hotová)
		for wid in contracts[id].window_ids:
			var w := WindowRegistry.find_window(wid)
			if w and w.completed:
				w.redirty()
	if active_id != "" and active_id != id:
		state[active_id] = "paused"
	var resumed: bool = state.get(id) == "paused"
	state[id] = "active"
	active_id = id
	var txt := "Pokračuješ v zakázce: %s" if resumed else ("Pravidelný úklid přijat: %s" if is_repeat(id) else "Zakázka přijata: %s")
	Events.toast(txt % contracts[id].title, "info")
	var req := WindowAccess.requirement(contracts[id].window_ids)
	if req["missing"]:
		Events.toast("Pozor: na %d %s zatím nedosáhneš – v tabletu u zakázky je napsané, co je potřeba." % [int(req["unreachable"]), "okno" if int(req["unreachable"]) == 1 else "oken"], "warn")
	Audio.play("click")
	Events.contract_changed.emit()


## Opakovaná zakázka: okna se znovu zašpiní (jiný vzor špíny).
func _restart(id: String) -> void:
	var c: ContractData = contracts[id]
	for wid in c.window_ids:
		var w := WindowRegistry.find_window(wid)
		if w:
			w.redirty()
	elapsed[id] = 0.0
	state[id] = "available"


func pause_active() -> void:
	if active_id == "":
		return
	state[active_id] = "paused"
	Events.toast("Zakázka přerušena. Rozpracovaná okna zůstávají uložená.", "info")
	active_id = ""
	Events.contract_changed.emit()


func contract_for_window(window_id: String) -> ContractData:
	# Okno může patřit víc zakázkám (příběhová i poptávka) – přednost má ta rozpracovaná.
	var act := active()
	if act and act.window_ids.has(window_id):
		return act
	for id in order:
		if contracts[id].window_ids.has(window_id):
			return contracts[id]
	return null


func can_clean(window_id: String) -> bool:
	var c := active()
	return c != null and c.window_ids.has(window_id)


## Vrací Vector2i(hotová okna, celkem oken).
func progress(id: String) -> Vector2i:
	var c: ContractData = contracts.get(id)
	if c == null:
		return Vector2i.ZERO
	var done := 0
	for wid in c.window_ids:
		var w := WindowRegistry.find_window(wid)
		if w and w.completed:
			done += 1
	if state.get(id) == "completed":
		done = c.window_ids.size()
	return Vector2i(done, c.window_ids.size())


func _on_window_completed(window_id: String) -> void:
	GameState.stats["windows_cleaned"] = int(GameState.stats.get("windows_cleaned", 0)) + 1
	GameState.add_xp(WINDOW_XP)
	var c := contract_for_window(window_id)
	if c and state.get(c.id) == "active":
		_floor_bonus(c, window_id)
		var p := progress(c.id)
		if p.x >= p.y:
			_complete(c.id)
		else:
			Events.toast("Okno je čisté!  +%d XP   (%d / %d)" % [WINDOW_XP, p.x, p.y], "success")
	else:
		Events.toast("Okno je čisté!  +%d XP" % WINDOW_XP, "success")
	Events.contract_changed.emit()


## Patro okna z jeho id (…_p8_2 / …_z8_1 / …_l8_3 / …_r8_1 → 8), nebo -1.
static func floor_of(window_id: String) -> int:
	var re := RegEx.create_from_string("_[a-z](\\d+)_\\d+$")
	var m := re.search(window_id)
	return int(m.get_string(1)) if m else -1


## Kolik oken patra je v zakázce a kolik z nich je umytých: Vector2i(hotovo, celkem).
func floor_progress(c: ContractData, fl: int) -> Vector2i:
	var done := 0
	var total := 0
	for wid in c.window_ids:
		if floor_of(wid) != fl:
			continue
		total += 1
		var w := WindowRegistry.find_window(wid)
		if w and w.completed:
			done += 1
	return Vector2i(done, total)


## Zakázka na celou budovu: patro umyté kolem dokola = bonus XP.
func _floor_bonus(c: ContractData, window_id: String) -> void:
	if c.floor_bonus_xp <= 0:
		return
	var fl := floor_of(window_id)
	if fl < 0:
		return
	var fp := floor_progress(c, fl)
	if fp.y > 0 and fp.x >= fp.y:
		GameState.add_xp(c.floor_bonus_xp)
		GameState.stats["floors_round"] = int(GameState.stats.get("floors_round", 0)) + 1
		Audio.play("levelup", -8.0, 1.3)
		Events.toast("%d. patro umyté kolem dokola!  +%d XP bonus" % [fl, c.floor_bonus_xp], "success")


func _complete(id: String) -> void:
	var c: ContractData = contracts[id]
	var money := reward_money(id)
	var xp := reward_xp(id)
	var bonus := 0
	if bonus_time_left(id) >= 0.0 and bonus_time_left(id) != INF:
		bonus = int(round(c.bonus_money * GameState.reward_multiplier()))
	state[id] = "completed"
	times_done[id] = int(times_done.get(id, 0)) + 1
	if active_id == id:
		active_id = ""
	GameState.add_money(money + bonus)
	GameState.add_xp(xp)
	GameState.stats["contracts_done"] = int(GameState.stats.get("contracts_done", 0)) + 1
	GameState.history.append({
		"id": id, "title": c.title + ("  (pravidelný úklid)" if times_done[id] > 1 else ""), "location": c.location,
		"money": money + bonus, "bonus": bonus, "xp": xp, "windows": c.window_ids.size(),
		"minutes": int(float(elapsed.get(id, 0.0)) / 60.0),
		"date": Time.get_datetime_string_from_system(false, true),
	})
	var rep := reputation_gain(id) + (3 if bonus > 0 else 0)
	Audio.play("coins")
	Events.contract_completed.emit(id, money + bonus, xp)
	if bonus > 0:
		Events.toast("Bonus za rychlou práci: +%s" % UITheme.money(bonus), "success")
	GameState.add_reputation(rep)
	if offers.has(id):
		var cid := str(offers[id]["client"])
		client_done[cid] = int(client_done.get(cid, 0)) + 1
		_remove_offer(id)
		ensure_offers()
	Events.contract_changed.emit()
	# Automatické uložení po dokončení zakázky.
	SaveManager.save_game.call_deferred(true)


## Body pověsti za dokončenou zakázku.
func reputation_gain(id: String) -> int:
	var c: ContractData = contracts.get(id)
	if c == null:
		return 0
	if offers.has(id):
		return int(offers[id].get("rep", 8))
	var r := c.reward_xp / 5
	if int(times_done.get(id, 0)) > 1:
		r = int(r * 0.5)
	return maxi(3, r)


func is_offer(id: String) -> bool:
	return offers.has(id)


# ------------------------------------------------------------------ poptávky z vesnice

var _ensure_queued := false


func register_client(d: Dictionary) -> void:
	clients[str(d["id"])] = d
	if not _ensure_queued:
		_ensure_queued = true
		ensure_offers.call_deferred()


## Kolik poptávek z vesnice visí v tabletu najednou (roste s pověstí).
func offer_slots() -> int:
	var st := GameState.stars()
	return 2 + (1 if st >= 2 else 0) + (1 if st >= 4 else 0) + (1 if GameState.unlocked_areas.has("predmesti") else 0) + (1 if GameState.unlocked_areas.has("mesto") else 0) + (1 if GameState.unlocked_areas.has("velkomesto") else 0)


## Doplní nabídky z vesnice do počtu volných míst.
func ensure_offers() -> void:
	_ensure_queued = false
	if clients.is_empty():
		return
	var open := 0
	for id in offers:
		if state.get(id) != "completed":
			open += 1
	var guard := 0
	while open < offer_slots() and guard < 20:
		guard += 1
		var spec := _roll_offer()
		if spec.is_empty():
			break
		_add_offer(spec)
		open += 1
	Events.contract_changed.emit()


## Po bouřce (Etapa 7) se ozvou další zákazníci s ušpiněnými okny – nad běžný počet
## nabídek (nejvýš o 2). Vrací, kolik poptávek přibylo.
func storm_offers(n: int) -> int:
	if clients.is_empty():
		return 0
	var open := 0
	for id in offers:
		if state.get(id) != "completed":
			open += 1
	var sit := _situation("po_bource")
	var added := 0
	for k in n:
		if open >= offer_slots() + 2:
			break
		var spec := _roll_offer()
		if spec.is_empty():
			break
		spec["situation"] = "po_bource"
		spec["profile"] = sit["profile"]
		spec["money"] = int(round(int(spec["money"]) * 1.2 / 10.0)) * 10
		spec["storm"] = true
		_add_offer(spec)
		open += 1
		added += 1
	if added > 0:
		Events.contract_changed.emit()
	return added


func _busy_clients() -> Dictionary:
	var busy := {}
	for id in offers:
		busy[str(offers[id]["client"])] = true
	return busy


func _roll_offer() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91573 + offer_counter * 7919
	var busy := _busy_clients()
	var free: Array = []
	for cid in clients:
		if not busy.has(cid) and GameState.unlocked_areas.has(str(clients[cid].get("area", "venkov"))):
			free.append(cid)
	if free.is_empty():
		return {}
	free.sort()
	var cid: String = free[rng.randi() % free.size()]
	var cl: Dictionary = clients[cid]
	var stars := GameState.stars()
	var sits: Array = []
	var total_w := 0.0
	for sit in SITUATIONS:
		if int(sit["stars"]) <= stars:
			if sit["id"] == "ptaci" and not bool(cl.get("tree", false)):
				continue
			sits.append(sit)
			total_w += 3.0 if sit["id"] == "bezne" else 2.0
	var pick := rng.randf() * total_w
	var sit: Dictionary = sits[0]
	for s2 in sits:
		pick -= 3.0 if s2["id"] == "bezne" else 2.0
		if pick <= 0.0:
			sit = s2
			break
	var scope: Dictionary = SCOPES[rng.randi() % SCOPES.size()]
	var wins: Array = []
	match scope["id"]:
		"front":
			wins = cl["front"].duplicate()
		"all":
			wins = cl["all"].duplicate()
		_:
			var pool: Array = cl["all"].duplicate()
			for k in 3:
				var j := rng.randi() % pool.size()
				wins.append(pool[j])
				pool.remove_at(j)
			wins.sort()
	var area := 0.0
	for wid in wins:
		var w := WindowRegistry.find_window(wid)
		area += w.glass_size.x * w.glass_size.y if w else 1.2
	var diff: float = sit["diff"]
	var money := int(round((60.0 + area * 48.0 * diff) * float(cl.get("pay", 1.0)) / 10.0)) * 10
	var xp := int(round(20.0 + wins.size() * 12.0 * diff))
	var hurry := rng.randf() < 0.35
	offer_counter += 1
	return {
		"id": "poptavka_%d" % offer_counter, "client": cid, "situation": sit["id"], "profile": sit["profile"],
		"windows": wins, "scope": scope["name"], "money": money, "xp": xp,
		"rep": int(round(5.0 + wins.size() * 2.0 * diff)),
		"bonus_min": (ceilf(wins.size() * 2.5 * diff) if hurry else 0.0),
		"bonus_money": (int(round(money * 0.2 / 10.0)) * 10 if hurry else 0),
		"prepared": false,
	}


func _situation(sid: String) -> Dictionary:
	for sit in SITUATIONS:
		if sit["id"] == sid:
			return sit
	return SITUATIONS[0]


func _build_offer(spec: Dictionary) -> ContractData:
	var cl: Dictionary = clients.get(str(spec["client"]), {})
	var sit := _situation(str(spec["situation"]))
	var c := ContractData.new()
	c.id = str(spec["id"])
	var who: String = cl.get("name", "Zákazník")
	c.title = "%s – %s (%s)" % [who.capitalize() if who.begins_with("p") else who, sit["name"], spec["scope"]]
	var area := str(cl.get("area", "venkov"))
	c.building_type = str(cl.get("building", "Rodinný dům na vsi"))
	c.location = {"predmesti": "Předměstí – Javorov", "mesto": "Město – Brodec", "velkomesto": "Velkoměsto – Horizont"}.get(area, "Venkov – Lipová Lhota")
	var regular := int(client_done.get(str(spec["client"]), 0)) > 0
	c.description = "%s píše: „%s“" % [cl.get("who", "Zákazník"), sit["text"]]
	if regular:
		c.description += "  Už tě zná – stálý zákazník přidá 10 %."
	c.dirt_level_text = sit["dirt"]
	c.recommended_equipment = sit["equip"]
	c.reward_money = int(round(int(spec["money"]) * (1.1 if regular else 1.0) / 10.0)) * 10
	c.reward_xp = int(spec["xp"])
	c.window_ids = PackedStringArray(spec["windows"])
	c.map_position = cl.get("pos", Vector2.ZERO)
	c.required_level = 1
	c.bonus_time_min = float(spec.get("bonus_min", 0.0))
	c.bonus_money = int(spec.get("bonus_money", 0))
	c.bonus_goal = "Nepovinné: zákazník spěchá – hotovo do %d minut práce = +%d Kč." % [int(c.bonus_time_min), c.bonus_money] if c.bonus_time_min > 0.0 else "Žádné – zákazník nespěchá."
	c.repeat_factor = 1.0
	c.dirt_profile_id = str(spec["profile"])
	return c


func _add_offer(spec: Dictionary) -> void:
	var id := str(spec["id"])
	offers[id] = spec
	contracts[id] = _build_offer(spec)
	order.append(id)
	state[id] = "available"
	elapsed[id] = 0.0
	times_done[id] = 0


func _remove_offer(id: String) -> void:
	offers.erase(id)
	contracts.erase(id)
	order.erase(id)
	state.erase(id)
	elapsed.erase(id)
	times_done.erase(id)
	if active_id == id:
		active_id = ""


## Odmítnutí poptávky (jen dokud se na ní nezačalo) – místo ní přijde jiná.
func decline(id: String) -> void:
	if not offers.has(id) or state.get(id) != "available" or bool(offers[id].get("prepared", false)):
		return
	_remove_offer(id)
	Events.toast("Poptávka odmítnuta. Časem se ozve někdo další.", "info")
	ensure_offers()


func to_dict() -> Dictionary:
	var offer_list := []
	for id in offers:
		offer_list.append(offers[id].duplicate(true))
	return {"state": state.duplicate(), "active_id": active_id, "elapsed": elapsed.duplicate(), "times_done": times_done.duplicate(),
		"offers": offer_list, "offer_counter": offer_counter, "client_done": client_done.duplicate()}


func from_dict(d: Dictionary) -> void:
	var saved_clients := clients
	clients = {}
	reset()
	clients = saved_clients
	offer_counter = int(d.get("offer_counter", 0))
	var cd: Dictionary = d.get("client_done", {})
	for k in cd:
		client_done[str(k)] = int(cd[k])
	for spec in d.get("offers", []):
		if spec is Dictionary and clients.has(str(spec.get("client", ""))):
			var sp: Dictionary = spec.duplicate(true)
			var wl: Array = []
			for wid in sp.get("windows", []):
				wl.append(str(wid))
			sp["windows"] = wl
			_add_offer(sp)
	var s: Dictionary = d.get("state", {})
	for id in s:
		if state.has(id):
			state[id] = str(s[id])
	var e: Dictionary = d.get("elapsed", {})
	for id in e:
		if elapsed.has(id):
			elapsed[id] = float(e[id])
	var td: Dictionary = d.get("times_done", {})
	for id in td:
		if times_done.has(id):
			times_done[id] = int(td[id])
	# Starší uložení (v1) neznala times_done – dokončená zakázka = 1×.
	for id in state:
		if state[id] == "completed" and int(times_done[id]) == 0:
			times_done[id] = 1
	active_id = str(d.get("active_id", ""))
	if not contracts.has(active_id) or state.get(active_id) != "active":
		active_id = ""
	ensure_offers()
	Events.contract_changed.emit()

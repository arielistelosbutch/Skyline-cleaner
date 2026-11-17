class_name Tutorial
extends Node
## Úvodní tutoriál: hráč začíná na vlastní základně a pod vedením umyje tři okna
## garáže (zakázka „Okna vlastní firmy"). Naučí se pohyb, tablet a přijetí zakázky,
## pracovní režim, saponát, drhnutí, vymáchání hadru, bláto a židli.
## Stav je v GameState.tutorial_step (-1 = tutoriál neběží / je hotový).
## Kroky se samy přeskočí, když je hráč udělá v jiném pořadí.

const CONTRACT_ID := "zakladna_garaz"
const W_DUST := "zakladna_w1_prach"
const W_MUD := "zakladna_w2_blato"
const W_HIGH := "zakladna_w3_vrata"
## Jak dlouho zůstane poslední krok (pochvala a odkaz na první zákaznici).
const OUTRO_TIME := 30.0

enum Step { MOVE, TABLET, WINDOW, SPRAY, WIPE, RINSE, MUD, CHAIR, SHOP, DONE }
const STEP_COUNT := 10
## Pult obchodu se smíšeným zbožím na návsi (krok Obchod).
const SHOP_POS := Vector3(-74.0, 0.0, -11.0)

var player: Player
var _start_pos := Vector3.ZERO
var _has_start := false
var _sprayed := false
var _rinsed := false
var _shop_seen := false
var _last_tank := -1.0
var _outro_t := 0.0
var _last_step := -2


func _ready() -> void:
	add_to_group("tutorial")
	Events.tank_changed.connect(_on_tank)
	Events.tutorial_event.connect(_on_event)
	Events.game_loaded.connect(func() -> void: _has_start = false)


static func active() -> bool:
	return GameState.tutorial_step >= 0


## Nová hra: tutoriál od začátku.
func start() -> void:
	GameState.tutorial_step = Step.MOVE
	_has_start = false
	_sprayed = false
	_rinsed = false
	_shop_seen = false
	_outro_t = 0.0
	_last_step = -2


## Přeskočení (menu pauzy). Zakázka garáže zůstane v tabletu jako běžná práce.
func skip() -> void:
	if not active():
		return
	GameState.tutorial_step = -1
	_show_shop_marker(false)
	Events.toast("Tutoriál přeskočen. První zákaznice, paní Nováková, čeká v tabletu [Tab].", "info")


func _on_tank(v: float, _cap: float) -> void:
	if _last_tank >= 0.0 and v < _last_tank:
		_sprayed = true
	_last_tank = v


func _on_event(id: String) -> void:
	if id == "rinse":
		_rinsed = true
	elif id == "shop":
		_shop_seen = true


func _window_done(id: String) -> bool:
	var w := WindowRegistry.find_window(id)
	return w != null and w.completed


func _contract_done() -> bool:
	return ContractManager.state.get(CONTRACT_ID) == "completed"


func _process(delta: float) -> void:
	if not active() or player == null:
		return
	if not _has_start:
		_start_pos = player.global_position
		_has_start = true
	# posun o víc kroků najednou, když už je hráč udělal
	var guard := 0
	while active() and guard < STEP_COUNT and _step_done(GameState.tutorial_step):
		GameState.tutorial_step += 1
		guard += 1
		if GameState.tutorial_step >= STEP_COUNT:
			_finish()
	if GameState.tutorial_step == Step.DONE:
		_outro_t += delta
		if _outro_t >= OUTRO_TIME:
			_finish()
	_last_tank = GameState.tank
	if GameState.tutorial_step != _last_step:
		if _last_step >= 0 and active():
			Audio.play("click", -6.0, 1.3)
		_last_step = GameState.tutorial_step
		_show_shop_marker(GameState.tutorial_step == Step.SHOP)


## Zelená značka ▼ OBCHOD nad obchodem na návsi (jen v kroku Obchod).
func _show_shop_marker(on: bool) -> void:
	# obchod ukáže i kompas nahoře (zelená značka)
	NavArrow.poi_on = on
	NavArrow.poi_pos = SHOP_POS
	if is_inside_tree():
		get_tree().call_group("tutorial_shop_marker", "set_visible", on)


func _step_done(step: int) -> bool:
	# dokončená zakázka garáže = všechno podstatné je za hráčem
	if _contract_done() and step < Step.SHOP:
		return true
	match step:
		Step.MOVE:
			return player.global_position.distance_to(_start_pos) > 3.5
		Step.TABLET:
			return ContractManager.active_id == CONTRACT_ID
		Step.WINDOW:
			return player.mode == Player.Mode.CLEANING or _any_done()
		Step.SPRAY:
			return _sprayed or _any_done()
		Step.WIPE:
			return _any_done()
		Step.RINSE:
			return _rinsed
		Step.MUD:
			return _window_done(W_DUST) and _window_done(W_MUD)
		Step.CHAIR:
			return _contract_done()
		Step.SHOP:
			var p := player.global_position
			return _shop_seen or Vector2(p.x - SHOP_POS.x, p.z - SHOP_POS.z).length() < 8.0
		Step.DONE:
			# hráč už přijal další zakázku – tutoriál může zmizet
			return ContractManager.active_id != "" and ContractManager.active_id != CONTRACT_ID
	return false


func _any_done() -> bool:
	return _window_done(W_DUST) or _window_done(W_MUD) or _window_done(W_HIGH)


func _finish() -> void:
	GameState.tutorial_step = -1
	_show_shop_marker(false)
	Events.toast("Tutoriál dokončen – teď už jsi na to sám. Hodně štěstí!", "success")


func header() -> String:
	return "TUTORIÁL  ·  krok %d / %d" % [mini(GameState.tutorial_step + 1, STEP_COUNT), STEP_COUNT]


## Text úkolu do HUD.
func text() -> String:
	var step := GameState.tutorial_step
	var foot := "\n(Tutoriál jde přeskočit v menu [Esc].)"
	if step >= Step.WINDOW and step <= Step.CHAIR and ContractManager.active_id != CONTRACT_ID:
		return "Tutoriál čeká na zakázku Okna vlastní firmy. Otevři tablet [Tab] a v Zakázkách v ní pokračuj." + foot
	match step:
		Step.MOVE:
			return "Vítej ve firmě Clear View! Zatím jsi to jen ty, starý hadr a garáž přímo před tebou.\nRozhlížej se myší a projdi se [WASD] ([Shift] = rychleji)."
		Step.TABLET:
			return "Práci si bereš přes pracovní tablet. Otevři ho [Tab] (leží i na stole v garáži) a v Zakázkách přijmi první práci: Okna vlastní firmy."
		Step.WINDOW:
			return "Než půjdeš k zákazníkům, vyzkoušej si to doma. Neumytá okna mají nad sebou žlutou značku ▼.\nDojdi k bočnímu oknu garáže, podívej se na něj zblízka a stiskni [E]."
		Step.SPRAY:
			return "Jsi v pracovním režimu – myš teď hýbe hadrem.\nNejdřív nastříkej saponát [F]: namočená špína jde dolů mnohem snáz."
		Step.WIPE:
			return "Drž [LMB] a pohybuj myší – hadr stírá jen tam, kudy projede. Na kousky, kam nedosáhneš, přešlápni [A/D].\nKolem 98 % se okno samo doleští. [PTM] nebo [E] pracovní režim ukončí."
		Step.RINSE:
			return "První okno je čisté! Hadr se ale ušpinil a ubylo saponátu.\nV garáži stojí kýbl s vodou – [E] u něj hadr vymácháš a doplníš rozprašovač. U zákazníků najdeš kohoutek nebo sud."
		Step.MUD:
			if not _window_done(W_MUD):
				return "Na druhém bočním okně je bláto od kol. Nasucho skoro nejde – nastříkej ho [F], chvilku nech působit a pak drhni.\nCo na okně je, napíše nápověda vlevo dole."
			return "Umyj ještě zbylé boční okno garáže (žlutá značka ▼)."
		Step.CHAIR:
			if _window_done(W_HIGH):
				return "Dokonči zbývající okna garáže (žluté značky ▼)."
			return "Malé okénko vedle vrat je vysoko. Vezmi židli u garáže [E], polož ji pod okno [E] nebo [B] (otáčí se kolečkem) a vyskoč na ni [mezerník]. Pak okno umyj."
		Step.SHOP:
			return "Garáž je umytá a máš první výdělek! Lepší vybavení prodává obchod Smíšené zboží na návsi.\nJe kousek na západ po chodníku podél silnice – nad ním svítí zelená značka ▼ OBCHOD (zelená značka je i na kompasu nahoře). Dojdi k němu, [E] u pultu otevře nákup."
		Step.DONE:
			return "Hotovo, firma se může ukázat! Za každou zakázku dostaneš peníze, zkušenosti a pověst.\nV tabletu [Tab] čeká první zákaznice – paní Nováková z Lipové Lhoty. Cestu k ní ti po přijetí zakázky ukáže kompas nahoře. Až budeš mít peníze, vrať se sem do obchodu pro lepší vybavení."
	return ""

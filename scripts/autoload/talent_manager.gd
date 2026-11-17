extends Node
## Talentový strom: definice (TalentData .tres), odemčené úrovně a jejich
## propojení na herní hodnoty. Body získává hráč za každou novou úroveň
## (GameState.talent_points).

const TALENT_PATHS := [
	"res://data/talents/pevna_ruka.tres", "res://data/talents/profesionalni_tah.tres",
	"res://data/talents/dokonaly_lesk.tres", "res://data/talents/mistr_cistoty.tres",
	"res://data/talents/sikovny_pracovnik.tres", "res://data/talents/uspore_davkovani.tres",
	"res://data/talents/dlouhy_dosah.tres", "res://data/talents/vyskovy_specialista.tres",
	"res://data/talents/technicky_genius.tres", "res://data/talents/mistr_plosin.tres",
	"res://data/talents/dobry_vyjednavac.tres", "res://data/talents/vyhodny_nakup.tres",
	"res://data/talents/spokojeni_zakaznici.tres", "res://data/talents/dobry_zamestnavatel.tres",
	"res://data/talents/automatizace.tres", "res://data/talents/cistici_imperium.tres",
	"res://data/talents/velka_nadrz.tres", "res://data/talents/automaticky_zavlazovac.tres",
	"res://data/talents/mestsky_profik.tres", "res://data/talents/mestske_kontakty.tres",
	"res://data/talents/rychle_nabijeni.tres", "res://data/talents/vetsi_baterie.tres",
	"res://data/talents/pecliva_podlozka.tres",
	"res://data/talents/dalkove_privolani.tres", "res://data/talents/turbo_rezim.tres",
	"res://data/talents/prisavne_rukavice.tres", "res://data/talents/rychle_vrtule.tres",
	"res://data/talents/vydrzne_baterie.tres", "res://data/talents/presne_trysky.tres",
]
## Etapa vývoje, která je teď hotová – talenty z pozdějších etap nejdou odemknout.
const CURRENT_STAGE := 6
const BRANCHES := [
	["zrucnost", "Zručnost", "Rychlost a kvalita čištění"],
	["technika", "Technika", "Vybavení a práce ve výškách"],
	["podnikani", "Podnikání", "Ekonomika a firma"],
	["robotika", "Robotika", "Roboti a drony"],
]

signal changed()

var talents := {}          # id -> TalentData
var order: Array[String] = []
var ranks := {}            # id -> int


func _ready() -> void:
	for p in TALENT_PATHS:
		var t: TalentData = load(p)
		if t:
			talents[t.id] = t
			order.append(t.id)


func reset() -> void:
	ranks.clear()
	changed.emit()


func get_talent(id: String) -> TalentData:
	return talents.get(id)


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func in_branch(branch: String) -> Array[TalentData]:
	var out: Array[TalentData] = []
	for id in order:
		if talents[id].branch == branch:
			out.append(talents[id])
	return out


## Prázdný řetězec = lze odemknout, jinak důvod (pro rozhraní).
func unlock_problem(id: String) -> String:
	var t: TalentData = talents.get(id)
	if t == null:
		return "Neznámý talent."
	if t.stage > CURRENT_STAGE:
		return "Připravujeme (Etapa %d)." % t.stage
	if rank(id) >= t.max_rank:
		return "Maximální úroveň."
	for r in t.requires:
		if rank(r) <= 0:
			return "Nejdřív odemkni: %s." % talents[r].display_name
	if GameState.talent_points < t.cost:
		return "Potřebuješ %d talentový bod%s." % [t.cost, "" if t.cost == 1 else "y"]
	return ""


func unlock(id: String) -> bool:
	if unlock_problem(id) != "":
		return false
	var t: TalentData = talents[id]
	GameState.talent_points -= t.cost
	ranks[id] = rank(id) + 1
	Audio.play("levelup", -6.0, 1.2)
	Events.toast("Talent odemčen: %s" % t.display_name, "success")
	changed.emit()
	return true


## Součin násobičů daného účinku ze všech odemčených talentů.
func mult(effect: String) -> float:
	var m := 1.0
	for id in ranks:
		var t: TalentData = talents.get(id)
		var r := rank(id)
		if t and r > 0 and t.effect == effect and t.stage <= CURRENT_STAGE:
			m *= t.values[mini(r, t.values.size()) - 1]
	return m


func has_effect(effect: String) -> bool:
	for id in ranks:
		var t: TalentData = talents.get(id)
		if t and rank(id) > 0 and t.effect == effect and t.stage <= CURRENT_STAGE:
			return true
	return false


## Nejmenší hodnota účinku (pro prahy), nebo výchozí hodnota.
func min_value(effect: String, default: float) -> float:
	var v := default
	for id in ranks:
		var t: TalentData = talents.get(id)
		var r := rank(id)
		if t and r > 0 and t.effect == effect and t.stage <= CURRENT_STAGE:
			v = minf(v, t.values[mini(r, t.values.size()) - 1])
	return v


func to_dict() -> Dictionary:
	return ranks.duplicate()


func from_dict(d: Dictionary) -> void:
	ranks.clear()
	for id in d:
		if talents.has(id):
			ranks[id] = clampi(int(d[id]), 0, talents[id].max_rank)
	changed.emit()

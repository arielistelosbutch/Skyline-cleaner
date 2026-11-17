class_name DirtProfile
extends Resource
## Datová definice znečištění okna: kolik které nečistoty se vygeneruje.
## Okno odkazuje na profil podle id (data/dirt/<id>.tres).
## Hodnota 0 = typ se nevyskytuje, 1 = běžné množství, víc = silněji.

@export var id := ""
@export var display_name := ""
@export_range(0.0, 2.0) var dust := 1.0
@export_range(0.0, 3.0) var streaks := 1.0
@export_range(0.0, 3.0) var drops := 1.0
@export_range(0.0, 3.0) var bird := 1.0
@export_range(0.0, 3.0) var mud := 0.0
@export_range(0.0, 3.0) var grease := 0.0
@export_range(0.0, 3.0) var pollen := 0.0
@export_range(0.0, 3.0) var heavy := 0.0

static var _cache := {}


## Načte profil podle id; neznámé id = výchozí profil (jako v Etapě 1).
static func get_profile(pid: String) -> DirtProfile:
	if pid == "":
		pid = "venkov_bezne"
	if _cache.has(pid):
		return _cache[pid]
	var path := "res://data/dirt/%s.tres" % pid
	var p: DirtProfile = load(path) if ResourceLoader.exists(path) else null
	if p == null:
		push_warning("DirtProfile: profil '%s' nenalezen, používám výchozí." % pid)
		p = DirtProfile.new()
		p.id = pid
	_cache[pid] = p
	return p


## Typy nečistot, které profil generuje (pro popis zakázky).
static func kinds_of(pid: String) -> Array[int]:
	var out: Array[int] = []
	var p := get_profile(pid)
	if p.dust > 0.0: out.append(DirtTypes.DUST)
	if p.drops > 0.0 or p.streaks > 0.0: out.append(DirtTypes.DROPS)
	if p.mud > 0.0: out.append(DirtTypes.MUD)
	if p.bird > 0.0: out.append(DirtTypes.BIRD)
	if p.grease > 0.0: out.append(DirtTypes.GREASE)
	if p.pollen > 0.0: out.append(DirtTypes.POLLEN)
	if p.heavy > 0.0: out.append(DirtTypes.HEAVY)
	return out

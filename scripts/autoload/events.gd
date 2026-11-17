extends Node
## Globální sběrnice událostí. Systémy spolu komunikují přes signály,
## aby na sobě nebyly přímo závislé.

signal notify(text: String, kind: String)
signal window_progress(window_id: String, cleanliness: float)
signal window_completed(window_id: String)
signal money_changed(value: int, delta: int)
signal xp_changed(xp: int, level: int, delta: int)
signal level_up(level: int)
signal contract_changed()
signal contract_completed(contract_id: String, money: int, xp: int)
signal cleaning_mode_changed(active: bool)
signal equipment_changed(item_id: String)
signal inventory_changed()
signal cleaning_hint(text: String)
signal game_loaded()
signal area_changed(area_id: String)
signal area_unlocked(area_id: String)
signal tank_changed(value: float, capacity: float)
## Změna vzhledu firmy (lak dodávky, polep, oblečení).
signal cosmetics_changed()
## Drobné herní akce pro tutoriál (např. "rinse" = vymáchání nástroje).
signal tutorial_event(id: String)


func toast(text: String, kind: String = "info") -> void:
	notify.emit(text, kind)

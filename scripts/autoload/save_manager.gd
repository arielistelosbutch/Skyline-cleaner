extends Node
## Ukládání a načítání do user://savegame.json s verzováním dat.
## Při změně formátu zvyš SAVE_VERSION a doplň krok do _migrate().

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 9
## Zrušené talenty: id -> cena za úroveň (při načtení starého uložení se body vrátí).
const REMOVED_TALENTS := {"nabijeni_na_cestach": 1}

## Nastaví se před reloadem scény – main.gd po postavení světa načte pozici.
var pending_load := false


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(silent: bool = false) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	var data := {
		"version": SAVE_VERSION,
		"game": "clear_view",
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"state": GameState.to_dict(),
		"contracts": ContractManager.to_dict(),
		"windows": WindowRegistry.save_all(),
		"player": player.save_state() if player and player.has_method("save_state") else {},
		"persist": {},
	}
	for n in get_tree().get_nodes_in_group("persist"):
		if n.has_method("save_state") and "persist_id" in n:
			data["persist"][n.persist_id] = n.save_state()
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		Events.toast("Uložení se nepovedlo (%s)." % error_string(FileAccess.get_open_error()), "warn")
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open("user://")
	if dir.file_exists("savegame.json"):
		if dir.file_exists("savegame.json.bak"):
			dir.remove("savegame.json.bak")
		dir.rename("savegame.json", "savegame.json.bak")
	var err := dir.rename("savegame.json.tmp", "savegame.json")
	if err != OK:
		Events.toast("Uložení se nepovedlo.", "warn")
		return false
	if not silent:
		Events.toast("Hra uložena.", "info")
	else:
		Events.toast("Automaticky uloženo.", "info")
	return true


func read_save() -> Dictionary:
	if not has_save():
		return {}
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: uložená pozice je poškozená.")
		return {}
	return _migrate(parsed)


func _migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 0))
	while v < SAVE_VERSION:
		match v:
			0:
				# Verze 0 neexistovala veřejně – jen doplníme chybějící klíče.
				for k in ["state", "contracts", "windows", "player", "persist"]:
					if not data.has(k):
						data[k] = {}
			1:
				# Etapa 1 → Etapa 2: talenty, aktivní nástroje, opakované zakázky.
				# Většinu doplní from_dict výchozími hodnotami; tady jen to, co jinak nejde.
				var st: Dictionary = data.get("state", {})
				if not st.has("talents"):
					st["talents"] = {}
				if not st.has("active_wipe"):
					st["active_wipe"] = "rag_old"
				if not st.has("active_spray"):
					st["active_spray"] = "detergent_basic"
				data["state"] = st
				var con: Dictionary = data.get("contracts", {})
				if not con.has("times_done"):
					var td := {}
					var states: Dictionary = con.get("state", {})
					for id in states:
						td[id] = 1 if str(states[id]) == "completed" else 0
					con["times_done"] = td
				if not con.has("elapsed"):
					con["elapsed"] = {}
				data["contracts"] = con
				var pl: Dictionary = data.get("player", {})
				if not pl.has("held"):
					pl["held"] = "detergent_basic" if int(pl.get("equipped", 0)) == 1 else "rag_old"
				data["player"] = pl
			2:
				# Etapa 2 → Etapa 3: oblast Předměstí (od úrovně 4), žebříky v persist.
				# Nové zakázky a okna doplní from_dict výchozími hodnotami.
				var st3: Dictionary = data.get("state", {})
				var areas: Array = st3.get("unlocked_areas", ["venkov"])
				if int(st3.get("level", 1)) >= 4 and not areas.has("predmesti"):
					areas.append("predmesti")
				st3["unlocked_areas"] = areas
				data["state"] = st3
			3:
				# Etapa 3 → Etapa 4: oblast Město (od úrovně 8). Nové zakázky, okna a talenty
				# doplní from_dict výchozími hodnotami; plošina se ukládá jen jako vlastněná položka.
				var st4: Dictionary = data.get("state", {})
				var areas4: Array = st4.get("unlocked_areas", ["venkov"])
				if int(st4.get("level", 1)) >= 8 and not areas4.has("mesto"):
					areas4.append("mesto")
				st4["unlocked_areas"] = areas4
				data["state"] = st4
			4:
				# Etapa 4 → Etapa 5: roboti na okna. Jejich stav je v persist["robots"];
				# starší uložení robota nemají, takže jen připravíme prázdný záznam
				# a statistiku umytých oken roboty.
				var persist5: Dictionary = data.get("persist", {})
				if not persist5.has("robots"):
					persist5["robots"] = {}
				data["persist"] = persist5
				var st5: Dictionary = data.get("state", {})
				var stats5: Dictionary = st5.get("stats", {})
				if not stats5.has("robot_windows"):
					stats5["robot_windows"] = 0
				st5["stats"] = stats5
				data["state"] = st5
			5:
				# Etapa 5 → víc robotů: kusy robotů (GameState.robot_units) a jejich stav
				# jako seznam. Ze starého uložení: od každého vlastněného modelu jeden kus.
				var st6: Dictionary = data.get("state", {})
				if not st6.has("robot_units"):
					var units: Array = []
					for m in ["robot_mini", "robot_pro", "robot_max"]:
						if (st6.get("inventory", []) as Array).has(m):
							units.append(m)
					st6["robot_units"] = units
				data["state"] = st6
				var persist6: Dictionary = data.get("persist", {})
				var old_r = persist6.get("robots", {})
				if old_r is Dictionary:
					var lst: Array = []
					for m in st6["robot_units"]:
						var e: Dictionary = (old_r as Dictionary).get(m, {}).duplicate()
						e["model"] = m
						lst.append(e)
					persist6["robots"] = lst
				data["persist"] = persist6
			6:
				# Etapa 6: Velkoměsto (od úrovně 14), drony (stav v persist["drone_depot"]),
				# dodávka si pamatuje, kde parkuje (persist["company_base"]), statistika dronů.
				var st7: Dictionary = data.get("state", {})
				var areas7: Array = st7.get("unlocked_areas", ["venkov"])
				if int(st7.get("level", 1)) >= 14 and not areas7.has("velkomesto"):
					areas7.append("velkomesto")
				st7["unlocked_areas"] = areas7
				var stats7: Dictionary = st7.get("stats", {})
				if not stats7.has("drone_windows"):
					stats7["drone_windows"] = 0
				st7["stats"] = stats7
				data["state"] = st7
			7:
				# Zrušený talent Nabíjení na cestách (roboti se už cestou nedobíjejí,
				# místo toho je stojan na dodávce) – vrátíme za něj talentový bod.
				var st8: Dictionary = data.get("state", {})
				var tal8: Dictionary = st8.get("talents", {})
				var refund := 0
				for old_id in REMOVED_TALENTS:
					if tal8.has(old_id):
						refund += int(tal8[old_id]) * int(REMOVED_TALENTS[old_id])
						tal8.erase(old_id)
				st8["talents"] = tal8
				st8["talent_points"] = int(st8.get("talent_points", 0)) + refund
				if refund > 0:
					data["refunded_talent_points"] = refund
				data["state"] = st8
			8:
				# Tutoriál na základně (zakázka Okna vlastní firmy): hráč ze staršího uložení
				# už začátek hry má za sebou – zakázku bereme jako hotovou (lze ji dát jako
				# pravidelný úklid) a tutoriál nespouštíme.
				var con9: Dictionary = data.get("contracts", {})
				var states9: Dictionary = con9.get("state", {})
				if not states9.has("zakladna_garaz"):
					states9["zakladna_garaz"] = "completed"
					var td9: Dictionary = con9.get("times_done", {})
					td9["zakladna_garaz"] = 1
					con9["times_done"] = td9
				con9["state"] = states9
				data["contracts"] = con9
				var st9: Dictionary = data.get("state", {})
				st9["tutorial_step"] = -1
				data["state"] = st9
		v += 1
	data["version"] = SAVE_VERSION
	return data


## Aplikuje uloženou pozici na již postavený svět.
func apply(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	GameState.from_dict(data.get("state", {}))
	WindowRegistry.load_all(data.get("windows", {}))
	ContractManager.from_dict(data.get("contracts", {}))
	var persist: Dictionary = data.get("persist", {})
	for n in get_tree().get_nodes_in_group("persist"):
		if "persist_id" in n and persist.has(n.persist_id):
			n.load_state(persist[n.persist_id])
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("load_state"):
		player.load_state(data.get("player", {}))
	Events.game_loaded.emit()
	var refunded := int(data.get("refunded_talent_points", 0))
	if refunded > 0:
		data.erase("refunded_talent_points")
		Events.toast("Talent Nabíjení na cestách byl zrušen – vracíme ti %d talentový bod. Roboti se teď nabíjejí ve stojanu na dodávce." % refunded, "info")
	return true


func load_game() -> bool:
	return apply(read_save())


## Načtení z běžící hry: scéna se postaví znovu a pak se aplikuje pozice.
func reload_and_load() -> void:
	pending_load = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


static func vec3_to_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func arr_to_vec3(a, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback

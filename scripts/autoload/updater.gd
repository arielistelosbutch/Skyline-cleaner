extends Node
## Automatické aktualizace přes GitHub Releases a okno „Co je nového".
##
## Jak to funguje:
## 1. Po spuštění se hra zeptá GitHubu na poslední vydání (releases/latest).
## 2. Je-li jeho číslo (tag, např. „v0.8.0") vyšší než verze hry
##    (Nastavení projektu → Application → Config → Version), nabídne aktualizaci.
## 3. Hra stáhne ClearView-windows.zip, vybalí z něj nové ClearView.exe vedle běžícího,
##    běžící exe přejmenuje na ClearView.old.exe (Windows to u běžícího programu dovolí),
##    nové dá na jeho místo, spustí ho a sama se ukončí. Staré exe smaže až další spuštění.
## 4. Když se nová verze spustí poprvé, ukáže okno s novinkami = popis vydání z GitHubu.
## Nejde-li exe přepsat (např. hra v Program Files), otevře se stránka vydání v prohlížeči.

signal update_available(info: Dictionary)
signal whats_new_ready(version: String, notes: String)
signal download_progress(ratio: float)
signal install_failed(message: String)

const REPO := "arielistelosbutch/Skyline-cleaner"
const ASSET_NAME := "ClearView-windows.zip"
const API_LATEST := "https://api.github.com/repos/%s/releases/latest" % REPO
const API_TAG := "https://api.github.com/repos/%s/releases/tags/%s"
const STATE_PATH := "user://update.cfg"
const DOWNLOAD_PATH := "user://update_download.zip"

## Poslední nalezená novější verze ({version, tag, notes, url, page}); prázdné = žádná.
var available: Dictionary = {}
var installing := false
## Novinky čekající na zobrazení ({version, notes}); UI je ukáže a vyprázdní.
var pending_whats_new: Dictionary = {}

var _http: HTTPRequest
var _download: HTTPRequest


func _ready() -> void:
	_cleanup_old_exe()
	if not enabled():
		return
	# Okno s novinkami: verze se od minulého spuštění změnila.
	var state := _state()
	var last_seen := str(state.get_value("update", "last_seen_version", ""))
	var current := current_version()
	if last_seen == "":
		# První spuštění s updaterem: jen si verzi zapamatuj.
		_remember_seen(current)
	elif last_seen != current:
		var cached := str(state.get_value("update", "notes_" + current, ""))
		if cached != "":
			_announce_whats_new(current, cached)
		else:
			_fetch_notes_for(current)
	if Settings.check_updates:
		check_for_update.call_deferred()


## Updater běží jen ve vyexportované hře (ne v editoru, ne v testech bez okna).
static func enabled() -> bool:
	if OS.has_feature("editor"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	var args := OS.get_cmdline_user_args()
	return not (args.has("--autotest") or args.has("--shots") or args.has("--zscan"))


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Umí hra sama vyměnit své exe? (jen Windows build; jinak se otevře stránka vydání)
static func can_self_install() -> bool:
	return OS.get_name() == "Windows" and not OS.has_feature("editor")


# ------------------------------------------------------------------ kontrola

func check_for_update() -> void:
	if _http:
		return
	_http = _make_request()
	_http.request_completed.connect(_on_latest)
	if _http.request(API_LATEST, _headers()) != OK:
		_http.queue_free()
		_http = null


func _on_latest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return  # bez internetu / bez vydání: tiše nic
	var info := parse_release(body.get_string_from_utf8())
	if info.is_empty():
		return
	if not is_newer(info.version, current_version()):
		return
	if info.url == "" and can_self_install():
		return  # vydání je založené, ale zip se ještě sestavuje (GitHub Actions) – příště
	# Pojistka proti nekonečné nabídce, kdyby se zapomnělo zvednout číslo verze v projektu.
	if str(_state().get_value("update", "installed_tag", "")) == info.tag:
		return
	available = info
	update_available.emit(info)


## Z JSONu vydání vytáhne verzi, popis a odkaz na zip. Prázdný slovník = nepoužitelné.
static func parse_release(json_text: String) -> Dictionary:
	var data = JSON.parse_string(json_text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("tag_name"):
		return {}
	if data.get("draft", false) or data.get("prerelease", false):
		return {}
	var tag := str(data.tag_name)
	var url := ""
	for a in data.get("assets", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("name", "")).to_lower() == ASSET_NAME.to_lower():
			url = str(a.get("browser_download_url", ""))
	if url == "":
		# zip s jiným jménem: vezmi první .zip
		for a in data.get("assets", []):
			if typeof(a) == TYPE_DICTIONARY and str(a.get("name", "")).to_lower().ends_with(".zip"):
				url = str(a.get("browser_download_url", ""))
				break
	var body = data.get("body", "")
	return {
		"tag": tag,
		"version": tag.trim_prefix("v").trim_prefix("V").strip_edges(),
		"title": str(data.get("name", "")) if data.get("name") != null else "",
		"notes": str(body) if body != null else "",
		"url": url,
		"page": str(data.get("html_url", "https://github.com/%s/releases" % REPO)),
	}


## „0.10.0" > „0.9.2"; chybějící čísla = 0; text za pomlčkou se ignoruje.
static func is_newer(candidate: String, current: String) -> bool:
	var a := _parts(candidate)
	var b := _parts(current)
	for i in maxi(a.size(), b.size()):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false


static func _parts(v: String) -> Array[int]:
	var out: Array[int] = []
	for p in v.trim_prefix("v").get_slice("-", 0).split("."):
		out.append(int(p) if p.is_valid_int() else 0)
	return out


# ------------------------------------------------------------------ instalace

## Stáhne a nainstaluje dostupnou verzi. Na jiném systému než Windows otevře stránku vydání.
func install_update() -> void:
	if available.is_empty() or installing:
		return
	if not can_self_install() or available.url == "":
		OS.shell_open(available.page)
		return
	installing = true
	_download = _make_request()
	_download.download_file = ProjectSettings.globalize_path(DOWNLOAD_PATH)
	_download.request_completed.connect(_on_downloaded)
	if _download.request(available.url, ["User-Agent: ClearView-Updater"]) != OK:
		_fail("Stažení se nepodařilo spustit.")
	set_process(true)


func _process(_d: float) -> void:
	if _download and installing:
		var total := _download.get_body_size()
		if total > 0:
			download_progress.emit(clampf(float(_download.get_downloaded_bytes()) / total, 0.0, 1.0))
	else:
		set_process(false)


func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_download.queue_free()
	_download = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Stažení se nepovedlo (zkontroluj internet).")
		return
	download_progress.emit(1.0)
	var err := install_from_zip(ProjectSettings.globalize_path(DOWNLOAD_PATH), OS.get_executable_path())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DOWNLOAD_PATH))
	if err != "":
		_fail(err)
		return
	# Zapamatuj si novinky (okno po spuštění funguje i offline) a nainstalovaný tag.
	var st := _state()
	st.set_value("update", "notes_" + str(available.version), available.notes)
	st.set_value("update", "installed_tag", available.tag)
	st.save(STATE_PATH)
	OS.create_process(OS.get_executable_path(), [])
	get_tree().quit()


## Vybalí exe ze zipu a vymění ho za `exe_path`. Vrací "" při úspěchu, jinak text chyby.
## (Statická a s cestami v parametrech, aby šla vyzkoušet i mimo Windows.)
static func install_from_zip(zip_path: String, exe_path: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "Stažený soubor je poškozený."
	var inner := ""
	for f in zip.get_files():
		if f.to_lower().ends_with(".exe"):
			inner = f
			break
	if inner == "":
		zip.close()
		return "Ve staženém souboru chybí ClearView.exe."
	var bytes := zip.read_file(inner)
	zip.close()
	if bytes.size() < 1024:
		return "Stažené ClearView.exe je poškozené."
	var dir := exe_path.get_base_dir()
	var new_path := dir.path_join("ClearView.new.exe")
	var old_path := dir.path_join("ClearView.old.exe")
	var f := FileAccess.open(new_path, FileAccess.WRITE)
	if f == null:
		return "Do složky hry nejde zapisovat."
	f.store_buffer(bytes)
	f.close()
	if FileAccess.file_exists(old_path):
		DirAccess.remove_absolute(old_path)
	if DirAccess.rename_absolute(exe_path, old_path) != OK:
		DirAccess.remove_absolute(new_path)
		return "Nepodařilo se uvolnit místo pro novou verzi."
	if DirAccess.rename_absolute(new_path, exe_path) != OK:
		DirAccess.rename_absolute(old_path, exe_path)  # vrať původní stav
		DirAccess.remove_absolute(new_path)
		return "Nepodařilo se nahradit ClearView.exe."
	return ""


func _fail(message: String) -> void:
	installing = false
	install_failed.emit(message + " Otevírám stránku pro ruční stažení.")
	if not available.is_empty():
		OS.shell_open(available.page)


func _cleanup_old_exe() -> void:
	if OS.has_feature("editor"):
		return
	var old := OS.get_executable_path().get_base_dir().path_join("ClearView.old.exe")
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)  # když to ještě nejde (dobíhá), zkusí se příště


# ------------------------------------------------------------------ co je nového

func _fetch_notes_for(version: String) -> void:
	var req := _make_request()
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		var notes := ""
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			notes = str(parse_release(body.get_string_from_utf8()).get("notes", ""))
		_announce_whats_new(version, notes))
	if req.request(API_TAG % [REPO, "v" + version], _headers()) != OK:
		req.queue_free()
		_announce_whats_new(version, "")


func _announce_whats_new(version: String, notes: String) -> void:
	if notes.strip_edges() == "":
		notes = "Hra byla aktualizována na verzi %s." % version
	pending_whats_new = {"version": version, "notes": notes}
	whats_new_ready.emit(version, notes)


## Volá UI, když okno s novinkami opravdu ukázalo (jinak se ukáže při dalším spuštění).
func mark_whats_new_seen(version: String) -> void:
	_remember_seen(version)


func _remember_seen(version: String) -> void:
	var st := _state()
	st.set_value("update", "last_seen_version", version)
	st.save(STATE_PATH)


func _state() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(STATE_PATH)
	return cf


func _make_request() -> HTTPRequest:
	var r := HTTPRequest.new()
	r.timeout = 60.0
	r.max_redirects = 10
	add_child(r)
	return r


func _headers() -> PackedStringArray:
	return ["User-Agent: ClearView-Updater", "Accept: application/vnd.github+json"]


## Jednoduchý převod Markdownu z GitHubu na BBCode pro RichTextLabel.
static func markdown_to_bbcode(md: String) -> String:
	var out: PackedStringArray = []
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	var italic := RegEx.create_from_string("(?<![\\*\\w])[\\*_]([^\\*_]+?)[\\*_](?![\\*\\w])")
	var link := RegEx.create_from_string("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	for raw in md.replace("\r", "").split("\n"):
		# odkazy [text](url) → jen text; zbylé hranaté závorky escapuj pro BBCode
		var line := link.sub(raw.strip_edges(false, true), "$1", true).replace("[", "[lb]")
		line = bold.sub(line, "[b]$1[/b]", true)
		line = italic.sub(line, "[i]$1[/i]", true)
		var t := line.strip_edges()
		if t.begins_with("#"):
			var h := t.lstrip("#").strip_edges()
			out.append("[font_size=22][b]%s[/b][/font_size]" % h)
		elif t.begins_with("- ") or t.begins_with("* ") or t.begins_with("+ "):
			out.append("  •  " + t.substr(2))
		else:
			out.append(line)
	return "\n".join(out).strip_edges()

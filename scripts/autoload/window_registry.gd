extends Node
## Rejstřík všech omyvatelných oken ve scéně podle window_id.
## Stará se i o líné aktivování masek podle vzdálenosti hráče.

const ACTIVATE_DISTANCE := 40.0

var windows := {}
var _timer := 0.0


func register(w: CleanableWindow) -> void:
	if w.window_id == "":
		push_error("CleanableWindow bez window_id: %s" % w.get_path())
		return
	if windows.has(w.window_id) and windows[w.window_id] != w:
		push_error("Duplicitní window_id: %s" % w.window_id)
	windows[w.window_id] = w


func unregister(w: CleanableWindow) -> void:
	if windows.get(w.window_id) == w:
		windows.erase(w.window_id)


func find_window(id: String) -> CleanableWindow:
	var w = windows.get(id)
	return w if is_instance_valid(w) else null


## Okno, jehož maska se právě generuje na pozadí.
var _pending: CleanableWindow


func _process(delta: float) -> void:
	# hotovou masku z vlákna převezmeme hned (vytvoření textury je levné)
	if _pending:
		if not is_instance_valid(_pending):
			_pending = null
		elif _pending.prefetch_done():
			_pending.finish_prefetch()
			_pending = null
	_timer += delta
	if _timer < 0.25 or _pending:
		return
	_timer = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# Nejbližší neaktivní okno v dosahu se generuje ve vlákně – bez záseku hry.
	var best: CleanableWindow = null
	var best_d := ACTIVATE_DISTANCE
	var pp := player.global_position
	for id in windows:
		var w: CleanableWindow = windows[id]
		if is_instance_valid(w) and not w.is_active():
			var d := w.global_position.distance_to(pp)
			if d < best_d:
				best_d = d
				best = w
	if best and best.prefetch():
		_pending = best


func save_all() -> Dictionary:
	var out := {}
	for id in windows:
		var w: CleanableWindow = windows[id]
		if is_instance_valid(w):
			var s := w.save_state()
			if not s.is_empty():
				out[id] = s
	return out


func load_all(data: Dictionary) -> void:
	for id in windows:
		var w: CleanableWindow = windows[id]
		if is_instance_valid(w):
			w.load_state(data.get(id, {}))


func reset_all() -> void:
	for id in windows:
		var w: CleanableWindow = windows[id]
		if is_instance_valid(w):
			w.reset_state()
			w.generation = 0
			w.override_profile = ""

class_name HeldItems
extends Node3D
## Předměty viditelné v rukou před kamerou v běžném FPS režimu.
## Jemný „sway" při rozhlížení, krátká animace při použití a přepnutí.

const REST := Vector3(0.27, -0.27, -0.5)

var _items := {}
var _current := ""
var _chair_view: MeshInstance3D
var _chair_rest := Transform3D.IDENTITY
var _sway := Vector2.ZERO
var _kick := 0.0
var _dip := 0.0
var _t := 0.0
## Rozprašovač v levé ruce: ukáže se při nástřiku, když v pravé ruce je jiný nástroj.
var _left: Node3D
var _left_id := ""
var _left_t := 0.0
const LEFT_REST := Vector3(-0.25, -0.25, -0.46)
## Když je před hráčem zeď nebo sklo blíž než tohle, nástroj v ruce se stáhne
## k tělu, aby neprojížděl skrz okno.
const CLEAR_DIST := 0.78
var _retract := 0.0


func _ready() -> void:
	_chair_view = MeshInstance3D.new()
	_chair_view.visible = false
	_chair_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chair_view.position = Vector3(0.05, -0.62, -0.95)
	_chair_view.rotation = Vector3(0.15, PI + 0.35, 0.0)
	add_child(_chair_view)
	Events.cosmetics_changed.connect(_rebuild)
	show_item("rag_old")


## Model nástroje se postaví až při prvním zobrazení (podle jeho dat).
func _get_item(id: String) -> Node3D:
	if _items.has(id):
		return _items[id]
	var t := GameState.get_tool(id)
	if t == null:
		return null
	var n := ToolVisuals.held(t)
	n.visible = false
	n.position = REST
	add_child(n)
	_items[id] = n
	return n


## Nové oblečení: modely v ruce (s rukávem) postavit znovu.
func _rebuild() -> void:
	if _left:
		_left.queue_free()
		_left = null
		_left_id = ""
	var shown := _items.has(_current) and (_items[_current] as Node3D).visible
	for k in _items:
		_items[k].queue_free()
	_items.clear()
	if shown:
		var n := _get_item(_current)
		if n:
			n.visible = true


func show_item(id: String) -> void:
	_chair_view.visible = false
	_current = id
	_dip = 1.0
	_get_item(id)
	for k in _items:
		_items[k].visible = (k == id)


func show_chair(mesh: Mesh) -> void:
	for k in _items:
		_items[k].visible = false
	_chair_view.mesh = mesh
	_chair_view.visible = true
	_chair_rest = Transform3D(Basis.from_euler(Vector3(0.15, PI + 0.35, 0.0)), Vector3(0.05, -0.62, -0.95))
	_chair_view.transform = _chair_rest
	_current = "chair"


## Nesený větší předmět (žebřík) s vlastní polohou vůči kameře.
func show_carry(mesh: Mesh, xf: Transform3D) -> void:
	for k in _items:
		_items[k].visible = false
	_chair_view.mesh = mesh
	_chair_view.visible = true
	_chair_rest = xf
	_chair_view.transform = xf
	_current = "carry"


func sway(rel: Vector2) -> void:
	_sway += rel * 0.00012
	_sway = _sway.limit_length(0.03)


func play_spray() -> void:
	_kick = 1.0


## Krátce ukázat rozprašovač v levé ruce (zrcadlově) – stříká se z něj.
func flash_left(t: ToolData) -> void:
	if t == null:
		return
	if _left == null or _left_id != t.id:
		if _left:
			_left.queue_free()
		_left = ToolVisuals.held(t)
		_left.scale = Vector3(-1, 1, 1)
		add_child(_left)
		_left_id = t.id
	_left.visible = true
	if _left_t <= 0.0:
		_left.position = LEFT_REST + Vector3(0, -0.12, 0)
	_left_t = 1.0


func left_nozzle_global() -> Vector3:
	if _left:
		return _left.global_transform * Vector3(0, 0.105, -0.08)
	return global_position


func nozzle_global() -> Vector3:
	var n: Node3D = _items.get(_current)
	if n:
		return n.global_transform * Vector3(0, 0.105, -0.08)
	return global_position


func _process(delta: float) -> void:
	_t += delta
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	_kick = move_toward(_kick, 0.0, delta * 4.0)
	_dip = move_toward(_dip, 0.0, delta * 3.5)
	var breathe := sin(_t * 1.3) * 0.003
	_retract = lerpf(_retract, _wall_retract(), 1.0 - exp(-14.0 * delta))
	var off := Vector3(-_sway.x - _retract * 0.08, _sway.y + breathe - _dip * _dip * 0.12 - _retract * 0.14, _kick * 0.04 + _retract)
	var n: Node3D = _items.get(_current)
	if n:
		n.position = REST + off
		n.rotation = Vector3(_kick * 0.25, 0.0, 0.0)
	if _left:
		_left_t = maxf(_left_t - delta, 0.0)
		_left.visible = _left_t > 0.0
		if _left.visible:
			# rychle vyjet zespodu, chvíli držet, pak zase zajet dolů
			var show := minf(1.0, (1.0 - _left_t) * 8.0) * minf(1.0, _left_t * 4.0)
			var kick := maxf(0.0, _left_t - 0.8) * 5.0
			_left.position = LEFT_REST + Vector3(_sway.x * -1.0 + _retract * 0.08, (1.0 - show) * -0.3 + breathe - _retract * 0.14, kick * 0.04 + _retract)
			_left.rotation = Vector3(kick * 0.25, 0.0, 0.0)
	if _chair_view.visible:
		_chair_view.position = _chair_rest.origin + Vector3(-_sway.x, _sway.y + breathe, 0.0)


## O kolik (m) stáhnout nástroj k tělu podle vzdálenosti překážky před kamerou.
func _wall_retract() -> float:
	if not is_inside_tree() or not visible:
		return 0.0
	var cam := get_parent() as Node3D
	if cam == null:
		return 0.0
	var body := cam.get_parent() as CollisionObject3D
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	var best := CLEAR_DIST
	# střed a pravá dolní část zorného pole (kde je ruka)
	for d: Vector3 in [fwd, (fwd + cam.global_basis.x * 0.45 - cam.global_basis.y * 0.4).normalized()]:
		var q := PhysicsRayQueryParameters3D.create(from, from + d * CLEAR_DIST, 1)
		if body:
			q.exclude = [body.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			best = minf(best, from.distance_to(hit["position"]))
	return clampf(CLEAR_DIST - best, 0.0, 0.3)

class_name Player
extends CharacterBody3D
## Hráč z pohledu první osoby: pohyb, rozhlížení, interakce, nošení židle
## a přepnutí do pracovního režimu čištění (CleaningController).
## Etapa 3: nošení a lezení po žebříku (LADDER) a visení na laně (ROPE).
## Na žebříku i na laně se pozice počítá přímo z opory (žádná gravitace),
## takže hráč nemůže sklouznout ani spadnout.

enum Mode { WALK, CLEANING, LADDER, ROPE }

const EYE_HEIGHT := 1.62
const WALK_SPEED := 3.5
const SPRINT_SPEED := 5.8
const JUMP_VELOCITY := 4.6
const REACH := 2.4
const CAMERA_BLEND_TIME := 0.45
## Pád z větší výšky (m) = hra hráče potichu vrátí na bezpečné místo.
const SAFE_FALL := 3.2

var mode := Mode.WALK
var yaw := 0.0
var pitch := 0.0
var ui_open := true
var camera: Camera3D
var cleaning: CleaningController
var hand: HandRig
var held: HeldItems
## [R] Najít nářadí (main.gd ho nastaví).
var finder: ToolFinder
## Nesený předmět: židle (Chair) nebo žebřík (Ladder).
var carried: Node3D = null
## Opora, na které hráč právě je (žebřík / kotva lana), jinak null.
var ladder: Ladder = null
var ladder_h := 0.0
var anchor: RopeAnchor = null
var rope_u := 0.0
var rope_y := 0.0
## Předmět, který hráč právě drží v ruce (ruční nástroj nebo přípravek).
var held_id := "rag_old"
var spawn_point := Vector3.ZERO
var spawn_yaw := 0.0

## Výsledek posledního paprsku z kamery (počítá se ve fyzikálním kroku).
var focus_window: CleanableWindow = null
var focus_point := Vector3.ZERO
var focus_object: Object = null

var _blend := 0.0
var _bob_t := 0.0
var _step_dist := 0.0
var _ghost: MeshInstance3D
var _ghost_valid := false
var _ghost_xf := Transform3D.IDENTITY
var _ghost_rot := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _last_safe := Vector3.ZERO
## Několik posledních bezpečných poloh na zemi (návrat po pádu jde na tu nejstarší,
## aby hráč neskončil znovu přímo na hraně).
var _safe_hist: Array[Vector3] = []
var _safe_t := 0.0
var _air_top := 0.0
var _rope_mi: Array[MeshInstance3D] = []
## Automatický sestup ze žebříku po stisku mezerníku (hráč nemusí držet [S]).
var _auto_descend := false
## Držení [E] na opřeném žebříku: krátký stisk = vylézt, podržení = zvednout.
var _e_hold_t := -1.0
var _e_hold_target: Node3D = null
const HOLD_PICKUP := 0.4


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(48.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)

	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.add_to_group("player_camera")
	camera.top_level = true
	camera.fov = Settings.fov
	camera.near = 0.03
	camera.far = 1600.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)

	held = HeldItems.new()
	camera.add_child(held)

	hand = HandRig.new()
	add_child(hand)

	cleaning = CleaningController.new()
	cleaning.player = self
	add_child(cleaning)

	_ghost = MeshInstance3D.new()
	_ghost.top_level = true
	_ghost.visible = false
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)

	for i in 2:
		var rm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.012
		cyl.height = 1.0
		cyl.radial_segments = 6
		cyl.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.45, 0.1)
		mat.roughness = 0.8
		cyl.material = mat
		rm.mesh = cyl
		rm.top_level = true
		rm.visible = false
		add_child(rm)
		_rope_mi.append(rm)

	_last_safe = global_position
	_air_top = global_position.y
	_update_camera(0.0)
	Events.equipment_changed.emit.call_deferred(held_id)
	Events.inventory_changed.connect(_on_inventory_changed)


func equipped_id() -> String:
	return held_id


## Vybavení, které jde přepínat kolečkem: ruční nástroje a pak přípravky.
func equipment_list() -> Array[String]:
	var out: Array[String] = []
	for t in GameState.owned_tools("rag"):
		out.append(t.id)
	for t in GameState.owned_tools("spray"):
		out.append(t.id)
	return out


func hold(id: String) -> void:
	if not GameState.has_item(id):
		return
	held_id = id
	GameState.set_active(id)
	if mode != Mode.CLEANING and carried == null:
		held.show_item(id)


func _on_inventory_changed() -> void:
	# Po načtení hry / změně inventáře musí hráč držet něco, co vlastní.
	if GameState.get_tool(held_id) == null or not GameState.has_item(held_id):
		held_id = GameState.active_wipe
	if mode != Mode.CLEANING and carried == null:
		held.show_item(held_id)
	Events.equipment_changed.emit(held_id)


func activate_camera() -> void:
	camera.current = true
	camera.fov = Settings.fov


# ------------------------------------------------------------------ vstup

func _unhandled_input(event: InputEvent) -> void:
	if ui_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.screen_relative
		if mode != Mode.CLEANING:
			yaw -= rel.x * Settings.mouse_sensitivity
			pitch = clampf(pitch - rel.y * Settings.mouse_sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
			held.sway(rel)
		else:
			cleaning.on_mouse_motion(rel)
		return

	if event.is_action_pressed("jump") and mode == Mode.LADDER:
		if ladder_h > 0.35:
			_auto_descend = true
		else:
			leave_ladder()
	elif event.is_action_pressed("jump") and mode == Mode.ROPE:
		_rope_exit()
	elif event.is_action_pressed("interact"):
		if mode == Mode.CLEANING:
			end_cleaning()
		elif carried:
			_try_place()
		elif mode == Mode.WALK and focus_window == null and _hold_pickable(focus_object):
			# o rozhodnutí vylézt / zvednout se rozhodne až při puštění (nebo po podržení)
			_e_hold_t = 0.0
			_e_hold_target = focus_object
		else:
			_interact()
	elif event.is_action_released("interact"):
		if _e_hold_t >= 0.0 and is_instance_valid(_e_hold_target):
			if _e_hold_target is Ladder:
				climb_ladder(_e_hold_target)
			else:
				_e_hold_target.interact(self)
		_e_hold_t = -1.0
		_e_hold_target = null
	elif event.is_action_pressed("use_tool"):
		if mode != Mode.CLEANING:
			if carried:
				_try_place()
			elif mode == Mode.WALK and focus_window == null and (focus_object is Ladder or focus_object is Bucket):
				pick_up(focus_object)
			else:
				_use_tool()
	elif event.is_action_pressed("alt_tool"):
		if mode == Mode.CLEANING:
			end_cleaning()
	elif event.is_action_pressed("place_item"):
		if carried:
			_try_place()
	elif event.is_action_pressed("spray"):
		if mode == Mode.CLEANING:
			cleaning.spray()
		elif not carried:
			if focus_window:
				_spray_at_focus()
			else:
				_spray_far()
	elif event.is_action_pressed("next_chem"):
		_cycle_spray()
	elif event.is_action_pressed("find_tools"):
		if mode == Mode.CLEANING:
			cleaning.wring()
		elif finder:
			finder.show_tools()
	elif event.is_action_pressed("robot"):
		if mode != Mode.CLEANING and not carried:
			place_robot()
	elif event.is_action_pressed("next_item") or event.is_action_pressed("prev_item"):
		var dir := 1 if event.is_action_pressed("next_item") else -1
		if carried:
			_ghost_rot += dir * deg_to_rad(15.0)
		elif mode == Mode.CLEANING:
			cleaning.cycle_tool(dir)
			held_id = cleaning.tool.id
			Events.equipment_changed.emit(held_id)
		else:
			var list := equipment_list()
			if list.is_empty():
				return
			var idx := maxi(0, list.find(held_id))
			hold(list[wrapi(idx + dir, 0, list.size())])
			Audio.play("cloth", -10.0, 1.3)
			Events.equipment_changed.emit(held_id)


## Přepnutí přípravku ve rozprašovači [Q].
func _cycle_spray() -> void:
	var sprays := GameState.owned_tools("spray")
	if sprays.size() < 2:
		if not sprays.is_empty():
			Events.toast("Máš jen jeden přípravek: %s. Další koupíš v obchodě." % sprays[0].display_name, "info")
		return
	var cur := GameState.spray_tool()
	var idx := maxi(0, sprays.find(cur))
	var t: ToolData = sprays[wrapi(idx + 1, 0, sprays.size())]
	GameState.set_active(t.id)
	if GameState.get_tool(held_id).kind == "spray":
		held_id = t.id
		if mode != Mode.CLEANING and carried == null:
			held.show_item(held_id)
	Audio.play("click", -8.0, 1.2)
	Events.toast("Přípravek: %s" % t.display_name, "info")
	Events.equipment_changed.emit(held_id)


func _holding_spray() -> bool:
	var t := GameState.get_tool(held_id)
	return t != null and t.kind == "spray"


## Předmět, u kterého krátký [E] dělá akci a podržený [E] ho zvedne
## (opřený žebřík, kbelík).
func _hold_pickable(o: Object) -> bool:
	if o is Ladder:
		return not (o as Ladder).lying
	return o is Bucket


func _interact() -> void:
	if focus_window:
		begin_cleaning(focus_window, focus_point)
	elif focus_object and focus_object.has_method("interact"):
		focus_object.interact(self)
	elif mode == Mode.WALK and carried == null and Talents.has_effect("wall_climb"):
		try_climb()


## Talent Přísavné rukavice: chytit se zdi, na kterou hráč míří.
func try_climb() -> bool:
	var g := ClimbGrip.try_create(self, camera.global_position, -camera.global_basis.z, [get_rid()])
	if g == null:
		return false
	get_parent().add_child(g)
	var feet := global_position.y
	attach_rope(g)
	if anchor != g:
		g.queue_free()
		return false
	rope_u = 0.0
	rope_y = clampf(feet + 0.1, g.bottom_feet(), g.top_feet())
	global_position = g.hang_pos(rope_u, rope_y)
	reset_physics_interpolation()
	return true


## Robot na okna: přiložit na okno, na které hráč míří [G].
func place_robot() -> bool:
	var fleet := RobotFleet.get_fleet(self)
	if fleet == null or focus_window == null or mode == Mode.CLEANING:
		return false
	return fleet.place(focus_window, focus_point)


func _use_tool() -> void:
	if focus_window == null:
		if _holding_spray():
			_spray_far()
		return
	if _holding_spray():
		_spray_at_focus()
	else:
		begin_cleaning(focus_window, focus_point)


func _spray_at_focus() -> void:
	var t := GameState.spray_tool()
	if t == null:
		return
	if not ContractManager.can_clean(focus_window.window_id):
		_explain_locked(focus_window)
		return
	if not GameState.use_tank():
		return
	focus_window.spray(focus_window.to_plane(focus_point), t, GameState.spray_radius_mult(), GameState.evaporation_mult())
	Audio.play("spray", -4.0, randf_range(0.95, 1.05))
	var from: Vector3
	if _holding_spray():
		held.play_spray()
		from = held.nozzle_global()
	else:
		# v pravé ruce je nástroj – stříká se rozprašovačem z levé ruky
		held.flash_left(t)
		from = held.left_nozzle_global()
	cleaning.spawn_spray_fx(from, focus_point, t.color)


## Tlakový rozprašovač: nástřik na okno až do vzdálenosti 7 m (např. patro ze země).
func _spray_far() -> bool:
	if not GameState.has_item("sprayer_pressure") or ui_open:
		return false
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 7.0, 1 | CleanableWindow.WINDOW_LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit["collider"] as Object).has_meta("window"):
		return false
	var w: CleanableWindow = hit["collider"].get_meta("window")
	if w.completed:
		return false
	focus_window = w
	focus_point = hit["position"]
	_spray_at_focus()
	focus_window = null
	return true


func _explain_locked(w: CleanableWindow) -> void:
	var c := ContractManager.contract_for_window(w.window_id)
	if c and ContractManager.state.get(c.id) == "completed":
		Events.toast("Tahle zakázka je už hotová.", "info")
	elif c:
		Events.toast("Nejdřív přijmi zakázku „%s“ v pracovním tabletu [Tab]." % c.title, "warn")
	else:
		Events.toast("Tohle okno není součástí žádné zakázky.", "info")


# ------------------------------------------------------------------ čištění

func begin_cleaning(w: CleanableWindow, hit_point: Vector3) -> void:
	if w.completed:
		Events.toast("Tohle okno je už dokonale čisté.", "info")
		return
	if not ContractManager.can_clean(w.window_id):
		_explain_locked(w)
		return
	if mode == Mode.WALK and not is_on_floor():
		return
	if cleaning.begin(w, hit_point):
		mode = Mode.CLEANING
		velocity = Vector3.ZERO
		held.visible = false
		Events.cleaning_mode_changed.emit(true)


func end_cleaning() -> void:
	if mode != Mode.CLEANING:
		return
	# Převezmeme natočení pracovní kamery, ať návrat do FPS neškubne.
	var f := -camera.global_basis.z
	yaw = atan2(-f.x, -f.z)
	pitch = asin(clampf(f.y, -1.0, 1.0))
	if cleaning.window:
		cleaning.window.finish_if_almost()
	cleaning.end()
	mode = Mode.LADDER if ladder else (Mode.ROPE if anchor else Mode.WALK)
	held.visible = true
	held.show_item(held_id)
	Events.cleaning_mode_changed.emit(false)


# ------------------------------------------------------------------ fyzika

func _physics_process(delta: float) -> void:
	Nature.grass_mat().set_shader_parameter("player_pos", global_position)
	if ladder or anchor:
		_support_physics(delta)
		_update_focus()
		return
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= _gravity * delta

	var input := Vector2.ZERO
	if not ui_open:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	if mode == Mode.WALK:
		var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
		var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") and not carried else WALK_SPEED
		if carried:
			speed *= GameState.carry_speed_mult()
		var target := dir * speed
		var accel := 11.0 if on_floor else 2.5
		var k := 1.0 - exp(-accel * delta)
		velocity.x = lerpf(velocity.x, target.x, k)
		velocity.z = lerpf(velocity.z, target.z, k)
		if on_floor and not ui_open and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		# V pracovním režimu jde jen přešlapovat podél okna (A/D).
		var tangent := cleaning.window.global_basis.x.normalized() if cleaning.window else Vector3.ZERO
		var target := tangent * input.x * 0.9
		var k := 1.0 - exp(-10.0 * delta)
		velocity.x = lerpf(velocity.x, target.x, k)
		velocity.z = lerpf(velocity.z, target.z, k)

	var before := global_position
	move_and_slide()

	# Kroky.
	if is_on_floor():
		var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
		_step_dist += moved
		if _step_dist > (0.75 if mode == Mode.WALK else 0.35):
			_step_dist = 0.0
			Audio.play("step", -14.0 if mode == Mode.WALK else -20.0, randf_range(0.85, 1.1))
		if moved < 0.5 and global_position.y > -1.0:
			_last_safe = global_position
		_safe_t += delta
		if _safe_t > 0.3:
			_safe_t = 0.0
			_safe_hist.append(global_position)
			if _safe_hist.size() > 4:
				_safe_hist.pop_front()
		_air_top = global_position.y
	else:
		_air_top = maxf(_air_top, global_position.y)
		# Relaxační hra: pád z výšky nikdy netrestá – hráče vrátíme zpět.
		if _air_top - global_position.y > SAFE_FALL:
			_safe_return("Opatrně, tohle by bolelo! Vrátil ses na bezpečné místo.")

	# Pád mimo mapu = bezpečný návrat.
	if global_position.y < -12.0:
		_safe_return("Opatrně! Vrátil ses na bezpečné místo.")

	_update_focus()
	if carried is Ladder:
		_update_ladder_ghost()
	elif carried:
		_update_ghost()


func _safe_return(msg: String) -> void:
	var p := _last_safe
	if not _safe_hist.is_empty():
		p = _safe_hist[0]
	global_position = p + Vector3(0, 0.05, 0)
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_air_top = global_position.y
	_safe_hist.clear()
	Audio.play("click", -6.0, 0.7)
	Events.toast(msg, "info")


func _update_focus() -> void:
	focus_window = null
	focus_object = null
	if mode == Mode.CLEANING or ui_open:
		return
	var from := camera.global_position
	var to := from - camera.global_basis.z * (REACH + GameState.reach_bonus(GameState.get_tool(held_id)))
	var ex: Array[RID] = [get_rid()]
	if ladder:
		ex.append(ladder.get_rid())
	if anchor:
		ex.append(anchor.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | CleanableWindow.WINDOW_LAYER, ex)
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	if col.has_meta("window"):
		focus_window = col.get_meta("window")
		focus_point = hit["position"]
	elif col.has_meta("interactable"):
		focus_object = col.get_meta("interactable")


## Text nápovědy k tomu, na co hráč míří (pro HUD).
func get_prompt() -> String:
	if mode == Mode.CLEANING:
		return ""
	if carried is Ladder and focus_object is Node and (focus_object as Node).has_meta("van_rack"):
		return "[E] Naložit žebřík na střechu dodávky"
	if carried is Ladder:
		return "[E] / [LMB] Opřít žebřík o zeď" if _ghost_valid else "Žebřík nes ke zdi – opřít ho jde o rovnou stěnu na rovném terénu"
	if carried:
		var what := "kbelík" if carried is Bucket else "židli"
		return ("[E] / [LMB] Položit %s    [kolečko] Otočit" % what) if _ghost_valid else ("Sem %s položit nejde" % what)
	var extra := ""
	if mode == Mode.LADDER:
		extra = "[W]/[S] Nahoru / dolů    " + ("[Mezerník] Slézt ze žebříku" if ladder_h < 0.35 else ("Slézám dolů…" if _auto_descend else "[Mezerník] Slézt dolů"))
	elif mode == Mode.ROPE:
		extra = "[W]/[S] Nahoru / dolů    [A]/[D] Do stran    "
		if _rope_can_exit() != "":
			extra += "[Mezerník] Odepnout se"
		elif anchor is ClimbGrip:
			extra += "do střechy %.0f m" % maxf(0.0, anchor.top_feet() - rope_y)
		elif anchor is SuspendedPlatform:
			extra += "nad zemí %.0f m" % maxf(0.0, rope_y - anchor.bottom_feet())
		else:
			extra += "lano %.0f / %.0f m" % [anchor.global_position.y - rope_y, RopeAnchor.ROPE_LENGTH]
	var main := _focus_prompt()
	if extra != "":
		return main + ("\n" if main != "" else "") + extra
	return main


func _focus_prompt() -> String:
	if focus_window:
		var w := focus_window
		if w.completed:
			return "Okno je čisté ✓"
		if not ContractManager.can_clean(w.window_id):
			return "Okno – nejdřív přijmi zakázku v tabletu [Tab]"
		var pct := int(floor(w.cleanliness() * 100.0))
		var rb := ""
		var fleet := RobotFleet.get_fleet(self)
		if fleet:
			var hint := fleet.window_hint(w)
			if hint != "":
				rb = "    " + hint
		if _holding_spray():
			return "[LMB] / [F] Nastříkat: %s    [E] Mýt okno (%d %%)%s" % [GameState.item_name(held_id), pct, rb]
		return "[E] / [LMB] Začít mýt okno (%d %%)%s" % [pct, rb]
	if focus_object and focus_object.has_method("get_prompt"):
		return focus_object.get_prompt(self)
	return ""


# ------------------------------------------------------------------ kamera

func _process(delta: float) -> void:
	if mode == Mode.CLEANING:
		cleaning.update(delta)
	if _e_hold_t >= 0.0:
		_e_hold_t += delta
		if _e_hold_t >= HOLD_PICKUP:
			_e_hold_t = -1.0
			if is_instance_valid(_e_hold_target) and mode == Mode.WALK and carried == null:
				pick_up(_e_hold_target)
			_e_hold_target = null
	_update_camera(delta)
	if carried:
		_ghost.visible = not ui_open
	_update_rope_visual()


func _update_camera(delta: float) -> void:
	var body_pos := get_global_transform_interpolated().origin if is_inside_tree() else global_position
	var bob := Vector3.ZERO
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if Settings.head_bob and mode == Mode.WALK and is_on_floor() and hspeed > 0.5:
		_bob_t += delta * hspeed * 1.9
		bob = Vector3(0, sin(_bob_t * 2.0) * 0.012, 0)
	var walk_xf := Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), body_pos + Vector3(0, EYE_HEIGHT, 0) + bob)
	var target := 1.0 if mode == Mode.CLEANING else 0.0
	_blend = move_toward(_blend, target, delta / CAMERA_BLEND_TIME) if delta > 0.0 else target
	var s := smoothstep(0.0, 1.0, _blend)
	if s > 0.0001 and cleaning.has_pose:
		camera.global_transform = walk_xf.interpolate_with(cleaning.camera_xf, s)
	else:
		camera.global_transform = walk_xf


# ------------------------------------------------------------------ židle

func pick_up(obj: Node3D) -> void:
	if carried or mode != Mode.WALK:
		return
	carried = obj
	obj.set_carried(true)
	if obj is Ladder:
		held.show_carry(obj.carry_mesh, Transform3D(Basis(Vector3.UP, 0.12), Vector3(0.38, -0.42, 0.55)))
	else:
		held.show_chair(obj.mesh)
	_ghost.mesh = obj.mesh
	_ghost.material_override = Mats.ghost(true)
	_ghost.visible = true
	_ghost_rot = 0.0
	Audio.play("pickup")


func _update_ghost() -> void:
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	var space := get_world_3d().direct_space_state
	var chair_yaw := yaw + _ghost_rot
	_ghost_valid = false
	# Zkusíme několik vzdáleností – u zdi se židle sama přisune blíž.
	var dists: Array[float] = [1.05, 0.9, 0.78, 1.25]
	if Talents.has_effect("carry"):
		dists.append_array([1.5, 1.8])
	for dist: float in dists:
		var base := global_position + fwd * dist
		var q := PhysicsRayQueryParameters3D.create(base + Vector3.UP * 1.2, base + Vector3.DOWN * 1.5, 1, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		var p: Vector3 = hit["position"]
		_ghost_xf = Transform3D(Basis(Vector3.UP, chair_yaw), p)
		if n.y < 0.9 or absf(p.y - global_position.y) > 0.6:
			continue
		var shape := BoxShape3D.new()
		shape.size = Chair.SEAT_SIZE - Vector3(0.04, 0.06, 0.04)
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = shape
		sq.transform = Transform3D(_ghost_xf.basis, p + Vector3(0, Chair.SEAT_SIZE.y * 0.5 + 0.04, 0))
		sq.collision_mask = 1
		sq.exclude = [get_rid()]
		if space.intersect_shape(sq, 1).is_empty():
			_ghost_valid = true
			break
	_ghost.global_transform = _ghost_xf
	_ghost.material_override = Mats.ghost(_ghost_valid)


func _try_place() -> void:
	if carried == null:
		return
	# žebřík na střešní nosič firemní dodávky
	if carried is Ladder and focus_object is Node and (focus_object as Node).has_meta("van_rack"):
		var base: CompanyBase = (focus_object as Node).get_meta("van_rack")
		if base.stow_ladder(self, carried):
			return
	if not _ghost_valid:
		if carried is Ladder:
			Events.toast("Žebřík opři o rovnou zeď – postav se k ní čelem (do 2,5 m) na rovném terénu.", "warn")
		else:
			Events.toast("Sem %s položit nejde – zkus rovné volné místo." % ("kbelík" if carried is Bucket else "židli"), "warn")
		return
	carried.global_transform = _ghost_xf
	carried.reset_physics_interpolation()
	release_carried()
	Audio.play("step", -6.0, 0.7)


## Pustí nesený předmět z rukou (kam ho položit, řeší volající).
func release_carried() -> void:
	if carried == null:
		return
	carried.set_carried(false)
	carried = null
	_ghost.visible = false
	held.show_item(held_id)


# ------------------------------------------------------------------ ukládání

func save_state() -> Dictionary:
	# Na žebříku / laně se ukládá bezpečné místo u opory (načtení tě postaví na zem).
	var pos := global_position
	if ladder:
		pos = _ladder_exit_pos()
	elif anchor:
		pos = anchor.roof_spot()
	return {
		"pos": SaveManager.vec3_to_arr(pos),
		"yaw": yaw, "pitch": pitch, "held": held_id,
	}


func load_state(d: Dictionary) -> void:
	if d.is_empty():
		return
	if mode == Mode.CLEANING:
		end_cleaning()
	ladder = null
	if anchor is ClimbGrip:
		anchor.queue_free()
	anchor = null
	mode = Mode.WALK
	global_position = SaveManager.arr_to_vec3(d.get("pos"), global_position)
	yaw = float(d.get("yaw", yaw))
	pitch = float(d.get("pitch", pitch))
	held_id = str(d.get("held", ""))
	if held_id == "":
		# Uložení v1: 0 = hadr, 1 = saponát.
		held_id = "detergent_basic" if int(d.get("equipped", 0)) == 1 else GameState.active_wipe
	if not GameState.has_item(held_id):
		held_id = GameState.active_wipe
	held.show_item(held_id)
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_last_safe = global_position
	_safe_hist.clear()
	_air_top = global_position.y


# ------------------------------------------------------------------ žebřík

func _update_ladder_ghost() -> void:
	var l: Ladder = carried
	var space := get_world_3d().direct_space_state
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	_ghost_valid = false
	var from := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 2.6, 1 | CleanableWindow.WINDOW_LAYER, [get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_ghost_xf = Transform3D(Basis(Vector3.UP, yaw), global_position + fwd * 1.2)
	else:
		var n: Vector3 = hit["normal"]
		var nh := Vector3(n.x, 0.0, n.z)
		if absf(n.y) < 0.3 and nh.length() > 0.5:
			nh = nh.normalized()
			var wall_p: Vector3 = hit["position"]
			var base := wall_p + nh * l.base_offset()
			var dq := PhysicsRayQueryParameters3D.create(base + Vector3.UP * 0.9, base + Vector3.DOWN * 1.2, 1, [get_rid()])
			var g := space.intersect_ray(dq)
			var basis := Basis.looking_at(-nh, Vector3.UP)
			if not g.is_empty():
				base.y = (g["position"] as Vector3).y
				_ghost_xf = Transform3D(basis, base)
				var gn: Vector3 = g["normal"]
				# Opřít jde jen na rovné zemi a o zeď, která sahá aspoň do poloviny žebříku.
				var mid := base + basis * (Ladder.up_local() * l.length * 0.5) + Vector3.UP * 0.0
				var wq := PhysicsRayQueryParameters3D.create(mid + nh * 0.6, mid - nh * 1.0, 1 | CleanableWindow.WINDOW_LAYER, [get_rid()])
				var wall_ok := not space.intersect_ray(wq).is_empty()
				_ghost_valid = gn.y > 0.92 and absf(base.y - global_position.y) < 0.6 and wall_ok
			else:
				_ghost_xf = Transform3D(basis, base)
		else:
			_ghost_xf = Transform3D(Basis(Vector3.UP, yaw), hit["position"])
	_ghost.global_transform = _ghost_xf
	_ghost.material_override = Mats.ghost(_ghost_valid)


func climb_ladder(l: Ladder) -> void:
	if mode != Mode.WALK or carried:
		return
	ladder = l
	ladder_h = 0.0
	mode = Mode.LADDER
	velocity = Vector3.ZERO
	var f := -l.global_basis.z
	yaw = atan2(-f.x, -f.z)
	global_position = l.feet_at(0.0)
	reset_physics_interpolation()
	Audio.play("step", -10.0, 0.8)


func _ladder_exit_pos() -> Vector3:
	var p := ladder.feet_at(0.0) + ladder.global_basis.z.normalized() * 0.25
	p.y = ladder.global_position.y + 0.05
	return p


## Sestup ze žebříku – dole hned, výš se nejdřív sleze po příčkách (mezerník).
func leave_ladder() -> void:
	if ladder == null:
		return
	if ladder_h > 0.35:
		_auto_descend = true
		return
	_auto_descend = false
	global_position = _ladder_exit_pos()
	ladder = null
	mode = Mode.WALK
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_air_top = global_position.y
	_safe_hist.clear()


# ------------------------------------------------------------------ lano

func attach_rope(a: RopeAnchor) -> void:
	if mode != Mode.WALK or carried:
		return
	anchor = a
	rope_u = 0.0
	rope_y = a.top_feet()
	mode = Mode.ROPE
	velocity = Vector3.ZERO
	var f := -a.outward()
	yaw = atan2(-f.x, -f.z)
	pitch = deg_to_rad(-10.0)
	global_position = a.hang_pos(rope_u, rope_y)
	reset_physics_interpolation()
	Audio.play("pickup", -4.0, 0.8)
	if a.has_method("attach_text"):
		Events.toast(a.attach_text(), "info")
	else:
		Events.toast("Připnuto. [S] spouštění dolů, [W] nahoru, [A]/[D] do stran. Okno umyješ jako obvykle [E].", "info")


## Kde se jde odepnout: "top" (zpět na střechu), "bottom" (na zem), "" (nikde).
func _rope_can_exit() -> String:
	if anchor == null:
		return ""
	if rope_y >= anchor.top_feet() - 0.15:
		return "top"
	if rope_y <= anchor.bottom_feet() + 0.15 and anchor.bottom_feet() <= anchor.ground_y + 0.05:
		return "bottom"
	return ""


func _rope_exit() -> void:
	var where := _rope_can_exit()
	if where == "":
		Events.toast("Odepnout se můžeš bezpečně nahoře u kotvy nebo dole na zemi.", "info")
		return
	var p: Vector3
	if where == "top":
		p = anchor.roof_spot()
	else:
		p = anchor.hang_pos(rope_u, anchor.ground_y + 0.05) + anchor.outward() * anchor.exit_out()
	if anchor is ClimbGrip:
		anchor.queue_free()
	anchor = null
	mode = Mode.WALK
	global_position = p
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_air_top = global_position.y
	_safe_hist.clear()
	Audio.play("click", -6.0, 1.0)


func _update_rope_visual() -> void:
	if anchor == null:
		for rm in _rope_mi:
			rm.visible = false
		return
	if anchor is SuspendedPlatform:
		for rm in _rope_mi:
			rm.visible = false
		(anchor as SuspendedPlatform).rig_visual(rope_u, rope_y)
		return
	if anchor.has_method("hides_rope"):
		for rm in _rope_mi:
			rm.visible = false
		return
	var top := anchor.global_position + Vector3.UP * 0.4
	var edge := anchor.global_position + anchor.outward() * (anchor.wall_out + 0.06)
	edge.y = anchor.roof_y + anchor.edge_h + 0.04
	var body := get_global_transform_interpolated().origin if is_inside_tree() else global_position
	var harness := body + Vector3.UP * 1.0 + anchor.outward() * 0.12
	_rope_segment(_rope_mi[0], top, edge)
	_rope_segment(_rope_mi[1], edge, harness)


func _rope_segment(rm: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len_m := d.length()
	if len_m < 0.01:
		rm.visible = false
		return
	var y := d / len_m
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	rm.global_transform = Transform3D(Basis(x, y * len_m, z), (a + b) * 0.5)
	rm.visible = true


# ------------------------------------------------------------------ opora

## Pohyb na žebříku / laně. Pozice se odvozuje přímo z opory, takže je stabilní.
func _support_physics(delta: float) -> void:
	velocity = Vector3.ZERO
	var input := Vector2.ZERO
	if not ui_open:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# V pracovním režimu jde posun jen pomalu (myš ovládá nástroj).
	var k := 0.4 if mode == Mode.CLEANING else 1.0
	if ladder:
		if not is_instance_valid(ladder):
			ladder = null
			mode = Mode.WALK
			return
		var before := ladder_h
		if _auto_descend:
			if input.y < -0.1 or mode != Mode.LADDER:
				_auto_descend = false
			else:
				input.y = 1.6
		ladder_h = clampf(ladder_h - input.y * Ladder.CLIMB_SPEED * k * delta, 0.0, ladder.max_stand())
		if _auto_descend and ladder_h <= 0.0:
			_auto_descend = false
			global_position = ladder.feet_at(0.0)
			leave_ladder()
			return
		global_position = ladder.feet_at(ladder_h)
		_step_dist += absf(ladder_h - before)
		if _step_dist > 0.28:
			_step_dist = 0.0
			Audio.play("step", -16.0, randf_range(1.15, 1.3))
	elif anchor:
		var before := Vector2(rope_u, rope_y)
		var sp := anchor.speed() * k
		rope_y = clampf(rope_y - input.y * sp * delta, anchor.bottom_feet(), anchor.top_feet())
		var r := anchor.side_range()
		rope_u = clampf(rope_u + input.x * sp * 0.8 * delta, -r, r)
		global_position = anchor.hang_pos(rope_u, rope_y)
		_step_dist += (Vector2(rope_u, rope_y) - before).length()
		if _step_dist > 0.6:
			_step_dist = 0.0
			Audio.play("cloth", -18.0, randf_range(0.7, 0.8))


## Aktuální opora (pro HUD/testy): "ladder", "rope" nebo "".
func support() -> String:
	if ladder:
		return "ladder"
	if anchor:
		return "rope"
	return ""

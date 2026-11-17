class_name HandRig
extends Node3D
## Ruka s hadrem v pracovním režimu. Leží ve světových souřadnicích přímo
## na skle; zápěstí se natáčí podle směru tahu, hadr se při přitlačení zplacatí.

const SKIN := Color(0.93, 0.74, 0.6)

var rag_node: MeshInstance3D
var palm: MeshInstance3D
var forearm: MeshInstance3D
var upper_arm: MeshInstance3D
var bottle: Node3D
## Teleskopická tyč (jen u nástrojů s reach_bonus).
var pole: MeshInstance3D
## Ruka svírající tyč, rukojeť stěrky nebo tělo kartáče (místo ploché dlaně).
var grip: MeshInstance3D
var _grip_thin: ArrayMesh
var _grip_thick: ArrayMesh
## Netočivé tělo elektrického kartáče (točí se jen kotouč v rag_node).
var brush_body: MeshInstance3D
var _tele := false
var _spin := 0.0
var _rag_mat: StandardMaterial3D
var _roll := 0.0
var _tilt := Vector2.ZERO
var _circle := 0.0
var _prev_vel := Vector2.ZERO
var _bottle_t := 0.0
var _base_color := Color(0.86, 0.74, 0.45)
var _visual := "rag"
var _bottle_color := Color(0.3, 0.72, 0.86)
## Ždímání [R]: krátká animace (nástroj se zmáčkne a odstoupí od skla) a kapky.
var _wring_t := 0.0
var _drips: CPUParticles3D


func _ready() -> void:
	top_level = true
	visible = false

	rag_node = MeshInstance3D.new()
	rag_node.mesh = ToolVisuals.rag_mesh()
	_rag_mat = StandardMaterial3D.new()
	_rag_mat.vertex_color_use_as_albedo = true
	_rag_mat.roughness = 1.0
	_rag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rag_node.material_override = _rag_mat
	add_child(rag_node)

	palm = MeshInstance3D.new()
	palm.mesh = _make_hand_mesh()
	add_child(palm)

	forearm = MeshInstance3D.new()
	add_child(forearm)
	upper_arm = MeshInstance3D.new()
	add_child(upper_arm)
	_build_sleeves()
	Events.cosmetics_changed.connect(_build_sleeves)

	bottle = ToolVisuals.spray_bottle(_bottle_color)
	bottle.visible = false
	add_child(bottle)

	var pb := MeshBuilder.new(7)
	pb.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.026, 1.0, 0.026)), Vector3(0, 0.5, 0)), Color(0.78, 0.8, 0.83), 0.02)
	pb.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.036, 0.25, 0.036)), Vector3(0, 0.12, 0)), Color(0.15, 0.15, 0.16), 0.02)
	pole = MeshInstance3D.new()
	pole.mesh = pb.commit()
	pole.visible = false
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pole)

	_grip_thin = ToolVisuals.grip_mesh(0.016)
	_grip_thick = ToolVisuals.grip_mesh(0.034)
	grip = MeshInstance3D.new()
	grip.mesh = _grip_thin
	grip.visible = false
	add_child(grip)
	brush_body = MeshInstance3D.new()
	brush_body.visible = false
	add_child(brush_body)

	_drips = CPUParticles3D.new()
	_drips.top_level = true
	_drips.emitting = false
	_drips.one_shot = true
	_drips.amount = 36
	_drips.lifetime = 0.8
	_drips.explosiveness = 0.35
	_drips.local_coords = false
	_drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drips.emission_box_extents = Vector3(0.05, 0.02, 0.02)
	_drips.direction = Vector3(0, -1, 0)
	_drips.spread = 12.0
	_drips.gravity = Vector3(0, -9.0, 0)
	_drips.initial_velocity_min = 0.1
	_drips.initial_velocity_max = 0.5
	_drips.scale_amount_min = 0.6
	_drips.scale_amount_max = 1.3
	var dq := QuadMesh.new()
	dq.size = Vector2(0.01, 0.016)
	dq.material = Mats.particle(Color(1, 1, 1, 1))
	_drips.mesh = dq
	add_child(_drips)

	for mi in [rag_node, palm, forearm, upper_arm, grip, brush_body]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func begin(tool: ToolData) -> void:
	_base_color = tool.color
	_visual = tool.visual
	rag_node.mesh = ToolVisuals.contact_mesh(tool)
	rag_node.material_override = null if _visual == "squeegee" or _visual == "brush" or _visual == "finger" else _rag_mat
	_tele = tool.reach_bonus > 0.0
	pole.visible = _tele
	brush_body.visible = _visual == "brush"
	if brush_body.visible:
		brush_body.mesh = ToolVisuals.brush_pole_mesh(tool.color) if _tele else ToolVisuals.brush_body_mesh(tool.color)
	grip.visible = _tele or _visual == "squeegee" or _visual == "brush"
	grip.mesh = _grip_thick if (_visual == "brush" and not _tele) else _grip_thin
	palm.visible = not grip.visible and _visual != "finger"
	visible = true
	_roll = 0.0
	_tilt = Vector2.ZERO


func end() -> void:
	visible = false
	bottle.visible = false


func flash_bottle(t: ToolData = null) -> void:
	if t and t.color != _bottle_color:
		_bottle_color = t.color
		var old := bottle
		bottle = ToolVisuals.spray_bottle(_bottle_color)
		bottle.visible = false
		add_child(bottle)
		old.queue_free()
	_bottle_t = 0.9


func play_wring(dirt: float) -> void:
	_wring_t = 0.7
	_drips.color = Color(0.85, 0.92, 0.95, 0.75).lerp(Color(0.5, 0.42, 0.3, 0.85), clampf(dirt * 1.2, 0.0, 1.0))
	_drips.restart()
	_drips.emitting = true


func pose(c: CleaningController, delta: float) -> void:
	var w := c.window
	if w == null:
		return
	var n := w.normal()
	var right := w.global_basis.x.normalized()
	var up := w.global_basis.y.normalized()
	var k := 1.0 - exp(-12.0 * delta)

	# Natočení zápěstí: náklon ve směru tahu + rotace při krouživém pohybu.
	var vel := c.rag_vel
	var turn := 0.0
	if vel.length() > 0.05 and _prev_vel.length() > 0.05:
		turn = _prev_vel.angle_to(vel)
	_prev_vel = vel
	_circle = lerpf(_circle, clampf(turn * 6.0, -0.6, 0.6), k)
	_roll = lerpf(_roll, clampf(-vel.x * 0.35, -0.35, 0.35) + _circle, k)
	_tilt = _tilt.lerp(Vector2(clampf(vel.y * 0.25, -0.25, 0.25), clampf(-vel.x * 0.25, -0.25, 0.25)), k)

	var wr := 0.0
	if _wring_t > 0.0:
		_wring_t = maxf(0.0, _wring_t - delta)
		wr = sin(clampf(_wring_t / 0.7, 0.0, 1.0) * PI)
	var gap := lerpf(0.035, 0.004, c.press) + wr * 0.09
	var contact := w.plane_to_world(c.rag, gap)
	var base := Basis(right, up, n)
	var squeegee := _visual == "squeegee"
	var rb: Basis
	if squeegee:
		# Lišta stěrky leží na skle kolmo ke směru tahu, jen se mírně naklání.
		rb = Basis(n, c.blade_angle) * Basis(right, _tilt.y * 0.3) * base
	elif _visual == "brush":
		# Rotační hlava kartáče se při přitlačení točí.
		_spin += delta * (2.0 + 22.0 * c.press)
		rb = Basis(n, _spin) * base
	else:
		rb = Basis(n, _roll) * Basis(right, _tilt.y) * Basis(up, _tilt.x) * base
	var squash := lerpf(1.0, 0.55, c.press) if _visual == "rag" else (1.0 if _visual == "finger" else lerpf(1.0, 0.8, c.press))
	# při ždímání se nástroj zmáčkne a trochu zkroutí
	var rxf := rb * Basis(Vector3.BACK, wr * 0.5) * Basis.from_scale(Vector3(1.0 - wr * 0.35, 1.0 - wr * 0.2, squash * (1.0 - wr * 0.3)))
	# Naklopený nástroj nesmí zajet hranou pod sklo: posuneme ho od skla o tolik,
	# o kolik by jeho nejnižší roh prošel rovinou okna.
	var push := maxf(0.0, 0.0015 - gap - _min_along(rag_node.mesh, rxf, n))
	if _visual == "brush" and not _tele:
		push = maxf(push, 0.0015 - gap - _min_along(brush_body.mesh, Basis(right, _tilt.y * 0.5) * base, n))
	contact += n * push
	rag_node.global_transform = Transform3D(rxf, contact)
	if wr > 0.0:
		_drips.global_position = contact - up * 0.05 + n * 0.02

	# Barva hadru postupně tmavne od setřené špíny, vlhký hadr je tmavší.
	var col := _base_color.lerp(Color(0.45, 0.38, 0.3), c.rag_dirt * 0.6)
	# suchý nástroj je světlejší, nasáklý tmavší
	col = col.lightened(0.12 * (1.0 - c.moisture)).darkened(c.moisture * 0.3)
	_rag_mat.albedo_color = col

	var palm_pos := contact + n * (0.022 + 0.008 * (1.0 - c.press)) - up * 0.01
	var cam := c.camera_xf
	var wrist: Vector3
	if _tele:
		# Ruka svírá tyč u těla, nástroj je na jejím konci.
		var grip_at := cam.origin + cam.basis * Vector3(0.16, -0.42, -0.42)
		var head := contact + n * 0.03 + rb * Vector3(0, -0.09 if squeegee else 0.0, 0.05)
		if _visual == "brush":
			# motor kartáče sedí na konci tyče a netočí se, tyč vede do jeho zadní části
			brush_body.global_transform = Transform3D(base, contact)
			head = contact + n * 0.15
		_place_limb(pole, grip_at, head)
		var ax := (head - grip_at).normalized()
		grip.global_transform = Transform3D(ToolVisuals.grip_basis(ax), grip_at + ax * 0.12)
		palm_pos = grip_at + ax * 0.12
		wrist = palm_pos - ax * 0.06 + cam.basis.x * 0.03
	elif squeegee:
		# Ruka svírá rukojeť stěrky (rukojeť jde od lišty šikmo dolů a od skla).
		var hax := rb * Vector3(0, 0.85, -0.52)
		var hc := contact + rb * Vector3(0, -0.115, 0.093)
		grip.global_transform = Transform3D(ToolVisuals.grip_basis(hax), hc)
		palm_pos = hc
		wrist = hc - hax * 0.07
	elif _visual == "brush":
		# Kotouč se točí, tělo strojku a ruka stojí.
		var sb := Basis(right, _tilt.y * 0.5) * base
		brush_body.global_transform = Transform3D(sb, contact)
		var bax := sb * Vector3(0, -0.39, 0.92)
		var bc := contact + sb * Vector3(0, -0.02, 0.17)
		grip.global_transform = Transform3D(ToolVisuals.grip_basis(-bax) * Basis(Vector3.UP, PI * 0.5), bc)
		palm_pos = bc
		wrist = bc + bax * 0.1
	elif _visual == "finger":
		# ruka s ukazováčkem: zápěstí za pěstí, kousek pod ní
		wrist = contact + n * 0.14 - up * 0.03 + right * 0.01
	elif _visual == "sponge":
		palm_pos = contact + n * (0.06 + 0.008 * (1.0 - c.press))
		palm.global_transform = Transform3D(rb, palm_pos)
		wrist = palm_pos + n * 0.02 - up * 0.075 + right * 0.01
	else:
		palm.global_transform = Transform3D(rb, palm_pos)
		wrist = palm_pos + n * 0.02 - up * 0.075 + right * 0.01

	var shoulder := cam.origin + cam.basis * Vector3(0.42, -0.55, 0.05)
	var mid := (shoulder + wrist) * 0.5
	var elbow := mid - up * 0.1 + right * 0.12 + n * 0.08
	_place_limb(forearm, wrist, elbow)
	_place_limb(upper_arm, elbow, shoulder)

	# Levá ruka se sprejem se krátce objeví při stříknutí.
	if _bottle_t > 0.0:
		_bottle_t = maxf(0.0, _bottle_t - delta)
		var show := sin(clampf(_bottle_t / 0.9, 0.0, 1.0) * PI)
		bottle.visible = true
		var bpos := cam.origin + cam.basis * Vector3(lerpf(-0.45, -0.24, show), lerpf(-0.45, -0.2, show), -0.38)
		var target := w.plane_to_world(c.rag)
		bottle.global_transform = Transform3D(Basis.looking_at(target - bpos, Vector3.UP), bpos)
	else:
		bottle.visible = false


## Nejmenší vzdálenost bodu meshe (rohy jeho AABB) od počátku ve směru n.
static func _min_along(m: Mesh, b: Basis, n: Vector3) -> float:
	if m == null:
		return 0.0
	var box := m.get_aabb()
	var lo := INF
	for i in 8:
		lo = minf(lo, (b * box.get_endpoint(i)).dot(n))
	return lo


func _place_limb(mi: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.001:
		return
	var b := MeshBuilder.basis_y(d)
	mi.global_transform = Transform3D(b * Basis.from_scale(Vector3(1.0, length, 1.0)), from)


func _make_hand_mesh() -> ArrayMesh:
	# Dlaň v pracovní rukavici položená na hadru, prsty mírně rozevřené
	# (lokálně: +Y = k prstům, +Z = od skla). Články prstů s klouby, palec stranou.
	var b := MeshBuilder.new(9)
	var g := ToolVisuals.GLOVE
	var gp := ToolVisuals.GLOVE_PALM
	# stejná plochá dlaň jako v ruce mimo okno (prsty lokálně -Z → zde +Y, hřbet → +Z)
	ToolVisuals.palm(b, Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, -0.008, 0.006)))
	for f in 4:
		var x := -0.03 + f * 0.02
		var length: float = [0.058, 0.068, 0.066, 0.053][f]
		var spread := (f - 1.5) * 0.08
		var dir := Vector3(-sin(spread), cos(spread), 0.0)
		var k0 := Vector3(x, 0.036, 0.002)
		var k1 := k0 + dir * length * 0.55 + Vector3(0, 0, -0.003)
		var k2 := k1 + dir * length * 0.45 + Vector3(0, 0, -0.004)
		b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.021), k0), g, 0.0)
		ToolVisuals._limb(b, k0, k1, 0.0092, g, "cyl6")
		b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.018), k1), g, 0.0)
		ToolVisuals._limb(b, k1, k2, 0.0085, g, "cyl6")
		b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.017), k2), gp, 0.0)
	var t0 := Vector3(-0.038, -0.02, 0.004)
	var t1 := t0 + Vector3(-0.026, 0.022, -0.002)
	var t2 := t1 + Vector3(-0.012, 0.022, -0.004)
	ToolVisuals._limb(b, t0, t1, 0.0115, g, "cyl6")
	b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.022), t1), g, 0.0)
	ToolVisuals._limb(b, t1, t2, 0.0105, g, "cyl6")
	b.add("sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.019), t2), gp, 0.0)
	# manžeta rukavice u zápěstí
	b.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.07, 0.03, 0.05)), Vector3(0, -0.068, 0.006)), ToolVisuals.CUFF, 0.0)
	return b.commit()


## Rukávy v barvě pracovního oblečení (Cosmetics, mění se v tabletu).
func _build_sleeves() -> void:
	var sl := Cosmetics.sleeve()
	var fb := MeshBuilder.new(5)
	fb.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.085, 0.86, 0.08)), Vector3(0, 0.57, 0)), sl, 0.04)
	fb.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.095, 0.05, 0.09)), Vector3(0, 0.15, 0)), sl.darkened(0.2), 0.02)
	fb.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.068, 0.11, 0.064)), Vector3(0, 0.055, 0)), ToolVisuals.CUFF, 0.0)
	fb.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.074, 0.02, 0.07)), Vector3(0, 0.115, 0)), ToolVisuals.CUFF.darkened(0.2), 0.0)
	forearm.mesh = fb.commit()
	var ub := MeshBuilder.new(6)
	ub.add("cyl10", Transform3D(Basis.from_scale(Vector3(0.09, 1.0, 0.085)), Vector3(0, 0.5, 0)), sl, 0.04)
	upper_arm.mesh = ub.commit()

class_name DirtMask
extends RefCounted
## Nízkorozlišovací maska znečištění jednoho okna.
##
## Data žijí na CPU v polích (přesnost) a zároveň v bajtových polích,
## která se jednou za snímek (jen když se něco změnilo) nahrají do textur:
##  * dirt_texture (RGBA8): R = množství špíny, G = odolnost, B = typ nečistoty
##  * wet_texture  (R8, poloviční rozlišení): vlhkost skla
## Na CPU navíc (poloviční rozlišení): chem = odmašťovací síla přípravku na skle,
## boost = jak silně přípravek rozpouští běžnou špínu.
## Shader glass_dirt.gdshader z textur skládá výsledný vzhled skla.
##
## Souřadnice: plane = metry od levého dolního rohu skla (u doprava, v nahoru).

const PX_PER_M := 110.0
const WET_DIV := 2
const WET_EVAPORATION := 0.045  ## za sekundu
const KIND_STEP := 36           ## typ v kanálu B = kind * KIND_STEP

var size_m := Vector2.ONE
var w := 0
var h := 0
var ww := 0
var wh := 0

var dirt := PackedFloat32Array()
var tough := PackedFloat32Array()
var kind := PackedByteArray()
## Jak rychle hadr stírá vodu ze skla (menší = sklo zůstane déle mokré
## a voda z rozprašovače pomáhá po víc tahů).
const RAG_ABSORB := 0.6

var wet := PackedFloat32Array()
var chem := PackedFloat32Array()
var boost := PackedFloat32Array()
var bytes := PackedByteArray()
var wet_bytes := PackedByteArray()

var image: Image
var texture: ImageTexture
var wet_image: Image
var wet_texture: ImageTexture

var initial_total := 1.0
var current_total := 0.0
## Počáteční množství špíny podle typu (pro rozhraní a nápovědy).
var initial_by_kind := PackedFloat32Array()
var changed := false
var wet_changed := false
var wet_active := false
## Násobek rychlosti odpařování podle posledního přípravku (a talentů).
var evap_mult := 1.0
## Voda nasátá nástrojem při posledním tahu (kladná) / vydaná na sklo (záporná).
var last_absorbed := 0.0
## Nejsilnější přípravek, který nástroj při posledním tahu nasál (houbička).
var last_chem_seen := 0.0

var drips: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _init(p_size: Vector2) -> void:
	size_m = p_size
	w = maxi(8, int(round(size_m.x * PX_PER_M)))
	h = maxi(8, int(round(size_m.y * PX_PER_M)))
	ww = maxi(4, int(ceil(w / float(WET_DIV))))
	wh = maxi(4, int(ceil(h / float(WET_DIV))))
	dirt.resize(w * h)
	dirt.fill(0.0)
	tough.resize(w * h)
	tough.fill(0.0)
	kind.resize(w * h)
	kind.fill(DirtTypes.DUST)
	wet.resize(ww * wh)
	wet.fill(0.0)
	chem.resize(ww * wh)
	chem.fill(0.0)
	boost.resize(ww * wh)
	boost.fill(0.0)
	bytes.resize(w * h * 4)
	bytes.fill(0)
	wet_bytes.resize(ww * wh)
	wet_bytes.fill(0)
	initial_by_kind.resize(DirtTypes.COUNT)
	initial_by_kind.fill(0.0)


# ------------------------------------------------------------------ generování

## Procedurálně vygeneruje znečištění podle profilu. Stejný seed = stejné okno
## (kvůli ukládání se ukládá jen množství špíny, typy se vygenerují znovu).
## Profil "venkov_bezne" dává přesně stejné okno jako Etapa 1.
func generate(seed_value: int, level: float, p: DirtProfile = null, textures: bool = true) -> void:
	if p == null:
		p = DirtProfile.get_profile("")
	_rng.seed = seed_value
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 2.4
	n.fractal_octaves = 3
	var n2 := FastNoiseLite.new()
	n2.seed = seed_value + 77
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n2.frequency = 11.0
	n2.fractal_octaves = 2

	# 1) Prach a šedý film – víc dole a v rozích.
	var dust_min := 0.12 * minf(p.dust, 1.0)
	for y in h:
		var v := size_m.y - (y + 0.5) / PX_PER_M
		var row := y * w
		var bottom := 1.0 - clampf(v / size_m.y, 0.0, 1.0)
		for x in w:
			var u := (x + 0.5) / PX_PER_M
			var base := 0.58 + 0.30 * n.get_noise_2d(u, v) + 0.12 * n2.get_noise_2d(u, v)
			base += 0.22 * bottom
			var ed := minf(minf(u, size_m.x - u), minf(v, size_m.y - v))
			base += 0.30 * (1.0 - smoothstep(0.0, 0.10, ed))
			dirt[row + x] = clampf(base * level * p.dust, dust_min, 1.0)

	# 2) Svislé šmouhy po dešti (mírně odolnější).
	var streaks := int((3 + 4 * level * size_m.x) * p.streaks)
	for s in streaks:
		var sx := _rng.randf_range(0.03, size_m.x - 0.03)
		var top := _rng.randf_range(size_m.y * 0.35, size_m.y)
		var length := _rng.randf_range(0.15, 0.6)
		var width := _rng.randf_range(0.006, 0.014)
		var px0 := int((sx - width) * PX_PER_M)
		var px1 := int((sx + width) * PX_PER_M)
		var py0 := int((size_m.y - top) * PX_PER_M)
		var py1 := int((size_m.y - top + length) * PX_PER_M)
		for y in range(maxi(py0, 0), mini(py1, h - 1) + 1):
			var t := float(y - py0) / maxf(1.0, py1 - py0)
			var wobble := int(sin(t * 9.0 + s) * 1.5)
			for x in range(maxi(px0 + wobble, 0), mini(px1 + wobble, w - 1) + 1):
				var i := y * w + x
				dirt[i] = minf(1.0, dirt[i] + 0.28 * (1.0 - t * 0.7))
				tough[i] = maxf(tough[i], 0.18)
				kind[i] = DirtTypes.DROPS

	# 3) Zaschlé kapky – kroužky s tmavším okrajem.
	var drops := int(30 * level * size_m.x * size_m.y * p.drops)
	for d in drops:
		var c := Vector2(_rng.randf_range(0.0, size_m.x), _rng.randf_range(0.0, size_m.y))
		var r := _rng.randf_range(0.006, 0.02)
		_splat(c, r, 0.95, 0.42, true, DirtTypes.DROPS)

	# 4) Ptačí trus – výrazný, odolný.
	var birds := 0
	if level > 0.5 and p.bird > 0.0:
		birds = _rng.randi_range(1, 2) if size_m.x * size_m.y > 1.0 else _rng.randi_range(0, 1)
		birds = int(round(birds * p.bird))
	for b in birds:
		var c := Vector2(_rng.randf_range(0.15, size_m.x - 0.15), _rng.randf_range(size_m.y * 0.3, size_m.y - 0.1))
		_bird_splat(c, _rng.randf_range(0.022, 0.036))

	# --- typy nečistot Etapy 2 (generují se až po původních, aby se Etapa 1 nezměnila)
	if p.mud > 0.0:
		_gen_mud(p.mud * level)
	if p.grease > 0.0:
		_gen_grease(p.grease * level)
	if p.pollen > 0.0:
		_gen_pollen(p.pollen * level, seed_value)
	if p.heavy > 0.0:
		_gen_heavy(p.heavy * level, seed_value)

	_rebuild_bytes()
	initial_total = maxf(0.001, _sum())
	current_total = initial_total
	initial_by_kind.fill(0.0)
	for i in dirt.size():
		initial_by_kind[kind[i]] += dirt[i]
	if textures:
		_create_textures()


## Textury až v hlavním vlákně (po generování na pozadí).
func finish_textures() -> void:
	_create_textures()


## Bláto: cákance odspodu (od kol, z kaluží), hustší u spodního okraje.
func _gen_mud(amount: float) -> void:
	var count := int(55 * amount * size_m.x)
	for k in count:
		var v := size_m.y * pow(_rng.randf(), 2.0) * 0.75
		var c := Vector2(_rng.randf_range(0.0, size_m.x), v)
		var r := _rng.randf_range(0.008, 0.035) * (1.3 - v / size_m.y)
		_blob(c, r, _rng.randf_range(0.8, 1.0), 0.35, DirtTypes.MUD)
		# drobné odstřiky kolem
		for j in _rng.randi_range(1, 4):
			var off := Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-1.0, 4.0)) * r
			_blob(c + off, r * _rng.randf_range(0.15, 0.4), 0.9, 0.35, DirtTypes.MUD)
	# souvislý pás bláta u spodní hrany
	var band := 0.06 + 0.06 * amount
	for y in h:
		var v := size_m.y - (y + 0.5) / PX_PER_M
		if v > band * 1.6:
			continue
		for x in w:
			var u := (x + 0.5) / PX_PER_M
			var edge := band * (0.7 + 0.5 * sin(u * 23.0) * sin(u * 7.0 + 1.3))
			if v < edge:
				var i := y * w + x
				var val := clampf(0.75 + (edge - v) * 4.0, 0.0, 1.0)
				if val > dirt[i] * 0.9:
					dirt[i] = maxf(dirt[i], val)
					tough[i] = maxf(tough[i], 0.35)
					kind[i] = DirtTypes.MUD


## Mastnota: otisky dlaní a prstů a rozmazané šmouhy, hlavně ve výšce rukou.
func _gen_grease(amount: float) -> void:
	var prints := int((2 + 3.0 * size_m.x * size_m.y) * amount)
	for k in prints:
		var c := Vector2(_rng.randf_range(0.12, size_m.x - 0.12), _rng.randf_range(size_m.y * 0.15, size_m.y * 0.75))
		var ang := _rng.randf_range(-0.5, 0.5)
		var rot := Vector2(cos(ang), sin(ang))
		var s := _rng.randf_range(0.8, 1.1)
		# dlaň
		_ellipse(c, Vector2(0.04, 0.05) * s, ang, 0.62, DirtTypes.GREASE)
		# prsty
		for f in 4:
			var fx := (-0.033 + f * 0.022) * s
			var fl: float = [0.055, 0.065, 0.062, 0.05][f] * s
			var fc := c + _rot(Vector2(fx, 0.05 * s + fl * 0.6), rot)
			_ellipse(fc, Vector2(0.009, fl * 0.5), ang + (f - 1.5) * 0.08, 0.66, DirtTypes.GREASE)
		_ellipse(c + _rot(Vector2(-0.055 * s, 0.0), rot), Vector2(0.01, 0.03) * s, ang + 0.9, 0.62, DirtTypes.GREASE)
	# rozmazané šmouhy (oblouky po neúspěšném „utření rukávem")
	var smears := int((1 + 2.0 * size_m.x) * amount)
	for k in smears:
		var c := Vector2(_rng.randf_range(0.1, size_m.x - 0.1), _rng.randf_range(size_m.y * 0.2, size_m.y * 0.8))
		var rad := _rng.randf_range(0.08, 0.2)
		var a0 := _rng.randf() * TAU
		for j in 22:
			var a := a0 + j * 0.09
			_ellipse(c + Vector2(cos(a), sin(a)) * rad, Vector2(0.018, 0.012), a, 0.5, DirtTypes.GREASE)


## Pyl: jemný žlutý film na velké ploše (víc nahoře) a hustá drobná zrnka.
func _gen_pollen(amount: float, seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value + 501
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.6
	for y in h:
		var v := size_m.y - (y + 0.5) / PX_PER_M
		var up := clampf(v / size_m.y, 0.0, 1.0)
		var row := y * w
		for x in w:
			var u := (x + 0.5) / PX_PER_M
			var film := (0.32 + 0.22 * n.get_noise_2d(u, v) + 0.25 * up) * amount
			if film <= 0.05:
				continue
			var i := row + x
			if film > dirt[i] * 0.6:
				kind[i] = DirtTypes.POLLEN
				tough[i] = minf(tough[i], 0.05)
			dirt[i] = minf(1.0, maxf(dirt[i], film) + film * 0.25)
	var grains := int(260 * amount * size_m.x * size_m.y)
	for k in grains:
		var c := Vector2(_rng.randf_range(0.0, size_m.x), size_m.y * (1.0 - pow(_rng.randf(), 1.6)))
		_blob(c, _rng.randf_range(0.003, 0.007), 0.85, 0.05, DirtTypes.POLLEN)


## Silná špína: několik vrstev – tvrdá krusta na velkých plochách.
func _gen_heavy(amount: float, seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value + 909
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 3.2
	n.fractal_octaves = 3
	var thr := 0.25 - 0.3 * amount
	for y in h:
		var v := size_m.y - (y + 0.5) / PX_PER_M
		var bottom := 1.0 - clampf(v / size_m.y, 0.0, 1.0)
		var row := y * w
		for x in w:
			var u := (x + 0.5) / PX_PER_M
			var nv := n.get_noise_2d(u, v) + bottom * 0.35
			if nv < thr:
				continue
			var i := row + x
			dirt[i] = maxf(dirt[i], clampf(0.82 + (nv - thr) * 0.8, 0.0, 1.0))
			tough[i] = maxf(tough[i], 0.8)
			kind[i] = DirtTypes.HEAVY


## Jeden ptačí „dárek“: flek, cákance kolem a krátký stékající ocásek.
func _bird_splat(c: Vector2, r: float) -> void:
	_splat(c, r, 1.0, 1.0, false, DirtTypes.BIRD)
	for k in 4:
		var off := Vector2(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-1.6, 1.6)) * r
		_splat(c + off, r * _rng.randf_range(0.25, 0.5), 1.0, 0.9, false, DirtTypes.BIRD)
	for k in 6:
		_splat(c + Vector2(_rng.randf_range(-0.2, 0.2) * r, -r * (0.8 + k * 0.45)), r * 0.28, 1.0, 0.85, false, DirtTypes.BIRD)


# ------------------------------------------------------------------ špína přidaná během hry (Etapa 7)
## Ptáci kápnou na rozdělané okno. Ukládá se jako seznam [x, y, r, seed],
## aby se po načtení masky (která se generuje znovu ze semínka) dala přidat zpátky.
var extras: Array = []


func add_bird(c: Vector2, r: float, seed_value: int) -> void:
	var e := [c.x, c.y, r, seed_value]
	extras.append(e)
	_apply_extra(e)
	current_total = _sum()
	initial_total = maxf(initial_total, current_total)
	_rebuild_bytes()


func _apply_extra(e: Array) -> void:
	_rng.seed = int(e[3])
	_bird_splat(Vector2(float(e[0]), float(e[1])), float(e[2]))


func _rot(v: Vector2, r: Vector2) -> Vector2:
	return Vector2(v.x * r.x - v.y * r.y, v.x * r.y + v.y * r.x)


func _splat(c: Vector2, r: float, d_val: float, t_val: float, ring: bool, k: int) -> void:
	var cx := c.x * PX_PER_M
	var cy := (size_m.y - c.y) * PX_PER_M
	var rp := maxf(1.0, r * PX_PER_M)
	for y in range(maxi(0, int(cy - rp)), mini(h - 1, int(cy + rp)) + 1):
		for x in range(maxi(0, int(cx - rp)), mini(w - 1, int(cx + rp)) + 1):
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cy
			var t := sqrt(dx * dx + dy * dy) / rp
			if t > 1.0:
				continue
			var i := y * w + x
			var dv := d_val
			var tv := t_val
			if ring:
				var edge := smoothstep(0.55, 0.95, t)
				dv = lerpf(0.75, 1.0, edge)
				tv = lerpf(t_val * 0.75, t_val, edge)
			if tv >= tough[i]:
				kind[i] = k
			dirt[i] = maxf(dirt[i], dv)
			tough[i] = maxf(tough[i], tv)


## Měkký kulatý flek daného typu.
func _blob(c: Vector2, r: float, d_val: float, t_val: float, k: int) -> void:
	_ellipse(c, Vector2(r, r), 0.0, d_val, k, t_val)


## Měkká elipsa daného typu (otisky prstů, cákance).
func _ellipse(c: Vector2, radii: Vector2, ang: float, d_val: float, k: int, t_val: float = -1.0) -> void:
	if t_val < 0.0:
		t_val = 0.3
	var cx := c.x * PX_PER_M
	var cy := (size_m.y - c.y) * PX_PER_M
	var rmax := maxf(1.0, maxf(radii.x, radii.y) * PX_PER_M)
	var ca := cos(ang)
	var sa := sin(ang)
	var inv := Vector2(1.0 / maxf(radii.x * PX_PER_M, 0.5), 1.0 / maxf(radii.y * PX_PER_M, 0.5))
	for y in range(maxi(0, int(cy - rmax)), mini(h - 1, int(cy + rmax)) + 1):
		for x in range(maxi(0, int(cx - rmax)), mini(w - 1, int(cx + rmax)) + 1):
			var dx := x + 0.5 - cx
			var dy := -(y + 0.5 - cy)
			var lx := (dx * ca + dy * sa) * inv.x
			var ly := (-dx * sa + dy * ca) * inv.y
			var t := lx * lx + ly * ly
			if t > 1.0:
				continue
			var i := y * w + x
			var val := d_val * (1.0 - smoothstep(0.55, 1.0, t))
			if val > dirt[i] * 0.85:
				kind[i] = k
				tough[i] = t_val
			dirt[i] = maxf(dirt[i], val)


func _sum() -> float:
	var s := 0.0
	for v in dirt:
		s += v
	return s


func _rebuild_bytes() -> void:
	for i in dirt.size():
		bytes[i * 4] = int(dirt[i] * 255.0)
		bytes[i * 4 + 1] = int(tough[i] * 255.0)
		bytes[i * 4 + 2] = kind[i] * KIND_STEP
		bytes[i * 4 + 3] = 255
	for i in wet.size():
		wet_bytes[i] = int(wet[i] * 255.0)
	changed = true
	wet_changed = true


func _create_textures() -> void:
	image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	texture = ImageTexture.create_from_image(image)
	wet_image = Image.create_from_data(ww, wh, false, Image.FORMAT_L8, wet_bytes)
	wet_texture = ImageTexture.create_from_image(wet_image)
	changed = false
	wet_changed = false


# ------------------------------------------------------------------ čištění

func cleanliness() -> float:
	return clampf(1.0 - current_total / initial_total, 0.0, 1.0)


## Typy nečistot, které na okně na začátku byly (podíl > 3 %).
func kinds_present() -> Array[int]:
	var out: Array[int] = []
	var total := 0.0
	for v in initial_by_kind:
		total += v
	for k in DirtTypes.COUNT:
		if total > 0.0 and initial_by_kind[k] / total > 0.03:
			out.append(k)
	return out


## Tah kulatým nástrojem z bodu a do bodu b (metry na skle). Mezi vzorky se
## stopa skládá z překrývajících se otisků, takže ani rychlý pohyb myši
## nenechá mezery. Odstraněné množství je úměrné ujeté dráze –
## bez pohybu se nic nečistí.
func scrub(a: Vector2, b: Vector2, tool: ToolData, moisture: float, mult: float = 1.0, carry_chem: float = 0.0) -> float:
	last_absorbed = 0.0
	last_chem_seen = 0.0
	var seg := b - a
	var length := seg.length()
	if length < 0.0004:
		return 0.0
	var step := tool.radius * 0.3
	var n := int(ceil(length / step))
	var dl := length / n
	var removed := 0.0
	for s in range(1, n + 1):
		var c := a + seg * (float(s) / n)
		removed += _stamp(c, tool.radius, tool.strength * dl * mult, tool, moisture, carry_chem)
	current_total = maxf(0.0, current_total - removed)
	return removed


## Rotační hlava: čistí přímo pod nástrojem i bez pohybu (amount = virtuální dráha × síla).
func spin_scrub(c: Vector2, tool: ToolData, moisture: float, amount: float) -> float:
	last_absorbed = 0.0
	last_chem_seen = 0.0
	if amount <= 0.0:
		return 0.0
	var removed := _stamp(c, tool.radius, amount, tool, moisture, 0.0)
	current_total = maxf(0.0, current_total - removed)
	return removed


## Přitlačení bez pohybu: setře jen tenkou vrchní vrstvu přímo pod nástrojem.
func press(c: Vector2, tool: ToolData) -> float:
	if tool.initial_press <= 0.0 or tool.shape == "blade":
		return 0.0
	var removed := _stamp(c, tool.radius * 0.85, tool.initial_press, tool, 0.0, 0.0, false)
	current_total = maxf(0.0, current_total - removed)
	return removed


## Účinnost nástroje na pixelu podle typu špíny, vlhkosti a přípravku.
func _factor(k: int, wv: float, ci: int, tool: ToolData) -> float:
	var wet_gain: float = 1.0 + tool.wet_bonus * DirtTypes.WATER_GAIN[k] * (1.0 + boost[ci])
	var f := lerpf(DirtTypes.DRY[k] * DirtTypes.DRY_SCALE * tool.dry_mult, wet_gain, wv)
	var cg: float = DirtTypes.CHEM_GAIN[k]
	if cg > 0.0:
		f *= 1.0 + chem[ci] * smoothstep(0.0, 0.25, wv) * cg
	return f * tool.km(k)


func _tough_at(i: int) -> float:
	var t := tough[i]
	if kind[i] == DirtTypes.HEAVY:
		# Silná špína má vrstvy: tvrdá krusta navrchu, pod ní měkčí špína.
		t *= smoothstep(0.25, 0.7, dirt[i])
	return t


func _stamp(c: Vector2, r: float, amount: float, tool: ToolData, moisture: float, carry_chem: float, water: bool = true) -> float:
	var cx := c.x * PX_PER_M
	var cy := (size_m.y - c.y) * PX_PER_M
	var rp := r * PX_PER_M
	var rp2 := rp * rp
	var inv_r := 1.0 / rp
	var x0 := maxi(0, int(cx - rp))
	var x1 := mini(w - 1, int(cx + rp))
	var y0 := maxi(0, int(cy - rp))
	var y1 := mini(h - 1, int(cy + rp))
	var removed := 0.0
	var tp := tool.tough_penalty
	var film := moisture * 0.3
	var spreads := tool.spreads > 0.0
	var handles_water := water and tool.wet_bonus > 0.0
	for y in range(y0, y1 + 1):
		var dy := y + 0.5 - cy
		var row := y * w
		var wrow := (y / WET_DIV) * ww
		for x in range(x0, x1 + 1):
			var dx := x + 0.5 - cx
			var d2 := dx * dx + dy * dy
			if d2 > rp2:
				continue
			var fall := clampf((1.0 - sqrt(d2) * inv_r) * 2.2, 0.0, 1.0)
			var i := row + x
			var wi := wrow + x / WET_DIV
			var wv := wet[wi]
			var dv := dirt[i]
			if dv > 0.0:
				var rem := minf(dv, amount * fall * _factor(kind[i], wv, wi, tool) / (1.0 + _tough_at(i) * tp))
				dv -= rem
				dirt[i] = dv
				removed += rem
				bytes[i * 4] = int(dv * 255.0)
			if not handles_water:
				continue
			var nw := wv
			if spreads:
				# Houbička: z mokrého skla vodu nasaje, na suché ji roztírá
				# (a s ní i přípravek, který v sobě nese).
				var target := moisture * 0.85 * fall
				if wv < target - 0.02:
					nw = target
					last_absorbed -= (target - wv)
					if carry_chem > chem[wi]:
						chem[wi] = lerpf(chem[wi], carry_chem, fall)
					wet_active = true
				elif wv > target + 0.05:
					nw = move_toward(wv, target, amount * fall * 0.6)
					last_absorbed += wv - nw
				last_chem_seen = maxf(last_chem_seen, chem[wi] * smoothstep(0.0, 0.2, wv))
			else:
				# Hadr vodu stírá do tenkého filmu, suchý hadr ji vsákne,
				# vlhký hadr naopak nechává jemné mokré stopy.
				var target := film * fall
				if wv > target:
					nw = move_toward(wv, target, amount * fall * RAG_ABSORB)
					last_absorbed += wv - nw
				elif target > 0.02:
					nw = maxf(wv, target)
					wet_active = true
			if nw != wv:
				wet[wi] = nw
				wet_bytes[wi] = int(nw * 255.0)
				wet_changed = true
	if removed > 0.0:
		changed = true
	return removed


## Tah stěrkou: lišta šířky blade_width kolmá k ose `axis` se posune z a do b.
## Každý pixel, přes který lišta přejede, dostane úměrně dráze, kterou pod
## lištou strávil (hloubka styku blade_depth) – nezávisle na počtu snímků.
## Stěrka zároveň stírá vodu ze skla.
func scrub_blade(a: Vector2, b: Vector2, axis: Vector2, width: float, tool: ToolData, mult: float = 1.0) -> float:
	last_absorbed = 0.0
	last_chem_seen = 0.0
	var ax := axis.normalized()
	if ax.length_squared() < 0.5:
		return 0.0
	var nb := Vector2(-ax.y, ax.x)
	var x0 := a.dot(nb)
	var x1 := b.dot(nb)
	if absf(x1 - x0) < 0.0002:
		return 0.0
	var half := width * 0.5
	var dh := tool.blade_depth * 0.5
	var lo := minf(x0, x1)
	var hi := maxf(x0, x1)
	# obálka tahu v pixelech
	var pts := [a + ax * half, a - ax * half, b + ax * half, b - ax * half]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for q: Vector2 in pts:
		mn = mn.min(q)
		mx = mx.max(q)
	mn -= Vector2(dh, dh) + Vector2.ONE * 0.01
	mx += Vector2(dh, dh) + Vector2.ONE * 0.01
	var px0 := maxi(0, int(mn.x * PX_PER_M))
	var px1 := mini(w - 1, int(mx.x * PX_PER_M))
	var py0 := maxi(0, int((size_m.y - mx.y) * PX_PER_M))
	var py1 := mini(h - 1, int((size_m.y - mn.y) * PX_PER_M))
	var inv_dx := 1.0 / (x1 - x0)
	var tp := tool.tough_penalty
	var amount := tool.strength * mult
	var removed := 0.0
	var dries := tool.dries
	var dir := signf(x1 - x0)
	var behind := dh + 1.0 / PX_PER_M
	# Dvě fáze: nejdřív stírání špíny (s vodou, která je pod lištou), pak
	# vysušení skla ZA lištou – stěrka vodu tlačí před sebou, za ní je sucho.
	for phase in (2 if dries > 0.0 else 1):
		for y in range(py0, py1 + 1):
			var pv := size_m.y - (y + 0.5) / PX_PER_M
			var row := y * w
			var wrow := (y / WET_DIV) * ww
			for x in range(px0, px1 + 1):
				var pu := (x + 0.5) / PX_PER_M
				var p := Vector2(pu, pv)
				var pn := p.dot(nb)
				var overlap := minf(hi, pn + dh) - maxf(lo, pn - dh)
				if overlap <= 0.0:
					continue
				var s := clampf((pn - x0) * inv_dx, 0.0, 1.0)
				var t := (p - a.lerp(b, s)).dot(ax)
				var at := absf(t)
				if at > half:
					continue
				var fall := clampf((half - at) / 0.012, 0.0, 1.0)
				var i := row + x
				var wi := wrow + x / WET_DIV
				var wv := wet[wi]
				if phase == 0:
					var dv := dirt[i]
					if dv > 0.0:
						var rem := minf(dv, amount * overlap * fall * _factor(kind[i], wv, wi, tool) / (1.0 + _tough_at(i) * tp))
						dv -= rem
						dirt[i] = dv
						removed += rem
						bytes[i * 4] = int(dv * 255.0)
				elif wv > 0.0 and (x1 - pn) * dir >= behind:
					var nw := move_toward(wv, 0.0, dries * fall)
					last_absorbed += wv - nw
					wet[wi] = nw
					wet_bytes[wi] = int(nw * 255.0)
					if nw <= 0.01:
						chem[wi] = 0.0
						boost[wi] = 0.0
					wet_changed = true
	if removed > 0.0:
		changed = true
	current_total = maxf(0.0, current_total - removed)
	return removed


## Průměrná špína v okolí bodu (pro zvuk „čistého skla").
func dirt_at(c: Vector2) -> float:
	return dirt[_idx(c)]


func kind_at(c: Vector2) -> int:
	return kind[_idx(c)]


func wet_at(c: Vector2) -> float:
	return wet[_widx(c)]


func chem_at(c: Vector2) -> float:
	return chem[_widx(c)]


func _idx(c: Vector2) -> int:
	var x := clampi(int(c.x * PX_PER_M), 0, w - 1)
	var y := clampi(int((size_m.y - c.y) * PX_PER_M), 0, h - 1)
	return y * w + x


func _widx(c: Vector2) -> int:
	var x := clampi(int(c.x * PX_PER_M / WET_DIV), 0, ww - 1)
	var y := clampi(int((size_m.y - c.y) * PX_PER_M / WET_DIV), 0, wh - 1)
	return y * ww + x


# ------------------------------------------------------------------ voda

## Nástřik přípravku: mlha drobných kapiček + několik stékajících kapek.
## grease_power = odmašťovací síla, dissolve = jak silně povoluje běžnou špínu.
func spray(c: Vector2, radius: float, grease_power: float = 0.3, dissolve: float = 1.0, evaporation: float = 1.0) -> void:
	var cx := c.x * PX_PER_M / WET_DIV
	var cy := (size_m.y - c.y) * PX_PER_M / WET_DIV
	var rp := radius * PX_PER_M / WET_DIV
	var bst := maxf(0.0, dissolve - 1.0)
	for y in range(maxi(0, int(cy - rp)), mini(wh - 1, int(cy + rp)) + 1):
		for x in range(maxi(0, int(cx - rp)), mini(ww - 1, int(cx + rp)) + 1):
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cy
			var t := sqrt(dx * dx + dy * dy) / rp
			if t > 1.0:
				continue
			var i := y * ww + x
			var v := maxf(wet[i], (1.0 - t * t) * _rng.randf_range(0.65, 1.0))
			wet[i] = v
			wet_bytes[i] = int(v * 255.0)
			chem[i] = maxf(chem[i], grease_power)
			boost[i] = maxf(boost[i], bst)
	for k in 70:
		var ang := _rng.randf() * TAU
		var dist := sqrt(_rng.randf()) * radius * 1.25
		var p := c + Vector2(cos(ang), sin(ang)) * dist
		_set_wet(p, 1.0)
	for k in _rng.randi_range(3, 5):
		var p := c + Vector2(_rng.randf_range(-0.8, 0.8) * radius, _rng.randf_range(-0.6, 0.3) * radius)
		drips.append({"p": p, "speed": _rng.randf_range(0.05, 0.11), "life": _rng.randf_range(1.6, 3.6), "phase": _rng.randf() * TAU})
	evap_mult = evaporation
	wet_active = true
	wet_changed = true


func _set_wet(p: Vector2, v: float) -> void:
	var x := int(p.x * PX_PER_M / WET_DIV)
	var y := int((size_m.y - p.y) * PX_PER_M / WET_DIV)
	if x < 0 or y < 0 or x >= ww or y >= wh:
		return
	var i := y * ww + x
	if v > wet[i]:
		wet[i] = v
		wet_bytes[i] = int(v * 255.0)


## Stékající kapky: smáčí sklo a za sebou vyrývají tenkou čistší stopu.
func update_drips(delta: float) -> void:
	if drips.is_empty():
		return
	var removed := 0.0
	for i in range(drips.size() - 1, -1, -1):
		var d: Dictionary = drips[i]
		var p: Vector2 = d["p"]
		var old_p := p
		d["phase"] = float(d["phase"]) + delta * 3.0
		p.y -= float(d["speed"]) * delta
		p.x += sin(float(d["phase"])) * 0.004 * delta
		d["speed"] = maxf(0.02, float(d["speed"]) * (1.0 - 0.25 * delta))
		d["life"] = float(d["life"]) - delta
		d["p"] = p
		var steps := maxi(1, int((old_p - p).length() * PX_PER_M))
		for s in steps:
			var q := old_p.lerp(p, float(s + 1) / steps)
			_set_wet(q, 0.9)
			var x := int(q.x * PX_PER_M)
			var y := int((size_m.y - q.y) * PX_PER_M)
			if x >= 0 and y >= 0 and x < w and y < h:
				var idx := y * w + x
				if kind[idx] == DirtTypes.GREASE:
					continue
				var rem := minf(dirt[idx], 0.22 / (1.0 + tough[idx] * 4.0))
				dirt[idx] -= rem
				bytes[idx * 4] = int(dirt[idx] * 255.0)
				removed += rem
		if float(d["life"]) <= 0.0 or p.y < 0.01:
			drips.remove_at(i)
	current_total = maxf(0.0, current_total - removed)
	changed = true
	wet_changed = true


func update_wet(dt: float) -> void:
	if not wet_active:
		return
	var evap := dt * WET_EVAPORATION * evap_mult
	var any := false
	for i in wet.size():
		var v := wet[i]
		if v > 0.0:
			v = maxf(0.0, v - evap)
			wet[i] = v
			wet_bytes[i] = int(v * 255.0)
			if v <= 0.0:
				chem[i] = 0.0
				boost[i] = 0.0
			any = true
	wet_active = any or not drips.is_empty()
	wet_changed = true


func flush() -> void:
	if changed and image:
		image.set_data(w, h, false, Image.FORMAT_RGBA8, bytes)
		texture.update(image)
		changed = false
	if wet_changed and wet_image:
		wet_image.set_data(ww, wh, false, Image.FORMAT_L8, wet_bytes)
		wet_texture.update(wet_image)
		wet_changed = false


func clear_all() -> void:
	dirt.fill(0.0)
	for i in dirt.size():
		bytes[i * 4] = 0
	current_total = 0.0
	drips.clear()
	changed = true


# ------------------------------------------------------------------ ukládání

func to_save() -> Dictionary:
	var q := PackedByteArray()
	q.resize(w * h)
	for i in w * h:
		q[i] = bytes[i * 4]
	var packed := q.compress(FileAccess.COMPRESSION_DEFLATE)
	var d := {"w": w, "h": h, "len": q.size(), "data": Marshalls.raw_to_base64(packed)}
	if not extras.is_empty():
		d["extras"] = extras.duplicate(true)
	return d


func apply_save(d: Dictionary) -> void:
	var sw := int(d.get("w", 0))
	var sh := int(d.get("h", 0))
	var raw := Marshalls.base64_to_raw(str(d.get("data", ""))).decompress(int(d.get("len", 0)), FileAccess.COMPRESSION_DEFLATE)
	if sw <= 0 or sh <= 0 or raw.size() != sw * sh:
		push_warning("DirtMask: poškozená data masky, ponechávám výchozí stav.")
		return
	# nejdřív vrátit ptačí fleky přidané během hry, pak teprve uplatnit, co už je umyté
	var ex: Array = d.get("extras", [])
	if not ex.is_empty():
		for e in ex:
			if e is Array and e.size() >= 4:
				extras.append(e)
				_apply_extra(e)
		initial_total = maxf(initial_total, _sum())
		for i in dirt.size():
			bytes[i * 4] = int(dirt[i] * 255.0)
			bytes[i * 4 + 1] = int(tough[i] * 255.0)
			bytes[i * 4 + 2] = kind[i] * KIND_STEP
	for y in h:
		var sy := mini(sh - 1, int(float(y) / h * sh))
		for x in w:
			var sx := mini(sw - 1, int(float(x) / w * sw))
			var v := raw[sy * sw + sx]
			var i := y * w + x
			# Nezměněné pixely si nechají přesnou vygenerovanou hodnotu.
			if v < bytes[i * 4]:
				dirt[i] = v / 255.0
			bytes[i * 4] = int(dirt[i] * 255.0)
	current_total = _sum()
	changed = true

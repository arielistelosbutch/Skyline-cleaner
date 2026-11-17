extends SceneTree
## Srovnání nástrojů: kolik sekund trvá umýt typické okno 1,0 × 1,2 m na 90 %.
## Spuštění: godot --headless --path . --script res://scripts/tests/tool_bench.gd

const SIZE := Vector2(1.0, 1.2)
const DT := 1.0 / 30.0
const LIMIT := 240.0
const PROFILES := ["venkov_bezne", "chata_blato", "kuchyn_mastnota", "chlev_silna", "mesto_smog", "fasada_vyska"]
const TOOLS := ["rag_old", "rag_micro", "sponge", "squeegee_25", "squeegee_35", "tele_mop", "tele_squeegee", "fold_mop", "brush_electric", "washer_electric", "brush_tele"]


func _init() -> void:
	var spray := load("res://data/tools/detergent_basic.tres") as ToolData
	var deg := load("res://data/tools/degreaser.tres") as ToolData
	var line := "%-16s" % "nastroj"
	for p in PROFILES:
		line += "%14s" % p.substr(0, 13)
	print(line)
	var only := OS.get_environment("BENCH_TOOLS")
	for id in (only.split(",") if only != "" else TOOLS):
		var t := load("res://data/tools/%s.tres" % id) as ToolData
		for speed in ([0.25, 0.6] if t.spin > 0.0 else [0.6]):
			line = "%-16s" % ("%s@%.2f" % [id, speed])
			for p in PROFILES:
				var chem := deg if p == "kuchyn_mastnota" else spray
				line += "%14s" % _fmt(_run(t, chem, p, speed))
			print(line)
	quit()


func _fmt(v: float) -> String:
	return ">%d" % int(LIMIT) if v >= LIMIT else "%.0f s" % v


func _run(t: ToolData, chem: ToolData, pid: String, speed: float) -> float:
	var m := DirtMask.new(SIZE)
	m.generate(1234, 1.0, DirtProfile.get_profile(pid), false)
	var blade := t.shape == "blade"
	var width := t.blade_width * 0.85 if blade else t.radius * 1.4
	var time := 0.0
	var mult := 1.0
	var fold_pen := 1.0
	if t.fold:
		fold_pen = 1.0  # v ruce
	while time < LIMIT:
		# hadí dráha shora dolů, pruhy rovnoměrně přes celou výšku
		var lanes := int(ceil(SIZE.y / width))
		var dir := 1.0
		for li in lanes:
			var lane := SIZE.y - (li + 0.5) * SIZE.y / lanes
			var a := Vector2(0.02 if dir > 0.0 else SIZE.x - 0.02, lane)
			var b := Vector2(SIZE.x - 0.02 if dir > 0.0 else 0.02, lane)
			# nastříkat pruh těsně před tahem (hráč ~ 0,25 s na nástřik)
			var sx := 0.12
			while sx < SIZE.x:
				for oy in ([-0.08, 0.08] if width > 0.2 else [0.0]):
					m.spray(Vector2(sx, lane + oy), chem.spray_radius, chem.grease_power, chem.dissolve, chem.evaporation)
					time += 0.25
				sx += 0.25
			var steps := int(ceil(a.distance_to(b) / (speed * DT)))
			var prev := a
			for s in range(1, steps + 1):
				var c := a.lerp(b, float(s) / steps)
				if blade:
					m.scrub_blade(prev, c, Vector2(0, 1), t.blade_width, t, mult)
				else:
					m.scrub(prev, c, t, 0.3, mult * fold_pen)
				if t.spin > 0.0:
					m.spin_scrub(c, t, 0.3, t.strength * t.spin * DT * mult)
				prev = c
				time += DT
				m.update_wet(DT)
			dir = -dir
			if m.cleanliness() >= 0.9:
				return time
		if m.cleanliness() >= 0.9:
			return time
	return LIMIT

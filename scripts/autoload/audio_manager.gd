extends Node
## Zvukový systém. Dokud nejsou k dispozici vlastní zvukové assety, všechny
## zvuky se syntetizují při startu (šum, tóny) – žádné cizí chráněné nahrávky.
## Vlastní nahrávku lze kdykoli dosadit: Audio.streams["rub"] = load("res://...").

const RATE := 22050

var streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _loops := {}
var _loop_level := {}
var _bird_timer := 4.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	streams["rub"] = _noise_loop(1.6, 0.18, 0.55, 7.0)
	streams["squeak"] = _squeak_loop()
	streams["wind"] = _noise_loop(4.0, 0.02, 0.5, 0.35)
	streams["step"] = _burst(0.11, 0.08, 18.0, 0.9)
	streams["spray"] = _burst(0.32, 0.65, 9.0, 0.7)
	streams["water"] = _burst(0.9, 0.25, 2.5, 0.55)
	streams["cloth"] = _burst(0.18, 0.3, 14.0, 0.5)
	streams["click"] = _tone_seq([[1320.0, 0.0, 0.05]], 0.35)
	streams["pickup"] = _tone_seq([[392.0, 0.0, 0.12], [523.0, 0.06, 0.14]], 0.3)
	streams["complete"] = _tone_seq([[784.0, 0.0, 1.1], [987.8, 0.09, 1.0], [1318.5, 0.18, 1.2]], 0.32)
	streams["coins"] = _tone_seq([[1046.5, 0.0, 0.5], [1568.0, 0.08, 0.7], [2093.0, 0.16, 0.6]], 0.3)
	streams["levelup"] = _tone_seq([[523.3, 0.0, 0.6], [659.3, 0.12, 0.6], [784.0, 0.24, 0.7], [1046.5, 0.36, 1.2]], 0.3)
	streams["bird"] = _bird()
	streams["rain"] = _noise_loop(3.0, 0.45, 0.35, 0.5)
	streams["thunder"] = _burst(2.4, 0.025, 1.4, 1.0)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for loop_name in ["rub", "squeak", "wind", "rain"]:
		var lp := AudioStreamPlayer.new()
		lp.stream = streams[loop_name]
		lp.volume_db = -80.0
		add_child(lp)
		_loops[loop_name] = lp
		_loop_level[loop_name] = 0.0


func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s: AudioStream = streams.get(sound)
	if s == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


## Plynulé řízení smyčky (tření hadru, vrzání čistého skla, vítr).
func set_loop(loop_name: String, intensity: float, pitch: float = 1.0) -> void:
	var lp: AudioStreamPlayer = _loops.get(loop_name)
	if lp == null:
		return
	_loop_level[loop_name] = clampf(intensity, 0.0, 1.0)
	lp.pitch_scale = clampf(pitch, 0.5, 2.0)


func _process(delta: float) -> void:
	for loop_name in _loops:
		var lp: AudioStreamPlayer = _loops[loop_name]
		var target: float = _loop_level[loop_name]
		var cur := db_to_linear(lp.volume_db) if lp.volume_db > -79.0 else 0.0
		cur = lerpf(cur, target, 1.0 - exp(-14.0 * delta))
		if cur < 0.003:
			if lp.playing:
				lp.stop()
			lp.volume_db = -80.0
		else:
			lp.volume_db = linear_to_db(cur)
			if not lp.playing:
				lp.play()
	# Ptáci na venkově – občas zacvrlikají.
	if float(_loop_level.get("wind", 0.0)) > 0.0:
		_bird_timer -= delta
		if _bird_timer <= 0.0:
			_bird_timer = _rng.randf_range(3.0, 9.0)
			play("bird", _rng.randf_range(-20.0, -13.0), _rng.randf_range(0.85, 1.25))


# ------------------------------------------------------------------ syntéza

func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## Filtrovaný šum s pomalou modulací (smyčka). cutoff 0..1 = jednopólový filtr.
func _noise_loop(seconds: float, cutoff: float, amp: float, mod_hz: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var white := _rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * cutoff
		lp2 += (lp - lp2) * cutoff
		var t := float(i) / RATE
		# modulace s celým počtem period v délce smyčky → bez cvaknutí
		var cycles := maxf(1.0, round(mod_hz * seconds))
		var m := 0.75 + 0.25 * sin(TAU * cycles * t / seconds)
		s[i] = (lp2 * 3.0 + (lp - lp2) * 1.5) * amp * m
	# prolnutí konce se začátkem
	var fade := int(0.05 * RATE)
	for i in fade:
		var k := float(i) / fade
		s[n - fade + i] = s[n - fade + i] * (1.0 - k) + s[i] * k
	return _wav(s, true)


func _squeak_loop() -> AudioStreamWAV:
	var seconds := 0.6
	var n := int(seconds * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 1250.0 + 140.0 * sin(TAU * 5.0 * t / seconds) + 40.0 * sin(TAU * 35.0 * t)
		phase += TAU * f / RATE
		var env := 0.6 + 0.4 * sin(TAU * 10.0 * t / seconds)
		s[i] = (sin(phase) * 0.6 + sin(phase * 2.0) * 0.25) * 0.22 * env
	return _wav(s, true)


## Krátký šumový zvuk s exponenciálním doznějem (kroky, sprej, voda).
func _burst(seconds: float, cutoff: float, decay: float, amp: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * cutoff
		var attack := clampf(t / 0.008, 0.0, 1.0)
		s[i] = lp * exp(-t * decay) * attack * amp * 2.0
	return _wav(s, false)


## Sekvence tónů [frekvence, začátek, délka] – zvonkohra, mince, level up.
func _tone_seq(notes: Array, amp: float) -> AudioStreamWAV:
	var total := 0.0
	for nt in notes:
		total = maxf(total, float(nt[1]) + float(nt[2]))
	var n := int((total + 0.05) * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	s.fill(0.0)
	for nt in notes:
		var f := float(nt[0])
		var start := int(float(nt[1]) * RATE)
		var length := int(float(nt[2]) * RATE)
		for i in length:
			var idx := start + i
			if idx >= n:
				break
			var t := float(i) / RATE
			var env := clampf(t / 0.006, 0.0, 1.0) * exp(-t * 4.5 / float(nt[2]))
			s[idx] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t) + 0.12 * sin(TAU * f * 3.01 * t)) * env * amp
	return _wav(s, false)


func _bird() -> AudioStreamWAV:
	var seconds := 0.5
	var n := int(seconds * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	s.fill(0.0)
	var phase := 0.0
	for chirp in 3:
		var start := int((chirp * 0.14) * RATE)
		var length := int(0.075 * RATE)
		for i in length:
			var t := float(i) / length
			var f := lerpf(2900.0, 4300.0, t) + 250.0 * sin(t * 18.0)
			phase += TAU * f / RATE
			var env := sin(PI * t)
			if start + i < n:
				s[start + i] = sin(phase) * env * 0.35
	return _wav(s, false)

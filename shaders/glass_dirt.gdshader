shader_type spatial;
// Sklo okna s vrstvou špíny řízenou maskou (DirtMask).
// R masky = množství špíny, G = odolnost (kapky / ptačí trus), B = typ nečistoty
// (0 prach, 1 kapky, 2 bláto, 3 trus, 4 mastnota, 5 pyl, 6 silná špína), wet_tex = vlhkost.
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform sampler2D dirt_tex : filter_linear, repeat_disable;
uniform sampler2D wet_tex : filter_linear, repeat_disable;
uniform bool use_mask = false;
uniform float proc_level = 1.0;
uniform vec2 glass_size = vec2(1.0, 1.0);
uniform float fade = 0.0;
uniform float glint = -1.0;
uniform float seed = 0.0;
uniform vec3 glass_tint : source_color = vec3(0.55, 0.72, 0.78);
uniform vec3 dust_color : source_color = vec3(0.66, 0.6, 0.5);
uniform vec3 grime_color : source_color = vec3(0.47, 0.41, 0.32);
uniform vec3 bird_color : source_color = vec3(0.88, 0.87, 0.82);
uniform vec3 mud_color : source_color = vec3(0.45, 0.33, 0.2);
uniform vec3 grease_color : source_color = vec3(0.78, 0.7, 0.48);
uniform vec3 pollen_color : source_color = vec3(0.95, 0.8, 0.26);
uniform vec3 heavy_color : source_color = vec3(0.32, 0.28, 0.22);
// Zrcadlové (reflexní) sklo mrakodrapů: 0 = běžné průhledné sklo, 1 = zrcadlo.
uniform float mirror = 0.0;
uniform vec3 mirror_tint : source_color = vec3(0.45, 0.6, 0.7);
// Počasí a denní doba (Atmosphere / Weather): rozsvícená okna v noci,
// kapky deště stékající po skle, námraza po okrajích v zimě.
global uniform float night_amount;
global uniform float rain_glass;
global uniform float frost_glass;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}

// Útlum jemných vzorů podle velikosti pixelu: když na jeden pixel připadne víc
// period šumu, vzor by při pohybu kamery blikal (aliasing) – místo toho zešedne.
float aa_keep(vec2 p, float freq) {
	vec2 fw = fwidth(p) * freq;
	return 1.0 - smoothstep(0.35, 0.9, max(fw.x, fw.y));
}

// x = vzdálenost k nejbližšímu bodu buňky, y = náhodná hodnota buňky
vec2 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 31.7));
			float d = length(g + o - f);
			if (d < best) {
				best = d;
				id = hash(i + g + 7.3);
			}
		}
	}
	return vec2(best, id);
}

vec4 sample_bilinear(sampler2D tex, vec2 uv) {
	ivec2 ts = textureSize(tex, 0);
	vec2 p = uv * vec2(ts) - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	ivec2 mx = ts - ivec2(1);
	vec4 a = texelFetch(tex, clamp(i, ivec2(0), mx), 0);
	vec4 b = texelFetch(tex, clamp(i + ivec2(1, 0), ivec2(0), mx), 0);
	vec4 c = texelFetch(tex, clamp(i + ivec2(0, 1), ivec2(0), mx), 0);
	vec4 d = texelFetch(tex, clamp(i + ivec2(1, 1), ivec2(0), mx), 0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Bilineárně vážené zastoupení zvláštních typů (bláto, mastnota, pyl, silná špína).
// Typ se neinterpoluje přímo – každý ze 4 sousedních texelů přispěje svou vahou.
vec4 kind_weights(sampler2D tex, vec2 uv) {
	ivec2 ts = textureSize(tex, 0);
	vec2 p = uv * vec2(ts) - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	ivec2 mx = ts - ivec2(1);
	vec4 acc = vec4(0.0);
	float total = 0.0001;
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k % 2, k / 2);
		vec4 t = texelFetch(tex, clamp(i + o, ivec2(0), mx), 0);
		float bw = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
		float wgt = bw * (t.r + 0.002);
		int kind = int(round(t.b * 255.0 / 36.0));
		if (kind == 2) acc.x += wgt;
		else if (kind == 4) acc.y += wgt;
		else if (kind == 5) acc.z += wgt;
		else if (kind == 6) acc.w += wgt;
		total += wgt;
	}
	return acc / total;
}

// Stékající dešťové kapky: řídké kapky na skle a občas jedna rychle sjede dolů.
float rain_drops(vec2 p, float t) {
	vec2 sc = p * vec2(9.0, 4.0);
	float col = floor(sc.x);
	float h = hash(vec2(col, 3.1));
	// sjíždějící kapka s krátkou stopou (UV.y roste směrem dolů, kapka tedy
	// sjíždí, když y v čase klesá – stopa zůstává nad hlavou kapky)
	float y = fract(sc.y * 0.25 - t * (0.06 + h * 0.1) + h * 7.0);
	float xd = abs(fract(sc.x) - 0.5 - sin(sc.y * 2.0 + h * 6.0) * 0.08);
	float head = (1.0 - smoothstep(0.05, 0.12, xd)) * smoothstep(0.9, 0.97, y) * step(0.45, h);
	float trail = (1.0 - smoothstep(0.02, 0.05, xd)) * smoothstep(0.55, 0.95, y) * step(0.45, h) * 0.5;
	// drobné stojící kapičky
	vec2 cv = cells(p * 28.0);
	float dot_d = (1.0 - smoothstep(0.06, 0.16, cv.x)) * step(0.55, cv.y);
	return clamp(head + trail + dot_d, 0.0, 1.0);
}

void fragment() {
	vec2 wp = UV * glass_size + vec2(seed);
	float dirt;
	float tough = 0.0;
	float wet = 0.0;
	vec4 kw = vec4(0.0);
	if (use_mask) {
		// Ruční bilineární filtrování – stejně hladké ve Forward+ i Compatibility.
		vec2 m = sample_bilinear(dirt_tex, UV).rg;
		dirt = m.r;
		tough = m.g;
		wet = sample_bilinear(wet_tex, UV).r;
		kw = kind_weights(dirt_tex, UV);
	} else {
		// Levná náhrada pro neaktivní (vzdálená) okna – žádná textura.
		dirt = clamp((0.6 + 0.5 * (fbm(wp * 2.4) - 0.5) + 0.2 * UV.y) * proc_level, 0.0, 1.0);
	}
	dirt *= (1.0 - fade);

	float n = fbm(wp * 9.0);
	float fine = mix(0.5, vnoise(wp * 90.0), aa_keep(wp, 90.0));
	float cover = smoothstep(0.02, 0.55, dirt);
	float a_dust = cover * mix(0.74, 0.97, n) * mix(0.93, 1.04, fine);
	vec3 dcol = mix(dust_color, grime_color, smoothstep(0.35, 0.8, n));

	float bird = smoothstep(0.7, 0.86, tough);
	float drop = smoothstep(0.2, 0.42, tough) * (1.0 - bird);
	dcol = mix(dcol, grime_color * 0.85, drop * 0.6);
	dcol = mix(dcol, bird_color * mix(0.85, 1.0, n), bird);
	a_dust = clamp(a_dust + (drop * 0.22 + bird * 0.65) * cover, 0.0, 0.96);

	// Zvláštní typy nečistot Etapy 2.
	float special = clamp(kw.x + kw.y + kw.z + kw.w, 0.0, 1.0);
	if (special > 0.001) {
		float clump = vnoise(wp * 34.0);
		vec3 c_mud = mud_color * mix(0.72, 1.12, clump) * mix(0.9, 1.05, fine);
		float a_mud = cover * mix(0.9, 0.99, clump);
		// mastnota: průsvitný nažloutlý film s jemnou duhovou kresbou
		float irid = sin(wp.x * 37.0 + wp.y * 23.0 + n * 9.0);
		vec3 c_grease = grease_color + vec3(0.06, -0.02, 0.07) * irid;
		float a_grease = cover * mix(0.38, 0.55, n);
		// pyl: žlutá zrnka a jemný prášek
		float grain = mix(0.4, step(0.6, vnoise(wp * 160.0)), aa_keep(wp, 160.0));
		vec3 c_pollen = pollen_color * mix(0.85, 1.08, grain) * mix(0.92, 1.04, fine);
		float a_pollen = cover * mix(0.62, 0.9, grain);
		// silná špína: tmavá popraskaná krusta
		vec2 cr = cells(wp * 22.0);
		float crack = smoothstep(0.04, 0.12, cr.x);
		vec3 c_heavy = mix(heavy_color * 0.6, heavy_color * mix(0.85, 1.15, cr.y), crack);
		float a_heavy = cover * 0.985;
		vec3 sc = (c_mud * kw.x + c_grease * kw.y + c_pollen * kw.z + c_heavy * kw.w) / max(special, 0.0001);
		float sa = (a_mud * kw.x + a_grease * kw.y + a_pollen * kw.z + a_heavy * kw.w) / max(special, 0.0001);
		dcol = mix(dcol, sc, special);
		a_dust = mix(a_dust, sa, special);
	}

	// Mokrá špína je výrazně tmavší a trochu průsvitnější – nástřik je dobře vidět.
	float wet_v = smoothstep(0.03, 0.5, wet);
	dcol *= mix(1.0, 0.55, wet_v);
	a_dust *= mix(1.0, 0.85, wet_v);
	// okraj mokré plochy (stékající lem saponátu)
	float wet_edge = clamp(fwidth(wet) * 14.0, 0.0, 1.0) * step(0.02, wet);

	float ndv = abs(dot(NORMAL, VIEW));
	float fres = pow(1.0 - clamp(ndv, 0.0, 1.0), 4.0);
	float clean = 1.0 - a_dust;

	// Jemné diagonální odlesky na čistém skle.
	float diag = UV.x * 0.7 + (1.0 - UV.y) * 0.5;
	float sheen = exp(-pow((diag - 0.42) * 7.0, 2.0)) * 0.6 + exp(-pow((diag - 0.62) * 18.0, 2.0)) * 0.35;

	// Kapičky vody na mokrých místech.
	vec2 cv = cells(wp * 60.0);
	float droplet = (1.0 - smoothstep(0.08, 0.3, cv.x)) * step(0.5, cv.y) * smoothstep(0.2, 0.65, wet) * aa_keep(wp, 60.0);

	// déšť na skle (venku), drobné kapky i po osychání
	float rain = rain_glass > 0.01 ? rain_drops(wp, TIME) * rain_glass * aa_keep(wp, 28.0) : 0.0;
	droplet = max(droplet, rain);
	// námraza po okrajích skla
	vec2 ed = min(UV, 1.0 - UV) * glass_size;
	float edge_d = min(ed.x, ed.y);
	float frost = frost_glass * (1.0 - smoothstep(0.02, 0.09 + fbm(wp * 14.0) * 0.12, edge_d)) * mix(0.8, mix(0.6, 1.0, vnoise(wp * 120.0)), aa_keep(wp, 120.0));

	vec3 glass_col = mix(glass_tint * 0.32, mirror_tint * 0.75, mirror);
	ALBEDO = mix(glass_col, dcol, a_dust) + vec3(0.22, 0.32, 0.38) * wet_v * 0.45 * clean + vec3(0.5, 0.6, 0.65) * wet_edge * 0.35;
	ALBEDO = mix(ALBEDO, vec3(0.88, 0.93, 0.98), frost * 0.85);
	// čisté sklo víc odráží oblohu (silnější Fresnel)
	float clear_a = mix(0.12 + fres * 0.75, 0.9 + fres * 0.1, mirror);
	ALPHA = clamp(mix(clear_a, 1.0, a_dust) + wet_v * 0.2 + wet_edge * 0.2 + droplet * 0.25 + frost * 0.7, 0.0, 1.0);
	ROUGHNESS = mix(mix(0.03, 0.88, a_dust), 0.22, kw.y * cover) * mix(1.0, 0.4, wet);
	SPECULAR = mix(0.85, 0.3, a_dust);
	// čisté zrcadlové sklo odráží nebe a okolní budovy, špína odlesk tlumí
	METALLIC = max(mirror * 0.92, 0.18) * clean;

	vec3 em = vec3(0.92, 0.97, 1.0) * sheen * clean * 0.07 + vec3(1.0) * droplet * 0.22 + vec3(0.75, 0.9, 1.0) * (wet_v * 0.05 + wet_edge * 0.1);
	if (glint > -0.5) {
		float g = exp(-pow((diag - (glint * 1.7 - 0.35)) * 7.0, 2.0));
		em += vec3(1.0, 0.98, 0.9) * g * 0.85;
	}
	// v noci se v části oken svítí (teplé světlo zevnitř), špína ho tlumí
	if (night_amount > 0.01) {
		float lit = step(0.42, hash(NODE_POSITION_WORLD.xz * 0.37 + NODE_POSITION_WORLD.y));
		vec3 warm = mix(vec3(1.0, 0.72, 0.4), vec3(1.0, 0.85, 0.62), hash(NODE_POSITION_WORLD.zx));
		em += warm * lit * night_amount * 0.9 * (1.0 - a_dust * 0.45) * (1.0 - mirror * 0.4);
	}
	EMISSION = em;
}

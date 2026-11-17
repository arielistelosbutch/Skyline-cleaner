shader_type spatial;
// Pomalu plující mraky na kopuli kolem kamery. Obloha samotná je statická
// (ProceduralSkyMaterial), takže se nemusí každý snímek přepočítávat odrazy.
// Dvě vrstvy: kupovité mraky s osvětlením od slunce (světlé okraje na straně
// slunce, tmavší spodek a hustá místa) a vysoké jemné řasy.
// coverage = jak velká část oblohy je zatažená (0 jasno … 1 zataženo, bouřka).
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform float speed = 0.004;
uniform float coverage = 0.45;
uniform vec3 tint : source_color = vec3(1.0);
// směr ke slunci (nastavuje Atmosphere)
uniform vec3 sun_dir = vec3(0.3, 0.6, 0.4);

varying vec3 dir;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int k = 0; k < 5; k++) { s += a * vnoise(p); p = p * 2.03 + 3.1; a *= 0.5; }
	return s;
}

// hustota kupovitých mraků v bodě roviny mraků
float cumulus(vec2 p, vec2 wind) {
	vec2 q = p + wind;
	// zvlnění souřadnic → nadýchané, nepravidelné tvary místo kulatých skvrn
	vec2 warp = vec2(vnoise(q * 0.7 + 1.7), vnoise(q * 0.7 + 8.3)) - 0.5;
	float base = fbm(q + warp * 0.9);
	float puff = fbm(q * 2.6 - wind * 0.6 + warp * 0.4);
	float th = mix(0.72, 0.3, clamp(coverage, 0.0, 1.0));
	return smoothstep(th, th + 0.2, base * 0.82 + puff * 0.26);
}

void vertex() {
	dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(dir);
	if (d.y < 0.01) { discard; }
	vec2 p = d.xz / (d.y + 0.12) * 1.5;
	vec2 wind = vec2(TIME * speed, TIME * speed * 0.4);
	float dens = cumulus(p, wind);
	// osvětlení: kolik mraku leží mezi bodem a sluncem
	vec3 sd = normalize(sun_dir);
	vec2 s2 = normalize(sd.xz + vec2(0.0001)) * 0.16;
	float toward = cumulus(p + s2, wind);
	float toward2 = cumulus(p + s2 * 2.2, wind);
	float shade = clamp(1.0 - (toward * 0.55 + toward2 * 0.35) + (1.0 - dens) * 0.25, 0.0, 1.0);
	float sun_up = clamp(sd.y * 2.0, 0.0, 1.0);
	vec3 lit = vec3(1.0, 0.99, 0.96);
	vec3 shadow = mix(vec3(0.56, 0.6, 0.7), vec3(0.66, 0.69, 0.76), sun_up);
	vec3 col = mix(shadow, lit, shade);
	// stříbrné okraje mraků blízko slunce
	float near_sun = pow(max(dot(d, sd), 0.0), 6.0);
	col += vec3(1.0, 0.95, 0.85) * near_sun * (1.0 - dens) * 0.6;
	// hustá zatažená obloha a bouřka jsou šedší a tmavší
	float storm = smoothstep(0.6, 0.9, coverage);
	col *= mix(1.0, 0.58, storm * dens);
	// vysoké řasy (natažený šum), jen když není zataženo
	vec2 cp = p * vec2(0.45, 2.2) + wind * 1.6;
	float cirrus = smoothstep(0.55, 0.85, fbm(cp + vec2(fbm(p * 0.8), 0.0))) * 0.35 * (1.0 - storm);
	float a = max(dens * 0.95, cirrus * (1.0 - dens));
	col = mix(vec3(0.97, 0.98, 1.0), col, clamp(dens * 1.6, 0.0, 1.0));
	// u obzoru mraky slábnou do oparu
	a *= smoothstep(0.01, 0.2, d.y);
	ALBEDO = col * tint;
	ALPHA = a;
}

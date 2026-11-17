shader_type spatial;
// Travnatá plocha s barevnými odchylkami podle světové pozice (bez textur).
// Roční období (globální parametry z Atmosphere): podzim hnědne, v zimě sníh.

global uniform float season_spring;
global uniform float season_autumn;
global uniform float season_winter;

uniform vec3 grass_a : source_color = vec3(0.42, 0.64, 0.30);
uniform vec3 grass_b : source_color = vec3(0.35, 0.57, 0.27);
uniform vec3 grass_dry : source_color = vec3(0.62, 0.66, 0.36);
// díra pro zapuštěný rybník (poloosy 0 = žádná)
uniform vec2 pond_center = vec2(0.0);
uniform vec2 pond_radii = vec2(0.0);

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int k = 0; k < 4; k++) { s += a * vnoise(p); p = p * 2.1 + 5.3; a *= 0.5; }
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (pond_radii.x > 0.0) {
		vec2 q = (wpos.xz - pond_center) / pond_radii;
		if (dot(q, q) < 1.0) { discard; }
	}
	float n = fbm(wpos.xz * 0.06);
	float n2 = vnoise(wpos.xz * 1.3);
	float n3 = vnoise(wpos.xz * 6.0);
	float dry = smoothstep(0.55, 0.8, fbm(wpos.xz * 0.018 + 7.0));
	vec3 col = mix(grass_a, grass_b, smoothstep(0.35, 0.65, n));
	col = mix(col, grass_dry, dry * 0.55);
	// světlejší vrcholky pahorků, tmavší úžlabí
	col *= 0.95 + clamp(wpos.y, 0.0, 3.0) * 0.025;
	col *= 0.93 + 0.12 * n2;
	col *= 0.96 + 0.07 * n3;
	col = mix(col, col * vec3(1.03, 1.08, 0.92), season_spring);
	vec3 autumn = mix(vec3(0.58, 0.55, 0.28), vec3(0.55, 0.42, 0.22), smoothstep(0.4, 0.7, n));
	col = mix(col, autumn * (0.93 + 0.12 * n2), season_autumn * 0.75);
	// sníh: souvislý, místy (strmé svahy, šum) prosvítá tráva
	float patchy = smoothstep(0.25, 0.5, fbm(wpos.xz * 0.15 + 3.0) + wnorm.y * 0.4 - 0.25);
	float snow = season_winter * clamp(patchy + 0.35, 0.0, 1.0);
	col = mix(col, vec3(0.9, 0.93, 0.97) * (0.96 + 0.05 * n2), snow);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.7, snow);
	SPECULAR = mix(0.2, 0.45, snow);
}

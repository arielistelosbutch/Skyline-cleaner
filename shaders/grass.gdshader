shader_type spatial;
// Tráva: zahnutá zužující se stébla (UV.y = 0 u kořene, 1 na špičce), barva
// od tmavého kořene ke světlé špičce. Stébla se ohýbají ve vlnách větru, které
// přebíhají přes louku, a uhýbají hráči z cesty. Roční období jako u ostatní vegetace.
render_mode cull_disabled;

global uniform float season_spring;
global uniform float season_autumn;
global uniform float season_winter;
global uniform float wind_strength;

uniform vec3 player_pos = vec3(0.0, -1000.0, 0.0);

varying float tip;
varying vec3 inst_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	inst_pos = MODEL_MATRIX[3].xyz;
	tip = UV.y;
	VERTEX.y *= 1.0 - season_winter * 0.5;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = UV.y * UV.y;
	// vlny větru: šum posouvaný po směru větru, k tomu drobné chvění jednotlivých trsů
	vec2 wdir = normalize(vec2(1.0, 0.35));
	float gust = vnoise(world.xz * 0.07 - wdir * TIME * 1.1) * 0.7 + vnoise(world.xz * 0.21 - wdir * TIME * 2.0) * 0.3;
	float flutter = sin(TIME * 2.4 + dot(inst_pos.xz, vec2(0.7, 1.3)) * 3.0) * 0.6 + sin(TIME * 3.9 + inst_pos.x * 5.1) * 0.4;
	float strength = (0.3 + wind_strength * 1.2) * (0.2 + gust);
	vec2 bend = wdir * strength * 0.2 + vec2(flutter, flutter * 0.6) * 0.025 * (0.6 + wind_strength);
	// hráč stébla rozhrnuje
	vec2 d = world.xz - player_pos.xz;
	float dist = length(d);
	float push = (1.0 - smoothstep(0.2, 1.0, dist)) * (1.0 - step(1.6, abs(world.y - player_pos.y)));
	bend += d / max(dist, 0.05) * push * 0.3;
	float bl = length(bend);
	if (bl > 0.32) { bend *= 0.32 / bl; bl = 0.32; }
	// ohnuté stéblo se zároveň trochu sníží, ať se neprodlužuje
	vec3 off = vec3(bend.x, -bl * bl * 0.9, bend.y) * h;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	if (!FRONT_FACING) {
		// oboustranná stébla: normála míří pořád hlavně nahoru, ať rub není tmavý
		NORMAL = -NORMAL;
	}
	vec3 base = COLOR.rgb;
	float r = hash(inst_pos.xz);
	vec3 c = mix(base * 0.5, base * 1.12 + vec3(0.06, 0.05, 0.0), smoothstep(0.0, 1.0, tip));
	c = mix(c, c * vec3(1.03, 1.1, 0.88) + vec3(0.02, 0.03, 0.0), season_spring);
	vec3 dry = mix(vec3(0.62, 0.55, 0.3), vec3(0.55, 0.42, 0.22), r) * (0.6 + 0.5 * tip);
	c = mix(c, dry, season_autumn * 0.65);
	c = mix(c, c * 0.75, season_winter * 0.6);
	c = mix(c, vec3(0.92, 0.94, 0.98), season_winter * smoothstep(0.35, 1.0, tip) * 0.75);
	ALBEDO = c;
	AO = mix(0.45, 1.0, tip);
	AO_LIGHT_AFFECT = 0.25;
	BACKLIGHT = vec3(0.18, 0.24, 0.06) * tip * (1.0 - season_winter);
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}

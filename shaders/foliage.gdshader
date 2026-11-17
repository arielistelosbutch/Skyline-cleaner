shader_type spatial;
// Stromy, keře, tráva a květiny s barvami podle ročního období (globální
// parametry nastavuje Atmosphere) a houpáním ve větru (u trávy a květin).
render_mode cull_disabled;

global uniform float season_spring;
global uniform float season_autumn;
global uniform float season_winter;
global uniform float wind_strength;

// 0 = strom/keř, 1 = tráva, 2 = květiny (v zimě zmizí pod sněhem), 3 = kopce v dálce
uniform int kind = 0;
uniform float sway = 0.0;

varying vec3 inst_pos;
varying float leaf;
varying float conifer;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	inst_pos = MODEL_MATRIX[3].xyz;
	vec3 c = COLOR.rgb;
	leaf = smoothstep(0.02, 0.1, c.g - max(c.r, c.b));
	conifer = smoothstep(0.58, 0.66, c.b / max(c.g, 0.01)) * leaf;
	if (kind == 2) {
		// květiny v zimě pod sněhem, na podzim jich ubývá
		VERTEX *= max(0.0, 1.0 - season_winter * 1.2 - season_autumn * 0.4);
	}
	if (kind == 1) {
		VERTEX.y *= 1.0 - season_winter * 0.55;
	}
	if (sway > 0.0) {
		float h = max(VERTEX.y, 0.0);
		float ph = inst_pos.x * 0.37 + inst_pos.z * 0.23;
		float w = sin(TIME * 1.6 + ph) * 0.6 + sin(TIME * 2.9 + ph * 1.7) * 0.4;
		VERTEX.x += w * sway * h * h * (0.6 + wind_strength);
		VERTEX.z += w * sway * h * h * 0.4 * (0.6 + wind_strength);
	}
}

void fragment() {
	vec3 c = COLOR.rgb;
	float r = hash(inst_pos.xz);
	float decid = leaf * (1.0 - conifer);
	// jaro: svěží světlejší zeleň
	c = mix(c, c * vec3(1.05, 1.12, 0.9) + vec3(0.03, 0.04, 0.0), season_spring * leaf);
	// podzim: listnaté stromy a keře žloutnou a rudnou, tráva hnědne
	vec3 autumn = mix(vec3(0.85, 0.55, 0.12), vec3(0.78, 0.28, 0.1), smoothstep(0.35, 0.85, r));
	autumn = mix(autumn, vec3(0.9, 0.75, 0.2), step(0.8, r));
	float grass_k = kind == 1 ? 1.0 : 0.0;
	vec3 autumn_c = mix(autumn * (0.8 + 0.4 * c.g), mix(c, vec3(0.62, 0.58, 0.3), 0.55), grass_k);
	c = mix(c, autumn_c, season_autumn * decid);
	// zima: holé koruny šedohnědé, na horních plochách sníh
	vec3 bare = vec3(0.56, 0.5, 0.45);
	c = mix(c, mix(bare, c * 0.8, grass_k * 0.4), season_winter * decid * (1.0 - grass_k * 0.5));
	float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
	float snow = season_winter * smoothstep(0.25, 0.7, up);
	c = mix(c, vec3(0.93, 0.95, 0.98), snow * mix(0.85, 0.6, grass_k));
	if (kind == 3) {
		// vzdálené kopce: podzimní hnědozelená, v zimě zasněžené
		c = COLOR.rgb;
		c = mix(c, c * vec3(1.05, 1.1, 0.9), season_spring);
		c = mix(c, vec3(0.6, 0.55, 0.3) * (0.8 + 0.4 * COLOR.g), season_autumn * 0.6);
		c = mix(c, vec3(0.9, 0.92, 0.96) * (0.92 + 0.1 * up), season_winter * 0.85);
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}

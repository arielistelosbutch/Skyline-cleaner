shader_type spatial;
// Dekorativní sklo (domy, mrakodrapy). V noci se náhodná okna rozsvítí –
// u sloučených fasád podle buněk světové pozice (patro × okno).
render_mode cull_disabled, specular_schlick_ggx;

global uniform float night_amount;

uniform bool use_vertex_color = false;
uniform vec4 base_color : source_color = vec4(0.32, 0.42, 0.46, 0.55);
uniform float metallic = 0.1;
uniform float roughness = 0.08;
uniform float metallic_specular = 0.5;
// true = jedno okno na instanci (pozice uzlu), false = buňky fasády
uniform bool per_node = true;
uniform bool transparent = true;
uniform bool night_lights = true;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = use_vertex_color ? COLOR.rgb : base_color.rgb;
	ALBEDO = c;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = metallic_specular;
	if (transparent) {
		float ndv = abs(dot(NORMAL, VIEW));
		ALPHA = clamp(base_color.a + pow(1.0 - ndv, 4.0) * 0.4, 0.0, 1.0);
	}
	if (night_lights && night_amount > 0.01) {
		vec2 cell;
		if (per_node) {
			cell = NODE_POSITION_WORLD.xz * 0.37 + vec2(NODE_POSITION_WORLD.y);
		} else {
			cell = vec2(floor((wpos.x + wpos.z) / 1.9), floor(wpos.y / 3.4));
		}
		float lit = step(0.5, hash(cell));
		vec3 warm = mix(vec3(1.0, 0.72, 0.42), vec3(0.95, 0.92, 0.85), hash(cell + 3.7));
		EMISSION = warm * lit * night_amount * 0.6;
	}
}

shader_type spatial;
// Budovy (barva z vertexů). V zimě na šikmých střechách leží sníh – jen na plochách
// skloněných jako střecha (podlahy a stoly uvnitř zůstanou bez sněhu).

global uniform float season_winter;

varying float roof_up;

void vertex() {
	roof_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float snow = season_winter * smoothstep(0.35, 0.55, roof_up) * (1.0 - smoothstep(0.96, 0.99, roof_up));
	ALBEDO = mix(c, vec3(0.93, 0.95, 0.98), snow);
	ROUGHNESS = mix(0.88, 0.7, snow);
	SPECULAR = 0.5;
}

shader_type spatial;
// Svítidlo pouliční lampy – v noci září (night_amount z Atmosphere).
render_mode unshaded, cull_disabled;

global uniform float night_amount;

void fragment() {
	vec3 off = vec3(0.85, 0.83, 0.78);
	vec3 on = vec3(1.0, 0.86, 0.6) * 3.0;
	ALBEDO = mix(off, on, night_amount);
}

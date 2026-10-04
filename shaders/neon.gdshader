shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Neon tubes of the "霓虹灯带" court decoration: vertex colour = base tube colour; a slow pulse travels along the run and
// the hue drifts between the tube colour and its neighbour. EMISSION > 1 lets the glow pass bloom it when glow is on.

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * 0.8 + (wpos.x + wpos.z) * 0.35;
	float pulse = 0.8 + 0.2 * sin(t * 2.0);
	vec3 base = COLOR.rgb;
	vec3 col = mix(base, base.gbr, 0.5 + 0.5 * sin(t * 0.5));
	ALBEDO = col * pulse;
	EMISSION = col * 1.6 * pulse;
}

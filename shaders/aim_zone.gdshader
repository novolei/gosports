shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// The aim zone on the floor: an evenly tinted disc (where the ball can land with the current timing), a crisp rim and a bright
// target dot in the middle. Colour = green (safe) / orange (close to a line) / red (out), set by Vfx.show_aim.

uniform vec4 zone_col : source_color = vec4(0.3, 1.0, 0.55, 1.0);
uniform float fill = 0.28;
uniform float rim_w = 0.06;       // rim width, as a fraction of the disc radius
uniform float dot_r = 0.12;       // target dot radius, as a fraction of the disc radius
uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.3 + 0.002;
	float disc = 1.0 - smoothstep(0.93 - aa, 0.93 + aa, r);
	float rim = 1.0 - smoothstep(rim_w * 0.5 - aa, rim_w * 0.5 + aa, abs(r - 0.9));
	float dotm = 1.0 - smoothstep(dot_r - aa, dot_r + aa, r);
	float halo = (1.0 - smoothstep(dot_r, dot_r * 2.4, r)) * 0.4;
	float edge = 1.0 - smoothstep(rim_w * 0.5 + 0.035 - aa, rim_w * 0.5 + 0.035 + aa, abs(r - 0.9));       // dark under-rim: contrast on any court colour
	float a = clamp(disc * fill + edge * 0.28 + rim * (0.9 + 0.1 * pulse) + dotm + halo, 0.0, 1.0);
	vec3 c = mix(zone_col.rgb * 1.2, vec3(1.0), dotm * 0.7 + rim * 0.12);
	c = mix(vec3(0.02, 0.1, 0.18), c, clamp(rim + disc * 0.7 + dotm + halo, 0.0, 1.0));
	ALBEDO = c;
	ALPHA = a;
}

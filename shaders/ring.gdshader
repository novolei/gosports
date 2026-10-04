shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Glowing floor ring under an athlete (Switch-Sports style): soft blue outer ring + rainbow inner ring.

uniform vec4 ring_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform sampler2D grad : source_color, repeat_disable, filter_linear;
uniform float inner = 0.55;         // inner radius (0..1, 1 = quad edge)
uniform float width = 0.1;
uniform float intensity = 1.0;
uniform float pulse = 0.0;          // 0..1 flash
uniform float fill_alpha = 0.12;
uniform float fill_flat = 0.0;       // 1 = an evenly filled disc with a crisp edge (the aim zone) instead of the soft falloff
uniform float rainbow = 1.0;
uniform float halo_strength = 0.0;
uniform float core_white = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.2 + 0.003;
	// outer ring
	float outer = 1.0 - smoothstep(width * 0.5 - aa, width * 0.5 + aa, abs(r - 0.9));
	// inner ring (thin)
	float inr = 1.0 - smoothstep(width * 0.35 - aa, width * 0.35 + aa, abs(r - inner));
	// disc fill with a soft falloff
	float fill = mix((1.0 - smoothstep(0.0, 0.92, r)) * fill_alpha, (1.0 - smoothstep(0.84, 0.9, r)) * fill_alpha, fill_flat);
	float halo = exp(-pow((r - 0.9) / 0.12, 2.0)) * 0.32 * halo_strength;     // soft glow around the outer ring
	vec3 rb = texture(grad, vec2(clamp(r, 0.0, 1.0), 0.5)).rgb;
	vec3 col = ring_color.rgb * (outer + fill + halo);
	col = mix(col, vec3(1.0), outer * core_white);                                // bright core line like the reference ring
	col += mix(vec3(1.0), rb, rainbow) * inr * 0.9;
	float a = clamp(outer * 0.97 + inr * 0.9 + fill + halo, 0.0, 1.0) * ring_color.a * intensity;
	col = mix(col, vec3(1.0), pulse * 0.6);
	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = clamp(a + pulse * outer * 0.4, 0.0, 1.0);
}

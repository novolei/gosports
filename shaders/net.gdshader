shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque, specular_disabled;
// Volleyball net: dark mesh with white top / bottom tape. UV.x along the width, UV.y 0 = top.

uniform vec2 size = vec2(10.0, 1.0);
uniform float cell = 0.11;
uniform float thickness = 0.16;
uniform vec3 mesh_col : source_color = vec3(0.05, 0.06, 0.08);
uniform vec3 tape_col : source_color = vec3(1.0, 0.98, 0.95);
uniform float tape_top = 0.11;
uniform float tape_bottom = 0.05;

void fragment() {
	vec2 p = UV * size;
	vec2 g = fract(p / cell);
	vec2 dg = min(g, 1.0 - g);
	vec2 fw = fwidth(p / cell);
	float tx = max(thickness * 0.5, fw.x * 0.9);
	float ty = max(thickness * 0.5, fw.y * 0.9);
	float lx = 1.0 - smoothstep(tx - fw.x * 0.6, tx + fw.x * 0.6, dg.x);
	float ly = 1.0 - smoothstep(ty - fw.y * 0.6, ty + fw.y * 0.6, dg.y);
	float net = max(lx, ly);
	float top = 1.0 - step(tape_top, p.y);
	float bot = step(size.y - tape_bottom, p.y);
	float tape = max(top, bot);
	ALBEDO = mix(mesh_col, tape_col, tape);
	ALPHA = max(net * 0.92, tape);
	ROUGHNESS = 0.9;
}

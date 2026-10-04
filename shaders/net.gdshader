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
uniform vec3 tape_col2 : source_color = vec3(1.0, 1.0, 1.0);
uniform float tape_stripe = 0.0;         // > 0: alternate tape_col / tape_col2 every this many metres
uniform float rainbow = 0.0;             // 1 = the tape runs through the rainbow
uniform float hearts = 0.0;              // 1 = pink hearts woven into the mesh
uniform vec3 heart_col : source_color = vec3(1.0, 0.45, 0.65);

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
	vec3 tc = tape_col;
	if (tape_stripe > 0.0) {
		tc = mix(tape_col, tape_col2, step(0.5, fract(p.x / tape_stripe)));
	}
	if (rainbow > 0.5) {
		vec3 k = clamp(abs(fract(vec3(p.x * 0.55) + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
		tc = mix(vec3(1.0), k, 0.8);
	}
	float heart = 0.0;
	if (hearts > 0.5) {
		float hc = cell * 2.4;
		vec2 id = floor(p / hc);
		float on = ((id.y == 1.0 && mod(id.x, 4.0) == 1.0) || (id.y == 2.0 && mod(id.x, 4.0) == 3.0) || (id.y == 3.0 && mod(id.x, 4.0) == 1.0)) ? 1.0 : 0.0;
		vec2 q = (fract(p / hc) - vec2(0.5)) * 2.6;
		q.y = -q.y + 0.15;
		float hh = pow(q.x * q.x + q.y * q.y - 1.0, 3.0) - q.x * q.x * q.y * q.y * q.y;
		heart = (1.0 - smoothstep(-0.05, 0.05, hh)) * on;
	}
	vec3 col = mix(mesh_col, tc, tape);
	col = mix(col, heart_col, heart);
	ALBEDO = col;
	ALPHA = max(max(net * 0.92, tape), heart * 0.95);
	ROUGHNESS = 0.9;
}

shader_type canvas_item;
// Fever time: a flickering flame-coloured glow around the screen edge (cheap: one full-screen quad, only visible in fever).

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.52, 0.12, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.0, 0.64)) * 1.55;
	float edge = smoothstep(0.5, 1.05, d);
	float flick = 0.82 + 0.18 * sin(TIME * 9.0 + uv.x * 15.0) * sin(TIME * 7.3 + uv.y * 12.0);
	COLOR = vec4(glow_color.rgb, edge * intensity * flick * 0.85);
}

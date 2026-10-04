shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
// LED advertising hoardings: ONE mesh for every board of the venue (one draw call). Each panel's vertices carry
// COLOR.r = first atlas cell / 15, COLOR.g = phase offset; the panel shows its cell and swaps to the next one every
// `period` seconds with a quick LED "wipe", like the rotating boards of a broadcast.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float period = 7.0;
uniform float bright = 1.0;
uniform float cells = 16.0;
uniform vec3 night_tint : source_color = vec3(1.0);

varying flat float v_cell;
varying float v_phase;

void vertex() {
	v_cell = floor(COLOR.r * 15.0 + 0.5);
	v_phase = COLOR.g * 40.0;
}

void fragment() {
	float t = (TIME + v_phase) / period;
	float step_i = floor(t);
	float k = fract(t);
	float cell = mod(v_cell + step_i * 5.0, cells);                 // 5 is coprime with 16: every board cycles through all 16 panels
	// wipe: the new panel sweeps in from the left during the first 8 % of the cycle, the old one is still there until it passes
	float wipe = smoothstep(0.0, 0.08, k);
	float prev = mod(v_cell + (step_i - 1.0) * 5.0, cells);
	float use_new = step(UV.x, wipe);
	float c = mix(prev, cell, use_new);
	vec2 local = clamp(UV, 0.004, 0.996);
	vec2 uv = (vec2(mod(c, 4.0), floor(c / 4.0)) + local) / 4.0;
	vec3 col = texture(atlas, uv).rgb;
	float edge = wipe >= 0.999 ? 1.0 : smoothstep(0.0, 0.015, abs(UV.x - wipe));
	col = mix(vec3(1.0), col, edge);                                 // bright scan line while wiping
	// LED pixel grid hint (very faint, only visible up close)
	float grid = 0.96 + 0.04 * step(0.5, fract(UV.y * 24.0));
	ALBEDO = col * grid * bright * night_tint;
}

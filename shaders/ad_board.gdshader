shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
// LED advertising hoardings: ONE mesh for every board of the venue (one draw call). Each panel's vertices carry
// COLOR.r = first atlas cell / 15, COLOR.g = phase offset; the panel shows its cell and swaps to the next one every
// `period` seconds with a quick LED "wipe", like the rotating boards of a broadcast.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float period = 7.0;
uniform float bright = 1.0;
uniform float cells = 16.0;
uniform float t_off = 0.0;               // dev: --adoffset=<seconds> jumps the rotation ahead
uniform vec3 night_tint : source_color = vec3(1.0);

varying flat float v_cell;
varying float v_phase;

void vertex() {
	v_cell = floor(COLOR.r * 15.0 + 0.5);
	v_phase = COLOR.g * 40.0;
}

void fragment() {
	float t = (TIME + t_off + v_phase) / period;
	float step_i = floor(t);
	float k = fract(t);
	float cell = mod(v_cell + step_i * 5.0, cells);                 // 5 is coprime with 16: every board cycles through all 16 panels
	float prev = mod(v_cell + (step_i - 1.0) * 5.0, cells);
	// every refresh uses one of four transition styles (picked from the step number and the board): wipe right, wipe left,
	// venetian blinds opening, or a pixel dissolve
	float style = mod(step_i * 3.0 + v_cell, 4.0);
	float wipe = smoothstep(0.0, 0.1, k);
	float use_new;
	float scan = 0.0;
	if (style < 0.5) {
		use_new = step(UV.x, wipe);
		scan = 1.0 - smoothstep(0.0, 0.015, abs(UV.x - wipe));
	} else if (style < 1.5) {
		use_new = step(1.0 - UV.x, wipe);
		scan = 1.0 - smoothstep(0.0, 0.015, abs((1.0 - UV.x) - wipe));
	} else if (style < 2.5) {
		use_new = step(fract(UV.y * 5.0), wipe);                         // each slat of the blinds opens from the top
	} else {
		vec2 cellp = floor(UV * vec2(32.0, 10.0));
		float h = fract(sin(dot(cellp, vec2(12.9898, 78.233))) * 43758.5453);
		use_new = step(h, wipe);
	}
	if (wipe >= 0.999) {
		use_new = 1.0;
		scan = 0.0;
	}
	float c = mix(prev, cell, use_new);
	vec2 local = clamp(UV, 0.004, 0.996);
	vec2 uv = (vec2(mod(c, 4.0), floor(c / 4.0)) + local) / 4.0;
	vec3 col = texture(atlas, uv).rgb;
	col = mix(col, vec3(1.0), scan);                                 // bright scan line while a wipe sweeps
	// LED pixel grid hint (very faint, only visible up close)
	float grid = 0.96 + 0.04 * step(0.5, fract(UV.y * 24.0));
	ALBEDO = col * grid * bright * night_tint;
}

shader_type spatial;
// Switch-Sports-like glossy volleyball court: orange->pink gradient, bright attack zone,
// teal free zone, white lines (analytic, anti-aliased) and soft diagonal light bands.

uniform vec2 half_size = vec2(4.5, 7.0);
uniform float attack = 2.8;
uniform float line_w = 0.075;
uniform vec3 col_net : source_color = vec3(0.98, 0.66, 0.36);
uniform vec3 col_base : source_color = vec3(0.97, 0.58, 0.55);
uniform vec3 col_attack : source_color = vec3(1.0, 0.74, 0.42);
uniform vec3 col_free : source_color = vec3(0.27, 0.62, 0.56);
uniform vec3 col_free_dark : source_color = vec3(0.20, 0.52, 0.48);
uniform vec3 line_col : source_color = vec3(1.0, 1.0, 1.0);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.36;
uniform float stripe_strength : hint_range(0.0, 0.4) = 0.1;
uniform float dash_len = 0.9;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line_mask(float d, float w, float aa) {
	return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, abs(d));
}

void fragment() {
	vec2 p = wp.xz;
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.9 + 0.002;
	vec2 d = abs(p) - half_size;
	float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	bool inside = sd < 0.0;

	// base colours
	float tz = clamp(abs(p.y) / half_size.y, 0.0, 1.0);
	vec3 court = mix(col_net, col_base, smoothstep(0.0, 1.0, tz));
	float in_attack = 1.0 - smoothstep(attack - 0.05, attack + 0.05, abs(p.y));
	court = mix(court, col_attack, in_attack * 0.85);
	// subtle lengthwise gradient to the sidelines
	court *= 1.0 - 0.05 * smoothstep(0.5, 1.0, abs(p.x) / half_size.x);

	float fz = smoothstep(0.0, 3.0, sd);
	vec3 free_c = mix(col_free, col_free_dark, fz);
	vec3 col = inside ? court : free_c;
	float edge = smoothstep(-aa, aa, sd);
	col = mix(court, free_c, edge);

	// lines
	float lm = line_mask(sd, line_w, aa);
	float ay = line_mask(abs(p.y) - attack, line_w, aa) * (1.0 - step(half_size.x, abs(p.x)));
	float cl = line_mask(p.y, line_w * 1.4, aa) * (1.0 - step(half_size.x, abs(p.x)));
	// dashed free-zone guide lines
	float dash_x = step(0.5, fract(p.x / dash_len));
	float dash_z = step(0.5, fract(p.y / dash_len));
	float g1 = line_mask(abs(p.y) - (half_size.y + 1.1), line_w, aa) * dash_x * (1.0 - step(half_size.x + 1.4, abs(p.x)));
	float g2 = line_mask(abs(p.x) - (half_size.x + 1.1), line_w, aa) * dash_z * (1.0 - step(half_size.y + 1.4, abs(p.y)));
	float lines = clamp(lm + ay + cl + g1 + g2, 0.0, 1.0);
	col = mix(col, line_col, lines * 0.96);

	// soft diagonal light bands (sun through the roof)
	float band = sin((p.x * 0.55 + p.y * 0.95) * 0.9) * 0.5 + 0.5;
	band = smoothstep(0.35, 0.65, band);
	col *= 1.0 - stripe_strength * (1.0 - band);

	ALBEDO = col;
	ROUGHNESS = roughness_v;
	SPECULAR = 0.55;
	METALLIC = 0.0;
}

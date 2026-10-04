shader_type canvas_item;
// Switch-Sports-style menu pill: rounded body with a soft vertical gradient, a gloss band, optional diagonal stripes,
// a fat white rim and a soft drop shadow. Drawn on a ColorRect that is `pad` pixels larger than the pill on every side
// (the shadow lives in that margin). One draw call per pill, no textures.

uniform vec2 rect_size = vec2(400.0, 80.0);   // the pill itself, in pixels
uniform float pad = 18.0;                      // margin around the pill
uniform float radius = 40.0;
uniform vec4 base_col : source_color = vec4(0.80, 0.89, 0.91, 1.0);
uniform vec4 rim_col : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim = 3.0;
uniform float stripes = 0.0;                   // 0..1 diagonal stripe strength (selected pills)
uniform float shade = 0.05;                    // bottom darkening (kept tiny: lightly flat look)
uniform float gloss = 0.03;                    // top lightening
uniform float shadow = 0.16;                   // shadow opacity
uniform float lift = 0.0;                      // 0..1: pressed pills sink (shadow shrinks)

float sdf_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 full = rect_size + vec2(pad * 2.0);
	vec2 p = (UV - vec2(0.5)) * full;
	float d = sdf_box(p, rect_size * 0.5, radius);
	float aa = 1.2;
	float body = 1.0 - smoothstep(-aa, aa, d);

	// soft drop shadow, offset downwards
	float ds = sdf_box(p - vec2(0.0, 5.0 - lift * 3.0), rect_size * 0.5, radius);
	float sh = (1.0 - smoothstep(-1.0, pad * 0.45, ds)) * shadow * (1.0 - lift * 0.5);

	float v = clamp((p.y / rect_size.y) + 0.5, 0.0, 1.0);
	vec3 c = base_col.rgb;
	c = mix(c * (1.0 + gloss), c * (1.0 - shade), smoothstep(0.0, 1.0, v));
	// top gloss band
	// diagonal stripes (like the selected menu entries of the reference game)
	float s = sin((p.x - p.y * 1.4) * 0.19);
	c = mix(c, c + vec3(0.07), stripes * smoothstep(0.4, 0.7, s));
	// rim
	float r = smoothstep(-rim - aa, -rim + aa, d);
	c = mix(c, rim_col.rgb, r * rim_col.a);
	float a = body * base_col.a;
	COLOR = vec4(mix(vec3(0.03, 0.12, 0.2), c, body), max(a, sh * (1.0 - body)));
	if (body > 0.01) {
		COLOR.a = max(body * base_col.a, sh);
	}
}

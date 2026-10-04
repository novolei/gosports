shader_type canvas_item;
// Frosted-glass panel like the match-settings / options panels of the reference game: the scene behind it is blurred and
// washed with a pale tint, a soft white rim, a faint corner gloss and a big watermark ring. Menus only (it reads the screen
// texture, which is cheap when nothing else animates behind it).

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 rect_size = vec2(600.0, 400.0);
uniform float pad = 22.0;
uniform float radius = 36.0;
uniform float lod = 3.0;
uniform vec4 tint : source_color = vec4(0.90, 0.96, 0.97, 1.0);
uniform float tint_amount = 0.62;
uniform float shadow = 0.14;
uniform float watermark = 0.07;

float sdf_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 full = rect_size + vec2(pad * 2.0);
	vec2 p = (UV - vec2(0.5)) * full;
	float d = sdf_box(p, rect_size * 0.5, radius);
	float body = 1.0 - smoothstep(-1.2, 1.2, d);
	float ds = sdf_box(p - vec2(0.0, 5.0), rect_size * 0.5, radius);
	float sh = (1.0 - smoothstep(-1.0, pad * 0.5, ds)) * shadow;

	vec3 bg = textureLod(screen_tex, SCREEN_UV, lod).rgb;
	vec3 c = mix(bg, tint.rgb, tint_amount);
	float v = clamp(p.y / rect_size.y + 0.5, 0.0, 1.0);
	c = mix(c + vec3(0.015), c - vec3(0.01), v);
	// faint watermark ring (a stylised ball) in the lower right
	vec2 wp = p - vec2(rect_size.x * 0.28, rect_size.y * 0.18);
	float wr = length(wp);
	float ring = smoothstep(rect_size.y * 0.42, rect_size.y * 0.42 - 6.0, wr) * smoothstep(rect_size.y * 0.34, rect_size.y * 0.34 + 6.0, wr);
	c = mix(c, vec3(1.0), ring * watermark);
	float rim = smoothstep(-3.5, -1.5, d);
	c = mix(c, vec3(1.0), rim * 0.9);
	COLOR = vec4(c, 1.0) * vec4(1.0, 1.0, 1.0, body);
	COLOR.a = max(body, sh * (1.0 - body));
	if (body < 0.99) {
		COLOR.rgb = mix(vec3(0.03, 0.12, 0.2), COLOR.rgb, body);
	}
}

shader_type canvas_item;
// Frosted backdrop behind pause menus: blurred copy of everything drawn so far, lightly tinted.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float lod : hint_range(0.0, 6.0) = 3.2;
uniform vec4 tint : source_color = vec4(0.78, 0.9, 0.93, 0.28);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb;
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}

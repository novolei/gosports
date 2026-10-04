shader_type canvas_item;
// Soft circular mask for portrait avatars: anti-aliased edge without clip_children (which costs an offscreen pass on phones).
uniform float feather = 0.035;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float aa = max(fwidth(d) * 1.2, feather * 0.5);
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.a *= 1.0 - smoothstep(1.0 - aa, 1.0, d);
	COLOR = c;
}

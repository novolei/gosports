shader_type canvas_item;
// Glossy "sports broadcast" glyph fill for the HUD callouts (Callout): a vertical two-colour gradient, a thin bright top edge
// and a diagonal sheen that sweeps across once when the text pops in. Used on a Label that has NO outline (the dark outline and the
// drop shadow are two plain labels behind it), so the gradient only ever touches the glyph fill.

uniform vec4 top_col : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 bot_col : source_color = vec4(0.75, 0.9, 1.0, 1.0);
uniform vec2 box = vec2(400.0, 100.0);   // size of the label (px)
uniform float sheen = -1.0;              // sweep position (0..1 across the label); < 0 = off

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float v = clamp(lp.y / box.y, 0.0, 1.0);
	vec3 c = mix(top_col.rgb, bot_col.rgb, smoothstep(0.22, 0.9, v));
	c += vec3(0.16) * (1.0 - smoothstep(0.0, 0.3, v));                 // bright top edge
	float d = lp.x / box.x + (lp.y / box.y) * 0.3 - sheen;
	c += vec3(0.6) * smoothstep(0.07, 0.0, abs(d)) * step(0.0, sheen);
	COLOR = vec4(c, t.a) * COLOR;
}

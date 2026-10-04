shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// "Hero" character material (athletes, menu stage, replay ghosts): the same texture, soft wrap lighting and rim light as the
// standard material, plus
//  * a ground-occlusion gradient: the lower parts of the body are a little darker and slightly cooler, so characters sit on the
//    floor instead of floating and the white / pale animals keep a readable form;
//  * a gentle saturation lift on the flat palette textures;
//  * a faint warm top light on the upper body (shoulders, ears, hair) which separates the head from the shirt.
// Cost: one texture sample and a few ALU ops per pixel, no extra passes (the outline is a separate next_pass material).

uniform sampler2D tex_n : source_color, filter_nearest, repeat_enable;
uniform sampler2D tex_l : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool pixel = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool alpha_cut = false;
uniform float rim = 0.3;
uniform float rim_tint = 0.6;
uniform float rough = 0.6;
uniform float spec = 0.35;
uniform float ao_floor = 0.7;
uniform float ao_height = 0.8;
uniform float sat = 1.06;
uniform vec3 ao_cool = vec3(0.9, 0.94, 1.08);
uniform float top_light = 0.1;

varying float v_wy;

void vertex() {
	v_wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec4 t = pixel ? texture(tex_n, UV) : texture(tex_l, UV);
	if (alpha_cut && t.a < 0.45) {
		discard;
	}
	vec3 c = t.rgb * tint.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat);
	float g = smoothstep(0.0, ao_height, v_wy);
	vec3 ao = mix(vec3(ao_floor) * ao_cool, vec3(1.0), g);
	c *= ao;
	c *= vec3(1.0) + vec3(1.0, 0.96, 0.88) * top_light * smoothstep(0.55, 1.25, v_wy);     // multiplicative: black hair stays black
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = spec;
	RIM = rim;
	RIM_TINT = rim_tint;
}

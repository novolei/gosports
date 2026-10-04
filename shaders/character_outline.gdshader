shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
// Thin silhouette outline for the athletes (next_pass of the hero material): the mesh is drawn again, back faces only, pushed
// outwards along its normals by a CONSTANT number of screen pixels (width is a fraction of the viewport height), in a dark
// colour-matched navy. Keeps white / pale animals readable against the white sky, clouds and light stands.

uniform float width = 0.0028;
uniform vec4 outline_color : source_color = vec4(0.08, 0.11, 0.26, 1.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 nv = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(nv, 0.0)).xy;
	float len = length(dir);
	dir = len > 0.0001 ? dir / len : vec2(0.0);
	dir.x *= VIEWPORT_SIZE.y / VIEWPORT_SIZE.x;
	clip.xy += dir * width * 2.0 * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}

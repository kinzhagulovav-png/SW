shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
instance uniform float frac = 1.0;
instance uniform vec4 fill = vec4(0.4, 1.0, 0.5, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec3 col = UV.x < frac ? fill.rgb : vec3(0.1, 0.12, 0.16);
	if (UV.x < 0.02 || UV.x > 0.98 || UV.y < 0.12 || UV.y > 0.88) {
		col = vec3(0.02, 0.03, 0.05);
	}
	ALBEDO = col;
}

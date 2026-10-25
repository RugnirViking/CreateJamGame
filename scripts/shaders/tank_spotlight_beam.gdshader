shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
void fragment() {
	ALBEDO = vec3(0.75, 0.82, 0.55);
	ALPHA = 0.035 * pow(1.0 - UV.y, 2.0);
}

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D tread_texture : source_color, filter_linear_mipmap;
uniform vec4 track_color : source_color = vec4(0.16, 0.12, 0.075, 0.55);

void fragment() {
	ALBEDO = track_color.rgb;
	ROUGHNESS = 1.0;
	ALPHA = texture(tread_texture, UV).a * track_color.a;
}

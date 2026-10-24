shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D chevron_texture : source_color, repeat_enable;
uniform vec4 tint : source_color = vec4(1.353256, 1.353256, 0.0, 1.0);
uniform float repeat_count : hint_range(1.0, 12.0, 1.0) = 3.0;
uniform float scroll_speed : hint_range(0.0, 2.0, 0.01) = 0.25;

void fragment() {
	// Quad UV +Y points toward the tank's local -X (forward).
	vec2 uv = vec2(UV.x, UV.y * repeat_count - TIME * scroll_speed);
	vec4 chevron = texture(chevron_texture, uv);
	ALBEDO = chevron.rgb * tint.rgb;
	ALPHA = chevron.a * tint.a;
}

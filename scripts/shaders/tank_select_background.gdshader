shader_type canvas_item;
void fragment() {
	vec2 cell = abs(fract(UV * vec2(64.0, 36.0)) - 0.5);
	float grid = step(0.485, max(cell.x, cell.y));
	float glow = exp(-length((UV - vec2(0.28, 0.45)) * vec2(1.0, 1.5)) * 3.0);
	COLOR = vec4(vec3(0.025, 0.036, 0.029) + grid * vec3(0.012, 0.018, 0.013) + glow * vec3(0.022, 0.029, 0.016), 1.0);
}

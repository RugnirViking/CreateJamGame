shader_type spatial;

instance uniform float player_x;
instance uniform float player_y;
uniform float player_speed;
instance uniform float radius;
uniform float feather;
uniform vec4 color_ground : source_color;
instance uniform vec4 color_target : source_color;
const int MAX_MARKERS = 32;
uniform int marker_count = 0;
// XZ center, radius, ring width. Arrays are uploaded together by the terrain renderer.
uniform vec4 marker_positions[MAX_MARKERS];
uniform vec4 marker_colors[MAX_MARKERS] : source_color;
// Pulse strength and capture progress.
uniform vec4 marker_effects[MAX_MARKERS];


uniform sampler2D sand_texture : source_color;
uniform sampler2D normal_map : hint_normal;
uniform float uv_scale = 20.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.8;

varying vec3 world_position;

void vertex() {
	// Called for every vertex the material is visible on.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Called for every pixel the material is visible on.
	vec2 target = vec2(player_x, player_y);
	float dist = length(world_position.xz - target);
	
    vec2 scaled_uv = UV * uv_scale;
    vec4 tex = texture(sand_texture, scaled_uv);
	
	float circle = 1.0 - smoothstep(radius, radius + feather, dist);
	
    ALBEDO = mix(color_ground.rgb*tex.rgb, color_target.rgb, circle*color_target.a);
	// Blend onto the opaque terrain so the fill shows the sand beneath it.
	for (int i = 0; i < marker_count; i++) {
		vec4 marker = marker_positions[i];
		vec4 tint = marker_colors[i];
		float marker_dist = length(world_position.xz - marker.xy);
		float edge = max(fwidth(marker_dist), 0.005);
		float outer = 1.0 - smoothstep(marker.z - edge, marker.z + edge, marker_dist);
		float inner_radius = max(marker.z - marker.w, 0.0);
		float ring = smoothstep(inner_radius - edge, inner_radius + edge, marker_dist);
		float fill = clamp(tint.a + marker_effects[i].x * 0.22 + marker_effects[i].y * 0.2, 0.0, 1.0);
		float opacity = outer * mix(fill, 1.0, ring);
		ALBEDO = mix(ALBEDO, tint.rgb, opacity);
	}
	
    NORMAL_MAP = texture(normal_map, scaled_uv).rgb;
    ROUGHNESS = roughness_val;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}

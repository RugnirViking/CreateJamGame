shader_type spatial;

instance uniform float player_x;
instance uniform float player_y;
uniform float player_speed;
instance uniform float radius;
uniform float feather;
uniform vec4 color_ground : source_color;
instance uniform vec4 color_target : source_color;


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
	
    NORMAL_MAP = texture(normal_map, scaled_uv).rgb;
    ROUGHNESS = roughness_val;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}

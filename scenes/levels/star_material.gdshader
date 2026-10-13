
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix, fog_disabled;

uniform float star_visibility : hint_range(0.0, 1.0) = 1.0;
uniform float star_density : hint_range(50.0, 1000.0) = 350.0;
uniform float star_brightness : hint_range(0.0, 5.0) = 1.5;
uniform float star_size : hint_range(0.001, 0.1) = 0.015;

varying vec3 star_direction;

float random_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	star_direction = normalize(VERTEX);
}

void fragment() {
	vec3 direction = normalize(star_direction);

	vec3 grid = direction * star_density;
	vec3 cell = floor(grid);
	vec3 local_pos = fract(grid) - 0.5;

	float random_value = random_hash(cell);

	float star = 0.0;

	if (random_value > 0.95) {
		float distance_to_center = length(local_pos);

		star = 1.0 - smoothstep(
			star_size,
			star_size * 2.0,
			distance_to_center
		);
	}

	float brightness = star * star_brightness * star_visibility;

	ALBEDO = vec3(brightness);
	EMISSION = vec3(brightness);
	ALPHA = clamp(brightness, 0.0, 1.0);
}

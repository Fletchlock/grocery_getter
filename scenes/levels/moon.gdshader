
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;

uniform vec4 moon_color : source_color = vec4(0.92, 0.94, 1.0, 1.0);
uniform float moon_visibility : hint_range(0.0, 1.0) = 1.0;
uniform float moon_brightness : hint_range(0.0, 5.0) = 1.5;
uniform float crater_strength : hint_range(0.0, 1.0) = 0.25;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	f = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float distance_from_center = length(uv);

	// Circular moon with a slightly softened edge.
	float moon_mask = 1.0 - smoothstep(
		0.94,
		1.0,
		distance_from_center
	);

	// Subtle surface variation.
	float surface_noise = noise(UV * 12.0);
	surface_noise += noise(UV * 28.0) * 0.3;
	surface_noise /= 1.3;

	float surface_detail = mix(
		1.0,
		0.65 + surface_noise * 0.35,
		crater_strength
	);

	// Slightly darker edges for a spherical appearance.
	float edge_shading = 1.0 - smoothstep(
		0.65,
		1.0,
		distance_from_center
	) * 0.25;

	vec3 final_color = moon_color.rgb
		* surface_detail
		* edge_shading
		* moon_brightness;

	ALBEDO = final_color;
	EMISSION = final_color;

	ALPHA = moon_mask * moon_visibility;
}

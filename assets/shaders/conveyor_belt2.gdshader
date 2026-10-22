
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 rubber_color : source_color = vec4(0.055, 0.065, 0.075, 1.0);
uniform vec4 groove_color : source_color = vec4(0.018, 0.022, 0.028, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.14, 0.17, 0.19, 1.0);

uniform float belt_speed : hint_range(-10.0, 10.0) = 1.5;
uniform float groove_density : hint_range(1.0, 100.0) = 45.0;
uniform float groove_width : hint_range(0.01, 0.5) = 0.12;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.88;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.05;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.35;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	// Animate along the belt's local Z axis.
	float moving_z = local_position.z - TIME * belt_speed;

	// Repeating transverse rubber grooves.
	float phase = fract(moving_z * groove_density);
	float groove = 1.0 - smoothstep(
		0.0,
		groove_width,
		min(phase, 1.0 - phase)
	);

	// Fine rubber surface variation.
	float grain = sin(local_position.x * 93.0 + moving_z * 31.0);
	grain *= sin(local_position.x * 47.0 - moving_z * 67.0);
	grain = grain * 0.5 + 0.5;

	// Subtle moving reflective bands.
	float highlight = pow(
		0.5 + 0.5 * sin(moving_z * 3.0),
		12.0
	);

	vec3 color = mix(
		rubber_color.rgb,
		groove_color.rgb,
		groove
	);

	color = mix(
		color,
		highlight_color.rgb,
		highlight * 0.16
	);

	color *= mix(0.92, 1.08, grain);

	ALBEDO = color;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;

	// Simulated groove depth through the normal map.
	NORMAL_MAP = vec3(
		0.5,
		0.5 + (groove - 0.5) * bump_strength,
		1.0
	);
	NORMAL_MAP_DEPTH = 0.4;
}

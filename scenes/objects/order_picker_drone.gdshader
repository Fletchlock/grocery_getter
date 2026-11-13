
shader_type spatial;

render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(0.05, 0.85, 1.0, 1.0);

uniform float beam_opacity : hint_range(0.0, 1.0) = 0.28;
uniform float swirl_speed : hint_range(0.0, 10.0) = 2.0;
uniform float swirl_density : hint_range(1.0, 20.0) = 8.0;
uniform float glow_strength : hint_range(0.0, 5.0) = 2.0;
uniform float bottom_fade_height : hint_range(0.01, 1.0) = 0.35;

varying vec3 beam_vertex_position;

void vertex() {
	beam_vertex_position = VERTEX;
}

void fragment() {
	// CylinderMesh is 2 metres tall.
	// Wide bottom = -1.0, narrow top = 1.0.
	float height_factor = clamp(
		(beam_vertex_position.y + 1.0) / 2.0,
		0.0,
		1.0
	);

	// Angle around the cone.
	float angle = atan(
		beam_vertex_position.z,
		beam_vertex_position.x
	);

	// Animated swirling energy.
	float spiral = sin(
		angle * 4.0 +
		height_factor * swirl_density * 6.28318 -
		TIME * swirl_speed
	);

	spiral = pow(spiral * 0.5 + 0.5, 3.0);

	// Fade out toward the wide bottom.
	float bottom_fade = smoothstep(
		0.0,
		bottom_fade_height,
		height_factor
	);

	// Slight fade near the narrow top.
	float top_fade = 1.0 - smoothstep(
		0.95,
		1.0,
		height_factor
	);

	float edge_fade = bottom_fade * top_fade;
	float intensity = 0.25 + spiral * 0.75;

	ALBEDO = beam_color.rgb;
	EMISSION = beam_color.rgb * glow_strength * intensity;
	ALPHA = beam_opacity * intensity * edge_fade;
}

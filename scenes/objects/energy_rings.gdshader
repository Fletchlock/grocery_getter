
shader_type spatial;

render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 ring_color : source_color = vec4(0.15, 0.95, 1.0, 1.0);

uniform float ring_count : hint_range(1.0, 10.0) = 4.0;
uniform float ring_speed : hint_range(0.0, 5.0) = 0.6;
uniform float ring_width : hint_range(0.005, 0.2) = 0.045;
uniform float ring_brightness : hint_range(0.0, 8.0) = 3.0;
uniform float ring_opacity : hint_range(0.0, 1.0) = 0.8;

// 0.0 = fully extended, 1.0 = hidden.
instance uniform float beam_cutoff = 1.0;

varying vec3 ring_vertex_position;

void vertex() {
	ring_vertex_position = VERTEX;
}

void fragment() {
	float height_factor = clamp(
		(ring_vertex_position.y + 1.0) / 2.0,
		0.0,
		1.0
	);

	float phase = fract(
		height_factor * ring_count - TIME * ring_speed
	);

	float distance_to_ring = abs(phase - 0.5);

	float ring = 1.0 - smoothstep(
		0.0,
		ring_width,
		distance_to_ring
	);

	float bottom_fade = smoothstep(
		0.05,
		0.25,
		height_factor
	);

	float top_fade = 1.0 - smoothstep(
		0.85,
		1.0,
		height_factor
	);

	float fade = bottom_fade * top_fade;

	// Match the cone's moving boundary.
	float reveal = smoothstep(
		beam_cutoff - 0.06,
		beam_cutoff + 0.06,
		height_factor
	);

	float intensity = ring * fade * reveal;

	ALBEDO = ring_color.rgb;
	EMISSION = ring_color.rgb * ring_brightness * intensity;
	ALPHA = ring_opacity * intensity;
}

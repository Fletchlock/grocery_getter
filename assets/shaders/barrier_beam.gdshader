
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(1.0, 0.02, 0.08, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.55, 0.65, 1.0);

uniform float emission_strength : hint_range(0.0, 10.0) = 4.0;
uniform float flow_speed : hint_range(0.0, 10.0) = 2.5;
uniform float streak_density : hint_range(1.0, 80.0) = 30.0;
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.12;
uniform float opacity : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	vec2 uv = UV;

	// Bright energy streaks moving left to right.
	float flow = uv.x * streak_density - TIME * flow_speed;
	float streaks = pow(
		0.5 + 0.5 * sin(flow),
		8.0
	);

	// Additional finer moving energy pattern.
	float detail = sin(
		uv.x * 85.0 - TIME * flow_speed * 3.0
		+ sin(uv.y * 14.0 + TIME * 2.0)
	);

	detail = detail * 0.5 + 0.5;

	// Brighter edges at the top and bottom.
	float edge = pow(
		abs(uv.y * 2.0 - 1.0),
		5.0
	);

	// Subtle energy fluctuation.
	float flicker = 1.0
		- flicker_strength * (
			0.5 + 0.5 * sin(TIME * 19.0)
		);

	float energy = clamp(
		streaks * 0.65
		+ detail * 0.2
		+ edge * 0.35,
		0.0,
		1.0
	);

	vec3 color = mix(
		beam_color.rgb,
		highlight_color.rgb,
		energy
	);

	ALBEDO = color;
	EMISSION = color * emission_strength * flicker;
	ALPHA = opacity * (0.8 + energy * 0.2);
}

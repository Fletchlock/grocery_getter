shader_type spatial;
render_mode unshaded;

// Grabs Godot's built-in depth buffer to calculate where mesh edges are
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

uniform vec4 outline_color : source_color = vec4(1.0, 0.5, 0.0, 1.0); // Bright Orange
uniform float outline_thickness : hint_range(0.0, 10.0) = 5.0;        // Line width in screen pixels

void vertex() {
	// Leave vertices exactly where they are so corners NEVER explode!
}

void fragment() {
	// 1. Calculate how far away the current surface pixel is from the camera
	float depth = texture(depth_texture, SCREEN_UV).r;
	
	// 2. Measure screen pixel dimensions
	vec2 pixel_size = 1.0 / VIEWPORT_SIZE;
	
	// 3. Scan the neighboring pixels around this coordinate to find the hard edge
	float edge = 0.0;
	for (float x = -outline_thickness; x <= outline_thickness; x += 1.0) {
		for (float y = -outline_thickness; y <= outline_thickness; y += 1.0) {
			vec2 offset = vec2(x, y) * pixel_size;
			float neighbor_depth = texture(depth_texture, SCREEN_UV + offset).r;
			
			// If there's a significant jump in depth, we found an edge!
			if (abs(depth - neighbor_depth) > 0.0001) {
				edge = 1.0;
			}
		}
	}
	
	// 4. Paint the edge bright orange; otherwise, keep the original box mesh visible
	if (edge > 0.0) {
		ALBEDO = outline_color.rgb;
	} else {
		discard; // This leaves the inside of the box completely untouched and normal!
	}
}

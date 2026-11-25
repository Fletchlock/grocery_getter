shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 skin_color : source_color = vec4(0.25, 0.75, 0.35, 1.0);
uniform vec4 pattern_color : source_color = vec4(0.05, 0.25, 0.10, 1.0);

uniform sampler2D pattern_texture : source_color, filter_linear_mipmap, repeat_enable;

uniform float pattern_strength : hint_range(0.0, 1.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float emission_strength : hint_range(0.0, 5.0, 0.01) = 1.0;

void fragment() {
	float mask = texture(pattern_texture, UV).r;
	float blend_amount = mask * pattern_strength;

	ALBEDO = mix(skin_color.rgb, pattern_color.rgb, blend_amount);
	ROUGHNESS = roughness;
	EMISSION = pattern_color.rgb * blend_amount * emission_strength;
}
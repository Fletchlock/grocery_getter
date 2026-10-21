shader_type spatial;

uniform sampler2D belt_texture : source_color, repeat_enable;
uniform float scroll_speed = 0.2;
uniform vec2 scroll_direction = vec2(0.0, 1.0);
uniform vec2 uv_scale = vec2(100.0, 100.0);

void fragment() {
    vec2 scrolling_uv = UV * uv_scale
        + scroll_direction * TIME * scroll_speed;

    vec4 tex = texture(belt_texture, scrolling_uv);

    ALBEDO = tex.rgb;
    ALPHA = tex.a;
}
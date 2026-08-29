shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flow_speed : hint_range(0.0, 1.0) = 0.22;
uniform float wave_strength : hint_range(0.0, 0.03) = 0.009;

void fragment() {
	vec2 uv = UV;
	float t = TIME * flow_speed;
	float w1 = sin(uv.y * 10.0 + t * 1.3);
	float w2 = cos(uv.x * 8.0 - t * 1.0);
	uv.x += w1 * wave_strength;
	uv.y += w2 * wave_strength * 0.65;
	float squeeze = 1.0 + sin(uv.y * 7.0 + t * 0.85) * wave_strength * 0.55;
	uv.x = (uv.x - 0.5) / squeeze + 0.5;
	vec4 c = texture(TEXTURE, uv) * tint;
	COLOR = c;
}

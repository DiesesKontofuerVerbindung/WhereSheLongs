shader_type canvas_item;

uniform vec3 key_color : source_color = vec3(0.31, 1.0, 0.32);
uniform float threshold : hint_range(0.0, 1.0) = 0.32;
uniform float smoothness : hint_range(0.0, 0.4) = 0.08;
uniform float green_bias : hint_range(0.0, 0.5) = 0.14;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float dist = distance(c.rgb, key_color);
	float green_dom = c.g - max(c.r, c.b);
	float key = max(
		1.0 - smoothstep(threshold, threshold + smoothness, dist),
		smoothstep(green_bias, green_bias + 0.12, green_dom)
	);
	float alpha = c.a * (1.0 - key);
	COLOR = vec4(c.rgb, alpha);
}

shader_type canvas_item;
render_mode blend_add;

uniform vec3 key_color : source_color = vec3(0.31, 1.0, 0.32);
uniform float threshold : hint_range(0.0, 1.0) = 0.32;
uniform float smoothness : hint_range(0.0, 0.4) = 0.08;
uniform vec3 glow_tint : source_color = vec3(1.0, 0.92, 0.55);
uniform float glow_strength : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float dist = distance(c.rgb, key_color);
	float green_dom = c.g - max(c.r, c.b);
	float key = max(
		1.0 - smoothstep(threshold, threshold + smoothness, dist),
		smoothstep(0.14, 0.26, green_dom)
	);
	float body = 1.0 - key;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float glow = body * (0.35 + lum * 0.65) * glow_strength;
	COLOR = vec4(glow_tint * glow, glow * 0.85);
}

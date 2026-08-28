shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform float alpha_boost : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 rgb = mix(tint.rgb * 0.35, c.rgb + tint.rgb * 0.25, clamp(lum * 3.0, 0.0, 1.0));
	float a = max(c.a, alpha_boost * (1.0 - lum));
	COLOR = vec4(rgb, a);
}

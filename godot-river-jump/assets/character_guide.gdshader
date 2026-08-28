shader_type canvas_item;

uniform float cutoff : hint_range(0.0, 0.25, 0.001) = 0.04;
uniform float blur : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	if (lum < cutoff && c.a < 0.5) {
		discard;
	}
	vec3 rgb = c.rgb + vec3(0.12, 0.1, 0.06) * (1.0 - lum);
	float alpha = max(c.a, lum);
	if (blur > 0.05) {
		rgb = mix(rgb, vec3(0.65, 0.78, 0.95), blur * 0.55);
		alpha *= 0.5 + blur * 0.35;
	}
	COLOR = vec4(rgb, alpha);
}

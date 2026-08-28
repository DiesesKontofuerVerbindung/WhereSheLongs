shader_type canvas_item;

uniform float cutoff : hint_range(0.0, 0.3, 0.001) = 0.08;
uniform float blur : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	if (lum < cutoff) {
		discard;
	}
	vec3 rgb = c.rgb;
	float alpha = c.a;
	if (blur > 0.05) {
		rgb = mix(rgb, vec3(0.55, 0.72, 0.92), blur * 0.5);
		alpha *= 0.45 + blur * 0.3;
	}
	COLOR = vec4(rgb, alpha);
}
